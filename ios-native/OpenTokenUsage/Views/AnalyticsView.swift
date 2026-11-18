import Charts
import SwiftUI

/// Usage per model pool: a "will it run out?" pace row per quota window
/// (spec-usage-pace-charts.md), then a trend line and a horizontal bar chart of the chosen
/// period (FR-34, FR-35).
struct AnalyticsView: View {
    let history: UsageHistory
    /// Current readings, for the pace rows.
    let items: [ProviderQuota]
    /// Changes when the 分析 tab is tapped again.
    var scrollToTopToken = 0
    @State private var period: UsageHistory.Period = .week

    var body: some View {
        NavigationStack {
            // Built once per update: one clock reading, pools decoded once per provider.
            let rows = paceRows(now: Date())
            List {
                if !rows.isEmpty {
                    paceSections(rows)
                }
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

    // MARK: - Pace

    private struct PaceRow: Identifiable {
        var id: String
        var providerId: String
        var providerName: String
        var title: String
        var windowIsEstimate: Bool
        var pace: PaceEstimate
    }

    /// Every window of every provider, in the 額度 page's fixed provider order. Not sorted by status.
    private func paceRows(now: Date) -> [PaceRow] {
        items.flatMap { item in
            let pools = item.pools
            return pools.flatMap { pool in
                pool.tiers.map { tier in
                    // The section header names the provider, so the row names only pool and window.
                    let title = pools.count > 1 ? "\(pool.name) · \(tier.label)" : tier.label
                    return PaceRow(id: "\(item.providerId)/\(pool.id)/\(tier.id)",
                                   providerId: item.providerId,
                                   providerName: item.name,
                                   title: title,
                                   windowIsEstimate: tier.windowIsEstimate == true,
                                   pace: PaceEstimate(tier: tier, now: now))
                }
            }
        }
    }

    private struct PaceGroup: Identifiable {
        var id: String
        var name: String
        var rows: [PaceRow]
    }

    /// One section per provider, in the rows' (fixed provider) order.
    private func paceGroups(_ rows: [PaceRow]) -> [PaceGroup] {
        var groups: [PaceGroup] = []
        for row in rows {
            if let index = groups.firstIndex(where: { $0.id == row.providerId }) {
                groups[index].rows.append(row)
            } else {
                groups.append(PaceGroup(id: row.providerId, name: row.providerName, rows: [row]))
            }
        }
        return groups
    }

    @ViewBuilder
    private func paceSections(_ rows: [PaceRow]) -> some View {
        let groups = paceGroups(rows)
        ForEach(groups) { group in
            Section {
                ForEach(group.rows) { row in
                    PaceRowView(providerName: row.providerName, title: row.title,
                                windowIsEstimate: row.windowIsEstimate, pace: row.pace)
                }
            } header: {
                HStack(spacing: 8) {
                    ProviderBadge(id: group.id, name: group.name, base: 20)
                    Text("會不會用完 · \(group.name)")
                }
            } footer: {
                if group.id == groups.last?.id {
                    Text("長條是剩下的額度，直線是這個週期剩下的時間，和「額度」頁同一個方向。長條比直線短就是用得比時間快；長條上的白色虛線是照目前速度到重置前會用掉的部分，一路到最左邊就是重置前會用完。")
                }
            }
        }
    }
}

extension PaceEstimate.Status {
    /// Fill colour for the pace bar.
    var tint: Color {
        switch self {
        case .exhausted, .willRunOut: return .red
        case .fast: return .orange
        case .onPace: return .green
        case .unknown: return .secondary
        }
    }

    /// Colour for the status word and sentences (≥ 4.5:1, see `QuotaLevel.textTint`).
    var textTint: Color {
        switch self {
        case .exhausted, .willRunOut: return .statusRed
        case .fast: return .statusOrange
        case .onPace: return .statusGreen
        case .unknown: return .secondary
        }
    }
}

private struct PaceRowView: View {
    let providerName: String
    let title: String
    let windowIsEstimate: Bool
    let pace: PaceEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(pace.status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(pace.status.textTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.15), in: Capsule())
            }
            PaceBar(pace: pace, tint: tint)
                .frame(height: 14)
                .padding(.vertical, 4)
            Text(figures)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            detail
                .font(.caption)
        }
        .padding(.vertical, 4)
        .opacity(pace.status == .unknown(.stale) ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var detail: some View {
        if let runOut = pace.runOutDate, let reset = pace.resetDate {
            Text("照目前速度約 \(Self.span(runOut.timeIntervalSinceNow)) 後用完，比重置早 \(Self.span(reset.timeIntervalSince(runOut)))")
                .foregroundStyle(Color.statusRed)
        } else if case .unknown(let reason) = pace.status, reason != .tooEarly {
            Text(reason.text).foregroundStyle(.secondary)
        } else if let reset = pace.resetDate {
            HStack(spacing: 4) {
                if case .unknown(let reason) = pace.status { Text("\(reason.text)，") }
                // Shared with the 額度 row: a reset time already passed reads 「重置時間已過」.
                ResetText(date: reset)
                if windowIsEstimate { Text("（估計週期）") }
            }
            .foregroundStyle(.secondary)
        }
    }

    /// Remaining figures, the same direction as the 額度 page.
    private var figures: String {
        var parts = ["剩餘 \(Self.percent(100 - pace.used))"]
        if let elapsed = pace.elapsed { parts.append("時間剩 \(Self.percent(100 - elapsed))") }
        if let projected = pace.projected {
            parts.append(projected >= 100 ? "重置前會用完" : "重置時約剩 \(Self.percent(100 - projected))")
        }
        if pace.used == 0 { parts.append("尚未使用") }
        return parts.joined(separator: " · ")
    }

    /// Everything the row shows, as one sentence for VoiceOver.
    private var spoken: String {
        var parts = ["\(providerName) · \(title)", pace.status.label, figures]
        if let runOut = pace.runOutDate, let reset = pace.resetDate {
            parts.append("照目前速度約 \(Self.span(runOut.timeIntervalSinceNow)) 後用完，比重置早 \(Self.span(reset.timeIntervalSince(runOut)))")
        } else if case .unknown(let reason) = pace.status {
            parts.append(reason.text)
        }
        if let reset = pace.resetDate, reset > Date() {
            parts.append("\(Self.span(reset.timeIntervalSinceNow))後重置")
        }
        return parts.joined(separator: "，")
    }

    private var tint: Color { pace.status.tint }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func span(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(seconds, 60))
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }
}

/// Bullet bar in the 額度 page's direction: remaining quota (filled), time left in the window
/// (marker), and what the current pace leaves at the reset (dashed, back towards zero).
private struct PaceBar: View {
    let pace: PaceEstimate
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let x = { (percent: Double) in width * min(max(percent, 0), 100) / 100 }
            let remaining = 100 - pace.used
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(tint)
                    .frame(width: max(x(remaining), remaining > 0 ? height : 0))
                // The projection runs back into the filled bar, so it is drawn over the fill.
                if let projected = pace.projected, projected > pace.used, remaining > 0 {
                    let inset = height / 2
                    Path { path in
                        path.move(to: CGPoint(x: max(x(remaining) - inset, inset), y: height / 2))
                        path.addLine(to: CGPoint(x: max(x(100 - projected), inset), y: height / 2))
                    }
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 4]))
                }
                if let elapsed = pace.elapsed {
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: height + 8)
                        .offset(x: x(100 - elapsed) - 1)
                }
            }
            // Keep the bar centred in its own frame; the time marker overhangs it evenly.
            .frame(width: width, height: height)
        }
    }
}

/// Fixed colours for pools, in the order they were first recorded. Red, orange and green are
/// left out: elsewhere in the app they mean 用完／偏低／充足, so a pool drawn in them would
/// look like it has that status.
enum SeriesPalette {
    /// Pink reads close to red, so it comes last.
    private static let base: [Color] = [.blue, .purple, .teal, .indigo, .brown, .cyan, .gray, .pink]

    static func colors(count: Int) -> [Color] {
        (0..<max(count, 1)).map { base[$0 % base.count] }
    }
}
