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
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), items: [], savedAt: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        // The app reloads this timeline after each refresh; this is only a fallback.
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func entry() -> QuotaEntry {
        let snapshot = QuotaCache.load()
        let order = ["codex", "claude", "cursor", "antigravity"]
        let items = (snapshot?.items ?? []).sorted {
            (order.firstIndex(of: $0.providerId) ?? 9) < (order.firstIndex(of: $1.providerId) ?? 9)
        }
        return QuotaEntry(date: Date(), items: items, savedAt: snapshot?.savedAt)
    }
}

struct QuotaWidgetView: View {
    let entry: QuotaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI 額度").font(.headline)
                Text("開啟 App 以更新").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entry.items.prefix(4)) { item in
                    HStack(spacing: 6) {
                        Text(item.name).font(.caption).lineLimit(1)
                        Spacer(minLength: 4)
                        if family != .systemSmall, item.reportsResetCredits, let credits = item.resetCredits, credits > 0 {
                            Label("\(credits)", systemImage: "gift.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .accessibilityLabel("免費重置 \(credits) 次")
                        }
                        Text(item.remainingPercent / 100, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(color(item.remainingPercent))
                    }
                }
                Spacer(minLength: 0)
                if let saved = entry.savedAt {
                    Text("更新於 \(saved, style: .relative)前").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func color(_ remaining: Double) -> Color {
        remaining <= 5 ? .red : remaining < 30 ? .orange : .green
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
        .description("Codex、Claude Code、Cursor 的剩餘額度與免費重置。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
