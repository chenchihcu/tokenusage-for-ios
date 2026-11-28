import Charts
import SwiftUI

/// One agent at a time: each window's elapsed time, and one trend for the selected window.
struct AnalyticsView: View {
    let history: UsageHistory
    let items: [ProviderQuota]
    var scrollToTopToken = 0
    @State private var providerId = DirectProvider.claude.rawValue
    @State private var windowId: String?
    @State private var period: UsageHistory.Period = .week

    var body: some View {
        let windows = quota.map { Glance.windows($0) } ?? []
        let selected = windows.first { $0.id == windowId } ?? windows.first { $0.isBottleneck } ?? windows.first
        NavigationStack {
            List {
                Section {
                    HStack {
                        ForEach(DirectProvider.allCases) { provider in
                            Button {
                                providerId = provider.rawValue
                                windowId = nil
                            } label: {
                                ProviderBadge(id: provider.rawValue, name: provider.name, base: 32)
                                    .opacity(provider.rawValue == providerId ? 1 : 0.35)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(provider.name)
                            .accessibilityAddTraits(provider.rawValue == providerId ? .isSelected : [])
                            Spacer(minLength: 0)
                        }
                    }
                }
                if !windows.isEmpty {
                    Section {
                        ForEach(windows) { window in
                            Button {
                                windowId = window.id
                            } label: {
                                PaceLine(window: window, selected: window.id == selected?.id)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("用量與重置預估")
                    }
                }
                Section {
                    Picker("期間", selection: $period) {
                        Text("日").tag(UsageHistory.Period.day)
                        Text("週").tag(UsageHistory.Period.week)
                        Text("月").tag(UsageHistory.Period.month)
                    }
                    .pickerStyle(.segmented)
                    trend(for: selected)
                        .frame(height: 120)
                        .accessibilityLabel("選中視窗的用量趨勢")
                }
            }
            .listStyle(.insetGrouped)
            .scrollsToTop(on: scrollToTopToken)
            .navigationTitle("用量分析")
            .onAppear(perform: syncProviderSelection)
            .onChange(of: items.map(\.providerId)) { _, _ in
                syncProviderSelection()
            }
        }
    }

    private func syncProviderSelection() {
        if quota == nil, let first = items.first?.providerId {
            providerId = first
            windowId = nil
        }
    }

    private var quota: ProviderQuota? {
        items.first { $0.providerId == providerId }
    }

    @ViewBuilder
    private func trend(for window: GlanceWindow?) -> some View {
        let points = series(for: window)
        if points.isEmpty {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 4)
                .frame(maxHeight: .infinity, alignment: .center)
        } else {
            let maxConsumed = points.map(\.consumed).max() ?? 0
            Chart(points) { item in
                AreaMark(
                    x: .value("期間", item.day),
                    y: .value("用量", item.consumed)
                )
                .foregroundStyle(Color.accentColor.opacity(0.12))

                LineMark(
                    x: .value("期間", item.day),
                    y: .value("用量", item.consumed)
                )
                .foregroundStyle(Color.accentColor)

                if item.consumed > 0 {
                    PointMark(
                        x: .value("期間", item.day),
                        y: .value("用量", item.consumed)
                    )
                    .symbolSize(20)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .chartYScale(domain: 0...max(maxConsumed * 1.15, 10))
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v.rounded()))%")
                                .font(.caption2.monospacedDigit())
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: period == .month ? .dateTime.month(.abbreviated) : .dateTime.month(.defaultDigits).day())
                                .font(.caption2)
                        }
                    }
                }
            }
        }
    }

    private func series(for window: GlanceWindow?) -> [UsageDay] {
        guard let window else { return [] }
        return history.series(providerId: providerId, poolId: window.poolId,
                              tierId: window.tier.id, period: period,
                              providerName: quota?.name, poolName: window.poolName)
    }
}

/// Current used share of the window, with pace status (never an uncapped >100% projection).
private struct PaceLine: View {
    let window: GlanceWindow
    let selected: Bool

    private var pace: PaceEstimate { PaceEstimate(tier: window.tier) }

    var body: some View {
        HStack(spacing: 8) {
            Text(window.mark)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .frame(width: 72, alignment: .leading)
                .lineLimit(1)
            ProgressView(value: min(max(pace.used, 0), 100), total: 100)
                .tint(pace.status.tint)
            Text(summary)
                .font(.body.monospacedDigit())
                .foregroundStyle(pace.status.textTint)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if pace.status == .willRunOut || pace.status == .fast {
                Circle().fill(Color.statusOrange).frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.mark)，已用 \(summary)")
    }

    private var summary: String {
        pace.compactSummary
    }
}

extension PaceEstimate.Status {
    var tint: Color {
        switch self {
        case .exhausted, .willRunOut: return .red
        case .fast: return .orange
        case .onPace: return .green
        case .unknown: return .secondary
        }
    }

    var textTint: Color {
        switch self {
        case .exhausted, .willRunOut: return .statusRed
        case .fast: return .statusOrange
        case .onPace: return .statusGreen
        case .unknown: return .secondary
        }
    }
}
