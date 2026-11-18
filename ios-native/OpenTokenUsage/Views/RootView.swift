import SwiftUI

/// The app's main pages in one standard tab bar (FR-39), so any page is one tap away and none
/// needs a close button. On iPhone Duo the system places the bar for each display and pose
/// (Apple HIG, Designing for iPhone Duo › Vertical controls); folding or unfolding keeps the
/// current tab, the selected platform, the scroll position and any open sheet (FR-29).
struct RootView: View {
    @Bindable var store: QuotaStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Tapping the tab you are already on is the way home: it returns that page to its start.
    private var tabSelection: Binding<QuotaStore.Tab> {
        Binding {
            store.selectedTab
        } set: { tab in
            if tab == store.selectedTab {
                store.returnToStart(tab, compact: sizeClass == .compact)
            }
            store.selectedTab = tab
        }
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("額度", systemImage: "gauge.with.dots.needle.50percent", value: QuotaStore.Tab.quotas) {
                QuotasSplitView(store: store)
            }
            Tab("分析", systemImage: "chart.xyaxis.line", value: QuotaStore.Tab.analytics) {
                AnalyticsView(history: store.displayHistory, items: store.displayItems,
                              scrollToTopToken: store.scrollToTop[.analytics, default: 0])
            }
            Tab("模型與費用", systemImage: "dollarsign.circle", value: QuotaStore.Tab.catalog) {
                ModelCatalogView(store: store)
            }
            Tab("設定", systemImage: "gearshape", value: QuotaStore.Tab.settings) {
                SettingsView(scrollToTopToken: store.scrollToTop[.settings, default: 0])
                    // Sign-in or token changes take effect as soon as you leave Settings.
                    .onDisappear { Task { await store.refresh(force: true) } }
            }
        }
        .sheet(item: $store.presentedSheet) { sheet in
            switch sheet {
            case .resets:
                ResetsView(store: store)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationRouter.openResets)) { _ in
            // A free-reset notification opens the resets sheet over the quotas page.
            store.selectedTab = .quotas
            store.presentedSheet = .resets
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationRouter.openQuotas)) { _ in
            // A quota warning opens the 額度 page (FR-A16).
            store.selectedTab = .quotas
        }
    }
}

/// The quotas page: a standard split view. On the outer display (compact width) it collapses to
/// the list, which pushes the detail screen; on the inner display list and detail sit side by
/// side and the system fits the columns to the fold.
private struct QuotasSplitView: View {
    @Bindable var store: QuotaStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationSplitView {
            QuotaListView(store: store)
        } detail: {
            if let id = store.selectedID {
                QuotaDetailContainer(store: store, id: id)
            } else {
                ContentUnavailableView(
                    "選擇一個平台",
                    systemImage: "sidebar.leading",
                    description: Text("在清單點選平台，詳細額度會顯示在這裡。")
                )
            }
        }
        .onChange(of: sizeClass, initial: true) { _, newValue in
            // Unfolding shows the most urgent platform right away instead of an empty pane.
            if newValue == .regular, store.selectedID == nil {
                store.selectedID = store.displayItems.first?.id
            }
        }
    }
}
