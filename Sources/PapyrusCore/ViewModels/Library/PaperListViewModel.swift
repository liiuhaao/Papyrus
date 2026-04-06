// PaperListViewModel.swift
// Main view model for paper management

import Foundation
import CoreData
import SwiftUI
import Combine

@MainActor
class PaperListViewModel: ObservableObject {
    @Published var papers: [Paper] = []
    var filters: LibraryFilterModel
    var taskState: LibraryTaskStateModel
    @Published private(set) var venueCounts: [(venue: String, count: Int)] = []
    @Published private(set) var yearCounts: [(year: Int, count: Int)] = []
    @Published private(set) var publicationTypeCounts: [(type: String, count: Int)] = []
    @Published private(set) var tagCounts: [(tag: String, count: Int)] = []
    @Published private(set) var rankKeywordCounts: [(keyword: String, count: Int)] = []
    @Published private(set) var flaggedCount: Int = 0
    private let viewContext: NSManagedObjectContext

    struct ImportTask: Identifiable, Equatable {
        typealias Stage = WorkflowStage

        enum Source {
            case importOperation
            case metadataRefresh
        }

        let id = UUID()
        let filename: String
        let source: Source
        var stage: Stage
    }
    
    @Published private(set) var filteredPapers: [Paper] = [] {
        didSet {
            filteredPapersRevision &+= 1
        }
    }
    @Published private(set) var filteredPapersRevision: Int = 0
    private var cancellables = Set<AnyCancellable>()
    private var notificationObservers: [NSObjectProtocol] = []

    private let maintainVenuesUseCase: MaintainVenuesUseCase
    private let libraryQueries: LibraryQueries
    private let libraryCommands: LibraryCommands
    private let reorderPinnedPapersUseCase: ReorderPinnedPapersUseCase
    private let refreshVenueRankingsUseCase: RefreshVenueRankingsUseCase
    private let openPaperPDFUseCase: OpenPaperPDFUseCase
    private let showPaperInFinderUseCase: ShowPaperInFinderUseCase
    private let exportLibraryUseCase: ExportLibraryUseCase
    private let taskScheduler = LibraryTaskScheduler(limits: [
        .importPDF: LibraryExecutionPolicy.importPDFWorkflowConcurrency,
        .refreshMetadata: LibraryExecutionPolicy.metadataRefreshWorkflowConcurrency
    ])
    private var refreshQueued = Set<NSManagedObjectID>()
    private var refreshInFlight = Set<NSManagedObjectID>()
    private var refreshTaskIDs: [NSManagedObjectID: UUID] = [:]
    private var refreshModes: [NSManagedObjectID: MetadataRefreshMode] = [:]
    private var didResumePendingImportRecovery = false

    private enum MetadataRefreshMode: Equatable {
        case full
        case fetchOnly
    }

