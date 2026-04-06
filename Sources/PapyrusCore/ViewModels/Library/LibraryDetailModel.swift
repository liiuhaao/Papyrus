import CoreData
import Foundation

@MainActor
final class LibraryDetailModel: ObservableObject {
    @Published private(set) var currentPaperID: NSManagedObjectID?
    @Published var showBibTeX = false
    @Published var bibTeXText = ""
    @Published var isFetchingBib = false
    @Published var showEditMetadata = false

    func updateSelection(_ paper: Paper?) {
        updateSelection(id: paper?.objectID)
    }

    func updateSelection(id: NSManagedObjectID?) {
        guard currentPaperID != id else { return }
        currentPaperID = id
        resetTransientState()
    }

    func clearSelection() {
        updateSelection(id: nil)
    }

    func requestEditMetadata(for paper: Paper) {
        updateSelection(paper)
        showEditMetadata = true
    }

    func showBibTeXPopover() {
        showBibTeX = true
    }

    func setBibTeX(_ text: String, for paperID: NSManagedObjectID) {
        guard currentPaperID == paperID else { return }
        bibTeXText = text
        isFetchingBib = false
    }

    func beginBibTeXFetch(for paperID: NSManagedObjectID) {
        guard currentPaperID == paperID else { return }
        isFetchingBib = true
    }

    func cancelBibTeXFetch() {
        isFetchingBib = false
    }

    func resetTransientState() {
        if showBibTeX {
            showBibTeX = false
        }
        if !bibTeXText.isEmpty {
            bibTeXText = ""
        }
        if isFetchingBib {
            isFetchingBib = false
        }
        if showEditMetadata {
            showEditMetadata = false
        }
    }
}
