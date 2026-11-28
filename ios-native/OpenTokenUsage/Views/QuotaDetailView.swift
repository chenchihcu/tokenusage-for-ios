import SwiftUI
import UIKit

/// Looks the platform up in the store so the detail stays live while refreshing.
struct QuotaDetailContainer: View {
    let store: QuotaStore
    let id: ProviderQuota.ID

    var body: some View {
        if let quota = store.displayItems.first(where: { $0.id == id }) {
            QuotaDetailView(quota: quota, status: store.status(for: quota.providerId),
                            signIn: {
                                if let provider = DirectProvider(rawValue: quota.providerId) {
                                    store.accountPrompt = provider
                                }
                            })
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
    /// The window whose reset and track button are open. The others stay one line.
    @State private var openedID: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var slots: [GlanceSlot] { Glance.detail(quota) }

    var body: some View {
        List {
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

            Section {
                ForEach(slots) { slot in
                    switch slot {
                    case .window(let window):
                        windowRow(window)
                    case .more(let count):
                        Text("還有 \(count) 個")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let combined = quota.metrics.first(where: { $0.label == "方案總用量" }),
               let used = combined.percentUsed {
                Section {
                    Text("方案總用量 \(Int(used.rounded()))% · 不另計限制")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if quota.reportsResetCredits, (quota.resetCredits ?? 0) > 0 {
                Section {
                    ResetCreditsLine(quota: quota)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDisabled(!typeSize.isAccessibilitySize && openedID == nil)
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
    }

    private func windowRow(_ window: GlanceWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                openedID = openedID == window.id ? nil : window.id
            } label: {
                GlanceReadout(mark: window.mark, remaining: window.remaining, urgent: window.urgent)
            }
            .buttonStyle(.plain)
            if openedID == window.id {
                if let reset = window.tier.resetDate {
                    ResetText(date: reset)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("重置時間不明")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                TrackButton(
                    window: QuotaWindow(providerId: quota.providerId, providerName: quota.name,
                                        poolId: window.poolId, poolName: window.poolName,
                                        poolCount: quota.pools.count, tier: window.tier),
                    dataDate: quota.fetchedDate ?? Date(),
                    trackedRef: $trackedRef, message: $trackMessage)
            }
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
