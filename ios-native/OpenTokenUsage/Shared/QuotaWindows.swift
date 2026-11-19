import Foundation

/// One quota window (a tier of a pool of a provider), flattened so widgets, the Live Activity
/// and Siri can name and find it (spec-competitive-gap-v3.1.md, FR-12, FR-15, FR-23, FR-25).
struct QuotaWindow: Equatable, Identifiable {
    var providerId: String
    var providerName: String
    var poolId: String
    var poolName: String
    var poolCount: Int
    var tier: QuotaTier

    /// `providerId|poolId|tierId` — stable across resets, unlike `QuotaAlerts.windowKey`.
    var id: String { QuotaWindows.ref(provider: providerId, pool: poolId, tier: tier.id) }

    var remaining: Double { tier.remaining }
    var resetDate: Date? { tier.resetDate }

    /// 「5 小時」, or 「Opus · 每週」 when the provider has several pools.
    var shortLabel: String { poolCount > 1 ? "\(poolName) · \(tier.label)" : tier.label }
    /// 「Claude Code · Opus · 每週」.
    var fullLabel: String { "\(providerName) · \(shortLabel)" }
}

enum QuotaWindows {
    static func ref(provider: String, pool: String, tier: String) -> String {
        "\(provider)|\(pool)|\(tier)"
    }

    static func all(_ items: [ProviderQuota]) -> [QuotaWindow] {
        ProviderStyle.vendorOrdered(items, id: \.providerId).flatMap { item -> [QuotaWindow] in
            let pools = item.pools
            return pools.flatMap { pool in
                pool.tiers.map { tier in
                    QuotaWindow(providerId: item.providerId, providerName: item.name, poolId: pool.id,
                                poolName: pool.name, poolCount: pools.count, tier: tier)
                }
            }
        }
    }

    static func find(_ ref: String, in items: [ProviderQuota]) -> QuotaWindow? {
        all(items).first { $0.id == ref }
    }

    /// 「最緊的窗口」: lowest remaining % among windows that have not already reset (FR-12).
    /// Ties go to the sooner reset, then to list order.
    static func tightest(_ items: [ProviderQuota], now: Date = Date()) -> QuotaWindow? {
        let live = all(items).filter { window in
            guard let reset = window.resetDate else { return true }
            return reset > now
        }
        return live.min { a, b in
            if a.remaining != b.remaining { return a.remaining < b.remaining }
            return (a.resetDate ?? .distantFuture) < (b.resetDate ?? .distantFuture)
        }
    }

    /// 「2 小時前的資料：」 when the cache is older than `freshFor` (FR-25).
    static func staleness(savedAt: Date?, now: Date = Date(), freshFor: TimeInterval = 15 * 60) -> String? {
        guard let savedAt, now.timeIntervalSince(savedAt) > freshFor else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh-Hant")
        formatter.unitsStyle = .full
        return "\(formatter.localizedString(for: savedAt, relativeTo: now))的資料："
    }

    /// One spoken line per window: 「Claude Code 5 小時剩 42%，2小時 10分鐘後重置」 (FR-25).
    static func spokenLine(_ window: QuotaWindow, now: Date = Date()) -> String {
        var line = "\(window.providerName) \(window.shortLabel)剩 \(Int(window.remaining.rounded()))%"
        if let reset = window.resetDate, reset > now {
            line += "，\(PaceEstimate.span(reset.timeIntervalSince(now)))後重置"
        }
        return line
    }

    /// What 查詢剩餘額度 says: each provider's tightest window, from the cache only (FR-25, FR-27).
    static func answer(items: [ProviderQuota], savedAt: Date?, now: Date = Date()) -> String {
        guard !items.isEmpty else { return "還沒有登入任何服務" }
        let lines = ProviderStyle.vendorOrdered(items, id: \.providerId).compactMap { item in
            tightest([item], now: now).map { spokenLine($0, now: now) }
        }
        guard !lines.isEmpty else { return "還沒有額度資料" }
        let body = lines.joined(separator: "。")
        return (staleness(savedAt: savedAt, now: now) ?? "") + body + "。"
    }
}
