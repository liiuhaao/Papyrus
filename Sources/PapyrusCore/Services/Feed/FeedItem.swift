import Foundation

struct FeedItem: Codable, Identifiable, Equatable {
    let id: UUID
    var arxivId: String?
    var doi: String?
    var title: String
    var authors: String
    var abstract: String?
    var year: Int
    var venue: String?
    var pdfURL: String?
    var landingURL: String?
    let fetchedAt: Date
    let subscriptionId: UUID
    let subscriptionLabel: String
    var status: Status

    enum Status: String, Codable {
        case unread
        case read

        var label: String {
            switch self {
            case .unread: return "Unread"
            case .read:   return "Read"
            }
        }

        var color: String {
            switch self {
            case .unread: return "blue"
            case .read:   return "green"
            }
        }
    }

    var displayAuthors: String {
        let names = authors
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if names.count > 3 {
            return names.prefix(3).joined(separator: ", ") + " et al."
        }
        return authors.isEmpty ? "Unknown authors" : authors
    }
}

// MARK: - Persistence

extension FeedItem {
    func matchesSearch(_ rawQuery: String) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return title.lowercased().contains(query)
            || displayAuthors.lowercased().contains(query)
            || (venue?.lowercased().contains(query) ?? false)
            || (abstract?.lowercased().contains(query) ?? false)
    }

    private static var storageDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Papyrus")
    }

    private static var storageURL: URL {
        storageDirectoryURL.appendingPathComponent("feed_items.json")
    }

    static func loadAll() -> [FeedItem] {
        guard let data = try? Data(contentsOf: storageURL),
              let items = try? JSONDecoder().decode([FeedItem].self, from: data) else {
            return []
        }

        return items
    }

    static func saveAll(_ items: [FeedItem]) {
        let url = storageURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url)
    }
}
