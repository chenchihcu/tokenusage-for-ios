import SwiftUI

/// Scrolls a page's list back to the top whenever `token` changes (tapping its tab again).
private struct ScrollToTopOnRetap: ViewModifier {
    let token: Int
    @State private var position = ScrollPosition(edge: .top)

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onChange(of: token) {
                withAnimation { position.scrollTo(edge: .top) }
            }
    }
}

extension View {
    func scrollsToTop(on token: Int) -> some View {
        modifier(ScrollToTopOnRetap(token: token))
    }
}
