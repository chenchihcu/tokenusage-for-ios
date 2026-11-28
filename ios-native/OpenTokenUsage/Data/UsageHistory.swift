import Foundation

/// Daily usage per model pool, recorded on the phone from every refresh (decided 2026-11-18:
/// phone-only history; the vendors do not give a phone per-model token counts).
///
/// The unit is "percent of that pool's longest window used that day" — for example % of the
/// Claude Opus weekly limit, or % of Cursor's API pool for the billing period. Within one pool
/// days compare directly; across pools the units differ, so charts never stack them.
struct UsageDay: Codable, Hashable, Identifiable {
    /// Start of the local day.
    var day: Date
    /// "<provider>/<pool id>", e.g. "claude/claude_opus".
    var key: String
    var providerName: String
    var poolName: String
    /// Percentage points of the window used that day (sum of rises between refreshes).
    var consumed: Double

    var id: String { "\(key)@\(day.timeIntervalSince1970)" }
    /// 「Claude Code · Opus」; a pool named after its provider (「Codex 用量」) reads just 「Codex」.
    var seriesName: String {
        poolName.hasPrefix(providerName) ? providerName : "\(providerName) · \(poolName)"
    }
}

struct UsageHistory: Codable, Equatable {
    var days: [UsageDay] = []
    /// Last reading of each pool's longest window, to turn readings into daily use.
    var lastReading: [String: Double] = [:]

    /// Days kept on the phone.
    static let retention = 400

    static func key(providerId: String, poolId: String, tierId: String? = nil) -> String {
        if let tierId { return "\(providerId)/\(poolId)/\(tierId)" }
        return "\(providerId)/\(poolId)"
    }

    /// Adds one refresh's readings per window. A rise counts as use; a meaningful drop (>= 1%)
    /// means the window reset, so everything shown after the reset was used since then.
    mutating func record(_ items: [ProviderQuota], at date: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: date)
        for item in items {
            for pool in item.pools {
                for tier in pool.tiers {
                    let key = Self.key(providerId: item.providerId, poolId: pool.id, tierId: tier.id)
                    let reading = tier.used
                    defer { lastReading[key] = reading }
                    guard let previous = lastReading[key] else { continue }
                    let used: Double
                    if reading >= previous {
                        used = reading - previous
                    } else if previous - reading >= 1.0 {
                        used = reading
                    } else {
                        used = 0
                    }
                    guard used > 0 else { continue }
                    if let index = days.firstIndex(where: { $0.key == key && $0.day == today }) {
                        days[index].consumed += used
                    } else {
                        days.append(UsageDay(day: today, key: key, providerName: item.name,
                                             poolName: pool.name, consumed: used))
                    }
                }
            }
        }
        if let cutoff = calendar.date(byAdding: .day, value: -Self.retention, to: today) {
            days.removeAll { $0.day < cutoff }
        }
    }

    /// Every pool seen, in a stable order.
    var seriesKeys: [String] {
        var seen: [String] = []
        for day in days.sorted(by: { $0.key < $1.key }) where !seen.contains(day.key) { seen.append(day.key) }
        return seen
    }

    enum Period: String, CaseIterable, Identifiable {
        case day = "每日", week = "每週", month = "每月"
        var id: String { rawValue }
        var component: Calendar.Component {
            switch self {
            case .day: return .day
            case .week: return .weekOfYear
            case .month: return .month
            }
        }
    }

    /// Use per pool summed by day, week or month.
    func totals(by period: Period, calendar: Calendar = .current) -> [UsageDay] {
        var sums: [String: UsageDay] = [:]
        for day in days {
            guard let start = calendar.dateInterval(of: period.component, for: day.day)?.start else { continue }
            let id = "\(day.key)@\(start.timeIntervalSince1970)"
            if sums[id] == nil {
                sums[id] = UsageDay(day: start, key: day.key, providerName: day.providerName,
                                    poolName: day.poolName, consumed: 0)
            }
            sums[id]?.consumed += day.consumed
        }
        return sums.values.sorted { ($0.day, $0.key) < ($1.day, $1.key) }
    }

    /// Contiguous calendar buckets for one window (last 30 days / 8 weeks / 12 months),
    /// filling idle buckets with 0 and falling back to legacy pool-level keys if needed.
    func series(providerId: String, poolId: String, tierId: String, period: Period,
                now: Date = Date(), calendar: Calendar = .current) -> [UsageDay] {
        let allTotals = totals(by: period, calendar: calendar)
        let tierKey = Self.key(providerId: providerId, poolId: poolId, tierId: tierId)
        let legacyKey = Self.key(providerId: providerId, poolId: poolId)
        let tierTotals = allTotals.filter { $0.key == tierKey }
        let matched = tierTotals.isEmpty ? allTotals.filter { $0.key == legacyKey } : tierTotals
        guard let template = matched.first else { return [] }

        let count: Int
        switch period {
        case .day: count = 30
        case .week: count = 8
        case .month: count = 12
        }
        guard let currentStart = calendar.dateInterval(of: period.component, for: now)?.start else { return [] }
        let byStart = Dictionary(uniqueKeysWithValues: matched.map { ($0.day, $0) })

        var result: [UsageDay] = []
        result.reserveCapacity(count)
        for offset in (0..<count).reversed() {
            guard let shifted = calendar.date(byAdding: period.component, value: -offset, to: currentStart),
                  let start = calendar.dateInterval(of: period.component, for: shifted)?.start else { continue }
            if let existing = byStart[start] {
                result.append(existing)
            } else {
                result.append(UsageDay(day: start, key: template.key, providerName: template.providerName,
                                       poolName: template.poolName, consumed: 0))
            }
        }
        return result
    }
}

/// Saved in the app's own folder; the history never leaves the phone.
enum UsageHistoryStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "usage-history-v1.json")
    }

    static func load() -> UsageHistory {
        guard let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode(UsageHistory.self, from: data) else { return UsageHistory() }
        return history
    }

    static func save(_ history: UsageHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
