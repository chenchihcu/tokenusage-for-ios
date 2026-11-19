import AppIntents
import Foundation
import WidgetKit

// spec-competitive-gap-v3.1.md, FR-12 and FR-23…FR-27. Intents read only the cached figures the
// app saved after its last refresh; they never sign in or fetch (FR-27).

/// A quota window someone can pick in a widget, the control or Shortcuts.
struct QuotaWindowEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "額度窗口"
    static let defaultQuery = QuotaWindowQuery()

    /// `providerId|poolId|tierId`.
    var id: String
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    init(_ window: QuotaWindow) {
        self.init(id: window.id, title: window.fullLabel)
    }
}

struct QuotaWindowQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [QuotaWindowEntity] {
        let windows = QuotaWindows.all(QuotaCache.load()?.items ?? [])
        // A window that no longer exists keeps its id, so the widget can say so (edge case in §6).
        return identifiers.map { id in
            windows.first { $0.id == id }.map(QuotaWindowEntity.init) ?? QuotaWindowEntity(id: id, title: "已不存在的窗口")
        }
    }

    func suggestedEntities() async throws -> [QuotaWindowEntity] {
        QuotaWindows.all(QuotaCache.load()?.items ?? []).map(QuotaWindowEntity.init)
    }
}

/// A provider for the Home Screen widget.
struct ProviderEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "服務"
    static let defaultQuery = ProviderQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ProviderQuery: EntityQuery {
    /// The three the phone can sign in to, whether or not signed in now.
    static let known: [ProviderEntity] = [
        ProviderEntity(id: "claude", name: "Claude Code"),
        ProviderEntity(id: "codex", name: "Codex"),
        ProviderEntity(id: "cursor", name: "Cursor"),
    ]

    func entities(for identifiers: [String]) async throws -> [ProviderEntity] {
        Self.known.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ProviderEntity] { Self.known }
}

/// Home Screen widget: all providers (default) or one provider's pools (FR-12).
struct HomeWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "AI 額度"
    static let description = IntentDescription("選一個服務，或顯示全部服務。")

    @Parameter(title: "服務")
    var provider: ProviderEntity?
}

/// Lock Screen widget: one window, by default the tightest one (FR-12).
struct LockWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "額度窗口"
    static let description = IntentDescription("選一個窗口；不選則顯示最緊的窗口。")

    @Parameter(title: "窗口")
    var window: QuotaWindowEntity?
}

/// 「追蹤下次重置」: starts the countdown Live Activity without opening the app (FR-23).
struct StartResetCountdownIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "追蹤下次重置"
    static let description = IntentDescription("在鎖定畫面顯示一個額度窗口的重置倒數。")

    @Parameter(title: "窗口")
    var window: QuotaWindowEntity?

    init() {}

    init(window: QuotaWindowEntity?) {
        self.window = window
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = QuotaCache.load()
        let items = snapshot?.items ?? []
        let chosen = window.flatMap { QuotaWindows.find($0.id, in: items) } ?? QuotaWindows.tightest(items)
        guard let chosen else {
            return .result(dialog: IntentDialog(stringLiteral: ResetActivity.StartError.noWindow.errorDescription ?? ""))
        }
        do {
            try await ResetActivity.start(chosen, dataDate: snapshot?.savedAt ?? Date())
            return .result(dialog: IntentDialog(stringLiteral: "正在追蹤 \(chosen.fullLabel) 的重置時間。"))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        }
    }
}

/// 「查詢剩餘額度」: one line per signed-in provider from the cache (FR-25).
struct CheckQuotaIntent: AppIntent {
    static let title: LocalizedStringResource = "查詢剩餘額度"
    static let description = IntentDescription("說出每個服務最緊的額度窗口與重置時間。")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let snapshot = QuotaCache.load()
        let text = QuotaWindows.answer(items: snapshot?.items ?? [], savedAt: snapshot?.savedAt)
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}
