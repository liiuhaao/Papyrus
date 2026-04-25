import SwiftUI

package struct ShortcutCommandGroup {
    package let title: String
    package let actions: [InputAction]
}

package enum AppShortcutConfig {
    package static let keyboardGroups: [ShortcutCommandGroup] = [
        ShortcutCommandGroup(title: "Browse", actions: [.openPDF, .quickLook, .deletePaper, .focusSearch]),
        ShortcutCommandGroup(title: "Library", actions: [.importPDF, .refreshMetadata]),
        ShortcutCommandGroup(title: "Panels", actions: [.toggleLeftPanel, .toggleRightPanel]),
        ShortcutCommandGroup(title: "Item", actions: [.pinPaper, .flagPaper, .copyTitle, .copyPDF, .copyBibTeX]),
    ]

    static let customizableActions: [InputAction] = keyboardGroups.flatMap(\.actions)

    static let allowedSingleKeys: Set<String> = [
        "space", "return", "enter", "delete", "backspace", "escape", "esc",
        "f1", "f2", "f3", "f4", "f5", "f6"
    ]

    static let defaultBindings: [InputAction: [InputBinding]] = [
        .openPDF: [InputBinding(rawValue: "return")],
        .quickLook: [InputBinding(rawValue: "space")],
        .deletePaper: [InputBinding(rawValue: "delete")],
        .focusSearch: [InputBinding(rawValue: "cmd+f")],
        .toggleLeftPanel: [],
        .toggleRightPanel: [],
        .importPDF: [],
        .refreshMetadata: [],
        .pinPaper: [],
        .flagPaper: [],
        .copyTitle: [],
        .copyPDF: [],
        .copyBibTeX: [],
        .rate1: [],
        .rate2: [],
        .rate3: [],
        .rate4: [],
        .rate5: [],
        .rateClear: [],
    ]

    static let defaultShortcuts: [String: [String]] = Dictionary(
        uniqueKeysWithValues: customizableActions.map { action in
            (action.rawValue, defaultBindings[action, default: []].map(\.rawValue))
        }
    )

    static let allActions: [InputAction] = customizableActions

    static func parseShortcut(_ string: String) -> KeyboardShortcut? {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var parts = normalized.components(separatedBy: "+")
        var modifiers: EventModifiers = []
        parts.removeAll { part in
            switch part {
            case "cmd", "command": modifiers.insert(.command); return true
            case "opt", "option", "alt": modifiers.insert(.option); return true
            case "shift": modifiers.insert(.shift); return true
            case "ctrl", "control": modifiers.insert(.control); return true
            default: return false
            }
        }

        guard let keyString = parts.first, !keyString.isEmpty else { return nil }
        guard let key = keyEquivalent(rawKey: keyString) else { return nil }
        return KeyboardShortcut(key, modifiers: modifiers)
    }

    static func keyboardShortcut(action: InputAction, shortcuts: [String: [String]]) -> KeyboardShortcut? {
        let keys = shortcuts[action.rawValue] ?? defaultShortcuts[action.rawValue] ?? []
        for raw in keys {
            guard let shortcut = parseShortcut(raw) else { continue }
            if !shortcut.modifiers.isEmpty {
                return shortcut
            }
        }
        return nil
    }

    static func keyboardShortcut(action: String, shortcuts: [String: [String]]) -> KeyboardShortcut? {
        guard let action = InputAction(rawValue: action) else { return nil }
        return keyboardShortcut(action: action, shortcuts: shortcuts)
    }

    static func helperText(for action: InputAction) -> String {
        switch action {
        case .openPDF: return "Open the current paper."
        case .quickLook: return "Preview the selection."
        case .deletePaper: return "Delete the selection."
        case .focusSearch: return "Focus the search field."
        case .importPDF: return "Import PDFs."
        case .refreshMetadata: return "Refresh metadata."
        case .pinPaper: return "Toggle pin."
        case .flagPaper: return "Toggle flag."
        case .copyTitle: return "Copy the title."
        case .copyPDF: return "Copy the PDF file."
        case .copyBibTeX: return "Copy the BibTeX entry."
        case .rate1: return "Rate 1 star."
        case .rate2: return "Rate 2 stars."
        case .rate3: return "Rate 3 stars."
        case .rate4: return "Rate 4 stars."
        case .rate5: return "Rate 5 stars."
        case .rateClear: return "Clear the rating."
        case .toggleLeftPanel: return "Toggle the sidebar."
        case .toggleRightPanel: return "Toggle the inspector."
        default: return action.displayName
        }
    }

    static func displayString(for binding: String) -> String {
        let parts = displayParts(for: binding)
        guard !parts.isEmpty else { return "None" }
        return parts.joined(separator: " ")
    }

    static func displayParts(for binding: String) -> [String] {
        let normalized = normalizeBinding(binding)
        guard !normalized.isEmpty else { return [] }
        return normalized.split(separator: "+").map { part in
            switch part {
            case "cmd": return "⌘"
            case "opt": return "⌥"
            case "shift": return "⇧"
            case "ctrl": return "⌃"
            case "return", "enter": return "↩"
            case "space": return "Space"
            case "delete", "backspace": return "Delete"
            case "escape", "esc": return "Esc"
            default: return part.uppercased()
            }
        }
    }

    static func bindingPreview(from modifierFlags: NSEvent.ModifierFlags) -> String {
        let filtered = modifierFlags.intersection([.command, .option, .control, .shift])
        var parts: [String] = []
        if filtered.contains(.control) { parts.append("ctrl") }
        if filtered.contains(.option) { parts.append("opt") }
        if filtered.contains(.shift) { parts.append("shift") }
        if filtered.contains(.command) { parts.append("cmd") }
        return normalizeBinding(parts.joined(separator: "+"))
    }

    static func bindingString(from event: NSEvent) -> String? {
        let modifierFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key: String
        switch event.keyCode {
        case 36: key = "return"
        case 48: key = "tab"
        case 49: key = "space"
        case 51, 117: key = "delete"
        case 53: key = "escape"
        case 122: key = "f1"
        case 120: key = "f2"
        case 99: key = "f3"
        case 118: key = "f4"
        case 96: key = "f5"
        case 97: key = "f6"
        default:
            let characters = (event.charactersIgnoringModifiers ?? event.characters ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard characters.count == 1, let char = characters.first else { return nil }
            key = String(char)
        }

        var parts: [String] = []
        if modifierFlags.contains(.control) { parts.append("ctrl") }
        if modifierFlags.contains(.option) { parts.append("opt") }
        if modifierFlags.contains(.shift) { parts.append("shift") }
        if modifierFlags.contains(.command) { parts.append("cmd") }
        parts.append(key)
        return normalizeBinding(parts.joined(separator: "+"))
    }

    static func normalizedBindings(_ shortcuts: [String: [String]]) -> [String: [String]] {
        var output = defaultShortcuts
        let allowedActions = Set(customizableActions.map(\.rawValue))
        for (action, keys) in shortcuts where allowedActions.contains(action) {
            let cleaned = keys
                .map { normalizeBinding($0) }
                .compactMap { value -> String? in
                    guard isValidBinding(value) else { return nil }
                    return value
                }
            output[action] = cleaned.isEmpty ? [] : [cleaned[0]]
        }
        return output
    }

    static func isValidBinding(_ raw: String) -> Bool {
        let value = normalizeBinding(raw)
        guard !value.isEmpty else { return true }
        if value.contains("+") {
            return parseShortcut(value) != nil
        }
        return allowedSingleKeys.contains(value)
    }

    static func normalizeBinding(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func keyEquivalent(rawKey: String) -> KeyEquivalent? {
        switch rawKey {
        case "return", "enter": return .return
        case "delete", "backspace": return .delete
        case "space": return .space
        case "escape", "esc": return .escape
        case "tab": return .tab
        case "left": return .leftArrow
        case "right": return .rightArrow
        case "up": return .upArrow
        case "down": return .downArrow
        default:
            guard rawKey.count == 1, let character = rawKey.first else { return nil }
            return KeyEquivalent(character)
        }
    }
}
