import Foundation

struct ArxivMetadataSource: MetadataSource {
    let name = "arxiv"
    let phase: MetadataSourcePhase = .direct
    let fetchSemanticScholar: @Sendable (String) async throws -> PaperMetadata
    let fetchArxiv: @Sendable (String) async throws -> PaperMetadata
    let fetchCrossRefByDOI: @Sendable (String) async throws -> PaperMetadata
    let fetchOpenAlexByDOI: @Sendable (String) async throws -> PaperMetadata

    func collectCandidates(for seed: MetadataSeed) async -> [MetadataCandidate] {
        guard let arxivId = seed.arxivId, !arxivId.isEmpty else { return [] }

        async let s2Result = try? fetchSemanticScholar(arxivId)
        async let arxivResult = try? fetchArxiv(arxivId)

        let s2Metadata = await s2Result
        let arxivMetadata = await arxivResult

        var candidates: [MetadataCandidate] = []

        if let s2 = s2Metadata {
            candidates.append(MetadataCandidate(
                metadata: s2,
                source: "semanticScholar(arxiv)",
                matchKind: .arxiv,
                sourcePriority: 0.95,
                sourceConfidence: 0.95,
                trace: arxivId
            ))

            // Only fetch by DOI if it's a publisher DOI, not an arXiv DOI (10.48550/...)
            if let doi = s2.doi, !doi.lowercased().contains("10.48550") {
                async let crossRefResult = try? fetchCrossRefByDOI(doi)
                async let openAlexResult = try? fetchOpenAlexByDOI(doi)

                if let crossRef = await crossRefResult {
                    candidates.append(MetadataCandidate(
                        metadata: crossRef,
                        source: "crossref(doi)",
                        matchKind: .doi,
                        sourcePriority: 0.97,
                        sourceConfidence: 0.95,
                        trace: "arxivId=\(arxivId) doi=\(doi)"
                    ))
                }
                if let openAlex = await openAlexResult {
                    candidates.append(MetadataCandidate(
                        metadata: openAlex,
                        source: "openAlex(doi)",
                        matchKind: .doi,
                        sourcePriority: 0.94,
                        sourceConfidence: 0.92,
                        trace: "arxivId=\(arxivId) doi=\(doi)"
                    ))
                }
            }
        }

        if let arxiv = arxivMetadata {
            candidates.append(MetadataCandidate(
                metadata: arxiv,
                source: "arxiv",
                matchKind: .arxiv,
                sourcePriority: 0.92,
                sourceConfidence: 0.9,
                trace: arxivId
            ))
        }

        return candidates
    }
}

struct DOIMetadataSource: MetadataSource {
    let name = "doi"
    let phase: MetadataSourcePhase = .direct
    let fetchSemanticScholar: @Sendable (String) async throws -> PaperMetadata
    let fetchOpenAlex: @Sendable (String) async throws -> PaperMetadata
    let fetchCrossRef: @Sendable (String) async throws -> PaperMetadata

    func collectCandidates(for seed: MetadataSeed) async -> [MetadataCandidate] {
        guard let doi = MetadataNormalization.normalizedDOI(seed.doi), !doi.isEmpty else { return [] }
        return await withTaskGroup(of: MetadataCandidate?.self) { group in
            group.addTask {
                guard let metadata = try? await fetchSemanticScholar(doi) else { return nil }
                return MetadataCandidate(
                    metadata: metadata,
                    source: "semanticScholar(doi)",
                    matchKind: .doi,
                    sourcePriority: 0.97,
                    sourceConfidence: 0.95,
                    trace: doi
                )
            }
            group.addTask {
                guard let metadata = try? await fetchOpenAlex(doi) else { return nil }
                return MetadataCandidate(
                    metadata: metadata,
                    source: "openAlex(doi)",
                    matchKind: .doi,
                    sourcePriority: 0.94,
                    sourceConfidence: 0.92,
                    trace: doi
                )
            }
            group.addTask {
                guard let metadata = try? await fetchCrossRef(doi) else { return nil }
                return MetadataCandidate(
                    metadata: metadata,
                    source: "crossref(doi)",
                    matchKind: .doi,
                    sourcePriority: 0.93,
                    sourceConfidence: 0.9,
                    trace: doi
                )
            }

            var candidates: [MetadataCandidate] = []
            for await candidate in group {
                if let candidate {
                    candidates.append(candidate)
                }
            }
            return candidates
        }
    }
}

