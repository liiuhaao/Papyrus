import Foundation

struct MetadataResolver {
    let preset: MetadataPreset

    init(preset: MetadataPreset = .general) {
        self.preset = preset
    }

    func resolve(seed: MetadataSeed, candidates: [MetadataCandidate]) -> MetadataResolution {
        let ranked = rank(seed: seed, candidates: candidates)
        guard let best = ranked.first else {
            return MetadataResolution(metadata: nil, candidates: [], trace: "no-candidates", selectedSource: nil, selectedScore: nil)
        }

        let acceptedScore = score(seed: seed, candidate: best)
        guard acceptedScore >= acceptanceThreshold(for: best),
              passesTitleEvidenceGuard(seed: seed, candidate: best) else {
            return MetadataResolution(metadata: nil, candidates: ranked, trace: "best-score=\(acceptedScore)", selectedSource: best.source, selectedScore: acceptedScore)
        }

        let merged = merge(seed: seed, ranked: ranked)
        return MetadataResolution(metadata: merged, candidates: ranked, trace: "accepted=\(best.source) score=\(acceptedScore)", selectedSource: best.source, selectedScore: acceptedScore)
    }

    // MARK: - Ranking

    private func rank(seed: MetadataSeed, candidates: [MetadataCandidate]) -> [MetadataCandidate] {
        var seen = Set<String>()
        let deduped = candidates.filter { candidate in
            let key = [
                MetadataNormalization.normalizeTitle(candidate.metadata.title) ?? "",
                MetadataNormalization.normalizedDOI(candidate.metadata.doi) ?? "",
                candidate.metadata.arxivId?.lowercased() ?? "",
                candidate.source
            ].joined(separator: "|")
            return seen.insert(key).inserted
        }

        return deduped.sorted { lhs, rhs in
            let left = score(seed: seed, candidate: lhs)
            let right = score(seed: seed, candidate: rhs)
            if left != right { return left > right }
            return lhs.sourcePriority > rhs.sourcePriority
        }
    }

    // MARK: - Scoring

    private func score(seed: MetadataSeed, candidate: MetadataCandidate) -> Double {
        var total = candidate.sourcePriority + candidate.sourceConfidence
        total += seed.searchTitles
            .map { MetadataNormalization.titleSimilarity($0, candidate.metadata.title) }
            .max() ?? 0
        total += (seed.searchTitles
            .map { MetadataNormalization.titleTokenCoverage($0, candidate.metadata.title) }
            .max() ?? 0) * 0.45
        total += (seed.searchTitles
            .map { MetadataNormalization.titleBigramOverlap($0, candidate.metadata.title) }
            .max() ?? 0) * 0.35
        total += (seed.searchTitles
            .map { MetadataNormalization.titleAnchoredTokenCoverage($0, candidate.metadata.title) }
            .max() ?? 0) * 0.2
        total += MetadataCompleteness.score(candidate.metadata) * 0.35
        total += sourceContextBonus(seed: seed, candidate: candidate)

        let seedAuthors = MetadataNormalization.authorTokens(seed.authors)
        let candidateAuthors = MetadataNormalization.authorTokens(candidate.metadata.authors)
        if !seedAuthors.isEmpty, !candidateAuthors.isEmpty {
            total += min(0.18, Double(seedAuthors.intersection(candidateAuthors).count) * 0.06)
        }

        if seed.year > 0, candidate.metadata.year > 0 {
            let delta = abs(Int(seed.year) - Int(candidate.metadata.year))
            if delta == 0 {
                total += 0.12
            } else if delta == 1 {
                total += 0.06
            } else if delta >= 3 {
                total -= 0.1
            }
        }

        if candidate.metadata.doi?.isEmpty == false { total += 0.08 } else { total -= 0.1 }
        if candidate.metadata.arxivId?.isEmpty == false { total += 0.05 }
        if candidate.metadata.venue?.isEmpty == false {
            total += 0.18
        } else {
            total -= 0.3
        }
        if candidate.metadata.abstract?.isEmpty == false { total += 0.02 }

        if MetadataCompleteness.isFormalPublication(candidate.metadata) { total += 0.08 }
        if MetadataCompleteness.isPreprint(candidate.metadata) { total -= 0.02 }

        if case .doi = candidate.matchKind { total += 0.2 }
        if case .arxiv = candidate.matchKind { total += 0.3 }
        if case .exactTitle = candidate.matchKind { total += 0.08 }

        total += presetSpecificBonus(seed: seed, candidate: candidate)

        return total
    }

