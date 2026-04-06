import Foundation

@MainActor
final class CommandRouter {
    static let shared = CommandRouter()

    private init() {}

    func execute(
        _ command: AppCommand,
        context: CommandContext,
        perform: (AppCommand, CommandContext) -> Void
    ) -> Bool {
        guard shouldExecute(command, context: context) else { return false }
        perform(command, context)
        return true
    }

    private func shouldExecute(_ command: AppCommand, context: CommandContext) -> Bool {
        if context.library.hasBlockingModal {
            return false
        }

        let descriptor = command.descriptor

        if descriptor.requiresFocusedLibraryContext(for: context.source),
           !context.library.isCommandFocusEligible {
            if descriptor.fallsBackToTextCopy {
                context.onTextCopyFallback?()
            }
            return false
        }

        return true
    }
}
