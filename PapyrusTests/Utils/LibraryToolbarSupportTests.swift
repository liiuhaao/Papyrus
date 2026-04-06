import Testing
@testable import PapyrusCore

struct LibraryToolbarSupportTests {
    @Test
    func toolbarConfigurationDerivesSelectionState() {
        let configuration = LibraryToolbarConfiguration(
            selectedPaperCount: 2,
            hasSelectedPaper: false,
            showDeleteSelectedConfirm: {},
            toggleFlag: {},
            flagIcon: "flag",
            flagHelp: "Flag",
            togglePin: {},
            pinIcon: "pin",
            pinHelp: "Pin",
            showEditor: {},
        )

        #expect(configuration.hasAnySelection == true)
        #expect(configuration.isEditorEnabled == true)
    }

    @MainActor
    @Test
    func exportContextPrefersSelectionThenFiltersThenAll() {
        let context = TestSupport.makeInMemoryContext()
        let first = TestSupport.makePaper(in: context, title: "First")
        let second = TestSupport.makePaper(in: context, title: "Second")

        let selected = LibraryExportContext.make(
            selectedPapers: [first],
            filteredPapers: [first, second],
            hasActiveFilters: true
        )
        #expect(selected.papers.map(\.objectID) == [first.objectID])
        #expect(selected.label == "Export 1 selected")

        let filtered = LibraryExportContext.make(
            selectedPapers: [],
            filteredPapers: [first],
            hasActiveFilters: true
        )
        #expect(filtered.papers.map(\.objectID) == [first.objectID])
        #expect(filtered.label == "Export 1")

        let all = LibraryExportContext.make(
            selectedPapers: [],
            filteredPapers: [first, second],
            hasActiveFilters: false
        )
        #expect(all.papers.count == 2)
        #expect(all.label == "Export all")
    }

    @MainActor
    @Test
    func onlineLinksDetectsPresenceFromPaperMetadata() {
        let context = TestSupport.makeInMemoryContext()
        let paper = TestSupport.makePaper(in: context, title: "Graph Agents")
        paper.doi = "10.1145/1234567.1234568"

        let links = LibraryOnlineLinks(paper: paper)

        #expect(links.doi != nil)
        #expect(links.hasAny == true)

        let emptyLinks = LibraryOnlineLinks(paper: nil)
        #expect(emptyLinks.hasAny == false)
    }
}
