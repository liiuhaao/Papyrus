import Foundation

enum MetadataUpdatePolicy {
    @MainActor
    static func apply(_ metadata: PaperMetadata, to paper: Paper) {
        let normalized = MetadataNormalization.normalizeMetadata(metadata)

        if let title = normalized.title {
            paper.resolvedTitle = title
            if !paper.titleManual {
                paper.title = title
            }
        }
        if let authors = normalized.authors {
            paper.resolvedAuthors = authors
            if !paper.authorsManual {
                paper.authors = authors
            }
        }
        if let venue = normalized.venue {
            paper.resolvedVenue = venue
            if !paper.venueManual {
                paper.venue = venue
            }
            if let acronym = normalized.venueAcronym {
                Task { await VenueAbbreviationService.shared.store(venue: venue, acronym: acronym) }
            }
        }
        if normalized.year > 0 {
            paper.resolvedYear = normalized.year
            if !paper.yearManual {
                paper.year = normalized.year
            }
        }
        if let abstract = normalized.abstract {
            paper.resolvedAbstract = abstract
            paper.abstract = abstract
        }
        if let doi = normalized.doi {
            paper.resolvedDOI = doi
            if !paper.doiManual {
                paper.doi = doi
            }
        }
        if let arxivID = normalized.arxivId {
            paper.resolvedArxivId = arxivID
            if !paper.arxivManual {
                paper.arxivId = arxivID
            }
        }

        let inferredType = normalized.publicationType
            ?? MetadataParsers.inferPublicationType(
                venue: paper.venue,
                doi: paper.doi,
                arxivId: paper.arxivId
            )
        if let inferredType {
            paper.resolvedPublicationType = inferredType
            if !paper.publicationTypeManual {
                paper.publicationType = inferredType
            }
        }
        if let citationCount = normalized.citationCount {
            paper.resolvedCitationCount = citationCount
            paper.citationCount = citationCount
        }

        paper.dateModified = Date()
        try? paper.managedObjectContext?.save()
    }
}
