import XCTest
@testable import OpenTokenUsage

/// docs/spec-quota-threshold-alerts.md — the pure decision logic (FR-A5…FR-A13).
final class QuotaAlertsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// A 5 h window that resets `resetIn` seconds from now.
    private func provider(used: Double, resetIn: TimeInterval = 4 * 3600,
                          window: Double? = 5 * 3600, estimate: Bool? = nil) -> ProviderQuota {
        var tier = QuotaAssembly.tier(id: "5h", label: "5 小時", used: used,
                                      resetsAt: iso.string(from: now.addingTimeInterval(resetIn)),
                                      windowSeconds: window)
        tier.windowIsEstimate = estimate
        return QuotaAssembly.make(id: "claude", name: "Claude Code", plan: "Max",
                                  pools: [.init(id: "all", name: "全部模型", tiers: [tier])],
                                  metrics: [], now: now)
    }

    private func kinds(_ alerts: [QuotaAlert]) -> [QuotaAlert.Kind] { alerts.map(\.kind) }

    func testCrossing80AlertsOnce() {
        let first = QuotaAlerts.due(items: [provider(used: 81, resetIn: 1 * 3600, window: nil)], sent: [:], now: now)
        XCTAssertEqual(kinds(first.alerts), [.level(80)])
        let again = QuotaAlerts.due(items: [provider(used: 86, resetIn: 1 * 3600, window: nil)], sent: first.sent, now: now)
        XCTAssertTrue(again.alerts.isEmpty)
    }

    func testJumpPastBothLevelsSendsOnly95() {
        let first = QuotaAlerts.due(items: [provider(used: 97, resetIn: 1800)], sent: [:], now: now)
        XCTAssertEqual(kinds(first.alerts), [.level(95)])
        let key = first.sent.keys.first!
        XCTAssertEqual(Set(first.sent[key]!), ["80", "95"])
        let again = QuotaAlerts.due(items: [provider(used: 98, resetIn: 1800)], sent: first.sent, now: now)
        XCTAssertTrue(again.alerts.isEmpty)
    }

    func testBelowLevelsAndOnPaceSendsNothing() {
        // 10 % used, 20 % of the window gone: projected 50 %.
        let result = QuotaAlerts.due(items: [provider(used: 10)], sent: [:], now: now)
        XCTAssertTrue(result.alerts.isEmpty)
        XCTAssertTrue(result.sent.isEmpty)
    }

    func testPaceAlertWhenRunningOutBeforeReset() {
        // 40 % used after 1 h of a 5 h window: projected 200 %.
        let result = QuotaAlerts.due(items: [provider(used: 40)], sent: [:], now: now)
        XCTAssertEqual(kinds(result.alerts), [.pace])
        XCTAssertNotNil(result.alerts.first?.runOutDate)
        let again = QuotaAlerts.due(items: [provider(used: 50)], sent: result.sent, now: now)
        XCTAssertTrue(again.alerts.isEmpty)
    }

    func testNoPaceAlertForEstimatedWindow() {
        let result = QuotaAlerts.due(items: [provider(used: 40, estimate: true)], sent: [:], now: now)
        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testNoPaceAlertTooEarlyInWindow() {
        // 3 % of the window gone → PaceEstimate refuses to project.
        let result = QuotaAlerts.due(items: [provider(used: 20, resetIn: 5 * 3600 * 0.97)], sent: [:], now: now)
        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testNoPaceAlertAfter95() {
        let first = QuotaAlerts.due(items: [provider(used: 96)], sent: [:], now: now)
        XCTAssertEqual(kinds(first.alerts), [.level(95)])
    }

    func testNewWindowAlertsAgain() {
        let first = QuotaAlerts.due(items: [provider(used: 81, resetIn: 1800, window: nil)], sent: [:], now: now)
        XCTAssertEqual(first.alerts.count, 1)
        // Next window: the old reset has passed, a new resetsAt arrives.
        let later = now.addingTimeInterval(3600)
        var next = provider(used: 82, resetIn: 1800 + 5 * 3600, window: nil)
        next.fetchedAt = iso.string(from: later)
        let second = QuotaAlerts.due(items: [next], sent: first.sent, now: later)
        XCTAssertEqual(kinds(second.alerts), [.level(80)])
        // The expired window was pruned.
        XCTAssertEqual(second.sent.count, 1)
    }

    func testStaleWindowIsSkipped() {
        let result = QuotaAlerts.due(items: [provider(used: 99, resetIn: -60)], sent: [:], now: now)
        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testRevisedDownDoesNotRealert() {
        let first = QuotaAlerts.due(items: [provider(used: 82, resetIn: 1800, window: nil)], sent: [:], now: now)
        let down = QuotaAlerts.due(items: [provider(used: 76, resetIn: 1800, window: nil)], sent: first.sent, now: now)
        let up = QuotaAlerts.due(items: [provider(used: 83, resetIn: 1800, window: nil)], sent: down.sent, now: now)
        XCTAssertTrue(down.alerts.isEmpty)
        XCTAssertTrue(up.alerts.isEmpty)
    }

    func testTextNamesProviderPoolAndLevel() {
        let alert = QuotaAlerts.due(items: [provider(used: 81, resetIn: 1800, window: nil)], sent: [:], now: now).alerts[0]
        XCTAssertEqual(alert.title(), "Claude Code · 全部模型 已用 80%")
        XCTAssertTrue(alert.body(now: now).hasPrefix("5 小時，"))
        XCTAssertTrue(alert.identifier.hasPrefix("quota-80-claude|all|5h|"))
    }

    func testCheckDoesNothingWithDemoData() {
        let defaults = UserDefaults.standard
        let saved = (defaults.object(forKey: QuotaAlerts.enabledKey), defaults.object(forKey: SettingsKey.sampleData),
                     defaults.object(forKey: QuotaAlerts.sentKey))
        defer {
            defaults.set(saved.0, forKey: QuotaAlerts.enabledKey)
            defaults.set(saved.1, forKey: SettingsKey.sampleData)
            defaults.set(saved.2, forKey: QuotaAlerts.sentKey)
        }
        defaults.set(true, forKey: QuotaAlerts.enabledKey)
        defaults.set(true, forKey: SettingsKey.sampleData)
        defaults.removeObject(forKey: QuotaAlerts.sentKey)
        QuotaAlerts.check([provider(used: 99, resetIn: 1800)], now: now)
        XCTAssertNil(defaults.object(forKey: QuotaAlerts.sentKey))
    }

    func testDriftingResetTimeIsSameWindow() {
        // Codex "reset_after_seconds": each refresh works the reset out from the clock.
        let first = QuotaAlerts.due(items: [provider(used: 81, resetIn: 1800, window: nil)], sent: [:], now: now)
        XCTAssertEqual(first.alerts.count, 1)
        let drifted = QuotaAlerts.due(items: [provider(used: 84, resetIn: 1801, window: nil)], sent: first.sent, now: now)
        XCTAssertTrue(drifted.alerts.isEmpty)
        XCTAssertEqual(drifted.sent.count, 1)
    }

    func testFreeResetCheckDoesNothingWithDemoData() {
        let defaults = UserDefaults.standard
        let seenKey = "opentokenusage_reset_credits_seen"
        let saved = (defaults.object(forKey: SettingsKey.sampleData), defaults.object(forKey: seenKey))
        defer {
            defaults.set(saved.0, forKey: SettingsKey.sampleData)
            defaults.set(saved.1, forKey: seenKey)
        }
        let demo = [QuotaAssembly.make(id: "codex", name: "Codex", plan: "Plus", pools: [],
                                       metrics: [QuotaMetric(label: "Resets", value: "2 available")], now: now)]
        XCTAssertEqual(demo[0].resetCredits, 2)
        defaults.set(true, forKey: SettingsKey.sampleData)
        defaults.removeObject(forKey: seenKey)
        ResetAlerts.check(demo)
        XCTAssertNil(defaults.object(forKey: seenKey))
    }
}
