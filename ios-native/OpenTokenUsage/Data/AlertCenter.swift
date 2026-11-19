import Foundation
import UserNotifications

// spec-competitive-gap-v3.1.md, P2 (FR-28…FR-38): every quota notification the app sends or
// schedules, planned by pure functions and applied in one place after each refresh.

/// 勿擾時段, as minutes after local midnight (FR-34). Start == end means off.
struct QuietHours: Equatable {
    var start: Int
    var end: Int

    static let defaultStart = 23 * 60
    static let defaultEnd = 8 * 60

    private func minutes(_ date: Date, _ calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard start != end else { return false }
        let m = minutes(date, calendar)
        return start < end ? (m >= start && m < end) : (m >= start || m < end)
    }

    /// The date itself, or the end of the quiet period it falls in.
    func release(_ date: Date, calendar: Calendar = .current) -> Date {
        guard contains(date, calendar: calendar) else { return date }
        let day = calendar.startOfDay(for: date)
        var end = calendar.date(byAdding: .minute, value: self.end, to: day) ?? date
        if end <= date { end = calendar.date(byAdding: .day, value: 1, to: end) ?? date }
        return end
    }
}

/// What the person turned on in Settings › 通知.
struct AlertSettings: Equatable {
    var levelAlerts = false
    var early = false
    var limitAndReset = false
    var unusedReminders = false
    var weeklySummary = false
    var quiet: QuietHours?

    var levels: [Int] {
        guard levelAlerts else { return [] }
        return early ? QuotaAlerts.earlyLevels : QuotaAlerts.levels
    }

    var anyOn: Bool { levelAlerts || limitAndReset || unusedReminders || weeklySummary }
}

/// One notification to show now (`fireDate` nil) or later.
struct PlannedNote: Equatable {
    var id: String
    var title: String
    var body: String
    var fireDate: Date?
    var open: String
    var thread: String
    /// After this the note says something untrue; a held copy is dropped (FR-35).
    var expires: Date?
}

/// When a window was seen used up, for the weekly summary (FR-36).
/// Window key (as `QuotaAlerts.windowKey`) → time first seen at 100 %.
typealias ExhaustionLog = [String: Date]

enum AlertCenter {
    static let timingKey = "opentokenusage_alert_timing"           // "standard" | "early"
    static let limitResetKey = "opentokenusage_limit_reset_alerts"
    static let unusedKey = "opentokenusage_unused_reminders"
    static let weeklyKey = "opentokenusage_weekly_summary"
    static let quietKey = "opentokenusage_quiet_hours"
    static let quietStartKey = "opentokenusage_quiet_start"
    static let quietEndKey = "opentokenusage_quiet_end"
    static let exhaustionKey = "opentokenusage_exhaustion_log"

    /// FR-30: a reset is worth announcing only after heavy use.
    static let resetNoticeFrom = 80.0
    /// FR-32.
    static let unusedLead: TimeInterval = 12 * 3600
    static let unusedBelow = 50.0
    /// FR-35: a reset notice held longer than this is old news.
    static let resetNoticeShelfLife: TimeInterval = 2 * 3600

    static let resetPrefix = "quota-reset-"
    static let unusedPrefix = "quota-unused-"
    static let summaryID = "quota-weekly-summary"

    static func settings(_ defaults: UserDefaults = .standard) -> AlertSettings {
        var quiet: QuietHours?
        if defaults.bool(forKey: quietKey) {
            let start = defaults.object(forKey: quietStartKey) as? Int ?? QuietHours.defaultStart
            let end = defaults.object(forKey: quietEndKey) as? Int ?? QuietHours.defaultEnd
            quiet = QuietHours(start: start, end: end)
        }
        return AlertSettings(levelAlerts: defaults.bool(forKey: QuotaAlerts.enabledKey),
                             early: defaults.string(forKey: timingKey) == "early",
                             limitAndReset: defaults.bool(forKey: limitResetKey),
                             unusedReminders: defaults.bool(forKey: unusedKey),
                             weeklySummary: defaults.bool(forKey: weeklyKey),
                             quiet: quiet)
    }

    // MARK: Pure planning

