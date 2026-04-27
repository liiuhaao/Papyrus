import Foundation

enum MetadataUpdatePolicy {
    @MainActor
    static func apply(_ resolution: MetadataResolution, to paper: Paper) {
        // 1. 写入审计字段（无论成功与否）
        if let data = try? JSONEncoder().encode(resolution.candidates),
           let json = String(data: data, encoding: .utf8) {
            paper.fetchCandidatesJSON = json
        } else {
            paper.fetchCandidatesJSON = nil
        }
        paper.fetchSelectedSource = resolution.selectedSource
        paper.fetchSelectedScore = resolution.selectedScore ?? 0
        paper.fetchSelectedTrace = resolution.trace
        paper.fetchTimestamp = Date()

        // 2. 更新 resolved / display 字段（仅当成功获取到 metadata 时）
        guard let metadata = resolution.metadata else { return }
        apply(
            metadata: metadata,
            from: resolution.selectedSource ?? "",
            score: resolution.selectedScore,
            candidates: resolution.candidates,
            trace: resolution.trace,
            to: paper
        )
    }

    @MainActor
    static func apply(
        metadata: PaperMetadata,
        from source: String,
        score: Double?,
        candidates: [MetadataCandidate],
        trace: String? = nil,
        to paper: Paper
    ) {
        if let data = try? JSONEncoder().encode(candidates),
           let json = String(data: data, encoding: .utf8) {
            paper.fetchCandidatesJSON = json
        } else {
            paper.fetchCandidatesJSON = nil
        }
        paper.fetchSelectedSource = source
        paper.fetchSelectedScore = score ?? 0
        paper.fetchSelectedTrace = trace ?? "manual=\(source)"
        paper.fetchTimestamp = Date()

        print("[UpdatePolicy] incoming venue=\(metadata.venue ?? "nil") venueManual=\(paper.venueManual)")
        let normalized = MetadataNormalization.normalizeMetadata(metadata)

        let canonicalVenue = normalized.venue.map {
            VenueFormatter.expandedFullName(forAbbreviation: $0)
                ?? VenueFormatter.standardFullName($0)
                ?? $0
        }
        if let canonical = canonicalVenue {
            print("[UpdatePolicy] writing venue=\(canonical) venueManual=\(paper.venueManual)")
        }

        // MARK: Resolved 层 — 始终覆盖（包括 nil，反映最后一次 fetch 的真实结果）
        paper.resolvedTitle = normalized.title
        paper.resolvedAuthors = normalized.authors
        paper.resolvedVenue = canonicalVenue
        paper.resolvedYear = normalized.year
        paper.resolvedAbstract = normalized.abstract
        paper.resolvedDOI = normalized.doi
        paper.resolvedArxivId = normalized.arxivId
        paper.resolvedCitationCount = normalized.citationCount ?? -1

        let inferredType = normalized.publicationType
            ?? MetadataParsers.inferPublicationType(
                venue: paper.venue,
                doi: paper.doi,
                arxivId: paper.arxivId
            )
        paper.resolvedPublicationType = inferredType

        // MARK: Display 层 — 非 manual 时跟随 resolved（包括 nil）
        if !paper.titleManual {
            paper.title = paper.resolvedTitle
        }
        if !paper.authorsManual {
            paper.authors = paper.resolvedAuthors
        }
        if !paper.venueManual {
            paper.venue = paper.resolvedVenue
        } else {
            print("[UpdatePolicy] SKIPPED because venueManual=true")
        }
        if !paper.yearManual {
            paper.year = paper.resolvedYear
        }
        paper.abstract = paper.resolvedAbstract
        if !paper.doiManual {
            paper.doi = paper.resolvedDOI
        }
        if !paper.arxivManual {
            paper.arxivId = paper.resolvedArxivId
        }
        if !paper.publicationTypeManual {
            paper.publicationType = paper.resolvedPublicationType
        }
        paper.citationCount = paper.resolvedCitationCount

        if let canonical = canonicalVenue, let acronym = normalized.venueAcronym {
            Task { await VenueAbbreviationService.shared.store(venue: canonical, acronym: acronym) }
        }

        paper.dateModified = Date()
        try? paper.managedObjectContext?.save()
    }
}
