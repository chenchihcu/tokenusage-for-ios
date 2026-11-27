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
    @Environment(\.dynamicTypeSize) private var typeSize

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
                        ForEach(windows.prefix(Glance.detailLimit)) { window in
                            Button {
                                windowId = window.id
                            } label: {
                                PaceLine(window: window, selected: window.id == selected?.id)
                            }
                            .buttonStyle(.plain)
                        }
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
            .scrollDisabled(!typeSize.isAccessibilitySize)
            .scrollsToTop(on: scrollToTopToken)
            .navigationTitle("用量分析")
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
            Chart(points) { item in
                LineMark(
                    x: .value("期間", item.day, unit: period.component),
                    y: .value("用量", item.consumed)
                )
                .foregroundStyle(Color.accentColor)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
    }

    private func series(for window: GlanceWindow?) -> [UsageDay] {
        guard let window else { return [] }
        let key = "\(providerId)/\(window.poolId)"
        let totals = history.totals(by: period).filter { $0.key == key }
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
}

/// Elapsed share of the window, with the projected use at reset.
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
            ProgressView(value: min(max(pace.elapsed ?? 0, 0), 100), total: 100)
                .tint(pace.status.tint)
            Text(projected)
                .font(.body.monospacedDigit())
                .foregroundStyle(pace.status.textTint)
                .frame(minWidth: 44, alignment: .trailing)
            if pace.status == .willRunOut || pace.status == .fast {
                Circle().fill(Color.statusOrange).frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.mark)，\(pace.status.label)，\(projected)")
    }

    private var projected: String {
        guard let value = pace.projected else { return "—" }
        return (value / 100).formatted(.percent.precision(.fractionLength(0)))
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
