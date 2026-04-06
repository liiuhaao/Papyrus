import Foundation

package struct LibraryPaperSummary: Encodable {
    package let id: UUID
    package let title: String
    package let authors: String
    package let venue: String?
    package let year: Int
    package let tags: [String]
    package let flagged: Bool
    package let pinned: Bool
    package let readingStatus: String
}

package struct LibraryRuntimeSnapshot: Encodable {
    package let storePath: String
}

package struct LibraryListQuery {
    package let searchText: String
    package let rankKeywords: Set<String>
    package let readingStatuses: Set<String>
    package let minRating: Int
    package let venueAbbreviations: Set<String>
    package let years: Set<Int>
    package let publicationTypes: Set<String>
    package let tags: Set<String>
    package let flaggedOnly: Bool
    package let pinnedOnly: Bool
    package let sortField: PaperSortField
    package let sortAscending: Bool
    package let limit: Int?

    package init(
        searchText: String = "",
        rankKeywords: Set<String> = [],
        readingStatuses: Set<String> = [],
        minRating: Int = 0,
        venueAbbreviations: Set<String> = [],
        years: Set<Int> = [],
        publicationTypes: Set<String> = [],
        tags: Set<String> = [],
        flaggedOnly: Bool = false,
        pinnedOnly: Bool = false,
        sortField: PaperSortField = .dateAdded,
        sortAscending: Bool = false,
        limit: Int? = nil
    ) {
        self.searchText = searchText
        self.rankKeywords = rankKeywords
        self.readingStatuses = readingStatuses
        self.minRating = minRating
        self.venueAbbreviations = venueAbbreviations
        self.years = years
        self.publicationTypes = publicationTypes
        self.tags = tags
        self.flaggedOnly = flaggedOnly
        self.pinnedOnly = pinnedOnly
        self.sortField = sortField
        self.sortAscending = sortAscending
        self.limit = limit
    }
}

@MainActor
package struct LibraryQueries {
    private let loadLibraryPapersUseCase: LoadLibraryPapersUseCase

    init(loadLibraryPapersUseCase: LoadLibraryPapersUseCase) {
        self.loadLibraryPapersUseCase = loadLibraryPapersUseCase
    }

    package func runtimeSnapshot() -> LibraryRuntimeSnapshot {
        LibraryRuntimeSnapshot(storePath: PersistenceController.desiredStoreURL.path)
    }

    func fetchAllPapers() throws -> [Paper] {
        try loadLibraryPapersUseCase.fetchAllPapers()
    }

    package func listPapers(_ query: LibraryListQuery = LibraryListQuery()) throws -> [LibraryPaperSummary] {
        let allPapers = try fetchAllPapers()
        return filteredPapers(
            allPapers: allPapers,
            query: query,
            visibleRankSourceKeys: []
        ).map(Self.makeSummary)
    }

    package func filterPaperIDs(
        allPapers: [Paper],
        query: LibraryListQuery,
        visibleRankSourceKeys: [String]
    ) -> [UUID] {
        filteredPapers(
            allPapers: allPapers,
            query: query,
            visibleRankSourceKeys: visibleRankSourceKeys
        ).map(\.id)
    }

    private func filteredPapers(
        allPapers: [Paper],
        query: LibraryListQuery,
        visibleRankSourceKeys: [String]
    ) -> [Paper] {
        let state = PaperFilterState(
            searchText: query.searchText,
            sortField: query.sortField,
            sortAscending: query.sortAscending,
            filterRankKeywords: query.rankKeywords,
            filterReadingStatus: query.readingStatuses,
            filterMinRating: query.minRating,
            filterVenueAbbr: query.venueAbbreviations,
            filterYear: query.years,
            filterPublicationType: query.publicationTypes,
            filterTags: query.tags,
            filterFlaggedOnly: query.flaggedOnly
        )

        var filtered = loadLibraryPapersUseCase.filterPapers(
            allPapers: allPapers,
            state: state,
            visibleRankSourceKeys: visibleRankSourceKeys
        )

        if query.pinnedOnly {
            filtered = filtered.filter(\.isPinned)
        }

        if let limit = query.limit, limit >= 0 {
            filtered = Array(filtered.prefix(limit))
        }

        return filtered
    }

    private static func makeSummary(_ paper: Paper) -> LibraryPaperSummary {
        LibraryPaperSummary(
            id: paper.id,
            title: paper.displayTitle,
            authors: paper.formattedAuthors,
            venue: paper.venue,
            year: Int(paper.year),
            tags: paper.tagsList,
            flagged: paper.isFlagged,
            pinned: paper.isPinned,
            readingStatus: paper.currentReadingStatus.rawValue
        )
    }
}
