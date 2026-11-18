import SwiftUI
import WidgetKit

/// Home Screen widget: the four agents' remaining usage and free resets, from the
/// app's last refresh. The widget itself never signs in or fetches.
struct QuotaEntry: TimelineEntry {
    let date: Date
    let items: [ProviderQuota]
    let savedAt: Date?
}

struct QuotaProvider: TimelineProvider {
    /// Shown (redacted by the system) while the widget loads: real-looking rows, not the
    /// empty state, so the gallery and a new widget never look blank.
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), items: SampleQuotas.items(), savedAt: Date())
    }

    /// The widget gallery asks for a preview: the person's own figures when the app has saved
    /// some, otherwise sample rows. A placed widget never shows sample data (see `entry()`).
    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        let real = entry()
        if context.isPreview, real.items.isEmpty {
            completion(QuotaEntry(date: Date(), items: SampleQuotas.items(), savedAt: Date()))
        } else {
            completion(real)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        // The app reloads this timeline after each refresh; this is only a fallback.
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func entry() -> QuotaEntry {
        let snapshot = QuotaCache.load()
        // QuotaWidgetContent puts them in the 額度 list's order (FR-W1).
        return QuotaEntry(date: Date(), items: snapshot?.items ?? [], savedAt: snapshot?.savedAt)
    }
}

struct QuotaWidgetView: View {
    let entry: QuotaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        QuotaWidgetContent(items: entry.items, savedAt: entry.savedAt,
                           size: family == .systemSmall ? .small : .medium)
    }
}

@main
struct QuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenTokenUsageQuota", provider: QuotaProvider()) { entry in
            QuotaWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AI 額度")
        .description("Claude Code、Codex、Cursor 的剩餘額度與免費重置。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
