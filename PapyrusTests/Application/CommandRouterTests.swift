import Testing
@testable import PapyrusCore

struct CommandRouterTests {
    @Test
    func copyCommandsKeepTextFallbackAndPrimaryTarget() {
        let descriptor = AppCommand.copyTitle.descriptor

        #expect(descriptor.target == .primaryItem)
        #expect(descriptor.fallsBackToTextCopy == true)
    }

    @Test
    func refreshTargetsSelectionAndRequiresFocus() {
        let descriptor = AppCommand.refreshMetadata.descriptor

        #expect(descriptor.target == .selection)
        #expect(descriptor.requiresFocusedLibraryContext(for: .globalShortcutLayer) == true)
    }

    @Test
    func importDoesNotRequireFocusedLibraryContext() {
        let descriptor = AppCommand.importPDF.descriptor

        #expect(descriptor.target == .library)
        #expect(descriptor.requiresFocusedLibraryContext(for: .globalShortcutLayer) == false)
    }
}
