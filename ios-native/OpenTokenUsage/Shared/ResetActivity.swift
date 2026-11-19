import ActivityKit
import Foundation

/// 「重置倒數」 Live Activity (spec-competitive-gap-v3.1.md, FR-15…FR-22).
struct ResetCountdownAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var remaining: Double
        var resetDate: Date?
        /// When the figures were read (shown so a stale % is honest).
        var dataDate: Date
    }

    /// `providerId|poolId|tierId` (QuotaWindow.id).
    var windowRef: String
    var providerId: String
    var providerName: String
    var windowLabel: String
}

/// Starts, updates and ends the one running activity. Shared with the widget extension because
/// the Control Center control and Siri start it through an intent (FR-23).
enum ResetActivity {
    /// Shared with SettingsKey.sampleData; the extension can't see SettingsKey.
    static let sampleDataKey = "opentokenusage_sample_data"
    /// FR-20.
    static let lingerAfterReset: TimeInterval = 15 * 60
    /// `[VERIFY]` ActivityKit keeps an activity active for about 8 hours.
    static let maximumLife: TimeInterval = 8 * 3600

    enum StartError: LocalizedError, Equatable {
        case disabled, sampleData, noWindow, noResetDate

        var errorDescription: String? {
            switch self {
            case .disabled: return "即時動態已關閉，需要到 iOS「設定」開啟。"
            case .sampleData: return "示範資料開啟時無法追蹤。"
            case .noWindow: return "還沒有額度資料。"
            case .noResetDate: return "沒有重置時間"
            }
        }
    }

    static var isSampleData: Bool { UserDefaults.standard.bool(forKey: sampleDataKey) }

    static var areEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// The window the running activity follows, if any.
    static var trackedRef: String? {
        Activity<ResetCountdownAttributes>.activities.first { $0.activityState == .active }?.attributes.windowRef
    }

    static func state(for window: QuotaWindow, dataDate: Date) -> ResetCountdownAttributes.ContentState {
        .init(remaining: window.remaining, resetDate: window.resetDate, dataDate: dataDate)
    }

    /// FR-18: at most one activity; starting a new one ends the old one.
    @discardableResult
    static func start(_ window: QuotaWindow, dataDate: Date, now: Date = Date()) async throws -> String {
        guard !isSampleData else { throw StartError.sampleData }
        guard let reset = window.resetDate, reset > now else { throw StartError.noResetDate }
        guard areEnabled else { throw StartError.disabled }
        await endAll()
        let attributes = ResetCountdownAttributes(windowRef: window.id, providerId: window.providerId,
                                                  providerName: window.providerName, windowLabel: window.shortLabel)
        // Stale at the reset: the view then says 「已重置」 even if the app never runs again.
        let content = ActivityContent(state: state(for: window, dataDate: dataDate), staleDate: reset)
        let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        return activity.id
    }

    static func stop() async { await endAll() }

    private static func endAll() async {
        for activity in Activity<ResetCountdownAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// What to do with a running activity after a refresh. Pure, so it can be tested.
    enum Action: Equatable {
        case update(ResetCountdownAttributes.ContentState)
        /// End, leaving it on the Lock Screen until this date.
        case end(dismissAt: Date)
    }

    static func action(ref: String, current: ResetCountdownAttributes.ContentState,
                       items: [ProviderQuota], dataDate: Date, now: Date = Date()) -> Action {
        // FR-20: the reset it was counting down to has passed.
        if let reset = current.resetDate, reset <= now {
            return .end(dismissAt: max(now, reset.addingTimeInterval(lingerAfterReset)))
        }
        let provider = ref.split(separator: "|").first.map(String.init) ?? ""
        // Signed out (provider gone) or the window no longer exists: end now.
        guard items.contains(where: { $0.providerId == provider }),
              let window = QuotaWindows.find(ref, in: items) else {
            return .end(dismissAt: now)
        }
        // FR-19, FR-21: new % and, if it moved, the new reset date.
        return .update(state(for: window, dataDate: dataDate))
    }

    /// FR-19: called after every refresh, in the foreground or a background task.
    static func update(with items: [ProviderQuota], now: Date = Date()) async {
        // Demo figures are not your usage (FR-22): leave a running activity as it was.
        guard !isSampleData else { return }
        for activity in Activity<ResetCountdownAttributes>.activities where activity.activityState == .active {
            let current = activity.content.state
            switch action(ref: activity.attributes.windowRef, current: current, items: items,
                          dataDate: now, now: now) {
            case .update(let state):
                guard state != current else { continue }
                await activity.update(ActivityContent(state: state, staleDate: state.resetDate))
            case .end(let dismissAt):
                await activity.end(nil, dismissalPolicy: dismissAt > now ? .after(dismissAt) : .immediate)
            }
        }
    }
}
