import XCTest
@testable import OpenTokenUsage

final class QuotaModelTests: XCTestCase {
    /// Same shape as `GET /api/quotas` (see DEFAULT_REAL_QUOTAS in src/worker/index.ts).
    private let sample = #"""
    {"success":true,"data":[
      {"provider_id":"cursor","name":"Cursor","plan_name":"Premium","total_quota":100,"used_quota":100,
       "remaining_percent":0,"reset_time":"2026-11-03T12:12:52.768Z","status":"active",
       "metrics_json":"[{\"label\":\"Total usage\",\"used\":100.0,\"limit\":100.0,\"kind\":\"percent\",\"isAlert\":true},{\"label\":\"Credits\",\"value\":\"$0.00\"}]",
       "fetched_at":"2026-10-30T17:55:18.457747Z"},
      {"provider_id":"antigravity","name":"Google Antigravity","plan_name":"Google AI Pro","total_quota":100,"used_quota":69,
       "remaining_percent":31,"reset_time":"2026-11-02T16:54:00Z","status":"warning",
       "token_pools_json":"[{\"id\":\"gemini_models\",\"name\":\"Gemini Models\",\"effectiveRemaining\":31,\"effectiveUsed\":69,\"primaryResetTime\":\"2026-11-02T16:54:00Z\",\"isCritical\":false,\"tiers\":[{\"id\":\"5h\",\"label\":\"5h limit\",\"used\":69,\"limit\":100,\"remaining\":31,\"resetsAt\":\"2026-11-02T16:54:00Z\",\"isGoverning\":true}]}]",
       "fetched_at":"2026-10-30T17:55:18Z"}
    ]}
    """#

    private func decode() throws -> [ProviderQuota] {
        let envelope = try JSONDecoder().decode(QuotaEnvelope.self, from: Data(sample.utf8))
        XCTAssertTrue(envelope.success)
        return try XCTUnwrap(envelope.data)
    }

    func testDecodesProvidersPoolsAndMetrics() throws {
        let items = try decode()
        XCTAssertEqual(items.map(\.id), ["cursor", "antigravity"])

        let cursor = items[0]
        XCTAssertEqual(cursor.level, .exhausted)
        XCTAssertEqual(cursor.metrics.count, 2)
        XCTAssertEqual(cursor.metrics[0].percentUsed, 100)
        XCTAssertNil(cursor.metrics[1].percentUsed)
        XCTAssertEqual(cursor.metrics[1].value, "$0.00")
        XCTAssertTrue(cursor.pools.isEmpty)

        let antigravity = items[1]
        XCTAssertEqual(antigravity.level, .healthy)
        XCTAssertEqual(antigravity.pools.first?.tiers.first?.isGoverning, true)
    }

    func testParsesIsoDatesWithAnyFractionLength() {
        XCTAssertNotNil(QuotaDate.parse("2026-11-03T12:12:52.768Z"))
        XCTAssertNotNil(QuotaDate.parse("2026-10-30T17:55:18.457747Z"))
        XCTAssertNotNil(QuotaDate.parse("2026-10-30T17:55:18Z"))
        XCTAssertNotNil(QuotaDate.parse("2026-10-30T17:55:18.1+08:00"))
        XCTAssertNil(QuotaDate.parse(""))
        XCTAssertNil(QuotaDate.parse("not a date"))
    }

    func testAutoResetRefillsExpiredExhaustedWindows() throws {
        let items = try decode()
        let after = try XCTUnwrap(QuotaDate.parse("2026-11-05T00:00:00Z"))

        let cursor = items[0].applyingAutoReset(now: after)
        XCTAssertEqual(cursor.remainingPercent, 100)

        // 31 % left is not exhausted, so it is not refilled early.
        let antigravity = items[1].applyingAutoReset(now: after)
        XCTAssertEqual(antigravity.remainingPercent, 31)

        let before = try XCTUnwrap(QuotaDate.parse("2026-11-01T00:00:00Z"))
        XCTAssertEqual(items[0].applyingAutoReset(now: before).remainingPercent, 0)
    }

    func testLevels() {
        XCTAssertEqual(QuotaLevel(remaining: 5), .exhausted)
        XCTAssertEqual(QuotaLevel(remaining: 29), .low)
        XCTAssertEqual(QuotaLevel(remaining: 30), .healthy)
        XCTAssertLessThan(QuotaLevel.exhausted, QuotaLevel.healthy)
    }
}
