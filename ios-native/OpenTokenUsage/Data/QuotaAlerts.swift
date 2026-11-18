import Foundation
import UserNotifications

/// One quota warning to show (docs/spec-quota-threshold-alerts.md).
struct QuotaAlert: Equatable {
    enum Kind: Equatable {
        case level(Int)   // used % reached this level
        case pace         // current pace runs out before the reset
    }

    var providerId: String
    var providerName: String
    var poolName: String
    var tierLabel: String
    /// `providerId|poolId|tierId|resetsAt` — one quota window (FR-A10).
    var windowKey: String
    var kind: Kind
    var resetDate: Date?
    var runOutDate: Date?

    var mark: String {
        switch kind {
        case .level(let level): return String(level)
        case .pace: return QuotaAlerts.paceMark
        }
    }

    /// FR-A15: also lets iOS drop a duplicate.
    var identifier: String { "quota-\(mark)-\(windowKey)" }

    /// FR-A14.
    func title() -> String {
        switch kind {
        case .level(let level): return "\(providerName) · \(poolName) 已用 \(level)%"
        case .pace: return "\(providerName) · \(poolName) 照目前速度會用完"
        }
    }

    func body(now: Date = Date()) -> String {
        switch kind {
        case .level:
            if let reset = resetDate {
                return "\(tierLabel)，\(PaceEstimate.span(reset.timeIntervalSince(now))) 後重置。"
            }
            return "\(tierLabel)。"
        case .pace:
            guard let runOut = runOutDate else { return "\(tierLabel)。" }
            var text = "約 \(PaceEstimate.span(runOut.timeIntervalSince(now))) 後用完"
            if let reset = resetDate {
                text += "，比重置早 \(PaceEstimate.span(reset.timeIntervalSince(runOut)))"
            }
            return text + "。"
        }
    }
}

/// Local notifications when a quota window passes 80 % / 95 % or will run out before it resets.
/// Runs after every refresh, like `ResetAlerts`; there is no push server.
enum QuotaAlerts {
    static let enabledKey = "opentokenusage_quota_alerts"
    static let sentKey = "opentokenusage_quota_alerts_sent"
    /// FR-A5 levels, lowest first.
    static let levels = [80, 95]
    static let paceMark = "pace"

    /// What has been sent: window key → marks ("80", "95", "pace").
    typealias Sent = [String: [String]]

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Asked only when the person turns the switch on, never at launch (FR-A2).
    static func requestPermission() async -> Bool {
        let granted = await ResetAlerts.askNotificationPermission()
        UserDefaults.standard.set(granted, forKey: enabledKey)
        return granted
    }

    static func windowKey(provider: String, pool: String, tier: QuotaTier) -> String {
        "\(provider)|\(pool)|\(tier.id)|\(tier.resetsAt ?? "none")"
    }

    /// Codex may send only "resets in N seconds", so the reset time is worked out from the clock
    /// and drifts a little between refreshes. A saved window of the same tier whose reset is this
    /// close counts as the same window.
    static let sameWindowTolerance: TimeInterval = 10 * 60

    static func matchingKey(_ key: String, resetDate: Date?, in sent: Sent) -> String {
        guard sent[key] == nil, let resetDate else { return key }
        let prefix = key.split(separator: "|").dropLast().joined(separator: "|") + "|"
        return sent.keys.first { other in
            guard other.hasPrefix(prefix),
                  let date = QuotaDate.parse(String(other.dropFirst(prefix.count))) else { return false }
            return abs(date.timeIntervalSince(resetDate)) <= sameWindowTolerance
        } ?? key
    }

    /// Which alerts are due, and the sent state afterwards. Pure, so it can be tested.
    static func due(items: [ProviderQuota], sent: Sent, now: Date = Date()) -> (alerts: [QuotaAlert], sent: Sent) {
        // FR-A11: forget windows that have already reset.
        var sent = sent.filter { key, _ in
            guard let resets = key.split(separator: "|").last, resets != "none",
                  let date = QuotaDate.parse(String(resets)) else { return true }
            return date > now
        }
        var alerts: [QuotaAlert] = []
        for item in items {
            for pool in item.pools {
                for tier in pool.tiers {
                    // FR-A13: data from a window that has already reset says nothing about now.
                    if let reset = tier.resetDate, reset <= now { continue }
                    let key = matchingKey(windowKey(provider: item.providerId, pool: pool.id, tier: tier),
                                          resetDate: tier.resetDate, in: sent)
                    var marks = sent[key] ?? []
                    func alert(_ kind: QuotaAlert.Kind, runOut: Date? = nil) -> QuotaAlert {
                        QuotaAlert(providerId: item.providerId, providerName: item.name, poolName: pool.name,
                                   tierLabel: tier.label, windowKey: key, kind: kind,
                                   resetDate: tier.resetDate, runOutDate: runOut)
                    }

                    // FR-A5 / FR-A6: only the highest new level, and every crossed level counts as sent.
                    let crossed = levels.filter { tier.used >= Double($0) }
                    if let highest = crossed.last, !marks.contains(String(highest)) {
                        alerts.append(alert(.level(highest)))
                    }
                    for level in crossed where !marks.contains(String(level)) { marks.append(String(level)) }

                    // FR-A7…FR-A9.
                    if tier.windowIsEstimate != true,
                       !marks.contains(String(levels.last!)), !marks.contains(paceMark) {
                        let pace = PaceEstimate(tier: tier, now: now)
                        if pace.status == .willRunOut {
                            alerts.append(alert(.pace, runOut: pace.runOutDate))
                            marks.append(paceMark)
                        }
                    }
                    if !marks.isEmpty { sent[key] = marks }
                }
            }
        }
        return (alerts, sent)
    }

    /// Sends what is due and remembers it. Does nothing while off or showing demo data (FR-A12).
    static func check(_ items: [ProviderQuota], now: Date = Date()) {
        guard isEnabled, !UserDefaults.standard.bool(forKey: SettingsKey.sampleData) else { return }
        let stored = (UserDefaults.standard.dictionary(forKey: sentKey) as? Sent) ?? [:]
        let result = due(items: items, sent: stored, now: now)
        UserDefaults.standard.set(result.sent, forKey: sentKey)
        for alert in result.alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title()
            content.body = alert.body(now: now)
            content.sound = .default
            content.threadIdentifier = alert.providerId
            content.userInfo = ["open": "quotas"]
            let request = UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
