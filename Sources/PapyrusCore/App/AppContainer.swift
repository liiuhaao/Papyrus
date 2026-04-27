import CoreData
import Foundation

@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let persistenceController: PersistenceController
    let metadataProvider: MetadataProviding
    let rankProvider: RankProviding
    let venueAbbreviationProvider: VenueAbbreviationProviding
    let fileStorage: FileStorageProviding

    init(
        persistenceController: PersistenceController = .shared,
        metadataProvider: MetadataProviding = MetadataService.shared,
        rankProvider: RankProviding = JournalRankService.shared,
        venueAbbreviationProvider: VenueAbbreviationProviding = VenueAbbreviationService.shared,
        fileStorage: FileStorageProviding = PaperFileManager.shared
    ) {
        self.persistenceController = persistenceController
        self.metadataProvider = metadataProvider
        self.rankProvider = rankProvider
        self.venueAbbreviationProvider = venueAbbreviationProvider
        self.fileStorage = fileStorage
    }

    var viewContext: NSManagedObjectContext {
        persistenceController.container.viewContext
    }

    func makeLibraryRuntime() -> LibraryRuntime {
        let venueMaintenanceService = VenueMaintenanceService(
            viewContext: viewContext,
            rankProvider: rankProvider,
            venueAbbreviationProvider: venueAbbreviationProvider
        )
        let mutationService = PaperMutationService(
            viewContext: viewContext,
            venueMaintenanceService: venueMaintenanceService,
            metadataProvider: metadataProvider,
            rankProvider: rankProvider,
            venueAbbreviationProvider: venueAbbreviationProvider,
            fileStorage: fileStorage
        )
        let importService = PaperImportService(
            viewContext: viewContext,
            venueMaintenanceService: venueMaintenanceService,
            metadataProvider: metadataProvider,
            fileStorage: fileStorage
        )
        let loadLibraryPapersUseCase = LoadLibraryPapersUseCase(viewContext: viewContext)
        return LibraryRuntime(
            queries: LibraryQueries(loadLibraryPapersUseCase: loadLibraryPapersUseCase),
            commands: LibraryCommands(
                viewContext: viewContext,
                importPaperFromPDFUseCase: ImportPaperFromPDFUseCase(importService: importService),
                deletePapersUseCase: DeletePapersUseCase(mutationService: mutationService),
                refreshPaperMetadataUseCase: RefreshPaperMetadataUseCase(mutationService: mutationService),
                fetchPaperMetadataUseCase: FetchPaperMetadataUseCase(mutationService: mutationService),
                reextractPaperSeedUseCase: ReextractPaperSeedUseCase(mutationService: mutationService),
                applyMetadataCandidateUseCase: ApplyMetadataCandidateUseCase(mutationService: mutationService),
                applyBatchEditUseCase: ApplyBatchEditUseCase(mutationService: mutationService),
                setFlagStateUseCase: SetFlagStateUseCase(viewContext: viewContext),
                setPinnedStateUseCase: SetPinnedStateUseCase(viewContext: viewContext),
                loadLibraryPapersUseCase: loadLibraryPapersUseCase
            )
        )
    }

    func makePaperListViewModel() -> PaperListViewModel {
        let runtime = makeLibraryRuntime()
        return PaperListViewModel(
            context: viewContext,
            libraryRuntime: runtime
        )
    }
}
