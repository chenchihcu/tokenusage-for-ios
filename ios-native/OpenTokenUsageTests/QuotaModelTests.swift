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

    func testResetCreditsComeOnlyFromTheVendor() {
        let now = Date()
        let tier = QuotaParser.tier(id: "weekly", label: "每週", used: 100, resetsAt: nil)
        let with = QuotaParser.make(.codex, plan: "Plus", poolName: "Codex", tiers: [tier],
                                    metrics: [QuotaMetric(label: "Resets", value: "2 available")], now: now)
        XCTAssertEqual(with.resetCredits, 2)
        XCTAssertEqual(with.resetCreditsText, "免費重置 2 次")

        let without = QuotaParser.make(.claude, plan: "Pro", poolName: "Claude", tiers: [tier], metrics: [], now: now)
        XCTAssertNil(without.resetCredits)
        XCTAssertEqual(without.resetCreditsText, "免費重置：不提供")
        // An exhausted window whose reset time passed stays exhausted until the vendor says otherwise.
        XCTAssertEqual(without.remainingPercent, 0)
        XCTAssertFalse(QuotaParser.make(.cursor, plan: "Pro", poolName: "Cursor", tiers: [tier], metrics: [], now: now).reportsResetCredits)
    }

    func testRefreshFloorsPerProvider() {
        XCTAssertEqual(DirectProvider.claude.minimumInterval, 300)
        XCTAssertEqual(DirectProvider.codex.minimumInterval, 60)
        XCTAssertEqual(DirectProvider.cursor.minimumInterval, 60)
    }

    func testLevels() {
        XCTAssertEqual(QuotaLevel(remaining: 5), .exhausted)
        XCTAssertEqual(QuotaLevel(remaining: 29), .low)
        XCTAssertEqual(QuotaLevel(remaining: 30), .healthy)
        XCTAssertLessThan(QuotaLevel.exhausted, QuotaLevel.healthy)
    }

    // MARK: - Direct provider parsing

    private func json(_ text: String) throws -> Data { Data(text.utf8) }

    func testParsesClaudeUsage() throws {
        let data = try json(#"{"five_hour":{"utilization":42.0,"resets_at":"2026-11-17T03:00:00Z"},"seven_day":{"utilization":81,"resets_at":"2026-11-20T00:00:00Z"},"seven_day_opus":null}"#)
        let quota = try XCTUnwrap(DirectProvider.claude.parse(data))
        XCTAssertEqual(quota.providerId, "claude")
        XCTAssertEqual(quota.remainingPercent, 19, accuracy: 0.001)
        XCTAssertEqual(quota.resetTime, "2026-11-20T00:00:00Z")
        let tiers = try XCTUnwrap(quota.pools.first).tiers
        XCTAssertEqual(tiers.map(\.id), ["5h", "weekly"])
        XCTAssertEqual(tiers.first { $0.isGoverning == true }?.id, "weekly")
    }

    func testParsesCodexUsage() throws {
        let data = try json(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":27,"limit_window_seconds":18000,"reset_at":1794873600},"secondary_window":{"used_percent":100,"limit_window_seconds":604800,"reset_after_seconds":3600}},"credits":{"balance":"0"}}"#)
        let now = Date(timeIntervalSince1970: 1_794_800_000)
        let quota = try XCTUnwrap(DirectProvider.codex.parse(data, now: now))
        XCTAssertEqual(quota.planName, "Plus")
        XCTAssertEqual(quota.remainingPercent, 0)
        XCTAssertEqual(quota.level, .exhausted)
        let tiers = try XCTUnwrap(quota.pools.first).tiers
        XCTAssertEqual(tiers.map(\.label), ["5 小時", "每週"])
        XCTAssertEqual(tiers[0].resetDate, Date(timeIntervalSince1970: 1_794_873_600))
        XCTAssertEqual(tiers[1].resetDate, now.addingTimeInterval(3600))
        XCTAssertEqual(quota.metrics.first?.value, "0")
    }

    func testParsesCursorUsage() throws {
        let data = try json(#"{"membershipType":"pro","billingCycleEnd":"2026-12-01T00:00:00.000Z","individualUsage":{"plan":{"used":1500,"limit":2000,"autoPercentUsed":60.5}}}"#)
        let quota = try XCTUnwrap(DirectProvider.cursor.parse(data))
        XCTAssertEqual(quota.remainingPercent, 25, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(quota.pools.first).tiers.map(\.id), ["total", "auto"])
        XCTAssertNotNil(quota.resetDate)
    }

    func testUnrecognisedPayloadsAreRejected() throws {
        for provider in DirectProvider.allCases {
            XCTAssertNil(provider.parse(try json(#"{"error":"nope"}"#)))
            XCTAssertNil(provider.parse(try json("not json")))
        }
    }

    func testReadsChatGPTAccountFromToken() {
        let claims = #"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct-123"}}"#
        let payload = Data(claims.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(QuotaParser.chatGPTAccountID(fromJWT: "h.\(payload).s"), "acct-123")
        XCTAssertNil(QuotaParser.chatGPTAccountID(fromJWT: "opaque-token"))
    }

    func testSampleDataCoversEveryLevel() {
        let levels = Set(SampleData.items().map(\.level))
        XCTAssertEqual(levels, [.exhausted, .low, .healthy])
    }

    func testImportsLabelledTokensAndSkipsPlaceholders() {
        let text = """
        Claude Code access token:
        sk-ant-oat01-abc

        Codex access token:
        eyJhbGci.payload.sig

        Cursor WorkosCursorSessionToken:
        (not stored readably on this Mac — copy it from cursor.com)
        """
        let found = TokenImport.parse(text)
        XCTAssertEqual(found[.claude], "sk-ant-oat01-abc")
        XCTAssertEqual(found[.codex], "eyJhbGci.payload.sig")
        XCTAssertNil(found[.cursor])
        XCTAssertEqual(TokenImport.parse("WorkosCursorSessionToken=user_1%3A%3Ajwt")[.cursor], "user_1%3A%3Ajwt")
        XCTAssertTrue(TokenImport.parse("hello world").isEmpty)
    }

    func testPKCEChallengeMatchesRFC7636Example() {
        XCTAssertEqual(SignInService.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertFalse(SignInService.randomURLSafe(bytes: 32).contains("="))
    }

    func testTokenResponsesBecomeCredentials() throws {
        let fresh = try SignInService.credential(status: 200, json: ["access_token": "a", "refresh_token": "r", "expires_in": 3600], keepingRefresh: nil)
        XCTAssertEqual(fresh.refreshToken, "r")
        XCTAssertFalse(fresh.needsRenewal())
        XCTAssertTrue(fresh.needsRenewal(now: Date().addingTimeInterval(3590)))

        // A renewal that returns no new refresh token keeps the old one.
        let renewed = try SignInService.credential(status: 200, json: ["access_token": "b"], keepingRefresh: "r")
        XCTAssertEqual(renewed.refreshToken, "r")

        XCTAssertThrowsError(try SignInService.credential(status: 400, json: [:], keepingRefresh: nil))
        XCTAssertThrowsError(try SignInService.credential(status: 200, json: ["error": "x"], keepingRefresh: nil))
    }

    func testCursorCookieGetsTheUserIDFromTheToken() {
        let payload = SignInService.base64URL(Data(#"{"sub":"auth0|user_42","exp":2000000000}"#.utf8))
        let token = "h.\(payload).s"
        XCTAssertEqual(JWT.cursorUserID(of: token), "user_42")
        XCTAssertEqual(JWT.expiry(of: token), Date(timeIntervalSince1970: 2_000_000_000))
        let cookie = DirectProvider.cursor.request(token: token).value(forHTTPHeaderField: "Cookie")
        XCTAssertEqual(cookie, "WorkosCursorSessionToken=user_42%3A%3A\(token)")
        // A full cookie value pasted by hand is left alone.
        let pasted = DirectProvider.cursor.request(token: "user_1::abc").value(forHTTPHeaderField: "Cookie")
        XCTAssertEqual(pasted, "WorkosCursorSessionToken=user_1::abc")
    }
}
