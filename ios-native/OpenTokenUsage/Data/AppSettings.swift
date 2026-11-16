import Foundation

/// Keys shared with the iOS Settings app (Settings.bundle) and the in-app sheet.
enum SettingsKey {
    static let refreshInterval = "opentokenusage_refresh_interval"
    static let smartAutoReset = "opentokenusage_smart_autoreset"
    static let haptics = "opentokenusage_haptics_enabled"
    static let apiBaseURL = "opentokenusage_api_base_url"
}

enum AppSettings {
    static let defaultBaseURL = "https://opentokenusage-web.chihfu-chen-tw.workers.dev"

    /// Settings.bundle defaults are not applied until registered.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.refreshInterval: 60,
            SettingsKey.smartAutoReset: true,
            SettingsKey.haptics: true,
            SettingsKey.apiBaseURL: defaultBaseURL,
        ])
    }

    static var baseURL: URL {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.apiBaseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let url = URL(string: raw), url.scheme == "https", url.host() != nil { return url }
        return URL(string: defaultBaseURL)!
    }

    struct IntervalOption: Identifiable, Hashable {
        let seconds: Int
        let title: String
        var id: Int { seconds }
    }

    static let intervalOptions: [IntervalOption] = [
        .init(seconds: 15, title: "15 秒"),
        .init(seconds: 30, title: "30 秒"),
        .init(seconds: 60, title: "1 分鐘"),
        .init(seconds: 300, title: "5 分鐘"),
        .init(seconds: 900, title: "15 分鐘"),
        .init(seconds: 0, title: "僅手動"),
    ]
}
