import Foundation

/// One time window inside a pool, e.g. "5h limit" or "Weekly limit".
struct QuotaTier: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var used: Double
    var limit: Double
    var remaining: Double
    var resetsAt: String?
    var resetDurationText: String?
    var isGoverning: Bool?
    /// Length of the window in seconds, when the vendor tells us (or it is fixed, like 5 h).
    /// Missing in snapshots saved before pace charts existed; those decode as nil.
    var windowSeconds: Double? = nil
    /// True when `windowSeconds` is a guess (Cursor without a cycle start date).
    var windowIsEstimate: Bool? = nil

    var resetDate: Date? { resetsAt.flatMap(QuotaDate.parse) }
}

/// A separately metered group of models inside one provider.
struct TokenPool: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var description: String?
    var effectiveRemaining: Double
    var effectiveUsed: Double
    var primaryResetTime: String?
    var isCritical: Bool
    var tiers: [QuotaTier]

    var resetDate: Date? { primaryResetTime.flatMap(QuotaDate.parse) }
}

/// Older flat metric rows (still sent for providers without pools).
struct QuotaMetric: Codable, Hashable {
    var label: String
    var used: Double?
    var limit: Double?
    var kind: String?
    var value: String?
    var isAlert: Bool?

    var percentUsed: Double? {
        guard let used else { return nil }
        let limit = (self.limit ?? 100) > 0 ? (self.limit ?? 100) : 100
        return min(max(used / limit * 100, 0), 100)
    }
}

/// One provider row from `GET /api/quotas`.
struct ProviderQuota: Codable, Hashable, Identifiable {
    var providerId: String
    var name: String
    var planName: String
    var totalQuota: Double
    var usedQuota: Double
    var remainingPercent: Double
    var resetTime: String
    var status: String
    var tokenPoolsJson: String?
    var metricsJson: String?
    var fetchedAt: String
    /// Optional billing-cycle token usage; missing in older snapshots and decodes as nil.
    var tokenUsage: TokenUsageSummary? = nil

    var id: String { providerId }

    enum CodingKeys: String, CodingKey {
        case providerId = "provider_id"
        case name
        case planName = "plan_name"
        case totalQuota = "total_quota"
        case usedQuota = "used_quota"
        case remainingPercent = "remaining_percent"
        case resetTime = "reset_time"
        case status
        case tokenPoolsJson = "token_pools_json"
        case metricsJson = "metrics_json"
        case fetchedAt = "fetched_at"
        case tokenUsage = "token_usage"
    }

    var pools: [TokenPool] { Self.decodeEmbedded([TokenPool].self, from: tokenPoolsJson) ?? [] }
    var metrics: [QuotaMetric] { Self.decodeEmbedded([QuotaMetric].self, from: metricsJson) ?? [] }
    var resetDate: Date? { QuotaDate.parse(resetTime) }
    var fetchedDate: Date? { QuotaDate.parse(fetchedAt) }

    var level: QuotaLevel { QuotaLevel(remaining: remainingPercent) }

