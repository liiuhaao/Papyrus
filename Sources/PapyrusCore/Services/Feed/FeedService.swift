import Foundation

actor FeedService {
    static let shared = FeedService()

    private var subscriptions: [FeedSubscription] = []
    private var feedItems: [FeedItem] = []
    private let rssFetcher = GenericRSSFetcher()
    private let limiter = AsyncLimiter(maxConcurrent: 2)

    private init() {}

    // MARK: - Load

    func load() {
        subscriptions = FeedSubscription.loadAll()
        feedItems = FeedItem.loadAll()
    }

    // MARK: - Subscriptions

    func allSubscriptions() -> [FeedSubscription] { subscriptions }

    func addSubscription(_ sub: FeedSubscription) -> Bool {
        subscriptions.append(sub)
        FeedSubscription.saveAll(subscriptions)
        return true
    }

    func removeSubscription(id: UUID) -> Bool {
        let originalSubscriptionCount = subscriptions.count
        let originalItemCount = feedItems.count
        subscriptions.removeAll { $0.id == id }
        feedItems.removeAll { $0.subscriptionId == id }
        let didChangeSubscriptions = subscriptions.count != originalSubscriptionCount
        let didChangeItems = feedItems.count != originalItemCount
        if didChangeSubscriptions {
            FeedSubscription.saveAll(subscriptions)
        }
        if didChangeItems {
            FeedItem.saveAll(feedItems)
        }
        return didChangeSubscriptions || didChangeItems
    }

    func cleanupOrphanedItems() {
        let validIds = Set(subscriptions.map(\.id))
        let before = feedItems.count
        feedItems.removeAll { !validIds.contains($0.subscriptionId) }
        if feedItems.count != before {
            FeedItem.saveAll(feedItems)
        }
    }

    func clearItems(forSubscription id: UUID) -> Bool {
        let before = feedItems.count
        feedItems.removeAll { $0.subscriptionId == id }
        let didChange = feedItems.count != before
        if didChange { FeedItem.saveAll(feedItems) }
        return didChange
    }

    func updateSubscription(_ updated: FeedSubscription) -> Bool {
        guard let idx = subscriptions.firstIndex(where: { $0.id == updated.id }) else { return false }
        guard subscriptions[idx] != updated else { return false }
        subscriptions[idx] = updated
        FeedSubscription.saveAll(subscriptions)
        return true
    }

    // MARK: - Feed Items

    func allFeedItems() -> [FeedItem] { feedItems }

    func items(statusFilter: Set<FeedItem.Status> = [], subscriptionId: UUID? = nil) -> [FeedItem] {
        feedItems
            .filter {
                (statusFilter.isEmpty || statusFilter.contains($0.status))
                && (subscriptionId == nil || $0.subscriptionId == subscriptionId)
            }
            .sorted {
                if $0.year != $1.year { return $0.year > $1.year }
                return $0.fetchedAt > $1.fetchedAt
            }
    }

    /// 每个订阅各状态的数量（用于来源筛选行计数，基于当前 statusFilter）
    func countBySubscription(statusFilter: Set<FeedItem.Status> = []) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for item in feedItems where statusFilter.isEmpty || statusFilter.contains(item.status) {
            counts[item.subscriptionId, default: 0] += 1
        }
        return counts
    }

    func countByStatus() -> [FeedItem.Status: Int] {
        var counts: [FeedItem.Status: Int] = [:]
        for item in feedItems {
            counts[item.status, default: 0] += 1
        }
        return counts
    }

    func markRead(id: UUID) -> Bool {
        guard let idx = feedItems.firstIndex(where: { $0.id == id }) else { return false }
        guard feedItems[idx].status != .read else { return false }
        feedItems[idx].status = .read
        FeedItem.saveAll(feedItems)
        return true
    }

    func markUnread(id: UUID) -> Bool {
        guard let idx = feedItems.firstIndex(where: { $0.id == id }) else { return false }
        guard feedItems[idx].status != .unread else { return false }
        feedItems[idx].status = .unread
        FeedItem.saveAll(feedItems)
        return true
    }

    func markAllRead() -> Bool {
        var didChange = false
        for idx in feedItems.indices where feedItems[idx].status == .unread {
            feedItems[idx].status = .read
            didChange = true
        }
        if didChange {
            FeedItem.saveAll(feedItems)
        }
        return didChange
    }

    func batchMarkRead(ids: Set<UUID>) -> Bool {
        var didChange = false
        for idx in feedItems.indices where ids.contains(feedItems[idx].id) {
            guard feedItems[idx].status != .read else { continue }
            feedItems[idx].status = .read
            didChange = true
        }
        if didChange {
            FeedItem.saveAll(feedItems)
        }
        return didChange
    }

    func batchMarkUnread(ids: Set<UUID>) -> Bool {
        var didChange = false
        for idx in feedItems.indices where ids.contains(feedItems[idx].id) {
            guard feedItems[idx].status != .unread else { continue }
            feedItems[idx].status = .unread
            didChange = true
        }
        if didChange {
            FeedItem.saveAll(feedItems)
        }
        return didChange
    }

    func clearRead() -> Bool {
        let before = feedItems.count
        feedItems.removeAll { $0.status == .read }
        let didChange = feedItems.count != before
        if didChange {
            FeedItem.saveAll(feedItems)
        }
        return didChange
    }

    // MARK: - Fetch

    /// Fetch all enabled subscriptions. Returns count of newly discovered items.
    func fetchAll(existingArxivIds: Set<String>, existingDOIs: Set<String>) async -> Int {
        let enabled = subscriptions.filter(\.isEnabled)
        guard !enabled.isEmpty else { return 0 }

        // Collect existing feed arxivIds to avoid duplicates within the feed.
        let existingFeedIDs = Set(feedItems.compactMap(\.arxivId))

        var newItems: [FeedItem] = []
        await withTaskGroup(of: [FeedItem].self) { group in
            for sub in enabled {
                group.addTask {
                    await self.limiter.acquire()
                    defer { Task { await self.limiter.release() } }
                    return (try? await self.fetchSubscription(
                        sub,
                        existingArxivIds: existingArxivIds,
                        existingDOIs: existingDOIs,
                        existingFeedIDs: existingFeedIDs
                    )) ?? []
                }
            }
            for await items in group {
                newItems.append(contentsOf: items)
            }
        }

        // Deduplicate across concurrent results (same paper from multiple subs)
        var seen = Set<String>()
        let deduplicated = newItems.filter { item in
            guard let key = item.arxivId ?? item.doi else { return true }
            return seen.insert(key).inserted
        }

        feedItems.append(contentsOf: deduplicated)

        // Update lastFetchedAt for all enabled subscriptions
        let now = Date()
        for idx in subscriptions.indices where subscriptions[idx].isEnabled {
            subscriptions[idx].lastFetchedAt = now
        }

        FeedSubscription.saveAll(subscriptions)
        FeedItem.saveAll(feedItems)

        return deduplicated.count
    }

    private func fetchSubscription(
        _ subscription: FeedSubscription,
        existingArxivIds: Set<String>,
        existingDOIs: Set<String>,
        existingFeedIDs: Set<String>
    ) async throws -> [FeedItem] {
        guard let url = URL(string: subscription.value) else { return [] }
        let entries = try await rssFetcher.fetchEntries(url: url, after: subscription.lastFetchedAt)
        let calendar = Calendar.current
        return entries.compactMap { entry -> FeedItem? in
            if let aid = entry.arxivId, existingArxivIds.contains(aid) { return nil }
            if let doi = entry.doi, existingDOIs.contains(doi) { return nil }
            if let aid = entry.arxivId, existingFeedIDs.contains(aid) { return nil }

            let year = entry.publishedDate.map { calendar.component(.year, from: $0) }
                ?? calendar.component(.year, from: Date())
            let pdfURL = entry.arxivId.map { "https://arxiv.org/pdf/\($0)" }

            return FeedItem(
                id: UUID(),
                arxivId: entry.arxivId,
                doi: entry.doi,
                title: entry.title,
                authors: entry.authors,
                abstract: entry.abstract,
                year: year,
                venue: nil,
                pdfURL: pdfURL,
                landingURL: entry.landingURL,
                fetchedAt: Date(),
                subscriptionId: subscription.id,
                subscriptionLabel: subscription.displayLabel,
                status: .unread
            )
        }
    }
}
