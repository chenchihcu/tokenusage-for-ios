import WidgetKit
import SwiftUI

// MARK: - 資料模型契約 (DTO)
struct TokenQuotaSnapshot: Codable {
    let id: String
    let name: String
    let remainingPercent: Int
    let usedPercent: Int
    let resetText: String
    let isCritical: Bool
}

struct OpenTokenUsageEntry: TimelineEntry {
    let date: Date
    let quotas: [TokenQuotaSnapshot]
    let governingName: String
    let governingRemaining: Int
    let governingReset: String
}

// MARK: - 時間線提供者 (Timeline Provider)
struct OpenTokenUsageTimelineProvider: TimelineProvider {
    private static let appGroupSuite = "group.com.chihfu.opentokenusage"
    private static let cacheKeys = [
        "opentokenusage_cached_quotas",
        "CapacitorStorage.opentokenusage_cached_quotas"
    ]

    func placeholder(in context: Context) -> OpenTokenUsageEntry {
        OpenTokenUsageEntry(
            date: Date(),
            quotas: defaultMockQuotas(),
            governingName: "Cursor",
            governingRemaining: 0,
            governingReset: "2d 9h"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (OpenTokenUsageEntry) -> Void) {
        completion(loadSharedEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OpenTokenUsageEntry>) -> Void) {
        let entry = loadSharedEntry()
        // 每 15 分鐘自適應重新評估時間線
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadSharedEntry() -> OpenTokenUsageEntry {
        let defaults = UserDefaults(suiteName: Self.appGroupSuite)
        let jsonStr = Self.cacheKeys.lazy.compactMap { defaults?.string(forKey: $0) }.first
        if let jsonStr = jsonStr,
           let data = jsonStr.data(using: .utf8),
           let rawItems = try? JSONDecoder().decode([RawQuotaItem].self, from: data),
           !rawItems.isEmpty {
            let mapped = rawItems.map { item in
                let remaining = max(0, min(100, item.resolvedRemainingPercent))
                return TokenQuotaSnapshot(
                    id: item.resolvedId,
                    name: item.name,
                    remainingPercent: remaining,
                    usedPercent: 100 - remaining,
                    resetText: item.resolvedResetTime,
                    isCritical: remaining <= 5
                )
            }
            let minItem = mapped.min(by: { $0.remainingPercent < $1.remainingPercent }) ?? mapped[0]
            return OpenTokenUsageEntry(
                date: Date(),
                quotas: mapped,
                governingName: minItem.name,
                governingRemaining: minItem.remainingPercent,
                governingReset: minItem.resetText
            )
        }
        return placeholder(in: .init())
    }

    private func defaultMockQuotas() -> [TokenQuotaSnapshot] {
        return [
            TokenQuotaSnapshot(id: "cursor", name: "Cursor", remainingPercent: 0, usedPercent: 100, resetText: "3d 4h", isCritical: true),
            TokenQuotaSnapshot(id: "codex", name: "Codex", remainingPercent: 0, usedPercent: 100, resetText: "4d 1h", isCritical: true),
            TokenQuotaSnapshot(id: "antigravity", name: "Antigravity", remainingPercent: 31, usedPercent: 69, resetText: "2d 9h", isCritical: false),
            TokenQuotaSnapshot(id: "claude", name: "Claude", remainingPercent: 2, usedPercent: 98, resetText: "2d 5h", isCritical: true),
            TokenQuotaSnapshot(id: "grok", name: "Grok", remainingPercent: 0, usedPercent: 100, resetText: "3d 4h", isCritical: true)
        ]
    }
}

/// 相容 ProviderQuotaWithPools (snake_case) 與精簡快取格式 (camelCase)
private struct RawQuotaItem: Codable {
    let id: String?
    let provider_id: String?
    let name: String
    let remainingPercent: Int?
    let remaining_percent: Int?
    let resetTime: String?
    let reset_time: String?

    var resolvedId: String {
        provider_id ?? id ?? name.lowercased()
    }

    var resolvedRemainingPercent: Int {
        remaining_percent ?? remainingPercent ?? 0
    }

    var resolvedResetTime: String {
        let raw = reset_time ?? resetTime
        if let raw = raw, !raw.isEmpty {
            return raw
        }
        return "週期重置"
    }
}

private let widgetObsidianBg = Color(red: 0.01, green: 0.02, blue: 0.09)

private struct WidgetBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                widgetObsidianBg
            }
        } else {
            content.background(widgetObsidianBg)
        }
    }
}

