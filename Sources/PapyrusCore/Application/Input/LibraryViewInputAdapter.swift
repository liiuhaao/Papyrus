import AppKit
import Foundation

struct LibrarySelectionRevealContext {
    let primarySelectionID: NSManagedObjectID?
    let visiblePapers: [Paper]
    let listTableView: NSTableView?
}

protocol LibraryViewInputAdapter {
    var mode: LibraryViewMode { get }
    var supportsMultiSelection: Bool { get }

    func canAcceptLibraryCommands(
        window: NSWindow,
        responder: NSResponder,
        listTableView: NSTableView?
    ) -> Bool

    @MainActor
    func handleNavigation(
        _ command: LinearNavigationCommand,
        interactions: LibraryInteractionCoordinator,
        visiblePapers: [Paper]
    )

    @MainActor
    func revealPrimarySelection(using context: LibrarySelectionRevealContext)
}

struct ListViewInputAdapter: LibraryViewInputAdapter {
    let mode: LibraryViewMode = .list
    let supportsMultiSelection: Bool = true

    func canAcceptLibraryCommands(
        window: NSWindow,
        responder: NSResponder,
        listTableView: NSTableView?
    ) -> Bool {
        guard let view = responder as? NSView else { return false }
        if let tableView = listTableView {
            return view.nearestTableView === tableView
        }
        return view.nearestTableView != nil
    }

    @MainActor
    func handleNavigation(
        _ command: LinearNavigationCommand,
        interactions: LibraryInteractionCoordinator,
        visiblePapers: [Paper]
    ) {
        interactions.listSelection.handleNavigation(command, in: visiblePapers)
    }

    @MainActor
    func revealPrimarySelection(using context: LibrarySelectionRevealContext) {
        guard let selectedID = context.primarySelectionID else { return }
        guard let tableView = context.listTableView else { return }
        guard let row = context.visiblePapers.firstIndex(where: { $0.objectID == selectedID }) else { return }
        tableView.scrollRowToVisible(row)
    }
}

struct GalleryViewInputAdapter: LibraryViewInputAdapter {
    let mode: LibraryViewMode = .gallery
    let supportsMultiSelection: Bool = true

    func canAcceptLibraryCommands(
        window: NSWindow,
        responder: NSResponder,
        listTableView: NSTableView?
    ) -> Bool {
        _ = responder
        _ = listTableView
        return window === NSApp.keyWindow || window === NSApp.mainWindow
    }

    @MainActor
    func handleNavigation(
        _ command: LinearNavigationCommand,
        interactions: LibraryInteractionCoordinator,
        visiblePapers: [Paper]
    ) {
        interactions.gallerySelection.handleNavigation(command, in: visiblePapers)
    }

    @MainActor
    func revealPrimarySelection(using context: LibrarySelectionRevealContext) {
        _ = context
    }
}
