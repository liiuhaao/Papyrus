// JournalRankService.swift
// Venue rank lookup via EasyScholar open API.
// API key configured in the Settings panel under API Keys

import Foundation

struct JournalRankInfo: Codable {
    var sources: [String: String]

    init(sources: [String: String] = [:]) {
        self.sources = sources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sources = try container.decodeIfPresent([String: String].self, forKey: .sources) ?? [:]
    }
}

actor JournalRankService: RankProviding {
    nonisolated static let shared = JournalRankService()

    // nonisolated(unsafe): written only during actor-isolated fetch, read-only elsewhere
    private nonisolated(unsafe) var cache: [String: JournalRankInfo] = [:]
    private var inFlight: Set<String> = []
    private let requestLimiter = AsyncLimiter(maxConcurrent: 1)

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Papyrus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("journal_rank_cache.json")
    }()

    init() {
        Task { await loadDiskCache() }
    }

    // MARK: - Public

    /// Synchronous cache-only read (for badge display).
    nonisolated func cached(venue: String) -> JournalRankInfo? {
        let keys = Self.cacheLookupKeys(for: venue)
        var mergedSources: [String: String] = [:]
        for key in keys {
            guard let info = cache[key] else { continue }
            for (source, value) in info.sources where !value.isEmpty {
                mergedSources[source] = value
            }
        }
        guard !mergedSources.isEmpty else { return nil }
        return JournalRankInfo(sources: mergedSources)
    }

    /// Fetch from EasyScholar if not cached. Call during import / refresh metadata.
    func fetchIfNeeded(venue: String) async {
        let key = venue.lowercased()
        guard !inFlight.contains(key) else { return }
        if cache[key] != nil {
            return
        }
        let apiKey = await MainActor.run { AppConfig.shared.easyscholarKey }
        guard !apiKey.isEmpty else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        if let info = await queryEasyScholarBestMatch(for: venue, apiKey: apiKey) {
            cache[key] = mergeRankInfo(existing: cache[key], incoming: info)
            saveDiskCache()
        }
    }

    /// Force re-fetch from EasyScholar, ignoring cache. Call when refreshing all venue rankings.
    func fetchForce(venue: String) async {
        let key = venue.lowercased()
        guard !inFlight.contains(key) else { return }
        let apiKey = await MainActor.run { AppConfig.shared.easyscholarKey }
        guard !apiKey.isEmpty else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        if let info = await queryEasyScholarBestMatch(for: venue, apiKey: apiKey) {
            cache[key] = mergeRankInfo(existing: cache[key], incoming: info)
            saveDiskCache()
        }
    }

    // MARK: - EasyScholar API

    private func queryEasyScholarBestMatch(for venue: String, apiKey: String) async -> JournalRankInfo? {
        let candidates = queryNameCandidates(for: venue)
        var merged: [String: String] = [:]
        for candidate in candidates {
            guard let info = await queryEasyScholar(name: candidate, apiKey: apiKey) else { continue }
            for (source, value) in info.sources where !value.isEmpty {
                merged[source] = value
            }
        }
        if merged.isEmpty { return nil }
        return JournalRankInfo(sources: merged)
    }

    private func queryNameCandidates(for venue: String) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return }
            output.append(trimmed)
        }

        append(venue)
        append(VenueFormatter.unifiedFullName(venue))
        append(VenueFormatter.unifiedDisplayName(venue))
        append(Self.normalizedVenueQueryName(venue))
        append(Self.normalizedVenueQueryName(VenueFormatter.unifiedFullName(venue)))
        append(Self.normalizedVenueQueryName(VenueFormatter.unifiedDisplayName(venue)))

        return output
    }

    private nonisolated static func cacheLookupKeys(for venue: String) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        func append(_ value: String) {
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            output.append(key)
        }

        append(venue)
        append(VenueFormatter.unifiedFullName(venue))
        append(VenueFormatter.unifiedDisplayName(venue))
        append(normalizedVenueQueryName(venue))
        append(normalizedVenueQueryName(VenueFormatter.unifiedFullName(venue)))
        append(normalizedVenueQueryName(VenueFormatter.unifiedDisplayName(venue)))

        return output
    }

    private nonisolated static func normalizedVenueQueryName(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return value }

        // Strip parenthetical details like "(NeurIPS 2023)".
        value = value.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        // Strip trailing "volume"/edition numbers and years often present in proceedings titles.
        value = value.replacingOccurrences(of: #"\b\d{2,4}\b$"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\b(vol(?:ume)?\.?\s*)?\d{1,3}\b$"#, with: "", options: .regularExpression)
        // Remove leading boilerplate wrapper.
        value = value.replacingOccurrences(of: #"(?i)^proceedings of (the )?"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // EasyScholar tends to index NeurIPS under this canonical name.
        let lowered = value.lowercased()
        if lowered.contains("advances in neural information processing systems")
            || lowered.contains("neural information processing systems")
            || lowered == "neurips"
            || lowered == "nips" {
            return "Neural Information Processing Systems"
        }

        return value
    }

    private func queryEasyScholar(name: String, apiKey: String) async -> JournalRankInfo? {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.easyscholar.cc/open/getPublicationRank?secretKey=\(apiKey)&publicationName=\(encoded)")
        else { return nil }

        do {
            let (data, _) = try await performRequest {
                try await URLSession.shared.data(from: url)
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseData = json["data"] as? [String: Any],
                  let officialRank = responseData["officialRank"] as? [String: Any]
            else { return nil }

            let rawSources = normalizedSources(from: officialRank)
            guard !rawSources.isEmpty else { return nil }
            return JournalRankInfo(sources: rawSources)
        } catch {
            return nil
        }
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

    private func normalizedSources(from raw: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in raw {
            collectSourceEntries(path: [normalizedToken(key)], value: value, into: &result)
        }
        return result
    }

    private func collectSourceEntries(path: [String], value: Any, into output: inout [String: String]) {
        if let scalar = normalizedScalarString(value),
           !scalar.isEmpty,
           let key = sourceKey(from: path) {
            output[key] = scalar
            return
        }

        if let dict = value as? [String: Any] {
            if let key = sourceKey(from: path),
               let scalar = firstScalarField(in: dict),
               !scalar.isEmpty {
                output[key] = scalar
            }

            for (childKey, childValue) in dict {
                let token = normalizedToken(childKey)
                guard !token.isEmpty else { continue }
                collectSourceEntries(path: path + [token], value: childValue, into: &output)
            }
            return
        }

        if let list = value as? [Any], !list.isEmpty {
            let scalars = list.compactMap(normalizedScalarString).filter { !$0.isEmpty }
            if let key = sourceKey(from: path),
               !scalars.isEmpty {
                output[key] = scalars.joined(separator: ", ")
                return
            }
            for child in list {
                collectSourceEntries(path: path, value: child, into: &output)
            }
        }
    }

    private func firstScalarField(in dict: [String: Any]) -> String? {
        let preferred = ["value", "rank", "grade", "level", "label", "result"]
        for key in preferred {
            if let value = dict[key], let scalar = normalizedScalarString(value), !scalar.isEmpty {
                return scalar
            }
        }
        return nil
    }

    private func normalizedScalarString(_ value: Any) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func normalizedToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func sourceKey(from path: [String]) -> String? {
        let wrappers: Set<String> = ["all", "data", "rank", "ranks", "officialrank"]
        for token in path {
            let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            if wrappers.contains(cleaned) { continue }
            return cleaned
        }
        return nil
    }

    private func mergeRankInfo(existing: JournalRankInfo?, incoming: JournalRankInfo) -> JournalRankInfo {
        guard let existing else { return incoming }
        var sources = existing.sources
        for (source, value) in incoming.sources where !value.isEmpty {
            sources[source] = value
        }
        return JournalRankInfo(sources: sources)
    }

    // MARK: - Disk Cache

    private func loadDiskCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([String: JournalRankInfo].self, from: data)
        else { return }
        cache = decoded
    }

    private func saveDiskCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
