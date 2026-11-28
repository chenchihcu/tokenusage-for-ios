import SwiftUI
import UIKit

struct QuotaListView: View {
    @Bindable var store: QuotaStore

    @AppStorage(SettingsKey.haptics) private var hapticsOn = true
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

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
            .scrollDisabled(!typeSize.isAccessibilitySize && !showsBanner)
            .overlay {
                if store.items.isEmpty, store.isLoading {
                    ProgressView("正在載入額度…")
                }
            }
            .sensoryFeedback(.selection, trigger: store.selectedID) { _, _ in hapticsOn && sizeClass == .regular }
            .sensoryFeedback(.success, trigger: store.refreshCount) { _, _ in hapticsOn }
            .scrollsToTop(on: store.scrollToTop[.quotas, default: 0])
    }

    private var showsBanner: Bool {
        if case .failed(let error) = store.state, error != .notConfigured { return true }
        return false
    }

    /// One row per agent, in vendor order. A row without a sign-in says 未設定 and has no percent.
    private var agentRows: [DirectProvider] {
        let providers = store.alertsOnly
            ? store.visibleItems.map(\.providerId)
            : DirectProvider.allCases.map(\.rawValue)
        return providers.compactMap { DirectProvider(rawValue: $0) }
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
        if !agentRows.isEmpty {
            Section { rows(agentRows) }
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
    }

    private func rows(_ providers: [DirectProvider]) -> some View {
        ForEach(providers) { provider in
            AgentGlanceRow(store: store, provider: provider)
        }
    }
}

/// The company icon is the shortcut. The bar and the percent are read-only.
private struct AgentGlanceRow: View {
    let store: QuotaStore
    let provider: DirectProvider
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var quota: ProviderQuota? { store.displayItems.first { $0.id == provider.rawValue } }
    private var hasAccess: Bool { provider.isSignedIn || quota != nil }

    var body: some View {
        HStack(spacing: 12) {
            shortcut
            readout
        }
        .contextMenu { ProviderActions(store: store, providerId: provider.rawValue) }
    }

    @ViewBuilder
    private var shortcut: some View {
        if hasAccess {
            NavigationLink(value: provider.rawValue) {
                ProviderBadge(id: provider.rawValue, name: provider.name, base: 28)
            }
            .buttonStyle(.borderless)
            .navigationLinkIndicatorVisibility(.hidden)
            .accessibilityLabel("\(provider.name)，詳細內容")
        } else {
            Button {
                if sizeClass == .regular {
                    store.selectedID = provider.rawValue
                } else {
                    store.accountPrompt = provider
                }
            } label: {
                ProviderBadge(id: provider.rawValue, name: provider.name, base: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(provider.name)，登入")
        }
    }

    @ViewBuilder
    private var readout: some View {
        if hasAccess, let quota, let window = Glance.bottleneck(quota) {
            if let usage = quota.tokenUsage {
                VStack(alignment: .leading, spacing: 3) {
                    GlanceReadout(mark: window.mark, remaining: window.remaining, urgent: window.urgent)
                    Text(TokenFormat.rowSummary(usage))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(TokenFormat.rowAccessibilityLabel(usage))
                }
            } else {
                GlanceReadout(mark: window.mark, remaining: window.remaining, urgent: window.urgent)
            }
        } else if hasAccess, quota?.isUnsupportedPlan == true {
            Text("這個方案目前無法顯示額度")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if hasAccess {
            Text("尚未更新")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text("未設定")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                ForEach(DirectProvider.allCases) { provider in
                    let quota = store.displayItems.first { $0.id == provider.rawValue }
                    HStack(spacing: 12) {
                        ProviderBadge(id: provider.rawValue, name: provider.name, base: 28)
                        if let credits = ResetBoard.creditText(quota) {
                            Text(credits)
                                .font(.body.monospacedDigit().weight(.medium))
                                .foregroundStyle((quota?.resetCredits ?? 0) > 0 ? Color.statusGreen : Color.secondary)
                        }
                        Spacer(minLength: 8)
                        if let date = quota.flatMap({ Glance.bottleneck($0)?.tier.resetDate }) {
                            ResetText(date: date)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
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

/// Free-reset digits for the four-row reset sheet. Cursor and Antigravity stay blank.
enum ResetBoard {
    static func creditText(_ quota: ProviderQuota?) -> String? {
        guard let quota, quota.reportsResetCredits, let credits = quota.resetCredits else { return nil }
        return String(credits)
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
