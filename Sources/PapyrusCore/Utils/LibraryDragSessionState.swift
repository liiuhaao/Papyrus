import Foundation

@MainActor
final class LibraryDragSessionState {
    static let shared = LibraryDragSessionState()

    var isInternalDragActive = false

    private init() {}
}
