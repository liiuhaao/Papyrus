import Combine
import CoreData
import Foundation

@MainActor
final class LibraryTaskStateModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var importTasks: [PaperListViewModel.ImportTask] = []
    @Published var pendingMetadataEditPaperID: NSManagedObjectID?

    func addImportTask(
        filename: String,
        source: PaperListViewModel.ImportTask.Source,
        stage: WorkflowStage
    ) -> UUID {
        let task = PaperListViewModel.ImportTask(filename: filename, source: source, stage: stage)
        importTasks.append(task)
        if !isLoading {
            isLoading = true
        }
        return task.id
    }

    func updateImportTask(id: UUID, stage: WorkflowStage) {
        if let idx = importTasks.firstIndex(where: { $0.id == id }),
           importTasks[idx].stage != stage {
            importTasks[idx].stage = stage
        }
    }

    func removeImportTask(id: UUID) {
        importTasks.removeAll { $0.id == id }
        let nextLoading = !importTasks.isEmpty
        if isLoading != nextLoading {
            isLoading = nextLoading
        }
    }

    func clearError() {
        if errorMessage != nil {
            errorMessage = nil
        }
    }
}
