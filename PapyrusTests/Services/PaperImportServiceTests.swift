import CoreData
import Testing
@testable import PapyrusCore

private final class NoopMetadataProvider: MetadataProviding {
    func enrichMetadata(paper: Paper) async -> Bool { false }
    func fetchPDFURL(arxivId: String?, doi: String?) async throws -> URL { throw MetadataError.notFound }
    func fetchReferences(for paper: Paper) async throws -> [PaperReference] { [] }
    func fetchCitations(for paper: Paper) async throws -> [PaperReference] { [] }
}

private final class NoopRankProvider: RankProviding {
    func cached(venue: String) -> JournalRankInfo? { nil }
    func fetchIfNeeded(venue: String) async {}
    func fetchForce(venue: String) async {}
}

private final class NoopVenueAbbreviationProvider: VenueAbbreviationProviding {
    func cached(venue: String) -> String? { nil }
    func fetchFromDBLPIfNeeded(venue: String) async {}
}

private final class RecordingFileStorage: FileStorageProviding {
    let libraryURL: URL = FileManager.default.temporaryDirectory
    let pdfDirectoryURL: URL = FileManager.default.temporaryDirectory
    let attachmentsDirectoryURL: URL = FileManager.default.temporaryDirectory
    private(set) var importCallCount = 0

