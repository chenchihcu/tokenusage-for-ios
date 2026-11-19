import AppIntents

/// Siri and Shortcuts phrases (spec-competitive-gap-v3.1.md, FR-26). Each phrase names the app.
struct OpenTokenUsageShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckQuotaIntent(),
            phrases: [
                "用 \(.applicationName) 查額度",
                "\(.applicationName) 還剩多少額度",
                "查詢 \(.applicationName) 剩餘額度",
            ],
            shortTitle: "查詢剩餘額度",
            systemImageName: "gauge.with.dots.needle.50percent"
        )
        AppShortcut(
            intent: StartResetCountdownIntent(),
            phrases: [
                "用 \(.applicationName) 追蹤下次重置",
                "\(.applicationName) 追蹤重置",
            ],
            shortTitle: "追蹤下次重置",
            systemImageName: "timer"
        )
    }
}
