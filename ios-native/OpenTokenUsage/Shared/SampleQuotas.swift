import Foundation

/// The one set of made-up quota rows: Settings → 示範資料 in the app (`SampleData.items`),
/// the widget gallery and the widget's loading placeholder. Never saved, never shown on a
/// placed widget as real figures.
enum SampleQuotas {
    static func items(now: Date = Date()) -> [ProviderQuota] {
        func at(_ hours: Double) -> String {
            ISO8601DateFormatter().string(from: now.addingTimeInterval(hours * 3600))
        }
        let tier = QuotaAssembly.tier
        return [
            QuotaAssembly.make(id: "claude", name: "Claude Code", plan: "訂閱方案", pools: [
                .init(id: "claude_all", name: "所有模型", description: "每個模型都計入這些限制。", tiers: [
                    tier("5h", "5 小時", 42, at(2.5), 5 * 3600),
                    tier("weekly", "每週", 81, at(60), 7 * 86_400),
                ]),
                .init(id: "claude_opus", name: "Opus", description: "Opus 另有的每週限制，同時受「所有模型」限制。",
                      tiers: [tier("weekly_opus", "每週", 12, at(60), 7 * 86_400)]),
                .init(id: "claude_sonnet", name: "Sonnet", description: "Sonnet 另有的每週限制，同時受「所有模型」限制。",
                      tiers: [tier("weekly_sonnet", "每週", 55, at(60), 7 * 86_400)]),
            ], metrics: [], now: now),
            QuotaAssembly.make(id: "codex", name: "Codex", plan: "Plus", pools: [
                .init(id: "codex_main", name: "Codex 用量", description: nil, tiers: [
                    tier("primary_window", "5 小時", 8, at(4), 5 * 3600),
                    tier("secondary_window", "每週", 35, at(120), 7 * 86_400),
                ]),
            ], metrics: [QuotaMetric(label: "Credits", value: "0")], now: now),
            QuotaAssembly.make(id: "cursor", name: "Cursor", plan: "Pro", pools: [
                .init(id: "cursor_auto", name: "Auto + Composer", description: "Auto 模式與 Composer 模型。",
                      tiers: [tier("auto", "本期", 100, at(90), 30 * 86_400)]),
                .init(id: "cursor_api", name: "API 模型", description: "手動指定的模型，例如 Claude、GPT。",
                      tiers: [tier("api", "本期", 0, at(90), 30 * 86_400)]),
            ], metrics: [QuotaMetric(label: "方案總用量", used: 62, limit: 100)], now: now),
        ]
    }
}
