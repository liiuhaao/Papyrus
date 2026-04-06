import AppKit
import CoreData
import Combine

@MainActor
protocol LibrarySelectionModeling: ObservableObject {
    var selectedIDs: Set<NSManagedObjectID> { get set }
    var primarySelectionID: NSManagedObjectID? { get set }
    var lastSelectionTrigger: SelectionTrigger { get set }

    func selectedPaper(in papers: [Paper]) -> Paper?
    func selectedPapers(in papers: [Paper]) -> [Paper]
    func selectPaper(_ paper: Paper?)
    func applyExternalSelection(
        orderedIDs: [NSManagedObjectID],
        preferredPrimaryID: NSManagedObjectID?,
        trigger: SelectionTrigger
    )
    func clearSelection()
    func syncSelectionToFilteredResults(_ papers: [Paper])
    func reconcileSelection(validIDs: Set<NSManagedObjectID>)
}

@MainActor
final class ListInteractionModel: ObservableObject, LibrarySelectionModeling {
    @Published var selectedIDs: Set<NSManagedObjectID> = []
    @Published var primarySelectionID: NSManagedObjectID?
    @Published var lastSelectionTrigger: SelectionTrigger = .programmatic

    func selectedPaper(in papers: [Paper]) -> Paper? {
        guard selectedIDs.count == 1 else { return nil }
        guard let selectedID = primarySelectionID ?? selectedIDs.first else { return nil }
        return papers.first { $0.objectID == selectedID }
    }

    func selectedPapers(in papers: [Paper]) -> [Paper] {
        papers.filter { selectedIDs.contains($0.objectID) }
    }

    func selectPaper(_ paper: Paper?) {
        let nextSelectedIDs: Set<NSManagedObjectID>
        let nextPrimarySelectionID: NSManagedObjectID?
        if let paper {
            nextSelectedIDs = [paper.objectID]
            nextPrimarySelectionID = paper.objectID
        } else {
            nextSelectedIDs = []
            nextPrimarySelectionID = nil
        }
        if selectedIDs != nextSelectedIDs {
            selectedIDs = nextSelectedIDs
        }
        if primarySelectionID != nextPrimarySelectionID {
            primarySelectionID = nextPrimarySelectionID
        }
        if lastSelectionTrigger != .programmatic {
            lastSelectionTrigger = .programmatic
        }
    }

    func applyExternalSelection(
        orderedIDs: [NSManagedObjectID],
        preferredPrimaryID: NSManagedObjectID?,
        trigger: SelectionTrigger
    ) {
        let nextSelectedIDs = Set(orderedIDs)
        let nextPrimarySelectionID = resolvedPrimarySelectionID(
            orderedIDs: orderedIDs,
            preferredPrimaryID: preferredPrimaryID,
            currentPrimaryID: primarySelectionID,
            fallbackPrimaryID: nil
        )
        if selectedIDs != nextSelectedIDs {
            selectedIDs = nextSelectedIDs
        }
        if primarySelectionID != nextPrimarySelectionID {
            primarySelectionID = nextPrimarySelectionID
        }
        if lastSelectionTrigger != trigger {
            lastSelectionTrigger = trigger
        }
    }

    func clearSelection() {
        if !selectedIDs.isEmpty {
            selectedIDs = []
        }
        if primarySelectionID != nil {
            primarySelectionID = nil
        }
        if lastSelectionTrigger != .programmatic {
            lastSelectionTrigger = .programmatic
        }
    }

    func handleExternalSelectionChange(in papers: [Paper]) {
        applyExternalSelection(
            orderedIDs: orderedSelectedIDs(in: papers, selectedIDs: selectedIDs, id: \.objectID),
            preferredPrimaryID: primarySelectionID,
            trigger: lastSelectionTrigger
        )
    }

