// ContentView.swift
// Main application view — 3-column: filter | list | detail

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import AppKit

package struct ContentView: View {
    @Environment(\.managedObjectContext) var viewContext
    @StateObject var viewModel: PaperListViewModel
    @ObservedObject var taskState: LibraryTaskStateModel
    @ObservedObject var feedViewModel = FeedViewModel.shared
    @StateObject var presentationState = LibraryPresentationStateModel()
    @StateObject var singleKeyMonitor = SingleKeyShortcutMonitor()
    @StateObject var interactions = LibraryInteractionCoordinator()
    @StateObject var feedSelection = FeedInteractionModel()
    @StateObject var detailModel = LibraryDetailModel()
    @StateObject var selectionStore = SelectionStore()
    @State var listTableView: NSTableView?
    @State var showingFeed = false
    @FocusState var isSearchFocused: Bool
    @ObservedObject var appConfig = AppConfig.shared

    package init() {
        let viewModel = AppContainer.shared.makePaperListViewModel()
        _viewModel = StateObject(wrappedValue: viewModel)
        _taskState = ObservedObject(wrappedValue: viewModel.taskState)
    }

    package var body: some View {
        rootView
    }

    private var rootView: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $presentationState.columnVisibility) {
                filterPane
            } detail: {
                detailPane
            }
            windowOverlayLayer
        }
    }

    private var filterPane: some View {
        FilterPanelView(
            viewModel: viewModel,
            feedViewModel: feedViewModel,
            onImport: { presentationState.showingImportDialog = true },
            onDeleteAll: { presentationState.showingDeleteAllConfirm = true },
            showingFeed: $showingFeed
        )
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
    }

    private var detailPane: some View {
        detailPaneWithOverlays
    }

    private var detailPaneWithOverlays: some View {
        detailPaneWithToolbar
            .overlay(globalShortcutLayer)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: presentationState.toastMessage)
            .fileImporter(
                isPresented: $presentationState.showingImportDialog,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true,
                onCompletion: handleFileImport
            )
            .onAppear {
                setupSingleKeyMonitor()
                interactions.updateMode(appConfig.libraryViewMode, visiblePapers: viewModel.filteredPapers, selectedPaper: currentPrimaryPaper)
                synchronizeSelectionState()
                viewModel.resumePendingImportRecoveryIfNeeded()
                Task {
                    // Brief delay to let paper fetch complete before deduplication
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    await feedViewModel.refreshIfStale(papers: viewModel.papers)
                }
                for pendingURL in BrowserImportURLDispatcher.shared.drainPendingURLs() {
                    handleIncomingURLImport(pendingURL)
                }
            }
            .onDisappear {
                singleKeyMonitor.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: .browserImportURLReceived)) { notification in
                guard let url = notification.object as? URL else { return }
                handleIncomingURLImport(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .libraryWillSwitch)) { _ in
                interactions.clearSelection()
                selectionStore.clear()
                detailModel.clearSelection()
            }
            .onReceive(NotificationCenter.default.publisher(for: .libraryDidSwitch)) { _ in
                interactions.clearSelection()
                selectionStore.clear()
                detailModel.clearSelection()
            }
            .onReceive(NotificationCenter.default.publisher(for: .executeLibraryCommand)) { notification in
                if let rawCommand = notification.userInfo?["command"] as? String,
                   let command = AppCommand(rawValue: rawCommand) {
                    _ = executeAppCommand(command, source: .notification)
                    return
                }
                guard let rawAction = notification.userInfo?["action"] as? String,
                      let action = InputAction(rawValue: rawAction) else { return }
                _ = performKeyboardAction(action, source: .notification)
            }
            .onReceive(viewModel.$papers) { _ in
                DispatchQueue.main.async {
                    reconcileSelectionWithCurrentPapers()
                }
            }
            .onReceive(feedViewModel.$feedItems) { _ in
                DispatchQueue.main.async {
                    guard showingFeed else { return }
                    reconcileFeedSelection()
                }
            }
            .onChange(of: appConfig.libraryViewMode) { _, _ in
                interactions.updateMode(
                    appConfig.libraryViewMode,
                    visiblePapers: viewModel.filteredPapers,
                    selectedPaper: currentPrimaryPaper
                )
                if appConfig.libraryViewMode != .list {
                    listTableView = nil
                }
                synchronizeSelectionState()
            }
            .onChange(of: viewModel.filters.searchText) { _, newValue in
                guard !showingFeed else { return }
                guard !newValue.isEmpty else { return }
                syncSelectionToFilteredResults()
            }
    }

    @ViewBuilder
    private var windowOverlayLayer: some View {
        VStack(spacing: 0) {
            NotificationStack(toast: presentationState.toastMessage)
                .frame(maxWidth: 380)
                .padding(.top, 18)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: presentationState.toastMessage)
    }

    private var detailPaneWithToolbar: some View {
        detailPaneCore
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: presentationState.toggleInspectorVisibility) {
                        Image(systemName: "info.circle")
                    }
                    .help(presentationState.showInspector ? "Hide Inspector" : "Show Inspector")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if showingFeed {
                        feedToolbarItems
                    } else {
                        importMenu
                        exportMenu
                        sortMenu
                        openMenu
                        viewControls
                        refreshButton
                        finderButton
                        bibTeXButton
                    }
                }
                if !showingFeed {
                    MainToolbarContent(configuration: toolbarConfiguration)
                }
            }
    }

    var visibleFeedItems: [FeedItem] {
        feedViewModel.feedItems.filter { $0.matchesSearch(viewModel.filters.searchText) }
    }

    var selectedFeedItems: [FeedItem] {
        feedSelection.selectedItems(in: visibleFeedItems)
    }

    private var detailPaneCore: some View {
        let searchBinding = Binding(
            get: { viewModel.filters.searchText },
            set: { viewModel.filters.searchText = $0 }
        )
        return libraryPane
            .searchable(
                text: searchBinding,
                placement: .toolbar,
                prompt: showingFeed
                    ? "Search title, authors, venue, abstract..."
                    : "Search title, authors, abstract, notes..."
            )
            .searchFocused($isSearchFocused)
            .onSubmit(of: .search) {
                if showingFeed {
                    syncFeedSelectionToVisibleResults()
                } else {
                    focusListAfterSearch()
                }
            }
            .inspector(isPresented: $presentationState.showInspector) {
                if showingFeed {
                    FeedDetailPane(
                        selectedItems: selectedFeedItems,
                        onStatusChange: { itemID, status in
                            Task {
                                guard let item = selectedFeedItems.first(where: { $0.id == itemID }) else { return }
                                switch status {
                                case .unread:
                                    await feedViewModel.markUnread(item)
                                case .read:
                                    await feedViewModel.markRead(item)
                                }
                            }
                        }
                    )
                        .inspectorColumnWidth(min: 340, ideal: 340, max: 500)
                } else {
                    InspectorHostView(
                        viewModel: viewModel,
                        taskState: taskState,
                        detailModel: detailModel,
                        primaryPaper: currentPrimaryPaper,
                        selectedPapers: currentSelectedPapers,
                        showBatchEdit: $presentationState.showingBatchEdit,
                        onBatchEdit: {
                            guard currentSelectedPapers.count >= 2 else { return }
                            detailModel.resetTransientState()
                            presentationState.showingBatchEdit = true
                        },
                        onRefreshSelection: {
                            viewModel.refreshMetadata(currentSelectedPapers)
                        },
                        onDeleteSelection: {
                            presentationState.showingDeleteSelectedConfirm = true
                        }
                    )
                }
            }
            .onChange(of: showingFeed) { _, _ in
                feedSelection.clearSelection()
            }
            .onReceive(feedViewModel.$feedItems) { _ in
                guard showingFeed else { return }
                DispatchQueue.main.async {
                    reconcileFeedSelection()
                }
            }
            .onChange(of: viewModel.filters.searchText) { _, _ in
                guard showingFeed else { return }
                syncFeedSelectionToVisibleResults()
            }
            .onReceive(interactions.listSelection.$selectedIDs) { _ in
                guard interactions.mode == .list else { return }
                DispatchQueue.main.async {
                    interactions.handleListSelectionChange(in: viewModel.filteredPapers)
                    synchronizeSelectionState()
                }
            }
            .onReceive(interactions.listSelection.$primarySelectionID) { _ in
                guard interactions.mode == .list else { return }
                DispatchQueue.main.async {
                    synchronizeSelectionState()
                }
            }
            .onReceive(interactions.gallerySelection.$selectedIDs) { _ in
                guard interactions.mode == .gallery else { return }
                DispatchQueue.main.async {
                    interactions.handleGallerySelectionChange(in: viewModel.filteredPapers)
                    synchronizeSelectionState()
                }
            }
            .onReceive(interactions.gallerySelection.$primarySelectionID) { _ in
                guard interactions.mode == .gallery else { return }
                DispatchQueue.main.async {
                    synchronizeSelectionState()
                }
            }
            .alert(deleteSelectedAlertTitle, isPresented: $presentationState.showingDeleteSelectedConfirm) {
                Button("Delete", role: .destructive) { confirmDeleteSelection() }
                Button("Cancel", role: .cancel) { presentationState.pendingDeletePaperIDs = [] }
            } message: {
                Text("This will permanently delete the selected papers and their PDF files. This action cannot be undone.")
            }
            .alert("Delete All Papers?", isPresented: $presentationState.showingDeleteAllConfirm) {
                Button("Delete All", role: .destructive) { confirmDeleteAll() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all papers and their PDF files. This action cannot be undone.")
            }
            .alert("Something went wrong", isPresented: errorAlertBinding) {
                Button("OK") { taskState.clearError() }
            } message: {
                Text(taskState.errorMessage ?? "")
            }
    }

    private var deleteSelectedAlertTitle: String {
        let count = deleteTargetPapers.count
        return "Delete \(count) Paper\(count == 1 ? "" : "s")?"
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { taskState.errorMessage != nil },
            set: { if !$0 { taskState.clearError() } }
        )
    }

    @ViewBuilder
    var feedToolbarItems: some View {
        let singleItem: FeedItem? = feedSelection.selectedIDs.count == 1 ? feedSelection.selectedItem(in: visibleFeedItems) : nil
        let singleURL: URL? = singleItem.flatMap { URL(string: $0.landingURL ?? "") }

        Button {
            openPrimaryFeedItemOnline()
        } label: {
            Label("Open Online", systemImage: "safari")
        }
        .disabled(singleURL == nil)
        .help("Open online")

        Button {
            Task { await feedViewModel.refresh(papers: viewModel.papers) }
        } label: {
            if feedViewModel.isFetching {
                ProgressView().controlSize(.small)
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .disabled(feedViewModel.isFetching)
        .help("Fetch new papers from subscriptions")
    }

    @ViewBuilder
    private var libraryPane: some View {
        if showingFeed {
            FeedListPane(
                feedViewModel: feedViewModel,
                selectionModel: feedSelection,
                searchText: viewModel.filters.searchText
            )
        } else if appConfig.libraryViewMode == .gallery {
            PaperGridPane(
                viewModel: viewModel,
                appConfig: appConfig,
                selectionModel: interactions.gallerySelection,
                importPDFs: { urls in
                    for url in urls {
                        viewModel.importPDF(from: url)
                    }
                },
                showToast: presentationState.showToast,
                openOnlineURL: onlineURL(for:),
                openPDF: { openPaperForPrimaryAction(preferredID: $0) },
                showInFinder: { PaperContextMenuSupport.showInFinder($0) },
                refreshMetadata: { viewModel.refreshMetadata($0) },
                reorderPinned: { source, destination, visiblePinned in
                    viewModel.reorderPinned(from: source, to: destination, visiblePinned: visiblePinned)
                },
                cycleReadingStatus: cycleReadingStatus(for:),
                setPinned: { pinned, papers in
                    viewModel.setPinned(pinned, for: papers)
                },
                setFlag: { flagged, papers in
                    viewModel.setFlag(flagged, for: papers)
                },
                setRating: { rating, papers in
                    viewModel.applyBatchEdit(
                        to: papers,
                        status: nil,
                        rating: rating,
                        tagsToAdd: [],
                        tagsToRemove: [],
                        publicationType: nil
                    )
                },
                copyBibTeX: { papers in
                    let bibtex = viewModel.exportBibTeX(papers: papers)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bibtex, forType: .string)
                    presentationState.showToast("BibTeX copied")
                },
                editMetadata: { paper in
                    viewModel.requestEditMetadata(for: paper)
                    detailModel.requestEditMetadata(for: paper)
                    presentationState.revealInspector()
                },
                deletePapers: { papers in
                    beginDelete(papers: papers)
                }
            )
        } else {
            PaperListPane(
                viewModel: viewModel,
                selectionModel: interactions.listSelection,
                listTableView: $listTableView,
                showToast: presentationState.showToast,
                importPDFs: { urls in
                    for url in urls {
                        viewModel.importPDF(from: url)
                    }
                },
                openOnlineURL: onlineURL(for:),
                openPDF: { openPaperForPrimaryAction(preferredID: $0) },
                cycleReadingStatus: cycleReadingStatus(for:),
                editMetadata: { paper in
                    viewModel.requestEditMetadata(for: paper)
                    detailModel.requestEditMetadata(for: paper)
                    presentationState.revealInspector()
                },
                deletePapers: { papers in
                    beginDelete(papers: papers)
                }
            )
        }
    }
}
