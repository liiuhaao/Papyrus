import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreData

struct PaperGridPane: View {
    @ObservedObject var viewModel: PaperListViewModel
    @ObservedObject var appConfig: AppConfig
    @ObservedObject var selectionModel: GalleryInteractionModel
    @State private var isExternalDropTargeted = false
    let importPDFs: ([URL]) -> Void
    let showToast: (String) -> Void
    let openOnlineURL: (Paper) -> URL?
    let openPDF: (NSManagedObjectID?) -> Void
    let showInFinder: ([Paper]) -> Void
    let refreshMetadata: ([Paper]) -> Void
    let reorderPinned: (IndexSet, Int, [Paper]) -> Void
    let cycleReadingStatus: (Paper) -> Void
    let setPinned: (Bool, [Paper]) -> Void
    let setFlag: (Bool, [Paper]) -> Void
    let setRating: (Int, [Paper]) -> Void
    let copyBibTeX: ([Paper]) -> Void
    let editMetadata: (Paper) -> Void
    let deletePapers: ([Paper]) -> Void

    private let gridSpacing: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.filters.hasActiveFilters || !viewModel.filters.searchText.isEmpty {
                PaperListSummaryBar(
                    resultCount: viewModel.filteredPapers.count,
                    totalCount: viewModel.papers.count,
                    searchText: viewModel.filters.searchText,
                    activeFilters: activeFilterSummary,
                    onClearSearch: { viewModel.filters.searchText = "" },
                    onClearFilters: { viewModel.filters.clearFilters() }
                )
            }