    init(
        context: NSManagedObjectContext,
        libraryRuntime: LibraryRuntime,
        filters: LibraryFilterModel? = nil,
        taskState: LibraryTaskStateModel? = nil
    ) {
        self.viewContext = context
        self.filters = filters ?? LibraryFilterModel()
        self.taskState = taskState ?? LibraryTaskStateModel()
        let resolvedVenueMaintenanceService = VenueMaintenanceService(viewContext: context)
        self.maintainVenuesUseCase = MaintainVenuesUseCase(venueMaintenanceService: resolvedVenueMaintenanceService)
        self.libraryQueries = libraryRuntime.queries
        self.libraryCommands = libraryRuntime.commands
        self.reorderPinnedPapersUseCase = ReorderPinnedPapersUseCase(viewContext: context)
        self.refreshVenueRankingsUseCase = RefreshVenueRankingsUseCase(venueMaintenanceService: resolvedVenueMaintenanceService)
        self.openPaperPDFUseCase = OpenPaperPDFUseCase()
        self.showPaperInFinderUseCase = ShowPaperInFinderUseCase()
        self.exportLibraryUseCase = ExportLibraryUseCase()
        self.filters.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        AppConfig.shared.$rankBadgeSources
            .sink { [weak self] _ in
                self?.refreshRankKeywordCounts()
            }
            .store(in: &cancellables)
        AppConfig.shared.$customVenues
            .sink { [weak self] _ in
                self?.refreshVenueCounts()
            }
            .store(in: &cancellables)
        fetchPapers()

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .libraryWillSwitch, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resetMetadataRefreshState()
                self?.papers = []
                self?.filteredPapers = []
            }
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .libraryDidSwitch, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.resetMetadataRefreshState()
                self?.fetchPapers()
            }
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .refreshVenueRankings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshAllVenueRankings() }
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSManagedObjectContextDidSave,
            object: context,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleContextDidSave(notification)
            }
        })
        setupFilterPipeline()
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupFilterPipeline() {
        // Watch all filter/sort inputs; debounce then refetch.
        // (papers changes are handled by fetchPapers calling refetchFiltered directly.)
        let trigger = Publishers.MergeMany([
            filters.$searchText.map { _ in () }.eraseToAnyPublisher(),
            filters.$sortField.map { _ in () }.eraseToAnyPublisher(),
            filters.$sortAscending.map { _ in () }.eraseToAnyPublisher(),
            filters.$filterRankKeywords.map { _ in () }.eraseToAnyPublisher(),
            filters.$filterReadingStatus.map { _ in () }.eraseToAnyPublisher(),
            filters.$filterMinRating.map { _ in () }.eraseToAnyPublisher(),
            filters.$filterVenueAbbr.map { _ in () }.eraseToAnyPublisher(),
            filters.$filterYear.map { _ in () }.eraseToAnyPublisher(),
            filters.$filterPublicationType.map { _ in () }.eraseToAnyPublisher(),
            filters.$filterTags.map { _ in () }.eraseToAnyPublisher(),
            filters.$filterFlaggedOnly.map { _ in () }.eraseToAnyPublisher(),
        ])
        trigger
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] in self?.refetchFiltered() }
            .store(in: &cancellables)
    }

    private func handleContextDidSave(_ notification: Notification) {
        let inserted = managedObjects(for: NSInsertedObjectsKey, in: notification)
        let updated = managedObjects(for: NSUpdatedObjectsKey, in: notification)
        let deleted = managedObjects(for: NSDeletedObjectsKey, in: notification)

        let insertedOrDeletedPapers = containsManagedObjects(of: Paper.self, in: inserted.union(deleted))
        let venueStructureChanged = containsManagedObjects(of: Venue.self, in: inserted.union(deleted))
        let paperOrVenueUpdated = containsManagedObjects(of: Paper.self, in: updated)
            || containsManagedObjects(of: Venue.self, in: updated)

        guard insertedOrDeletedPapers || venueStructureChanged || paperOrVenueUpdated else { return }

        if insertedOrDeletedPapers || venueStructureChanged {
            fetchPapers()
            return
        }

        refreshFacetCaches()
        refetchFiltered()
    }

    private func managedObjects(for key: String, in notification: Notification) -> Set<NSManagedObject> {
        notification.userInfo?[key] as? Set<NSManagedObject> ?? []
    }

    private func containsManagedObjects<T: NSManagedObject>(of type: T.Type, in objects: Set<NSManagedObject>) -> Bool {
        objects.contains { $0 is T }
    }

    private var listQuery: LibraryListQuery {
        LibraryListQuery(
            searchText: filters.searchText,
            rankKeywords: filters.filterRankKeywords,
            readingStatuses: filters.filterReadingStatus,
            minRating: filters.filterMinRating,
            venueAbbreviations: filters.filterVenueAbbr,
            years: filters.filterYear,
            publicationTypes: filters.filterPublicationType,
            tags: filters.filterTags,
            flaggedOnly: filters.filterFlaggedOnly,
            sortField: filters.sortField,
            sortAscending: filters.sortAscending
        )
    }
    
    func refetchFiltered() {
        let orderedIDs = libraryQueries.filterPaperIDs(
            allPapers: papers,
            query: listQuery,
            visibleRankSourceKeys: AppConfig.shared.rankBadgeSources
        )
        let papersByID = Dictionary(uniqueKeysWithValues: papers.map { ($0.id, $0) })
        filteredPapers = orderedIDs.compactMap { papersByID[$0] }
    }

    func fetchPapers() {
        do {
            papers = try libraryQueries.fetchAllPapers()
            refreshFacetCaches()
        } catch {
            taskState.errorMessage = "Failed to fetch papers: " + error.localizedDescription
        }
        refetchFiltered()
    }

    private func refreshFacetCaches() {
        refreshVenueCounts()
        yearCounts = PaperQueryService.yearCounts(in: papers)
        publicationTypeCounts = PaperQueryService.publicationTypeCounts(in: papers)
        tagCounts = PaperQueryService.tagCounts(in: papers)
        refreshRankKeywordCounts()
        flaggedCount = papers.filter(\.isFlagged).count
    }

    private func refreshVenueCounts() {
        venueCounts = PaperQueryService.venueCounts(in: papers)
    }

    private func refreshRankKeywordCounts() {
        rankKeywordCounts = PaperQueryService.rankKeywordCounts(
            in: papers,
            visibleSourceKeys: AppConfig.shared.rankBadgeSources
        )
    }

    func resumePendingImportRecoveryIfNeeded() {
        guard !didResumePendingImportRecovery else { return }
        didResumePendingImportRecovery = true

        let requests = ImportRecoveryCoordinator.shared.consumePendingRequests()
        for request in requests {
            guard FileManager.default.fileExists(atPath: request.pdfPath) else {
                ImportRecoveryCoordinator.shared.cleanupConsumedRequest(request)
                taskState.errorMessage = ImportRecoveryError.invalidQueuedPDF.localizedDescription
                continue
            }
            runImport(.pdf(
                url: URL(fileURLWithPath: request.pdfPath),
                webpageMetadata: nil,
                recoveryRequest: request
            ))
        }
    }

    func importPDF(from url: URL, webpageMetadata: WebpageMetadata? = nil) {
        runImport(.pdf(
            url: url,
            webpageMetadata: webpageMetadata,
            recoveryRequest: nil
        ))
    }

    private enum ImportOperation {
        case pdf(
            url: URL,
            webpageMetadata: WebpageMetadata?,
            recoveryRequest: PendingImportRequest?
        )

        var displayName: String {
            switch self {
            case .pdf(let url, _, _):
                return url.lastPathComponent
            }
        }

        var initialStage: ImportTask.Stage {
            .checking
        }

        var taskKind: LibraryTaskKind {
            .importPDF
        }

        var recoveryRequest: PendingImportRequest? {
            switch self {
            case .pdf(_, _, let request):
                return request
            }
        }

        var sourcePDFURL: URL? {
            switch self {
            case .pdf(let url, _, _):
                return url
            }
        }

        var webpageMetadata: WebpageMetadata? {
            switch self {
            case .pdf(_, let webpageMetadata, _):
                return webpageMetadata
            }
        }

        var errorFallback: String {
            PaperImportError.importFailed.localizedDescription
        }
    }

    private func runImport(_ operation: ImportOperation) {
        let taskID = taskState.addImportTask(
            filename: operation.displayName,
            source: .importOperation,
            stage: operation.initialStage
        )

        func updateStage(_ stage: ImportTask.Stage) {
            taskState.updateImportTask(id: taskID, stage: stage)
        }

        Task {
            switch await prepareImportExecution(
                request: operation.recoveryRequest,
                sourcePDFURL: operation.sourcePDFURL,
                updateStage: updateStage
            ) {
            case .proceed:
                break
            case .handoff:
                taskState.removeImportTask(id: taskID)
                return
            case .failed(let message):
                await failImportTask(
                    id: taskID,
                    message: message,
                    updateStage: updateStage
                )
                return
            }

            do {
                switch operation {
                case .pdf(let url, let webpageMetadata, _):
                    let detail = try await libraryCommands.queueImportPaper(
                        ImportPaperCommand(
                            pdfURL: url,
                            webpageMetadata: webpageMetadata
                        ),
                        onStageChange: updateStage
                    )

                    fetchPapers()
                    updateStage(.queued)
                    if let queuedPaper = resolvePaper(id: detail.id) {
                        enqueueMetadataRefresh(
                            [(objectID: queuedPaper.objectID, displayName: queuedPaper.displayTitle)],
                            mode: .full,
                            showsTaskOverlay: false
                        )
                    }
                }
                cleanupRecoveryArtifacts(for: operation.recoveryRequest)
                taskState.removeImportTask(id: taskID)
            } catch {
                switch await recoverImportExecution(
                    error: error,
                    request: operation.recoveryRequest,
                    sourcePDFURL: operation.sourcePDFURL,
                    updateStage: updateStage
                ) {
                case .handoff:
                    return
                case .failed:
                    let message = (error as? LocalizedError)?.errorDescription ?? operation.errorFallback
                    await failImportTask(
                        id: taskID,
                        message: message,
                        updateStage: updateStage
                    )
                }
            }
        }
    }

    private func failImportTask(
        id: UUID,
        message: String,
        updateStage: @escaping (ImportTask.Stage) -> Void
    ) async {
        updateStage(.failed(message))
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        taskState.removeImportTask(id: id)
    }

    private enum ImportPreparationOutcome {
        case proceed
        case handoff
        case failed(String)
    }

    private enum ImportRecoveryOutcome {
        case handoff
        case failed
    }

    private func prepareImportExecution(
        request: PendingImportRequest?,
        sourcePDFURL: URL?,
        updateStage: @escaping (ImportTask.Stage) -> Void
    ) async -> ImportPreparationOutcome {
        guard ImportRecoveryCoordinator.shared.storeFilesMissing(for: viewContext) else {
            return .proceed
        }

        updateStage(.checking)
        return await handOffImportToRecovery(
            existingRequest: request,
            sourcePDFURL: sourcePDFURL
        )
    }

    private func recoverImportExecution(
        error: Error,
        request: PendingImportRequest?,
        sourcePDFURL: URL?,
        updateStage: @escaping (ImportTask.Stage) -> Void
    ) async -> ImportRecoveryOutcome {
        guard shouldRecoverPersistentStore(for: error) else {
            cleanupRecoveryArtifacts(for: request)
            return .failed
        }

        updateStage(.checking)
        let outcome = await handOffImportToRecovery(
            existingRequest: request,
            sourcePDFURL: sourcePDFURL
        )
        switch outcome {
        case .handoff:
            return .handoff
        case .proceed, .failed:
            return .failed
        }
    }

    private func handOffImportToRecovery(
        existingRequest: PendingImportRequest?,
        sourcePDFURL: URL?
    ) async -> ImportPreparationOutcome {
        do {
            if existingRequest == nil, let sourcePDFURL {
                _ = try ImportRecoveryCoordinator.shared.enqueuePDFImport(from: sourcePDFURL)
            }
            try await ImportRecoveryCoordinator.shared.relaunchApplication()
            return .handoff
        } catch {
            return .failed("Database recovery failed: \(error.localizedDescription)")
        }
    }

    private func cleanupRecoveryArtifacts(for request: PendingImportRequest?) {
        guard let request else { return }
        ImportRecoveryCoordinator.shared.cleanupConsumedRequest(request)
    }

    private func shouldRecoverPersistentStore(for error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            let recoverableCodes: Set<Int> = [
                NSPersistentStoreOperationError,
                NSPersistentStoreOpenError,
                NSPersistentStoreIncompatibleVersionHashError,
                NSPersistentStoreTimeoutError
            ]
            if recoverableCodes.contains(nsError.code) {
                return true
            }
        }

        let message = (error as? LocalizedError)?.errorDescription ?? nsError.localizedDescription
        let lower = message.lowercased()
        return lower.contains("persistent store")
            || lower.contains("sqlite")
            || lower.contains("no such file")
            || lower.contains("couldn’t be opened")
            || lower.contains("could not be opened")
    }

    func deletePaper(_ paper: Paper) {
        papers.removeAll { $0.objectID == paper.objectID }

        do {
            try libraryCommands.deletePaper(id: paper.id)
            fetchPapers()
        } catch {
            taskState.errorMessage = "Failed to delete: " + error.localizedDescription
        }
    }
    
    func deletePapers(_ papers: [Paper]) {
        self.papers.removeAll { candidate in
            papers.contains(where: { $0.objectID == candidate.objectID })
        }
        do {
            try libraryCommands.deletePapers(ids: papers.map(\.id))
            fetchPapers()
        } catch {
            taskState.errorMessage = "Failed to delete: " + error.localizedDescription
        }
    }

    /// Delete all papers - completely resets the library
    func deleteAllPapers() {
        do {
            try libraryCommands.deleteAllPapers()
            fetchPapers()
        } catch {
            taskState.errorMessage = "Failed to delete all: " + error.localizedDescription
        }
    }
    
    func refreshMetadata(_ paper: Paper) {
        refreshMetadata([paper])
    }

    func refreshMetadata(_ papers: [Paper]) {
        guard !papers.isEmpty else { return }
        enqueueMetadataRefresh(
            papers.map { (objectID: $0.objectID, displayName: $0.displayTitle) },
            mode: .full,
            showsTaskOverlay: false
        )
    }

    func reextractMetadataSeed(_ paper: Paper) {
        Task {
            do {
                _ = try await libraryCommands.reextractMetadataSeed(id: paper.id)
                fetchPapers()
            } catch {
                taskState.errorMessage = "Failed to re-extract from PDF: " + error.localizedDescription
            }
        }
    }

    private func enqueueMetadataRefresh(
        _ jobs: [(objectID: NSManagedObjectID, displayName: String)],
        mode: MetadataRefreshMode,
        showsTaskOverlay: Bool
    ) {
        guard !jobs.isEmpty else { return }
        var enqueuedAny = false

        for job in jobs {
            let objectID = job.objectID
            guard !refreshQueued.contains(objectID),
                  !refreshInFlight.contains(objectID) else { continue }

            if showsTaskOverlay {
                let taskID = taskState.addImportTask(
                    filename: job.displayName,
                    source: .metadataRefresh,
                    stage: .queued
                )
                refreshTaskIDs[objectID] = taskID
            }
            refreshQueued.insert(objectID)
            refreshModes[objectID] = mode
            applyQueuedWorkflowStatus(for: objectID, mode: mode)
            enqueuedAny = true

            Task {
                await taskScheduler.run(kind: .refreshMetadata) { [self] in
                    await executeRefreshTask(for: objectID)
                }
            }
        }

        if enqueuedAny {
            publishPaperStateChange()
        }
        try? viewContext.save()
    }

    private func executeRefreshTask(for objectID: NSManagedObjectID) async {
        refreshQueued.remove(objectID)
        refreshInFlight.insert(objectID)
        publishPaperStateChange()

        let taskID = refreshTaskIDs[objectID]
        let mode = refreshModes[objectID] ?? .full
        if let taskID {
            taskState.updateImportTask(id: taskID, stage: mode == .full ? .extracting : .fetching)
        }

        guard let paper = resolvePaper(for: objectID) else {
            finishRefreshTask(for: objectID, taskID: taskID)
            return
        }

        func updateStage(_ stage: ImportTask.Stage) {
            publishPaperStateChange()
            guard let taskID else { return }
            taskState.updateImportTask(id: taskID, stage: stage)
        }

        switch mode {
        case .full:
            _ = try? await libraryCommands.refreshMetadata(
                id: paper.id,
                onStageChange: updateStage
            )
        case .fetchOnly:
            _ = try? await libraryCommands.fetchMetadata(
                id: paper.id,
                forceVenueRefresh: false,
                onStageChange: updateStage
            )
        }
        finishRefreshTask(for: objectID, taskID: taskID)
    }

    private func finishRefreshTask(
        for objectID: NSManagedObjectID,
        taskID: UUID?
    ) {
        if let taskID {
            taskState.removeImportTask(id: taskID)
        }
        refreshTaskIDs.removeValue(forKey: objectID)
        refreshModes.removeValue(forKey: objectID)
        refreshInFlight.remove(objectID)
        fetchPapers()
    }

    private func publishPaperStateChange() {
        refetchFiltered()
    }

    private func enqueueImportedMetadataRefresh(_ receipt: PaperImportService.ImportReceipt) {
        guard receipt.shouldEnrich else { return }
        let displayName = resolvePaper(for: receipt.objectID)?.displayTitle ?? "Metadata"
        enqueueMetadataRefresh(
            [(objectID: receipt.objectID, displayName: displayName)],
            mode: .fetchOnly,
            showsTaskOverlay: false
        )
    }

    private func applyQueuedWorkflowStatus(for objectID: NSManagedObjectID, mode: MetadataRefreshMode) {
        guard let paper = resolvePaper(for: objectID) else { return }
        switch mode {
        case .full, .fetchOnly:
            paper.workflowStatus = PaperWorkflowStatus(fetch: .queued)
        }
        try? viewContext.save()
    }

    private func resolvePaper(for objectID: NSManagedObjectID) -> Paper? {
        if let inMemory = papers.first(where: { $0.objectID == objectID }) {
            return inMemory
        }
        return (try? viewContext.existingObject(with: objectID)) as? Paper
    }

    private func resolvePaper(id: UUID) -> Paper? {
        if let inMemory = papers.first(where: { $0.id == id }) {
            return inMemory
        }

        let request: NSFetchRequest<Paper> = Paper.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }

    private func resetMetadataRefreshState() {
        for taskID in refreshTaskIDs.values {
            taskState.removeImportTask(id: taskID)
        }
        refreshQueued.removeAll()
        refreshInFlight.removeAll()
        refreshTaskIDs.removeAll()
        refreshModes.removeAll()
    }

    func showInFinder(_ paper: Paper) {
        showPaperInFinderUseCase.execute(paper)
    }

    func openPDF(_ paper: Paper) {
        openPaperPDFUseCase.execute(paper)
    }

    // MARK: - Export

    func exportBibTeX(papers: [Paper]? = nil) -> String {
        exportLibraryUseCase.exportBibTeX(papers ?? self.papers)
    }

    func exportCSV(papers: [Paper]? = nil) -> String {
        exportLibraryUseCase.exportCSV(papers ?? self.papers)
    }

    // MARK: - Venue

    /// Find or create a Venue object for a paper, populating rank data from services.
    func findOrCreateVenue(for paper: Paper) {
        maintainVenuesUseCase.findOrCreateVenue(for: paper)
    }

    /// Bulk-refresh rankings for all known Venue objects.
    /// Call this when EasyScholar data has been updated (e.g. from Settings).
    func refreshAllVenueRankings() {
        refreshVenueRankingsUseCase.execute { [weak self] in
            self?.fetchPapers()
        }
    }

    func requestEditMetadata(for paper: Paper) {
        taskState.pendingMetadataEditPaperID = paper.objectID
    }

    func setFlag(_ flagged: Bool, for papers: [Paper]) {
        do {
            try libraryCommands.updatePapers(
                papers.map { UpdatePaperCommand(id: $0.id, flagged: flagged) }
            )
            fetchPapers()
        } catch {
            taskState.errorMessage = "Failed to update flag: " + error.localizedDescription
        }
    }

    func setPinned(_ pinned: Bool, for papers: [Paper]) {
        do {
            try libraryCommands.updatePapers(
                papers.map { UpdatePaperCommand(id: $0.id, pinned: pinned) }
            )
            fetchPapers()
        } catch {
            taskState.errorMessage = "Failed to update pin: " + error.localizedDescription
        }
    }

    func reorderPinned(from source: IndexSet, to destination: Int, visiblePinned: [Paper]) {
        do {
            try reorderPinnedPapersUseCase.execute(
                from: source,
                to: destination,
                visiblePinned: visiblePinned,
                allPapers: self.papers
            )
            refreshFilteredPinnedOrder()
        } catch {
            taskState.errorMessage = "Failed to reorder pins: " + error.localizedDescription
        }
    }

    private func refreshFilteredPinnedOrder() {
        guard !filteredPapers.isEmpty else { return }
        let pinned = filteredPapers
            .filter(\.isPinned)
            .sorted { $0.pinOrder < $1.pinOrder }
        let nonPinned = filteredPapers.filter { !$0.isPinned }
        filteredPapers = pinned + nonPinned
    }
    // MARK: - Batch Edit

    func applyBatchEdit(
        to papers: [Paper],
        status: Paper.ReadingStatus?,
        rating: Int,                   // -1 = no change, 0 = clear, 1-5 = set
        tagsToAdd: Set<String>,
        tagsToRemove: Set<String>,
        publicationType: String?
    ) {
        do {
            try libraryCommands.updatePapers(
                papers.map { paper in
                    UpdatePaperCommand(
                        id: paper.id,
                        readingStatus: status,
                        rating: rating >= 0 ? rating : nil,
                        tagsToAdd: tagsToAdd,
                        tagsToRemove: tagsToRemove,
                        publicationType: publicationType
                    )
                }
            )
            fetchPapers()
        } catch {
            taskState.errorMessage = "Batch edit failed: " + error.localizedDescription
        }
    }
}
