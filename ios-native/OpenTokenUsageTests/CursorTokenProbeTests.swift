import XCTest
@testable import OpenTokenUsage

/// TEMPORARY with CursorTokenProbeView (spec-token-usage-codex-cursor.md §12, P1).
final class CursorTokenProbeTests: XCTestCase {
    func testSumsTokensPerModelAndHidesOtherValues() throws {
        let json = try JSONSerialization.jsonObject(with: Data(#"""
        {"totalUsageEventsCount": 3, "usageEventsDisplay": [
          {"model": "claude-x", "userEmail": "someone@example.com",
           "tokenUsage": {"inputTokens": 100, "outputTokens": 10, "cacheReadTokens": 1000, "totalCents": 1.5}},
          {"model": "claude-x", "tokenUsage": {"inputTokens": 50, "outputTokens": 5, "cacheReadTokens": 0, "totalCents": 0.5}},
          {"model": "gpt-y", "tokenUsage": {"inputTokens": "7", "outputTokens": 3}}
        ]}
        """#.utf8))
        let totals = CursorTokenProbe.perModel(json)
        XCTAssertEqual(totals["claude-x"]?["inputTokens"], 150)
        XCTAssertEqual(totals["claude-x"]?["totalCents"], 2)
        XCTAssertEqual(totals["gpt-y"]?["inputTokens"], 7)
        let shape = CursorTokenProbe.shape(json)
        XCTAssertFalse(shape.contains("someone@example.com"))
        XCTAssertTrue(shape.contains("userEmail: string"))
        XCTAssertTrue(shape.contains("inputTokens=100"))
    }
}