            ZStack {
                if viewModel.papers.isEmpty {
                    dropImportEmptyState(
                        icon: "tray",
                        title: "Library is empty",
                        subtitle: "Drag PDF files here, or click + to import"
                    )
                } else if viewModel.filteredPapers.isEmpty {
                    dropImportEmptyState(
                        icon: "magnifyingglass",
                        title: "No results",
                        subtitle: "Try adjusting filters or search terms"
                    )
                } else {
                    NativePaperGridView(
                        papers: viewModel.filteredPapers,
                        pinnedCount: viewModel.filteredPapers.filter(\.isPinned).count,
                        searchText: viewModel.filters.searchText,
                        minCardWidth: appConfig.galleryCardSize.minCardWidth,
                        gridSpacing: gridSpacing,
                        selectionModel: selectionModel,
                        isExternalDropTargeted: $isExternalDropTargeted,
                        importPDFs: importPDFs,
                        showToast: showToast,
                        openOnlineURL: openOnlineURL,
                        openPDF: openPDF,
                        showInFinder: showInFinder,
                        refreshMetadata: refreshMetadata,
                        reorderPinned: reorderPinned,
                        cycleReadingStatus: cycleReadingStatus,
                        setPinned: setPinned,
                        setFlag: setFlag,
                        setRating: setRating,
                        copyBibTeX: copyBibTeX,
                        editMetadata: editMetadata,
                        deletePapers: deletePapers
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

    private func cardContent(for paper: Paper) -> some View {
        PaperGridCard(
            paper: paper,
            workflowStatus: paper.workflowStatus,
            isSelected: selectionModel.selectedIDs.contains(paper.objectID),
            searchText: viewModel.filters.searchText,
            showToast: showToast,
            openOnlineURL: openOnlineURL,
            openPDF: openPDF,
            showInFinder: showInFinder,
            refreshMetadata: refreshMetadata,
            cycleReadingStatus: cycleReadingStatus,
            setPinned: setPinned,
            setFlag: setFlag,
            setRating: setRating,
            copyBibTeX: copyBibTeX,
            editMetadata: editMetadata,
            deletePapers: deletePapers,
            visiblePapers: viewModel.filteredPapers,
            selectionModel: selectionModel
        )
    }

    @ViewBuilder
    private func gridEmptyState(icon: String, title: String, subtitle: String) -> some View {
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
    }

    private func dropImportEmptyState(icon: String, title: String, subtitle: String) -> some View {
        gridEmptyState(icon: icon, title: title, subtitle: subtitle)
            .onDrop(of: [UTType.pdf, UTType.fileURL], isTargeted: $isExternalDropTargeted, perform: handleExternalDrop)
    }

    private func handleExternalDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { tempURL, _ in
                    guard let tempURL else { return }
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + ".pdf")
                    do {
                        try FileManager.default.copyItem(at: tempURL, to: dest)
                        DispatchQueue.main.async {
                            importPDFs([dest])
                        }
                    } catch {
                        print("Copy error: \(error)")
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var url: URL?
                    if let nsurl = item as? NSURL {
                        url = nsurl as URL
                    } else if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    }
                    if let url, url.pathExtension.lowercased() == "pdf" {
                        DispatchQueue.main.async {
                            importPDFs([url])
                        }
                    }
                }
            }
        }
        return true
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
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text("Drop PDF to import")
                        .font(AppTypography.titleSmall)
                        .foregroundStyle(.primary)
                    Text("External files only")
                        .font(AppTypography.label)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

private struct NativePaperGridView: NSViewRepresentable {
    let papers: [Paper]
    let pinnedCount: Int
    let searchText: String
    let minCardWidth: CGFloat
    let gridSpacing: CGFloat
    @ObservedObject var selectionModel: GalleryInteractionModel
    @Binding var isExternalDropTargeted: Bool
    let importPDFs: ([URL]) -> Void
    let showToast: (String) -> Void
    let openOnlineURL: (Paper) -> URL?
    let openPDF: (NSManagedObjectID?) -> Void
    let showInFinder: ([Paper]) -> Void
    let refreshMetadata: ([Paper]) -> Void
    let reorderPinned: (IndexSet, Int, [Paper]) -> Void
    let cycleReadingStatus: (Paper) -> Void
    let setPinned: (Bool, [Paper]) -> Void
    let setFlag: (Bool, [Paper]) -> Void
    let setRating: (Int, [Paper]) -> Void
    let copyBibTeX: ([Paper]) -> Void
    let editMetadata: (Paper) -> Void
    let deletePapers: ([Paper]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let layout = NSCollectionViewFlowLayout()
        layout.minimumLineSpacing = gridSpacing
        layout.minimumInteritemSpacing = gridSpacing
        layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let collectionView = NativePaperCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.register(
            NativePaperGridItem.self,
            forItemWithIdentifier: NativePaperGridItem.reuseIdentifier
        )
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.delegate = context.coordinator
        collectionView.dataSource = context.coordinator
        collectionView.onDoubleClickPaperID = { [weak coordinator = context.coordinator] paperID in
            coordinator?.openItem(with: paperID)
        }
        collectionView.externalDropHoverDidChange = { [weak coordinator = context.coordinator] isTargeted in
            coordinator?.setExternalDropTargeted(isTargeted)
        }
        scrollView.documentView = collectionView

        context.coordinator.collectionView = collectionView
        context.coordinator.scrollView = scrollView
        context.coordinator.applyLayout(width: scrollView.contentSize.width)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.selectionModel.updateCurrentPapers(papers)
        context.coordinator.applyLayout(width: scrollView.contentSize.width)
        context.coordinator.reloadDataIfNeeded()
        context.coordinator.syncSelectionFromModel()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        var parent: NativePaperGridView
        weak var collectionView: NativePaperCollectionView?
        weak var scrollView: NSScrollView?
        var isSyncingSelection = false
        var lastPrimarySelectionID: NSManagedObjectID?
        var lastRenderedPaperIDs: [NSManagedObjectID] = []
        var lastRenderedSearchText: String = ""
        var draggingIndexPaths: Set<IndexPath> = []
        var externalDragMonitor: Timer?

        init(parent: NativePaperGridView) {
            self.parent = parent
        }

        var selectionModel: GalleryInteractionModel { parent.selectionModel }

        func reloadDataIfNeeded() {
            let paperIDs = parent.papers.map(\.objectID)
            let needsReload = paperIDs != lastRenderedPaperIDs || parent.searchText != lastRenderedSearchText
            guard needsReload else { return }
            guard let collectionView else {
                lastRenderedPaperIDs = paperIDs
                lastRenderedSearchText = parent.searchText
                return
            }

            let searchChanged = parent.searchText != lastRenderedSearchText
            let canReorderInPlace = !searchChanged
                && paperIDs.count == lastRenderedPaperIDs.count
                && Set(paperIDs) == Set(lastRenderedPaperIDs)

            if canReorderInPlace {
                applyReorder(from: lastRenderedPaperIDs, to: paperIDs, in: collectionView)
            } else {
                collectionView.reloadData()
            }
            lastRenderedPaperIDs = paperIDs
            lastRenderedSearchText = parent.searchText
        }

        private func applyReorder(
            from oldIDs: [NSManagedObjectID],
            to newIDs: [NSManagedObjectID],
            in collectionView: NSCollectionView
        ) {
            guard oldIDs != newIDs else { return }

            var currentIDs = oldIDs
            collectionView.performBatchUpdates {
                for targetIndex in newIDs.indices {
                    let targetID = newIDs[targetIndex]
                    guard let currentIndex = currentIDs.firstIndex(of: targetID),
                          currentIndex != targetIndex else { continue }
                    collectionView.moveItem(
                        at: IndexPath(item: currentIndex, section: 0),
                        to: IndexPath(item: targetIndex, section: 0)
                    )
                    let movedID = currentIDs.remove(at: currentIndex)
                    currentIDs.insert(movedID, at: targetIndex)
                }
            }
        }

        func applyLayout(width: CGFloat) {
            guard let layout = collectionView?.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
            let resolvedWidth = width.isFinite ? width : 0
            let horizontalInsets = layout.sectionInset.left + layout.sectionInset.right
            let availableWidth = max(1, resolvedWidth - horizontalInsets)
            let contentWidth = max(parent.minCardWidth, availableWidth)
            let columnWidth = parent.minCardWidth
            let columns = max(1, Int(((contentWidth + parent.gridSpacing) / (columnWidth + parent.gridSpacing)).rounded(.down)))
            let totalSpacing = CGFloat(max(0, columns - 1)) * parent.gridSpacing
            let rawItemWidth = floor((contentWidth - totalSpacing) / CGFloat(columns))
            let itemWidth = max(120, rawItemWidth)
            let thumbnailHeight = max(160, itemWidth * (4.0 / 3.0))
            let detailHeight: CGFloat = {
                if parent.minCardWidth >= 330 { return 146 }
                if parent.minCardWidth >= 250 { return 122 }
                return 104
            }()
            let itemHeight = max(260, thumbnailHeight + detailHeight)
            guard itemWidth.isFinite, itemHeight.isFinite, itemWidth > 0, itemHeight > 0 else { return }
            layout.itemSize = NSSize(width: itemWidth, height: itemHeight)
            if selectionModel.gridColumnCount != columns {
                DispatchQueue.main.async { [weak selectionModel] in
                    if selectionModel?.gridColumnCount != columns {
                        selectionModel?.gridColumnCount = columns
                    }
                }
            }
        }

        func syncSelectionFromModel() {
            guard let collectionView else { return }
            let selectedIndexPaths = Set(parent.papers.enumerated().compactMap { index, paper in
                selectionModel.selectedIDs.contains(paper.objectID) ? IndexPath(item: index, section: 0) : nil
            })

            let current = collectionView.selectionIndexPaths
            guard current != selectedIndexPaths || lastPrimarySelectionID != selectionModel.primarySelectionID else { return }

            isSyncingSelection = true
            collectionView.selectionIndexPaths = selectedIndexPaths
            lastPrimarySelectionID = selectionModel.primarySelectionID
            isSyncingSelection = false
        }

        func openItem(with paperID: NSManagedObjectID) {
            guard let index = parent.papers.firstIndex(where: { $0.objectID == paperID }) else { return }
            let paper = parent.papers[index]
            let indexPath = IndexPath(item: index, section: 0)
            selectionModel.applyExternalSelection(
                orderedIDs: [paper.objectID],
                preferredPrimaryID: paper.objectID,
                trigger: .mouse
            )
            lastPrimarySelectionID = paper.objectID
            collectionView?.selectionIndexPaths = [indexPath]
            collectionView?.window?.makeFirstResponder(collectionView)
            parent.openPDF(paper.objectID)
        }

        func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.papers.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            let item = collectionView.makeItem(
                withIdentifier: NativePaperGridItem.reuseIdentifier,
                for: indexPath
            )
            guard let gridItem = item as? NativePaperGridItem else { return item }
            let paper = parent.papers[indexPath.item]
            gridItem.configure(
                paper: paper,
                selectionModel: selectionModel,
                searchText: parent.searchText,
                showToast: parent.showToast,
                openOnlineURL: parent.openOnlineURL,
                openPDF: parent.openPDF,
                showInFinder: parent.showInFinder,
                refreshMetadata: parent.refreshMetadata,
                cycleReadingStatus: parent.cycleReadingStatus,
                setPinned: parent.setPinned,
                setFlag: parent.setFlag,
                setRating: parent.setRating,
                copyBibTeX: parent.copyBibTeX,
                editMetadata: parent.editMetadata,
                deletePapers: parent.deletePapers,
                visiblePapers: parent.papers
            )
            return gridItem
        }

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard indexPath.item < parent.papers.count else { return nil }
            guard let filePath = parent.papers[indexPath.item].filePath else { return nil }
            return PaperDragDrop.makeDragPasteboardItem(filePath: filePath)
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forItemsAt indexPaths: Set<IndexPath>
        ) {
            draggingIndexPaths = indexPaths
            setExternalDropTargeted(false)
            LibraryDragSessionState.shared.isInternalDragActive = true
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            dragOperation operation: NSDragOperation
        ) {
            draggingIndexPaths = []
            setExternalDropTargeted(false)
            LibraryDragSessionState.shared.isInternalDragActive = false
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            validateDrop draggingInfo: NSDraggingInfo,
            proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
        ) -> NSDragOperation {
            if let source = draggingInfo.draggingSource as? NSCollectionView, source === collectionView {
                setExternalDropTargeted(false)
                let pinnedCount = parent.pinnedCount
                guard pinnedCount > 1 else { return [] }

                let draggingIndexes = Set(draggingIndexPaths.map(\.item))
                let allPinned = !draggingIndexes.isEmpty && draggingIndexes.allSatisfy { $0 < pinnedCount }
                guard allPinned else { return [] }

                proposedDropOperation.pointee = .before
                let destination = min(proposedDropIndexPath.pointee.item, pinnedCount)
                guard destination <= pinnedCount else { return [] }
                proposedDropIndexPath.pointee = NSIndexPath(forItem: destination, inSection: 0)
                return .move
            }

            let urls = droppedPDFURLs(from: draggingInfo)
            if !urls.isEmpty {
                proposedDropOperation.pointee = .on
            }
            setExternalDropTargeted(!urls.isEmpty)
            return urls.isEmpty ? [] : .copy
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            acceptDrop draggingInfo: NSDraggingInfo,
            indexPath: IndexPath,
            dropOperation: NSCollectionView.DropOperation
        ) -> Bool {
            defer { setExternalDropTargeted(false) }
            if let source = draggingInfo.draggingSource as? NSCollectionView, source === collectionView {
                let draggingIndexes = IndexSet(draggingIndexPaths.map(\.item))
                let pinnedCount = parent.pinnedCount
                guard !draggingIndexes.isEmpty else { return false }
                guard draggingIndexes.allSatisfy({ $0 < pinnedCount }), indexPath.item <= pinnedCount else { return false }
                let visiblePinned = Array(parent.papers.prefix(pinnedCount))
                parent.reorderPinned(draggingIndexes, indexPath.item, visiblePinned)
                return true
            }

            let urls = droppedPDFURLs(from: draggingInfo)
            guard !urls.isEmpty else { return false }
            DispatchQueue.main.async { [parent] in
                parent.importPDFs(urls)
            }
            return true
        }