    func handleNavigation(_ command: LinearNavigationCommand, in papers: [Paper]) {
        guard let nextIndex = nextIndex(for: command, in: papers) else { return }
        let nextPaper = papers[nextIndex]
        let nextSelectedIDs: Set<NSManagedObjectID> = [nextPaper.objectID]
        if selectedIDs != nextSelectedIDs {
            selectedIDs = nextSelectedIDs
        }
        if primarySelectionID != nextPaper.objectID {
            primarySelectionID = nextPaper.objectID
        }
        if lastSelectionTrigger != .keyboard {
            lastSelectionTrigger = .keyboard
        }
    }

    func syncSelectionToFilteredResults(_ papers: [Paper]) {
        guard !papers.isEmpty else {
            if !selectedIDs.isEmpty {
                selectedIDs = []
            }
            if primarySelectionID != nil {
                primarySelectionID = nil
            }
            return
        }

        if let selected = selectedPaper(in: papers),
           papers.contains(where: { $0.objectID == selected.objectID }) {
            return
        }

        let first = papers[0]
        let nextSelectedIDs: Set<NSManagedObjectID> = [first.objectID]
        if selectedIDs != nextSelectedIDs {
            selectedIDs = nextSelectedIDs
        }
        if primarySelectionID != first.objectID {
            primarySelectionID = first.objectID
        }
    }

    func reconcileSelection(validIDs: Set<NSManagedObjectID>) {
        let newSelection = selectedIDs.intersection(validIDs)
        if newSelection != selectedIDs {
            selectedIDs = newSelection
        }
        let nextPrimarySelectionID: NSManagedObjectID?
        if let primarySelectionID, newSelection.contains(primarySelectionID) {
            nextPrimarySelectionID = primarySelectionID
        } else {
            nextPrimarySelectionID = newSelection.first
        }
        if primarySelectionID == nextPrimarySelectionID {
            return
        }
        primarySelectionID = nextPrimarySelectionID
    }

    private func nextIndex(for command: LinearNavigationCommand, in papers: [Paper]) -> Int? {
        let currentIndex = selectedPaper(in: papers).flatMap { selected in
            papers.firstIndex(where: { $0.objectID == selected.objectID })
        }
        return nextLinearSelectionIndex(
            currentIndex: currentIndex,
            command: command,
            count: papers.count
        )
    }

}

@MainActor
final class GalleryInteractionModel: ObservableObject, LibrarySelectionModeling {
    @Published var selectedIDs: Set<NSManagedObjectID> = []
    @Published var gridColumnCount: Int = 1
    @Published var isMultiSelectActive: Bool = false
    @Published var primarySelectionID: NSManagedObjectID?
    @Published var lastSelectionTrigger: SelectionTrigger = .programmatic

    private var lastAnchorID: NSManagedObjectID?
    private var lastSelectionID: NSManagedObjectID?
    private var currentPapers: [Paper] = []

    private func setSelectedIDs(_ ids: Set<NSManagedObjectID>) {
        if selectedIDs != ids {
            selectedIDs = ids
        }
    }

    private func setPrimarySelectionID(_ id: NSManagedObjectID?) {
        if primarySelectionID != id {
            primarySelectionID = id
        }
    }

    private func setLastSelectionTrigger(_ trigger: SelectionTrigger) {
        if lastSelectionTrigger != trigger {
            lastSelectionTrigger = trigger
        }
    }

    private func setIsMultiSelectActive(_ active: Bool) {
        if isMultiSelectActive != active {
            isMultiSelectActive = active
        }
    }

    fileprivate func setGridColumnCount(_ count: Int) {
        if gridColumnCount != count {
            gridColumnCount = count
        }
    }

    func selectedPaper(in papers: [Paper]) -> Paper? {
        guard selectedIDs.count == 1, let id = selectedIDs.first else { return nil }
        return papers.first { $0.objectID == id }
    }

    func selectedPapers(in papers: [Paper]) -> [Paper] {
        papers.filter { selectedIDs.contains($0.objectID) }
    }

