import SwiftUI
import UIKit

/// Looks the platform up in the store so the detail stays live while refreshing.
struct QuotaDetailContainer: View {
    let store: QuotaStore
    let id: ProviderQuota.ID

    var body: some View {
        if let quota = store.displayItems.first(where: { $0.id == id }) {
            QuotaDetailView(quota: quota, status: store.status(for: quota.providerId),
                            signIn: { store.selectedTab = .settings })
                .refreshable { await store.refresh(force: true) }
        } else {
            ContentUnavailableView("找不到這個平台", systemImage: "questionmark.circle")
        }
    }
}

struct QuotaDetailView: View {
    let quota: ProviderQuota
    var status: ProviderStatus? = nil
    var signIn: () -> Void = {}
    /// The window the Live Activity follows (FR-18).
    @State private var trackedRef: String? = ResetActivity.trackedRef
    @State private var trackMessage: String?

    var body: some View {
        let pools = quota.pools
        let metrics = quota.metrics

        List {
            Section {
                SummaryHeader(quota: quota)
            }

            // FR-4: why this provider's figures may be old, with the way out for a 401.
            if let problem = status?.problem {
                Section {
                    ProviderStatusLine(status: status)
                    if problem == .signIn {
                        Button("重新登入", action: signIn)
                    }
                }
            }
            if quota.isUnsupportedPlan {
                Section {
                    Text("這個方案目前無法顯示額度").foregroundStyle(.secondary)
                }
            }

            if !pools.isEmpty {
                ForEach(pools) { pool in
                    Section {
                        ForEach(pool.tiers) { tier in
                            VStack(alignment: .leading, spacing: 8) {
                                TierRow(tier: tier, marksBottleneck: pool.tiers.count > 1)
                                TrackButton(
                                    window: QuotaWindow(providerId: quota.providerId, providerName: quota.name,
                                                        poolId: pool.id, poolName: pool.name,
                                                        poolCount: pools.count, tier: tier),
                                    dataDate: quota.fetchedDate ?? Date(),
                                    trackedRef: $trackedRef, message: $trackMessage)
                            }
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
        .alert("無法追蹤", isPresented: Binding(get: { trackMessage != nil }, set: { if !$0 { trackMessage = nil } })) {
            if trackMessage == ResetActivity.StartError.disabled.errorDescription {
                Button("開啟設定") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text(trackMessage ?? "")
        }
        .onAppear { trackedRef = ResetActivity.trackedRef }
        .navigationTitle(quota.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    ProviderBadge(id: quota.providerId, name: quota.name, base: 24)
                    Text(quota.name).font(.headline)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
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
            // The ring only shows the share; 「剩餘 X%」 beside it already says the number.
            Gauge(value: min(max(quota.remainingPercent, 0), 100), in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
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
                    .foregroundStyle(quota.level.textTint)
                if let reset = quota.resetDate {
                    ResetText(date: reset)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if quota.reportsResetCredits, quota.resetCredits != nil {
                    ResetCreditsLine(quota: quota).font(.subheadline)
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
                .foregroundStyle(QuotaLevel(remaining: pool.effectiveRemaining).textTint)
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
                        .foregroundStyle(Color.statusRed)
                }
                Spacer(minLength: 8)
                Text("剩餘 \(Int(tier.remaining.rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(QuotaLevel(remaining: tier.remaining).textTint)
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
                        .foregroundStyle(QuotaLevel(remaining: 100 - used).textTint)
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

/// 「在鎖定畫面追蹤」 for one window (FR-18, FR-22), or 「停止追蹤」 when it is the one followed.
private struct TrackButton: View {
    let window: QuotaWindow
    let dataDate: Date
    @Binding var trackedRef: String?
    @Binding var message: String?

    var body: some View {
        Group {
            if trackedRef == window.id {
                Button("停止追蹤", systemImage: "stop.circle") {
                    Task {
                        await ResetActivity.stop()
                        trackedRef = nil
                    }
                }
            } else if window.resetDate == nil {
                Label("沒有重置時間，無法追蹤", systemImage: "timer")
                    .foregroundStyle(.secondary)
            } else if ResetActivity.isSampleData {
                // FR-22: demo figures are not your usage.
                Label("示範資料開啟時無法追蹤", systemImage: "timer")
                    .foregroundStyle(.secondary)
            } else {
                Button(title, systemImage: "timer") {
                    Task {
                        do {
                            try await ResetActivity.start(window, dataDate: dataDate)
                            trackedRef = window.id
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
            }
        }
        .font(.subheadline)
        .buttonStyle(.borderless)
    }

    /// A Live Activity lasts about 8 hours, shorter than a weekly window (§6).
    private var title: String {
        guard let reset = window.resetDate, reset.timeIntervalSinceNow > ResetActivity.maximumLife else {
            return "在鎖定畫面追蹤"
        }
        return "在鎖定畫面追蹤（最多 8 小時）"
    }
}