    private func acceptanceThreshold(for candidate: MetadataCandidate) -> Double {
        switch candidate.matchKind {
        case .doi, .arxiv:
            return 0.6
        case .exactTitle:
            return 1.08
        case .fuzzyTitle:
            return 1.4
        }
    }

    private func passesTitleEvidenceGuard(seed: MetadataSeed, candidate: MetadataCandidate) -> Bool {
        guard case .fuzzyTitle = candidate.matchKind else { return true }
        let similarity = seed.searchTitles
            .map { MetadataNormalization.titleSimilarity($0, candidate.metadata.title) }
            .max() ?? 0
        let coverage = seed.searchTitles
            .map { MetadataNormalization.titleTokenCoverage($0, candidate.metadata.title) }
            .max() ?? 0
        let bigram = seed.searchTitles
            .map { MetadataNormalization.titleBigramOverlap($0, candidate.metadata.title) }
            .max() ?? 0
        let anchoredCoverage = seed.searchTitles
            .map { MetadataNormalization.titleAnchoredTokenCoverage($0, candidate.metadata.title) }
            .max() ?? 0

        if similarity >= 0.92 { return true }
        if anchoredCoverage == 0, coverage < 0.8 {
            return false
        }
        return coverage >= 0.78 || (coverage >= 0.62 && bigram >= 0.4 && anchoredCoverage >= 0.5)
    }

    private func isLikelySameWork(seed: MetadataSeed, candidate: MetadataCandidate) -> Bool {
        let coverage = seed.searchTitles
            .map { MetadataNormalization.titleTokenCoverage($0, candidate.metadata.title) }
            .max() ?? 0
        let bigram = seed.searchTitles
            .map { MetadataNormalization.titleBigramOverlap($0, candidate.metadata.title) }
            .max() ?? 0
        let anchoredCoverage = seed.searchTitles
            .map { MetadataNormalization.titleAnchoredTokenCoverage($0, candidate.metadata.title) }
            .max() ?? 0
        let similarity = seed.searchTitles
            .map { MetadataNormalization.titleSimilarity($0, candidate.metadata.title) }
            .max() ?? 0
        return similarity >= 0.95
            || coverage >= 0.84
            || (coverage >= 0.7 && bigram >= 0.5 && anchoredCoverage >= 0.5)
    }

    // MARK: - Merge (source-atomic selection)

    private func merge(seed: MetadataSeed, ranked: [MetadataCandidate]) -> PaperMetadata {
        // Partition into formal and informal candidates.
        let formal = ranked.filter { isReliableFormal($0, seed: seed) }
        let informal = ranked.filter { !isReliableFormal($0, seed: seed) }

        // Pick the best candidate: formal first, then informal.
        let chosen: MetadataCandidate?
        if let bestFormal = formal.first {
            chosen = bestFormal
        } else if let bestInformal = informal.first {
            chosen = bestInformal
        } else {
            chosen = nil
        }

        var result = PaperMetadata()
        if let candidate = chosen {
            // Use the chosen candidate atomically; fall back to seed for missing fields.
            result.title = candidate.metadata.title ?? seed.title
            result.authors = candidate.metadata.authors ?? seed.authors
            result.venue = candidate.metadata.venue
            result.year = candidate.metadata.year > 0 ? candidate.metadata.year : seed.year
            result.doi = candidate.metadata.doi ?? seed.doi
            result.arxivId = candidate.metadata.arxivId ?? seed.arxivId
            result.abstract = candidate.metadata.abstract ?? seed.abstract
            result.venueAcronym = candidate.metadata.venueAcronym
            result.citationCount = candidate.metadata.citationCount
        } else {
            // No usable candidate at all — fall back to the PDF seed.
            result.title = seed.title
            result.authors = seed.authors
            result.venue = seed.venue
            result.year = seed.year
            result.doi = seed.doi
            result.arxivId = seed.arxivId
            result.abstract = seed.abstract
        }

        result.publicationType = MetadataParsers.inferPublicationType(
            venue: result.venue,
            doi: result.doi,
            arxivId: result.arxivId
        )

        return result
    }

