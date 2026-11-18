import Foundation

/// Last successful response on disk, so the app opens with data even offline.
/// Stored in the App Group container when available, so the widget can read it;
/// falls back to the app's own folder (the widget then shows 「開啟 App 以更新」).
enum QuotaCache {
    static let appGroup = "group.com.chihfu.opentokenusage"

    private static var url: URL {
        let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        let dir = shared ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
