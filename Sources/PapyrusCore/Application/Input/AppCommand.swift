import Foundation

package enum AppCommand: String, CaseIterable {
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

    package init?(inputAction: InputAction) {
        self.init(rawValue: inputAction.rawValue)
    }

    package var inputAction: InputAction? {
        InputAction(rawValue: rawValue)
    }
}