struct TitleSearchMetadataSource: MetadataSource {
    let name: String
    let phase: MetadataSourcePhase = .title
    let sourcePriority: Double
    let search: @Sendable (String) async throws -> [PaperMetadata]

    func collectCandidates(for seed: MetadataSeed) async -> [MetadataCandidate] {
        let baseTitles = seed.searchTitles
        guard !baseTitles.isEmpty else { return [] }

        var candidates: [MetadataCandidate] = []
        var seen = Set<String>()
        for query in Array(baseTitles.flatMap(MetadataNormalization.titleSearchQueries).prefix(4)) {
            guard let results = try? await search(query) else { continue }
            for metadata in results {
                let similarity = baseTitles
                    .map { MetadataNormalization.titleSimilarity($0, metadata.title) }
                    .max() ?? 0
                guard similarity >= 0.42 else { continue }

                let key = [
                    MetadataNormalization.normalizeTitle(metadata.title) ?? "",
                    MetadataNormalization.normalizedDOI(metadata.doi) ?? "",
                    metadata.arxivId?.lowercased() ?? ""
                ].joined(separator: "|")
                guard seen.insert(key).inserted else { continue }

                candidates.append(MetadataCandidate(
                    metadata: metadata,
                    source: name,
                    matchKind: similarity >= 0.92 ? .exactTitle : .fuzzyTitle,
                    sourcePriority: sourcePriority,
                    sourceConfidence: similarity,
                    trace: "query=\(query)"
                ))
            }
        }
        return candidates
    }
}

struct DOIRecoveryMetadataSource: MetadataSource {
    let name = "doiRecovery"
    let phase: MetadataSourcePhase = .fallback
    let searchDBLP: @Sendable (String) async throws -> [PaperMetadata]
    let fetchSemanticScholarByDOI: @Sendable (String) async throws -> PaperMetadata
    let fetchOpenAlexByDOI: @Sendable (String) async throws -> PaperMetadata
    let fetchCrossRefByDOI: @Sendable (String) async throws -> PaperMetadata
    let priorityBase: Double

    func collectCandidates(for seed: MetadataSeed) async -> [MetadataCandidate] {
        let baseTitles = seed.searchTitles
        guard !baseTitles.isEmpty else { return [] }
        var candidates: [MetadataCandidate] = []
        var seen = Set<String>()
        for query in Array(baseTitles.flatMap(MetadataNormalization.titleSearchQueries).prefix(4)) {
            guard let dblpResults = try? await searchDBLP(query) else { continue }
            for result in dblpResults.prefix(5) {
                let similarity = baseTitles
                    .map { MetadataNormalization.titleSimilarity($0, result.title) }
                    .max() ?? 0
                guard similarity >= 0.6,
                      let doi = MetadataNormalization.normalizedDOI(result.doi),
                      !doi.isEmpty,
                      seen.insert(doi).inserted else { continue }

                if let metadata = try? await fetchSemanticScholarByDOI(doi) {
                    candidates.append(MetadataCandidate(
                        metadata: metadata,
                        source: "dblp->semanticScholar(doi)",
                        matchKind: .fuzzyTitle,
                        sourcePriority: 0.98 * priorityBase,
                        sourceConfidence: similarity,
                        trace: "query=\(query) doi=\(doi)"
                    ))
                    continue
                }
                if let metadata = try? await fetchOpenAlexByDOI(doi) {
                    candidates.append(MetadataCandidate(
                        metadata: metadata,
                        source: "dblp->openAlex(doi)",
                        matchKind: .fuzzyTitle,
                        sourcePriority: 0.96 * priorityBase,
                        sourceConfidence: similarity,
                        trace: "query=\(query) doi=\(doi)"
                    ))
                    continue
                }
                if let metadata = try? await fetchCrossRefByDOI(doi) {
                    candidates.append(MetadataCandidate(
                        metadata: metadata,
                        source: "dblp->crossref(doi)",
                        matchKind: .fuzzyTitle,
                        sourcePriority: 0.95 * priorityBase,
                        sourceConfidence: similarity,
                        trace: "query=\(query) doi=\(doi)"
                    ))
                }
            }
        }
        return candidates
    }
}
