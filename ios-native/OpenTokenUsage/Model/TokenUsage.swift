import Foundation

/// Per-model token usage and estimated API cost for one billing period.
struct TokenUsageModel: Codable, Hashable, Identifiable {
    var model: String
    var inputTokens: Int64?
    var cacheWriteTokens: Int64?
    var cacheReadTokens: Int64?
    var outputTokens: Int64?
    var totalTokens: Int64
    var totalCents: Double?

    var id: String { model }
}

/// Billing-cycle token summary stored alongside a `ProviderQuota` snapshot.
/// Shared by both the app and widget targets via `OpenTokenUsage/Model/`.
struct TokenUsageSummary: Codable, Hashable {
    var periodStart: String?
    var periodEnd: String?
    /// True when the provider did not supply a billing cycle start date and a 30-day fallback was used.
    var isFallbackPeriod: Bool
    var totalTokens: Int64
    var inputTokens: Int64?
    var cacheWriteTokens: Int64?
    var cacheReadTokens: Int64?
    var outputTokens: Int64?
    var totalCents: Double?
    /// Models sorted largest `totalTokens` first, then lexicographically by name.
    var models: [TokenUsageModel]
    var fetchedAt: String
    /// True when fallback event pagination stopped at the safety cap before reading all events.
    var isPartial: Bool? = nil

    var periodStartDate: Date? { periodStart.flatMap(QuotaDate.parse) }
    var periodEndDate: Date? { periodEnd.flatMap(QuotaDate.parse) }
    var fetchedDate: Date? { QuotaDate.parse(fetchedAt) }
}

/// Non-PII reason why the latest token usage request failed while quota figures remained unaffected.
enum TokenUsageProblem: Error, Codable, Equatable, Hashable {
    case unauthorized(Int)
    case rateLimited
    case badFormat
    case offline
    case timedOut
    case server(Int)

    var message: String {
        switch self {
        case .unauthorized(let code):
            return "暫時無法更新 Token 資料（HTTP \(code)）"
        case .rateLimited:
            return "請求過多，暫停更新 Token 資料"
        case .badFormat:
            return "Token 回應格式已變更，暫時無法讀取"
        case .offline:
            return "無法連線以更新 Token 資料"
        case .timedOut:
            return "連線逾時，暫時無法更新 Token 資料"
        case .server(let code):
            return "暫時無法更新 Token 資料（HTTP \(code)）"
        }
    }
}
