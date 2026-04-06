import CoreData
import Foundation
import Testing
@testable import PapyrusCore

private final class CommandsNoopMetadataProvider: MetadataProviding {
    func enrichMetadata(paper: Paper) async -> Bool { false }
    func fetchPDFURL(arxivId: String?, doi: String?) async throws -> URL { throw MetadataError.notFound }
    func fetchReferences(for paper: Paper) async throws -> [PaperReference] { [] }
    func fetchCitations(for paper: Paper) async throws -> [PaperReference] { [] }
}

private final class CommandsEnrichingMetadataProvider: MetadataProviding {
    func enrichMetadata(paper: Paper) async -> Bool {
        paper.title = "Enriched Title"
        paper.dateModified = Date()
        return true
    }

    func fetchPDFURL(arxivId: String?, doi: String?) async throws -> URL { throw MetadataError.notFound }
    func fetchReferences(for paper: Paper) async throws -> [PaperReference] { [] }
    func fetchCitations(for paper: Paper) async throws -> [PaperReference] { [] }
}

private final class CommandsNoopRankProvider: RankProviding {
    func cached(venue: String) -> JournalRankInfo? { nil }
    func fetchIfNeeded(venue: String) async {}
    func fetchForce(venue: String) async {}
}

private final class CommandsNoopVenueAbbreviationProvider: VenueAbbreviationProviding {
    func cached(venue: String) -> String? { nil }
    func fetchFromDBLPIfNeeded(venue: String) async {}
}

private final class CommandsRecordingFileStorage: FileStorageProviding {
    let libraryURL: URL = FileManager.default.temporaryDirectory
    let pdfDirectoryURL: URL = FileManager.default.temporaryDirectory
    let attachmentsDirectoryURL: URL = FileManager.default.temporaryDirectory

    func importPDF(from sourceURL: URL, paper: Paper) throws -> URL {
        sourceURL
    }

    func renameFile(for paper: Paper) throws -> URL? {
        nil
    }

    func notesURL(for paper: Paper) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("notes.md")
    }

    func loadNotes(for paper: Paper) -> String? {
        nil
    }

    func saveNotes(_ content: String?, for paper: Paper) throws -> URL? {
        nil
    }

    func removeAttachments(for paper: Paper) {}
}

struct LibraryCommandsTests {
    @MainActor
    @Test
    func getPaperReturnsDetailForUUID() throws {
        let context = TestSupport.makeInMemoryContext()
        let paper = TestSupport.makePaper(in: context, title: "Command Target")
        paper.doi = "10.1000/test"
        paper.tags = "ml, agents"
        try context.save()

        let commands = makeCommands(context: context)

        let detail = try commands.getPaper(id: paper.id)

        #expect(detail.title == "Command Target")
        #expect(detail.doi == "10.1000/test")
        #expect(detail.tags == ["ml", "agents"])
    }

    @MainActor
    @Test
    func updatePaperAppliesStatusRatingFlagsPinAndTags() throws {
        let context = TestSupport.makeInMemoryContext()
        let existingPinned = TestSupport.makePaper(in: context, title: "Pinned", isPinned: true, pinOrder: 0)
        let target = TestSupport.makePaper(in: context, title: "Target")
        target.tags = "old"
        try context.save()

        let commands = makeCommands(context: context)

        let updated = try commands.updatePaper(
            UpdatePaperCommand(
                id: target.id,
                readingStatus: .read,
                rating: 5,
                flagged: true,
                pinned: true,
                tagsToAdd: ["new"],
                tagsToRemove: ["old"]
            )
        )

        #expect(updated.readingStatus == Paper.ReadingStatus.read.rawValue)
        #expect(updated.rating == 5)
        #expect(updated.flagged == true)
        #expect(updated.pinned == true)
        #expect(Set(updated.tags) == ["new"])
        #expect(target.pinOrder == existingPinned.pinOrder + 1)
    }

