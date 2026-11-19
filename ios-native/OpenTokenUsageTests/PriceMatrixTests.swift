import XCTest
@testable import OpenTokenUsage

final class PriceMatrixTests: XCTestCase {
    private let models = [
        CatalogModel(id: "a-model", vendor: .openai, inputPerMillion: 3, outputPerMillion: 15, contextTokens: 200_000),
        CatalogModel(id: "b-model", vendor: .openai, inputPerMillion: 0.25, outputPerMillion: 2),
        CatalogModel(id: "c-model", vendor: .openai, inputPerMillion: nil, contextTokens: 1_048_576),
    ]

    func testDefaultKeepsNewestNamesFirst() {
        XCTAssertEqual(MatrixSort().apply(models).map(\.id), ["c-model", "b-model", "a-model"])
    }

    func testTappingAColumnSortsCheapestFirstAndMissingLast() {
        var sort = MatrixSort()
        sort.tap(.input)
        XCTAssertEqual(sort.apply(models).map(\.id), ["b-model", "a-model", "c-model"])
        sort.tap(.input)
        XCTAssertEqual(sort.apply(models).map(\.id), ["a-model", "b-model", "c-model"])
    }

    func testCellText() {
        XCTAssertEqual(MatrixColumn.context.text(models[0]), "200K")
        XCTAssertEqual(MatrixColumn.context.text(models[2]), "1M")
        XCTAssertEqual(MatrixColumn.context.text(models[1]), "—")
        XCTAssertEqual(MatrixColumn.tokens(2_000_000), "2M")
        XCTAssertEqual(MatrixColumn.tokens(1_500_000), "1.5M")
    }
}

extension PriceMatrixTests {
    func testPricesUseABareDollarSign() {
        XCTAssertEqual(MatrixColumn.price(3), "$3.00")
        XCTAssertEqual(MatrixColumn.price(0.075), "$0.075")
    }
}
