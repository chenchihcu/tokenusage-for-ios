import XCTest
@testable import OpenTokenUsage

/// Every release: the version and the settings shown in the iOS Settings app (Settings.bundle)
/// must match the app itself. These tests fail when one side is changed without the other.
final class SettingsAlignmentTests: XCTestCase {
    private var rootPlist: [[String: Any]] {
        guard let url = Bundle.main.url(forResource: "Root", withExtension: "plist", subdirectory: "Settings.bundle"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let specs = plist["PreferenceSpecifiers"] as? [[String: Any]] else {
            XCTFail("Settings.bundle/Root.plist missing from the app bundle")
            return []
        }
        return specs
    }

    private func spec(_ key: String) -> [String: Any]? { rootPlist.first { $0["Key"] as? String == key } }

    func testVersionIsTheReleaseVersionNotTheTemplateDefault() {
        let text = AppSettings.versionText()
        XCTAssertNotNil(text.range(of: #"^\d+\.\d+\.\d+ \(\d+\)$"#, options: .regularExpression), text)
        XCTAssertFalse(text.hasPrefix("1.0 "), "Info.plist still has the template 1.0")
    }

    func testWidgetExtensionHasTheSameVersionAsTheApp() throws {
        let appex = try XCTUnwrap(Bundle.main.builtInPlugInsURL?.appending(path: "OpenTokenUsageWidget.appex"))
        let widget = try XCTUnwrap(Bundle(url: appex))
        XCTAssertEqual(AppSettings.versionText(widget), AppSettings.versionText())
    }

    func testSettingsAppShowsTheInstalledVersion() throws {
        XCTAssertEqual(spec(SettingsKey.appVersion)?["Type"] as? String, "PSTitleValueSpecifier")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SettingsAlignmentTests"))
        defer { defaults.removePersistentDomain(forName: "SettingsAlignmentTests") }
        AppSettings.publishVersion(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: SettingsKey.appVersion), AppSettings.versionText())
    }

    func testSettingsAppKeysAreKnownToTheApp() {
        let known: Set<String> = [SettingsKey.refreshInterval, SettingsKey.haptics, SettingsKey.sampleData,
                                  SettingsKey.catalogSchedule, SettingsKey.appVersion]
        for key in rootPlist.compactMap({ $0["Key"] as? String }) {
            XCTAssertTrue(known.contains(key), "Settings.bundle key \(key) is not a SettingsKey")
        }
    }

    func testSettingsAppDefaultsMatchTheApp() {
        let defaults = UserDefaults.standard
        AppSettings.registerDefaults()
        XCTAssertEqual(spec(SettingsKey.refreshInterval)?["DefaultValue"] as? Int,
                       defaults.volatileDomain(forName: UserDefaults.registrationDomain)[SettingsKey.refreshInterval] as? Int)
        XCTAssertEqual(spec(SettingsKey.haptics)?["DefaultValue"] as? Bool,
                       defaults.volatileDomain(forName: UserDefaults.registrationDomain)[SettingsKey.haptics] as? Bool)
    }

    func testRefreshChoicesMatchTheInAppPicker() {
        let refresh = spec(SettingsKey.refreshInterval)
        XCTAssertEqual(refresh?["Values"] as? [Int], AppSettings.intervalOptions.map(\.seconds))
        XCTAssertEqual(refresh?["Titles"] as? [String], AppSettings.intervalOptions.map(\.title))
    }
}