    private static func decodeEmbedded<T: Decodable>(_ type: T.Type, from json: String?) -> T? {
        guard let data = json?.data(using: .utf8), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// How worried the person should be about a remaining percentage.
enum QuotaLevel: Comparable {
    case exhausted   // ≤ 5 %
    case low         // < 30 %
    case healthy

    init(remaining: Double) {
        if remaining <= 5 { self = .exhausted }
        else if remaining < 30 { self = .low }
        else { self = .healthy }
    }

    var label: String {
        switch self {
        case .exhausted: return "已耗盡"
        case .low: return "偏低"
        case .healthy: return "充足"
        }
    }
}

/// "Will this window run out before it resets?" (spec-usage-pace-charts.md, FR-P2…FR-P5).
/// Straight-line pace since the window started; computed on the phone from one reading.
struct PaceEstimate: Equatable {
    enum Status: Equatable {
        case exhausted   // 已用完
        case willRunOut  // 會用完
        case fast        // 偏快
        case onPace      // 正常
        case unknown(Reason)

        var label: String {
            switch self {
            case .exhausted: return "已用完"
            case .willRunOut: return "會用完"
            case .fast: return "偏快"
            case .onPace: return "正常"
            case .unknown: return "無法估算"
            }
        }
    }

    enum Reason: Equatable {
        case noResetDate, noWindowLength, tooEarly, stale

        var text: String {
            switch self {
            case .noResetDate: return "沒有重置時間"
            case .noWindowLength: return "不知道週期長度"
            case .tooEarly: return "剛重置，資料不足"
            case .stale: return "資料已過期，請更新"
            }
        }
    }

    /// "3小時 20分鐘"-style text, at least one minute. Used by 用量分析 and quota alerts.
    static func span(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(seconds, 60))
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    /// Below this share of the window, one burst would swing the projection wildly.
    static let minElapsedPercent = 5.0
    /// Projected use at reset from which the pace counts as 偏快.
    static let fastThreshold = 85.0

    var used: Double
    /// Share of the window's time already gone, 0…100. Nil when it can't be worked out.
    var elapsed: Double?
    /// Use at reset if the current pace holds. Nil when not projected.
    var projected: Double?
    var resetDate: Date?
    /// When use reaches 100 % at the current pace; only when that is before the reset.
    var runOutDate: Date?
    var status: Status

    init(tier: QuotaTier, now: Date = Date()) {
        let used = min(max(tier.used, 0), 100)
        self.used = used
        self.resetDate = tier.resetDate
        guard used < 100 else {
            status = .exhausted
            return
        }
        guard let reset = tier.resetDate else {
            status = .unknown(.noResetDate)
            return
        }
        guard reset > now else {
            status = .unknown(.stale)
            return
        }
        guard let window = tier.windowSeconds, window > 0 else {
            status = .unknown(.noWindowLength)
            return
        }
        let start = reset.addingTimeInterval(-window)
        let gone = min(max(now.timeIntervalSince(start), 0), window)
        let elapsed = gone / window * 100
        self.elapsed = elapsed
        if used == 0 {
            status = .onPace
            return
        }
        guard elapsed >= Self.minElapsedPercent else {
            status = .unknown(.tooEarly)
            return
        }
        let projected = used / elapsed * 100
        self.projected = projected
        if projected > 100 {
            // Use per second so far, carried on until 100 %.
            let rate = used / gone
            runOutDate = now.addingTimeInterval((100 - used) / rate)
            status = .willRunOut
        } else if projected >= Self.fastThreshold {
            status = .fast
        } else {
            status = .onPace
        }
    }

    /// Compact single-line summary for analytics rows: shows actual used % (0–100%) and pace warning
    /// without exposing uncapped >100% projections as if they were token usage.
    var compactSummary: String {
        let usedPercent = (min(max(used, 0), 100) / 100).formatted(.percent.precision(.fractionLength(0)))
        switch status {
        case .exhausted, .willRunOut, .fast:
            return "\(usedPercent) · \(status.label)"
        case .onPace, .unknown:
            return usedPercent
        }
    }
}

/// Builds provider rows from their windows. Shared by the response parser, the bundled
/// sample data and the widget gallery, so all three produce the same shape.
enum QuotaAssembly {
    /// A pool before its bottleneck is worked out.
    struct PoolDraft {
        var id: String
        var name: String
        var description: String?
        var tiers: [QuotaTier]
    }

    static func tier(id: String, label: String, used: Double, resetsAt: String?,
                     windowSeconds: Double? = nil) -> QuotaTier {
        let clamped = min(max(used, 0), 100)
        return QuotaTier(id: id, label: label, used: clamped, limit: 100, remaining: 100 - clamped,
                         resetsAt: resetsAt, resetDurationText: nil, isGoverning: nil,
                         windowSeconds: windowSeconds)
    }

    /// Each pool's remaining share is its tightest window (RFC-003). The provider headline is
    /// its tightest pool, so a model that has run out is never hidden behind one that has not.
    static func make(id: String, name: String, plan: String, pools drafts: [PoolDraft],
                     metrics: [QuotaMetric], now: Date,
                     tokenUsage: TokenUsageSummary? = nil) -> ProviderQuota {
        let pools = drafts.map { draft -> TokenPool in
            var tiers = draft.tiers
            let worst = tiers.indices.min { tiers[$0].remaining < tiers[$1].remaining }
            if let worst { tiers[worst].isGoverning = true }
            let remaining = worst.map { tiers[$0].remaining } ?? 100
            return TokenPool(id: draft.id, name: draft.name, description: draft.description,
                             effectiveRemaining: remaining, effectiveUsed: 100 - remaining,
                             primaryResetTime: worst.flatMap { tiers[$0].resetsAt },
                             isCritical: remaining <= 5, tiers: tiers)
        }
        let worstPool = pools.min { $0.effectiveRemaining < $1.effectiveRemaining }
        let remaining = worstPool?.effectiveRemaining ?? 100
        let reset = worstPool?.primaryResetTime
        return ProviderQuota(
            providerId: id, name: name, planName: plan,
            totalQuota: 100, usedQuota: 100 - remaining, remainingPercent: remaining,
            resetTime: reset ?? "", status: remaining <= 5 ? "warning" : "active",
            tokenPoolsJson: encode(pools), metricsJson: metrics.isEmpty ? nil : encode(metrics),
            fetchedAt: iso.string(from: now), tokenUsage: tokenUsage)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func encode<T: Encodable>(_ value: T) -> String? {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

struct QuotaEnvelope: Decodable {
    var success: Bool
    var data: [ProviderQuota]?
    var error: String?
}

enum QuotaDate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Accepts ISO 8601 with 0, 3 or 6 fractional digits (the API sends both).
    static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let d = withFraction.date(from: trimmed) ?? plain.date(from: trimmed) { return d }
        // Drop fractional seconds, keep the zone designator.
        if let dot = trimmed.firstIndex(of: "."),
           let zone = trimmed[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            let stripped = String(trimmed[..<dot]) + String(trimmed[zone...])
            return plain.date(from: stripped)
        }
        return nil
    }
}

extension ProviderQuota {
    /// Codex and Claude Code can grant free resets; other providers never do.
    var reportsResetCredits: Bool { providerId == "codex" || providerId == "claude" }

    /// Free resets the vendor says are available ("Resets: 2 available").
    /// `nil` means the vendor did not report a number — never shown as 0.
    var resetCredits: Int? {
        for metric in metrics where metric.label.lowercased().hasPrefix("reset") {
            guard let value = metric.value else { continue }
            let digits = value.drop { !$0.isNumber }.prefix { $0.isNumber }
            if let count = Int(digits) { return count }
        }
        return nil
    }

    /// FR-7: the vendor answered, but nothing in it is a window or figure we can show.
    var isUnsupportedPlan: Bool { pools.isEmpty && metrics.isEmpty }

    var resetCreditsText: String {
        resetCredits.map { "免費重置 \($0) 次" } ?? "免費重置：不提供"
    }
}

/// One window drawn as a mark, a bar and a percent. The list shows only the bottleneck;
/// the detail shows up to four of these.
struct GlanceWindow: Equatable, Identifiable {
    var poolId: String
    var poolName: String
    var tier: QuotaTier
    var mark: String
    var isBottleneck: Bool
    var urgent: Bool

    var id: String { "\(poolId).\(tier.id)" }
    var remaining: Double { tier.remaining }
}

enum GlanceSlot: Equatable, Identifiable {
    case window(GlanceWindow)
    case more(Int)

    var id: String {
        switch self {
        case .window(let window): return window.id
        case .more: return "more"
        }
    }
}

/// Names the tightest window with a short mark: `5h`, `週`, `月`, or `Opus週`.
enum Glance {
    /// Detail keeps four cells. Past that, the fourth cell is a count.
    static let detailLimit = 4

    static func bottleneck(_ quota: ProviderQuota, forcePrefix: Bool = false, now: Date = Date()) -> GlanceWindow? {
        windows(quota, forcePrefix: forcePrefix, now: now).first { $0.isBottleneck }
    }

    /// Bottleneck first, then the next-tightest windows.
    static func windows(_ quota: ProviderQuota, forcePrefix: Bool = false, now: Date = Date()) -> [GlanceWindow] {
        let tightest = quota.pools.min { $0.effectiveRemaining < $1.effectiveRemaining }
        let governing = tightest.flatMap { pool in
            pool.tiers.first { $0.isGoverning == true } ?? pool.tiers.min { $0.remaining < $1.remaining }
        }
        let rows = quota.pools.flatMap { pool in
            pool.tiers.map { tier in
                window(pool: pool, tier: tier, quota: quota, forcePrefix: forcePrefix,
                       bottleneck: pool.id == tightest?.id && tier.id == governing?.id, now: now)
            }
        }
        return rows.sorted { lhs, rhs in
            if lhs.isBottleneck != rhs.isBottleneck { return lhs.isBottleneck }
            if lhs.remaining != rhs.remaining { return lhs.remaining < rhs.remaining }
            return lhs.id < rhs.id
        }
    }

    /// At most four cells. More windows collapse into 「還有 N 個」.
    static func detail(_ quota: ProviderQuota, now: Date = Date()) -> [GlanceSlot] {
        let rows = windows(quota, now: now)
        guard rows.count > detailLimit else { return rows.map { .window($0) } }
        return rows.prefix(detailLimit - 1).map { .window($0) } + [.more(rows.count - (detailLimit - 1))]
    }

    /// One line per pool, for a widget that shows a single agent. Each line is that pool's tightest window.
    static func poolLines(_ quota: ProviderQuota, now: Date = Date()) -> [GlanceWindow] {
        let prefix = quota.pools.count > 1
        return quota.pools.compactMap { pool in
            let tier = pool.tiers.first { $0.isGoverning == true } ?? pool.tiers.min { $0.remaining < $1.remaining }
            guard let tier else { return nil }
            return window(pool: pool, tier: tier, quota: quota, forcePrefix: prefix, bottleneck: false, now: now)
        }
    }

    private static func window(pool: TokenPool, tier: QuotaTier, quota: ProviderQuota,
                               forcePrefix: Bool, bottleneck: Bool, now: Date) -> GlanceWindow {
        GlanceWindow(poolId: pool.id, poolName: pool.name, tier: tier,
                     mark: mark(pool: pool, tier: tier, quota: quota, forcePrefix: forcePrefix),
                     isBottleneck: bottleneck, urgent: isUrgent(tier, now: now))
    }

    static func mark(pool: TokenPool, tier: QuotaTier, quota: ProviderQuota, forcePrefix: Bool = false) -> String {
        let symbol = symbol(tier: tier, providerId: quota.providerId)
        if !forcePrefix, isShared(pool, quota: quota) { return symbol }
        return shortName(pool) + symbol
    }

    /// The agent's shared pool, or its only pool, is named by the symbol alone.
    static func isShared(_ pool: TokenPool, quota: ProviderQuota) -> Bool {
        if quota.pools.count <= 1 { return true }
        if pool.id == "claude_all" || pool.name == "所有模型" { return true }
        if pool.id == "codex_main" { return true }
        return false
    }

    static func symbol(tier: QuotaTier, providerId: String) -> String {
        if tier.label == "本期" { return "月" }
        if providerId == "cursor", tier.label != "5 小時", tier.label != "每週" { return "月" }
        if let seconds = tier.windowSeconds {
            if abs(seconds - 18_000) <= 120 { return "5h" }
            if abs(seconds - 604_800) <= 3_600 || abs(seconds - 7 * 86_400) <= 3_600 { return "週" }
        }
        if tier.label.contains("5"), tier.label.contains("小時") { return "5h" }
        if tier.label.contains("每週") || tier.label.localizedCaseInsensitiveContains("week") { return "週" }
        if providerId == "cursor" { return "月" }
        return tier.label
    }

    static func shortName(_ pool: TokenPool) -> String {
        let known = [
            "claude_opus": "Opus",
            "claude_sonnet": "Sonnet",
            "claude_oauth_apps": "App",
            "claude_cowork": "Cowork",
            "cursor_auto": "Auto",
            "cursor_api": "API",
            "antigravity_gemini": "Gemini",
            "antigravity_3p": "Claude",
            "antigravity_gemini_argon_wtu": "Argon",
        ]
        if let name = known[pool.id] { return name }
        let word = pool.name.split(whereSeparator: { $0 == " " || $0 == "·" }).first.map(String.init) ?? pool.name
        return String(word.prefix(8))
    }

    static func isUrgent(_ tier: QuotaTier, now: Date) -> Bool {
        switch PaceEstimate(tier: tier, now: now).status {
        case .willRunOut, .fast: return true
        default: return false
        }
    }
}
