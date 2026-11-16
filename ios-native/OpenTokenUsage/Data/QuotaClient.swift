import Foundation

enum QuotaClientError: LocalizedError, Equatable {
    case offline
    case timedOut
    case server(status: Int)
    case badResponse
    case notConfigured
    case unauthorized(provider: String)

    var errorDescription: String? {
        switch self {
        case .offline: return "目前沒有網路連線"
        case .timedOut: return "連線逾時"
        case .server(let status): return "伺服器錯誤（\(status)）"
        case .badResponse: return "收到無法辨識的資料"
        case .notConfigured: return "尚未設定帳號權杖"
        case .unauthorized(let provider): return "\(provider) 的權杖已失效"
        }
    }

    /// What the person can do about it.
    var hint: String {
        switch self {
        case .notConfigured: return "到設定貼上至少一個平台的權杖。"
        case .unauthorized: return "到設定重新貼上新的權杖。"
        default: return "請稍後再試。"
        }
    }
}

/// Asks each provider directly from the phone. No relay server in between.
struct QuotaClient {
    struct Result {
        var items: [ProviderQuota]
        var firstError: QuotaClientError?
    }

    var session: URLSession = .shared

    /// Providers that fail keep their previous row, so one expired token
    /// does not blank the whole list.
    func fetchQuotas(previous: [ProviderQuota]) async throws -> Result {
        if UserDefaults.standard.bool(forKey: SettingsKey.sampleData) {
            return Result(items: SampleData.items(), firstError: nil)
        }
        let configured = DirectProvider.allCases.compactMap { provider in
            provider.token.map { (provider, $0) }
        }
        guard !configured.isEmpty else { throw QuotaClientError.notConfigured }

        var items: [ProviderQuota] = []
        var firstError: QuotaClientError?
        await withTaskGroup(of: (DirectProvider, Swift.Result<ProviderQuota, QuotaClientError>).self) { group in
            for (provider, token) in configured {
                group.addTask { (provider, await self.fetch(provider, token: token)) }
            }
            for await (provider, outcome) in group {
                switch outcome {
                case .success(let quota):
                    items.append(quota)
                case .failure(let error):
                    if firstError == nil { firstError = error }
                    if let old = previous.first(where: { $0.providerId == provider.rawValue }) {
                        items.append(old)
                    }
                }
            }
        }
        if items.isEmpty, let firstError { throw firstError }
        return Result(items: items, firstError: firstError)
    }

    private func fetch(_ provider: DirectProvider, token: String) async -> Swift.Result<ProviderQuota, QuotaClientError> {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: provider.request(token: token))
        } catch let error as URLError where error.code == .timedOut {
            return .failure(.timedOut)
        } catch {
            return .failure(.offline)
        }
        guard let http = response as? HTTPURLResponse else { return .failure(.badResponse) }
        if http.statusCode == 401 || http.statusCode == 403 {
            return .failure(.unauthorized(provider: provider.name))
        }
        guard (200..<300).contains(http.statusCode) else {
            return .failure(.server(status: http.statusCode))
        }
        guard let quota = provider.parse(data) else { return .failure(.badResponse) }
        return .success(quota)
    }
}

/// Last successful response on disk, so the app opens with data even offline.
enum QuotaCache {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "quotas-v1.json")
    }

    struct Snapshot: Codable {
        var savedAt: Date
        var items: [ProviderQuota]
    }

    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ items: [ProviderQuota], at date: Date = Date()) {
        guard let data = try? JSONEncoder().encode(Snapshot(savedAt: date, items: items)) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