    func selectPaper(_ paper: Paper?) {
        if let paper {
            setSelectedIDs([paper.objectID])
            lastAnchorID = paper.objectID
            lastSelectionID = paper.objectID
            setPrimarySelectionID(paper.objectID)
        } else {
            setSelectedIDs([])
            lastAnchorID = nil
            lastSelectionID = nil
            setPrimarySelectionID(nil)
        }
        setIsMultiSelectActive(false)
        setLastSelectionTrigger(.programmatic)
    }

    func applyExternalSelection(
        orderedIDs: [NSManagedObjectID],
        preferredPrimaryID: NSManagedObjectID?,
        trigger: SelectionTrigger
    ) {
        let nextSelectedIDs = Set(orderedIDs)
        let nextPrimarySelectionID = resolvedPrimarySelectionID(
            orderedIDs: orderedIDs,
            preferredPrimaryID: preferredPrimaryID,
            currentPrimaryID: primarySelectionID,
            fallbackPrimaryID: lastSelectionID
        )
        let nextIsMultiSelectActive = orderedIDs.count > 1

        if selectedIDs != nextSelectedIDs {
            selectedIDs = nextSelectedIDs
        }
        if primarySelectionID != nextPrimarySelectionID {
            primarySelectionID = nextPrimarySelectionID
        }
        if lastSelectionTrigger != trigger {
            lastSelectionTrigger = trigger
        }
        if isMultiSelectActive != nextIsMultiSelectActive {
            isMultiSelectActive = nextIsMultiSelectActive
        }

        if let primarySelectionID {
            lastSelectionID = primarySelectionID
            if !nextIsMultiSelectActive {
                lastAnchorID = primarySelectionID
            }
        } else {
            lastSelectionID = nil
            if orderedIDs.isEmpty {
                lastAnchorID = nil
            }
        }
    }

    func clearSelection() {
        setSelectedIDs([])
        lastAnchorID = nil
        lastSelectionID = nil
        setPrimarySelectionID(nil)
        setIsMultiSelectActive(false)
        setLastSelectionTrigger(.programmatic)
    }

    func updateCurrentPapers(_ papers: [Paper]) {
        currentPapers = papers
    }

    func handleExternalSelectionChange(in papers: [Paper]) {
        updateCurrentPapers(papers)
        applyExternalSelection(
            orderedIDs: orderedSelectedIDs(in: papers, selectedIDs: selectedIDs, id: \.objectID),
            preferredPrimaryID: primarySelectionID ?? lastSelectionID,
            trigger: lastSelectionTrigger
        )
        if !isMultiSelectActive {
            collapseToSingleSelection(preferLast: true)
        }
    }

    func toggleSelection(for paper: Paper, modifiers: NSEvent.ModifierFlags) {
        if !modifiers.contains(.command) && !modifiers.contains(.shift) {
            lastAnchorID = paper.objectID
        }
        if modifiers.contains(.shift) {
            setIsMultiSelectActive(true)
            extendSelection(to: paper, addingToExistingSelection: modifiers.contains(.command))
            setPrimarySelectionID(paper.objectID)
            lastSelectionID = paper.objectID
        } else if modifiers.contains(.command) {
            setIsMultiSelectActive(true)
            if selectedIDs.contains(paper.objectID) {
                selectedIDs.remove(paper.objectID)
            } else {
                selectedIDs.insert(paper.objectID)
                setPrimarySelectionID(paper.objectID)
                lastSelectionID = paper.objectID
            }
        } else {
            setSelectedIDs([paper.objectID])
            lastSelectionID = paper.objectID
            setPrimarySelectionID(paper.objectID)
            setIsMultiSelectActive(false)
        }
    }

