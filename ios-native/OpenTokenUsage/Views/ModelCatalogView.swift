import SwiftUI
import UIKit

/// Models per agent with their list API prices (FR-36, FR-37).
struct ModelCatalogView: View {
    let store: QuotaStore
    @AppStorage(SettingsKey.catalogSchedule) private var schedule = ModelCatalog.Schedule.weekly.rawValue
    @State private var search = ""
    @SceneStorage("catalog.vendor") private var vendor: CatalogModel.Vendor = .anthropic
    @State private var sort = MatrixSort()
    @Environment(\.dynamicTypeSize) private var typeSize

    private var catalog: ModelCatalog { store.catalog }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                if !catalog.added.isEmpty || !catalog.removed.isEmpty {
                    changesSection
                }
                vendorSection
                matrixSection
            }
            .listStyle(.insetGrouped)
            .scrollsToTop(on: store.scrollToTop[.catalog, default: 0])
            .searchable(text: $search, prompt: "搜尋模型")
            .navigationTitle("模型與費用")
            .overlay {
                if catalog.models.isEmpty {
                    if store.isUpdatingCatalog {
                        ProgressView("正在下載模型清單…")
                    } else {
                        ContentUnavailableView {
                            Label("尚未下載模型清單", systemImage: "list.bullet.rectangle")
                        } description: {
                            Text(store.catalogError ?? "下載各代理可用的模型與 API 牌價。")
                        } actions: {
                            Button("立即下載") { Task { await store.refreshCatalogIfDue(force: true) } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
    }

    private func matches(_ model: CatalogModel) -> Bool {
        search.isEmpty || model.id.localizedCaseInsensitiveContains(search)
    }

    private func models(of vendor: CatalogModel.Vendor) -> [CatalogModel] {
        catalog.models.filter { $0.vendor == vendor && matches($0) }
    }

    /// One vendor at a time, so its models compare side by side in one matrix.
    @ViewBuilder
    private var vendorSection: some View {
        if !catalog.models.isEmpty {
            Section {
                Picker("AI 廠商", selection: $vendor) {
                    ForEach(CatalogModel.Vendor.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private var matrixSection: some View {
        let shown = sort.apply(models(of: vendor))
        if !catalog.models.isEmpty {
            Section {
                if shown.isEmpty {
                    noMatches
                } else if typeSize.isAccessibilitySize {
                    // A matrix cannot hold accessibility text sizes; each model gets its own card.
                    ForEach(shown) { ModelPriceRow(model: $0) }
                } else {
                    PriceMatrix(models: shown, sort: $sort)
                        .listRowInsets(EdgeInsets())
                }
            } header: {
                HStack {
                    Text("\(vendor.name) · \(shown.count) 個模型")
                    Spacer()
                    sortMenu
                }
                .textCase(nil)
            } footer: {
                matrixFooter(shown)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("排序依據", selection: $sort.column) {
                ForEach(MatrixColumn.allCases) { Text($0.title).tag($0) }
            }
            Picker("順序", selection: $sort.ascending) {
                Text("由小到大").tag(true)
                Text("由大到小").tag(false)
            }
        } label: {
            Label("排序", systemImage: "arrow.up.arrow.down")
                .font(.footnote)
        }
        .accessibilityLabel("排序：\(sort.column.title)，\(sort.ascending ? "由小到大" : "由大到小")")
    }

    @ViewBuilder
    private var noMatches: some View {
        let others = CatalogModel.Vendor.allCases.filter { $0 != vendor && !models(of: $0).isEmpty }
        VStack(alignment: .leading, spacing: 8) {
            Text("\(vendor.name) 沒有符合「\(search)」的模型。")
                .foregroundStyle(.secondary)
            ForEach(others) { other in
                Button("查看 \(other.name)（\(models(of: other).count) 個符合）") { vendor = other }
            }
        }
        .padding(.vertical, 4)
    }

    private func matrixFooter(_ shown: [CatalogModel]) -> some View {
        let retiring = shown.compactMap { model in model.retires.map { "\(model.id)（\($0)）" } }
        return VStack(alignment: .leading, spacing: 4) {
            Text("美元／每百萬 token。點欄位標題可排序，長按模型名稱可複製。")
            if !retiring.isEmpty {
                Text("\(Image(systemName: "calendar.badge.exclamationmark")) 預定退役：\(retiring.joined(separator: "、"))")
                    .foregroundStyle(Color.statusOrange)
            }
            Text("使用的代理：\(vendor.agents.joined(separator: "、"))")
        }
    }

    private var statusSection: some View {
        Section {
            Picker("自動更新", selection: $schedule) {
                ForEach(ModelCatalog.Schedule.allCases) { Text($0.title).tag($0.rawValue) }
            }
            LabeledContent("上次更新") {
                if let date = catalog.fetchedAt {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                } else {
                    Text("尚未更新")
                }
            }
            Button {
                Task { await store.refreshCatalogIfDue(force: true) }
            } label: {
                if store.isUpdatingCatalog {
                    HStack { ProgressView(); Text("更新中…") }
                } else {
                    Label("立即更新", systemImage: "arrow.clockwise")
                }
            }
            .disabled(store.isUpdatingCatalog)
            if let error = store.catalogError {
                Text(error).font(.footnote).foregroundStyle(Color.statusOrange)
            }
        } footer: {
            Text("價格是各家 API 的公開牌價（美元／每百萬 token），來自社群維護的 LiteLLM 價格表，不是訂閱方案的實際費用。Cursor 的 API 額度依這些牌價計費。已公布退役日期且已過期的模型會自動移除。")
        }
    }

    private var changesSection: some View {
        Section("上次更新的變動") {
            if !catalog.added.isEmpty {
                LabeledContent("新增") {
                    Text(catalog.added.joined(separator: "\n")).multilineTextAlignment(.trailing)
                }
            }
            if !catalog.removed.isEmpty {
                LabeledContent("移除") {
                    Text(catalog.removed.joined(separator: "\n")).multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

private struct ModelPriceRow: View {
    let model: CatalogModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.id)
                .font(.subheadline.weight(.semibold).monospaced())
                .textSelection(.enabled)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                price("輸入", model.inputPerMillion)
                price("輸出", model.outputPerMillion)
                price("快取讀取", model.cacheReadPerMillion)
                if let context = model.contextTokens {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("上下文").font(.caption2).foregroundStyle(.secondary)
                        Text("\(context / 1000)K").font(.caption.monospacedDigit())
                    }
                }
            }
            if let retires = model.retires {
                Label("預定退役 \(retires)", systemImage: "calendar.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Color.statusOrange)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func price(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            if let value {
                Text(value, format: .currency(code: "USD").precision(.fractionLength(value < 1 ? 3 : 2)))
                    .font(.caption.monospacedDigit())
            } else {
                Text("—").font(.caption)
            }
        }
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

/// Models as rows and prices as columns. The model column stays put while the figures scroll
/// sideways on narrow iPhones; every row has the same height so both halves line up.
private struct PriceMatrix: View {
    let models: [CatalogModel]
    @Binding var sort: MatrixSort

    @ScaledMetric(relativeTo: .footnote) private var nameWidth: CGFloat = 136
    @ScaledMetric(relativeTo: .footnote) private var figureWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .footnote) private var rowHeight: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header(.model, alignment: .leading)
                    .frame(width: nameWidth, height: rowHeight, alignment: .leading)
                ForEach(models) { model in
                    Divider()
                    nameCell(model)
                        .frame(width: nameWidth, height: rowHeight, alignment: .leading)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color(uiColor: .separator)).frame(width: 1)
            }
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(MatrixColumn.figures) { column in
                            header(column, alignment: .trailing)
                                .frame(width: figureWidth, height: rowHeight, alignment: .trailing)
                        }
                    }
                    ForEach(models) { model in
                        Divider()
                        HStack(spacing: 0) {
                            ForEach(MatrixColumn.figures) { column in
                                let value = column.text(model)
                                Text(value)
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(value == "—" ? .secondary : .primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(width: figureWidth, height: rowHeight, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(.trailing, 16)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        // VoiceOver reads one model per row instead of the cells split across two columns.
        .accessibilityElement(children: .ignore)
        .accessibilityChildren {
            ForEach(models) { model in
                Text(spoken(model))
            }
        }
    }

    private func header(_ column: MatrixColumn, alignment: HorizontalAlignment) -> some View {
        Button {
            withAnimation { sort.tap(column) }
        } label: {
            HStack(spacing: 2) {
                Text(column.title)
                if sort.column == column {
                    Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                        .imageScale(.small)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(sort.column == column ? Color.accentColor : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: alignment == .leading ? .leading : .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func nameCell(_ model: CatalogModel) -> some View {
        HStack(spacing: 4) {
            Text(model.id)
                .font(.footnote.weight(.medium).monospaced())
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if model.retires != nil {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Color.statusOrange)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("複製模型名稱", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = model.id
            }
            if let retires = model.retires {
                Text("預定退役 \(retires)")
            }
        }
    }

    private func spoken(_ model: CatalogModel) -> String {
        var parts = [model.id]
        for column in MatrixColumn.figures {
            parts.append("\(column.title) \(column.text(model) == "—" ? "無資料" : column.text(model))")
        }
        if let retires = model.retires { parts.append("預定退役 \(retires)") }
        return parts.joined(separator: "，")
    }
}
