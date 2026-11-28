import Foundation

/// Why one provider's last refresh failed (spec-competitive-gap-v3.1.md, FR-4).
/// Kept apart from `QuotaClientError` so the widget extension can read it too.
enum ProviderProblem: Codable, Equatable, Hashable {
    case signIn
    case rateLimited
    case badFormat
    case offline
    case timedOut
    case server(Int)
    /// Google Antigravity (relayed by the person's Mac): nothing relayed yet.
    case relayEmpty
    /// Google Antigravity: the Mac's latest figures are over an hour old.
    case relayStale

    /// FR-4 wording. `retryAt` is only used for a rate limit.
    func message(retryAt: Date?, now: Date = Date()) -> String {
        switch self {
        case .signIn: return "需要重新登入"
        case .rateLimited:
            let minutes = retryAt.map { max(1, Int(($0.timeIntervalSince(now) / 60).rounded(.up))) } ?? 10
            return "請求過多，\(minutes) 分鐘後再試"
        case .badFormat: return "服務回應格式改變，暫時無法讀取"
        case .offline: return "沒有網路"
        case .timedOut: return "連線逾時"
        case .server(let code): return "服務暫時出錯（\(code)）"
        case .relayEmpty: return "Mac 尚未轉送資料"
        case .relayStale: return "Mac 超過 1 小時未轉送"
        }
    }
}

/// One provider's refresh outcome (FR-1).
struct ProviderStatus: Codable, Equatable {
    /// Last time this provider answered with usage we could read.
    var lastSuccess: Date?
    /// Set when the latest attempt failed; cleared by the next success.
    var problem: ProviderProblem?
    /// When a 429 back-off ends.
    var retryAt: Date?
    /// Non-PII reason why the latest token usage request failed; independent of quota `problem`.
    var tokenProblem: TokenUsageProblem? = nil
}

/// Per-provider status on disk in the App Group, so it survives launches and the widget can
/// read it (FR-2).
enum ProviderStatusStore {
    private static let key = "opentokenusage_provider_status_v1"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: QuotaCache.appGroup) ?? .standard
    }

    static func load() -> [String: ProviderStatus] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: ProviderStatus].self, from: data)) ?? [:]
    }

    static func save(_ status: [String: ProviderStatus]) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        defaults.set(data, forKey: key)
    }
}
