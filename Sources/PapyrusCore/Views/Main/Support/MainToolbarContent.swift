import SwiftUI

struct MainToolbarContent: ToolbarContent {
    let configuration: LibraryToolbarConfiguration

    var body: some ToolbarContent {
        paperToolbarItems
    }

    @ToolbarContentBuilder
    private var paperToolbarItems: some ToolbarContent {
        let any = configuration.hasAnySelection

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: configuration.toggleFlag) {
                Image(systemName: configuration.flagIcon)
            }
            .disabled(!any)
            .help(configuration.flagHelp)

            Button(action: configuration.togglePin) {
                Image(systemName: configuration.pinIcon)
            }
            .disabled(!any)
            .help(configuration.pinHelp)

            Button(action: configuration.showEditor) {
                Image(systemName: "square.and.pencil")
            }
            .disabled(!configuration.isEditorEnabled)
            .help("Edit")

            Button(action: configuration.showDeleteSelectedConfirm) {
                Image(systemName: "trash")
            }
            .disabled(!any)
            .foregroundStyle(any ? Color.red : Color.secondary)
            .help(configuration.selectedPaperCount > 1 ? "Delete \(configuration.selectedPaperCount) Papers" : "Delete Paper")
        }
    }
}
