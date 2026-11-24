import SwiftUI
import UIKit
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

    func testClaudeModelLimitsAreSeparatePools() throws {
        let data = try json(#"{"five_hour":{"utilization":10,"resets_at":"2026-11-17T03:00:00Z"},"seven_day":{"utilization":40,"resets_at":"2026-11-20T00:00:00Z"},"seven_day_opus":{"utilization":100,"resets_at":"2026-11-20T00:00:00Z"},"seven_day_sonnet":{"utilization":20,"resets_at":"2026-11-20T00:00:00Z"},"seven_day_haiku_x":{"utilization":5,"resets_at":null},"extra_usage":{"is_enabled":false}}"#)
        let quota = try XCTUnwrap(DirectProvider.claude.parse(data))
        XCTAssertEqual(quota.pools.map(\.id), ["claude_all", "claude_haiku_x", "claude_opus", "claude_sonnet"])
        XCTAssertEqual(quota.pools.map(\.name), ["所有模型", "Haiku X", "Opus", "Sonnet"])
        XCTAssertEqual(quota.pools[0].effectiveRemaining, 60, accuracy: 0.001)
        XCTAssertEqual(quota.pools[2].effectiveRemaining, 0, accuracy: 0.001)
        XCTAssertEqual(quota.pools[3].effectiveRemaining, 80, accuracy: 0.001)
        // The headline is the tightest pool, so an exhausted model is never hidden.
        XCTAssertEqual(quota.remainingPercent, 0, accuracy: 0.001)
    }

    func testParsesCursorPools() throws {
        let data = try json(#"{"membershipType":"pro","billingCycleEnd":"2026-12-01T00:00:00.000Z","individualUsage":{"plan":{"totalPercentUsed":62,"autoPercentUsed":100,"apiPercentUsed":24}}}"#)
        let quota = try XCTUnwrap(DirectProvider.cursor.parse(data))
        XCTAssertEqual(quota.pools.map(\.name), ["Auto + Composer", "API 模型"])
        XCTAssertEqual(quota.pools[0].effectiveRemaining, 0, accuracy: 0.001)
        XCTAssertEqual(quota.pools[1].effectiveRemaining, 76, accuracy: 0.001)
        XCTAssertEqual(quota.remainingPercent, 0, accuracy: 0.001)
        // The combined figure is shown but does not gate either pool.
        XCTAssertEqual(quota.metrics.first?.label, "方案總用量")
        XCTAssertEqual(try XCTUnwrap(quota.metrics.first?.percentUsed), 62, accuracy: 0.001)
        XCTAssertNotNil(quota.resetDate)
    }

    func testCursorWithOnlyCombinedFigureIsOnePool() throws {
        let data = try json(#"{"membershipType":"pro","individualUsage":{"plan":{"used":1500,"limit":2000}}}"#)
        let quota = try XCTUnwrap(DirectProvider.cursor.parse(data))
        XCTAssertEqual(quota.pools.map(\.id), ["cursor_plan"])
        XCTAssertEqual(quota.remainingPercent, 25, accuracy: 0.001)
        XCTAssertTrue(quota.metrics.isEmpty)
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

    func testResetAlertsFireOnlyOnIncrease() {
        XCTAssertEqual(ResetAlerts.increases(previous: [:], current: ["codex": 1]), ["codex": 1])
        XCTAssertEqual(ResetAlerts.increases(previous: ["codex": 1], current: ["codex": 1]), [:])
        XCTAssertEqual(ResetAlerts.increases(previous: ["codex": 1], current: ["codex": 2]), ["codex": 2])
        XCTAssertEqual(ResetAlerts.increases(previous: ["claude": 2], current: ["claude": 0]), [:])
        XCTAssertEqual(ResetAlerts.increases(previous: [:], current: ["claude": 0]), [:])
    }
}

/// spec-usage-pace-charts.md, FR-P1…FR-P5.
final class PaceEstimateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400
    private let week: TimeInterval = 7 * 86_400

    private func tier(used: Double, resetIn: TimeInterval?, window: TimeInterval?) -> QuotaTier {
        let reset = resetIn.map { ISO8601DateFormatter().string(from: now.addingTimeInterval($0)) }
        return QuotaParser.tier(id: "w", label: "每週", used: used, resetsAt: reset, windowSeconds: window)
    }

    private func pace(used: Double, resetIn: TimeInterval?, window: TimeInterval?) -> PaceEstimate {
        PaceEstimate(tier: tier(used: used, resetIn: resetIn, window: window), now: now)
    }

    func testHalfWayAtFortyPercentIsOnPace() throws {
        let p = pace(used: 40, resetIn: 3.5 * day, window: week)
        XCTAssertEqual(try XCTUnwrap(p.elapsed), 50, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(p.projected), 80, accuracy: 0.001)
        XCTAssertEqual(p.status, .onPace)
        XCTAssertNil(p.runOutDate)
    }

    func testNinetyPercentProjectedIsFast() {
        XCTAssertEqual(pace(used: 45, resetIn: 3.5 * day, window: week).status, .fast)
    }

    func testFastPaceGivesRunOutBeforeReset() throws {
        let p = pace(used: 70, resetIn: 3.5 * day, window: week)
        XCTAssertEqual(p.status, .willRunOut)
        XCTAssertEqual(try XCTUnwrap(p.projected), 140, accuracy: 0.001)
        let runOut = try XCTUnwrap(p.runOutDate)
        XCTAssertEqual(runOut.timeIntervalSince(now), 1.5 * day, accuracy: 1)
        XCTAssertEqual(now.addingTimeInterval(3.5 * day).timeIntervalSince(runOut), 2 * day, accuracy: 1)
    }

    func testUsedUpIsExhaustedWithoutProjection() {
        let p = pace(used: 100, resetIn: day, window: week)
        XCTAssertEqual(p.status, .exhausted)
        XCTAssertNil(p.projected)
        XCTAssertNil(p.runOutDate)
    }

    func testJustResetIsTooEarly() {
        let p = pace(used: 3, resetIn: 5 * 3600 - 600, window: 5 * 3600)
        XCTAssertEqual(p.status, .unknown(.tooEarly))
        XCTAssertNil(p.projected)
    }

    func testUnusedIsOnPace() {
        let p = pace(used: 0, resetIn: day, window: week)
        XCTAssertEqual(p.status, .onPace)
        XCTAssertNil(p.projected)
    }

    func testMissingResetOrWindowOrStaleCannotEstimate() {
        XCTAssertEqual(pace(used: 40, resetIn: nil, window: week).status, .unknown(.noResetDate))
        XCTAssertEqual(pace(used: 40, resetIn: day, window: nil).status, .unknown(.noWindowLength))
        XCTAssertEqual(pace(used: 40, resetIn: -60, window: week).status, .unknown(.stale))
    }

    func testParsersRecordWindowLengths() throws {
        func json(_ text: String) -> Data { Data(text.utf8) }
        let codex = try XCTUnwrap(DirectProvider.codex.parse(json(#"{"rate_limit":{"primary_window":{"used_percent":27,"limit_window_seconds":18000,"reset_after_seconds":60},"secondary_window":{"used_percent":5,"limit_window_seconds":604800,"reset_after_seconds":60}}}"#)))
        XCTAssertEqual(codex.pools.flatMap(\.tiers).map(\.windowSeconds), [18_000, 604_800])

        let claude = try XCTUnwrap(DirectProvider.claude.parse(json(#"{"five_hour":{"utilization":10,"resets_at":"2026-11-17T03:00:00Z"},"seven_day_opus":{"utilization":20,"resets_at":"2026-11-20T00:00:00Z"}}"#)))
        XCTAssertEqual(claude.pools.flatMap(\.tiers).map(\.windowSeconds), [18_000, 604_800])

        let withStart = try XCTUnwrap(DirectProvider.cursor.parse(json(#"{"billingCycleStart":"2026-11-01T00:00:00.000Z","billingCycleEnd":"2026-12-01T00:00:00.000Z","individualUsage":{"plan":{"autoPercentUsed":10,"apiPercentUsed":20}}}"#)))
        let exact = try XCTUnwrap(withStart.pools.first?.tiers.first)
        XCTAssertEqual(exact.windowSeconds, 30 * 86_400)
        XCTAssertNil(exact.windowIsEstimate)

        let withoutStart = try XCTUnwrap(DirectProvider.cursor.parse(json(#"{"billingCycleEnd":"2026-12-01T00:00:00.000Z","individualUsage":{"plan":{"autoPercentUsed":10}}}"#)))
        let guessed = try XCTUnwrap(withoutStart.pools.first?.tiers.first)
        XCTAssertNotNil(guessed.windowSeconds)
        XCTAssertEqual(guessed.windowIsEstimate, true)
    }

    func testOldSnapshotTiersDecodeWithoutWindow() throws {
        let old = #"{"id":"5h","label":"5h limit","used":69,"limit":100,"remaining":31,"resetsAt":"2026-11-02T16:54:00Z","isGoverning":true}"#
        let tier = try JSONDecoder().decode(QuotaTier.self, from: Data(old.utf8))
        XCTAssertNil(tier.windowSeconds)
        XCTAssertEqual(PaceEstimate(tier: tier, now: now).status, .unknown(.stale))
    }
}

/// spec-vendor-badges-app-icon.md, FR-B1, FR-B3, FR-B6.
final class ProviderBadgeTests: XCTestCase {
    private func channels(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private func contrastWithWhite(_ hex: UInt32) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = channels(hex)
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        return 1.05 / (luminance + 0.05)
    }

    private func hue(_ hex: UInt32) -> (degrees: Double, chroma: Double) {
        let (r, g, b) = channels(hex)
        let maxC = max(r, g, b), minC = min(r, g, b), chroma = maxC - minC
        guard chroma > 0.05 else { return (0, chroma) }
        var h: Double
        if maxC == r { h = ((g - b) / chroma).truncatingRemainder(dividingBy: 6) }
        else if maxC == g { h = (b - r) / chroma + 2 }
        else { h = (r - g) / chroma + 4 }
        h *= 60
        return (h < 0 ? h + 360 : h, chroma)
    }

    func testEveryVendorHasABadge() {
        XCTAssertEqual(Set(ProviderStyle.known.keys), ["claude", "codex", "cursor", "antigravity"])
        XCTAssertEqual(Set(ProviderStyle.known.values.map(\.code)).count, 4)
        XCTAssertEqual(Set(ProviderStyle.known.values.compactMap(\.symbol)).count, 4, "symbols must differ in shape")
    }

    func testSymbolsExistOnThisSystem() {
        for (id, style) in ProviderStyle.known {
            let symbol = try? XCTUnwrap(style.symbol)
            XCTAssertNotNil(symbol.flatMap { UIImage(systemName: $0) }, "\(id): \(symbol ?? "nil")")
        }
    }

    func testWhiteSymbolsAreReadable() {
        for (id, style) in ProviderStyle.known {
            XCTAssertGreaterThanOrEqual(contrastWithWhite(style.hex), 4.5, id)
        }
    }

    func testColouredBadgesAreFarApartInHue() {
        let hues = ProviderStyle.known.values.map { hue($0.hex) }.filter { $0.chroma > 0.05 }.map(\.degrees)
        XCTAssertEqual(hues.count, 3, "Codex is the one achromatic badge")
        for (i, a) in hues.enumerated() {
            for b in hues[(i + 1)...] {
                let gap = min(abs(a - b), 360 - abs(a - b))
                XCTAssertGreaterThanOrEqual(gap, 40)
            }
        }
    }

    func testUnknownVendorGetsGreyLetters() {
        let style = ProviderStyle.style(for: "foo", name: "Foo AI")
        XCTAssertEqual(style.code, "FO")
        XCTAssertNil(style.symbol)
    }
}

/// spec-widget-alignment.md, FR-W1…FR-W6.
@MainActor
final class WidgetAlignmentTests: XCTestCase {
    func testVendorOrderMatchesTheList() {
        let ids = ["codex", "foo", "cursor", "claude", "antigravity"]
        let ordered: [String] = ProviderStyle.vendorOrdered(ids, id: { (id: String) in id })
        XCTAssertEqual(ordered, ["claude", "codex", "cursor", "antigravity", "foo"])
    }

    func testOrderIgnoresRemainingPercent() {
        let items = SampleData.items()
        let ordered: [ProviderQuota] = ProviderStyle.vendorOrdered(items, id: { (item: ProviderQuota) in item.providerId })
        XCTAssertEqual(ordered.map { $0.providerId }, ["claude", "codex", "cursor"])
    }

    func testPoolLineJoinsEveryPool() throws {
        let claude = try XCTUnwrap(SampleData.items().first { $0.providerId == "claude" })
        // Every pool, in order, with its % and the 「 · 」 separator (FR-W6). This is the text
        // VoiceOver reads on the medium widget; the styled line is built from the same parts.
        XCTAssertEqual(PoolSummary.plainLine(claude.pools), "所有模型 19% · Opus 88% · Sonnet 45%")
        XCTAssertEqual(PoolSummary.plainLine([]), "")
    }

    /// The gallery and loading placeholder use these rows, so they must never be empty.
    func testGalleryPreviewHasEveryVendorWithPools() {
        XCTAssertEqual(SampleData.items().map { $0.providerId }, SampleQuotas.items().map { $0.providerId },
                       "示範資料 and the widget gallery share one sample set")
        let items = SampleQuotas.items()
        XCTAssertEqual(items.map { $0.providerId }, ["claude", "codex", "cursor"])
        XCTAssertEqual(items.map { $0.pools.count }, [3, 1, 2])
        XCTAssertTrue(items.allSatisfy { $0.resetDate != nil })
        XCTAssertEqual(items[2].remainingPercent, 0, accuracy: 0.001)
    }

    /// Renders both sizes to PNG when TEST_RENDER_DIR is set (xcodebuild: TEST_RUNNER_TEST_RENDER_DIR),
    /// for a visual check without placing a widget on the home screen.
    func testRenderWidgetSizes() throws {
        let items = SampleQuotas.items()
        let saved = Date().addingTimeInterval(-180)
        for (size, name, width) in [(QuotaWidgetContent.Size.small, "small", 158.0),
                                    (QuotaWidgetContent.Size.medium, "medium", 338.0)] {
            for scheme in [ColorScheme.light, .dark] {
                let view = QuotaWidgetContent(items: items, savedAt: saved, size: size)
                    .padding(16)
                    .frame(width: width, height: 158)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                guard let image = renderer.uiImage else { return XCTFail("\(name) did not render") }
                XCTAssertEqual(image.size.width, width, accuracy: 1)
                if let dir = ProcessInfo.processInfo.environment["TEST_RENDER_DIR"] {
                    let url = URL(fileURLWithPath: dir).appending(path: "widget-\(name)-\(scheme == .dark ? "dark" : "light").png")
                    guard let png = image.pngData() else { return XCTFail("\(name) has no PNG data") }
                    try png.write(to: url)
                }
            }
        }
    }
}

/// Google Antigravity cannot sign in on the phone; its figures are relayed by the person's Mac.
final class AntigravityRelayTests: XCTestCase {
    /// `GET /api/quotas` after `scripts/relay-antigravity-mac.py` uploaded (its output, verbatim),
    /// next to another provider's row with missing fields.
    private let relayed = #"""
    {"success": true, "data": [{"provider_id": "grok", "name": "Grok", "plan_name": null, "total_quota": 100, "used_quota": 0, "remaining_percent": 100, "reset_time": null, "status": "active", "fetched_at": null}, {"provider_id": "antigravity", "name": "Google Antigravity", "plan_name": "Google AI Pro", "total_quota": 100.0, "used_quota": 31.3, "remaining_percent": 68.7, "reset_time": "2026-11-20T17:55:53Z", "status": "active", "metrics_json": "[{\"label\": \"來源\", \"value\": \"Mac 轉送（CodexBar）\"}]", "token_pools_json": "[{\"id\": \"antigravity_gemini\", \"name\": \"Gemini Models\", \"description\": \"Gemini 模型共用這些限制。\", \"effectiveRemaining\": 68.7, \"effectiveUsed\": 31.3, \"primaryResetTime\": \"2026-11-20T17:55:53Z\", \"isCritical\": false, \"tiers\": [{\"id\": \"5h\", \"label\": \"5 小時\", \"used\": 31.3, \"limit\": 100.0, \"remaining\": 68.7, \"resetsAt\": \"2026-11-20T17:55:53Z\", \"windowSeconds\": 18000.0, \"isGoverning\": true}, {\"id\": \"weekly\", \"label\": \"每週\", \"used\": 17.8, \"limit\": 100.0, \"remaining\": 82.2, \"resetsAt\": \"2026-11-25T01:06:22Z\", \"windowSeconds\": 604800.0, \"isGoverning\": null}]}, {\"id\": \"antigravity_3p\", \"name\": \"Claude and GPT models\", \"description\": \"Claude 與 GPT 模型共用這些限制。\", \"effectiveRemaining\": 100.0, \"effectiveUsed\": 0.0, \"primaryResetTime\": \"2026-11-20T21:25:46Z\", \"isCritical\": false, \"tiers\": [{\"id\": \"5h\", \"label\": \"5 小時\", \"used\": 0.0, \"limit\": 100.0, \"remaining\": 100.0, \"resetsAt\": \"2026-11-20T21:25:46Z\", \"windowSeconds\": 18000.0, \"isGoverning\": true}, {\"id\": \"weekly\", \"label\": \"每週\", \"used\": 0.0, \"limit\": 100.0, \"remaining\": 100.0, \"resetsAt\": \"2026-11-27T16:25:46Z\", \"windowSeconds\": 604800.0, \"isGoverning\": null}]}, {\"id\": \"antigravity_gemini_argon_wtu\", \"name\": \"Gemini 4 Argon\", \"description\": null, \"effectiveRemaining\": 100.0, \"effectiveUsed\": 0.0, \"primaryResetTime\": \"2026-11-27T16:25:46Z\", \"isCritical\": false, \"tiers\": [{\"id\": \"weekly\", \"label\": \"每週\", \"used\": 0.0, \"limit\": 100.0, \"remaining\": 100.0, \"resetsAt\": \"2026-11-27T16:25:46Z\", \"windowSeconds\": 604800.0, \"isGoverning\": true}]}]", "fetched_at": "2026-11-20T16:25:46Z"}]}
    """#

    func testRelayedAntigravityKeepsTheMacsPoolsAndDataTime() throws {
        let quota = try XCTUnwrap(DirectProvider.antigravity.parse(Data(relayed.utf8)))
        XCTAssertEqual(quota.providerId, "antigravity")
        XCTAssertEqual(quota.name, "Google Antigravity")
        XCTAssertEqual(quota.planName, "Google AI Pro")
        XCTAssertEqual(quota.pools.map(\.name), ["Gemini Models", "Claude and GPT models", "Gemini 4 Argon"])
        XCTAssertEqual(quota.pools[0].tiers.map(\.id), ["5h", "weekly"])
        XCTAssertEqual(quota.pools[0].tiers.map(\.windowSeconds), [18_000, 604_800])
        XCTAssertEqual(quota.pools[0].tiers[0].isGoverning, true)
        // Headline is the tightest pool, worked out on the phone like every other provider.
        XCTAssertEqual(quota.remainingPercent, 68.7, accuracy: 0.0001)
        XCTAssertEqual(quota.resetTime, "2026-11-20T17:55:53Z")
        // The data time is the Mac's reading, not when the phone asked.
        XCTAssertEqual(quota.fetchedDate, QuotaDate.parse("2026-11-20T16:25:46Z"))
        XCTAssertEqual(quota.metrics.map(\.label), [AntigravityRelay.sourceLabel])
        XCTAssertFalse(quota.reportsResetCredits)
    }

    func testAntigravityRowsNotFromTheRelayAreNeverShown() throws {
        // The database's own seed row (migrations/0002) has no relay marker: never shown as real figures.
        let seed = #"""
        {"success":true,"data":[{"provider_id":"antigravity","name":"Google Antigravity","plan_name":"Google AI Pro",
         "total_quota":100,"used_quota":8,"remaining_percent":92,"reset_time":"2026-10-30T23:29:29Z","status":"active",
         "metrics_json":"[{\"label\":\"Session\",\"used\":8.0,\"limit\":100.0,\"kind\":\"percent\"}]",
         "token_pools_json":"[{\"id\":\"gemini_models\",\"name\":\"Gemini Models\",\"effectiveRemaining\":31,\"effectiveUsed\":69,\"isCritical\":false,\"tiers\":[{\"id\":\"weekly\",\"label\":\"Weekly limit\",\"used\":69,\"limit\":100,\"remaining\":31}]}]",
         "fetched_at":"2026-10-30T22:57:18.6093812Z"}]}
        """#
        XCTAssertEqual(AntigravityRelay.read(Data(seed.utf8)), .nothingRelayed)
        XCTAssertNil(DirectProvider.antigravity.parse(Data(seed.utf8)))
        XCTAssertEqual(AntigravityRelay.read(Data(#"{"success":true,"data":[]}"#.utf8)), .nothingRelayed)
        // A relayed placeholder (CodexBar offline: no window length) is not a figure either.
        let placeholder = #"""
        {"success":true,"data":[{"provider_id":"antigravity","name":"Google Antigravity","plan_name":"offline",
         "total_quota":100,"used_quota":0,"remaining_percent":100,"reset_time":"","status":"active",
         "metrics_json":"[{\"label\": \"來源\", \"value\": \"Mac 轉送（CodexBar）\"}]",
         "token_pools_json":"[{\"id\":\"antigravity_offline\",\"name\":\"Offline\",\"effectiveRemaining\":100,\"effectiveUsed\":0,\"isCritical\":false,\"tiers\":[{\"id\":\"conversations\",\"label\":\"用量\",\"used\":0,\"limit\":100,\"remaining\":100}]}]",
         "fetched_at":"2026-11-24T05:54:47Z"}]}
        """#
        XCTAssertEqual(AntigravityRelay.read(Data(placeholder.utf8)), .nothingRelayed)
        XCTAssertEqual(AntigravityRelay.read(Data(#"{"error":"nope"}"#.utf8)), .unreadable)
        XCTAssertEqual(AntigravityRelay.read(Data("error code: 1042".utf8)), .unreadable)
    }

    func testRelayAddressMustBeHTTPSExceptOnThisMachine() {
        XCTAssertEqual(AntigravityRelay.normalizedBase(" https://x.workers.dev/api/quotas?a=1 "), "https://x.workers.dev")
        XCTAssertEqual(AntigravityRelay.normalizedBase("http://127.0.0.1:8787"), "http://127.0.0.1:8787")
        XCTAssertNil(AntigravityRelay.normalizedBase("http://x.workers.dev"))
        XCTAssertNil(AntigravityRelay.normalizedBase("x.workers.dev"))
        XCTAssertNil(AntigravityRelay.normalizedBase(""))
        XCTAssertEqual(DirectProvider.antigravity.request(token: "https://x.workers.dev/").url?.absoluteString,
                       "https://x.workers.dev/api/quotas")
        XCTAssertEqual(DirectProvider.antigravity.minimumInterval, 60)
        XCTAssertTrue(DirectProvider.antigravity.isRelayed)
        XCTAssertFalse(DirectProvider.allCases.filter { $0 != .antigravity }.contains(where: \.isRelayed))
    }

    func testRelayedFiguresGoStaleAfterAnHour() throws {
        let quota = try XCTUnwrap(DirectProvider.antigravity.parse(Data(relayed.utf8)))
        let data = try XCTUnwrap(quota.fetchedDate)
        XCTAssertFalse(AntigravityRelay.isStale(quota, now: data.addingTimeInterval(59 * 60)))
        XCTAssertTrue(AntigravityRelay.isStale(quota, now: data.addingTimeInterval(61 * 60)))
        XCTAssertEqual(ProviderProblem.relayStale.message(retryAt: nil), "Mac 超過 1 小時未轉送")
        XCTAssertEqual(QuotaClientError.relayEmpty.providerProblem, .relayEmpty)
    }
}
