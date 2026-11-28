import Foundation

/// The models the agents can use and their list API prices (FR-36, FR-37), refreshed weekly or
/// monthly from LiteLLM's public price file (decided 2026-11-18). No vendor publishes an
/// official model or price API, so this is community data; the app labels it as list API
/// prices, not what a subscription costs.
struct CatalogModel: Codable, Hashable, Identifiable {
    var id: String
    var vendor: Vendor
    /// US dollars per million tokens.
    var inputPerMillion: Double?
    var outputPerMillion: Double?
    var cacheReadPerMillion: Double?
    var contextTokens: Int?
    /// When the vendor retires it (yyyy-MM-dd), if announced.
    var retires: String?

    enum Vendor: String, Codable, CaseIterable, Identifiable {
        case anthropic, openai, google
        var id: String { rawValue }

        var name: String {
            switch self {
            case .anthropic: return "Anthropic"
            case .openai: return "OpenAI"
            case .google: return "Google"
            }
        }

        /// Agents that run this vendor's models. Cursor's API pool bills them at these rates.
        var agents: [String] {
            switch self {
            case .anthropic: return ["Claude Code", "Cursor"]
            case .openai: return ["Codex", "Cursor"]
            case .google: return ["Google Antigravity", "Cursor"]
            }
        }
    }
}

struct ModelCatalog: Codable, Equatable {
    var models: [CatalogModel] = []
    var fetchedAt: Date?
    /// What changed at the last refresh, so new and retired models stand out.
    var added: [String] = []
    var removed: [String] = []

    static let source = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!

    enum Schedule: String, CaseIterable, Identifiable {
        case weekly, monthly, manual
        var id: String { rawValue }
        var title: String {
            switch self {
            case .weekly: return "每週"
            case .monthly: return "每月"
            case .manual: return "僅手動"
            }
        }
        var interval: TimeInterval? {
            switch self {
            case .weekly: return 7 * 86_400
            case .monthly: return 30 * 86_400
            case .manual: return nil
            }
        }
    }

