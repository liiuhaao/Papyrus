import Foundation

struct MetadataSeed {
    let title: String?
    let titleCandidates: [String]
    let authors: String?
    let doi: String?
    let arxivId: String?
    let abstract: String?
    let venue: String?
    let year: Int16
    let originalFilename: String?

    var searchTitles: [String] {
        let candidates = titleCandidates
        var seen = Set<String>()
        return candidates.compactMap(MetadataNormalization.normalizeTitle).filter { value in
            seen.insert(value.lowercased()).inserted
        }
    }

    init(
        title: String?,
        titleCandidates: [String] = [],
        authors: String?,
        doi: String?,
        arxivId: String?,
        abstract: String?,
        venue: String?,
        year: Int16,
        originalFilename: String?
    ) {
        self.title = title
        self.titleCandidates = titleCandidates.isEmpty ? [title].compactMap { $0 } : titleCandidates
        self.authors = authors
        self.doi = doi
        self.arxivId = arxivId
        self.abstract = abstract
        self.venue = venue
        self.year = year
        self.originalFilename = originalFilename
    }

    init(paper: Paper) {
        self.init(
            title: paper.refreshMetadataSeed.title,
            titleCandidates: paper.refreshMetadataSeed.titleCandidates,
            authors: paper.refreshMetadataSeed.authors,
            doi: paper.refreshMetadataSeed.doi,
            arxivId: paper.refreshMetadataSeed.arxivId,
            abstract: paper.refreshMetadataSeed.abstract,
            venue: paper.refreshMetadataSeed.venue,
            year: paper.refreshMetadataSeed.year,
            originalFilename: paper.originalFilename
        )
    }
}