        func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
            guard let indexPath = indexPaths.first, indexPaths.count == 1 else { return indexPaths }
            guard parent.papers.indices.contains(indexPath.item) else { return indexPaths }
            guard let event = NSApp.currentEvent else { return indexPaths }

            let modifiers = event.modifierFlags.intersection([.command, .shift])
            guard modifiers.contains(.shift) else { return indexPaths }

            let paper = parent.papers[indexPath.item]
            selectionModel.toggleSelection(for: paper, modifiers: modifiers)
            syncSelectionFromModel()
            lastPrimarySelectionID = selectionModel.primarySelectionID
            collectionView.window?.makeFirstResponder(collectionView)
            return []
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            handleSelectionChange(in: collectionView, trigger: .mouse)
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            handleSelectionChange(in: collectionView, trigger: .mouse)
        }

        private func handleSelectionChange(in collectionView: NSCollectionView, trigger: SelectionTrigger) {
            guard !isSyncingSelection else { return }
            let selected = collectionView.selectionIndexPaths
                .sorted { $0.item < $1.item }
                .compactMap { path in parent.papers.indices.contains(path.item) ? parent.papers[path.item] : nil }
            let resolvedTrigger = currentSelectionTrigger(default: trigger)
            let preferredPrimaryID = (collectionView as? NativePaperCollectionView)?.lastInteractedPaperID
            selectionModel.applyExternalSelection(
                orderedIDs: selected.map(\.objectID),
                preferredPrimaryID: preferredPrimaryID,
                trigger: resolvedTrigger
            )
            lastPrimarySelectionID = selectionModel.primarySelectionID
            collectionView.window?.makeFirstResponder(collectionView)
        }

        private func currentSelectionTrigger(default trigger: SelectionTrigger) -> SelectionTrigger {
            guard let event = NSApp.currentEvent else { return trigger }
            if event.type == .keyDown { return .keyboard }
            if event.type == .leftMouseDown || event.type == .leftMouseUp { return .mouse }
            return trigger
        }

        private func droppedPDFURLs(from info: NSDraggingInfo) -> [URL] {
            PaperDragDrop.droppedPDFURLs(from: info.draggingPasteboard)
        }

        func setExternalDropTargeted(_ isTargeted: Bool) {
            guard parent.isExternalDropTargeted != isTargeted else { return }
            parent.isExternalDropTargeted = isTargeted
            if isTargeted {
                startExternalDragMonitor()
            } else {
                stopExternalDragMonitor()
            }
        }

        private func startExternalDragMonitor() {
            guard externalDragMonitor == nil else { return }
            externalDragMonitor = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshExternalDropHoverState()
                }
            }
            RunLoop.main.add(externalDragMonitor!, forMode: .common)
        }

        private func stopExternalDragMonitor() {
            externalDragMonitor?.invalidate()
            externalDragMonitor = nil
        }

        private func refreshExternalDropHoverState() {
            guard parent.isExternalDropTargeted else {
                stopExternalDragMonitor()
                return
            }
            guard let collectionView, let window = collectionView.window else {
                setExternalDropTargeted(false)
                return
            }

            let location = collectionView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if !collectionView.bounds.contains(location) {
                setExternalDropTargeted(false)
            }
        }

        deinit {
            externalDragMonitor?.invalidate()
        }
    }
}

