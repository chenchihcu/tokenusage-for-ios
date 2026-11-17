import SwiftUI

@main
struct OpenTokenUsageApp: App {
    @State private var store: QuotaStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = 60

    init() {
        AppSettings.registerDefaults()
        _store = State(initialValue: QuotaStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Poll only while on screen: no background network use.
                    if phase == .active { store.startAutoRefresh() } else { store.stopAutoRefresh() }
                }
                .onChange(of: refreshInterval) {
                    if scenePhase == .active { store.startAutoRefresh() }
                }
        }
    }
}
