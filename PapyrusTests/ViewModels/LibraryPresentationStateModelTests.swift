import SwiftUI
import Testing
@testable import PapyrusCore

struct LibraryPresentationStateModelTests {
    @MainActor
    @Test
    func handleSelectionChangeCollapsesBatchEditForSingleSelection() {
        let model = LibraryPresentationStateModel()
        model.showingBatchEdit = true
        model.showInspector = false

        model.handleSelectionChange(selectedCount: 3)

        #expect(model.showInspector == false)
        #expect(model.showingBatchEdit == true)

        model.handleSelectionChange(selectedCount: 1)
        #expect(model.showingBatchEdit == false)
    }

    @MainActor
    @Test
    func toggleInspectorVisibilityFlipsVisibility() {
        let model = LibraryPresentationStateModel()
        model.showInspector = true

        model.toggleInspectorVisibility()
        #expect(model.showInspector == false)

        model.toggleInspectorVisibility()
        #expect(model.showInspector == true)
    }

    @MainActor
    @Test
    func blockingModalReflectsDialogsAndErrors() {
        let model = LibraryPresentationStateModel()
        #expect(model.hasBlockingModal(errorMessagePresent: false) == false)

        model.showingImportDialog = true
        #expect(model.hasBlockingModal(errorMessagePresent: false) == true)

        model.showingImportDialog = false
        #expect(model.hasBlockingModal(errorMessagePresent: true) == true)
    }
}
