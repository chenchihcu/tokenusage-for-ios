import Foundation

enum QuotaClientError: LocalizedError, Equatable {
    case offline
    case timedOut
    case server(status: Int)
    case badResponse
    case notConfigured
    case unauthorized(provider: String)
    case rateLimited(provider: String)
    /// The Worker answered, but the Mac has not relayed Antigravity figures to it.
    case relayEmpty

    var errorDescription: String? {
        switch self {
        case .offline: return "目前沒有網路連線"
        case .timedOut: return "連線逾時"
        case .server(let status): return "伺服器錯誤（\(status)）"
        case .badResponse: return "收到無法辨識的資料"
        case .notConfigured: return "尚未登入任何服務"
        case .unauthorized(let provider): return "\(provider) 需要重新登入"
        case .rateLimited(let provider): return "\(provider) 暫時限制查詢"
        case .relayEmpty: return "Mac 尚未轉送 Antigravity 資料"
        }
    }

    /// What the person can do about it.
    var hint: String {
        switch self {
        case .notConfigured: return "到設定登入至少一個服務。"
        case .unauthorized: return "到設定重新登入這個服務。"
        case .rateLimited: return "稍後會自動再試，目前顯示上次的資料。"
        case .relayEmpty: return "在 Mac 執行轉送程式，並確認 CodexBar 讀得到 Antigravity。"
        default: return "請稍後再試。"
        }
    }
}

extension QuotaClientError {
    /// What one provider's row says about this failure (FR-4).
    var providerProblem: ProviderProblem {
        switch self {
        case .unauthorized, .notConfigured: return .signIn
        case .rateLimited: return .rateLimited
        case .badResponse: return .badFormat
        case .offline: return .offline
        case .timedOut: return .timedOut
        case .server(let status): return .server(status)
        case .relayEmpty: return .relayEmpty
        }
    }
}

/// Asks each provider directly from the phone. No relay server in between.
struct QuotaClient {
    struct Result {
        var items: [ProviderQuota]
        var firstError: QuotaClientError?
        /// Providers actually asked this round.
        var asked: Set<DirectProvider> = []
        /// Seconds the provider asked us to wait (HTTP 429 Retry-After).
        var retryAfter: [DirectProvider: TimeInterval] = [:]
        /// Providers that answered with usage we could read this round.
        var succeeded: Set<DirectProvider> = []
        /// Why each failed provider failed this round (FR-1).
        var errors: [DirectProvider: QuotaClientError] = [:]
        /// Providers whose secondary token usage request succeeded this round.
        var tokenSucceeded: Set<DirectProvider> = []
        /// Non-PII reason why a provider's token usage request failed (independent of quota status).
        var tokenProblems: [DirectProvider: TokenUsageProblem] = [:]
    }

    enum Outcome {
        case success(ProviderQuota, tokenSucceeded: Bool = false, tokenProblem: TokenUsageProblem? = nil)
        case failure(QuotaClientError, retryAfter: TimeInterval?)
    }

    var session: URLSession = .shared

    /// Providers that fail, or are skipped this round, keep their previous row,
    /// so one expired token or a rate limit does not blank the whole list.
    func fetchQuotas(previous: [ProviderQuota], skipping: Set<DirectProvider> = []) async throws -> Result {
        // Renews tokens that are about to expire before asking for usage.
        var configured: [(DirectProvider, String)] = []
        for provider in DirectProvider.allCases where !skipping.contains(provider) || provider.isSignedIn {
            if skipping.contains(provider) {
                configured.append((provider, ""))
            } else if let token = await SignInService.validToken(for: provider) {
                configured.append((provider, token))
            }
        }
        guard !configured.isEmpty else { throw QuotaClientError.notConfigured }

        var result = Result(items: [], firstError: nil)
        func keepPrevious(_ provider: DirectProvider) {
            if let old = previous.first(where: { $0.providerId == provider.rawValue }) {
                result.items.append(old)
            }
        }
        for (provider, _) in configured where skipping.contains(provider) { keepPrevious(provider) }

        await withTaskGroup(of: (DirectProvider, Outcome).self) { group in
            for (provider, token) in configured where !skipping.contains(provider) {
                let prev = previous.first { $0.providerId == provider.rawValue }
                group.addTask { (provider, await self.fetch(provider, token: token, previous: prev)) }
            }
            for await (provider, outcome) in group {
                result.asked.insert(provider)
                switch outcome {
                case .success(let quota, let tokenSucceeded, let tokenProblem):
                    result.items.append(quota)
                    result.succeeded.insert(provider)
                    if tokenSucceeded { result.tokenSucceeded.insert(provider) }
                    if let tokenProblem { result.tokenProblems[provider] = tokenProblem }
                case .failure(let error, let retryAfter):
                    if result.firstError == nil { result.firstError = error }
                    result.errors[provider] = error
                    if let retryAfter { result.retryAfter[provider] = retryAfter }
                    keepPrevious(provider)
                }
            }
        }
        if result.items.isEmpty, let error = result.firstError { throw error }
        return result
    }

    func fetch(_ provider: DirectProvider, token: String, previous: ProviderQuota? = nil) async -> Outcome {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: provider.request(token: token))
        } catch let error as URLError where error.code == .timedOut {
            return .failure(.timedOut, retryAfter: nil)
        } catch {
            return .failure(.offline, retryAfter: nil)
        }
        guard let http = response as? HTTPURLResponse else { return .failure(.badResponse, retryAfter: nil) }
        if http.statusCode == 401 || http.statusCode == 403 {
            return .failure(.unauthorized(provider: provider.name), retryAfter: nil)
        }
        if http.statusCode == 429 {
            let seconds = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            return .failure(.rateLimited(provider: provider.name), retryAfter: seconds ?? 600)
        }
        guard (200..<300).contains(http.statusCode) else {
            return .failure(.server(status: http.statusCode), retryAfter: nil)
        }
        if provider.isRelayed, AntigravityRelay.read(data) == .nothingRelayed {
            return .failure(.relayEmpty, retryAfter: nil)
        }
        guard var quota = provider.parse(data) else { return .failure(.badResponse, retryAfter: nil) }

        if provider == .cursor {
            let cycle: (start: Date?, end: Date?)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                cycle = QuotaParser.cursorCycle(json)
            } else {
                cycle = (nil, nil)
            }
            switch await CursorTokenSource.fetch(token: token, cycleStart: cycle.start, cycleEnd: cycle.end, session: session) {
            case .success(let summary):
                quota.tokenUsage = summary
                return .success(quota, tokenSucceeded: true, tokenProblem: nil)
            case .failure(let problem):
                // TR-6: quota still succeeds; keep the last saved token figures with their data time.
                quota.tokenUsage = previous?.tokenUsage
                return .success(quota, tokenSucceeded: false, tokenProblem: problem)
            }
        }
        return .success(quota)
    }
}
