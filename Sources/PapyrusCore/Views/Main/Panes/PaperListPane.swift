import SwiftUI
import AppKit
import CoreData

struct PaperListPane: View {
    @ObservedObject var viewModel: PaperListViewModel
    @ObservedObject var selectionModel: ListInteractionModel
    @ObservedObject private var appConfig = AppConfig.shared
    @Binding var listTableView: NSTableView?
    @State private var isExternalDropTargeted = false
    let showToast: (String) -> Void
    let importPDFs: ([URL]) -> Void
    let openOnlineURL: (Paper) -> URL?
    let openPDF: (NSManagedObjectID?) -> Void
    let cycleReadingStatus: (Paper) -> Void
    let editMetadata: (Paper) -> Void
    let deletePapers: ([Paper]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.filters.hasActiveFilters || !viewModel.filters.searchText.isEmpty {
                PaperListSummaryBar(
                    resultCount: viewModel.filteredPapers.count,
                    totalCount: viewModel.totalPaperCount,
                    searchText: viewModel.filters.searchText,
                    activeFilters: activeFilterSummary,
                    onClearSearch: { viewModel.filters.searchText = "" },
                    onClearFilters: { viewModel.filters.clearFilters() }
                )
            }

            ZStack {
                NativePaperListView(
                    rows: displayedPapers,
                    contentRevision: viewModel.filteredPapersRevision,
                    pinnedCount: pinnedPapers.count,
                    searchText: viewModel.filters.searchText,
                    resolvedColorScheme: appConfig.resolvedColorScheme,
                    selectionModel: selectionModel,
                    tableViewRef: $listTableView,
                    isExternalDropTargeted: $isExternalDropTargeted,
                    showToast: showToast,
                    importPDFs: importPDFs,
                    openOnlineURL: openOnlineURL,
                    openPDF: openPDF,
                    cycleReadingStatus: cycleReadingStatus,
                    editMetadata: editMetadata,
                    deletePapers: deletePapers,
                    viewModel: viewModel,
                    resolvePaper: resolvePaper(for:)
                )
                .overlay {
                    if viewModel.totalPaperCount == 0 {
                        listEmptyState(
                            icon: "tray",
                            title: "Library is empty",
                            subtitle: "Drag PDF files here, or click + to import"
                        )
                    } else if viewModel.filteredPapers.isEmpty {
                        listEmptyState(
                            icon: "magnifyingglass",
                            title: "No results",
                            subtitle: "Try adjusting filters or search terms"
                        )
                    }
                }
                .overlay {
                    if isExternalDropTargeted {
                        externalPDFDropOverlay
                    }
                }
            }
        }
    }

    private var pinnedPapers: [Paper] {
        viewModel.filteredPapers.filter(\.isPinned)
    }

    private var regularPapers: [Paper] {
        viewModel.filteredPapers.filter { !$0.isPinned }
    }

    private var displayedPapers: [Paper] {
        pinnedPapers + regularPapers
    }

    private func resolvePaper(for objectID: NSManagedObjectID) -> Paper? {
        if let paper = viewModel.filteredPapers.first(where: { $0.objectID == objectID }) {
            return paper
        }
        return viewModel.papers.first(where: { $0.objectID == objectID })
    }

    private var activeFilterSummary: [String] {
        var items: [String] = []
        if !viewModel.filters.filterReadingStatus.isEmpty {
            items.append("\(viewModel.filters.filterReadingStatus.count) status")
        }
        if !viewModel.filters.filterTags.isEmpty {
            items.append("\(viewModel.filters.filterTags.count) tag")
        }
        if !viewModel.filters.filterYear.isEmpty {
            items.append("\(viewModel.filters.filterYear.count) year")
        }
        if !viewModel.filters.filterVenueAbbr.isEmpty {
            items.append("\(viewModel.filters.filterVenueAbbr.count) venue")
        }
        if !viewModel.filters.filterPublicationType.isEmpty {
            items.append("\(viewModel.filters.filterPublicationType.count) type")
        }
        if !viewModel.filters.filterRankKeywords.isEmpty {
            items.append("rank filters")
        }
        if viewModel.filters.filterMinRating > 0 {
            items.append("rating ≥ \(viewModel.filters.filterMinRating)")
        }
        return items
    }

    private var externalPDFDropOverlay: some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(Color.accentColor.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))
            )
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text("Drop PDF to import")
                        .font(AppTypography.titleSmall)
                        .foregroundStyle(.primary)
                    Text("Imports only external PDF files")
                        .font(AppTypography.label)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    @ViewBuilder
    private func listEmptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(AppTypography.titleSmall)
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(AppTypography.label)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .allowsHitTesting(false)
    }
}

