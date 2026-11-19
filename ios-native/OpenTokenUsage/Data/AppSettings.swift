import Foundation

/// Keys shared with the iOS Settings app (Settings.bundle) and the in-app sheet.
enum SettingsKey {
    static let refreshInterval = "opentokenusage_refresh_interval"
    static let haptics = "opentokenusage_haptics_enabled"
    static let sampleData = "opentokenusage_sample_data"
    static let catalogSchedule = "opentokenusage_catalog_schedule"
    /// Read-only 版本 row in the iOS Settings app (Settings.bundle), written at launch.
    static let appVersion = "opentokenusage_app_version"
}

enum AppSettings {
    /// Settings.bundle defaults are not applied until registered.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.refreshInterval: 60,
            SettingsKey.haptics: true,
            SettingsKey.sampleData: false,
            SettingsKey.catalogSchedule: ModelCatalog.Schedule.weekly.rawValue,
        ])
        publishVersion()
    }

    /// 「3.1.0 (1)」 from the bundle, the one place the version is read; shown in the app's
    /// 設定 › 版本 and in the iOS Settings app, so both always match the installed build.
    static func versionText(_ bundle: Bundle = .main) -> String {
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    /// Settings.bundle can't read the bundle version itself, so the app writes it on every launch.
    static func publishVersion(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        defaults.set(versionText(bundle), forKey: SettingsKey.appVersion)
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
