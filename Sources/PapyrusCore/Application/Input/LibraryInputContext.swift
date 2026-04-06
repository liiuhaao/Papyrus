import CoreData
import Foundation

enum CommandTargetKind {
    case primaryItem
    case selection
    case library
    case navigation
    case uiState
}

struct LibraryInputContext {
    let activeViewMode: LibraryViewMode
    let supportsMultiSelection: Bool
    let hasBlockingModal: Bool
    let isTextInputFocused: Bool
    let isLibraryWindowActive: Bool
    let isCommandFocusEligible: Bool
    let primaryPaperID: NSManagedObjectID?
    let selectedPaperIDs: Set<NSManagedObjectID>

    var hasPrimaryPaper: Bool {
        primaryPaperID != nil
    }

    var selectedCount: Int {
        selectedPaperIDs.count
    }

    var hasSelection: Bool {
        !selectedPaperIDs.isEmpty
    }
}

struct CommandDescriptor {
    let target: CommandTargetKind
    let fallsBackToTextCopy: Bool

    func requiresFocusedLibraryContext(for source: CommandSource) -> Bool {
        if source == .singleKeyMonitor {
            return true
        }
        switch target {
        case .primaryItem, .selection:
            return true
        case .library, .navigation, .uiState:
            return false
        }
    }
}

extension AppCommand {
    var descriptor: CommandDescriptor {
        switch self {
        case .openPDF, .quickLook, .rate1, .rate2, .rate3, .rate4, .rate5, .rateClear:
            return CommandDescriptor(target: .primaryItem, fallsBackToTextCopy: false)
        case .copyTitle, .copyBibTeX:
            return CommandDescriptor(target: .primaryItem, fallsBackToTextCopy: true)
        case .deletePaper, .refreshMetadata, .flagPaper, .pinPaper, .toggleRead:
            return CommandDescriptor(target: .selection, fallsBackToTextCopy: false)
        case .moveDown, .moveUp, .moveLeft, .moveRight, .moveTop, .moveBottom, .pageDown, .pageUp:
            return CommandDescriptor(target: .navigation, fallsBackToTextCopy: false)
        case .focusSearch, .toggleLeftPanel, .toggleRightPanel, .showHelp, .clearFilters:
            return CommandDescriptor(target: .uiState, fallsBackToTextCopy: false)
        case .importPDF:
            return CommandDescriptor(target: .library, fallsBackToTextCopy: false)
        }
    }
}
