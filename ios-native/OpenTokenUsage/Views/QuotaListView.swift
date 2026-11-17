import SwiftUI

struct QuotaListView: View {
    enum Style { case push, select }

    @Bindable var store: QuotaStore
    let style: Style

    @State private var showSettings = false
    @AppStorage(SettingsKey.haptics) private var hapticsOn = true

    private var attention: [ProviderQuota] { store.displayItems.filter { $0.level != .healthy } }
    private var healthy: [ProviderQuota] { store.displayItems.filter { $0.level == .healthy } }

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
                ToolbarItem(placement: .status) {
                    StatusLine(store: store)
                }
            }
            .toolbar(.visible, for: .bottomBar)
            .refreshable { await store.refresh() }
            .overlay {
                if store.displayItems.isEmpty {
                    emptyState
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { Task { await store.refresh() } }) { SettingsView() }
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
        if case .failed(let error) = store.state {
            Section {
                ProblemBanner(error: error, hasData: !store.items.isEmpty) {
                    Task { await store.refresh() }
                }
            }
        }
        if !attention.isEmpty {
            Section("需要注意") { rows(attention) }
        }
        if !healthy.isEmpty {
            Section("額度充足") { rows(healthy) }
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

    @ViewBuilder
    private var emptyState: some View {
        if store.isLoading {
            ProgressView("正在載入額度…")
        } else {
            ContentUnavailableView {
                Label("還沒有額度資料", systemImage: "chart.bar.xaxis")
            } description: {
                Text(store.isOnline ? "下拉即可重新整理。" : "連上網路後會自動載入。")
            } actions: {
                Button("重新整理") { Task { await store.refresh() } }
                    .buttonStyle(.borderedProminent)
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
        case "grok": return .pink
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
