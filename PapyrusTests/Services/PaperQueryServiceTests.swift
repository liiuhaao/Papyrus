import CoreData
import Testing
@testable import PapyrusCore

struct PaperQueryServiceTests {
    @Test
    func parseSearchPreservesQuotedTerms() {
        let query = PaperQueryService.parseSearch("graph \"multi agent\" retrieval")

        #expect(query.terms == ["graph", "multi agent", "retrieval"])
    }

    @MainActor
    @Test
    func applySearchPrioritizesPinnedThenHigherScoringMatches() {
        let context = TestSupport.makeInMemoryContext()
        let pinned = TestSupport.makePaper(in: context, title: "Graph Agents", isPinned: true, pinOrder: 0)
        pinned.abstract = "planning system"

        let titleMatch = TestSupport.makePaper(in: context, title: "Graph Retrieval")
        titleMatch.abstract = "misc"

        let abstractOnly = TestSupport.makePaper(in: context, title: "Unrelated")
        abstractOnly.abstract = "graph reasoning"

        let query = PaperQueryService.parseSearch("graph")
        let results = PaperQueryService.applySearch(
            papers: [abstractOnly, titleMatch, pinned],
            query: query,
            sortField: .title,
            sortAscending: true
        )

        #expect(results.map(\.objectID) == [pinned.objectID, titleMatch.objectID, abstractOnly.objectID])
    }

    @MainActor
    @Test
    func buildFilteredFetchRequestIncludesVenueYearAndFlagFilters() throws {
        let state = PaperFilterState(
            searchText: "graph",
            sortField: .year,
            sortAscending: false,
            filterRankKeywords: [],
            filterReadingStatus: ["reading"],
            filterMinRating: 4,
            filterVenueAbbr: ["ICLR"],
            filterYear: [2024],
            filterPublicationType: ["conference"],
            filterTags: ["ml"],
            filterFlaggedOnly: true
        )

        let request = PaperQueryService.buildFilteredFetchRequest(state: state)

        let predicate = try #require(request.predicate as? NSCompoundPredicate)
        #expect(predicate.compoundPredicateType == .and)
        #expect(predicate.subpredicates.count == 7)

        let sortDescriptors = try #require(request.sortDescriptors)
        #expect(sortDescriptors.map(\.key) == ["isPinned", "pinOrder", "year"])
        #expect(sortDescriptors.map(\.ascending) == [false, true, false])
    }

    @MainActor
    @Test
    func venueCountsPreferVenueObjectAbbreviation() {
        let context = TestSupport.makeInMemoryContext()
        let venue = TestSupport.makeVenue(
            in: context,
            name: "International Conference on Learning Representations",
            abbreviation: "ICLR"
        )
        let paper = TestSupport.makePaper(in: context, title: "Paper")
        paper.venue = venue.name
        paper.venueObject = venue

        let counts = PaperQueryService.venueCounts(in: [paper])

        #expect(counts.count == 1)
        #expect(counts.first?.venue == "ICLR")
        #expect(counts.first?.count == 1)
    }

    @MainActor
    @Test
    func venueCountsDoNotCollapseSingleTokenVenueToInitial() {
        let context = TestSupport.makeInMemoryContext()
        let paper = TestSupport.makePaper(in: context, title: "Paper")
        paper.venue = "arXiv"

        let counts = PaperQueryService.venueCounts(in: [paper])

        #expect(counts.count == 1)
        #expect(counts.first?.venue == "arXiv")
    }

    @MainActor
    @Test
    func buildFilteredFetchRequestComposesTagYearAndFlaggedPredicates() throws {
        let state = PaperFilterState(
            searchText: "",
            sortField: .dateAdded,
            sortAscending: false,
            filterRankKeywords: [],
            filterReadingStatus: [],
            filterMinRating: 0,
            filterVenueAbbr: [],
            filterYear: [2023, 2024],
            filterPublicationType: [],
            filterTags: ["ml", "systems"],
            filterFlaggedOnly: true
        )

        let request = PaperQueryService.buildFilteredFetchRequest(state: state)
        let predicate = try #require(request.predicate as? NSCompoundPredicate)

        #expect(predicate.compoundPredicateType == .and)
        #expect(predicate.subpredicates.count == 3)

        let format = predicate.predicateFormat
        #expect(format.contains("year IN"))
        #expect(format.contains("isFlagged == 1"))
        #expect(format.contains("tags CONTAINS[cd]"))
        #expect(format.contains("OR"))
    }

    @MainActor
    @Test
    func applySearchMatchesVenueAbbreviationFromVenueObject() {
        let context = TestSupport.makeInMemoryContext()
        let venue = TestSupport.makeVenue(
            in: context,
            name: "International Conference on Learning Representations",
            abbreviation: "ICLR"
        )
        let paper = TestSupport.makePaper(in: context, title: "Paper")
        paper.venue = venue.name
        paper.venueObject = venue

        let query = PaperQueryService.parseSearch("ICLR")
        let results = PaperQueryService.applySearch(
            papers: [paper],
            query: query,
            sortField: .dateAdded,
            sortAscending: false
        )

        #expect(results.map(\.objectID) == [paper.objectID])
    }

    @MainActor
    @Test
    func structuredVenueFilterMatchesDisplayedVenueWithoutVenueObject() {
        let context = TestSupport.makeInMemoryContext()
        let paper = TestSupport.makePaper(in: context, title: "Paper")
        paper.venue = "arXiv"

        let state = PaperFilterState(
            searchText: "",
            sortField: .dateAdded,
            sortAscending: false,
            filterRankKeywords: [],
            filterReadingStatus: [],
            filterMinRating: 0,
            filterVenueAbbr: ["arXiv"],
            filterYear: [],
            filterPublicationType: [],
            filterTags: [],
            filterFlaggedOnly: false
        )

        let filtered = PaperQueryService.applyStructuredFilters(papers: [paper], state: state)
        #expect(filtered.map(\.objectID) == [paper.objectID])
    }

    @MainActor
    @Test
    func applySearchRequiresAllTermsToMatchSomeField() {
        let context = TestSupport.makeInMemoryContext()
        let matching = TestSupport.makePaper(in: context, title: "Graph Agents")
        matching.tags = "planning, ml"

        let partial = TestSupport.makePaper(in: context, title: "Graph Retrieval")
        partial.tags = "search"

        let query = PaperQueryService.parseSearch("graph planning")
        let results = PaperQueryService.applySearch(
            papers: [matching, partial],
            query: query,
            sortField: .title,
            sortAscending: true
        )

        #expect(results.map(\.objectID) == [matching.objectID])
    }

    @MainActor
    @Test
    func applySearchMatchesNotesContent() {
        let context = TestSupport.makeInMemoryContext()
        let noteMatch = TestSupport.makePaper(in: context, title: "Unrelated")
        noteMatch.notes = "This uses Monte Carlo tree search for planning."

        let nonMatch = TestSupport.makePaper(in: context, title: "Control")
        nonMatch.notes = "General summary"

        let query = PaperQueryService.parseSearch("tree search")
        let results = PaperQueryService.applySearch(
            papers: [nonMatch, noteMatch],
            query: query,
            sortField: .title,
            sortAscending: true
        )

        #expect(results.map(\.objectID) == [noteMatch.objectID])
    }
}
