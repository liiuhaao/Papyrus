import Foundation

package enum CommandLineToolSupport {
    package static let bundledExecutableName = "papyrus"
    package static let installDestinationURL = URL(fileURLWithPath: "/usr/local/bin/papyrus")

    private static let supportedInstallRoots = [
        URL(fileURLWithPath: "/Applications", isDirectory: true).standardizedFileURL.path,
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL.path
    ]

    package enum InstallPlan: Equatable {
        case unavailable
        case upToDate
        case install(source: URL, destination: URL, requiresPrivilegedInstall: Bool)
        case blockedByExistingCommand(destination: URL)
    }

    package static func bundledCLIURL(bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?
            .appendingPathComponent(bundledExecutableName)
    }

    package static func installPlan(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        installDestinationURL: URL = installDestinationURL
    ) -> InstallPlan {
        guard let bundledCLIURL = bundledCLIURL(bundle: bundle) else {
            return .unavailable
        }

        return installPlan(
            bundleURL: bundle.bundleURL,
            bundledCLIURL: bundledCLIURL,
            fileManager: fileManager,
            installDestinationURL: installDestinationURL
        )
    }

    package static func installPlan(
        bundleURL: URL,
        bundledCLIURL: URL,
        fileManager: FileManager = .default,
        installDestinationURL: URL = installDestinationURL
    ) -> InstallPlan {
        guard isSupportedInstallLocation(bundleURL),
              fileManager.isExecutableFile(atPath: bundledCLIURL.path) else {
            return .unavailable
        }

        if let existingTarget = symbolicLinkTarget(at: installDestinationURL, fileManager: fileManager) {
            if samePath(existingTarget, bundledCLIURL) {
                return .upToDate
            }

            if isManagedPapyrusCommand(existingTarget) {
                return .install(
                    source: bundledCLIURL,
                    destination: installDestinationURL,
                    requiresPrivilegedInstall: requiresPrivilegedInstall(
                        for: installDestinationURL,
                        fileManager: fileManager
                    )
                )
            }

            return .blockedByExistingCommand(destination: installDestinationURL)
        }

        if fileManager.fileExists(atPath: installDestinationURL.path) {
            return samePath(installDestinationURL, bundledCLIURL)
                ? .upToDate
                : .blockedByExistingCommand(destination: installDestinationURL)
        }

        return .install(
            source: bundledCLIURL,
            destination: installDestinationURL,
            requiresPrivilegedInstall: requiresPrivilegedInstall(
                for: installDestinationURL,
                fileManager: fileManager
            )
        )
    }

    package static func isSupportedInstallLocation(_ bundleURL: URL) -> Bool {
        let path = bundleURL.standardizedFileURL.path
        guard !path.hasPrefix("/Volumes/"), !path.contains("/AppTranslocation/") else {
            return false
        }

        return supportedInstallRoots.contains { root in
            path.hasPrefix(root + "/")
        }
    }

    private static func requiresPrivilegedInstall(
        for installDestinationURL: URL,
        fileManager: FileManager
    ) -> Bool {
        let installDirectoryURL = installDestinationURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: installDirectoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return true
        }

        return !fileManager.isWritableFile(atPath: installDirectoryURL.path)
    }

    private static func symbolicLinkTarget(
        at url: URL,
        fileManager: FileManager
    ) -> URL? {
        guard let rawTarget = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else {
            return nil
        }

        if rawTarget.hasPrefix("/") {
            return URL(fileURLWithPath: rawTarget).standardizedFileURL
        }

        return url.deletingLastPathComponent()
            .appendingPathComponent(rawTarget)
            .standardizedFileURL
    }

    private static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private static func isManagedPapyrusCommand(_ targetURL: URL) -> Bool {
        let path = targetURL.standardizedFileURL.path
        return path.hasSuffix("/Papyrus.app/Contents/Resources/\(bundledExecutableName)")
            || path.hasSuffix("/PapyrusCLI")
    }
}
