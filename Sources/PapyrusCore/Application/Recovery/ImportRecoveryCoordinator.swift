import AppKit
import CoreData
import Foundation

struct PendingImportRequest: Codable {
    let displayName: String
    let pdfPath: String
}

enum ImportRecoveryError: LocalizedError {
    case appBundleUnavailable
    case invalidQueuedPDF

    var errorDescription: String? {
        switch self {
        case .appBundleUnavailable:
            return "Could not relaunch Papyrus"
        case .invalidQueuedPDF:
            return "Queued PDF is no longer available"
        }
    }
}

@MainActor
final class ImportRecoveryCoordinator {
    static let shared = ImportRecoveryCoordinator()

    private let defaultsKey = "Papyrus.pendingImportRequests.v1"

    func storeFilesMissing(for context: NSManagedObjectContext) -> Bool {
        guard let store = context.persistentStoreCoordinator?.persistentStores.first,
              let storeURL = store.url else {
            return true
        }

        if store.type == NSInMemoryStoreType {
            return false
        }

        let fm = FileManager.default
        let directoryURL = storeURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: directoryURL.path) {
            do {
                try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            } catch {
                return true
            }
        }

        // A newly attached SQLite store may not materialize its files until the first save.
        // If Core Data already has the store open, importing should proceed and let save-time
        // errors drive recovery instead of forcing a relaunch on a fresh empty library.
        return false
    }

    func enqueuePDFImport(from sourceURL: URL) throws -> PendingImportRequest {
        let stagedURL = try stagePDFForRecovery(from: sourceURL)
        let request = PendingImportRequest(
            displayName: sourceURL.lastPathComponent,
            pdfPath: stagedURL.path
        )
        try append(request)
        return request
    }

    func consumePendingRequests() -> [PendingImportRequest] {
        let requests = loadRequests()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        return requests
    }

    func cleanupConsumedRequest(_ request: PendingImportRequest) {
        guard FileManager.default.fileExists(atPath: request.pdfPath) else {
            return
        }

        try? FileManager.default.removeItem(atPath: request.pdfPath)
    }

    func relaunchApplication() async throws {
        let bundleURL = Bundle.main.bundleURL
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw ImportRecoveryError.appBundleUnavailable
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: ())
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func append(_ request: PendingImportRequest) throws {
        var requests = loadRequests()
        requests.append(request)
        let data = try JSONEncoder().encode(requests)
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func loadRequests() -> [PendingImportRequest] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let requests = try? JSONDecoder().decode([PendingImportRequest].self, from: data) else {
            return []
        }
        return requests
    }

    private func stagePDFForRecovery(from sourceURL: URL) throws -> URL {
        let directory = try recoveryDirectoryURL()
        let preferredName = sourceURL.lastPathComponent.isEmpty ? UUID().uuidString + ".pdf" : sourceURL.lastPathComponent
        let destinationURL = uniqueURL(in: directory, preferredName: preferredName)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func recoveryDirectoryURL() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport
            .appendingPathComponent("Papyrus", isDirectory: true)
            .appendingPathComponent("Pending Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func uniqueURL(in directory: URL, preferredName: String) -> URL {
        let sanitizedName = preferredName.replacingOccurrences(of: "/", with: "_")
        let baseURL = directory.appendingPathComponent(sanitizedName)
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let stem = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension
        var counter = 1

        while true {
            let candidateName: String
            if ext.isEmpty {
                candidateName = "\(stem)-\(counter)"
            } else {
                candidateName = "\(stem)-\(counter).\(ext)"
            }
            let candidate = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