private final class NativePaperCollectionView: NSCollectionView {
    var onDoubleClickPaperID: ((NSManagedObjectID) -> Void)?
    var lastInteractedPaperID: NSManagedObjectID?
    var externalDropHoverDidChange: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: point),
           let item = item(at: indexPath) as? NativePaperGridItem,
           let paperID = item.representedObject as? NSManagedObjectID {
            lastInteractedPaperID = paperID
        } else {
            lastInteractedPaperID = nil
        }
        super.mouseDown(with: event)
        guard event.clickCount >= 2 else { return }
        guard let indexPath = indexPathForItem(at: point) else { return }
        guard let item = item(at: indexPath) as? NativePaperGridItem,
              let paperID = item.representedObject as? NSManagedObjectID else { return }
        onDoubleClickPaperID?(paperID)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        externalDropHoverDidChange?(false)
        super.draggingExited(sender)
    }
}

private final class NativePaperGridItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("NativePaperGridItem")

    private struct Configuration {
        let paper: Paper
        let searchText: String
        let showToast: (String) -> Void
        let openOnlineURL: (Paper) -> URL?
        let openPDF: (NSManagedObjectID?) -> Void
        let showInFinder: ([Paper]) -> Void
        let refreshMetadata: ([Paper]) -> Void
        let cycleReadingStatus: (Paper) -> Void
        let setPinned: (Bool, [Paper]) -> Void
        let setFlag: (Bool, [Paper]) -> Void
        let setRating: (Int, [Paper]) -> Void
        let copyBibTeX: ([Paper]) -> Void
        let editMetadata: (Paper) -> Void
        let deletePapers: ([Paper]) -> Void
        let visiblePapers: [Paper]
        let selectionModel: GalleryInteractionModel
    }

    private var hostingView: NSHostingView<AnyView>?
    private var configuration: Configuration?
    private var renderedPaperID: NSManagedObjectID?

    override var isSelected: Bool {
        didSet { render() }
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    func configure(
        paper: Paper,
        selectionModel: GalleryInteractionModel,
        searchText: String,
        showToast: @escaping (String) -> Void,
        openOnlineURL: @escaping (Paper) -> URL?,
        openPDF: @escaping (NSManagedObjectID?) -> Void,
        showInFinder: @escaping ([Paper]) -> Void,
        refreshMetadata: @escaping ([Paper]) -> Void,
        cycleReadingStatus: @escaping (Paper) -> Void,
        setPinned: @escaping (Bool, [Paper]) -> Void,
        setFlag: @escaping (Bool, [Paper]) -> Void,
        setRating: @escaping (Int, [Paper]) -> Void,
        copyBibTeX: @escaping ([Paper]) -> Void,
        editMetadata: @escaping (Paper) -> Void,
        deletePapers: @escaping ([Paper]) -> Void,
        visiblePapers: [Paper]
    ) {
        representedObject = paper.objectID
        configuration = Configuration(
            paper: paper,
            searchText: searchText,
            showToast: showToast,
            openOnlineURL: openOnlineURL,
            openPDF: openPDF,
            showInFinder: showInFinder,
            refreshMetadata: refreshMetadata,
            cycleReadingStatus: cycleReadingStatus,
            setPinned: setPinned,
            setFlag: setFlag,
            setRating: setRating,
            copyBibTeX: copyBibTeX,
            editMetadata: editMetadata,
            deletePapers: deletePapers,
            visiblePapers: visiblePapers,
            selectionModel: selectionModel
        )
        if renderedPaperID != paper.objectID {
            resetHostingView()
            renderedPaperID = paper.objectID
        }
        render()
    }

    private func render() {
        guard let configuration else { return }
        resetHostingView()
        let root = AnyView(
            PaperGridCard(
                paper: configuration.paper,
                workflowStatus: configuration.paper.workflowStatus,
                isSelected: isSelected,
                searchText: configuration.searchText,
                showToast: configuration.showToast,
                openOnlineURL: configuration.openOnlineURL,
                openPDF: configuration.openPDF,
                showInFinder: configuration.showInFinder,
                refreshMetadata: configuration.refreshMetadata,
                cycleReadingStatus: configuration.cycleReadingStatus,
                setPinned: configuration.setPinned,
                setFlag: configuration.setFlag,
                setRating: configuration.setRating,
                copyBibTeX: configuration.copyBibTeX,
                editMetadata: configuration.editMetadata,
                deletePapers: configuration.deletePapers,
                visiblePapers: configuration.visiblePapers,
                selectionModel: configuration.selectionModel
            )
            .id(configuration.paper.objectID)
        )
        let hostingView = NSHostingView(rootView: root)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.hostingView = hostingView
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configuration = nil
        representedObject = nil
        renderedPaperID = nil
        resetHostingView()
    }

    private func resetHostingView() {
        if let hostingView = hostingView {
            hostingView.rootView = AnyView(EmptyView())
            hostingView.removeFromSuperview()
        }
        hostingView = nil
    }
}

