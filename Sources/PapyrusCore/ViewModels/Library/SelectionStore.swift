import CoreData
import Foundation

@MainActor
final class SelectionStore: ObservableObject {
    @Published private(set) var mode: LibraryViewMode = .list
    @Published private(set) var selectedIDs: Set<NSManagedObjectID> = []
    @Published private(set) var selectedCount: Int = 0
    @Published private(set) var primaryID: NSManagedObjectID?

    func clear() {
        if mode != .list {
            mode = .list
        }
        if !selectedIDs.isEmpty {
            selectedIDs = []
        }
        if selectedCount != 0 {
            selectedCount = 0
        }
        if primaryID != nil {
            primaryID = nil
        }
    }

    func sync(
        mode: LibraryViewMode,
        selectedIDs: Set<NSManagedObjectID>,
        primarySelectionID: NSManagedObjectID?,
        visiblePapers _: [Paper],
        allPapers _: [Paper],
        context _: NSManagedObjectContext
    ) {
        if self.mode != mode {
            self.mode = mode
        }
        if self.selectedIDs != selectedIDs {
            self.selectedIDs = selectedIDs
        }
        if selectedCount != selectedIDs.count {
            selectedCount = selectedIDs.count
        }
        if primaryID != primarySelectionID {
            primaryID = primarySelectionID
        }
    }
}
