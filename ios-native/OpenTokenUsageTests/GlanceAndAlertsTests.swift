import XCTest
@testable import OpenTokenUsage

/// docs/spec-competitive-gap-v3.1.md — pure logic behind P1 (windows, Siri answer, Live
/// Activity, provider status) and P2 (limit, reset, unused, quiet hours, weekly summary).
final class GlanceAndAlertsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// Wednesday 2026-11-18 12:00 UTC.
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12))!
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 18) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// One provider, one pool, one window.
    private func item(_ id: String = "claude", name: String = "Claude Code", used: Double,
                      resetIn: TimeInterval = 4 * 3600, window: Double? = 5 * 3600,
                      tierID: String = "5h", label: String = "5 小時") -> ProviderQuota {
        let tier = QuotaAssembly.tier(id: tierID, label: label, used: used,
                                      resetsAt: iso.string(from: now.addingTimeInterval(resetIn)), windowSeconds: window)
        return QuotaAssembly.make(id: id, name: name, plan: "Max",
                                  pools: [.init(id: "all", name: "全部模型", tiers: [tier])], metrics: [], now: now)
    }

    private func plan(_ items: [ProviderQuota], _ settings: AlertSettings, sent: QuotaAlerts.Sent = [:],
                      history: UsageHistory = UsageHistory(), log: ExhaustionLog = [:], at date: Date? = nil) -> [PlannedNote] {
        AlertCenter.plan(items: items, sent: sent, settings: settings, history: history, exhausted: log,
                         now: date ?? now, calendar: calendar).notes
    }

    // MARK: FR-28, FR-29

    func testLimitReplaces95FromSameRefresh() {
        let notes = plan([item(used: 100, resetIn: 1800)], AlertSettings(levelAlerts: true, limitAndReset: true))
        let immediate = notes.filter { $0.fireDate == nil }
        XCTAssertEqual(immediate.count, 1)
        XCTAssertEqual(immediate.first?.title, "Claude Code · 全部模型 已用完")
    }

    func testLimitAlertOnlyOncePerWindow() {
        let first = AlertCenter.plan(items: [item(used: 100)], sent: [:], settings: AlertSettings(limitAndReset: true),
                                     history: UsageHistory(), exhausted: [:], now: now, calendar: calendar)
        let again = AlertCenter.plan(items: [item(used: 100)], sent: first.sent, settings: AlertSettings(limitAndReset: true),
                                     history: UsageHistory(), exhausted: [:], now: now, calendar: calendar)
        XCTAssertEqual(first.notes.filter { $0.fireDate == nil }.count, 1)
        XCTAssertTrue(again.notes.filter { $0.fireDate == nil }.isEmpty)
    }

    func testStandardTimingIgnores55() {
        let notes = plan([item(used: 55, resetIn: 1800, window: nil)], AlertSettings(levelAlerts: true))
        XCTAssertTrue(notes.isEmpty)
    }

    func testEarlyTimingAlertsAt50() {
        let notes = plan([item(used: 55, resetIn: 1800, window: nil)], AlertSettings(levelAlerts: true, early: true))
        XCTAssertEqual(notes.map(\.title), ["Claude Code · 全部模型 已用 50%"])
    }

    // MARK: FR-30, FR-31

    func testResetNoticeAtResetAfterHeavyUse() {
        let notes = plan([item(used: 100, resetIn: 2 * 3600)], AlertSettings(limitAndReset: true))
        let reset = notes.first { $0.id.hasPrefix(AlertCenter.resetPrefix) }
        XCTAssertEqual(reset?.fireDate, now.addingTimeInterval(2 * 3600))
        XCTAssertEqual(reset?.title, "Claude Code · 5 小時 已重置，可以繼續用了")
        XCTAssertEqual(reset?.id, "quota-reset-claude|all|5h")
    }

    func testNoResetNoticeAfterLightUse() {
        let notes = plan([item(used: 30)], AlertSettings(limitAndReset: true))
        XCTAssertTrue(notes.isEmpty)
    }

    func testResetNoticeFollowsMovedResetWithSameID() {
        let first = plan([item(used: 90, resetIn: 2 * 3600)], AlertSettings(limitAndReset: true))
            .first { $0.id.hasPrefix(AlertCenter.resetPrefix) }
        let moved = plan([item(used: 90, resetIn: 3 * 3600)], AlertSettings(limitAndReset: true))
            .first { $0.id.hasPrefix(AlertCenter.resetPrefix) }
        XCTAssertEqual(first?.id, moved?.id)   // same id: iOS replaces the pending one
        XCTAssertEqual(moved?.fireDate, now.addingTimeInterval(3 * 3600))
    }

    // MARK: FR-32

    func testUnusedReminder12HoursBeforeWeeklyReset() {
        let weekly = item("codex", name: "Codex", used: 30, resetIn: 3 * 86_400, window: 7 * 86_400,
                          tierID: "secondary_window", label: "每週")
        let note = plan([weekly], AlertSettings(unusedReminders: true)).first
        XCTAssertEqual(note?.fireDate, now.addingTimeInterval(3 * 86_400 - 12 * 3600))
        XCTAssertEqual(note?.title, "Codex 每週額度還剩 70%，12 小時後重置")
    }

    func testNoUnusedReminderAtHalfUsed() {
        let weekly = item("codex", name: "Codex", used: 60, resetIn: 3 * 86_400, window: 7 * 86_400)
        XCTAssertTrue(plan([weekly], AlertSettings(unusedReminders: true)).isEmpty)
    }

    func testNoUnusedReminderForFiveHourWindow() {
        XCTAssertTrue(plan([item(used: 10)], AlertSettings(unusedReminders: true)).isEmpty)
    }

    // MARK: FR-34, FR-35

    func testQuietHoursAcrossMidnight() {
        let quiet = QuietHours(start: 23 * 60, end: 8 * 60)
        XCTAssertTrue(quiet.contains(at(23, 30), calendar: calendar))
        XCTAssertTrue(quiet.contains(at(7, 59), calendar: calendar))
        XCTAssertFalse(quiet.contains(at(8, 0), calendar: calendar))
        XCTAssertFalse(quiet.contains(at(12), calendar: calendar))
        XCTAssertEqual(quiet.release(at(23, 30), calendar: calendar), at(8, day: 19))
        XCTAssertEqual(quiet.release(at(1), calendar: calendar), at(8))
        XCTAssertFalse(QuietHours(start: 600, end: 600).contains(at(10), calendar: calendar))
    }

    func testAlertInQuietHoursIsHeldToTheEnd() {
        let oneAM = at(1)
        let tier = QuotaAssembly.tier(id: "5h", label: "5 小時", used: 96,
                                      resetsAt: iso.string(from: at(10)), windowSeconds: nil)
        let quota = QuotaAssembly.make(id: "claude", name: "Claude Code", plan: "Max",
                                       pools: [.init(id: "all", name: "全部模型", tiers: [tier])], metrics: [], now: oneAM)
        let quiet = QuietHours(start: 23 * 60, end: 8 * 60)
        let notes = plan([quota], AlertSettings(levelAlerts: true, quiet: quiet), at: oneAM)
        XCTAssertEqual(notes.map(\.fireDate), [at(8)])
        let off = plan([quota], AlertSettings(levelAlerts: true), at: oneAM)
        XCTAssertEqual(off.map(\.fireDate), [nil])
    }

    func testHeldAlertDroppedWhenWindowResetsFirst() {
        let oneAM = at(1)
        let tier = QuotaAssembly.tier(id: "5h", label: "5 小時", used: 96,
                                      resetsAt: iso.string(from: at(5)), windowSeconds: nil)
        let quota = QuotaAssembly.make(id: "claude", name: "Claude Code", plan: "Max",
                                       pools: [.init(id: "all", name: "全部模型", tiers: [tier])], metrics: [], now: oneAM)
        let notes = plan([quota], AlertSettings(levelAlerts: true, quiet: QuietHours(start: 23 * 60, end: 8 * 60)), at: oneAM)
        XCTAssertTrue(notes.isEmpty)
    }

    func testResetNoticeHeldOver2HoursIsDropped() {
        // Resets at 05:00 inside 23:00–08:00: 3 hours late, so not sent.
        let oneAM = at(1)
        let tier = QuotaAssembly.tier(id: "5h", label: "5 小時", used: 100,
                                      resetsAt: iso.string(from: at(5)), windowSeconds: 5 * 3600)
        let quota = QuotaAssembly.make(id: "claude", name: "Claude Code", plan: "Max",
                                       pools: [.init(id: "all", name: "全部模型", tiers: [tier])], metrics: [], now: oneAM)
        var settings = AlertSettings(limitAndReset: true, quiet: QuietHours(start: 23 * 60, end: 8 * 60))
        XCTAssertFalse(plan([quota], settings, at: oneAM).contains { $0.id.hasPrefix(AlertCenter.resetPrefix) })
        settings.quiet = QuietHours(start: 23 * 60, end: 6 * 60)   // 1 hour late: still sent, at 06:00
        let reset = plan([quota], settings, at: oneAM).first { $0.id.hasPrefix(AlertCenter.resetPrefix) }
        XCTAssertEqual(reset?.fireDate, at(6))
    }

    func testStaleCleanupKeepsHeldAlertsUntilExpiry() {
        let pending: [(id: String, expires: Date?)] = [
            (id: "quota-reset-claude|all|5h", expires: nil),           // no longer planned
            (id: "quota-95-claude|all|5h|x", expires: at(14)),         // held, still valid
            (id: "quota-80-codex|m|w|y", expires: at(11)),             // held, window already reset
            (id: "reset-codex-2", expires: nil),                       // free-reset notice: not ours
        ]
        let remove = AlertCenter.stale(pending: pending, planned: [], settings: AlertSettings(levelAlerts: true), now: now)
        XCTAssertEqual(Set(remove), ["quota-reset-claude|all|5h", "quota-80-codex|m|w|y"])
    }

    // MARK: FR-36

    func testWeeklySummaryCountsUsedUpWindows() {
        var log = AlertCenter.record([item(used: 100, resetIn: 3600)], into: [:], now: at(10, day: 16))
        log = AlertCenter.record([item(used: 100, resetIn: 6 * 3600)], into: log, now: at(9, day: 17))
        XCTAssertEqual(log.count, 2)
        // Same window seen again (Codex-style drift) is not counted twice.
        XCTAssertEqual(AlertCenter.record([item(used: 100, resetIn: 6 * 3600 + 5)], into: log, now: at(9, day: 17)).count, 2)
        let text = AlertCenter.weeklySummary(history: UsageHistory(), exhausted: log, items: [item(used: 10)],
                                             now: now, calendar: calendar)
        XCTAssertEqual(text, "Claude Code：用完 2 次")
        let note = plan([item(used: 10)], AlertSettings(weeklySummary: true), log: log).first
        XCTAssertEqual(note?.id, AlertCenter.summaryID)
        XCTAssertEqual(note?.fireDate, at(9, day: 23))   // next Monday 09:00
        XCTAssertEqual(note?.open, "analytics")
    }

    func testNoSummaryWhenOff() {
        XCTAssertTrue(plan([item(used: 10)], AlertSettings()).isEmpty)
    }

    func testSummaryWithoutDataSaysSo() {
        XCTAssertEqual(AlertCenter.weeklySummary(history: UsageHistory(), exhausted: [:], items: [], now: now,
                                                 calendar: calendar), "上週沒有用量紀錄。")
    }

    // MARK: FR-12, FR-25

    func testTightestWindowIsLowestRemaining() {
        let items = [item(used: 40), item("codex", name: "Codex", used: 90, tierID: "w", label: "每週")]
        XCTAssertEqual(QuotaWindows.tightest(items, now: now)?.id, "codex|all|w")
    }

    func testTightestSkipsWindowsAlreadyReset() {
        let items = [item(used: 40), item("codex", name: "Codex", used: 99, resetIn: -60)]
        XCTAssertEqual(QuotaWindows.tightest(items, now: now)?.providerId, "claude")
    }

    func testSiriAnswerFreshAndStale() {
        let items = [item(used: 58, resetIn: 2 * 3600 + 600)]
        let fresh = QuotaWindows.answer(items: items, savedAt: now.addingTimeInterval(-300), now: now)
        XCTAssertTrue(fresh.hasPrefix("Claude Code 5 小時剩 42%，"), fresh)
        let stale = QuotaWindows.answer(items: items, savedAt: now.addingTimeInterval(-2 * 3600), now: now)
        XCTAssertTrue(stale.hasPrefix("2小時前的資料："), stale)
        XCTAssertEqual(QuotaWindows.answer(items: [], savedAt: nil, now: now), "還沒有登入任何服務")
    }

    // MARK: FR-19…FR-21

    func testActivityUpdatesWithNewFigures() {
        let state = ResetCountdownAttributes.ContentState(remaining: 60, resetDate: now.addingTimeInterval(3600), dataDate: now)
        let action = ResetActivity.action(ref: "claude|all|5h", current: state,
                                          items: [item(used: 70, resetIn: 5400)], dataDate: now, now: now)
        XCTAssertEqual(action, .update(.init(remaining: 30, resetDate: now.addingTimeInterval(5400), dataDate: now)))
    }

    func testActivityEnds15MinutesAfterReset() {
        let reset = now.addingTimeInterval(-60)
        let state = ResetCountdownAttributes.ContentState(remaining: 0, resetDate: reset, dataDate: now)
        let action = ResetActivity.action(ref: "claude|all|5h", current: state, items: [item(used: 0)],
                                          dataDate: now, now: now)
        XCTAssertEqual(action, .end(dismissAt: reset.addingTimeInterval(15 * 60)))
    }

    func testActivityEndsWhenSignedOut() {
        let state = ResetCountdownAttributes.ContentState(remaining: 50, resetDate: now.addingTimeInterval(3600), dataDate: now)
        let action = ResetActivity.action(ref: "cursor|all|5h", current: state, items: [item(used: 10)],
                                          dataDate: now, now: now)
        XCTAssertEqual(action, .end(dismissAt: now))
    }

    // MARK: FR-4

    func testProviderProblemWording() {
        XCTAssertEqual(QuotaClientError.unauthorized(provider: "Codex").providerProblem, .signIn)
        XCTAssertEqual(ProviderProblem.signIn.message(retryAt: nil), "需要重新登入")
        XCTAssertEqual(ProviderProblem.badFormat.message(retryAt: nil), "服務回應格式改變，暫時無法讀取")
        XCTAssertEqual(ProviderProblem.rateLimited.message(retryAt: now.addingTimeInterval(170), now: now),
                       "請求過多，3 分鐘後再試")
    }
}