    func handleNavigation(_ command: LinearNavigationCommand, in papers: [Paper]) {
        let currentIndex = selectedPaper(in: papers).flatMap { selected in
            papers.firstIndex(where: { $0.objectID == selected.objectID })
        }
        guard let nextIndex = nextIndex(
            currentIndex: currentIndex,
            command: command,
            count: papers.count,
            columns: gridColumnCount
        ) else { return }
        let nextPaper = papers[nextIndex]
        setSelectedIDs([nextPaper.objectID])
        lastAnchorID = nextPaper.objectID
        lastSelectionID = nextPaper.objectID
        setPrimarySelectionID(nextPaper.objectID)
        setIsMultiSelectActive(false)
        setLastSelectionTrigger(.keyboard)
    }

    func syncSelectionToFilteredResults(_ papers: [Paper]) {
        guard !papers.isEmpty else {
            setSelectedIDs([])
            setPrimarySelectionID(nil)
            return
        }

        if let selected = selectedPaper(in: papers),
           papers.contains(where: { $0.objectID == selected.objectID }) {
            return
        }

        let first = papers[0]
        setSelectedIDs([first.objectID])
        lastAnchorID = first.objectID
        setPrimarySelectionID(first.objectID)
        lastSelectionID = first.objectID
        setIsMultiSelectActive(false)
    }

    func reconcileSelection(validIDs: Set<NSManagedObjectID>) {
        let newSelection = selectedIDs.intersection(validIDs)
        if newSelection != selectedIDs {
            selectedIDs = newSelection
        }
        if let currentPrimary = primarySelectionID {
            if !newSelection.contains(currentPrimary) {
                setPrimarySelectionID(newSelection.first)
            }
        } else {
            setPrimarySelectionID(newSelection.first)
        }
    }

    func collapseToSingleSelection(preferLast: Bool) {
        guard selectedIDs.count > 1 else {
            if selectedIDs.count == 1 {
                setPrimarySelectionID(selectedIDs.first)
                lastSelectionID = selectedIDs.first
                setIsMultiSelectActive(false)
            } else {
                setPrimarySelectionID(nil)
                setIsMultiSelectActive(false)
            }
            return
        }

        var targetID: NSManagedObjectID?
        if preferLast, let last = lastSelectionID, selectedIDs.contains(last) {
            targetID = last
        } else {
            targetID = selectedIDs.first
        }

        if let targetID {
            setSelectedIDs([targetID])
            setPrimarySelectionID(targetID)
            lastSelectionID = targetID
        } else {
            setSelectedIDs([])
            setPrimarySelectionID(nil)
        }
        setIsMultiSelectActive(false)
    }

    private func extendSelection(to paper: Paper, addingToExistingSelection: Bool) {
        let all = currentPapers
        guard let targetIndex = all.firstIndex(where: { $0.objectID == paper.objectID }) else {
            setSelectedIDs([paper.objectID])
            lastAnchorID = paper.objectID
            return
        }
        let anchorID = lastAnchorID ?? selectedIDs.first
        guard let anchorID,
              let anchorIndex = all.firstIndex(where: { $0.objectID == anchorID }) else {
            setSelectedIDs([paper.objectID])
            lastAnchorID = paper.objectID
            return
        }
        let lower = min(anchorIndex, targetIndex)
        let upper = max(anchorIndex, targetIndex)
        let rangeIDs = Set(all[lower...upper].map(\.objectID))
        setSelectedIDs(addingToExistingSelection ? selectedIDs.union(rangeIDs) : rangeIDs)
    }

