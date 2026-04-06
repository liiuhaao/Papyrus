import Foundation
import PapyrusCore

do {
    let exitCode = try await CLISupport.run(arguments: CommandLine.arguments)
    exit(exitCode)
} catch {
    fputs("papyrus: \(error.localizedDescription)\n", stderr)
    exit(1)
}
