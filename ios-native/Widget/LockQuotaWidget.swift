import SwiftUI
import WidgetKit

/// Lock Screen widgets (spec-competitive-gap-v3.1.md, FR-8…FR-14): one quota window,
/// by default the tightest one.
struct LockEntry: TimelineEntry {
    enum Content: Equatable {
        case window(QuotaWindow)
        case empty            // nothing cached yet
        case signedOut(String)
        case missingWindow
    }

    let date: Date
    let content: Content
    let savedAt: Date?
}

struct LockProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LockEntry {
        let window = QuotaWindows.tightest(SampleQuotas.items())
        return LockEntry(date: Date(), content: window.map { .window($0) } ?? .empty, savedAt: Date())
    }

    func snapshot(for configuration: LockWidgetIntent, in context: Context) async -> LockEntry {
        let real = entry(configuration, at: Date())
        if context.isPreview, real.content == .empty { return placeholder(in: context) }
        return real
    }

    func timeline(for configuration: LockWidgetIntent, in context: Context) async -> Timeline<LockEntry> {
        let savedAt = QuotaCache.load()?.savedAt
        let entries = QuotaTimeline.dates(savedAt: savedAt).map { entry(configuration, at: $0) }
        return Timeline(entries: entries, policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    static func content(ref: String?, items: [ProviderQuota], now: Date) -> LockEntry.Content {
        guard let ref else {
            return QuotaWindows.tightest(items, now: now).map { .window($0) } ?? .empty
        }
        let provider = ref.split(separator: "|").first.map(String.init) ?? ""
        guard items.contains(where: { $0.providerId == provider }) else {
            let name = ProviderQuery.known.first { $0.id == provider }?.name ?? provider
            return .signedOut(name)
        }
        return QuotaWindows.find(ref, in: items).map { .window($0) } ?? .missingWindow
    }

    private func entry(_ configuration: LockWidgetIntent, at date: Date) -> LockEntry {
        let snapshot = QuotaCache.load()
        return LockEntry(date: date,
                         content: Self.content(ref: configuration.window?.id, items: snapshot?.items ?? [], now: date),
                         savedAt: snapshot?.savedAt)
    }
}

struct LockQuotaView: View {
    let entry: LockEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch entry.content {
        case .window(let window):
            windowView(window)
                .widgetURL(URL(string: "opentokenusage://quotas"))
        case .empty:
            message("開啟 App 以更新")
        case .signedOut(let name):
            message(family == .accessoryCircular ? "未登入" : "\(name) 未登入")
                .widgetURL(URL(string: "opentokenusage://settings"))
        case .missingWindow:
            message("窗口已不存在，請重新設定")
        }
    }

    private var stale: Bool { QuotaWidgetContent.isStale(savedAt: entry.savedAt, now: entry.date) }

    @ViewBuilder
    private func windowView(_ window: QuotaWindow) -> some View {
        let remaining = Int(window.remaining.rounded())
        let code = ProviderStyle.style(for: window.providerId, name: window.providerName).code
        Group {
            switch family {
            case .accessoryCircular:
                // FR-9: gauge of remaining %, with the provider's 2-letter code.
                Gauge(value: min(max(window.remaining, 0), 100), in: 0...100) {
                    Text(code)
                } currentValueLabel: {
                    Text("\(remaining)")
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryInline:
                // FR-11.
                if let reset = window.resetDate, reset > entry.date {
                    Text("\(window.providerName) 剩 \(remaining)% · \(reset, style: .relative)")
                } else {
                    Text("\(window.providerName) 剩 \(remaining)%")
                }
            default:
                // FR-10.
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.providerName).font(.headline).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(window.shortLabel).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("剩 \(remaining)%").monospacedDigit().fontWeight(.semibold)
                    }
                    .font(.caption)
                    Gauge(value: min(max(window.remaining, 0), 100), in: 0...100) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                    if stale, let savedAt = entry.savedAt {
                        Text("\(savedAt, format: .dateTime.hour().minute()) 的資料").font(.caption2)
                    } else if let reset = window.resetDate {
                        ResetText.text(reset).font(.caption2).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .opacity(stale ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(window, now: entry.date, stale: stale))
    }

    static func spoken(_ window: QuotaWindow, now: Date, stale: Bool) -> String {
        QuotaWindows.spokenLine(window, now: now) + (stale ? "，資料超過一小時" : "")
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
    }
}

struct LockQuotaWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OpenTokenUsageLock", intent: LockWidgetIntent.self,
                               provider: LockProvider()) { entry in
            LockQuotaView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("額度窗口")
        .description("鎖定畫面上的一個額度窗口：剩餘 % 與重置時間。")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
