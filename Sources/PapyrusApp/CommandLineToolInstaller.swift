import Foundation
import AppKit
import PapyrusCore

enum CommandLineToolInstaller {
    static func ensureInstalledIfNeeded() {
        switch CommandLineToolSupport.installPlan() {
        case .install(let source, let destination, let requiresPrivilegedInstall):
            do {
                try install(
                    source: source,
                    destination: destination,
                    requiresPrivilegedInstall: requiresPrivilegedInstall
                )
            } catch {
                NSLog("Papyrus CLI install skipped: %@", error.localizedDescription)
            }
        case .blockedByExistingCommand(let destination):
            NSLog(
                "Papyrus CLI install skipped because %@ is already managed by another command.",
                destination.path
            )
        case .unavailable, .upToDate:
            break
        }
    }

    private static func install(
        source: URL,
        destination: URL,
        requiresPrivilegedInstall: Bool
    ) throws {
        let installDirectory = destination.deletingLastPathComponent()
        let command = """
        mkdir -p \(shellQuoted(installDirectory.path)) && \
        ln -sfn \(shellQuoted(source.path)) \(shellQuoted(destination.path))
        """

        if requiresPrivilegedInstall {
            try runPrivilegedShellCommand(command)
        } else {
            try runShellCommand(command)
        }
    }

    private static func runShellCommand(_ command: String) throws {
        let process = Process()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstallerError.commandFailed(
                stderrText ?? "Shell command exited with status \(process.terminationStatus)."
            )
        }
    }

    private static func runPrivilegedShellCommand(_ command: String) throws {
        let scriptSource = "do shell script \(appleScriptQuoted(command)) with administrator privileges"
        guard let script = NSAppleScript(source: scriptSource) else {
            throw InstallerError.invalidScript
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? errorInfo.description
            throw InstallerError.commandFailed(message)
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func appleScriptQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private enum InstallerError: LocalizedError {
        case invalidScript
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidScript:
                return "Failed to build the Papyrus CLI install script."
            case .commandFailed(let message):
                return message
            }
        }
    }
}
