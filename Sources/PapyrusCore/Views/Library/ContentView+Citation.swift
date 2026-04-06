import AppKit
import SwiftUI

extension ContentView {
    var bibTeXButton: some View {
        Button {
            detailModel.showBibTeXPopover()
            refreshBibTeX()
        } label: {
            Image(systemName: "text.quote")
        }
        .disabled(currentPrimaryPaper == nil)
        .help("Copy Citation")
        .popover(isPresented: $detailModel.showBibTeX, arrowEdge: .bottom) {
            CitationPopover(
                bibTeXText: detailModel.bibTeXText,
                isBibTeXLoading: detailModel.isFetchingBib,
                gbtText: citationText(.gbt7714),
                mlaText: citationText(.mla),
                apaText: citationText(.apa),
                onCopyBibTeX: copyBibTeXText,
                onCopyGBT: { copyCitation(.gbt7714) },
                onCopyMLA: { copyCitation(.mla) },
                onCopyAPA: { copyCitation(.apa) }
            )
        }
    }

    func copyBibTeX() {
        guard let paper = currentPrimaryPaper else { return }
        detailModel.beginBibTeXFetch(for: paper.objectID)
        Task {
            let bib = await MetadataService.shared.fetchBibTeX(for: paper)
            let normalized = PaperCitationSupport.normalizeBibTeX(bib, for: paper)
            detailModel.setBibTeX(normalized, for: paper.objectID)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(normalized, forType: .string)
            presentationState.showToast("BibTeX copied")
        }
    }

    func copySelectedBibTeX() {
        guard let paper = currentPrimaryPaper else { return }
        Task {
            let bib = await MetadataService.shared.fetchBibTeX(for: paper)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(bib, forType: .string)
            presentationState.showToast("BibTeX copied")
        }
    }

    func copySelectedTitle() {
        guard let paper = currentPrimaryPaper else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paper.displayTitle, forType: .string)
        presentationState.showToast("Title copied")
    }

    func applyRating(_ rating: Int) {
        guard let paper = currentPrimaryPaper else { return }
        paper.rating = Int16(rating)
        paper.dateModified = Date()
        try? paper.managedObjectContext?.save()
        presentationState.showToast(
            rating == 0 ? "Rating cleared" : "Rating: " + "\(String(repeating: "★", count: rating))"
        )
    }

    func copyBibTeXText() {
        if detailModel.bibTeXText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copyBibTeX()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(detailModel.bibTeXText, forType: .string)
        presentationState.showToast("BibTeX copied")
    }

    func refreshBibTeX() {
        guard let paper = currentPrimaryPaper else {
            detailModel.resetTransientState()
            return
        }
        detailModel.beginBibTeXFetch(for: paper.objectID)
        let currentID = paper.objectID
        Task {
            let bib = await MetadataService.shared.fetchBibTeX(for: paper)
            detailModel.setBibTeX(PaperCitationSupport.normalizeBibTeX(bib, for: paper), for: currentID)
        }
    }

    func copyCitation(_ style: PaperCitationStyle) {
        guard let paper = currentPrimaryPaper else { return }
        let citation = PaperCitationSupport.formatCitation(for: paper, style: style)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(citation, forType: .string)
        presentationState.showToast("\(style.label) copied")
    }

    func citationText(_ style: PaperCitationStyle) -> String {
        guard let paper = currentPrimaryPaper else { return "" }
        return PaperCitationSupport.formatCitation(for: paper, style: style)
    }
}

struct CitationPopover: View {
    let bibTeXText: String
    let isBibTeXLoading: Bool
    let gbtText: String
    let mlaText: String
    let apaText: String
    let onCopyBibTeX: () -> Void
    let onCopyGBT: () -> Void
    let onCopyMLA: () -> Void
    let onCopyAPA: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                citationBlock(
                    title: "BibTeX",
                    text: bibTeXText,
                    isLoading: isBibTeXLoading,
                    monospaced: true,
                    onCopy: onCopyBibTeX
                )
                Divider()
                citationBlock(
                    title: "GB/T 7714",
                    text: gbtText,
                    onCopy: onCopyGBT
                )
                Divider()
                citationBlock(
                    title: "MLA",
                    text: mlaText,
                    onCopy: onCopyMLA
                )
                Divider()
                citationBlock(
                    title: "APA",
                    text: apaText,
                    onCopy: onCopyAPA
                )
            }
            .frame(maxWidth: 520, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func citationBlock(
        title: String,
        text: String,
        isLoading: Bool = false,
        monospaced: Bool = false,
        onCopy: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Copy") { onCopy() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            Text(text.isEmpty ? "No citation available." : text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
        }
    }
}
