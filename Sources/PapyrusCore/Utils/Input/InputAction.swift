import Foundation
import SwiftUI

package enum InputAction: String, CaseIterable, Identifiable {
    case moveDown = "move_down"
    case moveUp = "move_up"
    case moveLeft = "move_left"
    case moveRight = "move_right"
    case moveTop = "move_top"
    case moveBottom = "move_bottom"
    case pageDown = "page_down"
    case pageUp = "page_up"
    case openPDF = "open_pdf"
    case quickLook = "quick_look"
    case toggleRead = "toggle_read"
    case flagPaper = "flag_paper"
    case pinPaper = "pin_paper"
    case deletePaper = "delete_paper"
    case refreshMetadata = "refresh_metadata"
    case copyBibTeX = "copy_bibtex"
    case copyTitle = "copy_title"
    case focusSearch = "focus_search"
    case toggleLeftPanel = "toggle_left_panel"
    case toggleRightPanel = "toggle_right_panel"
    case importPDF = "import_pdf"
    case rate1 = "rate_1"
    case rate2 = "rate_2"
    case rate3 = "rate_3"
    case rate4 = "rate_4"
    case rate5 = "rate_5"
    case rateClear = "rate_clear"
    case showHelp = "show_help"
    case clearFilters = "clear_filters"

    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .moveDown: return "Move Down"
        case .moveUp: return "Move Up"
        case .moveLeft: return "Move Left"
        case .moveRight: return "Move Right"
        case .moveTop: return "Move Top"
        case .moveBottom: return "Move Bottom"
        case .pageDown: return "Page Down"
        case .pageUp: return "Page Up"
        case .openPDF: return "Open PDF"
        case .quickLook: return "Quick Look"
        case .toggleRead: return "Toggle Read"
        case .flagPaper: return "Toggle Flag"
        case .pinPaper: return "Toggle Pin"
        case .deletePaper: return "Delete Selection"
        case .refreshMetadata: return "Refresh Metadata"
        case .copyBibTeX: return "Copy BibTeX"
        case .copyTitle: return "Copy Title"
        case .focusSearch: return "Focus Search"
        case .toggleLeftPanel: return "Toggle Sidebar"
        case .toggleRightPanel: return "Toggle Inspector"
        case .importPDF: return "Import PDFs"
        case .rate1: return "Rate 1"
        case .rate2: return "Rate 2"
        case .rate3: return "Rate 3"
        case .rate4: return "Rate 4"
        case .rate5: return "Rate 5"
        case .rateClear: return "Clear Rating"
        case .showHelp: return "Show Help"
        case .clearFilters: return "Clear Filters"
        }
    }
}

enum InputBindingKind: String, Codable {
    case keyEquivalent
    case keyCombo
    case keySequence
}

struct InputBinding: Hashable, Codable, Identifiable {
    let rawValue: String
    let kind: InputBindingKind

    var id: String { rawValue }

    init(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawValue = normalized
        self.kind = Self.classify(normalized)
    }

    private static func classify(_ rawValue: String) -> InputBindingKind {
        let normalized = rawValue.lowercased()
        if normalized.contains("+") {
            return .keyCombo
        }
        if normalized == "left" || normalized == "right" || normalized == "up" || normalized == "down"
            || normalized == "return" || normalized == "enter"
            || normalized == "space" || normalized == "tab"
            || normalized == "escape" || normalized == "esc"
            || normalized == "delete" || normalized == "backspace" {
            return .keyEquivalent
        }
        return rawValue.count > 1 ? .keySequence : .keyEquivalent
    }
}
