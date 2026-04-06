import Foundation

struct FeedSubscription: Codable, Identifiable, Equatable {
    let id: UUID
    var type: SubscriptionType
    var value: String
    var displayLabel: String
    var isEnabled: Bool
    var lastFetchedAt: Date?

    enum SubscriptionType: String, Codable, CaseIterable {
        case rssURL = "rss_url"

        var displayName: String { "RSS / Atom" }
        var placeholder: String { "https://..." }
        var systemImage: String { "dot.radiowaves.up.forward" }
    }

    init(
        id: UUID = UUID(),
        type: SubscriptionType,
        value: String,
        displayLabel: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.type = type
        self.value = value
        self.displayLabel = displayLabel ?? value
        self.isEnabled = isEnabled
        self.lastFetchedAt = nil
    }
}

// MARK: - Persistence

extension FeedSubscription {
    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Papyrus")
            .appendingPathComponent("subscriptions.json")
    }

    static func loadAll() -> [FeedSubscription] {
        guard let data = try? Data(contentsOf: storageURL),
              let rawArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        // Decode item-by-item so subscriptions with unknown/legacy types are silently dropped
        return rawArray.compactMap { dict in
            guard let itemData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? JSONDecoder().decode(FeedSubscription.self, from: itemData)
        }
    }

    static func saveAll(_ subscriptions: [FeedSubscription]) {
        let url = storageURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(subscriptions) else { return }
        try? data.write(to: url)
    }
}
