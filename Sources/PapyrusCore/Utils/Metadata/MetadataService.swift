// MetadataService.swift
// Fetch paper metadata from online sources

import Foundation

enum MetadataError: Error {
    case networkError
    case parseError
    case notFound
}

class MetadataService: MetadataProviding {
    
    nonisolated static let shared = MetadataService()
    
    private let session: URLSession
    private let arxivClient: ArxivClient
    private let openReviewClient: OpenReviewClient
    private let crossRefClient: CrossRefClient
    private let dblpClient: DBLPClient
    private let openAlexClient: OpenAlexClient
    private let semanticScholarClient: SemanticScholarClient
    private let semanticScholarGraphClient: SemanticScholarGraphClient
    private let pdfResolverClient: PDFResolverClient
    private let pipelineTimeoutSeconds: Double = 28
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 2
        self.session = URLSession(configuration: config)
        self.arxivClient = ArxivClient(session: self.session)
        self.openReviewClient = OpenReviewClient(session: self.session)
        self.crossRefClient = CrossRefClient(session: self.session)
        self.dblpClient = DBLPClient(session: self.session)
        self.openAlexClient = OpenAlexClient(session: self.session)
        self.semanticScholarClient = SemanticScholarClient(session: self.session)
        self.semanticScholarGraphClient = SemanticScholarGraphClient(session: self.session)
        self.pdfResolverClient = PDFResolverClient(session: self.session, openAlexClient: self.openAlexClient)
    }

    private func makePipeline(for preset: MetadataPreset, seed: MetadataSeed) -> MetadataPipeline {
        var sources: [MetadataSource] = [
            ArxivMetadataSource(
                fetchSemanticScholar: { try await self.fetchFromSemanticScholar(arxivId: $0) },
                fetchArxiv: { try await self.fetchFromArxiv(arxivId: $0) }
            ),
            DOIMetadataSource(
                fetchSemanticScholar: { try await self.fetchFromSemanticScholar(doi: $0) },
                fetchOpenAlex: { try await self.fetchFromOpenAlex(doi: $0) },
                fetchCrossRef: { try await self.fetchFromCrossRef(doi: $0) }
            )
        ]

        guard !seed.searchTitles.isEmpty else {
            return MetadataPipeline(sources: sources, resolver: MetadataResolver(preset: preset))
        }

        switch preset {
        case .general:
            sources.append(contentsOf: fullFuzzySourcesForGeneral())
            sources.append(doiRecoverySource(priorityBase: 0.92))
        case .cs:
            sources.append(contentsOf: fullFuzzySourcesForCS())
            sources.append(doiRecoverySource(priorityBase: 1.0))
        case .physics:
            sources.append(contentsOf: fullFuzzySourcesForPhysics())
            sources.append(doiRecoverySource(priorityBase: 0.88))
        case .biomed:
            sources.append(contentsOf: fullFuzzySourcesForBiomed())
            sources.append(doiRecoverySource(priorityBase: 0.94))
        }

        return MetadataPipeline(sources: sources, resolver: MetadataResolver(preset: preset))
    }

    private func fullFuzzySourcesForGeneral() -> [MetadataSource] {
        [
            titleSource(name: "semanticScholar", priority: 0.87, search: { try await self.searchSemanticScholar(title: $0) }),
            titleSource(name: "openAlex", priority: 0.85, search: { try await self.searchOpenAlex(title: $0) }),
            titleSource(name: "crossref", priority: 0.83, search: { try await self.searchCrossRef(title: $0) })
        ]
    }

    private func fullFuzzySourcesForCS() -> [MetadataSource] {
        [
            titleSource(name: "dblp", priority: 0.96, search: { try await self.searchDBLP(title: $0) }),
            titleSource(name: "openReview", priority: 0.9, search: { try await self.searchOpenReview(title: $0) }),
            titleSource(name: "semanticScholar", priority: 0.88, search: { try await self.searchSemanticScholar(title: $0) }),
            titleSource(name: "openAlex", priority: 0.84, search: { try await self.searchOpenAlex(title: $0) }),
            titleSource(name: "crossref", priority: 0.82, search: { try await self.searchCrossRef(title: $0) })
        ]
    }

    private func fullFuzzySourcesForPhysics() -> [MetadataSource] {
        [
            titleSource(name: "semanticScholar", priority: 0.89, search: { try await self.searchSemanticScholar(title: $0) }),
            titleSource(name: "openAlex", priority: 0.87, search: { try await self.searchOpenAlex(title: $0) }),
            titleSource(name: "crossref", priority: 0.84, search: { try await self.searchCrossRef(title: $0) })
        ]
    }

    private func fullFuzzySourcesForBiomed() -> [MetadataSource] {
        [
            titleSource(name: "semanticScholar", priority: 0.88, search: { try await self.searchSemanticScholar(title: $0) }),
            titleSource(name: "openAlex", priority: 0.88, search: { try await self.searchOpenAlex(title: $0) }),
            titleSource(name: "crossref", priority: 0.87, search: { try await self.searchCrossRef(title: $0) })
        ]
    }

    private func titleSource(
        name: String,
        priority: Double,
        search: @escaping @Sendable (String) async throws -> [PaperMetadata]
    ) -> MetadataSource {
        TitleSearchMetadataSource(name: name, sourcePriority: priority, search: search)
    }

    private func doiRecoverySource(priorityBase: Double) -> MetadataSource {
        DOIRecoveryMetadataSource(
            searchDBLP: { try await self.searchDBLP(title: $0) },
            fetchSemanticScholarByDOI: { try await self.fetchFromSemanticScholar(doi: $0) },
            fetchOpenAlexByDOI: { try await self.fetchFromOpenAlex(doi: $0) },
            fetchCrossRefByDOI: { try await self.fetchFromCrossRef(doi: $0) },
            priorityBase: priorityBase
        )
    }
    
    // MARK: - ArXiv
    
    func fetchFromArxiv(arxivId: String) async throws -> PaperMetadata {
        let xml = try await arxivClient.fetchFeed(arxivId: arxivId)
        return try MetadataParsers.parseArxivXML(xml)
    }
    
    // MARK: - CrossRef (DOI)
    
    func fetchFromCrossRef(doi: String) async throws -> PaperMetadata {
        let message = try await crossRefClient.fetchWorkJSON(doi: doi)
        return MetadataParsers.parseCrossRefJSON(message)
    }

    func searchCrossRef(title: String) async throws -> [PaperMetadata] {
        try await crossRefClient.searchWorks(title: title).map(MetadataParsers.parseCrossRefJSON)
    }

    // MARK: - OpenAlex

    func fetchFromOpenAlex(doi: String) async throws -> PaperMetadata {
        let work = try await openAlexClient.fetchWork(doi: doi)
        return MetadataParsers.parseOpenAlexWork(work)
    }

    func searchOpenAlex(title: String) async throws -> [PaperMetadata] {
        try await openAlexClient.searchWorks(title: title).map(MetadataParsers.parseOpenAlexWork)
    }

    // MARK: - DBLP

    func searchDBLP(title: String) async throws -> [PaperMetadata] {
        try await dblpClient.searchPublications(title: title).map(MetadataParsers.parseDBLPHit)
    }
    
    // MARK: - OpenReview
    
    func fetchFromOpenReview(forumId: String) async throws -> PaperMetadata {
        let firstNote = try await openReviewClient.fetchNote(forumId: forumId)
        return try MetadataParsers.parseOpenReviewNote(firstNote)
    }
    
    // MARK: - OpenReview title search

    func searchOpenReview(title: String) async throws -> [PaperMetadata] {
        let first = try await openReviewClient.searchNotes(title: title)
        return [try MetadataParsers.parseOpenReviewSearchResult(first)]
    }

    // MARK: - Semantic Scholar

    func fetchFromSemanticScholar(arxivId: String) async throws -> PaperMetadata {
        let apiKey = await MainActor.run { AppConfig.shared.semanticScholarKey }
        let json = try await semanticScholarClient.fetchPaperByArxivID(arxivId, apiKey: apiKey)
        return parseS2Paper(json)
    }

    func fetchFromSemanticScholar(doi: String) async throws -> PaperMetadata {
        let apiKey = await MainActor.run { AppConfig.shared.semanticScholarKey }
        let json = try await semanticScholarClient.fetchPaperByDOI(doi, apiKey: apiKey)
        return parseS2Paper(json)
    }

    func searchSemanticScholar(title: String) async throws -> [PaperMetadata] {
        let results = try await semanticScholarClient.searchPapersByTitle(title)
        let parsed = results.compactMap { item -> PaperMetadata? in
            guard let returnedTitle = item["title"] as? String else { return nil }
            let similarity = MetadataNormalization.titleSimilarity(title, returnedTitle)
            print("[S2 search] similarity=\(String(format: "%.2f", similarity)) returned=\(returnedTitle)")
            guard similarity >= 0.55 else { return nil }
            return parseS2Paper(item)
        }
        guard !parsed.isEmpty else { throw MetadataError.notFound }
        return parsed
    }

    private func parseS2Paper(_ json: [String: Any]) -> PaperMetadata {
        MetadataParsers.parseSemanticScholarPaper(json)
    }

    @MainActor
    func enrichMetadata(paper: Paper) async -> Bool {
        let filename = paper.originalFilename ?? paper.displayTitle
        print("[Enrich] \(filename) arXiv=\(paper.arxivId ?? "-") doi=\(paper.doi ?? "-")")
        let preset = AppConfig.shared.metadataPreset
        let seed = MetadataSeed(paper: paper)
        guard let resolution: MetadataResolution = await AsyncTimeout.value(
            seconds: pipelineTimeoutSeconds,
            operation: {
                await self.makePipeline(for: preset, seed: seed).resolve(seed: seed)
            }
        ) else {
            print("[Enrich] Pipeline timed out after \(Int(pipelineTimeoutSeconds))s")
            return false
        }
        if let metadata = resolution.metadata {
            print("[Enrich] Pipeline succeeded: \(resolution.trace)")
            MetadataUpdatePolicy.apply(metadata, to: paper)
            return true
        } else {
            print("[Enrich] Pipeline failed: \(resolution.trace)")
            if let arxivId = seed.arxivId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !arxivId.isEmpty,
               let fallback = await fetchArxivFallback(arxivId: arxivId) {
                print("[Enrich] Fallback arXiv succeeded for \(arxivId)")
                MetadataUpdatePolicy.apply(fallback, to: paper)
                return true
            }
            return false
        }
    }

    private func fetchArxivFallback(arxivId: String) async -> PaperMetadata? {
        if let metadata = try? await fetchFromArxiv(arxivId: arxivId) {
            return metadata
        }
        let base = arxivId.components(separatedBy: "v").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? arxivId
        guard !base.isEmpty, base != arxivId else { return nil }
        return try? await fetchFromArxiv(arxivId: base)
    }

    private func hasStableIdentifier(_ seed: MetadataSeed) -> Bool {
        if let doi = MetadataNormalization.normalizedDOI(seed.doi), !doi.isEmpty {
            return true
        }
        if let arxivId = seed.arxivId?.trimmingCharacters(in: .whitespacesAndNewlines), !arxivId.isEmpty {
            return true
        }
        return false
    }

    // MARK: - PDF URL Resolution

    /// Resolve a direct PDF download URL for a paper.
    /// Priority: arXiv direct link → Unpaywall → Sci-Hub (for DOI).
    func fetchPDFURL(arxivId: String? = nil, doi: String? = nil) async throws -> URL {
        try await pdfResolverClient.fetchPDFURL(arxivId: arxivId, doi: doi)
    }

    // MARK: - BibTeX

    func fetchBibTeX(for paper: Paper) async -> String {
        if let doi = paper.doi, !doi.isEmpty, !doi.lowercased().contains("10.48550"),
           let bib = try? await fetchBibTeXFromCrossRef(doi: doi) {
            return bib
        }
        return MetadataBibTeXSupport.constructBibTeX(for: paper)
    }

    private func fetchBibTeXFromCrossRef(doi: String) async throws -> String {
        try await crossRefClient.fetchBibTeX(doi: doi)
    }

    // MARK: - References & Citations

    func fetchReferences(for paper: Paper) async throws -> [PaperReference] {
        let apiKey = await MainActor.run { AppConfig.shared.semanticScholarKey }
        return try await semanticScholarGraphClient.fetchReferences(for: paper, apiKey: apiKey)
    }

    func fetchCitations(for paper: Paper) async throws -> [PaperReference] {
        let apiKey = await MainActor.run { AppConfig.shared.semanticScholarKey }
        return try await semanticScholarGraphClient.fetchCitations(for: paper, apiKey: apiKey)
    }

}

// MARK: - Supporting Types

struct PaperMetadata: Sendable {
    var title: String?
    var authors: String?
    var venue: String?
    var venueAcronym: String?
    var year: Int16 = 0
    var doi: String?
    var arxivId: String?
    var abstract: String?
    var publicationType: String?
    var citationCount: Int32?
}

struct PaperReference: Codable, Identifiable {
    let paperId: String?
    let title: String?
    let authors: String?
    let year: Int?
    let doi: String?
    let arxivId: String?

    var id: String { paperId ?? "\(title ?? "")-\(year ?? 0)" }

    init(from json: [String: Any]) {
        paperId  = json["paperId"] as? String
        title    = json["title"] as? String
        year     = json["year"] as? Int
        let ids  = json["externalIds"] as? [String: Any]
        doi      = ids?["DOI"] as? String
        arxivId  = ids?["ArXiv"] as? String
        authors  = (json["authors"] as? [[String: Any]])?
            .compactMap { $0["name"] as? String }
            .joined(separator: ", ")
    }
}

extension String {
    func trimmed() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