// MARK: - NativePaperListView

private struct NativePaperListView: NSViewRepresentable {
    let rows: [Paper]
    let contentRevision: Int
    let pinnedCount: Int
    let searchText: String
    let resolvedColorScheme: ColorScheme
    @ObservedObject var selectionModel: ListInteractionModel
    @Binding var tableViewRef: NSTableView?
    @Binding var isExternalDropTargeted: Bool
    let showToast: (String) -> Void
    let importPDFs: ([URL]) -> Void
    let openOnlineURL: (Paper) -> URL?
    let openPDF: (NSManagedObjectID?) -> Void
    let cycleReadingStatus: (Paper) -> Void
    let editMetadata: (Paper) -> Void
    let deletePapers: ([Paper]) -> Void
    let viewModel: PaperListViewModel
    let resolvePaper: (NSManagedObjectID) -> Paper?

    static func estimatedRowHeight() -> CGFloat {
        height(for: nil)
    }

    static func height(for paper: Paper?) -> CGFloat {
        let scale = AppStyleConfig.fontScale
        let titleLineHeight = 13.0 * scale * 1.22
        let labelHeight = 12.0 * scale * 1.18
        let stackSpacing = ListRowLayoutMetrics.stackSpacing * 2
        let verticalPadding = ListRowLayoutMetrics.verticalPadding * 2
        return ceil(titleLineHeight + labelHeight * 2 + stackSpacing + verticalPadding)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let components = NativeListSupport.makeScrollView(
            columnIdentifier: "paper",
            rowHeight: NativePaperListView.estimatedRowHeight(),
            coordinator: context.coordinator
        ) { tableView in
            tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
            tableView.setDraggingSourceOperationMask(.move, forLocal: true)
            tableView.registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL])
        }
        let scrollView = components.scrollView
        let tableView = components.tableView
        tableView.doubleAction = #selector(Coordinator.tableViewDoubleClicked(_:))
        tableView.modifierSelectionHandler = { [weak coordinator = context.coordinator] tableView, event in
            coordinator?.handleModifierSelection(in: tableView, event: event) ?? false
        }
        tableView.contextMenuProvider = { [weak coordinator = context.coordinator] tableView, event in
            coordinator?.makeContextMenu(in: tableView, event: event)
        }
        tableView.externalDropHoverDidChange = { [weak coordinator = context.coordinator] isTargeted in
            coordinator?.setExternalDropTargeted(isTargeted)
        }

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.startRefaultTimer()

        DispatchQueue.main.async {
            tableViewRef = tableView
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.scheduleTableUpdate()
        if let tv = context.coordinator.tableView, tableViewRef !== tv {
            DispatchQueue.main.async {
                if tableViewRef !== tv {
                    tableViewRef = tv
                }
            }
        }
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativePaperListView
        weak var tableView: NativeListTableView?
        var isSyncingSelection = false
        var lastRenderedContentRevision: Int?
        var lastRenderedColorScheme: ColorScheme?
        var draggingRowIndexes: IndexSet = []
        var selectionAnchorRow: Int?
        var lastInteractedPaperID: NSManagedObjectID?
        var contextMenuPaperIDs: [NSManagedObjectID] = []
        var contextMenuPrimaryPaperID: NSManagedObjectID?
        private var hasScheduledTableUpdate = false
        private var refaultTimer: Timer?

        init(parent: NativePaperListView) {
            self.parent = parent
        }

        deinit {
            refaultTimer?.invalidate()
        }

        func startRefaultTimer() {
            guard refaultTimer == nil else { return }
            refaultTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refaultInvisiblePapers()
                }
            }
        }

        private func refaultInvisiblePapers() {
            let visibleRange = tableView?.rows(in: tableView?.visibleRect ?? .zero)
            let visibleRows: IndexSet = visibleRange.map { range in
                IndexSet(integersIn: Int(range.location)..<Int(range.location + range.length))
            } ?? IndexSet()
            let visibleIDs = Set(visibleRows.compactMap { row -> NSManagedObjectID? in
                guard row < parent.rows.count else { return nil }
                return parent.rows[row].objectID
            })
            parent.viewModel.refaultInvisiblePapers(visibleObjectIDs: visibleIDs)
        }

        func scheduleTableUpdate() {
            guard !hasScheduledTableUpdate else { return }
            hasScheduledTableUpdate = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.hasScheduledTableUpdate = false
                self.reloadIfNeeded()
                self.syncSelectionFromBinding()
            }
        }

        func reloadIfNeeded() {
            let contentChanged = parent.contentRevision != lastRenderedContentRevision
            let colorSchemeChanged = parent.resolvedColorScheme != lastRenderedColorScheme
            guard contentChanged || colorSchemeChanged else { return }
            tableView?.reloadData()
            lastRenderedContentRevision = parent.contentRevision
            lastRenderedColorScheme = parent.resolvedColorScheme
        }

        func syncSelectionFromBinding() {
            guard let tableView else { return }
            let selectedIndexes = IndexSet(
                parent.rows.indices.filter { parent.selectionModel.selectedIDs.contains(parent.rows[$0].objectID) }
            )
            guard tableView.selectedRowIndexes != selectedIndexes else { return }
            isSyncingSelection = true
            tableView.selectRowIndexes(selectedIndexes, byExtendingSelection: false)
            isSyncingSelection = false
            updateSelectionAnchor(using: selectedIndexes)
        }

        @objc
        func tableViewDoubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < parent.rows.count else { return }
            parent.openPDF(parent.rows[row].objectID)
        }

        // MARK: NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.rows.count
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < parent.rows.count else { return nil }
            guard let filePath = parent.rows[row].filePath else { return nil }
            return PaperDragDrop.makeDragPasteboardItem(filePath: filePath)
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forRowIndexes rowIndexes: IndexSet
        ) {
            draggingRowIndexes = rowIndexes
            setExternalDropTargeted(false)
            LibraryDragSessionState.shared.isInternalDragActive = true
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            draggingRowIndexes = []
            setExternalDropTargeted(false)
            LibraryDragSessionState.shared.isInternalDragActive = false
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            if let source = info.draggingSource as? NSTableView, source === tableView {
                tableView.draggingDestinationFeedbackStyle = .regular
                setExternalDropTargeted(false)
                let pinnedCount = parent.pinnedCount
                guard pinnedCount > 1 else { return [] }
                let allPinned = draggingRowIndexes.allSatisfy { $0 < pinnedCount }
                guard allPinned, dropOperation == .above, row <= pinnedCount else { return [] }
                return .move
            }

            let urls = droppedPDFURLs(from: info)
            tableView.draggingDestinationFeedbackStyle = .none
            if !urls.isEmpty {
                tableView.setDropRow(-1, dropOperation: .on)
            }
            setExternalDropTargeted(!urls.isEmpty)
            return urls.isEmpty ? [] : .copy
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            defer { setExternalDropTargeted(false) }
            if !draggingRowIndexes.isEmpty {
                let pinnedCount = parent.pinnedCount
                guard draggingRowIndexes.allSatisfy({ $0 < pinnedCount }), row <= pinnedCount else { return false }
                let visiblePinned = Array(parent.rows.prefix(pinnedCount))
                parent.viewModel.reorderPinned(from: draggingRowIndexes, to: row, visiblePinned: visiblePinned)
                return true
            }

            let urls = droppedPDFURLs(from: info)
            guard !urls.isEmpty else { return false }
            DispatchQueue.main.async { [self] in
                parent.importPDFs(urls)
            }
            return true
        }

        // MARK: NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.rows.count else { return nil }
            let paper = parent.rows[row]
            let id = NSUserInterfaceItemIdentifier("PaperListCell")
            var cellView = tableView.makeView(withIdentifier: id, owner: nil) as? NativeListCellView
            if cellView == nil {
                cellView = NativeListCellView()
                cellView?.identifier = id
            }
            cellView?.configure(
                rootView: AnyView(
                    PaperRowView(paper: paper, searchText: parent.searchText)
                        .id(paper.objectID)
                ),
                showsBottomDivider: row < parent.rows.count - 1
            )
            return cellView
        }

        func tableView(
            _ tableView: NSTableView,
            selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet
        ) -> IndexSet {
            guard let event = NSApp.currentEvent else { return proposedSelectionIndexes }
            return resolvedSelectionIndexes(for: tableView, event: event)?.selection ?? proposedSelectionIndexes
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard parent.rows.indices.contains(row) else {
                return NativePaperListView.estimatedRowHeight()
            }
            return NativePaperListView.height(for: parent.rows[row])
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let tableView else { return }
            let orderedIDs = tableView.selectedRowIndexes
                    .filter { $0 < parent.rows.count }
                    .map { parent.rows[$0].objectID }
            parent.selectionModel.applyExternalSelection(
                orderedIDs: orderedIDs,
                preferredPrimaryID: lastInteractedPaperID,
                trigger: NativeListSupport.currentSelectionTrigger(default: .mouse)
            )
            updateSelectionAnchor(using: tableView.selectedRowIndexes)
        }

        // MARK: Context menu helpers (called from cells)

        func showToast(_ message: String) { parent.showToast(message) }
        func openOnlineURL(for paper: Paper) -> URL? { parent.openOnlineURL(paper) }
        func openPDF(id: NSManagedObjectID?) { parent.openPDF(id) }
        func cycleReadingStatus(for paper: Paper) { parent.cycleReadingStatus(paper) }
        func editMetadata(for paper: Paper) { parent.editMetadata(paper) }
        func deletePapers(_ papers: [Paper]) { parent.deletePapers(papers) }
        func reextractSeed(for paper: Paper) { parent.viewModel.reextractMetadataSeed(paper) }

        func makeContextMenu(in tableView: NativeListTableView, event: NSEvent) -> NSMenu? {
            let clickedRow = resolvedClickedRow(in: tableView, event: event)
            guard clickedRow >= 0, clickedRow < parent.rows.count else { return nil }

            if !tableView.selectedRowIndexes.contains(clickedRow) {
                isSyncingSelection = true
                tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
                isSyncingSelection = false
                tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification, object: tableView))
            }

            let selectedRows = tableView.selectedRowIndexes.filter { $0 < parent.rows.count }
            let selectedPapers = selectedRows.map { parent.rows[$0] }
            guard !selectedPapers.isEmpty else { return nil }

            contextMenuPaperIDs = selectedPapers.map(\.objectID)
            contextMenuPrimaryPaperID = parent.rows[clickedRow].objectID

            let primaryPaper = parent.rows[clickedRow]
            let context = PaperContextMenuContext(
                papers: selectedPapers,
                primaryPaper: primaryPaper
            )
            let menu = NSMenu()

            if !context.isMultiSelection {
                menu.addItem(menuItem("Open PDF", action: #selector(contextOpenPDF), enabled: context.canOpenPrimaryPDF))
                menu.addItem(menuItem("Quick Look", action: #selector(contextQuickLook), enabled: context.canOpenPrimaryPDF))
                if openOnlineURL(for: context.primaryPaper) != nil {
                    menu.addItem(menuItem("Open Online", action: #selector(contextOpenOnline)))
                }
            }

            if context.hasLocalFiles {
                menu.addItem(menuItem("Show in Finder", action: #selector(contextShowInFinder)))
            }

            if context.canCopyPDFs {
                menu.addItem(menuItem(context.copyPDFTitle, action: #selector(contextCopyPDFs)))
            }

            if !context.isMultiSelection || context.hasLocalFiles {
                menu.addItem(.separator())
            }

            menu.addItem(menuItem(context.copyTitlesTitle, action: #selector(contextCopyTitles)))
            menu.addItem(menuItem("Copy BibTeX", action: #selector(contextCopyBibTeX)))

            menu.addItem(.separator())
            menu.addItem(menuItem("Refresh Metadata", action: #selector(contextRefreshMetadata)))
            if !context.isMultiSelection {
                menu.addItem(menuItem("Re-extract From PDF", action: #selector(contextReextractSeed)))
            }

            if !context.isMultiSelection {
                menu.addItem(menuItem("Edit Metadata", action: #selector(contextEditMetadata)))
            }

            menu.addItem(.separator())
            if !context.isMultiSelection {
                menu.addItem(menuItem(context.readingStatusTitle, action: #selector(contextCycleReadingStatus)))
            }

            menu.addItem(menuItem(context.pinTitle, action: #selector(contextTogglePin)))
            menu.addItem(menuItem(context.flagTitle, action: #selector(contextToggleFlag)))
            menu.addItem(makeRatingMenu())
            menu.addItem(.separator())
            menu.addItem(menuItem(context.deleteTitle, action: #selector(contextDeleteSelected)))
            return menu
        }

        private func menuItem(_ title: String, action: Selector, enabled: Bool = true) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            return item
        }

        private func makeRatingMenu() -> NSMenuItem {
            let parentItem = NSMenuItem(title: "Rating", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: "Rating")

            let clear = NSMenuItem(title: "Clear Rating", action: #selector(contextClearRating), keyEquivalent: "")
            clear.target = self
            submenu.addItem(clear)
            submenu.addItem(.separator())

            for rating in 1...5 {
                let item = NSMenuItem(title: String(repeating: "★", count: rating), action: #selector(contextSetRating(_:)), keyEquivalent: "")
                item.target = self
                item.tag = rating
                submenu.addItem(item)
            }

            parentItem.submenu = submenu
            return parentItem
        }

        private func contextMenuPapers() -> [Paper] {
            contextMenuPaperIDs.compactMap { resolvePaper(for: $0) }
        }

        private func contextPrimaryPaper() -> Paper? {
            if let id = contextMenuPrimaryPaperID, let paper = resolvePaper(for: id) {
                return paper
            }
            return contextMenuPapers().first
        }

        @objc private func contextOpenPDF() {
            guard let paper = contextPrimaryPaper() else { return }
            openPDF(id: paper.objectID)
        }

        @objc private func contextOpenOnline() {
            guard let paper = contextPrimaryPaper(),
                  let url = openOnlineURL(for: paper) else { return }
            NSWorkspace.shared.open(url)
        }

        @objc private func contextQuickLook() {
            guard let paper = contextPrimaryPaper() else { return }
            QuickLookHelper.shared.toggle(for: paper)
        }

        @objc private func contextShowInFinder() {
            PaperContextMenuSupport.showInFinder(contextMenuPapers())
        }

        @objc private func contextCopyPDFs() {
            PaperContextMenuSupport.copyPDFs(contextMenuPapers(), showToast: showToast)
        }

        @objc private func contextCycleReadingStatus() {
            guard let paper = contextPrimaryPaper() else { return }
            cycleReadingStatus(for: paper)
        }

        @objc private func contextEditMetadata() {
            guard let paper = contextPrimaryPaper() else { return }
            editMetadata(for: paper)
        }

        @objc private func contextRefreshMetadata() {
            let papers = contextMenuPapers()
            guard !papers.isEmpty else { return }
            parent.viewModel.refreshMetadata(papers)
        }

        @objc private func contextReextractSeed() {
            guard let paper = contextPrimaryPaper() else { return }
            reextractSeed(for: paper)
        }

        @objc private func contextTogglePin() {
            let papers = contextMenuPapers()
            guard !papers.isEmpty else { return }
            let allPinned = papers.allSatisfy(\.isPinned)
            parent.viewModel.setPinned(!allPinned, for: papers)
        }

        @objc private func contextToggleFlag() {
            let papers = contextMenuPapers()
            guard !papers.isEmpty else { return }
            let allFlagged = papers.allSatisfy(\.isFlagged)
            parent.viewModel.setFlag(!allFlagged, for: papers)
        }

        @objc private func contextClearRating() {
            applyRatingToContextMenuSelection(0)
        }

        @objc private func contextSetRating(_ sender: NSMenuItem) {
            applyRatingToContextMenuSelection(sender.tag)
        }

        private func applyRatingToContextMenuSelection(_ rating: Int) {
            let papers = contextMenuPapers()
            guard !papers.isEmpty else { return }
            parent.viewModel.applyBatchEdit(
                to: papers,
                status: nil,
                rating: rating,
                tagsToAdd: [],
                tagsToRemove: [],
                publicationType: nil
            )
        }

        @objc private func contextCopyTitles() {
            PaperContextMenuSupport.copyTitles(contextMenuPapers(), showToast: showToast)
        }

        @objc private func contextCopyBibTeX() {
            let papers = contextMenuPapers()
            guard !papers.isEmpty else { return }
            let bibtex = parent.viewModel.exportBibTeX(papers: papers)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(bibtex, forType: .string)
            showToast("BibTeX copied")
        }

        @objc private func contextDeleteSelected() {
            let papers = contextMenuPapers()
            guard !papers.isEmpty else { return }
            deletePapers(papers)
        }

        func handleModifierSelection(in tableView: NativeListTableView, event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection([.command, .shift])
            guard modifiers.contains(.command) || modifiers.contains(.shift) else { return false }
            guard event.type == .leftMouseDown else { return false }
            guard let selection = resolvedSelectionIndexes(for: tableView, event: event) else { return false }

            isSyncingSelection = true
            tableView.selectRowIndexes(selection.selection, byExtendingSelection: false)
            isSyncingSelection = false
            tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification, object: tableView))
            return true
        }

        private func resolvedClickedRow(in tableView: NSTableView, event: NSEvent) -> Int {
            NativeListSupport.resolvedClickedRow(in: tableView, event: event)
        }

        private func resolvedSelectionIndexes(
            for tableView: NSTableView,
            event: NSEvent
        ) -> (selection: IndexSet, interactedID: NSManagedObjectID)? {
            let result = NativeListSupport.resolvedSelectionIndexes(
                in: tableView,
                event: event,
                itemCount: parent.rows.count,
                selectionAnchorRow: &selectionAnchorRow,
                primarySelectionID: parent.selectionModel.primarySelectionID,
                itemIDAtRow: { parent.rows[$0].objectID }
            )
            lastInteractedPaperID = result?.interactedID
            return result
        }

        private func updateSelectionAnchor(using selectedIndexes: IndexSet) {
            NativeListSupport.updateSelectionAnchor(
                using: selectedIndexes,
                selectionAnchorRow: &selectionAnchorRow,
                primarySelectionID: parent.selectionModel.primarySelectionID,
                itemCount: parent.rows.count,
                itemIDAtRow: { parent.rows[$0].objectID }
            )
        }

        private func droppedPDFURLs(from info: NSDraggingInfo) -> [URL] {
            PaperDragDrop.droppedPDFURLs(from: info.draggingPasteboard)
        }

        private func resolvePaper(for objectID: NSManagedObjectID) -> Paper? {
            parent.resolvePaper(objectID)
        }

        func setExternalDropTargeted(_ isTargeted: Bool) {
            guard parent.isExternalDropTargeted != isTargeted else { return }
            parent.isExternalDropTargeted = isTargeted
        }
    }
}
