import SwiftUI
import Textual
import AppKit

struct MarkdownRenderer: View {
    let text: String

    var body: some View {
        StructuredText(markdown: text, syntaxExtensions: [.math])
            .environment(\.openURL, OpenURLAction { url in
                NSWorkspace.shared.open(url)
                return .handled
            })
            .textual.textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
