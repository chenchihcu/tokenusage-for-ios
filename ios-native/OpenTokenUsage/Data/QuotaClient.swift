import Foundation

enum QuotaClientError: LocalizedError, Equatable {
    case offline
    case timedOut
    case server(status: Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .offline: return "目前沒有網路連線"
        case .timedOut: return "連線逾時"
        case .server(let status): return "伺服器錯誤（\(status)）"
        case .badResponse: return "收到無法辨識的資料"
        }
    }
}

/// Talks to the Cloudflare Worker. Uses ETag so unchanged data costs no body.
actor QuotaClient {
    private let session: URLSession
    private var etag: String?
    private var lastGood: [ProviderQuota]?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchQuotas(baseURL: URL) async throws -> [ProviderQuota] {
        var request = URLRequest(url: baseURL.appending(path: "api/quotas"))
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag, lastGood != nil { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                 .internationalRoamingOff, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw QuotaClientError.offline
            case .timedOut:
                throw QuotaClientError.timedOut
            default:
                throw QuotaClientError.offline
            }
        }

        guard let http = response as? HTTPURLResponse else { throw QuotaClientError.badResponse }
        if http.statusCode == 304, let lastGood { return lastGood }
        guard (200..<300).contains(http.statusCode) else {
            throw QuotaClientError.server(status: http.statusCode)
        }
        guard let envelope = try? JSONDecoder().decode(QuotaEnvelope.self, from: data),
              envelope.success, let items = envelope.data else {
            throw QuotaClientError.badResponse
        }
        etag = http.value(forHTTPHeaderField: "ETag")
        lastGood = items
        return items
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
