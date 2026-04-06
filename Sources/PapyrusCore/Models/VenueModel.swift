// VenueModel.swift
// Core Data entity for venue metadata (rank sources, abbreviation)

import Foundation
import CoreData

@objc(Venue)
public class Venue: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Venue> {
        return NSFetchRequest<Venue>(entityName: "Venue")
    }

    @NSManaged public var name: String
    @NSManaged public var abbreviation: String?
    @NSManaged public var rankSourceJSON: String?
    @NSManaged public var papers: NSSet?
}

extension Venue {
    var displayName: String { abbreviation ?? name }

    var rankSources: [String: String] {
        var sources: [String: String] = [:]

        if let rankSourceJSON,
           let data = rankSourceJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            for (key, value) in decoded where !key.isEmpty && !value.isEmpty {
                sources[key.lowercased()] = value
            }
        }

        return sources
    }

    func setRankSources(_ sources: [String: String]) {
        let normalized = sources.reduce(into: [String: String]()) { partial, pair in
            let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            partial[key] = value
        }

        if let data = try? JSONEncoder().encode(normalized) {
            rankSourceJSON = String(data: data, encoding: .utf8)
        } else {
            rankSourceJSON = nil
        }
    }

    func orderedRankEntries(visibleSourceKeys: [String]) -> [(String, String)] {
        let sources = rankSources
        let visibleKeys = RankSourceConfig.normalizedKeys(visibleSourceKeys)

        if !visibleKeys.isEmpty {
            return visibleKeys.compactMap { key in
                guard let value = sources[key] else { return nil }
                return (key, value)
            }
        }

        return RankProfiles.sortEntries(sources.map { ($0.key, $0.value) })
    }
}
