import SwiftUI

struct GlobalShortcutConfiguration {
    let openPDFShortcut: KeyboardShortcut?
    let quickLookShortcut: KeyboardShortcut?
    let deletePaperShortcut: KeyboardShortcut?
    let focusSearchShortcut: KeyboardShortcut?
    let toggleLeftPanelShortcut: KeyboardShortcut?
    let toggleRightPanelShortcut: KeyboardShortcut?
    let importPDFShortcut: KeyboardShortcut?
    let refreshMetadataShortcut: KeyboardShortcut?
    let pinPaperShortcut: KeyboardShortcut?
    let flagPaperShortcut: KeyboardShortcut?
    let copyTitleShortcut: KeyboardShortcut?
    let copyPDFShortcut: KeyboardShortcut?
    let copyBibTeXShortcut: KeyboardShortcut?
    let openPDF: () -> Void
    let quickLook: () -> Void
    let deletePaper: () -> Void
    let focusSearch: () -> Void
    let toggleLeftPanel: () -> Void
    let toggleRightPanel: () -> Void
    let importPDF: () -> Void
    let refreshMetadata: () -> Void
    let pinPaper: () -> Void
    let flagPaper: () -> Void
    let copyTitle: () -> Void
    let copyPDF: () -> Void
    let copyBibTeX: () -> Void
}

struct GlobalShortcutLayer: View {
    let configuration: GlobalShortcutConfiguration

    var body: some View {
        Group {
            Button("", action: configuration.openPDF).keyboardShortcut(configuration.openPDFShortcut)
            Button("", action: configuration.quickLook).keyboardShortcut(configuration.quickLookShortcut)
            Button("", action: configuration.deletePaper).keyboardShortcut(configuration.deletePaperShortcut)
            Button("", action: configuration.focusSearch).keyboardShortcut(configuration.focusSearchShortcut)
            Button("", action: configuration.toggleLeftPanel).keyboardShortcut(configuration.toggleLeftPanelShortcut)
            Button("", action: configuration.toggleRightPanel).keyboardShortcut(configuration.toggleRightPanelShortcut)
            Button("", action: configuration.importPDF).keyboardShortcut(configuration.importPDFShortcut)
            Button("", action: configuration.refreshMetadata).keyboardShortcut(configuration.refreshMetadataShortcut)
            Button("", action: configuration.pinPaper).keyboardShortcut(configuration.pinPaperShortcut)
            Button("", action: configuration.flagPaper).keyboardShortcut(configuration.flagPaperShortcut)
            Button("", action: configuration.copyTitle).keyboardShortcut(configuration.copyTitleShortcut)
            Button("", action: configuration.copyPDF).keyboardShortcut(configuration.copyPDFShortcut)
            Button("", action: configuration.copyBibTeX).keyboardShortcut(configuration.copyBibTeXShortcut)
        }
        .labelsHidden()
        .frame(width: 0, height: 0)
        .opacity(0.01)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