    /// Everything that should be shown or pending after this refresh, and the sent state.
    static func plan(items: [ProviderQuota], sent: QuotaAlerts.Sent, settings: AlertSettings,
                     history: UsageHistory, exhausted: ExhaustionLog,
                     now: Date = Date(), calendar: Calendar = .current) -> (notes: [PlannedNote], sent: QuotaAlerts.Sent) {
        var notes: [PlannedNote] = []
        var newSent = sent

        // FR-28/FR-29 and the existing level and pace alerts.
        if settings.levelAlerts || settings.limitAndReset {
            let due = QuotaAlerts.due(items: items, sent: sent, now: now, levels: settings.levels,
                                      pace: settings.levelAlerts, limit: settings.limitAndReset)
            newSent = due.sent
            notes += due.alerts.map { alert in
                PlannedNote(id: alert.identifier, title: alert.title(), body: alert.body(now: now), fireDate: nil,
                            open: "quotas", thread: alert.providerId, expires: alert.resetDate)
            }
        }

        let windows = QuotaWindows.all(items).filter { window in
            guard let reset = window.resetDate else { return false }
            return reset > now
        }
        // FR-30/FR-31.
        if settings.limitAndReset {
            for window in windows where window.tier.used >= resetNoticeFrom {
                let reset = window.resetDate!
                notes.append(PlannedNote(
                    id: resetPrefix + window.id,
                    title: "\(window.fullLabel) 已重置，可以繼續用了",
                    body: "上次讀到已用 \(Int(window.tier.used.rounded()))%。",
                    fireDate: reset, open: "quotas", thread: window.providerId,
                    expires: reset.addingTimeInterval(resetNoticeShelfLife)))
            }
        }
        // FR-32: weekly windows only.
        if settings.unusedReminders {
            for window in windows where isWeekly(window.tier) && window.tier.used < unusedBelow {
                let reset = window.resetDate!
                let fire = reset.addingTimeInterval(-unusedLead)
                guard fire > now else { continue }
                let name = window.poolCount > 1 ? "\(window.providerName) · \(window.poolName)" : window.providerName
                notes.append(PlannedNote(
                    id: unusedPrefix + window.id,
                    title: "\(name) 每週額度還剩 \(Int(window.remaining.rounded()))%，12 小時後重置",
                    body: "依 \(now.formatted(.dateTime.month().day().hour().minute())) 更新時的用量。",
                    fireDate: fire, open: "quotas", thread: window.providerId, expires: reset))
            }
        }
        // FR-36.
        if settings.weeklySummary, let fire = nextSummaryDate(after: now, calendar: calendar) {
            notes.append(PlannedNote(
                id: summaryID, title: "上週額度摘要",
                body: weeklySummary(history: history, exhausted: exhausted, items: items, now: now, calendar: calendar),
                fireDate: fire, open: "analytics", thread: "summary", expires: nil))
        }

        // FR-34/FR-35: hold what falls in quiet hours; drop what would be untrue by then.
        if let quiet = settings.quiet {
            notes = notes.compactMap { note in
                let wanted = note.fireDate ?? now
                let released = quiet.release(wanted, calendar: calendar)
                guard released != wanted else { return note }
                if let expires = note.expires, released >= expires { return nil }
                var held = note
                held.fireDate = released
                return held
            }
        }
        return (notes, newSent)
    }

    static func isWeekly(_ tier: QuotaTier) -> Bool {
        guard let window = tier.windowSeconds else { return false }
        return window >= 6 * 86_400 && window <= 8 * 86_400
    }