private struct PaperGridCard: View {
    @ObservedObject var paper: Paper
    let workflowStatus: PaperWorkflowStatus?
    let isSelected: Bool
    let searchText: String
    let showToast: (String) -> Void
    let openOnlineURL: (Paper) -> URL?
    let openPDF: (NSManagedObjectID?) -> Void
    let showInFinder: ([Paper]) -> Void
    let refreshMetadata: ([Paper]) -> Void
    let cycleReadingStatus: (Paper) -> Void
    let setPinned: (Bool, [Paper]) -> Void
    let setFlag: (Bool, [Paper]) -> Void
    let setRating: (Int, [Paper]) -> Void
    let copyBibTeX: ([Paper]) -> Void
    let editMetadata: (Paper) -> Void
    let deletePapers: ([Paper]) -> Void
    let visiblePapers: [Paper]
    @ObservedObject var selectionModel: GalleryInteractionModel
    @ObservedObject private var appConfig = AppConfig.shared
    @State private var isHovered = false

    private var venueLine: String? {
        guard appConfig.showVenueInList else { return nil }
        let fullVenue = (paper.venue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let venueText = (paper.venueObject?.abbreviation ?? VenueFormatter.unifiedDisplayName(fullVenue))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !venueText.isEmpty else {
            return paper.year > 0 ? "\(paper.year)" : nil
        }
        if paper.year > 0 {
            return "\(paper.year)  ·  \(venueText)"
        }
        return venueText
    }

    private var searchQuery: PaperQueryService.SearchQuery {
        PaperQueryService.parseSearch(searchText)
    }

    private var titleText: AttributedString {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AttributedString(paper.displayTitle)
        }
        let terms = PaperQueryService.highlightTerms(for: .title, query: searchQuery)
        return highlightedText(paper.displayTitle, terms: terms)
    }

