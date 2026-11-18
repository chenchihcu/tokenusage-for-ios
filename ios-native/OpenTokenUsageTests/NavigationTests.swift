import XCTest
@testable import OpenTokenUsage

@MainActor
final class NavigationTests: XCTestCase {
    func testRetappingQuotasWhenFoldedReturnsToTheList() {
        let store = QuotaStore()
        store.selectedID = "codex"
        store.returnToStart(.quotas, compact: true)
        XCTAssertNil(store.selectedID)                       // detail closed, list shown
        XCTAssertEqual(store.scrollToTop[.quotas], 1)
    }

    func testRetappingQuotasWhenUnfoldedKeepsTheDetailPane() {
        let store = QuotaStore()
        store.selectedID = "codex"
        store.returnToStart(.quotas, compact: false)
        XCTAssertEqual(store.selectedID, "codex")
        XCTAssertEqual(store.scrollToTop[.quotas], 1)
    }

    func testRetappingOtherTabsOnlyScrollsThem() {
        let store = QuotaStore()
        store.selectedID = "claude"
        store.returnToStart(.analytics, compact: true)
        store.returnToStart(.analytics, compact: true)
        XCTAssertEqual(store.selectedID, "claude")
        XCTAssertEqual(store.scrollToTop[.analytics], 2)
        XCTAssertNil(store.scrollToTop[.settings])
    }
}
