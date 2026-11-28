import Foundation

/// Fetches billing-cycle token usage for Cursor directly from the phone.
///
/// Strategy (RFC-Cursor-Tokens):
/// 1. Primary: `POST /api/dashboard/get-aggregated-usage-events` (single call).
/// 2. Fallback: `POST /api/dashboard/get-filtered-usage-events` with bounded pagination
///    (`maxPages = 10`, `pageSize = 100`) when primary fails with non-429 or lacks recognizable fields.
/// 3. Never throws into the quota pipeline: failures return `.failure(TokenUsageProblem)` so the
///    caller keeps the previous cached `TokenUsageSummary` and shows a non-PII diagnostic hint.
enum CursorTokenSource {
    enum FetchOutcome: Equatable {
        case success(TokenUsageSummary)
        case failure(TokenUsageProblem)
    }

    static let maxPages = 10
    static let pageSize = 100
    static let fallbackWindowSeconds: TimeInterval = 30 * 86_400

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Requests

    static func aggregatedRequest(token: String, start: Date, end: Date) -> URLRequest {
        dashboardRequest(
            path: "get-aggregated-usage-events",
            token: token,
            body: [
                "teamId": -1,
                "startDate": millisString(start),
                "endDate": millisString(end),
            ]
        )
    }

    static func filteredRequest(token: String, start: Date, end: Date, page: Int, pageSize: Int = pageSize) -> URLRequest {
        dashboardRequest(
            path: "get-filtered-usage-events",
            token: token,
            body: [
                "teamId": 0,
                "startDate": millisString(start),
                "endDate": millisString(end),
                "page": page,
                "pageSize": pageSize,
            ]
        )
    }

    private static func dashboardRequest(path: String, token: String, body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/dashboard/\(path)")!)
        request.httpMethod = "POST"
        request.setValue(DirectProvider.cursorCookieHeader(for: token), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private static func millisString(_ date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }

    // MARK: - Network orchestration

    static func fetch(
        token: String,
        cycleStart: Date?,
        cycleEnd: Date?,
        session: URLSession = .shared,
        now: Date = Date()
    ) async -> FetchOutcome {
        let isFallbackPeriod = cycleStart == nil
        let queryStart = cycleStart ?? now.addingTimeInterval(-fallbackWindowSeconds)
        let queryEnd = isFallbackPeriod ? now : (cycleEnd ?? now)
        let displayStart: Date? = isFallbackPeriod ? nil : cycleStart
        let displayEnd: Date? = isFallbackPeriod ? nil : (cycleEnd ?? now)

        // 1. Primary endpoint: single-call aggregated summary.
        let primaryReq = aggregatedRequest(token: token, start: queryStart, end: queryEnd)
        let primaryProblem: TokenUsageProblem
        switch await send(primaryReq, session: session) {
        case .success(let data):
            if let summary = parseAggregated(data, periodStart: displayStart, periodEnd: displayEnd,
                                             isFallbackPeriod: isFallbackPeriod, now: now) {
                return .success(summary)
            }
            primaryProblem = .badFormat
        case .failure(let problem):
            // Never hammer Cursor with a fallback request when rate-limited (TR-C3).
            if problem == .rateLimited { return .failure(.rateLimited) }
            primaryProblem = problem
        }

        // 2. Fallback endpoint: paginated usage events with hard page cap.
        var allEvents: [RawUsageRow] = []
        var expectedTotal: Int64?
        var hitCap = false

        for page in 1...maxPages {
            let req = filteredRequest(token: token, start: queryStart, end: queryEnd, page: page, pageSize: pageSize)
            switch await send(req, session: session) {
            case .success(let data):
                guard let parsed = parseFilteredPage(data) else {
                    return .failure(preferAuthFailure(primaryProblem, .badFormat))
                }
                if let total = parsed.totalCount { expectedTotal = total }
                allEvents.append(contentsOf: parsed.rows)

                let fetched = Int64(allEvents.count)
                let reachedEnd = parsed.rows.isEmpty
                    || parsed.rows.count < pageSize
                    || (expectedTotal.map { fetched >= $0 } ?? false)
                if reachedEnd {
                    return .success(buildSummary(
                        from: allEvents,
                        topLevel: nil,
                        periodStart: displayStart,
                        periodEnd: displayEnd,
                        isFallbackPeriod: isFallbackPeriod,
                        isPartial: false,
                        now: now
                    ))
                }
                if page == maxPages {
                    hitCap = true
                }
            case .failure(let problem):
                // Do not return partial pages if pagination failed mid-flight.
                return .failure(preferAuthFailure(primaryProblem, problem))
            }
        }

        return .success(buildSummary(
            from: allEvents,
            topLevel: nil,
            periodStart: displayStart,
            periodEnd: displayEnd,
            isFallbackPeriod: isFallbackPeriod,
            isPartial: hitCap,
            now: now
        ))
    }

    private static func preferAuthFailure(_ primary: TokenUsageProblem, _ fallback: TokenUsageProblem) -> TokenUsageProblem {
        if case .unauthorized = fallback { return fallback }
        if case .rateLimited = fallback { return fallback }
        if case .unauthorized = primary, fallback == .badFormat { return primary }
        return fallback
    }

    private static func send(_ request: URLRequest, session: URLSession) async -> Result<Data, TokenUsageProblem> {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            return .failure(.timedOut)
        } catch {
            return .failure(.offline)
        }
        guard let http = response as? HTTPURLResponse else { return .failure(.badFormat) }
        switch http.statusCode {
        case 200..<300:
            return .success(data)
        case 401, 403:
            return .failure(.unauthorized(http.statusCode))
        case 429:
            return .failure(.rateLimited)
        default:
            return .failure(.server(http.statusCode))
        }
    }

    // MARK: - Pure parsers

    struct RawUsageRow: Equatable {
        var model: String
        var inputTokens: Int64?
        var cacheWriteTokens: Int64?
        var cacheReadTokens: Int64?
        var outputTokens: Int64?
        var explicitTotalTokens: Int64?
        var totalCents: Double?
    }

    struct FilteredPage: Equatable {
        var rows: [RawUsageRow]
        var totalCount: Int64?
    }

    /// Parses `get-aggregated-usage-events`. Returns `nil` when JSON lacks recognizable fields.
    static func parseAggregated(
        _ data: Data,
        periodStart: Date?,
        periodEnd: Date?,
        isFallbackPeriod: Bool,
        now: Date = Date()
    ) -> TokenUsageSummary? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let topLevel = extractTopLevelTotals(json)
        let array = (json["aggregations"] as? [[String: Any]])
            ?? (json["modelAggregations"] as? [[String: Any]])

        guard array != nil || topLevel != nil else { return nil }

        var rows: [RawUsageRow] = []
        if let array {
            for item in array {
                guard let row = parseRow(item) else { continue }
                rows.append(row)
            }
            // Non-empty array where zero rows had any token/model fields means schema changed.
            if !array.isEmpty && rows.isEmpty && topLevel == nil { return nil }
        }

        return buildSummary(
            from: rows,
            topLevel: topLevel,
            periodStart: periodStart,
            periodEnd: periodEnd,
            isFallbackPeriod: isFallbackPeriod,
            isPartial: false,
            now: now
        )
    }

