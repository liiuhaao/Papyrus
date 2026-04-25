import Foundation
import CoreData

@MainActor
final class PaperTransientStateStore: ObservableObject {
    static let shared = PaperTransientStateStore()

    @Published private(set) var workflowStatuses: [NSManagedObjectID: PaperWorkflowStatus] = [:]

    func setWorkflowStatus(_ status: PaperWorkflowStatus?, for objectID: NSManagedObjectID) {
        if let status {
            workflowStatuses[objectID] = status
            if status.shouldAutoClear {
                scheduleWorkflowStatusAutoClear(for: objectID, expectedStatus: status)
            }
        } else {
            workflowStatuses.removeValue(forKey: objectID)
        }
    }

    func workflowStatus(for objectID: NSManagedObjectID) -> PaperWorkflowStatus? {
        workflowStatuses[objectID]
    }

    func clearAll() {
        workflowStatuses.removeAll()
    }

    private func scheduleWorkflowStatusAutoClear(
        for objectID: NSManagedObjectID,
        expectedStatus: PaperWorkflowStatus
    ) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }
            if self.workflowStatuses[objectID] == expectedStatus {
                self.workflowStatuses.removeValue(forKey: objectID)
            }
        }
    }
}
