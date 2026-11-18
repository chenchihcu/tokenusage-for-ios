import SwiftUI
import UIKit

struct QuotaListView: View {
    @Bindable var store: QuotaStore

    @AppStorage(SettingsKey.haptics) private var hapticsOn = true
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var attention: [ProviderQuota] { store.visibleItems.filter { $0.level != .healthy } }
    private var healthy: [ProviderQuota] { store.visibleItems.filter { $0.level == .healthy } }

    var body: some View {
        List(selection: $store.selectedID) { sections }
            .listStyle(.insetGrouped)
            .navigationTitle("額度")
            .toolbar {
                // Fast path (FR-17/18): standard toolbar items, never a custom bar. On iPhone Duo
                // the system puts them on the vertical bar beside the outer camera, and on the
                // inner display keeps them with this (leading) pane — Apple HIG, Designing for
                // iPhone Duo › Vertical controls. They stay in the bar ahead of Settings.
                FastPathItems(store: store)
                    .visibilityPriority(.high)
                ToolbarItem(placement: .status) {
                    StatusLine(store: store)
                }
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
        if case .failed(let error) = store.state, error != .notConfigured {
            Section {
                ProblemBanner(error: error, hasData: !store.items.isEmpty) {
                    Task { await store.refresh(force: true) }
                }
            }
        }
        if !attention.isEmpty {
            Section("需要注意") { rows(attention) }
        }
        if !healthy.isEmpty {
            Section("額度充足") { rows(healthy) }
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
        if !store.alertsOnly {
            Section {
                ForEach(store.missingProviders) { provider in
                    Button {
                        store.selectedTab = .settings
                    } label: {
                        LabeledContent(provider.name) {
                            Text("前往設定").foregroundStyle(.tint)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                LabeledContent("Google Antigravity") {
                    Text("暫不支援手機登入").foregroundStyle(.secondary)
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
            NavigationLink(value: item.id) { QuotaRow(quota: item) }
        }
    }
}

/// Bottom-bar line: when data was last updated, or what is happening now.
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
        .lineLimit(1)
    }
}

struct ProblemBanner: View {
    let error: QuotaClientError
    let hasData: Bool
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: error == .offline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .foregroundStyle(error == .offline ? Color.secondary : Color.orange)
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

struct QuotaRow: View {
    let quota: ProviderQuota
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
                        Text(quota.name).font(.headline)
                        Text(quota.planName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        percentText
                    }
                }
                ProgressView(value: min(max(quota.remainingPercent, 0), 100), total: 100)
                    .tint(quota.level.tint)
                if quota.pools.count > 1 {
                    PoolSummary(pools: quota.pools)
                }
                if let reset = quota.resetDate {
                    ResetText(date: reset)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if quota.reportsResetCredits {
                    Label(quota.resetCreditsText, systemImage: "gift")
                        .font(.caption)
                        .foregroundStyle((quota.resetCredits ?? 0) > 0 ? Color.green : Color.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue("剩餘 \(Int(quota.remainingPercent.rounded()))%，\(quota.level.label)")
    }

    private var percentText: some View {
        Text(quota.remainingPercent / 100, format: .percent.precision(.fractionLength(0)))
            .font(.headline.monospacedDigit())
            .foregroundStyle(quota.level.tint)
            .fixedSize()
    }
}

/// Each separately metered model pool with what is left in it, so the row says which
/// models still work when one pool has run out ("Opus 0% · Sonnet 80%").
struct PoolSummary: View {
    let pools: [TokenPool]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // One pool per line, free to wrap, so a long name never widens the row.
                VStack(alignment: .leading, spacing: 2) { items(fixed: false) }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { items(fixed: true) }
                    VStack(alignment: .leading, spacing: 2) { items(fixed: false) }
                }
            }
        }
        .font(.caption)
    }

    private func items(fixed: Bool) -> some View {
        ForEach(pools) { pool in
            (Text(pool.name).foregroundStyle(.secondary)
             + Text(" ")
             + Text(pool.effectiveRemaining / 100, format: .percent.precision(.fractionLength(0)))
                .foregroundStyle(QuotaLevel(remaining: pool.effectiveRemaining).tint))
                .monospacedDigit()
                .fixedSize(horizontal: fixed, vertical: true)
                .accessibilityElement(children: .combine)
        }
    }
}

struct ResetText: View {
    let date: Date

    var body: some View {
        if date > Date() {
            Text("\(date, style: .relative)後重置")
        } else {
            Text("重置時間已過 · \(date, format: .dateTime.month().day().hour().minute())")
        }
    }
}

/// The agent's own logo when its file is in the app (FR-38), so each one is recognised at a
/// glance; otherwise the first letter on the brand colour.
struct ProviderBadge: View {
    let id: String
    let name: String
    /// Grows with the text so the letter or logo is never clipped.
    @ScaledMetric(relativeTo: .headline) private var side: CGFloat = 36

    var body: some View {
        Group {
            if let logo = ProviderStyle.logo(for: id) {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                Text(String(name.prefix(1)))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: side, height: side)
                    .background(ProviderStyle.color(for: id), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .accessibilityHidden(true)
    }
}

enum ProviderStyle {
    /// Logo files you add under Resources/Logos: logo-claude.png, logo-codex.png,
    /// logo-cursor.png, logo-antigravity.png (square PNG, at least 180 × 180 px).
    static func logo(for id: String) -> UIImage? {
        UIImage(named: "logo-\(id)")
    }

    static func color(for id: String) -> Color {
        switch id {
        case "cursor": return .teal
        case "codex": return .green
        case "antigravity": return .indigo
        case "claude": return .orange
        default: return .gray
        }
    }
}

extension QuotaLevel {
    var tint: Color {
        switch self {
        case .exhausted: return .red
        case .low: return .orange
        case .healthy: return .green
        }
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
                            Label(quota.resetCreditsText, systemImage: "gift")
                                .foregroundStyle((quota.resetCredits ?? 0) > 0 ? Color.green : Color.secondary)
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
