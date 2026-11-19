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

    /// Three rows is what fits either height (FR-W5, FR-W6).
    static let maxRows = 3
    /// Older figures are dimmed and labelled with their time (FR-14).
    static let staleAfter: TimeInterval = 3600

    static func isStale(savedAt: Date?, now: Date) -> Bool {
        guard let savedAt else { return false }
        return now.timeIntervalSince(savedAt) > staleAfter
    }

    /// One provider's pools as widget rows: same badge, the pool's name and tightest window.
    static func poolRows(_ item: ProviderQuota) -> [ProviderQuota] {
        let pools = item.pools
        guard pools.count > 1 else { return [item] }
        return pools.map { pool in
            var row = item
            row.name = pool.name
            row.planName = item.name
            row.remainingPercent = pool.effectiveRemaining
            row.usedQuota = pool.effectiveUsed
            row.resetTime = pool.primaryResetTime ?? ""
            row.tokenPoolsJson = nil
            row.metricsJson = nil
            return row
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
                    switch size {
                    case .small: SmallRow(quota: item)
                    case .medium: MediumRow(quota: item)
                    }
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

/// Badge · bar · % — no name: the badge says which vendor it is (FR-W5).
private struct SmallRow: View {
    let quota: ProviderQuota

    var body: some View {
        HStack(spacing: 8) {
            ProviderBadge(id: quota.providerId, name: quota.name, base: 22)
            LevelBar(remaining: quota.remainingPercent)
            PercentText(quota: quota)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel(quota))
    }
}

/// Badge, then name · plan · %, the bar, and one line of pools and reset time (FR-W6, FR-W7).
private struct MediumRow: View {
    let quota: ProviderQuota
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let pools = quota.pools  // decoded once per render
        HStack(alignment: .top, spacing: 8) {
            ProviderBadge(id: quota.providerId, name: quota.name, base: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(quota.name).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(quota.planName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    if quota.reportsResetCredits, let credits = quota.resetCredits, credits > 0 {
                        Label("\(credits)", systemImage: "gift.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.statusGreen)
                    }
                    PercentText(quota: quota)
                }
                LevelBar(remaining: quota.remainingPercent)
                // At accessibility sizes this line goes first, so names stay whole.
                if !typeSize.isAccessibilitySize {
                    secondaryLine(pools).font(.caption2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pools.count > 1
            ? "\(rowLabel(quota))，\(PoolSummary.plainLine(pools))" : rowLabel(quota))
    }

    /// Pools (when more than one), then the reset time, as in the 額度 row. When the line is
    /// too long the pools truncate and the reset time stays whole.
    private func secondaryLine(_ pools: [TokenPool]) -> some View {
        HStack(spacing: 0) {
            if pools.count > 1 {
                let sep = Text(verbatim: quota.resetDate == nil ? "" : PoolSummary.separator)
                    .foregroundStyle(.secondary)
                Text("\(PoolSummary.line(pools))\(sep)")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let reset = quota.resetDate {
                ResetText.text(reset)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
    }
}

private struct PercentText: View {
    let quota: ProviderQuota

    var body: some View {
        // A hidden 「100%」 holds the column width, so every bar ends at the same place.
        ZStack(alignment: .trailing) {
            Text("100%").hidden()
            Text(quota.remainingPercent / 100, format: .percent.precision(.fractionLength(0)))
                .foregroundStyle(quota.level.textTint)
                .widgetAccentable()
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .fixedSize()
    }
}

/// The 額度 row's progress bar: remaining %, in the level colour.
private struct LevelBar: View {
    let remaining: Double

    var body: some View {
        let value = min(max(remaining, 0), 100) / 100
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(QuotaLevel(remaining: remaining).tint)
                    .frame(width: geo.size.width * value)
                    .widgetAccentable()
            }
        }
        .frame(height: 4)
    }
}

/// Same wording as the 額度 row's VoiceOver value.
private func rowLabel(_ quota: ProviderQuota) -> String {
    "\(quota.name)，剩餘 \(Int(quota.remainingPercent.rounded()))%，\(quota.level.label)"
}
