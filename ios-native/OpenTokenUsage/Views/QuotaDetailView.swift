import SwiftUI

/// Looks the platform up in the store so the detail stays live while refreshing.
struct QuotaDetailContainer: View {
    let store: QuotaStore
    let id: ProviderQuota.ID

    var body: some View {
        if let quota = store.displayItems.first(where: { $0.id == id }) {
            QuotaDetailView(quota: quota)
                .refreshable { await store.refresh(force: true) }
        } else {
            ContentUnavailableView("找不到這個平台", systemImage: "questionmark.circle")
        }
    }
}

struct QuotaDetailView: View {
    let quota: ProviderQuota

    var body: some View {
        let pools = quota.pools
        let metrics = quota.metrics

        List {
            Section {
                SummaryHeader(quota: quota)
            }

            if !pools.isEmpty {
                ForEach(pools) { pool in
                    Section {
                        ForEach(pool.tiers) { tier in
                            TierRow(tier: tier, marksBottleneck: pool.tiers.count > 1)
                        }
                    } header: {
                        PoolHeader(pool: pool)
                    } footer: {
                        if let description = pool.description, !description.isEmpty {
                            Text(description)
                        }
                    }
                }
            }
            // Figures beside the pools that do not limit anything themselves (Cursor's combined total).
            let extra = metrics.filter { !$0.label.lowercased().hasPrefix("reset") }
            if !pools.isEmpty, !extra.isEmpty {
                Section("其他") {
                    ForEach(Array(extra.enumerated()), id: \.offset) { _, metric in
                        MetricRow(metric: metric)
                    }
                }
            } else if pools.isEmpty, !metrics.isEmpty {
                Section("用量明細") {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                        MetricRow(metric: metric)
                    }
                }
            }

            Section {
                LabeledContent("方案", value: quota.planName)
                if let reset = quota.resetDate {
                    LabeledContent("下次重置") {
                        Text(reset, format: .dateTime.month().day().hour().minute())
                    }
                }
                if let fetched = quota.fetchedDate {
                    LabeledContent("資料取得") {
                        Text(fetched, format: .dateTime.month().day().hour().minute())
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(quota.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SummaryHeader: View {
    let quota: ProviderQuota
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility text sizes the gauge goes above the text so nothing is squeezed.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        layout {
            Gauge(value: min(max(quota.remainingPercent, 0), 100), in: 0...100) {
                Text("剩餘")
            } currentValueLabel: {
                Text(quota.remainingPercent / 100, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(quota.level.tint)
            .scaleEffect(1.3)
            .frame(width: 72, height: 72)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("剩餘 \(Int(quota.remainingPercent.rounded()))%")
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text(quota.level.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(quota.level.tint)
                if let reset = quota.resetDate {
                    ResetText(date: reset)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if quota.reportsResetCredits {
                    Label(quota.resetCreditsText, systemImage: "gift")
                        .font(.subheadline)
                        .foregroundStyle((quota.resetCredits ?? 0) > 0 ? Color.green : Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct PoolHeader: View {
    let pool: TokenPool

    var body: some View {
        HStack {
            Text(pool.name)
            Spacer()
            Text(pool.effectiveRemaining / 100, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .foregroundStyle(QuotaLevel(remaining: pool.effectiveRemaining).tint)
        }
    }
}

private struct TierRow: View {
    let tier: QuotaTier
    /// 「瓶頸」 only means something when the pool has more than one window.
    var marksBottleneck = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let header = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        VStack(alignment: .leading, spacing: 6) {
            header {
                Text(tier.label)
                if marksBottleneck, tier.isGoverning == true {
                    Text("瓶頸")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 8)
                Text("剩餘 \(Int(tier.remaining.rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(QuotaLevel(remaining: tier.remaining).tint)
            }
            ProgressView(value: min(max(tier.remaining, 0), 100), total: 100)
                .tint(QuotaLevel(remaining: tier.remaining).tint)
            if let reset = tier.resetDate {
                ResetText(date: reset)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let text = tier.resetDurationText {
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct MetricRow: View {
    let metric: QuotaMetric

    var body: some View {
        if let used = metric.percentUsed {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(metric.label)
                    Spacer()
                    Text("已用 \(Int(used.rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(QuotaLevel(remaining: 100 - used).tint)
                }
                ProgressView(value: 100 - used, total: 100)
                    .tint(QuotaLevel(remaining: 100 - used).tint)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        } else {
            LabeledContent(metric.label, value: metric.value ?? "—")
        }
    }
}
