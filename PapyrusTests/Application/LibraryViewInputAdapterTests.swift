import Testing
@testable import PapyrusCore

struct LibraryViewInputAdapterTests {
    @Test
    func listAdapterReportsExpectedModeAndSelectionSupport() {
        let adapter = ListViewInputAdapter()

        #expect(adapter.mode == .list)
        #expect(adapter.supportsMultiSelection == true)
    }

    @Test
    func galleryAdapterReportsExpectedModeAndSelectionSupport() {
        let adapter = GalleryViewInputAdapter()

        #expect(adapter.mode == .gallery)
        #expect(adapter.supportsMultiSelection == true)
    }

    @MainActor
    @Test
    func listAdapterRoutesNavigationThroughListSelectionModel() {
        let context = TestSupport.makeInMemoryContext()
        let first = TestSupport.makePaper(in: context, title: "First")
        let second = TestSupport.makePaper(in: context, title: "Second")
        let interactions = LibraryInteractionCoordinator()
        interactions.mode = .list
        interactions.listSelection.selectPaper(first)

        ListViewInputAdapter().handleNavigation(.down, interactions: interactions, visiblePapers: [first, second])

        #expect(interactions.listSelection.primarySelectionID == second.objectID)
    }
}
