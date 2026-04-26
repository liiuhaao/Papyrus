import Foundation

struct MetadataResolver {
    let preset: MetadataPreset

    init(preset: MetadataPreset = .general) {
        self.preset = preset
    }

    func resolve(seed: MetadataSeed, candidates: [MetadataCandidate]) -> MetadataResolution {
        let ranked = rank(seed: seed, candidates: candidates)
        guard let best = ranked.first else {
            return MetadataResolution(metadata: nil, candidates: [], trace: "no-candidates")
        }

        let acceptedScore = score(seed: seed, candidate: best)
        guard acceptedScore >= acceptanceThreshold(for: best),
              passesTitleEvidenceGuard(seed: seed, candidate: best) else {
            return MetadataResolution(metadata: nil, candidates: ranked, trace: "best-score=\(acceptedScore)")
        }

        if isLikelyPrepublication(seed),
           !isLikelySameWork(seed: seed, candidate: best) {
            return MetadataResolution(metadata: nil, candidates: ranked, trace: "rejected-prepublication-mismatch")
        }

        let merged = merge(seed: seed, ranked: ranked)
        return MetadataResolution(metadata: merged, candidates: ranked, trace: "accepted=\(best.source) score=\(acceptedScore)")
    }

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

        if candidate.metadata.doi?.isEmpty == false { total += 0.1 }
        if candidate.metadata.arxivId?.isEmpty == false { total += 0.05 }
        if candidate.metadata.venue?.isEmpty == false { total += 0.04 }
        if candidate.metadata.abstract?.isEmpty == false { total += 0.02 }

        if MetadataCompleteness.isFormalPublication(candidate.metadata) { total += 0.08 }
        if MetadataCompleteness.isPreprint(candidate.metadata) { total -= 0.02 }

        if case .doi = candidate.matchKind { total += 0.2 }
        if case .arxiv = candidate.matchKind { total += 0.2 }
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

    private func isLikelyPrepublication(_ seed: MetadataSeed) -> Bool {
        let filename = (seed.originalFilename ?? "").lowercased()
        let title = (seed.title ?? "").lowercased()
        let text = filename + " " + title
        if text.contains("iclr 2026") || text.contains("icml 2026") || text.contains("neurips 2026") {
            return true
        }
        if text.contains("published as a conference paper at") {
            return true
        }
        return seed.year >= 2026 && seed.doi == nil
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

    private func merge(seed: MetadataSeed, ranked: [MetadataCandidate]) -> PaperMetadata {
        var merged = PaperMetadata()
        merged.title = seed.title
        merged.authors = seed.authors
        merged.venue = seed.venue
        merged.year = seed.year
        merged.doi = seed.doi
        merged.arxivId = seed.arxivId
        merged.abstract = seed.abstract

        for candidate in ranked.reversed() {
            apply(candidate.metadata, to: &merged)
        }

        // When the PDF seed identifies a formal publication (conference/journal)
        // but online sources returned an arXiv/preprint record, preserve the seed's
        // venue and year instead of overwriting with the preprint source.
        if let seedVenue = seed.venue,
           let seedType = MetadataParsers.inferPublicationType(venue: seedVenue, doi: nil, arxivId: nil),
           seedType == "conference" || seedType == "journal" {
            let mergedType = MetadataParsers.inferPublicationType(venue: merged.venue, doi: nil, arxivId: nil)
            if mergedType == "preprint" || mergedType == nil || merged.venue == nil {
                merged.venue = seedVenue
            }
            if seed.year > 0 {
                merged.year = seed.year
            }
        }

        if merged.publicationType == nil {
            merged.publicationType = MetadataParsers.inferPublicationType(
                venue: merged.venue,
                doi: merged.doi,
                arxivId: merged.arxivId
            )
        }

        return merged
    }

    private func apply(_ candidate: PaperMetadata, to merged: inout PaperMetadata) {
        if let title = candidate.title, !title.isEmpty { merged.title = title }
        if let authors = candidate.authors, !authors.isEmpty { merged.authors = authors }
        if let venue = candidate.venue, !venue.isEmpty {
            let candidateIsFormal = MetadataCompleteness.isFormalPublication(candidate)
            let mergedIsFormal = MetadataCompleteness.isFormalPublication(merged)
            if !mergedIsFormal || candidateIsFormal {
                merged.venue = venue
            }
        }
        if let venueAcronym = candidate.venueAcronym, !venueAcronym.isEmpty { merged.venueAcronym = venueAcronym }
        if candidate.year > 0 { merged.year = candidate.year }
        if let doi = candidate.doi, !doi.isEmpty { merged.doi = doi }
        if let arxivId = candidate.arxivId, !arxivId.isEmpty { merged.arxivId = arxivId }
        if let abstract = candidate.abstract, !abstract.isEmpty { merged.abstract = abstract }
        if let publicationType = candidate.publicationType, !publicationType.isEmpty { merged.publicationType = publicationType }
        if let citationCount = candidate.citationCount { merged.citationCount = citationCount }
    }

    private func sourceContextBonus(seed: MetadataSeed, candidate: MetadataCandidate) -> Double {
        var bonus = 0.0

        let source = candidate.source.lowercased()
        let seedWantsFormal = wantsFormalPublication(seed)
        if seedWantsFormal {
            if source.contains("dblp") { bonus += 0.12 }
            if source.contains("crossref") { bonus += 0.05 }
            if source.contains("openalex") { bonus += 0.04 }
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
            if source.contains("dblp") { bonus += 0.12 }
            if source.contains("openreview") { bonus += 0.08 }
            if source.contains("crossref") { bonus -= 0.02 }
            if MetadataCompleteness.isFormalPublication(candidate.metadata) { bonus += 0.04 }
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
