import Foundation

enum CommandSource: String {
    case commandMenu
    case notification
    case singleKeyMonitor
    case eventMonitor
    case globalShortcutLayer
    case inputAction
}

struct CommandContext {
    let source: CommandSource
    let library: LibraryInputContext
    let onTextCopyFallback: (() -> Void)?
}
