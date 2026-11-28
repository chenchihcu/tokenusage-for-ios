import XCTest
@testable import OpenTokenUsage

final class TokenUsageTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 12))!
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    override func tearDown() {
        MockTokenURLProtocol.handler = nil
        MockTokenURLProtocol.requests = []
        super.tearDown()
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockTokenURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - TokenFormat (FR-1, FR-3, Accessibility)

    func testShortCountFormattingAndBoundaries() {
        XCTAssertEqual(TokenFormat.shortCount(0), "0")
        XCTAssertEqual(TokenFormat.shortCount(850), "850")
        XCTAssertEqual(TokenFormat.shortCount(1_200), "1.2K")
        XCTAssertEqual(TokenFormat.shortCount(500_000), "500K")
        XCTAssertEqual(TokenFormat.shortCount(999_950), "1M")
        XCTAssertEqual(TokenFormat.shortCount(12_345_678), "12.3M")
        XCTAssertEqual(TokenFormat.shortCount(1_100_000_000), "1.1B")
        XCTAssertEqual(TokenFormat.shortCount(5_500_000_000), "5.5B")
    }

    func testRowSummaryAndAccessibilityWording() {
        let withCost = TokenUsageSummary(
            periodStart: "2026-11-03T00:00:00Z",
            periodEnd: "2026-12-03T00:00:00Z",
            isFallbackPeriod: false,
            totalTokens: 12_345_678,
            inputTokens: 1_000_000,
            cacheWriteTokens: nil,
            cacheReadTokens: 10_000_000,
            outputTokens: 1_345_678,
            totalCents: 410,
            models: [],
            fetchedAt: iso.string(from: now)
        )
        XCTAssertEqual(TokenFormat.rowSummary(withCost), "本期 12.3M tokens · ≈ $4.10")
        XCTAssertEqual(TokenFormat.periodText(withCost, calendar: calendar), "11/3 – 12/3")
        let spoken = TokenFormat.rowAccessibilityLabel(withCost)
        XCTAssertTrue(spoken.contains("12,345,678"), spoken)
        XCTAssertTrue(spoken.contains("4.10 美元"), spoken)
        XCTAssertFalse(spoken.contains("12.3M"), spoken)

        var noCost = withCost
        noCost.totalCents = nil
        XCTAssertEqual(TokenFormat.rowSummary(noCost), "本期 12.3M tokens")

        var partial = withCost
        partial.isPartial = true
        XCTAssertEqual(TokenFormat.rowSummary(partial), "本期 ≥ 12.3M tokens · ≈ $4.10")

        var fallback = withCost
        fallback.isFallbackPeriod = true
        XCTAssertEqual(TokenFormat.periodText(fallback, calendar: calendar), "最近 30 天")
    }

    // MARK: - Pure Parsers (FR-2, FR-8, Edge Cases)

    func testParseAggregatedSortsModelsOmitsNilTypesAndLabelsMissingModel() throws {
        let json = Data(#"""
        {
          "aggregations": [
            {"modelIntent": "gpt-5", "inputTokens": 1000000, "outputTokens": "2000000", "totalCents": 125},
            {"modelIntent": "claude-4-sonnet", "inputTokens": 4000000, "cacheReadTokens": 5000000, "totalCents": 285},
            {"modelIntent": "  ", "inputTokens": 500, "outputTokens": 250}
          ]
        }
        """#.utf8)
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 12, day: 3))!

        let summary = try XCTUnwrap(CursorTokenSource.parseAggregated(
            json, periodStart: start, periodEnd: end, isFallbackPeriod: false, now: now
        ))
        XCTAssertEqual(summary.totalTokens, 12_000_750)
        XCTAssertEqual(summary.inputTokens, 5_000_500)
        XCTAssertNil(summary.cacheWriteTokens, "Unreported category must stay nil")
        XCTAssertEqual(summary.cacheReadTokens, 5_000_000)
        XCTAssertEqual(summary.outputTokens, 2_000_250)
        XCTAssertEqual(summary.totalCents, 410)
        XCTAssertEqual(summary.models.map(\.model), ["claude-4-sonnet", "gpt-5", "其他"])
        XCTAssertEqual(summary.models.map(\.totalTokens), [9_000_000, 3_000_000, 750])
    }

    func testParseAggregatedEmptyArrayIsValidZeroNotSchemaFailure() throws {
        let json = Data(#"{"aggregations": []}"#.utf8)
        let summary = try XCTUnwrap(CursorTokenSource.parseAggregated(
            json, periodStart: nil, periodEnd: nil, isFallbackPeriod: true, now: now
        ))
        XCTAssertEqual(summary.totalTokens, 0)
        XCTAssertTrue(summary.models.isEmpty)
        XCTAssertEqual(TokenFormat.rowSummary(summary), "本期 0 tokens")
    }

    func testParseAggregatedRejectsUnrecognizedShape() {
        let json = Data(#"{"status": "ok", "unrelated": true}"#.utf8)
        XCTAssertNil(CursorTokenSource.parseAggregated(
            json, periodStart: nil, periodEnd: nil, isFallbackPeriod: true, now: now
        ))
    }

    // MARK: - Network Orchestration (Dual-Endpoint & Isolation)

    func testPrimarySuccessMakesSingleRequestWithExactCycleRange() async throws {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 12, day: 3))!
        MockTokenURLProtocol.handler = { req in
            let body = Data(#"{"aggregations":[{"modelIntent":"claude-4","inputTokens":1000,"outputTokens":500,"totalCents":5}]}"#.utf8)
            return (200, body)
        }

        let outcome = await CursorTokenSource.fetch(
            token: "user_1::jwt", cycleStart: start, cycleEnd: end, session: mockSession(), now: now
        )
        guard case .success(let summary) = outcome else { return XCTFail("Expected success, got \(outcome)") }
        XCTAssertEqual(MockTokenURLProtocol.requests.count, 1)
        XCTAssertTrue(MockTokenURLProtocol.requests[0].url?.path.hasSuffix("get-aggregated-usage-events") == true)
        let sentBody = try XCTUnwrap(MockTokenURLProtocol.bodyJSON(at: 0))
        XCTAssertEqual(sentBody["startDate"] as? String, String(Int64(start.timeIntervalSince1970 * 1000)))
        XCTAssertEqual(sentBody["endDate"] as? String, String(Int64(end.timeIntervalSince1970 * 1000)))
        XCTAssertEqual(summary.totalTokens, 1_500)
        XCTAssertFalse(summary.isFallbackPeriod)
    }

    func testFallbackPaginatesWhenPrimaryReturns404() async {
        MockTokenURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("get-aggregated-usage-events") {
                return (404, Data())
            }
            let body = MockTokenURLProtocol.decodeBody(req)
            let page = (body?["page"] as? Int) ?? 1
            if page == 1 {
                let events = (0..<100).map { _ in
                    ["model": "claude-4", "tokenUsage": ["inputTokens": 100, "outputTokens": 50, "totalCents": 0.5]] as [String: Any]
                }
                let data = try! JSONSerialization.data(withJSONObject: ["totalUsageEventsCount": 120, "usageEventsDisplay": events])
                return (200, data)
            } else {
                let events = (0..<20).map { _ in
                    ["model": "gpt-5", "tokenUsage": ["inputTokens": 200, "outputTokens": 50, "totalCents": 1.0]] as [String: Any]
                }
                let data = try! JSONSerialization.data(withJSONObject: ["totalUsageEventsCount": 120, "usageEventsDisplay": events])
                return (200, data)
            }
        }

        let outcome = await CursorTokenSource.fetch(
            token: "user_1::jwt", cycleStart: nil, cycleEnd: nil, session: mockSession(), now: now
        )
        guard case .success(let summary) = outcome else { return XCTFail("Expected success, got \(outcome)") }
        XCTAssertEqual(MockTokenURLProtocol.requests.count, 3) // 1 primary + 2 fallback pages
        XCTAssertTrue(summary.isFallbackPeriod)
        XCTAssertNil(summary.isPartial)
        XCTAssertEqual(summary.totalTokens, 100 * 150 + 20 * 250)
        XCTAssertEqual(summary.models.map(\.model), ["claude-4", "gpt-5"])
    }

    func testFallbackMarksPartialAtPageCap() async {
        MockTokenURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("get-aggregated-usage-events") == true {
                return (500, Data())
            }
            let events = (0..<100).map { _ in
                ["model": "auto", "tokenUsage": ["inputTokens": 10, "outputTokens": 5]] as [String: Any]
            }
            let data = try! JSONSerialization.data(withJSONObject: ["totalUsageEventsCount": 2500, "usageEventsDisplay": events])
            return (200, data)
        }

        let outcome = await CursorTokenSource.fetch(
            token: "user_1::jwt", cycleStart: nil, cycleEnd: nil, session: mockSession(), now: now
        )
        guard case .success(let summary) = outcome else { return XCTFail("Expected success, got \(outcome)") }
        XCTAssertEqual(MockTokenURLProtocol.requests.count, 1 + CursorTokenSource.maxPages)
        XCTAssertEqual(summary.isPartial, true)
        XCTAssertEqual(summary.totalTokens, Int64(CursorTokenSource.maxPages * 100 * 15))
    }

    func testPrimary429DoesNotCallFallback() async {
        MockTokenURLProtocol.handler = { _ in (429, Data()) }

        let outcome = await CursorTokenSource.fetch(
            token: "user_1::jwt", cycleStart: nil, cycleEnd: nil, session: mockSession(), now: now
        )
        XCTAssertEqual(outcome, .failure(.rateLimited))
        XCTAssertEqual(MockTokenURLProtocol.requests.count, 1)
    }

    func testFallbackMidPaginationErrorDoesNotReturnPartialData() async {
        MockTokenURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("get-aggregated-usage-events") == true {
                return (404, Data())
            }
            let page = (MockTokenURLProtocol.decodeBody(req)?["page"] as? Int) ?? 1
            if page == 1 {
                let events = (0..<100).map { _ in ["model": "auto", "inputTokens": 10] as [String: Any] }
                let data = try! JSONSerialization.data(withJSONObject: ["totalUsageEventsCount": 200, "usageEventsDisplay": events])
                return (200, data)
            }
            return (503, Data())
        }

        let outcome = await CursorTokenSource.fetch(
            token: "user_1::jwt", cycleStart: nil, cycleEnd: nil, session: mockSession(), now: now
        )
        XCTAssertEqual(outcome, .failure(.server(503)))
    }

    // MARK: - QuotaClient Isolation (TR-6)

    func testQuotaClientKeepsCachedTokensWhenTokenEndpointReturns403() async {
        let cached = TokenUsageSummary(
            periodStart: "2026-11-01T00:00:00Z",
            periodEnd: "2026-12-01T00:00:00Z",
            isFallbackPeriod: false,
            totalTokens: 5_200_000,
            inputTokens: 5_200_000,
            cacheWriteTokens: nil,
            cacheReadTokens: nil,
            outputTokens: nil,
            totalCents: 180,
            models: [TokenUsageModel(model: "claude-4", inputTokens: 5_200_000, totalTokens: 5_200_000, totalCents: 180)],
            fetchedAt: "2026-11-28T02:00:00Z"
        )
        var previous = SampleQuotas.items(now: now).first { $0.providerId == "cursor" }!
        previous.tokenUsage = cached

        MockTokenURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("usage-summary") == true {
                let summary = Data(#"""
                {
                  "membershipType": "pro",
                  "billingCycleStart": "2026-11-01T00:00:00Z",
                  "billingCycleEnd": "2026-12-01T00:00:00Z",
                  "individualUsage": {
                    "plan": {"autoPercentUsed": 60, "apiPercentUsed": 20, "totalPercentUsed": 40}
                  }
                }
                """#.utf8)
                return (200, summary)
            }
            return (403, Data())
        }

        let client = QuotaClient(session: mockSession())
        let outcome = await client.fetch(.cursor, token: "user_1::jwt", previous: previous)
        guard case .success(let quota, let tokenSucceeded, let tokenProblem) = outcome else {
            return XCTFail("Quota should succeed even when token endpoint returns 403")
        }
        XCTAssertEqual(quota.remainingPercent, 40)
        XCTAssertEqual(quota.tokenUsage, cached)
        XCTAssertFalse(tokenSucceeded)
        XCTAssertEqual(tokenProblem, .unauthorized(403))
        XCTAssertEqual(tokenProblem?.message, "暫時無法更新 Token 資料（HTTP 403）")
    }

    // MARK: - Backward Compatibility & Sample Data (FR-9, FR-10)

    func testLegacyQuotaAndStatusDecodeWithoutTokenFields() throws {
        let legacyQuotaJSON = Data(#"""
        {
          "provider_id": "cursor",
          "name": "Cursor",
          "plan_name": "Pro",
          "total_quota": 100,
          "used_quota": 30,
          "remaining_percent": 70,
          "reset_time": "2026-12-01T00:00:00Z",
          "status": "active",
          "fetched_at": "2026-11-28T00:00:00Z"
        }
        """#.utf8)
        let quota = try JSONDecoder().decode(ProviderQuota.self, from: legacyQuotaJSON)
        XCTAssertNil(quota.tokenUsage)

        let legacyStatusJSON = Data(#"{"lastSuccess": 0}"#.utf8)
        let status = try JSONDecoder().decode(ProviderStatus.self, from: legacyStatusJSON)
        XCTAssertNil(status.tokenProblem)
    }

    func testSampleDataProvidesTokensOnlyForCursor() {
        let items = SampleQuotas.items(now: now)
        let cursor = items.first { $0.providerId == "cursor" }
        XCTAssertNotNil(cursor?.tokenUsage)
        XCTAssertFalse(cursor?.tokenUsage?.models.isEmpty ?? true)
        XCTAssertNil(items.first { $0.providerId == "claude" }?.tokenUsage)
        XCTAssertNil(items.first { $0.providerId == "codex" }?.tokenUsage)
    }
}

private final class MockTokenURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func decodeBody(_ request: URLRequest) -> [String: Any]? {
        let data: Data?
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buf = Data()
            var chunk = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&chunk, maxLength: chunk.count)
                if n <= 0 { break }
                buf.append(chunk, count: n)
            }
            data = buf
        } else {
            data = nil
        }
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func bodyJSON(at index: Int) -> [String: Any]? {
        guard requests.indices.contains(index) else { return nil }
        return decodeBody(requests[index])
    }
}