    /// Models not yet retired on `now`. The stored catalog can be weeks old (or never refreshed
    /// on 僅手動), so a retirement date that has since passed must not still read as upcoming.
    func activeModels(now: Date = Date()) -> [CatalogModel] {
        let today = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate])
        return models.filter { ($0.retires ?? "9999") > today }
    }

    /// The last refresh's added and removed lists stop being news after a while.
    func showsChanges(now: Date = Date()) -> Bool {
        guard let fetchedAt, !(added.isEmpty && removed.isEmpty) else { return false }
        return now.timeIntervalSince(fetchedAt) < 14 * 86_400
    }

    func isDue(_ schedule: Schedule, now: Date = Date()) -> Bool {
        guard let interval = schedule.interval else { return false }
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) >= interval
    }

    /// Keeps chat models of the agents' vendors that are not retired, drops dated duplicates
    /// and older generations, and records what was added or removed since `previous`.
    static func parse(_ data: Data, previous: ModelCatalog, now: Date = Date()) -> ModelCatalog? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let today = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate])
        var found: [String: CatalogModel] = [:]
        for (rawID, value) in json {
            guard let entry = value as? [String: Any],
                  let provider = entry["litellm_provider"] as? String,
                  let mode = entry["mode"] as? String, mode == "chat" || mode == "responses" else { continue }
            let vendor: CatalogModel.Vendor
            switch provider {
            case "anthropic": vendor = .anthropic
            case "openai": vendor = .openai
            case "gemini": vendor = .google
            default: continue
            }
            let id = rawID.components(separatedBy: "/").last ?? rawID
            guard isCurrent(id, vendor: vendor) else { continue }
            let retires = entry["deprecation_date"] as? String
            if let retires, retires <= today { continue }
            func perMillion(_ key: String) -> Double? {
                (entry[key] as? NSNumber).map { $0.doubleValue * 1_000_000 }
            }
            found[id] = CatalogModel(
                id: id, vendor: vendor,
                inputPerMillion: perMillion("input_cost_per_token"),
                outputPerMillion: perMillion("output_cost_per_token"),
                cacheReadPerMillion: perMillion("cache_read_input_token_cost"),
                contextTokens: (entry["max_input_tokens"] as? NSNumber)?.intValue,
                retires: retires)
        }
        // Dated snapshots ("claude-sonnet-4-5-20250929", "gpt-5-2025-08-07") duplicate the
        // undated name when both are listed.
        let ids = Set(found.keys)
        for id in ids {
            guard let range = id.range(of: #"-(\d{8}|\d{4}-\d{2}-\d{2})$"#, options: .regularExpression) else { continue }
            if ids.contains(String(id[..<range.lowerBound])) { found[id] = nil }
        }
        guard !found.isEmpty else { return nil }
        let models = CatalogCorrections.current.apply(to: Array(found.values)).sorted { ($0.vendor.rawValue, $1.id) < ($1.vendor.rawValue, $0.id) }
        let newIDs = Set(models.map(\.id))
        let oldIDs = Set(previous.models.map(\.id))
        let first = previous.models.isEmpty
        return ModelCatalog(models: models, fetchedAt: now,
                            added: first ? [] : newIDs.subtracting(oldIDs).sorted(),
                            removed: first ? [] : oldIDs.subtracting(newIDs).sorted())
    }

    /// Current generations only, with open-ended floors so later generations (Claude 5,
    /// GPT‑6, Gemini 4…) appear without an app update; older ones drop out when retired.
    /// Variants the agents do not use (audio, realtime, image, search…) are skipped.
    static func isCurrent(_ id: String, vendor: CatalogModel.Vendor) -> Bool {
        let lower = id.lowercased()
        let skipped = ["audio", "realtime", "tts", "transcribe", "image", "search", "embedding",
                       "moderation", "computer-use", "instruct", "ft:", "live", "thinking-exp"]
        if skipped.contains(where: lower.contains) || lower.contains("-exp") { return false }
        switch vendor {
        case .anthropic:
            guard lower.hasPrefix("claude-") else { return false }
            return (firstNumber(in: lower) ?? 0) >= 4
        case .openai:
            if lower.contains("codex") { return true }
            guard lower.hasPrefix("gpt-") else { return false }
            return (firstNumber(in: lower) ?? 0) >= 5
        case .google:
            guard lower.hasPrefix("gemini-") else { return false }
            return (firstNumber(in: lower) ?? 0) >= 2.5
        }
    }

    /// First version number in an id: "claude-sonnet-4-5" → 4, "gemini-2.5-pro" → 2.5.
    private static func firstNumber(in id: String) -> Double? {
        guard let range = id.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(id[range])
    }
}

/// Fixes to LiteLLM's community data, checked by hand against the vendors' own model, pricing
/// and deprecation pages. Applied after parsing and to the stored catalog, so a correction
/// reaches people without waiting for the next refresh. Re-check when a vendor releases or
/// retires models, and remove an entry once LiteLLM agrees with the vendor.
struct CatalogCorrections {
    /// Ids the vendor does not list as a model of its own: LiteLLM aliases, and models the
    /// vendor no longer offers and silently routes to a newer one.
    var dropped: Set<String>
    /// Context windows that differ from the vendor's model page.
    var contextTokens: [String: Int]

    /// Checked 2026-11-19.
    static let current = CatalogCorrections(
        dropped: [
            "gpt-5.6",            // OpenAI lists only gpt-5.6-sol, -terra and -luna
            "gpt-5.5-cyber",      // OpenAI lists only gpt-5.5-cyber-preview
            "gemini-3.5-flash",   // removed from AI Studio; requests route to gemini-3.6-flash
            "gemini-3.7-flash",   // removed from AI Studio; requests route to gemini-3.8-flash
        ],
        contextTokens: [
            // OpenAI's model page: 1.05M (LiteLLM: 922K)
            "gpt-6.2-astra": 1_050_000,
            "gpt-6.2-sol": 1_050_000,
            "gpt-6.1-terra": 1_050_000,
            "gpt-6-luna": 1_050_000,
        ])

