import XCTest
@testable import OpenTokenUsage

final class AnalyticsCatalogTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c
    }()

    private func claude(weekly: Double, opus: Double) -> ProviderQuota {
        QuotaParser.make(.claude, plan: "Max", pools: [
            .init(id: "claude_all", name: "所有模型", description: nil, tiers: [
                QuotaParser.tier(id: "5h", label: "5 小時", used: 1, resetsAt: nil),
                QuotaParser.tier(id: "weekly", label: "每週", used: weekly, resetsAt: nil),
            ]),
            .init(id: "claude_opus", name: "Opus", description: nil,
                  tiers: [QuotaParser.tier(id: "weekly_opus", label: "每週", used: opus, resetsAt: nil)]),
        ], metrics: [], now: Date())
    }

    // MARK: - History

    func testHistoryCountsRisesAndResets() {
        var history = UsageHistory()
        let day1 = Date(timeIntervalSince1970: 1_794_800_000)
        history.record([claude(weekly: 10, opus: 5)], at: day1, calendar: calendar)   // first reading: no use yet
        XCTAssertTrue(history.days.isEmpty)
        history.record([claude(weekly: 25, opus: 5)], at: day1.addingTimeInterval(600), calendar: calendar)
        history.record([claude(weekly: 4, opus: 9)], at: day1.addingTimeInterval(1200), calendar: calendar) // weekly reset
        let all = history.days.first { $0.key == "claude/claude_all" }
        XCTAssertEqual(all?.consumed ?? 0, 15 + 4, accuracy: 0.001)
        let opus = history.days.first { $0.key == "claude/claude_opus" }
        XCTAssertEqual(opus?.consumed ?? 0, 4, accuracy: 0.001)
        XCTAssertEqual(opus?.seriesName, "Claude Code · Opus")
    }

    func testSeriesNameDropsRepeatedProvider() {
        let day = Date(timeIntervalSince1970: 1_794_800_000)
        let codex = UsageDay(day: day, key: "codex/codex_main", providerName: "Codex", poolName: "Codex 用量", consumed: 1)
        XCTAssertEqual(codex.seriesName, "Codex")
        let cursor = UsageDay(day: day, key: "cursor/api", providerName: "Cursor", poolName: "API 模型", consumed: 1)
        XCTAssertEqual(cursor.seriesName, "Cursor · API 模型")
    }

    @MainActor
    func testUnconfiguredProvidersAreThoseWithoutAToken() {
        XCTAssertEqual(QuotaStore.unconfiguredProviders(hasToken: { _ in false }).map(\.rawValue),
                       ["claude", "codex", "cursor", "antigravity"])
        XCTAssertEqual(QuotaStore.unconfiguredProviders(hasToken: { $0 == .codex }).map(\.rawValue),
                       ["claude", "cursor", "antigravity"])
    }

    func testTotalsByPeriod() {
        var history = UsageHistory()
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_794_800_000))
        history.days = [
            UsageDay(day: start, key: "codex/codex_main", providerName: "Codex", poolName: "Codex 用量", consumed: 3),
            UsageDay(day: calendar.date(byAdding: .day, value: 1, to: start)!, key: "codex/codex_main",
                     providerName: "Codex", poolName: "Codex 用量", consumed: 5),
            UsageDay(day: start, key: "claude/claude_opus", providerName: "Claude Code", poolName: "Opus", consumed: 2),
        ]
        let byMonth = history.totals(by: .month, calendar: calendar)
        XCTAssertEqual(byMonth.first { $0.key == "codex/codex_main" }?.consumed ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(byMonth.first { $0.key == "claude/claude_opus" }?.consumed ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(history.totals(by: .day, calendar: calendar).count, 3)
        XCTAssertEqual(history.seriesKeys, ["claude/claude_opus", "codex/codex_main"])
    }

    // MARK: - Catalog

    func testCatalogKeepsCurrentAgentModelsAndTracksChanges() throws {
        let json = #"""
        {
          "sample_spec": {"mode": "chat"},
          "claude-sonnet-4-5": {"litellm_provider": "anthropic", "mode": "chat", "input_cost_per_token": 3e-06, "output_cost_per_token": 1.5e-05, "cache_read_input_token_cost": 3e-07, "max_input_tokens": 200000},
          "claude-sonnet-4-5-20250929": {"litellm_provider": "anthropic", "mode": "chat", "input_cost_per_token": 3e-06},
          "claude-3-5-sonnet-20240620": {"litellm_provider": "anthropic", "mode": "chat", "input_cost_per_token": 3e-06},
          "claude-opus-4-1": {"litellm_provider": "anthropic", "mode": "chat", "input_cost_per_token": 1.5e-05, "deprecation_date": "2020-01-01"},
          "gpt-5-codex": {"litellm_provider": "openai", "mode": "responses", "input_cost_per_token": 1.25e-06},
          "gpt-5": {"litellm_provider": "openai", "mode": "chat", "input_cost_per_token": 1.25e-06},
          "gpt-5-2025-08-07": {"litellm_provider": "openai", "mode": "chat", "input_cost_per_token": 1.25e-06},
          "gpt-4o": {"litellm_provider": "openai", "mode": "chat", "input_cost_per_token": 2.5e-06},
          "gpt-5-audio": {"litellm_provider": "openai", "mode": "chat"},
          "gemini/gemini-2.5-pro": {"litellm_provider": "gemini", "mode": "chat", "input_cost_per_token": 1.25e-06, "deprecation_date": "2099-06-01"},
          "gemini/gemini-exp-1206": {"litellm_provider": "gemini", "mode": "chat"},
          "bedrock/claude-sonnet-4-5": {"litellm_provider": "bedrock", "mode": "chat"},
          "text-embedding-3-large": {"litellm_provider": "openai", "mode": "embedding"}
        }
        """#
        let previous = ModelCatalog(models: [
            CatalogModel(id: "claude-sonnet-4-5", vendor: .anthropic),
            CatalogModel(id: "claude-opus-4-1", vendor: .anthropic),
        ], fetchedAt: Date(timeIntervalSince1970: 0))
        let catalog = try XCTUnwrap(ModelCatalog.parse(Data(json.utf8), previous: previous))
        XCTAssertEqual(Set(catalog.models.map(\.id)), ["claude-sonnet-4-5", "gpt-5", "gpt-5-codex", "gemini-2.5-pro"])
        let sonnet = try XCTUnwrap(catalog.models.first { $0.id == "claude-sonnet-4-5" })
        XCTAssertEqual(try XCTUnwrap(sonnet.inputPerMillion), 3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(sonnet.outputPerMillion), 15, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(sonnet.cacheReadPerMillion), 0.3, accuracy: 0.0001)
        XCTAssertEqual(catalog.models.first { $0.id == "gemini-2.5-pro" }?.retires, "2099-06-01")
        XCTAssertEqual(catalog.added, ["gemini-2.5-pro", "gpt-5", "gpt-5-codex"])
        XCTAssertEqual(catalog.removed, ["claude-opus-4-1"])   // retired
    }

    func testCatalogCorrectionsDropAliasesAndFixContext() throws {
        let json = #"""
        {
          "gpt-5.6": {"litellm_provider": "openai", "mode": "chat", "input_cost_per_token": 4e-06},
          "gpt-5.6-sol": {"litellm_provider": "openai", "mode": "chat", "input_cost_per_token": 4e-06, "max_input_tokens": 922000},
          "gpt-6-luna": {"litellm_provider": "openai", "mode": "chat", "input_cost_per_token": 1e-07, "max_input_tokens": 922000},
          "gemini/gemini-3.5-flash": {"litellm_provider": "gemini", "mode": "chat", "input_cost_per_token": 1.5e-06},
          "gemini/gemini-3.6-flash": {"litellm_provider": "gemini", "mode": "chat", "input_cost_per_token": 7.5e-07}
        }
        """#
        let catalog = try XCTUnwrap(ModelCatalog.parse(Data(json.utf8), previous: ModelCatalog()))
        XCTAssertEqual(Set(catalog.models.map(\.id)), ["gpt-5.6-sol", "gpt-6-luna", "gemini-3.6-flash"])
        XCTAssertEqual(catalog.models.first { $0.id == "gpt-6-luna" }?.contextTokens, 1_050_000)
        XCTAssertEqual(catalog.models.first { $0.id == "gpt-5.6-sol" }?.contextTokens, 922_000)   // no correction
    }

    func testStoredCatalogHidesRetiredModelsAndOldChanges() {
        let fetched = ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z")!
        let catalog = ModelCatalog(models: [
            CatalogModel(id: "claude-sonnet-4-5", vendor: .anthropic, retires: "2026-11-30"),
            CatalogModel(id: "claude-sonnet-5-5", vendor: .anthropic),
        ], fetchedAt: fetched, added: ["claude-sonnet-5-5"])
        XCTAssertEqual(catalog.activeModels(now: fetched).count, 2)
        XCTAssertEqual(catalog.activeModels(now: fetched.addingTimeInterval(40 * 86_400)).map(\.id), ["claude-sonnet-5-5"])
        XCTAssertTrue(catalog.showsChanges(now: fetched.addingTimeInterval(86_400)))
        XCTAssertFalse(catalog.showsChanges(now: fetched.addingTimeInterval(20 * 86_400)))
    }

    func testCatalogSchedule() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let catalog = ModelCatalog(models: [], fetchedAt: now.addingTimeInterval(-8 * 86_400))
        XCTAssertTrue(catalog.isDue(.weekly, now: now))
        XCTAssertFalse(catalog.isDue(.monthly, now: now))
        XCTAssertFalse(catalog.isDue(.manual, now: now))
        XCTAssertTrue(ModelCatalog().isDue(.monthly, now: now))
    }
}