    /// Next Monday 09:00 local time, strictly after `now`.
    static func nextSummaryDate(after now: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 2),
                          matchingPolicy: .nextTime)
    }

    /// Adds windows that are used up now; forgets entries older than 30 days.
    static func record(_ items: [ProviderQuota], into log: ExhaustionLog, now: Date = Date()) -> ExhaustionLog {
        var log = log.filter { now.timeIntervalSince($0.value) < 30 * 86_400 }
        for item in items {
            for pool in item.pools {
                for tier in pool.tiers where tier.used >= 100 {
                    if let reset = tier.resetDate, reset <= now { continue }
                    let key = QuotaAlerts.matchingKey(
                        QuotaAlerts.windowKey(provider: item.providerId, pool: pool.id, tier: tier),
                        resetDate: tier.resetDate, in: log)
                    if log[key] == nil { log[key] = now }
                }
            }
        }
        return log
    }

    /// 「Claude Code：用完 2 次，最忙是星期三」 per provider, over the 7 days before `now`.
    static func weeklySummary(history: UsageHistory, exhausted: ExhaustionLog, items: [ProviderQuota],
                              now: Date, calendar: Calendar = .current) -> String {
        let from = now.addingTimeInterval(-7 * 86_400)
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "zh-Hant")
        weekday.calendar = calendar
        weekday.timeZone = calendar.timeZone
        weekday.dateFormat = "EEEE"

        var names: [String: String] = [:]
        for item in items { names[item.providerId] = item.name }
        var perDay: [String: [Date: Double]] = [:]
        for day in history.days where day.day >= calendar.startOfDay(for: from) && day.day < now {
            let provider = String(day.key.split(separator: "/").first ?? "")
            names[provider] = names[provider] ?? day.providerName
            perDay[provider, default: [:]][day.day, default: 0] += day.consumed
        }
        var counts: [String: Int] = [:]
        for (key, date) in exhausted where date >= from && date < now {
            counts[String(key.split(separator: "|").first ?? ""), default: 0] += 1
        }
        let providers = ProviderStyle.vendorOrdered(Array(Set(perDay.keys).union(counts.keys)), id: { $0 })
        let lines = providers.map { provider -> String in
            let name = names[provider] ?? provider
            let count = counts[provider] ?? 0
            var line = "\(name)：" + (count > 0 ? "用完 \(count) 次" : "沒有用完")
            if let busiest = perDay[provider]?.max(by: { $0.value < $1.value }), busiest.value > 0 {
                line += "，最忙是\(weekday.string(from: busiest.key))"
            }
            return line
        }
        return lines.isEmpty ? "上週沒有用量紀錄。" : lines.joined(separator: "\n")
    }

    /// Pending requests this module owns that are not in the new plan and should go. Held
    /// immediate alerts stay until they expire or every alert that makes them is off (FR-35).
    static func stale(pending: [(id: String, expires: Date?)], planned: Set<String>,
                      settings: AlertSettings, now: Date) -> [String] {
        pending.compactMap { request in
            guard request.id.hasPrefix("quota-"), !planned.contains(request.id) else { return nil }
            let scheduled = request.id.hasPrefix(resetPrefix) || request.id.hasPrefix(unusedPrefix)
                || request.id == summaryID
            if scheduled { return request.id }
            if let expires = request.expires, expires <= now { return request.id }
            if !settings.levelAlerts && !settings.limitAndReset { return request.id }
            return nil
        }
    }

    // MARK: Effects

    /// After every refresh, and when a notification setting changes.
    static func sync(_ items: [ProviderQuota], now: Date = Date()) async {
        let defaults = UserDefaults.standard
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()

        // FR-38: demo figures never produce or keep a quota notification.
        guard !defaults.bool(forKey: SettingsKey.sampleData) else {
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("quota-") })
            return
        }

        let log = record(items, into: loadLog(), now: now)
        saveLog(log)

        let settings = settings(defaults)
        let sent = (defaults.dictionary(forKey: QuotaAlerts.sentKey) as? QuotaAlerts.Sent) ?? [:]
        let result = plan(items: items, sent: sent, settings: settings, history: UsageHistoryStore.load(),
                          exhausted: log, now: now)
        if settings.levelAlerts || settings.limitAndReset {
            defaults.set(result.sent, forKey: QuotaAlerts.sentKey)
        }

        let old = pending.map { ($0.identifier, $0.content.userInfo["expires"] as? Date) }
        let remove = stale(pending: old.map { (id: $0.0, expires: $0.1) },
                           planned: Set(result.notes.map(\.id)), settings: settings, now: now)
        center.removePendingNotificationRequests(withIdentifiers: remove)

        for note in result.notes {
            let content = UNMutableNotificationContent()
            content.title = note.title
            content.body = note.body
            content.sound = .default
            content.threadIdentifier = note.thread
            var info: [String: Any] = ["open": note.open]
            if let expires = note.expires { info["expires"] = expires }
            content.userInfo = info
            var trigger: UNNotificationTrigger?
            if let fire = note.fireDate, fire.timeIntervalSince(now) > 1 {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSince(now), repeats: false)
            }
            try? await center.add(UNNotificationRequest(identifier: note.id, content: content, trigger: trigger))
        }
    }

    /// Re-plans from the cached figures, e.g. right after a switch in Settings changes.
    static func resync() async {
        await sync(QuotaCache.load()?.items ?? [])
    }

    private static func loadLog() -> ExhaustionLog {
        (UserDefaults.standard.dictionary(forKey: exhaustionKey) as? [String: Date]) ?? [:]
    }

    private static func saveLog(_ log: ExhaustionLog) {
        UserDefaults.standard.set(log, forKey: exhaustionKey)
    }
}
