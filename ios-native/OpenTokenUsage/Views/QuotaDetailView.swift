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

            tokenUsageSection
        }
        .listStyle(.insetGrouped)
        .scrollDisabled(!typeSize.isAccessibilitySize && openedID == nil && quota.tokenUsage == nil && status?.tokenProblem == nil)
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

    @ViewBuilder
    private var tokenUsageSection: some View {
        Section {
            if quota.providerId != DirectProvider.cursor.rawValue, quota.tokenUsage == nil {
                Text("Token：服務未提供")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if let problem = status?.tokenProblem {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: problem == .offline ? "wifi.slash" : "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)
                        Text(problem.message)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(problem == .offline ? Color.secondary : Color.statusOrange)
                }

                if let usage = quota.tokenUsage {
                    tokenUsageRows(usage)
                } else if status?.tokenProblem == nil {
                    Text("尚未取得 Token 資料")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Token 用量")
        } footer: {
            if let footer = tokenFooterText {
                Text(footer)
            }
        }
    }

    private var tokenFooterText: String? {
        guard let usage = quota.tokenUsage else { return nil }
        var lines: [String] = []
        if usage.totalCents != nil {
            lines.append("依服務回報的 API 價格估算，不是帳單金額。")
        }
        if usage.isPartial == true {
            lines.append("僅彙總前 1,000 筆事件，實際用量可能更高。")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    @ViewBuilder
    private func tokenUsageRows(_ usage: TokenUsageSummary) -> some View {
        LabeledContent("期間", value: TokenFormat.periodText(usage))
            .font(.subheadline)

        let totalPrefix = usage.isPartial == true ? "≥ " : ""
        let totalValue = usage.totalCents.map {
            "\(totalPrefix)\(TokenFormat.shortCount(usage.totalTokens)) tokens · \(TokenFormat.estimatedCost(cents: $0))"
        } ?? "\(totalPrefix)\(TokenFormat.shortCount(usage.totalTokens)) tokens"

        LabeledContent("總計") {
            Text(totalValue)
                .font(.subheadline.monospacedDigit().weight(.semibold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("總計，\(TokenFormat.rowAccessibilityLabel(usage))")

        let categories: [(String, Int64?)] = [
            ("輸入", usage.inputTokens),
            ("快取寫入", usage.cacheWriteTokens),
            ("快取讀取", usage.cacheReadTokens),
            ("輸出", usage.outputTokens),
        ]
        ForEach(categories.compactMap { title, value in value.map { (title, $0) } }, id: \.0) { title, value in
            LabeledContent(title) {
                Text(TokenFormat.shortCount(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title)，\(TokenFormat.spokenCount(value)) tokens")
        }

        ForEach(usage.models) { item in
            tokenModelRow(item)
        }

        if let fetched = usage.fetchedDate {
            LabeledContent("資料時間") {
                Text(fetched, format: .dateTime.month().day().hour().minute())
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
        }
    }

    @ViewBuilder
    private func tokenModelRow(_ item: TokenUsageModel) -> some View {
        let countText = "\(TokenFormat.shortCount(item.totalTokens)) tokens"
        let costText = item.totalCents.map { TokenFormat.estimatedCost(cents: $0) }
        let spoken = costText.map { "\(item.model)，\(TokenFormat.spokenCount(item.totalTokens)) tokens，\($0)" }
            ?? "\(item.model)，\(TokenFormat.spokenCount(item.totalTokens)) tokens"

        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.model)
                        .font(.subheadline.weight(.medium))
                    Text(costText.map { "\(countText) · \($0)" } ?? countText)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.model)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(costText.map { "\(countText) · \($0)" } ?? countText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
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
