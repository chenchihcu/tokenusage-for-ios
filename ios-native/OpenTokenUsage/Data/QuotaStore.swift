import Foundation
import Network
import Observation
import WidgetKit

@MainActor
@Observable
final class QuotaStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case failed(QuotaClientError)
    }

    private(set) var items: [ProviderQuota] = []
    private(set) var lastUpdated: Date?
    private(set) var state: LoadState = .idle
    private(set) var isOnline = true
    /// Bumped on every successful refresh so views can play haptics.
    private(set) var refreshCount = 0

    var selectedID: ProviderQuota.ID?
    /// Fast-path filter: only agents with 20 % or less remaining.
    var alertsOnly = false
    /// Providers with no sign-in yet; shown as 「未設定」 rows, never as numbers.
    private(set) var missingProviders: [DirectProvider] = DirectProvider.allCases.filter { $0.token == nil }

    /// Earliest time each provider may be asked again (its floor, or a 429 back-off).
    private var floorUntil: [DirectProvider: Date] = [:]
    private var blockedUntil: [DirectProvider: Date] = [:]

    private let client = QuotaClient()
    private let monitor = NWPathMonitor()
    private var autoRefreshTask: Task<Void, Never>?

    init() {
        if let snapshot = QuotaCache.load() {
            items = snapshot.items
            lastUpdated = snapshot.savedAt
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let cameBack = online && !self.isOnline
                self.isOnline = online
                if cameBack { await self.refresh() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "opentokenusage.path"))
    }

    /// Exactly what the vendors last reported, most urgent first. Nothing is inferred.
    var displayItems: [ProviderQuota] {
        items.sorted { lhs, rhs in
            if lhs.level != rhs.level { return lhs.level < rhs.level }
            return lhs.remainingPercent < rhs.remainingPercent
        }
    }

    var visibleItems: [ProviderQuota] {
        alertsOnly ? displayItems.filter { $0.remainingPercent <= 20 } : displayItems
    }

    /// Free resets available across Codex and Claude Code (badge on the fast path).
    var resetCreditsTotal: Int {
        items.filter(\.reportsResetCredits).compactMap(\.resetCredits).reduce(0, +)
    }

    var selected: ProviderQuota? {
        guard let selectedID else { return nil }
        return displayItems.first { $0.id == selectedID }
    }

    var alertCount: Int { displayItems.filter { $0.level == .exhausted }.count }

    var isLoading: Bool { state == .loading }

    /// `force` is a person asking (pull, button): it ignores the per-provider floor
    /// but still honours a 429 back-off.
    func refresh(force: Bool = false) async {
        guard state != .loading else { return }
        missingProviders = DirectProvider.allCases.filter { $0.token == nil }
        let now = Date()
        let skipping = Set(DirectProvider.allCases.filter { provider in
            if let until = blockedUntil[provider], now < until { return true }
            if !force, let until = floorUntil[provider], now < until { return true }
            return false
        })
        state = .loading
        do {
            let result = try await client.fetchQuotas(previous: items, skipping: skipping)
            for provider in result.asked {
                floorUntil[provider] = now.addingTimeInterval(provider.minimumInterval)
                blockedUntil[provider] = result.retryAfter[provider].map { now.addingTimeInterval($0) }
            }
            items = result.items
            if !result.asked.isEmpty { lastUpdated = Date() }
            state = result.firstError.map { .failed($0) } ?? .idle
            refreshCount += 1
            QuotaCache.save(result.items)
            WidgetCenter.shared.reloadAllTimelines()
            ResetAlerts.check(result.items)
        } catch let error as QuotaClientError {
            if error == .notConfigured { items = [] }
            state = .failed(error)
        } catch {
            state = .failed(.badResponse)
        }
    }

    /// Refresh on a timer only while the app is on screen.
    func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                let seconds = UserDefaults.standard.integer(forKey: SettingsKey.refreshInterval)
                guard seconds > 0 else { return }
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}
