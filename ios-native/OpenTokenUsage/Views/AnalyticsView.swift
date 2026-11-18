import Charts
import SwiftUI

/// Usage per model pool (FR-34, FR-35): a trend line, a horizontal bar chart of the chosen
/// period, and a donut per pool showing how much of its current limit is used.
struct AnalyticsView: View {
    let history: UsageHistory
    /// Current readings, for the donuts.
    let items: [ProviderQuota]
    /// Changes when the 分析 tab is tapped again.
    var scrollToTopToken = 0
    @State private var period: UsageHistory.Period = .week

    var body: some View {
        NavigationStack {
            List {
                if history.days.isEmpty {
                    ContentUnavailableView(
                        "尚無用量紀錄",
                        systemImage: "chart.xyaxis.line",
                        description: Text("App 每次更新都會記下各模型的用量；累積幾天後這裡就會出現趨勢與橫條圖。")
                    )
                } else {
                    trendSection
                    barSection
                }
                if !pools.isEmpty {
                    donutSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollsToTop(on: scrollToTopToken)
            .navigationTitle("用量分析")
        }
    }

    // MARK: - Trend

    private var trendSection: some View {
        Section {
            Picker("期間", selection: $period) {
                ForEach(UsageHistory.Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            let totals = visibleTotals
            Chart(totals) { item in
                LineMark(
                    x: .value("期間", item.day, unit: period.component),
                    y: .value("用量", item.consumed)
                )
                .foregroundStyle(by: .value("模型", item.seriesName))
                PointMark(
                    x: .value("期間", item.day, unit: period.component),
                    y: .value("用量", item.consumed)
                )
                .foregroundStyle(by: .value("模型", item.seriesName))
                .symbolSize(18)
            }
            .chartForegroundStyleScale(domain: seriesNames, range: SeriesPalette.colors(count: seriesNames.count))
            .chartYAxisLabel("額度 %")
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(minHeight: 260)
            .accessibilityLabel("各模型\(period.rawValue)用量趨勢")
        } header: {
            Text("用量趨勢")
        } footer: {
            Text("單位是該模型額度最長週期的百分比（例如 Opus 每週額度、Cursor 本期 API 額度），各線單位不同，只適合各自比較。最後一點是尚未結束的本日、本週或本月。資料由這支手機在每次更新時記錄。")
        }
    }

    /// The last 8 weeks, 12 months or 30 days, so the chart stays readable.
    private var visibleTotals: [UsageDay] {
        let totals = history.totals(by: period)
        let count: Int
        switch period {
        case .day: count = 30
        case .week: count = 8
        case .month: count = 12
        }
        let starts = Array(Set(totals.map(\.day))).sorted().suffix(count)
        guard let first = starts.first else { return [] }
        return totals.filter { $0.day >= first }
    }

    /// Every pool's name in a fixed order, so each pool keeps its colour in every chart.
    private var seriesNames: [String] {
        history.seriesKeys.compactMap { key in history.days.first { $0.key == key }?.seriesName }
    }

    // MARK: - Horizontal bars

    /// Use per pool in the latest day, week or month, largest first.
    private var barSection: some View {
        let latest = history.totals(by: period)
        let start = latest.map(\.day).max()
        let rows = latest.filter { $0.day == start }.sorted { $0.consumed > $1.consumed }
        return Section {
            Chart(rows) { item in
                BarMark(
                    x: .value("用量", item.consumed),
                    y: .value("模型", item.seriesName),
                    height: .ratio(0.45)
                )
                .foregroundStyle(by: .value("模型", item.seriesName))
                .cornerRadius(4)
                // Name and value sit above their own bar, so long names never cover a neighbour.
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.seriesName).foregroundStyle(.primary)
                        Text(item.consumed, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .lineLimit(1)
                }
            }
            .chartForegroundStyleScale(domain: seriesNames, range: SeriesPalette.colors(count: seriesNames.count))
            .chartLegend(.hidden)
            .chartYAxis(.hidden)
            .chartXAxisLabel("額度 %")
            .frame(height: CGFloat(max(rows.count, 1)) * 52 + 40)
            .accessibilityLabel("\(periodTitle)各模型用量")
        } header: {
            Text("\(periodTitle)用量（橫條圖）")
        } footer: {
            Text("跟著上方的每日／每週／每月切換。每條的單位是該模型自己的額度百分比。")
        }
    }

    private var periodTitle: String {
        switch period {
        case .day: return "今日"
        case .week: return "本週"
        case .month: return "本月"
        }
    }

    // MARK: - Donuts

    private struct PoolReading: Identifiable {
        var id: String
        var title: String
        var remaining: Double
    }

    private var pools: [PoolReading] {
        items.flatMap { item in
            item.pools.map { pool in
                PoolReading(id: "\(item.providerId)/\(pool.id)",
                            title: item.pools.count > 1 ? "\(item.name) · \(pool.name)" : item.name,
                            remaining: min(max(pool.effectiveRemaining, 0), 100))
            }
        }
    }

    private var donutSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 16)], spacing: 16) {
                ForEach(pools) { pool in
                    PoolDonut(title: pool.title, remaining: pool.remaining)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("目前額度（環圈圖）")
        } footer: {
            Text("每個圈是一個模型額度目前最緊的週期：彩色是已用，灰色是剩餘。")
        }
    }
}

private struct PoolDonut: View {
    let title: String
    let remaining: Double

    var body: some View {
        let used = 100 - remaining
        let level = QuotaLevel(remaining: remaining)
        VStack(spacing: 6) {
            Chart {
                SectorMark(angle: .value("已用", used), innerRadius: .ratio(0.62), angularInset: 1)
                    .foregroundStyle(level.tint)
                SectorMark(angle: .value("剩餘", remaining), innerRadius: .ratio(0.62), angularInset: 1)
                    .foregroundStyle(Color.secondary.opacity(0.25))
            }
            .chartLegend(.hidden)
            .frame(width: 96, height: 96)
            .overlay {
                VStack(spacing: 0) {
                    Text(remaining / 100, format: .percent.precision(.fractionLength(0)))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(level.tint)
                    Text("剩餘").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(title)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，剩餘 \(Int(remaining.rounded()))%")
    }
}

/// Fixed colours for pools, in the order they were first recorded.
enum SeriesPalette {
    private static let base: [Color] = [.blue, .green, .orange, .purple, .red, .teal, .pink, .brown, .indigo, .mint, .cyan, .yellow]

    static func colors(count: Int) -> [Color] {
        (0..<max(count, 1)).map { base[$0 % base.count] }
    }
}
