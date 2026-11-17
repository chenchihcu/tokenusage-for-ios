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
