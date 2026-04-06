import Testing
@testable import PapyrusCore

struct LibraryDetailModelTests {
    @MainActor
    @Test
    func updateSelectionResetsTransientDetailState() {
        let model = LibraryDetailModel()
        let context = TestSupport.makeInMemoryContext()
        let paperA = TestSupport.makePaper(in: context, title: "A")
        let paperB = TestSupport.makePaper(in: context, title: "B")

        model.requestEditMetadata(for: paperA)
        model.showBibTeX = true
        model.bibTeXText = "@article{a}"
        model.isFetchingBib = true

        model.updateSelection(paperB)

        #expect(model.currentPaperID == paperB.objectID)
        #expect(model.showEditMetadata == false)
        #expect(model.showBibTeX == false)
        #expect(model.bibTeXText.isEmpty)
        #expect(model.isFetchingBib == false)
    }

    @MainActor
    @Test
    func requestEditMetadataPinsCurrentPaperAndEditorState() {
        let model = LibraryDetailModel()
        let context = TestSupport.makeInMemoryContext()
        let paper = TestSupport.makePaper(in: context, title: "Edit Me")

        model.requestEditMetadata(for: paper)

        #expect(model.currentPaperID == paper.objectID)
        #expect(model.showEditMetadata == true)
    }
}
