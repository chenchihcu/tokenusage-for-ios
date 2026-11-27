import SwiftUI
import WidgetKit

/// Home Screen widget: the four agents' remaining usage and free resets, from the
/// app's last refresh. The widget itself never signs in or fetches.
struct QuotaEntry: TimelineEntry {
    let date: Date
    let items: [ProviderQuota]
    let savedAt: Date?
    /// Set when the widget is configured for one provider (FR-12).
    var providerId: String? = nil
}

/// Timeline entries for cached figures: now, and once more when they turn an hour old so the
/// widget dims them (FR-14). The app reloads every timeline after each refresh.
enum QuotaTimeline {
    static func dates(savedAt: Date?, now: Date = Date()) -> [Date] {
        var dates = [now]
        if let savedAt {
            let stale = savedAt.addingTimeInterval(QuotaWidgetContent.staleAfter)
            if stale > now { dates.append(stale) }
        }
        return dates
    }
}

struct QuotaProvider: AppIntentTimelineProvider {
    /// Shown (redacted by the system) while the widget loads: real-looking rows, not the
    /// empty state, so the gallery and a new widget never look blank.
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), items: SampleQuotas.items(), savedAt: Date())
    }

    /// The widget gallery asks for a preview: the person's own figures when the app has saved
    /// some, otherwise sample rows. A placed widget never shows sample data (see `entry()`).
    func snapshot(for configuration: HomeWidgetIntent, in context: Context) async -> QuotaEntry {
        let real = entry(configuration, at: Date())
        if context.isPreview, real.items.isEmpty {
            return QuotaEntry(date: Date(), items: SampleQuotas.items(), savedAt: Date())
        }
        return real
    }

    func timeline(for configuration: HomeWidgetIntent, in context: Context) async -> Timeline<QuotaEntry> {
        let savedAt = QuotaCache.load()?.savedAt
        let entries = QuotaTimeline.dates(savedAt: savedAt).map { entry(configuration, at: $0) }
        return Timeline(entries: entries, policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    private func entry(_ configuration: HomeWidgetIntent, at date: Date) -> QuotaEntry {
        let snapshot = QuotaCache.load()
        // QuotaWidgetContent puts them in the 額度 list's order (FR-W1).
        return QuotaEntry(date: date, items: snapshot?.items ?? [], savedAt: snapshot?.savedAt,
                          providerId: configuration.provider?.id)
    }
}

struct QuotaWidgetView: View {
    let entry: QuotaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let id = entry.providerId {
            if let item = entry.items.first(where: { $0.providerId == id }) {
                // One provider: its pools as rows, so the widget still has something per line.
                QuotaWidgetContent(items: QuotaWidgetContent.poolRows(item), savedAt: entry.savedAt,
                                   size: family == .systemSmall ? .small : .medium, now: entry.date,
                                   keepOrder: true, prefixPool: item.pools.count > 1)
            } else {
                // FR-13.
                QuotaWidgetMessage(title: ProviderQuery.known.first { $0.id == id }?.name ?? "AI 額度",
                                   message: "未登入")
                    .widgetURL(URL(string: "opentokenusage://settings"))
            }
        } else {
            QuotaWidgetContent(items: entry.items, savedAt: entry.savedAt,
                               size: family == .systemSmall ? .small : .medium, now: entry.date)
        }
    }
}

struct QuotaWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OpenTokenUsageQuota", intent: HomeWidgetIntent.self,
                               provider: QuotaProvider()) { entry in
            QuotaWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AI 額度")
        .description("Claude Code、Codex、Cursor 的剩餘額度與免費重置。可選一個服務。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// A title and one line, for 「未登入」 and similar states.
struct QuotaWidgetMessage: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