    private var authorsText: AttributedString {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AttributedString(paper.formattedAuthors)
        }
        let terms = PaperQueryService.highlightTerms(for: .authors, query: searchQuery)
        return highlightedText(paper.formattedAuthors, terms: terms)
    }

    private var hasNotesSearchMatch: Bool {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let notes = paper.notes ?? ""
        guard !notes.isEmpty else { return false }
        let terms = PaperQueryService.highlightTerms(for: .notes, query: searchQuery)
        return terms.contains { term in
            notes.localizedCaseInsensitiveContains(term)
        }
    }

    private var metaText: AttributedString? {
        let venueValue: AttributedString? = {
            guard let venueLine else { return nil }
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return AttributedString(venueLine)
            }
            let terms = PaperQueryService.highlightTerms(for: .venue, query: searchQuery)
                + PaperQueryService.highlightTerms(for: .year, query: searchQuery)
            return highlightedText(venueLine, terms: terms)
        }()

        return venueValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PaperThumbnailView(filePath: paper.filePath)
                .overlay(alignment: .bottomTrailing) {
                    hoverActions
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 6) {
                        if paper.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(8)
                                .background(Color.black.opacity(0.05), in: Circle())
                        }
                    }
                    .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    if appConfig.showFlagInList && paper.isFlagged {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(8)
                            .background(Color.black.opacity(0.05), in: Circle())
                            .padding(6)
                    }
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(titleText)
                    .font(AppTypography.bodyStrong)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(authorsText)
                    .font(AppTypography.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let metaText {
                        Text(metaText)
                            .font(AppTypography.label)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                    if hasNotesSearchMatch {
                        Label("Notes Hit", systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 10 * AppStyleConfig.fontScale, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .help("Matched in notes")
                    }
                    if appConfig.showRatingInList && paper.rating > 0 {
                        Text("★ \(paper.rating)")
                            .font(AppTypography.labelStrong)
                            .foregroundStyle(AppColors.star)
                    }
                    if let workflowStatus, workflowStatus.hasVisiblePhases {
                        WorkflowStatusStrip(status: workflowStatus)
                    } else if appConfig.showStatusInList {
                        Image(systemName: AppStatusStyle.icon(for: paper.currentReadingStatus))
                            .font(AppTypography.labelStrong)
                            .foregroundStyle(AppStatusStyle.tint(for: paper.currentReadingStatus))
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.12),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(0), radius: 0, y: 0)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: SelectedCardBoundsKey.self,
                        value: isSelected ? geo.frame(in: .named("gridScroll")) : nil
                    )
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            PaperContextMenuContent(
                context: PaperContextMenuSupport.resolvedContext(
                    clickedPaper: paper,
                    visiblePapers: visiblePapers,
                    selectedIDs: selectionModel.selectedIDs
                ),
                handlers: contextMenuHandlers
            )
        }
    }

    private var contextMenuHandlers: PaperContextMenuHandlers {
        PaperContextMenuHandlers(
            openOnlineURL: openOnlineURL,
            openPDF: { openPDF($0.objectID) },
            quickLook: { QuickLookHelper.shared.toggle(for: $0) },
            showInFinder: showInFinder,
            copyPDFs: { papers in
                PaperContextMenuSupport.copyPDFs(papers, showToast: showToast)
            },
            cycleReadingStatus: cycleReadingStatus,
            editMetadata: editMetadata,
            copyTitles: { papers in
                PaperContextMenuSupport.copyTitles(papers, showToast: showToast)
            },
            copyBibTeX: copyBibTeX,
            refreshMetadata: refreshMetadata,
            setPinned: setPinned,
            setFlag: setFlag,
            setRating: setRating,
            deletePapers: deletePapers
        )
    }

    private var hoverActions: some View {
        HStack(spacing: 6) {
            Button {
                openPDF(paper.objectID)
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.plain)
            .help("Open PDF")

            Button {
                QuickLookHelper.shared.toggle(for: paper)
            } label: {
                Image(systemName: "eye")
            }
            .buttonStyle(.plain)
            .help("Quick Look")

            Button {
                setPinned(!paper.isPinned, [paper])
            } label: {
                Image(systemName: paper.isPinned ? "pin.slash" : "pin")
            }
            .buttonStyle(.plain)
            .help(paper.isPinned ? "Unpin" : "Pin")

            Button {
                setFlag(!paper.isFlagged, [paper])
            } label: {
                Image(systemName: paper.isFlagged ? "flag.slash" : "flag")
            }
            .buttonStyle(.plain)
            .help(paper.isFlagged ? "Remove Flag" : "Flag")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.12), in: Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .padding(8)
        .opacity(isHovered ? 1 : 0)
    }

}

