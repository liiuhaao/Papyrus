import Foundation
import SwiftUI

@MainActor
final class FeedViewModel: ObservableObject {
    static let shared = FeedViewModel()

    @Published var feedItems: [FeedItem] = [] {
        didSet {
            feedItemsRevision &+= 1
        }
    }
    @Published var subscriptions: [FeedSubscription] = []
    @Published var isFetching = false
    @Published var fetchResultMessage: String?
    @Published var selectedSubscriptionFilter: UUID? = nil
    @Published var feedStatusFilter: Set<FeedItem.Status> = []
    @Published var itemCountBySubscription: [UUID: Int] = [:]
    @Published var countByStatus: [FeedItem.Status: Int] = [:]
    @Published private(set) var feedItemsRevision: Int = 0

    private let service = FeedService.shared

    init() {
        Task {
            await service.load()
            await service.cleanupOrphanedItems()
            await reload()
        }
    }

    var itemCount: Int { feedItems.count }

    // MARK: - Auto-refresh setting (UserDefaults, no complex config pipeline needed)

    static var autoRefreshOnLaunch: Bool {
        get { UserDefaults.standard.object(forKey: "feed.autoRefreshOnLaunch") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "feed.autoRefreshOnLaunch") }
    }

    /// Called on app launch. Refreshes if auto-refresh is on and any subscription is stale (> 1h since last fetch).
    func refreshIfStale(papers: [Paper]) async {
        guard FeedViewModel.autoRefreshOnLaunch else { return }
        guard !isFetching else { return }

        let subs = await service.allSubscriptions()
        let enabled = subs.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }

        let staleThreshold: TimeInterval = 3600  // 1 hour minimum between auto-refreshes
        let now = Date()
        let needsRefresh = enabled.contains { sub in
            guard let last = sub.lastFetchedAt else { return true }
            return now.timeIntervalSince(last) > staleThreshold
        }
        guard needsRefresh else { return }

        await refresh(papers: papers)
    }

    // MARK: - Reload from service

    func reload() async {
        let refreshedSubscriptions = await service.allSubscriptions()
        let refreshedFeedItems = await service.items(
            statusFilter: feedStatusFilter,
            subscriptionId: selectedSubscriptionFilter
        )
        let refreshedItemCounts = await service.countBySubscription(statusFilter: feedStatusFilter)
        let refreshedStatusCounts = await service.countByStatus()

        updatePublishedValue(\.subscriptions, to: refreshedSubscriptions)
        updatePublishedValue(\.feedItems, to: refreshedFeedItems)
        updatePublishedValue(\.itemCountBySubscription, to: refreshedItemCounts)
        updatePublishedValue(\.countByStatus, to: refreshedStatusCounts)
    }

    var totalItemCount: Int {
        itemCountBySubscription.values.reduce(0, +)
    }

    func selectFilter(_ id: UUID?) async {
        guard selectedSubscriptionFilter != id else { return }
        selectedSubscriptionFilter = id
        await reload()
    }

    func toggleStatusFilter(_ status: FeedItem.Status) async {
        var updatedFilter = feedStatusFilter
        if updatedFilter.contains(status) { updatedFilter.remove(status) }
        else { updatedFilter.insert(status) }
        guard updatedFilter != feedStatusFilter else { return }
        feedStatusFilter = updatedFilter
        await reload()
    }

    // MARK: - Fetch

    func refresh(papers: [Paper]) async {
        guard !isFetching else { return }
        guard !subscriptions.filter(\.isEnabled).isEmpty else {
            updatePublishedValue(\.fetchResultMessage, to: "No active subscriptions. Add one to get started.")
            return
        }
        updatePublishedValue(\.isFetching, to: true)
        updatePublishedValue(\.fetchResultMessage, to: nil)

        let identifiers = backedLibraryIdentifiers(from: papers)

        let count = await service.fetchAll(
            existingArxivIds: identifiers.arxivIds,
            existingDOIs: identifiers.dois
        )
        await reload()
        updatePublishedValue(\.isFetching, to: false)

        if count == 0 {
            updatePublishedValue(\.fetchResultMessage, to: "No new papers found.")
        } else {
            updatePublishedValue(\.fetchResultMessage, to: "\(count) new paper\(count == 1 ? "" : "s") found.")
        }
    }

    // MARK: - Subscriptions

    func addSubscription(_ sub: FeedSubscription) async {
        if await service.addSubscription(sub) {
            await reload()
        }
    }

    func removeSubscription(id: UUID) async {
        if await service.removeSubscription(id: id) {
            await reload()
        }
    }

    func updateSubscription(_ updated: FeedSubscription) async {
        let old = subscriptions.first(where: { $0.id == updated.id })
        var didClearItems = false
        if old?.value != updated.value {
            didClearItems = await service.clearItems(forSubscription: updated.id)
        }
        let didUpdate = await service.updateSubscription(updated)
        if didClearItems || didUpdate {
            await reload()
        }
    }

    func toggleSubscription(id: UUID) async {
        guard let sub = subscriptions.first(where: { $0.id == id }) else { return }
        var updated = sub
        updated.isEnabled.toggle()
        if await service.updateSubscription(updated) {
            await reload()
        }
    }

    // MARK: - Feed Actions

    func markRead(_ item: FeedItem) async {
        if await service.markRead(id: item.id) {
            await reload()
        }
    }

    func markUnread(_ item: FeedItem) async {
        if await service.markUnread(id: item.id) {
            await reload()
        }
    }

    func markAllRead() async {
        if await service.markAllRead() {
            await reload()
        }
    }

    func batchMarkRead(ids: Set<UUID>) async {
        if await service.batchMarkRead(ids: ids) {
            await reload()
        }
    }

    func batchMarkUnread(ids: Set<UUID>) async {
        if await service.batchMarkUnread(ids: ids) {
            await reload()
        }
    }

    func clearRead() async {
        if await service.clearRead() {
            await reload()
        }
    }

    private func backedLibraryIdentifiers(from papers: [Paper]) -> (arxivIds: Set<String>, dois: Set<String>) {
        let backedPapers = papers.filter(hasBackedPDF)
        return (
            Set(backedPapers.compactMap(\.arxivId)),
            Set(backedPapers.compactMap(\.doi))
        )
    }

    private func hasBackedPDF(_ paper: Paper) -> Bool {
        guard let filePath = paper.filePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !filePath.isEmpty else {
            return false
        }
        return FileManager.default.fileExists(atPath: filePath)
    }

    private func updatePublishedValue<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<FeedViewModel, Value>,
        to newValue: Value
    ) {
        guard self[keyPath: keyPath] != newValue else { return }
        self[keyPath: keyPath] = newValue
    }
}
