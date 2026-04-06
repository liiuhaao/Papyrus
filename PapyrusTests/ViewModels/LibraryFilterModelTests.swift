import Testing
@testable import PapyrusCore

struct LibraryFilterModelTests {
    @MainActor
    @Test
    func hasActiveFiltersIgnoresSearchTextButTracksFilterState() {
        let model = LibraryFilterModel()

        #expect(model.hasActiveFilters == false)

        model.searchText = "transformer"
        #expect(model.hasActiveFilters == false)

        model.filterTags = ["ml"]
        #expect(model.hasActiveFilters == true)
    }

    @MainActor
    @Test
    func clearFiltersResetsAllFilterInputsAndPreservesSearchAndSort() {
        let model = LibraryFilterModel()
        model.searchText = "agent"
        model.sortField = .citations
        model.sortAscending = true
        model.filterRankKeywords = ["CCF A"]
        model.filterReadingStatus = ["read"]
        model.filterMinRating = 4
        model.filterVenueAbbr = ["NeurIPS"]
        model.filterYear = [2024]
        model.filterPublicationType = ["conference"]
        model.filterTags = ["systems"]
        model.filterFlaggedOnly = true

        model.clearFilters()

        #expect(model.searchText == "agent")
        #expect(model.sortField == .citations)
        #expect(model.sortAscending == true)
        #expect(model.filterRankKeywords.isEmpty)
        #expect(model.filterReadingStatus.isEmpty)
        #expect(model.filterMinRating == 0)
        #expect(model.filterVenueAbbr.isEmpty)
        #expect(model.filterYear.isEmpty)
        #expect(model.filterPublicationType.isEmpty)
        #expect(model.filterTags.isEmpty)
        #expect(model.filterFlaggedOnly == false)
        #expect(model.hasActiveFilters == false)
    }
}