    /// Parses one page from `get-filtered-usage-events`.
    static func parseFilteredPage(_ data: Data) -> FilteredPage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let array = (json["usageEventsDisplay"] as? [[String: Any]])
            ?? (json["usageEvents"] as? [[String: Any]]) else { return nil }

        let totalCount = int64(json["totalUsageEventsCount"]) ?? int64(json["totalCount"])
        var rows: [RawUsageRow] = []
        rows.reserveCapacity(array.count)
        for item in array {
            if let row = parseRow(item) {
                rows.append(row)
            }
        }
        if !array.isEmpty && rows.isEmpty { return nil }
        return FilteredPage(rows: rows, totalCount: totalCount)
    }

    private struct TopLevelTotals {
        var inputTokens: Int64?
        var cacheWriteTokens: Int64?
        var cacheReadTokens: Int64?
        var outputTokens: Int64?
        var totalCents: Double?
    }

    private static func extractTopLevelTotals(_ json: [String: Any]) -> TopLevelTotals? {
        let input = int64(json["totalInputTokens"])
        let cacheWrite = int64(json["totalCacheWriteTokens"])
        let cacheRead = int64(json["totalCacheReadTokens"])
        let output = int64(json["totalOutputTokens"])
        let cents = double(json["totalCostCents"]) ?? double(json["totalCents"])
        if input == nil && cacheWrite == nil && cacheRead == nil && output == nil && cents == nil {
            return nil
        }
        return TopLevelTotals(
            inputTokens: input,
            cacheWriteTokens: cacheWrite,
            cacheReadTokens: cacheRead,
            outputTokens: output,
            totalCents: cents
        )
    }

    private static func parseRow(_ dict: [String: Any]) -> RawUsageRow? {
        let tokenDict = (dict["tokenUsage"] as? [String: Any]) ?? dict
        let input = int64(tokenDict["inputTokens"]) ?? int64(dict["inputTokens"]) ?? int64(dict["totalInputTokens"])
        let cacheWrite = int64(tokenDict["cacheWriteTokens"]) ?? int64(dict["cacheWriteTokens"]) ?? int64(dict["totalCacheWriteTokens"])
        let cacheRead = int64(tokenDict["cacheReadTokens"]) ?? int64(dict["cacheReadTokens"]) ?? int64(dict["totalCacheReadTokens"])
        let output = int64(tokenDict["outputTokens"]) ?? int64(dict["outputTokens"]) ?? int64(dict["totalOutputTokens"])
        let explicitTotal = int64(tokenDict["totalTokens"]) ?? int64(dict["totalTokens"])
        let cents = double(tokenDict["totalCents"])
            ?? double(dict["totalCents"])
            ?? double(dict["totalCostCents"])
            ?? double(tokenDict["cents"])
            ?? double(dict["cents"])

        let rawModel = ["modelIntent", "model", "modelName"]
            .compactMap { dict[$0] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        let hasAnyCount = input != nil || cacheWrite != nil || cacheRead != nil
            || output != nil || explicitTotal != nil || cents != nil
        guard hasAnyCount || rawModel != nil else { return nil }

        return RawUsageRow(
            model: rawModel ?? "其他",
            inputTokens: input,
            cacheWriteTokens: cacheWrite,
            cacheReadTokens: cacheRead,
            outputTokens: output,
            explicitTotalTokens: explicitTotal,
            totalCents: cents
        )
    }

    private static func buildSummary(
        from rows: [RawUsageRow],
        topLevel: TopLevelTotals?,
        periodStart: Date?,
        periodEnd: Date?,
        isFallbackPeriod: Bool,
        isPartial: Bool,
        now: Date
    ) -> TokenUsageSummary {
        struct Accumulator {
            var input: Int64?
            var cacheWrite: Int64?
            var cacheRead: Int64?
            var output: Int64?
            var explicitTotal: Int64?
            var cents: Double?

            mutating func add(_ row: RawUsageRow) {
                if let v = row.inputTokens { input = (input ?? 0) + v }
                if let v = row.cacheWriteTokens { cacheWrite = (cacheWrite ?? 0) + v }
                if let v = row.cacheReadTokens { cacheRead = (cacheRead ?? 0) + v }
                if let v = row.outputTokens { output = (output ?? 0) + v }
                if let v = row.explicitTotalTokens { explicitTotal = (explicitTotal ?? 0) + v }
                if let v = row.totalCents { cents = (cents ?? 0) + v }
            }

            var totalTokens: Int64 {
                if input != nil || cacheWrite != nil || cacheRead != nil || output != nil {
                    return (input ?? 0) + (cacheWrite ?? 0) + (cacheRead ?? 0) + (output ?? 0)
                }
                return explicitTotal ?? 0
            }
        }

        var byModel: [String: Accumulator] = [:]
        for row in rows {
            byModel[row.model, default: Accumulator()].add(row)
        }

        let models: [TokenUsageModel] = byModel.map { name, acc in
            TokenUsageModel(
                model: name,
                inputTokens: acc.input,
                cacheWriteTokens: acc.cacheWrite,
                cacheReadTokens: acc.cacheRead,
                outputTokens: acc.output,
                totalTokens: acc.totalTokens,
                totalCents: acc.cents
            )
        }.sorted { lhs, rhs in
            if lhs.totalTokens != rhs.totalTokens { return lhs.totalTokens > rhs.totalTokens }
            return lhs.model < rhs.model
        }

        func sumInt64(_ values: [Int64?]) -> Int64? {
            let present = values.compactMap { $0 }
            return present.isEmpty ? nil : present.reduce(0, +)
        }
        func sumDouble(_ values: [Double?]) -> Double? {
            let present = values.compactMap { $0 }
            return present.isEmpty ? nil : present.reduce(0, +)
        }

        let inputTotal = sumInt64(models.map(\.inputTokens)) ?? topLevel?.inputTokens
        let cacheWriteTotal = sumInt64(models.map(\.cacheWriteTokens)) ?? topLevel?.cacheWriteTokens
        let cacheReadTotal = sumInt64(models.map(\.cacheReadTokens)) ?? topLevel?.cacheReadTokens
        let outputTotal = sumInt64(models.map(\.outputTokens)) ?? topLevel?.outputTokens
        let centsTotal = sumDouble(models.map(\.totalCents)) ?? topLevel?.totalCents

        let grandTotal: Int64
        if !models.isEmpty {
            grandTotal = models.reduce(0) { $0 + $1.totalTokens }
        } else {
            grandTotal = (inputTotal ?? 0) + (cacheWriteTotal ?? 0) + (cacheReadTotal ?? 0) + (outputTotal ?? 0)
        }

        return TokenUsageSummary(
            periodStart: periodStart.map { iso.string(from: $0) },
            periodEnd: periodEnd.map { iso.string(from: $0) },
            isFallbackPeriod: isFallbackPeriod,
            totalTokens: grandTotal,
            inputTokens: inputTotal,
            cacheWriteTokens: cacheWriteTotal,
            cacheReadTokens: cacheReadTotal,
            outputTokens: outputTotal,
            totalCents: centsTotal,
            models: models,
            fetchedAt: iso.string(from: now),
            isPartial: isPartial ? true : nil
        )
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            let d = n.doubleValue
            guard d.isFinite else { return nil }
            return max(Int64(d), 0)
        }
        if let s = value as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let i = Int64(trimmed) { return max(i, 0) }
            if let d = Double(trimmed), d.isFinite { return max(Int64(d), 0) }
        }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            let d = n.doubleValue
            return d.isFinite ? max(d, 0) : nil
        }
        if let s = value as? String,
           let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)),
           d.isFinite {
            return max(d, 0)
        }
        return nil
    }
}
