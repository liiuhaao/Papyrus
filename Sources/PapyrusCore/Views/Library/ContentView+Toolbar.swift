import AppKit
import SwiftUI

extension ContentView {
    // MARK: - Toolbar

    var importMenu: some View {
        Button(action: { presentationState.showingImportDialog = true }) {
            Label("Import", systemImage: "plus")
        }
        .help("Import paper (⌘O)")
    }

    var exportMenu: some View {
        let context = exportContext
        return Menu {
            Button("Export BibTeX…") {
                PaperExportSupport.exportToFile(ext: "bib", content: viewModel.exportBibTeX(papers: context.papers))
            }
            Button("Export CSV…") {
                PaperExportSupport.exportToFile(ext: "csv", content: viewModel.exportCSV(papers: context.papers))
            }
            Button("Export JSON…") {
                PaperExportSupport.exportToFile(ext: "json", content: PaperExportSupport.exportJSON(context.papers))
            }
        } label: { Label(context.label, systemImage: "square.and.arrow.up") }
        .help("Export papers")
    }

    var sortMenu: some View {
        Menu {
            ForEach(PaperSortField.allCases, id: \.self) { field in
                Button {
                    if viewModel.filters.sortField == field { viewModel.filters.sortAscending.toggle() }
                    else { viewModel.filters.sortField = field; viewModel.filters.sortAscending = field == .title }
                } label: {
                    if viewModel.filters.sortField == field {
                        Label(field.rawValue, systemImage: viewModel.filters.sortAscending ? "chevron.up" : "chevron.down")
                    } else { Text(field.rawValue) }
                }
            }
        } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
        .help("Sort papers")
    }

