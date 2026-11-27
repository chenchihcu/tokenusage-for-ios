import SwiftUI
import UIKit

/// Models per agent with their list API prices (FR-36, FR-37).
struct ModelCatalogView: View {
    let store: QuotaStore
    @State private var search = ""
    /// Nil is the three-vendor board. Cursor opens that board with a shared-price note.
    @State private var vendor: CatalogModel.Vendor?
    @State private var showsCursor = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var catalog: ModelCatalog { store.catalog }

    var body: some View {
        let models = catalog.activeModels()
        NavigationStack {
            List {
                agentRow
                if showsCursor, vendor == nil {
                    Text("跟這三家同一套牌價")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if models.isEmpty {
                    Button("立即下載") { Task { await store.refreshCatalogIfDue(force: true) } }
                        .disabled(store.isUpdatingCatalog)
                } else if !search.isEmpty {
                    let lines = vendor.map { PriceBoard.lines(for: $0, in: models, matching: search) }
                        ?? PriceBoard.search(search, in: models)
                    ForEach(lines) { line in
                        priceLine(line)
                    }
                } else if let vendor {
                    ForEach(PriceBoard.lines(for: vendor, in: models)) { line in
                        priceLine(line)
                    }
                } else {
                    ForEach(PriceBoard.headlines(models)) { line in
                        priceLine(line)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDisabled(!typeSize.isAccessibilitySize && search.isEmpty)
            .scrollsToTop(on: store.scrollToTop[.catalog, default: 0])
            .searchable(text: $search, prompt: "搜尋模型")
            .navigationTitle("模型與費用")
        }
    }

    private var agentRow: some View {
        HStack {
            ForEach(DirectProvider.allCases) { provider in
                Button {
                    search = ""
                    if provider == .cursor {
                        vendor = nil
                        showsCursor = true
                    } else if let match = Self.vendor(for: provider) {
                        vendor = vendor == match && !showsCursor ? nil : match
                        showsCursor = false
                    }
                } label: {
                    ProviderBadge(id: provider.rawValue, name: provider.name, base: 32)
                        .opacity(isOn(provider) ? 1 : 0.35)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(provider.name)
                Spacer(minLength: 0)
            }
        }
    }

    private static func vendor(for provider: DirectProvider) -> CatalogModel.Vendor? {
        switch provider {
        case .claude: return .anthropic
        case .codex: return .openai
        case .antigravity: return .google
        case .cursor: return nil
        }
    }

    private func isOn(_ provider: DirectProvider) -> Bool {
        if vendor == nil, !showsCursor { return true }
        if provider == .cursor { return showsCursor }
        guard let vendor else { return false }
        switch provider {
        case .claude: return vendor == .anthropic
        case .codex: return vendor == .openai
        case .antigravity: return vendor == .google
        case .cursor: return false
        }
    }

    private func priceLine(_ line: PriceBoard.Line) -> some View {
        HStack(spacing: 8) {
            Text(line.modelId)
                .font(.subheadline)
                .lineLimit(1)
            ProgressView(value: line.fraction)
                .tint(Color.accentColor)
            Text(line.inputPerMillion, format: .currency(code: "USD").precision(.fractionLength(line.inputPerMillion < 1 ? 2 : 0)))
                .font(.body.monospacedDigit())
                .frame(minWidth: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

}


/// The matrix's columns: the model, then one column per figure.
enum MatrixColumn: String, CaseIterable, Identifiable {
    case model, input, output, cacheRead, context
    var id: String { rawValue }

    var title: String {
        switch self {
        case .model: return "模型"
        case .input: return "輸入"
        case .output: return "輸出"
        case .cacheRead: return "快取讀取"
        case .context: return "上下文"
        }
    }

    static let figures: [MatrixColumn] = [.input, .output, .cacheRead, .context]

    func number(_ model: CatalogModel) -> Double? {
        switch self {
        case .model: return nil
        case .input: return model.inputPerMillion
        case .output: return model.outputPerMillion
        case .cacheRead: return model.cacheReadPerMillion
        case .context: return model.contextTokens.map(Double.init)
        }
    }

    func text(_ model: CatalogModel) -> String {
        switch self {
        case .model: return model.id
        case .context: return model.contextTokens.map(Self.tokens) ?? "—"
        default: return number(model).map(Self.price) ?? "—"
        }
    }

    static func price(_ value: Double) -> String {
        // A bare "$": the section already says the figures are US dollars, and the locale's
        // "US$" would cost a column on the iPhone Duo's outer display.
        "$" + value.formatted(.number.grouping(.never).precision(.fractionLength(value < 1 ? 3 : 2)))
    }

    /// 200000 → "200K", 1048576 → "1M", 2000000 → "2M".
    static func tokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            let millions = (Double(count) / 1_000_000 * 10).rounded() / 10
            return millions.formatted(.number.precision(.fractionLength(0...1))) + "M"
        }
        return "\(count / 1000)K"
    }
}

/// Which column the matrix is sorted by. Models without the figure always sort last.
/// The default keeps the catalog's order: newest model names first.
struct MatrixSort: Equatable {
    var column: MatrixColumn = .model
    var ascending = false

    /// Tapping the sorted column flips the order; another column starts from smallest.
    mutating func tap(_ tapped: MatrixColumn) {
        if tapped == column {
            ascending.toggle()
        } else {
            column = tapped
            ascending = true
        }
    }

    func apply(_ models: [CatalogModel]) -> [CatalogModel] {
        models.sorted { a, b in
            guard column != .model else { return ascending ? a.id < b.id : a.id > b.id }
            switch (column.number(a), column.number(b)) {
            case let (x?, y?) where x != y: return ascending ? x < y : x > y
            case (nil, .some): return false
            case (.some, nil): return true
            default: return a.id > b.id
            }
        }
    }
}
