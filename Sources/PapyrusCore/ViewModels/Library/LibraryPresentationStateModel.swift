import SwiftUI
import CoreData

@MainActor
final class LibraryPresentationStateModel: ObservableObject {
    private let panelAnimation = Animation.easeInOut(duration: 0.2)

    @Published var showingImportDialog = false
    @Published var showingDeleteAllConfirm = false
    @Published var showingDeleteSelectedConfirm = false
    @Published var showingBatchEdit = false
    @Published var isDragTargeted = false
    @Published var showInspector = true
    @Published var toastMessage: String?
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var pendingDeletePaperIDs: Set<NSManagedObjectID> = []

    func handleSelectionChange(selectedCount: Int) {
        if selectedCount < 2 && showingBatchEdit {
            showingBatchEdit = false
        }
    }

    func toggleSidebarVisibility() {
        setSidebarVisible(columnVisibility == .detailOnly)
    }

    func setSidebarVisible(_ visible: Bool) {
        let targetVisibility: NavigationSplitViewVisibility = visible ? .all : .detailOnly
        guard columnVisibility != targetVisibility else { return }
        withAnimation(panelAnimation) {
            columnVisibility = targetVisibility
        }
    }

    func revealInspector() {
        setInspectorVisible(true)
    }

    func toggleInspectorVisibility() {
        setInspectorVisible(!showInspector)
    }

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard self?.toastMessage == message else { return }
            self?.toastMessage = nil
        }
    }

    func hasBlockingModal(errorMessagePresent: Bool) -> Bool {
        showingDeleteSelectedConfirm
            || showingDeleteAllConfirm
            || errorMessagePresent
            || showingImportDialog
    }

    private func setInspectorVisible(_ visible: Bool) {
        guard showInspector != visible else { return }
        withAnimation(panelAnimation) {
            showInspector = visible
        }
    }
}