    var viewModePicker: some View {
        Picker("", selection: viewModeBinding) {
            Label("List", systemImage: "list.bullet").tag(LibraryViewMode.list)
            Label("Gallery", systemImage: "square.grid.2x2").tag(LibraryViewMode.gallery)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .help("View mode")
    }

    var viewModeBinding: Binding<LibraryViewMode> {
        Binding(
            get: { appConfig.libraryViewMode },
            set: { newValue in
                guard appConfig.libraryViewMode != newValue else { return }
                try? appConfig.setLibraryViewMode(newValue)
            }
        )
    }

    var gallerySizePicker: some View {
        Menu {
            ForEach(GalleryCardSize.allCases, id: \.self) { size in
                Button(size.label) { try? appConfig.setGalleryCardSize(size) }
            }
        } label: {
            Label("Size", systemImage: "rectangle.expand.vertical")
        }
        .help("Gallery size")
        .disabled(appConfig.libraryViewMode != .gallery)
    }

    var viewControls: some View {
        HStack(spacing: 6) {
            viewModePicker
            gallerySizePicker
        }
    }

    var toolbarConfiguration: LibraryToolbarConfiguration {
        LibraryToolbarConfiguration(
            selectedPaperCount: currentSelectedPapers.count,
            hasSelectedPaper: currentPrimaryPaper != nil,
            showDeleteSelectedConfirm: { presentationState.showingDeleteSelectedConfirm = true },
            toggleFlag: toggleFlagForCurrentSelection,
            flagIcon: currentSelectionAllFlagged ? "flag.slash" : "flag",
            flagHelp: currentSelectionAllFlagged ? "Remove Flag" : "Flag",
            togglePin: togglePinForCurrentSelection,
            pinIcon: currentSelectionAllPinned ? "pin.slash" : "pin",
            pinHelp: currentSelectionAllPinned ? "Unpin" : "Pin",
            showEditor: showEditorForCurrentSelection
        )
    }

    var openMenu: some View {
        let links = onlineLinks
        return Menu {
            if let url = links.scholar { Button("Google Scholar") { NSWorkspace.shared.open(url) } }
            if let url = links.semanticScholar { Button("Semantic Scholar") { NSWorkspace.shared.open(url) } }
            if let url = links.doi { Button("DOI Page") { NSWorkspace.shared.open(url) } }
            if let url = links.arxiv { Button("arXiv Page") { NSWorkspace.shared.open(url) } }
            if let url = links.dblp { Button("DBLP") { NSWorkspace.shared.open(url) } }
        } label: { Image(systemName: "safari") }
        .disabled(currentPrimaryPaper == nil || !links.hasAny)
        .help("Open Online")
    }

    var refreshButton: some View {
        let any = !currentSelectedPapers.isEmpty
        return Button {
            viewModel.refreshMetadata(currentSelectedPapers)
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(!any)
        .help(currentSelectedPapers.count > 1 ? "Refresh Metadata (\(currentSelectedPapers.count))" : "Refresh Metadata")
    }

    var finderButton: some View {
        let single = currentPrimaryPaper != nil
        return Button {
            if let paper = currentPrimaryPaper { viewModel.showInFinder(paper) }
        } label: {
            Image(systemName: "folder")
        }
        .disabled(!single || currentPrimaryPaper?.filePath == nil)
        .help("Show in Finder")
    }

    private var exportContext: LibraryExportContext {
        LibraryExportContext.make(
            selectedPapers: currentSelectedPapers,
            filteredPapers: viewModel.filteredPapers,
            hasActiveFilters: viewModel.filters.hasActiveFilters
        )
    }

    private var onlineLinks: LibraryOnlineLinks {
        LibraryOnlineLinks(paper: currentPrimaryPaper)
    }

    func cycleReadingStatus(for paper: Paper) {
        paper.cycleReadingStatus()
        paper.dateModified = Date()
        try? paper.managedObjectContext?.save()
        Task { await viewModel.fetchPapers() }
        presentationState.showToast("Status: " + paper.currentReadingStatus.label)
    }

    var currentSelectionAllFlagged: Bool {
        let papers = currentSelectedPapers
        return !papers.isEmpty && papers.allSatisfy(\.isFlagged)
    }

    var currentSelectionAllPinned: Bool {
        let papers = currentSelectedPapers
        return !papers.isEmpty && papers.allSatisfy(\.isPinned)
    }

    func showEditorForCurrentSelection() {
        if currentSelectedPapers.count >= 2 {
            detailModel.resetTransientState()
            presentationState.showingBatchEdit = true
            presentationState.revealInspector()
        } else if let paper = currentPrimaryPaper {
            presentationState.showingBatchEdit = false
            detailModel.requestEditMetadata(for: paper)
            presentationState.revealInspector()
        }
    }

    func confirmDeleteSelection() {
        presentationState.showingDeleteSelectedConfirm = false
        let toDelete = deleteTargetPapers
        presentationState.pendingDeletePaperIDs = []
        prepareForDeletion(papers: toDelete)
        viewModel.deletePapers(toDelete)
    }

    func confirmDeleteAll() {
        presentationState.showingDeleteAllConfirm = false
        prepareForDeletion(papers: currentSelectedPapers)
        viewModel.deleteAllPapers()
    }

    func toggleFlagForCurrentSelection() {
        let papers = currentSelectedPapers
        guard !papers.isEmpty else { return }
        let shouldFlag = !papers.allSatisfy(\.isFlagged)
        viewModel.setFlag(shouldFlag, for: papers)
        presentationState.showToast(shouldFlag ? "Flagged" : "Flag removed")
    }

    func togglePinForCurrentSelection() {
        let papers = currentSelectedPapers
        guard !papers.isEmpty else { return }
        interactions.lastSelectionTrigger = .keyboard
        let shouldPin = !papers.allSatisfy(\.isPinned)
        viewModel.setPinned(shouldPin, for: papers)
        presentationState.showToast(shouldPin ? "Pinned" : "Unpinned")
    }

    func onlineURL(for paper: Paper) -> URL? {
        let doi = paper.doi ?? ""
        let arxiv = paper.arxivId ?? ""
        if !doi.isEmpty, !doi.lowercased().contains("10.48550") {
            return URL(string: "https://doi.org/\(doi)")
        }
        if !arxiv.isEmpty { return URL(string: "https://arxiv.org/abs/\(arxiv)") }
        return nil
    }
}
