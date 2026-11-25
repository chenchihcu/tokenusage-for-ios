import SwiftUI
import UIKit

struct QuotaListView: View {
    @Bindable var store: QuotaStore

    @AppStorage(SettingsKey.haptics) private var hapticsOn = true
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        List(selection: $store.selectedID) { sections }
            .listStyle(.insetGrouped)
            .navigationTitle("額度")
            .alignedMainPage()
            .toolbar {
                // Fast path (FR-17/18): standard toolbar items, never a custom bar. On iPhone Duo
                // the system puts them on the vertical bar beside the outer camera, and on the
                // inner display keeps them with this (leading) pane — Apple HIG, Designing for
                // iPhone Duo › Vertical controls. They stay in the bar ahead of Settings.
                FastPathItems(store: store)
                    .visibilityPriority(.high)
            }
            .refreshable { await store.refresh(force: true) }
            .overlay {
                if store.items.isEmpty, store.isLoading {
                    ProgressView("正在載入額度…")
                }
            }
            .sensoryFeedback(.selection, trigger: store.selectedID) { _, _ in hapticsOn && sizeClass == .regular }
            .sensoryFeedback(.success, trigger: store.refreshCount) { _, _ in hapticsOn }
            .scrollsToTop(on: store.scrollToTop[.quotas, default: 0])
    }

    @ViewBuilder
    private var sections: some View {
        MainPageNavigation()
        Section {
            StatusLine(store: store)
        }
        if case .failed(let error) = store.state, error != .notConfigured {
            Section {
                ProblemBanner(error: error, hasData: !store.items.isEmpty) {
                    Task { await store.refresh(force: true) }
                }
            }
        }
        if !store.visibleItems.isEmpty {
            Section { rows(store.visibleItems) }
        }
        if store.alertsOnly, store.visibleItems.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("目前沒有告警").font(.headline)
                    Text("沒有服務的剩餘額度低於 20%。").font(.subheadline).foregroundStyle(.secondary)
                    Button("顯示全部") { store.alertsOnly = false }
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }
        }
        if !store.alertsOnly, !store.missingProviders.isEmpty {
            Section {
                ForEach(store.missingProviders) { provider in
                    Button {
                        store.selectedTab = .settings
                    } label: {
                        LabeledContent {
                            Text("前往設定").foregroundStyle(.tint)
                        } label: {
                            VendorLabel(id: provider.rawValue, name: provider.name)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("未設定")
            } footer: {
                Text("設定後，這裡會顯示該服務的剩餘額度與重置時間。")
            }
        }
    }

    private func rows(_ items: [ProviderQuota]) -> some View {
        // In a split view's list, a value link selects the platform: unfolded it fills the
        // detail pane, folded it pushes the detail screen.
        ForEach(items) { item in
            NavigationLink(value: item.id) { QuotaRow(quota: item, status: store.status(for: item.providerId)) }
                .contextMenu { ProviderActions(store: store, providerId: item.providerId) }
        }
    }
}

/// Inline status showing the latest refresh or connection state.
struct StatusLine: View {
    let store: QuotaStore

    var body: some View {
        Group {
            if store.isLoading {
                Text("正在更新…")
            } else if !store.isOnline {
                Label("離線，顯示上次資料", systemImage: "wifi.slash")
            } else if let date = store.lastUpdated {
                Text("更新於 \(date, style: .relative)前")
            } else {
                Text("尚未更新")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct ProblemBanner: View {
    let error: QuotaClientError
    let hasData: Bool
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: error == .offline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .foregroundStyle(error == .offline ? Color.secondary : Color.statusOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.localizedDescription).font(.subheadline.weight(.semibold))
                Text(hasData && error.hint == "請稍後再試。" ? "目前顯示的是上次成功取得的資料。" : error.hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("重試", action: retry)
                .buttonStyle(.bordered)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Per-provider actions (FR-6): refresh just this one, or sign in again after a 401.
struct ProviderActions: View {
    let store: QuotaStore
    let providerId: String

    var body: some View {
        if let provider = DirectProvider(rawValue: providerId) {
            if let next = store.nextAllowed(provider) {
                // Inside the floor or a back-off: no request, and say when it is allowed.
                Button {} label: {
                    Label("只更新這個服務（\(next, style: .relative)後可更新）", systemImage: "arrow.clockwise")
                }
                .disabled(true)
            } else {
                Button {
                    Task { await store.refresh(only: provider) }
                } label: {
                    Label("只更新這個服務", systemImage: "arrow.clockwise")
                }
            }
            if store.status(for: providerId)?.problem == .signIn {
                Button {
                    store.selectedTab = .settings
                } label: {
                    Label("重新登入", systemImage: "person.crop.circle.badge.exclamationmark")
                }
            }
        }
    }
}

/// 「5 分鐘前更新」, or why the last try failed with the figures marked as old (FR-3…FR-5).
struct ProviderStatusLine: View {
    let status: ProviderStatus?

    var body: some View {
        if let status, let problem = status.problem {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: problem == .offline ? "wifi.slash" : "exclamationmark.triangle.fill")
                        .accessibilityHidden(true)
                    Text(problem.message(retryAt: status.retryAt))
                }
                .foregroundStyle(problem == .offline ? Color.secondary : Color.statusOrange)
                .font(.caption.weight(.semibold))
                if let last = status.lastSuccess {
                    Text("上次資料 · \(last, style: .relative)前").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("上次資料").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else if let last = status?.lastSuccess {
            Text("\(last, style: .relative)前更新")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct QuotaRow: View {
    let quota: ProviderQuota
    var status: ProviderStatus? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            // At accessibility text sizes the text needs the full width; the badge
            // only repeats the name, so it steps aside.
            if !typeSize.isAccessibilitySize {
                ProviderBadge(id: quota.id, name: quota.name)
            }
            VStack(alignment: .leading, spacing: 6) {
                if typeSize.isAccessibilitySize {
                    Text(quota.name).font(.headline)
                    Text(quota.planName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    percentText
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        // A long name ("Google Antigravity") keeps whole words in a narrow
                        // column; the plan gives way and truncates instead.
                        Text(quota.name).font(.headline)
                            .layoutPriority(1)
                        Text(quota.planName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        percentText
                    }
                }
                ProgressView(value: min(max(quota.remainingPercent, 0), 100), total: 100)
                    .tint(quota.level.tint)
                if quota.pools.count > 1 {
                    PoolSummary(pools: quota.pools)
                }
                // A healthy-looking figure can still run out before the reset; say so here
                // instead of only on the 分析 page.
                if let warning = paceWarning {
                    HStack(spacing: 4) {
                        Image(systemName: warning == .willRunOut ? "exclamationmark.triangle.fill" : "speedometer")
                            .accessibilityHidden(true)
                        Text(Self.warningText(warning))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(warning.textTint)
                }
                if let reset = quota.resetDate {
                    ResetText(date: reset)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Only when a free reset is waiting; 「不提供」 on every row was noise
                // (the resets sheet still lists every provider's count).
                if quota.reportsResetCredits, (quota.resetCredits ?? 0) > 0 {
                    ResetCreditsLine(quota: quota).font(.caption)
                }
                // FR-7: a plan the parser read but could not turn into any window.
                if quota.isUnsupportedPlan {
                    Text("這個方案目前無法顯示額度").font(.caption).foregroundStyle(.secondary)
                }
                ProviderStatusLine(status: status)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let base = "剩餘 \(Int(quota.remainingPercent.rounded()))%，\(quota.level.label)"
        return paceWarning.map { "\(base)，\(Self.warningText($0))" } ?? base
    }

    /// The most urgent pace among this provider's windows (會用完 before 偏快); nil when every
    /// window is on pace, already used up (the figure shows that) or can't be estimated.
    private var paceWarning: PaceEstimate.Status? {
        let statuses = quota.pools.flatMap(\.tiers).map { PaceEstimate(tier: $0).status }
        if statuses.contains(.willRunOut) { return .willRunOut }
        if statuses.contains(.fast) { return .fast }
        return nil
    }

    static func warningText(_ status: PaceEstimate.Status) -> String {
        status == .willRunOut ? "照目前速度，重置前會用完" : "用得比時間快"
    }

    private var percentText: some View {
        Text(quota.remainingPercent / 100, format: .percent.precision(.fractionLength(0)))
            .font(.headline.monospacedDigit())
            .foregroundStyle(quota.level.textTint)
            .fixedSize()
    }
}

/// The four fast-path actions (FR-17), each with a title and a symbol. Grouped so the
/// system keeps them together on a vertical or horizontal bar.
struct FastPathItems: ToolbarContent {
    @Bindable var store: QuotaStore
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = 60

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await store.refresh(force: true) }
            } label: {
                Label("更新", systemImage: "arrow.clockwise")
            }
            .disabled(store.isLoading)

            Button {
                store.presentedSheet = .resets
            } label: {
                Label("重置", systemImage: store.resetCreditsTotal > 0 ? "gift.fill" : "gift")
            }
            .badge(store.resetCreditsTotal)
            .accessibilityLabel(store.resetCreditsTotal > 0 ? "免費重置，\(store.resetCreditsTotal) 次可用" : "免費重置與重置時間")

            Button {
                store.alertsOnly.toggle()
            } label: {
                Label("告警", systemImage: store.alertsOnly ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
            }
            .accessibilityLabel(store.alertsOnly ? "顯示全部服務" : "只看告警")

            Menu {
                Picker("更新頻率", selection: $refreshInterval) {
                    ForEach(AppSettings.intervalOptions) { option in
                        Text(option.title).tag(option.seconds)
                    }
                }
            } label: {
                Label("頻率", systemImage: "timer")
            }
        }
    }
}

/// Free resets (Codex, Claude Code) and every window's reset time, in one place.
struct ResetsView: View {
    let store: QuotaStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.displayItems.isEmpty {
                    Text("尚無資料。").foregroundStyle(.secondary)
                }
                ForEach(store.displayItems) { quota in
                    Section(quota.name) {
                        if quota.reportsResetCredits {
                            LabeledContent("免費重置") {
                                if let credits = quota.resetCredits {
                                    Text("\(credits) 次")
                                        .foregroundStyle(credits > 0 ? Color.statusGreen : Color.secondary)
                                } else {
                                    Text("—").accessibilityLabel("不提供")
                                }
                            }
                        }
                        ForEach(quota.pools.flatMap { pool in
                            // Name the pool when there are several, e.g. 「Opus · 每週」.
                            pool.tiers.map { tier in
                                (id: "\(pool.id).\(tier.id)",
                                 label: quota.pools.count > 1 ? "\(pool.name) · \(tier.label)" : tier.label,
                                 tier: tier)
                            }
                        }, id: \.id) { row in
                            let tier = row.tier
                            LabeledContent(row.label) {
                                if let reset = tier.resetDate {
                                    ResetText(date: reset)
                                } else {
                                    Text("重置時間不明")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("免費重置與重置時間")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 「🎁 免費重置 2 次」 with the symbol tight against the words (a List `Label` puts the
/// symbol in its own wide column).
struct ResetCreditsLine: View {
    let quota: ProviderQuota

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gift").accessibilityHidden(true)
            Text(quota.resetCreditsText)
        }
        .foregroundStyle((quota.resetCredits ?? 0) > 0 ? Color.statusGreen : Color.secondary)
    }
}
