import SwiftUI

/// Picks the layout from the screen the app is on.
///
/// - Folded (outer screen, or any phone-sized window): one column. The list
///   pushes the detail screen, with the standard back button and edge swipe.
/// - Unfolded (inner screen, both sides at least 600 pt): two panes that meet
///   exactly at the middle of the display, where the fold is. Held as a book
///   (wider than tall) the panes sit left and right; turned upright they sit
///   above and below, so nothing is ever drawn across the crease.
struct RootView: View {
    @Bindable var store: QuotaStore

    static let unfoldedMinSide: CGFloat = 600

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if min(size.width, size.height) >= Self.unfoldedMinSide {
                DualScreenView(store: store, size: size)
            } else {
                SingleScreenView(store: store)
                    .frame(width: size.width, height: size.height)
            }
        }
        // Measure the whole display so the split lands on the physical fold;
        // each pane still keeps its own content inside the safe area.
        .ignoresSafeArea()
    }
}

struct SingleScreenView: View {
    @Bindable var store: QuotaStore
    @State private var path: [ProviderQuota.ID] = []

    var body: some View {
        NavigationStack(path: $path) {
            QuotaListView(store: store, style: .push)
                .navigationDestination(for: ProviderQuota.ID.self) { id in
                    QuotaDetailContainer(store: store, id: id)
                }
        }
        .onAppear {
            // Coming from the unfolded layout: keep the platform that was open.
            if let id = store.selectedID, path.isEmpty { path = [id] }
        }
        .onChange(of: path) { _, newPath in
            store.selectedID = newPath.last
        }
    }
}

struct DualScreenView: View {
    @Bindable var store: QuotaStore
    let size: CGSize

    private var sideBySide: Bool { size.width >= size.height }

    var body: some View {
        let layout = sideBySide
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))

        layout {
            NavigationStack {
                QuotaListView(store: store, style: .select)
            }
            .frame(width: sideBySide ? size.width / 2 : size.width,
                   height: sideBySide ? size.height : size.height / 2)

            NavigationStack {
                if let id = store.selectedID {
                    QuotaDetailContainer(store: store, id: id)
                } else {
                    ContentUnavailableView(
                        "選擇一個平台",
                        systemImage: "rectangle.righthalf.inset.filled",
                        description: Text("在另一側的清單點選平台，詳細額度會顯示在這一側。")
                    )
                }
            }
            .frame(width: sideBySide ? size.width / 2 : size.width,
                   height: sideBySide ? size.height : size.height / 2)
        }
        .frame(width: size.width, height: size.height)
        .onAppear {
            // Unfolding shows the most urgent platform right away.
            if store.selectedID == nil { store.selectedID = store.displayItems.first?.id }
        }
    }
}
