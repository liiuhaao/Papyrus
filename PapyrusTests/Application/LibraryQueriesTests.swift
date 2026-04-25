import Foundation
import Testing
@testable import PapyrusCore

struct LibraryQueriesTests {
    @MainActor
    @Test
    func listPapersReturnsSummariesInLibraryOrder() throws {
        let context = TestSupport.makeInMemoryContext()
        let newer = TestSupport.makePaper(in: context, title: "Newer")
        newer.tags = "ml, systems"
        newer.isFlagged = true
        newer.setReadingStatus(.reading)

        let older = TestSupport.makePaper(in: context, title: "Older")
        older.dateAdded = Date(timeIntervalSince1970: 1)
        newer.dateAdded = Date(timeIntervalSince1970: 2)
        try context.save()

        let queries = LibraryQueries(
            loadLibraryPapersUseCase: LoadLibraryPapersUseCase(viewContext: context)
        )

        let summaries = try queries.listPapers()

        #expect(summaries.map(\.displayTitle) == ["Newer", "Older"])
        #expect(summaries.first?.tags == ["ml", "systems"])
        #expect(summaries.first?.flagged == true)
        #expect(summaries.first?.readingStatus == Paper.ReadingStatus.reading.rawValue)
    }

    @MainActor
    @Test
    func listPapersAppliesStructuredFiltersAndLimit() throws {
        let context = TestSupport.makeInMemoryContext()

        let first = TestSupport.makePaper(in: context, title: "Graph Agents")
        first.tags = "agents, ml"
        first.isFlagged = true
        first.isPinned = true
        first.publicationType = "journal"
        first.rating = 5
        first.year = 2025
        first.setReadingStatus(.reading)
        first.dateAdded = Date(timeIntervalSince1970: 10)

        let second = TestSupport.makePaper(in: context, title: "Graph Systems")
        second.tags = "systems"
        second.publicationType = "conference"
        second.rating = 4
        second.year = 2025
        second.setReadingStatus(.reading)
        second.dateAdded = Date(timeIntervalSince1970: 9)

        let third = TestSupport.makePaper(in: context, title: "Other Paper")
        third.tags = "agents"
        third.isFlagged = true
        third.publicationType = "journal"
        third.rating = 5
        third.year = 2024
        third.setReadingStatus(.read)
        third.dateAdded = Date(timeIntervalSince1970: 8)

        try context.save()

        let queries = LibraryQueries(
            loadLibraryPapersUseCase: LoadLibraryPapersUseCase(viewContext: context)
        )

        let summaries = try queries.listPapers(
            LibraryListQuery(
                searchText: "graph",
                readingStatuses: [Paper.ReadingStatus.reading.rawValue],
                minRating: 4,
                years: [2025],
                publicationTypes: ["journal"],
                tags: ["agents"],
                flaggedOnly: true,
                pinnedOnly: true,
                sortField: .dateAdded,
                sortAscending: false,
                limit: 1
            )
        )

        #expect(summaries.count == 1)
        #expect(summaries.first?.displayTitle == "Graph Agents")
    }

    @MainActor
    @Test
    func filterPaperIDsPreservesSharedOrderingForAppConsumption() throws {
        let context = TestSupport.makeInMemoryContext()
        let older = TestSupport.makePaper(in: context, title: "Older")
        older.dateAdded = Date(timeIntervalSince1970: 1)
        let newer = TestSupport.makePaper(in: context, title: "Newer")
        newer.dateAdded = Date(timeIntervalSince1970: 2)
        newer.isPinned = true
        newer.pinOrder = 0
        try context.save()

        let queries = LibraryQueries(
            loadLibraryPapersUseCase: LoadLibraryPapersUseCase(viewContext: context)
        )

        let ids = queries.filterPaperIDs(
            allPapers: [older, newer],
            query: LibraryListQuery(
                pinnedOnly: true,
                sortField: .dateAdded,
                sortAscending: false
            ),
            visibleRankSourceKeys: []
        )

        #expect(ids == [newer.id])
    }
}
