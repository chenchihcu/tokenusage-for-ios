import SwiftUI

struct QuotaListView: View {
    enum Style { case push, select }

    @Bindable var store: QuotaStore
    let style: Style

    @State private var showSettings = false
    @State private var showResets = false
    @AppStorage(SettingsKey.haptics) private var hapticsOn = true
    @AppStorage(SettingsKey.leftHanded) private var leftHanded = false
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = 60

    private var attention: [ProviderQuota] { store.visibleItems.filter { $0.level != .healthy } }
    private var healthy: [ProviderQuota] { store.visibleItems.filter { $0.level == .healthy } }

    var body: some View {
        list
            .listStyle(.insetGrouped)
            .navigationTitle("額度")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("設定", systemImage: "gearshape")
                    }
                }
                // Inner screen: the fast path lives in the toolbar, which the system
                // moves to the vertical bar where it applies.
                if style == .select {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button {
                            Task { await store.refresh(force: true) }
                        } label: {
                            Label("更新", systemImage: "arrow.clockwise")
                        }
                        .disabled(store.isLoading)
                        Button {
                            showResets = true
                        } label: {
                            Label("重置", systemImage: store.resetCreditsTotal > 0 ? "gift.fill" : "gift")
                        }
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
                ToolbarItem(placement: .status) {
                    StatusLine(store: store)
                }
            }
            .toolbar(.visible, for: .bottomBar)
            // Outer screen: the fast path sits in the thumb zone, on the chosen hand's side.
            .safeAreaInset(edge: .bottom, alignment: leftHanded ? .leading : .trailing) {
                if style == .push {
                    FastPathBar(store: store, showResets: $showResets)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .refreshable { await store.refresh(force: true) }
            .overlay {
                if store.items.isEmpty, store.isLoading {
                    ProgressView("正在載入額度…")
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { Task { await store.refresh(force: true) } }) { SettingsView() }
            .sheet(isPresented: $showResets) { ResetsView(store: store) }
            .sensoryFeedback(.selection, trigger: store.selectedID) { _, _ in hapticsOn && style == .select }
            .sensoryFeedback(.success, trigger: store.refreshCount) { _, _ in hapticsOn }
    }

    @ViewBuilder
    private var list: some View {
        switch style {
        case .select:
            List(selection: $store.selectedID) { sections }
        case .push:
            List { sections }
        }
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
                        showSettings = true
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

    @ViewBuilder
    private func rows(_ items: [ProviderQuota]) -> some View {
        ForEach(items) { item in
            switch style {
            case .push:
                NavigationLink(value: item.id) { QuotaRow(quota: item) }
            case .select:
                QuotaRow(quota: item)
            }
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

    var body: some View {
        HStack(spacing: 12) {
            ProviderBadge(id: quota.id, name: quota.name)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(quota.name).font(.headline)
                    Text(quota.planName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(quota.remainingPercent / 100, format: .percent.precision(.fractionLength(0)))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(quota.level.tint)
                }
                ProgressView(value: min(max(quota.remainingPercent, 0), 100), total: 100)
                    .tint(quota.level.tint)
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

struct ProviderBadge: View {
    let id: String
    let name: String

    var body: some View {
        Text(String(name.prefix(1)))
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(ProviderStyle.color(for: id), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

enum ProviderStyle {
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

/// One-handed fast path for the outer screen: four actions, each with an icon,
/// a visible title and at least a 44-point target.
struct FastPathBar: View {
    @Bindable var store: QuotaStore
    @Binding var showResets: Bool
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = 60

    var body: some View {
        HStack(spacing: 2) {
            Button {
                Task { await store.refresh(force: true) }
            } label: {
                FastPathLabel(title: "更新", systemImage: "arrow.clockwise")
            }
            .disabled(store.isLoading)

            Button {
                showResets = true
            } label: {
                FastPathLabel(title: "重置", systemImage: store.resetCreditsTotal > 0 ? "gift.fill" : "gift")
            }
            .overlay(alignment: .topTrailing) {
                if store.resetCreditsTotal > 0 {
                    Text("\(store.resetCreditsTotal)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.green, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(store.resetCreditsTotal > 0 ? "免費重置，\(store.resetCreditsTotal) 次可用" : "免費重置與重置時間")

            Button {
                store.alertsOnly.toggle()
            } label: {
                FastPathLabel(title: "告警",
                              systemImage: store.alertsOnly ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
            }
            .accessibilityLabel(store.alertsOnly ? "顯示全部服務" : "只看告警")

            Menu {
                Picker("更新頻率", selection: $refreshInterval) {
                    ForEach(AppSettings.intervalOptions) { option in
                        Text(option.title).tag(option.seconds)
                    }
                }
            } label: {
                FastPathLabel(title: "頻率", systemImage: "timer")
            }
            .accessibilityLabel("更新頻率")
        }
        .buttonStyle(.borderless)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}

private struct FastPathLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage).font(.title3)
            Text(title).font(.caption2)
        }
        .frame(minWidth: 52, minHeight: 48)
        .contentShape(Rectangle())
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
                        ForEach(quota.pools.flatMap(\.tiers)) { tier in
                            LabeledContent(tier.label) {
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
