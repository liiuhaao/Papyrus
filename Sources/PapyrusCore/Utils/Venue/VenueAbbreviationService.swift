// VenueAbbreviationService.swift
// Maps full venue names to standard abbreviations.
// Priority: Semantic Scholar publicationVenue.acronym → DBLP venue search → VenueFormatter rules

import Foundation

actor VenueAbbreviationService: VenueAbbreviationProviding {
    nonisolated static let shared = VenueAbbreviationService()

    // Written only inside actor, read nonisolated for sync badge display
    private nonisolated(unsafe) var cache: [String: String] = [:]
    private var inFlight: Set<String> = []
    private let requestLimiter = AsyncLimiter(maxConcurrent: 1)

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Papyrus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("venue_abbr_cache.json")
    }()

    init() { Task { await loadDiskCache() } }

    // MARK: - Public

    /// Synchronous cache read for display (returns nil if not yet resolved)
    nonisolated func cached(venue: String) -> String? {
        cache[venue.lowercased()]
    }

    /// Store an acronym from Semantic Scholar's publicationVenue.acronym
    func store(venue: String, acronym: String) {
        let key = venue.lowercased()
        let normalized = canonicalAcronym(acronym, venue: venue)
        guard !normalized.isEmpty, cache[key] != normalized else { return }
        cache[key] = normalized
        saveDiskCache()
    }

    /// Fetch from DBLP if no acronym is cached for this venue
    func fetchFromDBLPIfNeeded(venue: String) async {
        let key = venue.lowercased()
        guard cache[key] == nil, !inFlight.contains(key), venue.count > 8 else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        if let acronym = await queryDBLP(venue: venue) {
            let normalized = canonicalAcronym(acronym, venue: venue)
            guard !normalized.isEmpty else { return }
            cache[key] = normalized
            saveDiskCache()
        }
    }

    // MARK: - DBLP Query

    private func queryDBLP(venue: String) async -> String? {
        guard let encoded = venue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://dblp.org/search/venue/api?q=\(encoded)&format=json&h=5")
        else { return nil }

        do {
            let (data, _) = try await performRequest {
                try await URLSession.shared.data(from: url)
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [String: Any],
                  let hits = result["hits"] as? [String: Any]
            else { return nil }

            // DBLP returns "hit" as array or single dict depending on result count
            var hitList: [[String: Any]] = []
            if let arr = hits["hit"] as? [[String: Any]] {
                hitList = arr
            } else if let single = hits["hit"] as? [String: Any] {
                hitList = [single]
            }

            let normalizedQuery = venue.lowercased()
            for hit in hitList {
                guard let info = hit["info"] as? [String: Any],
                      let acronym = info["acronym"] as? String, !acronym.isEmpty,
                      let hitVenue = info["venue"] as? String
                else { continue }
                let normalizedHit = hitVenue.lowercased()
                if normalizedHit.contains(normalizedQuery) || normalizedQuery.contains(normalizedHit) {
                    return acronym
                }
            }
            // Fallback: first hit's acronym
            if let first = hitList.first,
               let info = first["info"] as? [String: Any],
               let acronym = info["acronym"] as? String, !acronym.isEmpty {
                return acronym
            }
        } catch {}
        return nil
    }

    private func performRequest<T>(
        maxAttempts: Int = 3,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var delayNanoseconds: UInt64 = 1_000_000_000
        var lastError: Error = URLError(.unknown)

        for attempt in 1...maxAttempts {
            await requestLimiter.acquire()
            defer { Task { await requestLimiter.release() } }

            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < maxAttempts, shouldRetry(error) else { throw error }
            }

            let jitter = UInt64.random(in: 0...250_000_000)
            try await Task.sleep(nanoseconds: delayNanoseconds + jitter)
            delayNanoseconds *= 2
        }

        throw lastError
    }

    private func shouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .networkConnectionLost, .notConnectedToInternet, .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    // MARK: - Disk Cache

    private func loadDiskCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        var normalizedCache: [String: String] = [:]
        var changed = false
        for (key, value) in decoded {
            let normalized = canonicalAcronym(value, venue: key)
            normalizedCache[key] = normalized
            if normalized != value {
                changed = true
            }
        }
        cache = normalizedCache
        if changed {
            saveDiskCache()
        }
    }

    private func saveDiskCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func canonicalAcronym(_ raw: String, venue: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let lowered = trimmed.lowercased()
        if lowered == "nips" || lowered == "neurips" {
            return "NeurIPS"
        }

        let venueLower = venue.lowercased()
        if venueLower.contains("neural information processing systems")
            || venueLower.contains("advances in neural information processing systems")
            || venueLower.contains("neurips")
            || venueLower.contains("nips") {
            return "NeurIPS"
        }

        return trimmed
    }
}
