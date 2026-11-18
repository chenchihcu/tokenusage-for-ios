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
                     metrics: [QuotaMetric], now: Date) -> ProviderQuota {
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
            fetchedAt: iso.string(from: now))
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

    var resetCreditsText: String {
        resetCredits.map { "免費重置 \($0) 次" } ?? "免費重置：不提供"
    }
}