    func apply(to models: [CatalogModel]) -> [CatalogModel] {
        models.compactMap { model in
            guard !dropped.contains(model.id) else { return nil }
            var model = model
            if let tokens = contextTokens[model.id] { model.contextTokens = tokens }
            return model
        }
    }
}

enum ModelCatalogStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "model-catalog-v1.json")
    }

    static func load() -> ModelCatalog {
        guard let data = try? Data(contentsOf: url),
              var catalog = try? JSONDecoder().decode(ModelCatalog.self, from: data) else { return ModelCatalog() }
        catalog.models = CatalogCorrections.current.apply(to: catalog.models)
        return catalog
    }

    static func save(_ catalog: ModelCatalog) {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func download(previous: ModelCatalog, session: URLSession = .shared) async throws -> ModelCatalog {
        var request = URLRequest(url: ModelCatalog.source)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let catalog = ModelCatalog.parse(data, previous: previous) else {
            throw QuotaClientError.badResponse
        }
        return catalog
    }
}

/// One price bar. The fraction is this price divided by the dearest price in the same set.
enum PriceBoard {
    struct Line: Equatable, Identifiable {
        var vendor: CatalogModel.Vendor
        var modelId: String
        var inputPerMillion: Double
        var fraction: Double
        var id: String { "\(vendor.rawValue)/\(modelId)" }
    }

    static let rowLimit = 6

    /// The dearest input price of each vendor, scaled against the dearest of those three.
    static func headlines(_ models: [CatalogModel]) -> [Line] {
        let tops = CatalogModel.Vendor.allCases.compactMap { vendor -> Line? in
            guard let model = priciest(vendor, in: models, matching: "") else { return nil }
            return Line(vendor: vendor, modelId: model.id, inputPerMillion: model.inputPerMillion ?? 0, fraction: 0)
        }
        return scaled(tops)
    }

    /// Matches across vendors, dearest first, still at most six rows.
    static func search(_ query: String, in models: [CatalogModel]) -> [Line] {
        let matches = models
            .filter { ($0.inputPerMillion ?? 0) > 0 && $0.id.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.inputPerMillion ?? 0) > ($1.inputPerMillion ?? 0) }
            .prefix(rowLimit)
        return scaled(matches.map { model in
            Line(vendor: model.vendor, modelId: model.id, inputPerMillion: model.inputPerMillion ?? 0, fraction: 0)
        })
    }

    /// Up to six models of one vendor, dearest first. A query replaces that list.
    static func lines(for vendor: CatalogModel.Vendor, in models: [CatalogModel], matching query: String = "") -> [Line] {
        let matches = models
            .filter { model in
                model.vendor == vendor && (model.inputPerMillion ?? 0) > 0 &&
                    (query.isEmpty || model.id.localizedCaseInsensitiveContains(query))
            }
            .sorted { ($0.inputPerMillion ?? 0) > ($1.inputPerMillion ?? 0) }
            .prefix(rowLimit)
        return scaled(matches.map { model in
            Line(vendor: vendor, modelId: model.id, inputPerMillion: model.inputPerMillion ?? 0, fraction: 0)
        })
    }

    static func fraction(_ price: Double, of maxPrice: Double) -> Double {
        guard maxPrice > 0 else { return 0 }
        return min(max(price / maxPrice, 0), 1)
    }

    private static func priciest(_ vendor: CatalogModel.Vendor, in models: [CatalogModel], matching query: String) -> CatalogModel? {
        models
            .filter { $0.vendor == vendor && ($0.inputPerMillion ?? 0) > 0 &&
                (query.isEmpty || $0.id.localizedCaseInsensitiveContains(query)) }
            .max { ($0.inputPerMillion ?? 0) < ($1.inputPerMillion ?? 0) }
    }

    private static func scaled(_ lines: [Line]) -> [Line] {
        let maxPrice = lines.map(\.inputPerMillion).max() ?? 0
        return lines.map { line in
            var copy = line
            copy.fraction = fraction(line.inputPerMillion, of: maxPrice)
            return copy
        }
    }
}
