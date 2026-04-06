import Foundation

enum SelectionTrigger: Equatable {
    case keyboard
    case mouse
    case programmatic
}

enum LinearNavigationCommand {
    case up
    case down
    case left
    case right
    case pageUp
    case pageDown
    case top
    case bottom
}