    func importPDF(from sourceURL: URL, paper: Paper) throws -> URL {
        importCallCount += 1
        return sourceURL
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

private final class FailingFileStorage: FileStorageProviding {
    let libraryURL: URL = FileManager.default.temporaryDirectory
    let pdfDirectoryURL: URL = FileManager.default.temporaryDirectory
    let attachmentsDirectoryURL: URL = FileManager.default.temporaryDirectory

    func importPDF(from sourceURL: URL, paper: Paper) throws -> URL {
        throw CocoaError(.fileWriteUnknown)
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

@MainActor
struct PaperImportServiceTests {
    @Test
    func importPDFRejectsDuplicateByMatchingFileHashBeforeWriting() async throws {
        let context = TestSupport.makeInMemoryContext()
        let pdfURL = try TestSupport.makeTempPDF(named: "duplicate-source")
        let existingCopyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("duplicate-existing")
            .appendingPathExtension("pdf")
        try? FileManager.default.removeItem(at: existingCopyURL)
        try FileManager.default.copyItem(at: pdfURL, to: existingCopyURL)

        let existing = TestSupport.makePaper(in: context, title: "Existing Paper")
        existing.filePath = existingCopyURL.path
        try context.save()

        let fileStorage = RecordingFileStorage()
        let service = makeService(context: context, metadataProvider: NoopMetadataProvider(), fileStorage: fileStorage)
        var stages: [PaperListViewModel.ImportTask.Stage] = []

        await #expect(throws: PaperImportError.self) {
            try await service.importPDF(
                from: pdfURL,
                existingPapers: [existing],
                onStageChange: { stages.append($0) }
            )
        }

        #expect(fileStorage.importCallCount == 0)
        #expect(stages.count == 1)
        #expect(stages[0].label == "Checking duplicates...")
    }

    @Test
    func importPDFDoesNotLeaveHalfInsertedPaperWhenFileCopyFails() async throws {
        let context = TestSupport.makeInMemoryContext()
        let pdfURL = try TestSupport.makeTempPDF(named: "failing-import")
        let service = makeService(
            context: context,
            metadataProvider: NoopMetadataProvider(),
            fileStorage: FailingFileStorage()
        )

        await #expect(throws: Error.self) {
            try await service.importPDF(
                from: pdfURL,
                existingPapers: [],
                onStageChange: { _ in }
            )
        }

        let fetchRequest: NSFetchRequest<Paper> = Paper.fetchRequest()
        let papers = try context.fetch(fetchRequest)
        #expect(papers.isEmpty)
    }

    @Test
    func importPDFAppliesWebMetadataWhenProvided() async throws {
        let context = TestSupport.makeInMemoryContext()
        let pdfURL = try TestSupport.makeTempTextPDF(
            named: "pdf-with-web-metadata",
            lines: [
                "PDF Seed Title",
                "PDF Author"
            ]
        )
        let service = makeService(
            context: context,
            metadataProvider: NoopMetadataProvider(),
            fileStorage: RecordingFileStorage(),
            extractPDFSeed: { _ in
                PDFSeed(
                    title: "PDF Seed Title",
                    titleCandidates: ["PDF Seed Title"],
                    authors: "PDF Author",
                    venue: nil,
                    year: 0,
                    doi: nil,
                    arxivId: nil,
                    abstract: nil
                )
            }
        )

        var webMetadata = WebpageMetadata()
        webMetadata.title = "Browser PDF Title"
        webMetadata.authors = "Browser Author"
        webMetadata.doi = "10.1145/1234567.1234568"
        webMetadata.venue = "ACM Conference"
        webMetadata.year = 2026

        _ = try await service.importPDF(
            from: pdfURL,
            webpageMetadata: webMetadata,
            existingPapers: [],
            onStageChange: { _ in }
        )

        let fetchRequest: NSFetchRequest<Paper> = Paper.fetchRequest()
        let papers = try context.fetch(fetchRequest)
        #expect(papers.count == 1)
        let paper = try #require(papers.first)
        #expect(paper.filePath != nil)
        #expect(paper.title == "Browser PDF Title")
        #expect(paper.authors == "Browser Author")
        #expect(paper.doi == "10.1145/1234567.1234568")
        #expect(paper.venue == "ACM Conference")
        #expect(paper.venueObject?.name == "ACM Conference")
        #expect(paper.year == 2026)
    }

    @Test
    func importPDFPrefersReferrerPageMetadataForBrowserTransportedPDF() async throws {
        let context = TestSupport.makeInMemoryContext()
        let pdfURL = try TestSupport.makeTempTextPDF(
            named: "browser-pdf-referrer-metadata",
            lines: [
                "PDF Seed Title",
                "PDF Author"
            ]
        )
        let service = makeService(
            context: context,
            metadataProvider: NoopMetadataProvider(),
            fileStorage: RecordingFileStorage(),
            extractPDFSeed: { _ in
                PDFSeed(
                    title: "PDF Seed Title",
                    titleCandidates: ["PDF Seed Title"],
                    authors: "PDF Author",
                    venue: nil,
                    year: 0,
                    doi: nil,
                    arxivId: nil,
                    abstract: nil
                )
            },
            fetchWebpageMetadataClient: { url in
                #expect(url.absoluteString == "https://dl.acm.org/doi/10.1145/3540250.3549081")
                var metadata = WebpageMetadata()
                metadata.title = "Referrer Landing Title"
                metadata.authors = "Landing Author One, Landing Author Two"
                metadata.doi = "10.1145/3540250.3549081"
                metadata.venue = "CHI"
                metadata.year = 2026
                metadata.sourceURL = url
                metadata.pdfURL = URL(string: "https://dl.acm.org/doi/pdf/10.1145/3540250.3549081")
                return metadata
            }
        )

        var browserMetadata = WebpageMetadata()
        browserMetadata.title = "Safari PDF Tab Title"
        browserMetadata.pdfURL = URL(string: "https://dl.acm.org/doi/pdf/10.1145/3540250.3549081")
        browserMetadata.sourceURL = URL(string: "https://dl.acm.org/doi/10.1145/3540250.3549081")

        _ = try await service.importPDF(
            from: pdfURL,
            webpageMetadata: browserMetadata,
            existingPapers: [],
            onStageChange: { _ in }
        )

        let fetchRequest: NSFetchRequest<Paper> = Paper.fetchRequest()
        let papers = try context.fetch(fetchRequest)
        #expect(papers.count == 1)
        let paper = try #require(papers.first)
        #expect(paper.title == "Referrer Landing Title")
        #expect(paper.authors == "Landing Author One, Landing Author Two")
        #expect(paper.doi == "10.1145/3540250.3549081")
        #expect(paper.venue == "CHI")
        #expect(paper.venueObject?.name == "CHI")
        #expect(paper.year == 2026)
    }

    @Test
    func importPDFInfersIEEELandingPageMetadataFromStampPDFURL() async throws {
        let context = TestSupport.makeInMemoryContext()
        let pdfURL = try TestSupport.makeTempTextPDF(
            named: "browser-pdf-ieee-stamp",
            lines: [
                "PDF Seed Title",
                "PDF Author"
            ]
        )
        let service = makeService(
            context: context,
            metadataProvider: NoopMetadataProvider(),
            fileStorage: RecordingFileStorage(),
            extractPDFSeed: { _ in
                PDFSeed(
                    title: "PDF Seed Title",
                    titleCandidates: ["PDF Seed Title"],
                    authors: "PDF Author",
                    venue: nil,
                    year: 0,
                    doi: nil,
                    arxivId: nil,
                    abstract: nil
                )
            },
            fetchWebpageMetadataClient: { url in
                #expect(url.absoluteString == "https://ieeexplore.ieee.org/document/10368182")
                var metadata = WebpageMetadata()
                metadata.title = "JSAC Landing Title"
                metadata.authors = "IEEE Author One, IEEE Author Two"
                metadata.doi = "10.1109/jsac.2023.3348234"
                metadata.venue = "IEEE Journal on Selected Areas in Communications"
                metadata.year = 2024
                metadata.sourceURL = url
                return metadata
            }
        )

        var browserMetadata = WebpageMetadata()
        browserMetadata.title = "stamp.jsp"
        browserMetadata.pdfURL = URL(string: "https://ieeexplore.ieee.org/stamp/stamp.jsp?tp=&arnumber=10368182")

        _ = try await service.importPDF(
            from: pdfURL,
            webpageMetadata: browserMetadata,
            existingPapers: [],
            onStageChange: { _ in }
        )

        let fetchRequest: NSFetchRequest<Paper> = Paper.fetchRequest()
        let papers = try context.fetch(fetchRequest)
        #expect(papers.count == 1)
        let paper = try #require(papers.first)
        #expect(paper.title == "JSAC Landing Title")
        #expect(paper.authors == "IEEE Author One, IEEE Author Two")
        #expect(paper.doi == "10.1109/jsac.2023.3348234")
        #expect(paper.venue == "IEEE Journal on Selected Areas in Communications")
        #expect(paper.venueObject?.name == "IEEE Journal on Selected Areas in Communications")
        #expect(paper.year == 2024)
    }

    private func makeService(
        context: NSManagedObjectContext? = nil,
        metadataProvider: MetadataProviding,
        fileStorage: FileStorageProviding,
        downloadPDF: PaperImportService.PDFDownloadClient? = nil,
        extractPDFSeed: PaperImportService.PDFSeedClient? = nil,
        fetchWebpageMetadataClient: PaperImportService.WebpageMetadataClient? = nil
    ) -> PaperImportService {
        let context = context ?? TestSupport.makeInMemoryContext()
        let rankProvider = NoopRankProvider()
        let abbrProvider = NoopVenueAbbreviationProvider()
        let venueService = VenueMaintenanceService(
            viewContext: context,
            rankProvider: rankProvider,
            venueAbbreviationProvider: abbrProvider
        )
        return PaperImportService(
            viewContext: context,
            venueMaintenanceService: venueService,
            metadataProvider: metadataProvider,
            fileStorage: fileStorage,
            downloadPDF: downloadPDF,
            extractPDFSeed: extractPDFSeed,
            fetchWebpageMetadataClient: fetchWebpageMetadataClient
        )
    }
}