    /// A candidate is considered a reliable formal publication if:
    /// - It has a venue that is a conference or journal (not a preprint)
    /// - Its title matches the seed well enough to be trusted
    private func isReliableFormal(_ candidate: MetadataCandidate, seed: MetadataSeed) -> Bool {
        guard let venue = candidate.metadata.venue, !venue.isEmpty else { return false }
        let type = MetadataParsers.inferPublicationType(
            venue: venue,
            doi: candidate.metadata.doi,
            arxivId: candidate.metadata.arxivId
        )
        guard type == "conference" || type == "journal" else { return false }

        let similarity = seed.searchTitles
            .map { MetadataNormalization.titleSimilarity($0, candidate.metadata.title) }
            .max() ?? 0
        return similarity >= 0.7
    }

    // MARK: - Bonuses & helpers

    private func sourceContextBonus(seed: MetadataSeed, candidate: MetadataCandidate) -> Double {
        var bonus = 0.0

        let source = candidate.source.lowercased()
        let seedWantsFormal = wantsFormalPublication(seed)
        if seedWantsFormal {
            if source.contains("dblp"), MetadataCompleteness.isFormalPublication(candidate.metadata) { bonus += 0.12 }
            if source.contains("crossref"), MetadataCompleteness.isFormalPublication(candidate.metadata) { bonus += 0.05 }
            if source.contains("openalex"), MetadataCompleteness.isFormalPublication(candidate.metadata) { bonus += 0.04 }
            if MetadataCompleteness.isFormalPublication(candidate.metadata) { bonus += 0.08 }
            if MetadataCompleteness.isPreprint(candidate.metadata) { bonus -= 0.08 }
        }

        if seed.arxivId != nil, seed.doi == nil,
           MetadataCompleteness.isFormalPublication(candidate.metadata),
           (seed.searchTitles.map { MetadataNormalization.titleSimilarity($0, candidate.metadata.title) }.max() ?? 0) >= 0.9 {
            bonus += 0.12
        }

        return bonus
    }

    private func presetSpecificBonus(seed: MetadataSeed, candidate: MetadataCandidate) -> Double {
        let source = candidate.source.lowercased()
        switch preset {
        case .general:
            return 0
        case .cs:
            var bonus = 0.0
            if source.contains("dblp"), MetadataCompleteness.isFormalPublication(candidate.metadata) { bonus += 0.12 }
            if source.contains("openreview") { bonus += 0.08 }
            if source.contains("crossref") { bonus -= 0.02 }
            if MetadataCompleteness.isFormalPublication(candidate.metadata) { bonus += 0.04 }
            if source.contains("semanticscholar"), candidate.metadata.venue?.isEmpty == false { bonus += 0.10 }
            return bonus
        case .physics:
            var bonus = 0.0
            if source.contains("arxiv") { bonus += 0.1 }
            if MetadataCompleteness.isPreprint(candidate.metadata) { bonus += 0.06 }
            if source.contains("openreview") || source.contains("dblp") { bonus -= 0.05 }
            return bonus
        case .biomed:
            var bonus = 0.0
            if case .doi = candidate.matchKind { bonus += 0.08 }
            if source.contains("crossref") { bonus += 0.05 }
            if source.contains("openalex") { bonus += 0.04 }
            if MetadataCompleteness.isFormalPublication(candidate.metadata) { bonus += 0.05 }
            if MetadataCompleteness.isPreprint(candidate.metadata) { bonus -= 0.08 }
            return bonus
        }
    }

    private func wantsFormalPublication(_ seed: MetadataSeed) -> Bool {
        let title = (seed.title ?? "").lowercased()
        let filename = (seed.originalFilename ?? "").lowercased()
        let venue = (seed.venue ?? "").lowercased()
        let text = [title, filename, venue].joined(separator: " ")

        let conferenceHints = [
            "iclr", "icml", "neurips", "nips", "cvpr", "iccv", "eccv",
            "acl", "emnlp", "naacl", "aaai", "ijcai", "kdd", "sigir", "workshop"
        ]
        if conferenceHints.contains(where: { text.contains($0) }) {
            return true
        }
        return seed.doi == nil
    }
}
