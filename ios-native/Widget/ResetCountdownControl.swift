import AppIntents
import SwiftUI
import WidgetKit

/// Control Center button: starts the countdown for the tightest window (FR-24).
struct ResetCountdownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "OpenTokenUsageResetControl", provider: TightestWindowValue()) { label in
            ControlWidgetButton(action: StartResetCountdownIntent()) {
                Label(label, systemImage: "timer")
            }
        }
        .displayName("追蹤下次重置")
        .description("在鎖定畫面顯示最緊額度窗口的重置倒數。")
    }
}

/// 「Claude Code 剩 42%」 for the tightest window, from the last refresh.
struct TightestWindowValue: ControlValueProvider {
    var previewValue: String { "追蹤下次重置" }

    func currentValue() async throws -> String {
        let items = QuotaCache.load()?.items ?? []
        guard let window = QuotaWindows.tightest(items) else { return "追蹤下次重置" }
        return "\(window.providerName) 剩 \(Int(window.remaining.rounded()))%"
    }
}
