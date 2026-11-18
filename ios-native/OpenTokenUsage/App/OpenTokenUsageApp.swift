import BackgroundTasks
import SwiftUI
import UserNotifications

@main
struct OpenTokenUsageApp: App {
    @State private var store: QuotaStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = 60

    init() {
        AppSettings.registerDefaults()
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        _store = State(initialValue: QuotaStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Poll only while on screen: no background network use.
                    if phase == .active {
                        store.startAutoRefresh()
                    } else {
                        store.stopAutoRefresh()
                        if phase == .background { BackgroundRefresh.schedule() }
                    }
                }
                .onChange(of: refreshInterval) {
                    if scenePhase == .active { store.startAutoRefresh() }
                }
        }
        // iOS decides when this runs (FR-11). It refreshes once and asks for the next slot.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            BackgroundRefresh.schedule()
            await store.refresh()
        }
    }
}
