import AppKit
import CoreData

extension ContentView {
    // MARK: - Navigation Helpers

    var pendingDeletePapers: [Paper] {
        guard !presentationState.pendingDeletePaperIDs.isEmpty else { return [] }
        let ids = presentationState.pendingDeletePaperIDs
        return viewModel.papers.filter { ids.contains($0.objectID) }
    }

    var deleteTargetPapers: [Paper] {
        let pending = pendingDeletePapers
        return pending.isEmpty ? currentSelectedPapers : pending
    }

    func beginDelete(papers: [Paper]) {
        let targets = papers.isEmpty ? currentSelectedPapers : papers
        let ids = Set(targets.map(\.objectID))
        guard !ids.isEmpty else { return }
        presentationState.pendingDeletePaperIDs = ids
        presentationState.showingDeleteSelectedConfirm = true
    }

    func beginDeleteSelection() {
        if !selectionStore.selectedIDs.isEmpty {
            presentationState.pendingDeletePaperIDs = []
            presentationState.showingDeleteSelectedConfirm = true
        } else if let paper = currentPrimaryPaper {
            interactions.selectPaper(paper)
            presentationState.pendingDeletePaperIDs = [paper.objectID]
            presentationState.showingDeleteSelectedConfirm = true
        }
    }

    func prepareForDeletion(papers: [Paper]) {
        let ids = Set(papers.map(\.objectID))
        if ids.isEmpty {
            interactions.clearSelection()
        } else {
            switch appConfig.libraryViewMode {
            case .list:
                interactions.listSelection.selectedIDs.subtract(ids)
            case .gallery:
                interactions.gallerySelection.selectedIDs.subtract(ids)
            }
        }

        detailModel.clearSelection()
    }

    func syncSelectionToFilteredResults() {
        interactions.syncSelectionToFilteredResults(viewModel.filteredPapers)
        synchronizeSelectionState()
    }

    func syncFeedSelectionToVisibleResults() {
        guard showingFeed else { return }
        feedSelection.syncSelectionToVisibleResults(visibleFeedItems)
    }

    func reconcileFeedSelection() {
        feedSelection.reconcileSelection(validIDs: Set(visibleFeedItems.map(\.id)))
    }

    func focusListAfterSearch() {
        syncSelectionToFilteredResults()
        isSearchFocused = false
        DispatchQueue.main.async {
            focusListView()
        }
    }

    func navigateSelection(_ command: LinearNavigationCommand) {
        guard shouldHandleGlobalShortcut() else { return }
        interactions.lastSelectionTrigger = .keyboard
        activeViewInputAdapter.handleNavigation(
            command,
            interactions: interactions,
            visiblePapers: viewModel.filteredPapers
        )
        synchronizeSelectionState()
        activeViewInputAdapter.revealPrimarySelection(
            using: LibrarySelectionRevealContext(
                primarySelectionID: interactions.primarySelectionID,
                visiblePapers: viewModel.filteredPapers,
                listTableView: listTableView
            )
        )
    }

    func navigateFeedSelection(_ command: LinearNavigationCommand) {
        feedSelection.handleNavigation(command, in: visibleFeedItems)
    }

    func focusListView() {
        if appConfig.libraryViewMode == .list,
           let tableView = listTableView,
           let window = tableView.window {
            window.makeFirstResponder(tableView)
            return
        }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let tableView = window.contentView?.firstDescendant(ofType: NSTableView.self) else { return }
        window.makeFirstResponder(tableView)
    }

    var currentSelectedPapers: [Paper] {
        let selectedIDs = selectionStore.selectedIDs
        guard !selectedIDs.isEmpty else {
            guard let primaryID = selectionStore.primaryID,
                  let paper = resolvePaper(for: primaryID) else {
                return []
            }
            return [paper]
        }
        return selectedIDs.compactMap { resolvePaper(for: $0) }
    }

    var currentPrimaryPaper: Paper? {
        if let resolved = resolveCurrentPrimaryPaper() {
            return resolved
        }
        if selectionStore.primaryID == nil && selectionStore.selectedIDs.isEmpty {
            return nil
        }
        if let detailID = detailModel.currentPaperID,
           let paper = resolvePaper(for: detailID) {
            return paper
        }
        return nil
    }

    func paperForPrimaryAction(preferred paper: Paper? = nil) -> Paper? {
        paper ?? currentPrimaryPaper
    }

    func paperForPrimaryAction(preferredID: NSManagedObjectID?) -> Paper? {
        if let preferredID, let paper = resolvePaper(for: preferredID) {
            return paper
        }
        return currentPrimaryPaper
    }

    func performPrimaryPaperAction(
        preferredID: NSManagedObjectID? = nil,
        action: (Paper) -> Void
    ) {
        guard let target = paperForPrimaryAction(preferredID: preferredID) else { return }
        if let preferredID, interactions.primarySelectionID != preferredID {
            interactions.selectPaper(target)
            synchronizeSelectionState()
        }
        action(target)
    }

    func openPaperForPrimaryAction(preferred paper: Paper? = nil) {
        guard let target = paperForPrimaryAction(preferred: paper) else { return }
        viewModel.openPDF(target)
    }

    func openPaperForPrimaryAction(preferredID: NSManagedObjectID?) {
        performPrimaryPaperAction(preferredID: preferredID) { paper in
            viewModel.openPDF(paper)
        }
    }

    func quickLookForPrimaryAction(preferred paper: Paper? = nil) {
        guard let target = paperForPrimaryAction(preferred: paper) else { return }
        QuickLookHelper.shared.toggle(for: target)
    }

    func quickLookForPrimaryAction(preferredID: NSManagedObjectID?) {
        performPrimaryPaperAction(preferredID: preferredID) { paper in
            QuickLookHelper.shared.toggle(for: paper)
        }
    }

    func reconcileSelectionWithCurrentPapers() {
        interactions.reconcileSelection(with: viewModel.papers)
        synchronizeSelectionState()
    }

    func synchronizeSelectionState() {
        interactions.syncSelectionStore(
            selectionStore,
            visiblePapers: viewModel.filteredPapers,
            allPapers: viewModel.papers,
            context: viewContext
        )
        detailModel.updateSelection(id: selectionStore.primaryID)
        presentationState.handleSelectionChange(selectedCount: selectionStore.selectedCount)
    }

    private func resolveCurrentPrimaryPaper() -> Paper? {
        guard let id = selectionStore.primaryID else { return nil }
        return resolvePaper(for: id)
    }

    private func resolvePaper(for id: NSManagedObjectID) -> Paper? {
        if let visiblePaper = viewModel.filteredPapers.first(where: { $0.objectID == id }) {
            return visiblePaper
        }
        if let paper = viewModel.papers.first(where: { $0.objectID == id }) {
            return paper
        }
        return (try? viewContext.existingObject(with: id)) as? Paper
    }
}
