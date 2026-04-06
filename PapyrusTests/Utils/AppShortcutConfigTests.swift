import Testing
@testable import PapyrusCore

struct AppShortcutConfigTests {
    @Test
    func acceptsWhitelistedSingleKeysAndModifierShortcuts() {
        #expect(AppShortcutConfig.isValidBinding("space"))
        #expect(AppShortcutConfig.isValidBinding("return"))
        #expect(AppShortcutConfig.isValidBinding("delete"))
        #expect(AppShortcutConfig.isValidBinding("escape"))
        #expect(AppShortcutConfig.isValidBinding("f1"))
        #expect(AppShortcutConfig.isValidBinding("cmd+shift+c"))
    }

    @Test
    func rejectsBareLettersDigitsAndSequences() {
        #expect(!AppShortcutConfig.isValidBinding("p"))
        #expect(!AppShortcutConfig.isValidBinding("1"))
        #expect(!AppShortcutConfig.isValidBinding("gg"))
        #expect(!AppShortcutConfig.isValidBinding("cmd+f1"))
    }

    @Test
    func normalizesBindingsToSingleValidatedEntryPerAction() {
        let shortcuts = AppShortcutConfig.normalizedBindings([
            InputAction.openPDF.rawValue: ["RETURN", "space"],
            InputAction.pinPaper.rawValue: ["p", "f1"],
            InputAction.focusSearch.rawValue: ["cmd+f"],
        ])

        #expect(shortcuts[InputAction.openPDF.rawValue] == ["return"])
        #expect(shortcuts[InputAction.pinPaper.rawValue] == ["f1"])
        #expect(shortcuts[InputAction.focusSearch.rawValue] == ["cmd+f"])
    }
}