    @MainActor
    @Test
    func updatePaperRejectsOutOfRangeRating() throws {
        let context = TestSupport.makeInMemoryContext()
        let target = TestSupport.makePaper(in: context, title: "Target")
        try context.save()

        let commands = makeCommands(context: context)

        #expect(throws: LibraryCommandError.self) {
            try commands.updatePaper(
                UpdatePaperCommand(
                    id: target.id,
                    rating: 6
                )
            )
        }
    }

    @MainActor
    @Test
    func updatePapersAppliesBatchFieldsAcrossMultipleRecords() throws {
        let context = TestSupport.makeInMemoryContext()
        let first = TestSupport.makePaper(in: context, title: "First")
        let second = TestSupport.makePaper(in: context, title: "Second")
        try context.save()

        let commands = makeCommands(context: context)

        try commands.updatePapers([
            UpdatePaperCommand(
                id: first.id,
                readingStatus: .reading,
                tagsToAdd: ["proj:alpha"],
                publicationType: "journal"
            ),
            UpdatePaperCommand(
                id: second.id,
                readingStatus: .reading,
                tagsToAdd: ["proj:alpha"],
                publicationType: "journal"
            )
        ])

        #expect(first.readingStatus == Paper.ReadingStatus.reading.rawValue)
        #expect(second.readingStatus == Paper.ReadingStatus.reading.rawValue)
        #expect(first.publicationType == "journal")
        #expect(second.publicationType == "journal")
        #expect(Set(first.tagsList) == ["proj:alpha"])
        #expect(Set(second.tagsList) == ["proj:alpha"])
    }

    @MainActor
    @Test
    func importPaperCreatesLibraryRecord() async throws {
        let context = TestSupport.makeInMemoryContext()
        let pdfURL = try TestSupport.makeTempTextPDF(
            named: "library-commands-import",
            lines: ["Imported Paper", "Author One"]
        )

        let commands = makeCommands(
            context: context,
            metadataProvider: CommandsNoopMetadataProvider()
        )

        let detail = try await commands.importPaper(ImportPaperCommand(pdfURL: pdfURL))

        #expect(detail.filePath == pdfURL.path)
        #expect(detail.id.uuidString.isEmpty == false)
    }

    @MainActor
    @Test
    func queueImportPaperCreatesInitialRecordThroughSharedCommand() async throws {
        let context = TestSupport.makeInMemoryContext()
        let pdfURL = try TestSupport.makeTempTextPDF(
            named: "library-commands-queue-import",
            lines: ["Queued Paper", "Author One"]
        )

        let commands = makeCommands(context: context)

        let detail = try await commands.queueImportPaper(
            ImportPaperCommand(pdfURL: pdfURL)
        )

        #expect(detail.filePath == pdfURL.path)
        #expect(detail.id.uuidString.isEmpty == false)
    }

    @MainActor
    @Test
    func deletePapersRemovesMatchingRecords() throws {
        let context = TestSupport.makeInMemoryContext()
        let kept = TestSupport.makePaper(in: context, title: "Kept")
        let removed = TestSupport.makePaper(in: context, title: "Removed")
        try context.save()

        let commands = makeCommands(context: context)

        try commands.deletePapers(ids: [removed.id])

        let remaining = try LoadLibraryPapersUseCase(viewContext: context).fetchAllPapers()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == kept.id)
    }

    @MainActor
    @Test
    func refreshMetadataUsesEnrichmentPipeline() async throws {
        let context = TestSupport.makeInMemoryContext()
        let target = TestSupport.makePaper(in: context, title: "Seed Title")
        target.doi = "10.1000/test"
        try context.save()

        let commands = makeCommands(
            context: context,
            metadataProvider: CommandsEnrichingMetadataProvider()
        )

        let detail = try await commands.refreshMetadata(id: target.id)

        #expect(detail.title == "Enriched Title")
    }

    @MainActor
    @Test
    func fetchMetadataUsesSharedFetchPipeline() async throws {
        let context = TestSupport.makeInMemoryContext()
        let target = TestSupport.makePaper(in: context, title: "Seed Title")
        target.doi = "10.1000/test"
        try context.save()

        let commands = makeCommands(
            context: context,
            metadataProvider: CommandsEnrichingMetadataProvider()
        )

        let detail = try await commands.fetchMetadata(id: target.id)

        #expect(detail.title == "Enriched Title")
    }

    @MainActor
    @Test
    func reextractMetadataSeedUpdatesPaperUsingSharedCommand() async throws {
        let context = TestSupport.makeInMemoryContext()
        let target = TestSupport.makePaper(in: context, title: "Original Title")
        target.filePath = "/tmp/reextract-source.pdf"
        try context.save()

        let commands = makeCommands(
            context: context,
            extractPDFSeed: { _ in
                PDFSeed(
                    title: "Retitled Paper",
                    titleCandidates: ["Retitled Paper"],
                    authors: "Author One, Author Two",
                    venue: "ICML",
                    year: 2025,
                    doi: "10.1000/reextract",
                    arxivId: "2501.12345",
                    abstract: "Recovered abstract"
                )
            }
        )

        let detail = try await commands.reextractMetadataSeed(id: target.id)

        #expect(detail.title == "Retitled Paper")
        #expect(detail.doi == "10.1000/reextract")
        #expect(detail.arxivId == "2501.12345")
        #expect(target.title == "Retitled Paper")
    }

    @MainActor
    private func makeCommands(
        context: NSManagedObjectContext,
        metadataProvider: MetadataProviding = CommandsNoopMetadataProvider(),
        extractPDFSeed: PaperMutationService.PDFSeedClient? = nil
    ) -> LibraryCommands {
        let venueMaintenanceService = VenueMaintenanceService(
            viewContext: context,
            rankProvider: CommandsNoopRankProvider(),
            venueAbbreviationProvider: CommandsNoopVenueAbbreviationProvider()
        )
        let mutationService = PaperMutationService(
            viewContext: context,
            venueMaintenanceService: venueMaintenanceService,
            metadataProvider: metadataProvider,
            rankProvider: CommandsNoopRankProvider(),
            venueAbbreviationProvider: CommandsNoopVenueAbbreviationProvider(),
            fileStorage: CommandsRecordingFileStorage(),
            extractPDFSeed: extractPDFSeed
        )
        let importService = PaperImportService(
            viewContext: context,
            venueMaintenanceService: venueMaintenanceService,
            metadataProvider: metadataProvider,
            fileStorage: CommandsRecordingFileStorage()
        )
        return LibraryCommands(
            viewContext: context,
            importPaperFromPDFUseCase: ImportPaperFromPDFUseCase(importService: importService),
            deletePapersUseCase: DeletePapersUseCase(mutationService: mutationService),
            refreshPaperMetadataUseCase: RefreshPaperMetadataUseCase(mutationService: mutationService),
            fetchPaperMetadataUseCase: FetchPaperMetadataUseCase(mutationService: mutationService),
            reextractPaperSeedUseCase: ReextractPaperSeedUseCase(mutationService: mutationService),
            applyBatchEditUseCase: ApplyBatchEditUseCase(mutationService: mutationService),
            setFlagStateUseCase: SetFlagStateUseCase(viewContext: context),
            setPinnedStateUseCase: SetPinnedStateUseCase(viewContext: context),
            loadLibraryPapersUseCase: LoadLibraryPapersUseCase(viewContext: context)
        )
    }
}
