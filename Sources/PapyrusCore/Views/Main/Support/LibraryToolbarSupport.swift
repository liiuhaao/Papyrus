import Foundation

struct LibraryExportContext {
    let papers: [Paper]
    let label: String

    static func make(
        selectedPapers: [Paper],
        filteredPapers: [Paper],
        hasActiveFilters: Bool
    ) -> LibraryExportContext {
        let papers = selectedPapers.isEmpty ? filteredPapers : selectedPapers
        let label: String
        if !selectedPapers.isEmpty {
            label = "Export \(selectedPapers.count) selected"
        } else if hasActiveFilters {
            label = "Export \(filteredPapers.count)"
        } else {
            label = "Export all"
        }
        return LibraryExportContext(papers: papers, label: label)
    }
}

struct LibraryOnlineLinks {
    let scholar: URL?
    let semanticScholar: URL?
    let doi: URL?
    let arxiv: URL?
    let dblp: URL?

    init(paper: Paper?) {
        self.scholar = paper.flatMap(PaperCitationSupport.scholarURL(for:))
        self.semanticScholar = paper.flatMap(PaperCitationSupport.semanticScholarURL(for:))
        self.doi = paper.flatMap(PaperCitationSupport.doiURL(for:))
        self.arxiv = paper.flatMap(PaperCitationSupport.arxivURL(for:))
        self.dblp = paper.flatMap(PaperCitationSupport.dblpURL(for:))
    }

    var hasAny: Bool {
        scholar != nil || semanticScholar != nil || doi != nil || arxiv != nil || dblp != nil
    }
}

struct LibraryToolbarConfiguration {
    let selectedPaperCount: Int
    let hasSelectedPaper: Bool
    let showDeleteSelectedConfirm: () -> Void
    let toggleFlag: () -> Void
    let flagIcon: String
    let flagHelp: String
    let togglePin: () -> Void
    let pinIcon: String
    let pinHelp: String
    let showEditor: () -> Void

    var hasAnySelection: Bool {
        selectedPaperCount > 0
    }

    var isEditorEnabled: Bool {
        hasSelectedPaper || selectedPaperCount >= 2
    }

    init(
        selectedPaperCount: Int,
        hasSelectedPaper: Bool,
        showDeleteSelectedConfirm: @escaping () -> Void,
        toggleFlag: @escaping () -> Void,
        flagIcon: String,
        flagHelp: String,
        togglePin: @escaping () -> Void,
        pinIcon: String,
        pinHelp: String,
        showEditor: @escaping () -> Void
    ) {
        self.selectedPaperCount = selectedPaperCount
        self.hasSelectedPaper = hasSelectedPaper
        self.showDeleteSelectedConfirm = showDeleteSelectedConfirm
        self.toggleFlag = toggleFlag
        self.flagIcon = flagIcon
        self.flagHelp = flagHelp
        self.togglePin = togglePin
        self.pinIcon = pinIcon
        self.pinHelp = pinHelp
        self.showEditor = showEditor
    }
}
