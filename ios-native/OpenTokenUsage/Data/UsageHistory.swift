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
    var seriesName: String { "\(providerName) · \(poolName)" }
}

struct UsageHistory: Codable, Equatable {
    var days: [UsageDay] = []
    /// Last reading of each pool's longest window, to turn readings into daily use.
    var lastReading: [String: Double] = [:]

    /// Days kept on the phone.
    static let retention = 400

    /// Adds one refresh's readings. A rise counts as use; a drop means the window reset,
    /// so everything shown after the reset was used since then.
    mutating func record(_ items: [ProviderQuota], at date: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: date)
        for item in items {
            for pool in item.pools {
                // Tiers run shortest to longest window; the longest shows usage best.
                guard let window = pool.tiers.last else { continue }
                let key = "\(item.providerId)/\(pool.id)"
                let reading = window.used
                defer { lastReading[key] = reading }
                guard let previous = lastReading[key] else { continue }
                let used = reading >= previous ? reading - previous : reading
                guard used > 0 else { continue }
                if let index = days.firstIndex(where: { $0.key == key && $0.day == today }) {
                    days[index].consumed += used
                } else {
                    days.append(UsageDay(day: today, key: key, providerName: item.name,
                                         poolName: pool.name, consumed: used))
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
