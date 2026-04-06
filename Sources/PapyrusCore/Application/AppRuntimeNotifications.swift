import Foundation

package extension Notification.Name {
    static let executeLibraryCommand = Notification.Name("Papyrus.executeLibraryCommand")
    static let browserImportURLReceived = Notification.Name("Papyrus.browserImportURLReceived")
}

@MainActor
package final class BrowserImportURLDispatcher {
    package static let shared = BrowserImportURLDispatcher()

    private var pendingURLs: [URL] = []

    package func enqueue(_ url: URL) {
        pendingURLs.append(url)
        NotificationCenter.default.post(name: .browserImportURLReceived, object: url)
    }

    package func drainPendingURLs() -> [URL] {
        let queued = pendingURLs
        pendingURLs.removeAll()
        return queued
    }
}
