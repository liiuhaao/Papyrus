import CoreData
import Testing
@testable import PapyrusCore

struct LibraryTaskStateModelTests {
    @MainActor
    @Test
    func addUpdateAndRemoveImportTaskDrivesLoadingState() {
        let model = LibraryTaskStateModel()

        let id = model.addImportTask(
            filename: "paper.pdf",
            source: .importOperation,
            stage: .checking
        )

        #expect(model.isLoading == true)
        #expect(model.importTasks.count == 1)
        #expect(model.importTasks.first?.filename == "paper.pdf")
        #expect(model.importTasks.first?.stage.label == "Checking duplicates...")

        model.updateImportTask(id: id, stage: .done)
        #expect(model.importTasks.first?.stage.label == "Done")

        model.removeImportTask(id: id)
        #expect(model.importTasks.isEmpty)
        #expect(model.isLoading == false)
    }

    @MainActor
    @Test
    func clearErrorAndPendingMetadataEditStateAreIndependent() {
        let model = LibraryTaskStateModel()
        let objectID = makeObjectID()

        model.errorMessage = "failed"
        model.pendingMetadataEditPaperID = objectID
        model.clearError()

        #expect(model.errorMessage == nil)
        #expect(model.pendingMetadataEditPaperID == objectID)
    }

    @MainActor
    private func makeObjectID() -> NSManagedObjectID {
        let context = TestSupport.makeInMemoryContext()
        let paper = TestSupport.makePaper(in: context, title: "Object ID")
        try? context.save()
        return paper.objectID
    }
}