private struct PaperThumbnailView: View {
    let filePath: String?
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.03))
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .task(id: thumbnailRequestKey(for: geo.size)) {
                await loadThumbnail(for: geo.size)
            }
            .onDisappear {
                image = nil
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
    }

    @MainActor
    private func loadThumbnail(for size: CGSize) async {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        guard let filePath, !filePath.isEmpty else { image = nil; return }
        let url = URL(fileURLWithPath: filePath)
        let target = CGSize(width: size.width, height: size.height)
        if let cached = PDFThumbnailCache.shared.cachedThumbnail(for: url, size: target) {
            image = cached
            return
        }
        image = nil
        let rendered = await PDFThumbnailCache.shared.thumbnail(for: url, size: target)
        guard !Task.isCancelled else { return }
        if filePath == self.filePath {
            image = rendered
        }
    }

    private func thumbnailRequestKey(for size: CGSize) -> String {
        let bucket = Int((size.width / 8).rounded(.down))
        return "\(filePath ?? "")|\(bucket)"
    }
}

private struct SelectedCardBoundsKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private enum GridDisplayItem: Identifiable {
    case paper(Paper)
    case placeholder(UUID)

    var id: String {
        switch self {
        case .paper(let paper):
            return "paper-\(paper.objectID.uriRepresentation().lastPathComponent)"
        case .placeholder(let id):
            return "placeholder-\(id.uuidString)"
        }
    }
}

