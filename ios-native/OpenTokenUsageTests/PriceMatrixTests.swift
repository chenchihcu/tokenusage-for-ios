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
    func testHeadlineBarIsTheDearestModelAgainstTheDearestVendor() {
        let models = [
            CatalogModel(id: "opus", vendor: .anthropic, inputPerMillion: 15),
            CatalogModel(id: "haiku", vendor: .anthropic, inputPerMillion: 1),
            CatalogModel(id: "gpt", vendor: .openai, inputPerMillion: 5),
            CatalogModel(id: "gemini", vendor: .google, inputPerMillion: 1.25),
        ]
        let lines = PriceBoard.headlines(models)
        XCTAssertEqual(lines.map(\.modelId), ["opus", "gpt", "gemini"])
        XCTAssertEqual(lines[0].fraction, 1, accuracy: 0.0001)
        XCTAssertEqual(lines[1].fraction, 5.0 / 15, accuracy: 0.0001)
        XCTAssertEqual(lines[2].fraction, 1.25 / 15, accuracy: 0.0001)
        XCTAssertEqual(PriceBoard.lines(for: .anthropic, in: models).map(\.modelId), ["opus", "haiku"])
        XCTAssertEqual(PriceBoard.lines(for: .anthropic, in: models).first?.fraction, 1)
    }

    func testSearchReplacesTheBoardAndStopsAtSix() {
        let models = (0..<8).map { CatalogModel(id: "m\($0)", vendor: .openai, inputPerMillion: Double($0 + 1)) }
        XCTAssertEqual(PriceBoard.search("m", in: models).count, 6)
        XCTAssertEqual(PriceBoard.search("m", in: models).first?.modelId, "m7")
    }

    func testResetCountIsBlankUnlessTheVendorReportsOne() {
        let codex = QuotaAssembly.make(id: "codex", name: "Codex", plan: "Plus", pools: [],
                                        metrics: [QuotaMetric(label: "Resets", value: "2 available")], now: Date())
        let cursor = QuotaAssembly.make(id: "cursor", name: "Cursor", plan: "Pro", pools: [], metrics: [], now: Date())
        XCTAssertEqual(ResetBoard.creditText(codex), "2")
        XCTAssertNil(ResetBoard.creditText(cursor))
        XCTAssertNil(ResetBoard.creditText(nil))
    }

    func testPricesUseABareDollarSign() {
        XCTAssertEqual(MatrixColumn.price(3), "$3.00")
        XCTAssertEqual(MatrixColumn.price(0.075), "$0.075")
    }
}
