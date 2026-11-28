import SwiftUI
import WidgetKit

/// What the home-screen widget draws, shared so the app's tests can render it too
/// (spec-widget-alignment.md, FR-W1…FR-W8). Reads like a 額度 row: same badge, order,
/// level colours and bar.
struct QuotaWidgetContent: View {
    enum Size { case small, medium }

    let items: [ProviderQuota]
    let savedAt: Date?
    let size: Size
    var now: Date = Date()
    /// Rows already in the wanted order (one provider's pools), not the vendor order.
    var keepOrder = false
    /// Those pool rows should keep the pool's short name on the mark (`Opus週`).
    var prefixPool = false

    /// Three rows is what fits either height (FR-W5, FR-W6).
    static let maxRows = 3
    /// Older figures are dimmed and labelled with their time (FR-14).
    static let staleAfter: TimeInterval = 3600

    static func isStale(savedAt: Date?, now: Date) -> Bool {
        guard let savedAt else { return false }
        return now.timeIntervalSince(savedAt) > staleAfter
    }

    /// One provider's pools as widget rows. Each row keeps that pool, so its mark is the pool's tightest window.
    static func poolRows(_ item: ProviderQuota) -> [ProviderQuota] {
        let pools = item.pools
        guard pools.count > 1 else { return [item] }
        let now = item.fetchedDate ?? Date()
        return pools.map { pool in
            let tiers = pool.tiers.map { tier in
                QuotaAssembly.tier(id: tier.id, label: tier.label, used: tier.used,
                                   resetsAt: tier.resetsAt, windowSeconds: tier.windowSeconds)
            }
            return QuotaAssembly.make(id: item.providerId, name: item.name, plan: item.planName, pools: [
                QuotaAssembly.PoolDraft(id: pool.id, name: pool.name, description: pool.description, tiers: tiers),
            ], metrics: [], now: now)
        }
    }

    var body: some View {
        let stale = Self.isStale(savedAt: savedAt, now: now)
        content(stale: stale)
            .opacity(stale ? 0.55 : 1)
    }

    @ViewBuilder
    private func content(stale: Bool) -> some View {
        if items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI 額度").font(.headline)
                Text("開啟 App 以更新").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            let ordered = keepOrder ? items : ProviderStyle.vendorOrdered(items, id: \.providerId)
            let rows = Array(ordered.prefix(Self.maxRows))
            VStack(alignment: .leading, spacing: size == .small ? 10 : 7) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                    WidgetGlanceRow(quota: item, badge: size == .small ? 22 : 26, prefixPool: prefixPool)
                }
                Spacer(minLength: 0)
                // The medium height has no room under three rows (FR-W8); the app and the
                // small widget show freshness.
                if size == .small, let savedAt {
                    (stale ? Text("\(savedAt, format: .dateTime.hour().minute()) 的資料")
                           : Text("更新於 \(savedAt, style: .relative)前"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Company icon, bottleneck mark, bar, percent. One line, same as the 額度 row.
private struct WidgetGlanceRow: View {
    let quota: ProviderQuota
    var badge: CGFloat
    /// A widget set to one agent lists that agent's pools, so each mark keeps the pool name.
    var prefixPool = false

    var body: some View {
        let window = Glance.bottleneck(quota, forcePrefix: prefixPool)
        HStack(spacing: 8) {
            ProviderBadge(id: quota.providerId, name: quota.name, base: badge)
            if let window {
                GlanceReadout(mark: window.mark, remaining: window.remaining, urgent: window.urgent)
            } else if quota.isUnsupportedPlan {
                Text("這個方案目前無法顯示額度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(window))
    }

    private func label(_ window: GlanceWindow?) -> String {
        guard let window else {
            return quota.isUnsupportedPlan ? "\(quota.name)，這個方案目前無法顯示額度" : quota.name
        }
        let base = "\(quota.name)，\(window.mark)，剩餘 \(Int(window.remaining.rounded()))%，\(QuotaLevel(remaining: window.remaining).label)"
        return window.urgent ? base + "，重置前會用完" : base
    }
}

