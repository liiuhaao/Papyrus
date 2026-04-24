import Foundation
import CoreData

package struct LibraryPaperSummary: Encodable {
    package let objectID: NSManagedObjectID
    package let id: UUID
    package let displayTitle: String
    package let formattedAuthors: String
    package let venue: String?
    package let year: Int
    package let tags: [String]
    package let flagged: Bool
    package let pinned: Bool
    package let rating: Int
    package let readingStatus: String
    package let filePath: String?
    package let workflowStatus: PaperWorkflowStatus?
    package let notes: String?

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayTitle, forKey: .displayTitle)
        try container.encode(formattedAuthors, forKey: .formattedAuthors)
        try container.encode(venue, forKey: .venue)
        try container.encode(year, forKey: .year)
        try container.encode(tags, forKey: .tags)
        try container.encode(flagged, forKey: .flagged)
        try container.encode(pinned, forKey: .pinned)
        try container.encode(rating, forKey: .rating)
        try container.encode(readingStatus, forKey: .readingStatus)
        try container.encode(filePath, forKey: .filePath)
        try container.encode(workflowStatus, forKey: .workflowStatus)
        try container.encode(notes, forKey: .notes)
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayTitle, formattedAuthors, venue, year, tags
        case flagged, pinned, rating, readingStatus, filePath
        case workflowStatus, notes
    }
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

    package func fetchFilteredPapers(
        query: LibraryListQuery,
        visibleRankSourceKeys: [String]
    ) throws -> [Paper] {
        try _fetchFiltered(query: query, visibleRankSourceKeys: visibleRankSourceKeys)
    }

    package func fetchFilteredPaperSummaries(
        query: LibraryListQuery,
        visibleRankSourceKeys: [String]
    ) throws -> [LibraryPaperSummary] {
        try _fetchFiltered(query: query, visibleRankSourceKeys: visibleRankSourceKeys).map(Self.makeSummary)
    }

    private func _fetchFiltered(
        query: LibraryListQuery,
        visibleRankSourceKeys: [String]
    ) throws -> [Paper] {
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

        // Database query for most filters (search, status, year, type, tags, flagged)
        var papers = try loadLibraryPapersUseCase.fetchFilteredPapers(state: state)

        // In-memory post-filter for venue (complex matching logic)
        let selectedVenues = Set(state.filterVenueAbbr.map(PaperQueryService.normalizeVenueFilterValue))
        if !selectedVenues.isEmpty {
            papers = papers.filter { paper in
                !selectedVenues.isDisjoint(with: PaperQueryService.venueFilterKeys(for: paper))
            }
        }

        // In-memory post-filter for rank keywords
        if !state.filterRankKeywords.isEmpty {
            papers = papers.filter { paper in
                guard let venue = paper.venueObject else { return false }
                let labels = Set(venue.orderedRankEntries(visibleSourceKeys: visibleRankSourceKeys).map { key, value in
                    RankSourceConfig.displayLabel(for: key, value: value)
                })
                return !labels.isDisjoint(with: state.filterRankKeywords)
            }
        }

        if query.pinnedOnly {
            papers = papers.filter(\.isPinned)
        }

        if let limit = query.limit, limit >= 0 {
            papers = Array(papers.prefix(limit))
        }

        return papers
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
            objectID: paper.objectID,
            id: paper.id,
            displayTitle: paper.displayTitle,
            formattedAuthors: paper.formattedAuthors,
            venue: paper.venue,
            year: Int(paper.year),
            tags: paper.tagsList,
            flagged: paper.isFlagged,
            pinned: paper.isPinned,
            rating: Int(paper.rating),
            readingStatus: paper.currentReadingStatus.rawValue,
            filePath: paper.filePath,
            workflowStatus: paper.workflowStatus,
            notes: paper.notes
        )
    }
}
