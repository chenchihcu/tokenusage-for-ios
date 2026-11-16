import Foundation
import Network
import Observation

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

    var displayItems: [ProviderQuota] {
        let smart = UserDefaults.standard.bool(forKey: SettingsKey.smartAutoReset)
        let now = Date()
        return items
            .map { smart ? $0.applyingAutoReset(now: now) : $0 }
            .sorted { lhs, rhs in
                if lhs.level != rhs.level { return lhs.level < rhs.level }
                return lhs.remainingPercent < rhs.remainingPercent
            }
    }

    var selected: ProviderQuota? {
        guard let selectedID else { return nil }
        return displayItems.first { $0.id == selectedID }
    }

    var alertCount: Int { displayItems.filter { $0.level == .exhausted }.count }

    var isLoading: Bool { state == .loading }

    func refresh() async {
        guard state != .loading else { return }
        state = .loading
        do {
            let result = try await client.fetchQuotas(previous: items)
            items = result.items
            lastUpdated = Date()
            state = result.firstError.map { .failed($0) } ?? .idle
            refreshCount += 1
            QuotaCache.save(result.items)
        } catch let error as QuotaClientError {
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
