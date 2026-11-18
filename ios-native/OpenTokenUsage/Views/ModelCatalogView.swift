import SwiftUI

/// Models per agent with their list API prices (FR-36, FR-37).
struct ModelCatalogView: View {
    let store: QuotaStore
    @AppStorage(SettingsKey.catalogSchedule) private var schedule = ModelCatalog.Schedule.weekly.rawValue
    @State private var search = ""

    private var catalog: ModelCatalog { store.catalog }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                if !catalog.added.isEmpty || !catalog.removed.isEmpty {
                    changesSection
                }
                ForEach(CatalogModel.Vendor.allCases) { vendor in
                    let models = catalog.models.filter { $0.vendor == vendor && matches($0) }
                    if !models.isEmpty {
                        Section {
                            ForEach(models) { ModelPriceRow(model: $0) }
                        } header: {
                            Text(vendor.name)
                        } footer: {
                            Text("使用的代理：\(vendor.agents.joined(separator: "、"))")
                        }
                    }
                }
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
                Text(error).font(.footnote).foregroundStyle(.orange)
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
                    .foregroundStyle(.orange)
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