private struct PinnedCardFramesKey: PreferenceKey {
    static var defaultValue: [NSManagedObjectID: CGRect] = [:]
    static func reduce(value: inout [NSManagedObjectID: CGRect], nextValue: () -> [NSManagedObjectID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct PinnedDropDelegate: DropDelegate {
    @Binding var draggingPinnedID: NSManagedObjectID?
    @Binding var dragTargetIndex: Int?
    @Binding var pinnedCardFrames: [NSManagedObjectID: CGRect]
    let pinnedPapers: [Paper]
    let gridSpacing: CGFloat
    let onReorder: (NSManagedObjectID, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingPinnedID != nil
    }

    func dropEntered(info: DropInfo) {
        updateTarget(location: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateTarget(location: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        dragTargetIndex = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingID = draggingPinnedID else { return false }
        let destination = resolveDestinationIndex(location: info.location)
        DispatchQueue.main.async {
            onReorder(draggingID, destination)
            dragTargetIndex = nil
            draggingPinnedID = nil
        }
        return true
    }

    private func updateTarget(location: CGPoint) {
        let destination = resolveDestinationIndex(location: location)
        dragTargetIndex = destination
    }

    private func resolveDestinationIndex(location: CGPoint) -> Int {
        let orderedIDs = pinnedPapers
            .map(\.objectID)
            .filter { $0 != draggingPinnedID }
        guard !orderedIDs.isEmpty else { return 0 }

        let indexedFrames: [(index: Int, frame: CGRect)] = orderedIDs.enumerated().compactMap { idx, id in
            pinnedCardFrames[id].map { (idx, $0) }
        }
        guard !indexedFrames.isEmpty else { return orderedIDs.count }

        let sortedFrames = indexedFrames.sorted { $0.index < $1.index }

        // Group frames into rows based on vertical spacing.
        var rows: [(start: Int, end: Int, minY: CGFloat, maxY: CGFloat, frames: [(index: Int, frame: CGRect)])] = []
        let rowThreshold = max(8, gridSpacing * 0.5)
        for item in sortedFrames {
            if var last = rows.last, item.frame.minY <= last.maxY + rowThreshold {
                last.end = item.index
                last.maxY = max(last.maxY, item.frame.maxY)
                last.minY = min(last.minY, item.frame.minY)
                last.frames.append(item)
                rows[rows.count - 1] = last
            } else {
                rows.append((start: item.index, end: item.index, minY: item.frame.minY, maxY: item.frame.maxY, frames: [item]))
            }
        }

        if location.y < rows[0].minY - rowThreshold {
            return 0
        }
        if let last = rows.last, location.y > last.maxY + rowThreshold {
            return orderedIDs.count
        }

        for row in rows {
            if location.y >= row.minY - rowThreshold && location.y <= row.maxY + rowThreshold {
                let sortedRow = row.frames.sorted { $0.frame.minX < $1.frame.minX }
                if let first = sortedRow.first, location.x < first.frame.midX {
                    return row.start
                }
                for (offset, item) in sortedRow.enumerated() {
                    if location.x < item.frame.midX {
                        return row.start + offset
                    }
                }
                return row.end + 1
            }
        }

        // Fallback: append.
        return orderedIDs.count
    }
}