    private func nextIndex(
        currentIndex: Int?,
        command: LinearNavigationCommand,
        count: Int,
        columns: Int
    ) -> Int? {
        guard count > 0 else { return nil }
        let step = max(1, columns)
        if let currentIndex {
            let col = currentIndex % step
            let row = currentIndex / step
            let lastRow = (count - 1) / step
            let rowStart = row * step
            let rowEnd = min(count - 1, rowStart + step - 1)
            switch command {
            case .up where row == 0:
                return currentIndex
            case .down where row >= lastRow:
                return currentIndex
            case .up:
                return (row - 1) * step + col
            case .down:
                let targetRow = row + 1
                let candidate = targetRow * step + col
                if candidate < count { return candidate }
                return min(count - 1, targetRow * step + step - 1)
            case .left where col == 0:
                return currentIndex
            case .right where currentIndex >= rowEnd:
                return currentIndex
            case .left:
                return max(rowStart, currentIndex - 1)
            case .right:
                return min(rowEnd, currentIndex + 1)
            case .top:
                return 0
            case .bottom:
                return count - 1
            case .pageUp:
                return max(0, currentIndex - step * 5)
            case .pageDown:
                return min(count - 1, currentIndex + step * 5)
            }
        }

        switch command {
        case .top:
            return 0
        case .bottom:
            return count - 1
        case .pageUp, .up, .left:
            return count - 1
        case .pageDown, .down, .right:
            return 0
        }
    }
}

@MainActor
final class LibraryInteractionCoordinator: ObservableObject {
    @Published var mode: LibraryViewMode = .list

    let listSelection = ListInteractionModel()
    let gallerySelection = GalleryInteractionModel()

    private var cancellables = Set<AnyCancellable>()

    init() {
        gallerySelection.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var selectedIDs: Set<NSManagedObjectID> {
        activeSelectionModel.selectedIDs
    }

    var primarySelectionID: NSManagedObjectID? {
        activeSelectionModel.primarySelectionID
    }

    var lastSelectionTrigger: SelectionTrigger {
        get { activeSelectionModel.lastSelectionTrigger }
        set { activeSelectionModel.lastSelectionTrigger = newValue }
    }

    func activeSelectedPaper(in papers: [Paper]) -> Paper? {
        activeSelectionModel.selectedPaper(in: papers)
    }

    func activeSelectedPapers(in papers: [Paper]) -> [Paper] {
        activeSelectionModel.selectedPapers(in: papers)
    }

    func clearSelection() {
        listSelection.clearSelection()
        gallerySelection.clearSelection()
    }

    func selectPaper(_ paper: Paper?) {
        activeSelectionModel.selectPaper(paper)
    }

    func syncSelectionToFilteredResults(_ papers: [Paper]) {
        activeSelectionModel.syncSelectionToFilteredResults(papers)
    }

    func reconcileSelection(with papers: [Paper]) {
        let validIDs = Set(papers.map(\.objectID))
        listSelection.reconcileSelection(validIDs: validIDs)
        gallerySelection.reconcileSelection(validIDs: validIDs)
    }

    func handleListSelectionChange(in papers: [Paper]) {
        guard mode == .list else { return }
        listSelection.handleExternalSelectionChange(in: papers)
    }

    func handleGallerySelectionChange(in papers: [Paper]) {
        guard mode == .gallery else { return }
        gallerySelection.handleExternalSelectionChange(in: papers)
    }

    func updateMode(_ mode: LibraryViewMode, visiblePapers: [Paper], selectedPaper: Paper?) {
        if self.mode != mode {
            self.mode = mode
        }
        if let selectedPaper {
            activeSelectionModel.selectPaper(selectedPaper)
        } else {
            activeSelectionModel.syncSelectionToFilteredResults(visiblePapers)
        }
    }

    func updateGridColumnCount(_ count: Int) {
        gallerySelection.setGridColumnCount(count)
    }

    func syncSelectionStore(
        _ selectionStore: SelectionStore,
        visiblePapers: [Paper],
        allPapers: [Paper],
        context: NSManagedObjectContext
    ) {
        selectionStore.sync(
            mode: mode,
            selectedIDs: selectedIDs,
            primarySelectionID: primarySelectionID,
            visiblePapers: visiblePapers,
            allPapers: allPapers,
            context: context
        )
    }

    private var activeSelectionModel: any LibrarySelectionModeling {
        switch mode {
        case .list:
            return listSelection
        case .gallery:
            return gallerySelection
        }
    }
}
