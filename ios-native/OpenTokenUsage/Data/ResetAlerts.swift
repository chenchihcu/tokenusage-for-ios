import BackgroundTasks
import Foundation
import UserNotifications

/// Local notification when Codex or Claude Code free-reset credits appear or increase.
/// No push server: it runs whenever the app refreshes (foreground or background task).
enum ResetAlerts {
    static let enabledKey = "opentokenusage_reset_notifications"
    private static let seenKey = "opentokenusage_reset_credits_seen"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Asked only when the person turns the switch on, never at launch.
    static func requestPermission() async -> Bool {
        let granted = await askNotificationPermission()
        UserDefaults.standard.set(granted, forKey: enabledKey)
        return granted
    }

    /// Shared with `QuotaAlerts`; iOS shows the prompt only the first time.
    static func askNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorizationDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Which providers gained credits since the last count seen. Pure, so it can be tested.
    static func increases(previous: [String: Int], current: [String: Int]) -> [String: Int] {
        current.filter { provider, count in count > 0 && count > (previous[provider] ?? 0) }
    }

    /// Compares with the last seen counts, notifies once per increase, then remembers the new counts.
    static func check(_ items: [ProviderQuota]) {
        // Demo figures are not your credits: no notification, and the seen counts stay as they were.
        guard !UserDefaults.standard.bool(forKey: SettingsKey.sampleData) else { return }
        var current: [String: Int] = [:]
        for item in items where item.reportsResetCredits {
            if let credits = item.resetCredits { current[item.providerId] = credits }
        }
        let previous = (UserDefaults.standard.dictionary(forKey: seenKey) as? [String: Int]) ?? [:]
        var remembered = previous
        for (provider, count) in current { remembered[provider] = count }
        UserDefaults.standard.set(remembered, forKey: seenKey)

        guard isEnabled else { return }
        for (provider, count) in increases(previous: previous, current: current) {
            let name = items.first { $0.providerId == provider }?.name ?? provider
            let content = UNMutableNotificationContent()
            content.title = "\(name) 有免費重置可用"
            content.body = "目前有 \(count) 次免費重置。"
            content.sound = .default
            content.userInfo = ["open": "resets"]
            let request = UNNotificationRequest(identifier: "reset-\(provider)-\(count)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}

/// Opens the resets sheet when a free-reset notification is tapped.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()
    static let openResets = Notification.Name("opentokenusage.openResets")
    static let openQuotas = Notification.Name("opentokenusage.openQuotas")
    static let openAnalytics = Notification.Name("opentokenusage.openAnalytics")

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        switch response.notification.request.content.userInfo["open"] as? String {
        case "resets":
            await MainActor.run { NotificationCenter.default.post(name: Self.openResets, object: nil) }
        case "quotas":
            await MainActor.run { NotificationCenter.default.post(name: Self.openQuotas, object: nil) }
        case "analytics":
            await MainActor.run { NotificationCenter.default.post(name: Self.openAnalytics, object: nil) }
        default:
            break
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Background refresh. iOS decides when (and whether) it runs; the app only asks.
enum BackgroundRefresh {
    static let identifier = "com.chihfu.opentokenusage.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