// MARK: - 小工具視圖階層 (Widget Views)
struct OpenTokenUsageWidgetEntryView: View {
    var entry: OpenTokenUsageEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallGoverningWidgetView(entry: entry)
            case .systemMedium:
                MediumSpectrumWidgetView(entry: entry)
            case .systemLarge:
                LargeMatrixWidgetView(entry: entry)
            case .accessoryCircular:
                CircularGaugeWidgetView(entry: entry)
            case .accessoryRectangular:
                RectangularSummaryWidgetView(entry: entry)
            default:
                SmallGoverningWidgetView(entry: entry)
            }
        }
        .modifier(WidgetBackgroundModifier())
    }
}

// MARK: - Small 瓶頸特寫
struct SmallGoverningWidgetView: View {
    var entry: OpenTokenUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("GOVERNING")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(Color.cyan)
                Spacer()
                if entry.governingRemaining <= 5 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                }
            }

            HStack {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 5)
                        .frame(width: 54, height: 54)
                    Circle()
                        .trim(from: 0, to: CGFloat(entry.governingRemaining) / 100.0)
                        .stroke(
                            entry.governingRemaining <= 5 ? Color.red : Color.cyan,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 54, height: 54)
                    Text("\(entry.governingRemaining)%")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.governingName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(entry.governingReset)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .padding(.leading, 4)
            }
        }
        .padding(4)
    }
}

// MARK: - Medium 5 平台光譜
struct MediumSpectrumWidgetView: View {
    var entry: OpenTokenUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("5 PLATFORMS BONDED")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.cyan)
                Spacer()
                Text("Token Monitor")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
            }

            HStack(spacing: 8) {
                ForEach(entry.quotas.prefix(5), id: \.id) { q in
                    VStack(spacing: 4) {
                        Text(String(q.name.prefix(4)))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 14, height: 56)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(q.remainingPercent <= 5 ? Color.red : Color.cyan)
                                .frame(width: 14, height: CGFloat(q.remainingPercent) * 0.56)
                        }
                        Text("\(q.remainingPercent)%")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(q.remainingPercent <= 5 ? .red : .white)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(4)
    }
}

// MARK: - Large 完整矩陣
struct LargeMatrixWidgetView: View {
    var entry: OpenTokenUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MediumSpectrumWidgetView(entry: entry)
            Divider().background(Color.white.opacity(0.1))
            HStack {
                VStack(alignment: .leading) {
                    Text("LEAST REMAINING")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                    Text("\(entry.governingName): \(entry.governingRemaining)%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.cyan)
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - 鎖定畫面圓形 Gauge
struct CircularGaugeWidgetView: View {
    var entry: OpenTokenUsageEntry

    var body: some View {
        Gauge(value: Double(entry.governingRemaining), in: 0...100) {
            Text("BOTTLENECK")
        } currentValueLabel: {
            Text("\(entry.governingRemaining)%")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
        }
        .gaugeStyle(.accessoryCircular)
    }
}

// MARK: - 鎖定畫面矩形摘要
struct RectangularSummaryWidgetView: View {
    var entry: OpenTokenUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("AI Quota: \(entry.governingName)")
                .font(.system(size: 11, weight: .bold))
            Text("\(entry.governingRemaining)% left · \(entry.governingReset)")
                .font(.system(size: 10, design: .monospaced))
        }
    }
}

// MARK: - Widget 進入點
@main
struct OpenTokenUsageWidget: Widget {
    let kind: String = "OpenTokenUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OpenTokenUsageTimelineProvider()) { entry in
            OpenTokenUsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("OpenTokenUsage 額度監控")
        .description("一覽 Cursor, Codex, Antigravity, Claude, Grok 平台最新剩餘額度與瓶頸。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}
