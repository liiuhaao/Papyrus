import SwiftUI
import AppKit
import CoreData

struct PaperContextMenuContext {
    let papers: [Paper]
    let primaryPaper: Paper

    init(papers: [Paper], primaryPaper: Paper) {
        precondition(!papers.isEmpty, "PaperContextMenuContext requires at least one paper")
        self.papers = papers
        self.primaryPaper = papers.first(where: { $0.objectID == primaryPaper.objectID }) ?? papers[0]
    }

    var isMultiSelection: Bool {
        papers.count > 1
    }

    var hasLocalFiles: Bool {
        papers.contains { !($0.filePath?.isEmpty ?? true) }
    }

    var canCopyPDFs: Bool {
        papers.allSatisfy { !($0.filePath?.isEmpty ?? true) }
    }

    var canOpenPrimaryPDF: Bool {
        !(primaryPaper.filePath?.isEmpty ?? true)
    }

    var copyPDFTitle: String {
        isMultiSelection ? "Copy PDFs" : "Copy PDF"
    }

    var copyTitlesTitle: String {
        isMultiSelection ? "Copy Titles" : "Copy Title"
    }

    var pinTitle: String {
        let allPinned = papers.allSatisfy(\.isPinned)
        return allPinned ? "Unpin" : "Pin"
    }

    var flagTitle: String {
        let allFlagged = papers.allSatisfy(\.isFlagged)
        return allFlagged ? "Remove Flag" : "Flag"
    }

    var deleteTitle: String {
        isMultiSelection ? "Delete Selected" : "Delete"
    }

    var readingStatusTitle: String {
        "Toggle Reading Status" + "（\(primaryPaper.currentReadingStatus.label)）"
    }
}

enum PaperContextMenuSupport {
    static func resolvedContext(
        clickedPaper: Paper,
        visiblePapers: [Paper],
        selectedIDs: Set<NSManagedObjectID>
    ) -> PaperContextMenuContext {
        let selectedPapers = visiblePapers.filter { selectedIDs.contains($0.objectID) }
        let targetPapers: [Paper]
        if selectedIDs.contains(clickedPaper.objectID), !selectedPapers.isEmpty {
            targetPapers = selectedPapers
        } else {
            targetPapers = [clickedPaper]
        }
        return PaperContextMenuContext(papers: targetPapers, primaryPaper: clickedPaper)
    }

    static func showInFinder(_ papers: [Paper]) {
        let urls = papers.compactMap { paper -> URL? in
            guard let filePath = paper.filePath, !filePath.isEmpty else { return nil }
            return URL(fileURLWithPath: filePath)
        }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func copyPDFs(_ papers: [Paper], showToast: (String) -> Void) {
        let urls = papers.compactMap { paper -> NSURL? in
            guard let filePath = paper.filePath, !filePath.isEmpty else { return nil }
            return URL(fileURLWithPath: filePath) as NSURL
        }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls)
        showToast(urls.count > 1 ? "PDFs copied" : "PDF copied")
    }

    static func copyTitles(_ papers: [Paper], showToast: (String) -> Void) {
        let titles = papers.map(\.displayTitle).joined(separator: "\n")
        guard !titles.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(titles, forType: .string)
        showToast(papers.count > 1 ? "Titles copied" : "Title copied")
    }
}

struct PaperContextMenuHandlers {
    let openOnlineURL: (Paper) -> URL?
    let openPDF: (Paper) -> Void
    let quickLook: (Paper) -> Void
    let showInFinder: ([Paper]) -> Void
    let copyPDFs: ([Paper]) -> Void
    let cycleReadingStatus: (Paper) -> Void
    let editMetadata: (Paper) -> Void
    let copyTitles: ([Paper]) -> Void
    let copyBibTeX: ([Paper]) -> Void
    let refreshMetadata: ([Paper]) -> Void
    let setPinned: (Bool, [Paper]) -> Void
    let setFlag: (Bool, [Paper]) -> Void
    let setRating: (Int, [Paper]) -> Void
    let deletePapers: ([Paper]) -> Void
}

struct PaperContextMenuContent: View {
    let context: PaperContextMenuContext
    let handlers: PaperContextMenuHandlers

    var body: some View {
        if !context.isMultiSelection {
            Button("Open PDF") {
                handlers.openPDF(context.primaryPaper)
            }
            .disabled(!context.canOpenPrimaryPDF)

            Button("Quick Look") {
                handlers.quickLook(context.primaryPaper)
            }
            .disabled(!context.canOpenPrimaryPDF)

            if let url = handlers.openOnlineURL(context.primaryPaper) {
                Button("Open Online") {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        if context.hasLocalFiles {
            Button("Show in Finder") {
                handlers.showInFinder(context.papers)
            }
        }

        if context.canCopyPDFs {
            Button(context.copyPDFTitle) {
                handlers.copyPDFs(context.papers)
            }
        }

        if !context.isMultiSelection || context.hasLocalFiles {
            Divider()
        }

        Button(context.copyTitlesTitle) {
            handlers.copyTitles(context.papers)
        }

        Button("Copy BibTeX") {
            handlers.copyBibTeX(context.papers)
        }

        Divider()

        Button("Refresh Metadata") {
            handlers.refreshMetadata(context.papers)
        }

        if !context.isMultiSelection {
            Button("Edit Metadata") {
                handlers.editMetadata(context.primaryPaper)
            }
        }

        Divider()

        if !context.isMultiSelection {
            Button(context.readingStatusTitle) {
                handlers.cycleReadingStatus(context.primaryPaper)
            }
        }

        Button(context.pinTitle) {
            handlers.setPinned(!context.papers.allSatisfy(\.isPinned), context.papers)
        }

        Button(context.flagTitle) {
            handlers.setFlag(!context.papers.allSatisfy(\.isFlagged), context.papers)
        }

        Menu("Rating") {
            Button("Clear Rating") {
                handlers.setRating(0, context.papers)
            }
            ForEach(1...5, id: \.self) { rating in
                Button(String(repeating: "★", count: rating)) {
                    handlers.setRating(rating, context.papers)
                }
            }
        }

        Divider()

        Button(context.deleteTitle, role: .destructive) {
            handlers.deletePapers(context.papers)
        }
    }
}
