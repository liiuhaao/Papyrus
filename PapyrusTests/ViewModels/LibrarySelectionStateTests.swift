import Testing
@testable import PapyrusCore

struct LibrarySelectionStateTests {
    @MainActor
    @Test
    func listModePublishesPrimaryPaperOnly() {
        let context = TestSupport.makeInMemoryContext()
        let state = SelectionStore()
        let paperA = TestSupport.makePaper(in: context, title: "A")
        let paperB = TestSupport.makePaper(in: context, title: "B")

        state.sync(
            mode: .list,
            selectedIDs: [paperA.objectID],
            primarySelectionID: paperA.objectID,
            visiblePapers: [paperA, paperB],
            allPapers: [paperA, paperB],
            context: context
        )

        #expect(state.selectedCount == 1)
        #expect(state.primaryID == paperA.objectID)
        #expect(state.selectedIDs == [paperA.objectID])
    }

    @MainActor
    @Test
    func listModePreservesMultiSelectionSnapshot() {
        let context = TestSupport.makeInMemoryContext()
        let state = SelectionStore()
        let paperA = TestSupport.makePaper(in: context, title: "A")
        let paperB = TestSupport.makePaper(in: context, title: "B")

        state.sync(
            mode: .list,
            selectedIDs: [paperA.objectID, paperB.objectID],
            primarySelectionID: paperA.objectID,
            visiblePapers: [paperA, paperB],
            allPapers: [paperA, paperB],
            context: context
        )

        #expect(state.selectedCount == 2)
        #expect(state.primaryID == paperA.objectID)
        #expect(state.selectedIDs == [paperA.objectID, paperB.objectID])
    }

    @MainActor
    @Test
    func galleryModePublishesAllSelectedPapers() {
        let context = TestSupport.makeInMemoryContext()
        let state = SelectionStore()
        let paperA = TestSupport.makePaper(in: context, title: "A")
        let paperB = TestSupport.makePaper(in: context, title: "B")

        state.sync(
            mode: .gallery,
            selectedIDs: [paperA.objectID, paperB.objectID],
            primarySelectionID: paperB.objectID,
            visiblePapers: [paperA, paperB],
            allPapers: [paperA, paperB],
            context: context
        )

        #expect(state.selectedCount == 2)
        #expect(state.primaryID == paperB.objectID)
        #expect(state.selectedIDs == [paperA.objectID, paperB.objectID])
    }
}
