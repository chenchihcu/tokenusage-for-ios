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
    /// Each provider's last success and last problem (FR-1, FR-2).
    private(set) var providerStatus: [String: ProviderStatus] = ProviderStatusStore.load()
    /// Providers being refreshed on their own (FR-6).
    private(set) var refreshingOne: Set<DirectProvider> = []
    /// Bumped on every successful refresh so views can play haptics.
    private(set) var refreshCount = 0
    /// Daily use per model pool, kept on the phone for the charts (FR-34).
    private(set) var history = UsageHistoryStore.load()
    /// Models and list prices (FR-36/37), refreshed on the chosen schedule.
    private(set) var catalog = ModelCatalogStore.load()
    private(set) var isUpdatingCatalog = false
    private(set) var catalogError: String?

    var displayHistory: UsageHistory {
        UserDefaults.standard.bool(forKey: SettingsKey.sampleData) ? SampleData.history() : history
    }

    /// The app's main pages (FR-39). One tab bar holds them, so any page is one tap away and
    /// each keeps its place; the system puts the bar beside the camera on iPhone Duo.
    enum Tab: Hashable {
        case quotas, analytics, catalog, settings
    }

    /// The only sheet left: a quick look at resets from the fast path. It sits above every
    /// layout, so folding or unfolding keeps it open (FR-29).
    enum Sheet: String, Identifiable {
        case resets
        var id: String { rawValue }
    }

    var selectedTab: Tab = .quotas
    /// Bumped when the person taps the tab they are already on; that page scrolls to its top.
    private(set) var scrollToTop: [Tab: Int] = [:]
    var selectedID: ProviderQuota.ID?
    /// Sign-in or Mac relay for one agent, presented over the compact 額度 list.
    var accountPrompt: DirectProvider?
    var presentedSheet: Sheet?
    /// Fast-path filter: only agents with 20 % or less remaining.
    var alertsOnly = false
    /// Providers with no sign-in yet; shown as 「未設定」 rows, never as numbers.
    private(set) var missingProviders: [DirectProvider] = QuotaStore.unconfiguredProviders()

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

    /// Exactly what the vendors last reported. Nothing is inferred. Not ranked by urgency:
    /// rows keep a fixed provider order so they don't jump around between refreshes
    /// (fetches finish in any order).
    var displayItems: [ProviderQuota] {
        ProviderStyle.vendorOrdered(items, id: \.providerId)
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

    /// Providers with no sign-in. `hasToken` is injected so tests do not read this phone's Keychain.
    nonisolated static func unconfiguredProviders(
        hasToken: (DirectProvider) -> Bool = { $0.isSignedIn }
    ) -> [DirectProvider] {
        DirectProvider.allCases.filter { !hasToken($0) }
    }

    var alertCount: Int { displayItems.filter { $0.level == .exhausted }.count }

    var isLoading: Bool { state == .loading }

    /// Earliest time this provider may be asked again (its floor or a 429 back-off);
    /// nil when it can be asked now (FR-6).
    func nextAllowed(_ provider: DirectProvider, now: Date = Date()) -> Date? {
        let until = [floorUntil[provider], blockedUntil[provider]].compactMap { $0 }.max()
        return until.flatMap { $0 > now ? $0 : nil }
    }

    func status(for providerId: String) -> ProviderStatus? { providerStatus[providerId] }

    /// `force` is a person asking (pull, button): it ignores the per-provider floor
    /// but still honours a 429 back-off. `only` refreshes one provider and keeps its floor (FR-6).
    func refresh(force: Bool = false, only: DirectProvider? = nil) async {
        if let only {
            guard state != .loading, !refreshingOne.contains(only), nextAllowed(only) == nil else { return }
        } else {
            guard state != .loading, refreshingOne.isEmpty else { return }
        }
        missingProviders = Self.unconfiguredProviders()
        let now = Date()
        let skipping = Set(DirectProvider.allCases.filter { provider in
            if let only { return provider != only }
            if let until = blockedUntil[provider], now < until { return true }
            if !force, let until = floorUntil[provider], now < until { return true }
            return false
        })
        if let only { refreshingOne.insert(only) } else { state = .loading }
        defer { if let only { refreshingOne.remove(only) } }
        do {
            let result = try await client.fetchQuotas(previous: items, skipping: skipping)
            for provider in result.asked {
                floorUntil[provider] = now.addingTimeInterval(provider.minimumInterval)
                blockedUntil[provider] = result.retryAfter[provider].map { now.addingTimeInterval($0) }
            }
            recordStatus(result, at: now)
            items = result.items
            if !result.asked.isEmpty { lastUpdated = Date() }
            // One failing provider shows on its own row (FR-4); the banner is for "nothing worked".
            if only == nil {
                state = result.succeeded.isEmpty ? result.firstError.map { .failed($0) } ?? .idle : .idle
            }
            refreshCount += 1
            QuotaCache.save(result.items)
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenter.shared.reloadAllControls()
            ResetAlerts.check(result.items)
            await AlertCenter.sync(result.items)
            await ResetActivity.update(with: result.items)
            if !result.asked.isEmpty, !UserDefaults.standard.bool(forKey: SettingsKey.sampleData) {
                history.record(result.items)
                UsageHistoryStore.save(history)
            }
        } catch let error as QuotaClientError {
            if error == .notConfigured { items = [] }
            if only == nil { state = .failed(error) }
        } catch {
            if only == nil { state = .failed(.badResponse) }
        }
    }

    /// FR-1/FR-2: a success sets the time and clears the problem; a failure keeps the last
    /// success so the row can say how old its figures are.
    private func recordStatus(_ result: QuotaClient.Result, at now: Date) {
        guard !result.asked.isEmpty else { return }
        for provider in result.succeeded {
            var status = ProviderStatus(lastSuccess: now, problem: nil, retryAt: nil)
            // Relayed figures are as old as the Mac's last upload, not this request.
            if provider.isRelayed,
               let quota = result.items.first(where: { $0.providerId == provider.rawValue }) {
                status.lastSuccess = min(quota.fetchedDate ?? now, now)
                if AntigravityRelay.isStale(quota, now: now) { status.problem = .relayStale }
            }
            providerStatus[provider.rawValue] = status
        }
        for (provider, error) in result.errors {
            var status = providerStatus[provider.rawValue] ?? ProviderStatus()
            status.problem = error.providerProblem
            status.retryAt = result.retryAfter[provider].map { now.addingTimeInterval($0) }
            providerStatus[provider.rawValue] = status
        }
        ProviderStatusStore.save(providerStatus)
    }

    /// Tapping the current tab again brings that page back to its start, the usual iPhone way
    /// home: folded, 額度 closes the open platform and shows the list; every page scrolls to top.
    func returnToStart(_ tab: Tab, compact: Bool) {
        if tab == .quotas, compact { selectedID = nil }
        scrollToTop[tab, default: 0] += 1
    }

    /// Downloads the model list and prices when the weekly or monthly slot has passed,
    /// or right away when `force` (the person tapped 「立即更新」).
    func refreshCatalogIfDue(force: Bool = false) async {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.catalogSchedule) ?? ""
        let schedule = ModelCatalog.Schedule(rawValue: raw) ?? .weekly
        guard !isUpdatingCatalog, isOnline, force || catalog.isDue(schedule) else { return }
        isUpdatingCatalog = true
        defer { isUpdatingCatalog = false }
        do {
            let fresh = try await ModelCatalogStore.download(previous: catalog)
            catalog = fresh
            catalogError = nil
            ModelCatalogStore.save(fresh)
        } catch {
            catalogError = "無法下載模型清單，下次開啟 App 會再試。"
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
