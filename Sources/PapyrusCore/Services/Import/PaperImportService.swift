import Foundation
import CoreData
import CryptoKit

enum PaperImportError: LocalizedError {
    case duplicate(title: String)
    case importFailed
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .duplicate(let title):
            return "Already exists: \(title)"
        case .importFailed:
            return "Import failed"
        case .downloadFailed:
            return "Download failed"
        }
    }
}

@MainActor
final class PaperImportService {
    typealias PDFDownloadClient = @Sendable (URLRequest) async throws -> URL
    typealias PDFSeedClient = @Sendable (URL) -> PDFSeed
    typealias WebpageMetadataClient = @Sendable (URL) async throws -> WebpageMetadata
    typealias PaperChangeHandler = @MainActor @Sendable (NSManagedObjectID) -> Void

    struct ImportReceipt {
        let objectID: NSManagedObjectID
        let shouldEnrich: Bool
    }

    struct QueuedImport {
        let objectID: NSManagedObjectID
        let sourcePDFURL: URL?
        let temporaryFiles: [URL]
    }

    private final class ImportWorkingSet {
        var temporaryFiles: [URL] = []
    }

    private struct ImportDraft {
        let id: UUID
        let sourcePDFURL: URL?
        let originalFilename: String
        var title: String?
        var titleCandidates: [String]
        var authors: String?
        var venue: String?
        var year: Int16
        var doi: String?
        var arxivId: String?
        var abstract: String?
        var publicationType: String?

        init(sourcePDFURL: URL?, originalFilename: String) {
            self.id = UUID()
            self.sourcePDFURL = sourcePDFURL
            self.originalFilename = originalFilename
            self.title = nil
            self.titleCandidates = []
            self.authors = nil
            self.venue = nil
            self.year = 0
            self.doi = nil
            self.arxivId = nil
            self.abstract = nil
            self.publicationType = nil
        }

        mutating func apply(pdfSeed: PDFSeed) {
            if title == nil {
                title = MetadataNormalization.normalizeTitle(pdfSeed.title)
            }
            titleCandidates = mergeTitleCandidates(titleCandidates, pdfSeed.titleCandidates + [pdfSeed.title].compactMap { $0 })
            if authors == nil {
                authors = MetadataNormalization.normalizedAuthorsString(pdfSeed.authors)
            }
            if venue == nil {
                venue = MetadataNormalization.normalizeVenue(pdfSeed.venue)
            }
            if year == 0, pdfSeed.year > 0 {
                year = pdfSeed.year
            }
            if doi == nil {
                doi = Self.normalizedDOI(pdfSeed.doi)
            }
            if arxivId == nil {
                arxivId = Self.normalizedArxivID(pdfSeed.arxivId)
            }
            if abstract == nil {
                abstract = MetadataNormalization.normalizeAbstract(pdfSeed.abstract)
            }
        }

        mutating func apply(webpageMetadata: WebpageMetadata) {
            if let resolvedTitle = MetadataNormalization.normalizeTitle(webpageMetadata.title) {
                title = resolvedTitle
                titleCandidates = mergeTitleCandidates(titleCandidates, [resolvedTitle])
            }
            if let resolvedAuthors = MetadataNormalization.normalizedAuthorsString(webpageMetadata.authors) {
                authors = resolvedAuthors
            }
            if let resolvedVenue = MetadataNormalization.normalizeVenue(webpageMetadata.venue) {
                venue = resolvedVenue
            }
            if webpageMetadata.year > 0 {
                year = Int16(clamping: webpageMetadata.year)
            }
            if let resolvedDOI = Self.normalizedDOI(webpageMetadata.doi) {
                doi = resolvedDOI
            }
            if let resolvedArxivId = Self.normalizedArxivID(webpageMetadata.arxivId) {
                arxivId = resolvedArxivId
            }
            if let resolvedAbstract = MetadataNormalization.normalizeAbstract(webpageMetadata.abstract) {
                abstract = resolvedAbstract
            }
        }

        mutating func finalize() {
            title = MetadataNormalization.normalizeTitle(title)
            titleCandidates = mergeTitleCandidates(titleCandidates, [title].compactMap { $0 })
            authors = MetadataNormalization.normalizedAuthorsString(authors)
            venue = MetadataNormalization.normalizeVenue(venue)
            abstract = MetadataNormalization.normalizeAbstract(abstract)
            doi = Self.normalizedDOI(doi)
            arxivId = Self.normalizedArxivID(arxivId)
            if publicationType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                publicationType = MetadataParsers.inferPublicationType(
                    venue: venue,
                    doi: doi,
                    arxivId: arxivId
                )
            }
        }

        func apply(to paper: Paper) {
            paper.id = id
            paper.originalFilename = originalFilename
            paper.dateAdded = Date()
            paper.dateModified = Date()
            paper.setReadingStatus(.unread)
            paper.rating = 0
            paper.citationCount = -1
            paper.resetResolvedMetadata()
            paper.applySourceSeed(
                title: title,
                authors: authors,
                venue: venue,
                year: year,
                doi: doi,
                arxivId: arxivId,
                abstract: abstract,
                publicationType: publicationType,
                updateDisplayedFields: true
            )
        }

        func applyMetadata(to paper: Paper, updateDisplayedFields: Bool) {
            paper.resetResolvedMetadata()
            paper.applySourceSeed(
                title: title,
                authors: authors,
                venue: venue,
                year: year,
                doi: doi,
                arxivId: arxivId,
                abstract: abstract,
                publicationType: publicationType,
                updateDisplayedFields: updateDisplayedFields
            )
        }

        private static func normalizedDOI(_ raw: String?) -> String? {
            let value = MetadataNormalization.normalizedDOI(raw)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value, !value.isEmpty else { return nil }
            return value.lowercased()
        }

        private static func normalizedArxivID(_ raw: String?) -> String? {
            guard let raw else { return nil }
            let cleaned = PaperImportService.normalizedArxivID(raw)
            return cleaned.isEmpty ? nil : cleaned
        }

        private func mergeTitleCandidates(_ existing: [String], _ incoming: [String]) -> [String] {
            var ordered = existing
            var seen = Set(existing.map { $0.lowercased() })
            for raw in incoming {
                for query in MetadataNormalization.titleSearchQueries(raw) {
                    let key = query.lowercased()
                    if seen.insert(key).inserted {
                        ordered.append(query)
                    }
                }
            }
            return ordered
        }
    }

    private let viewContext: NSManagedObjectContext
    private let venueMaintenanceService: VenueMaintenanceService
    private let metadataProvider: MetadataProviding
    private let fileStorage: FileStorageProviding
    private let downloadPDF: PDFDownloadClient
    private let extractPDFSeed: PDFSeedClient
    private let fetchWebpageMetadataClient: WebpageMetadataClient

    init(
        viewContext: NSManagedObjectContext,
        venueMaintenanceService: VenueMaintenanceService,
        metadataProvider: MetadataProviding = MetadataService.shared,
        fileStorage: FileStorageProviding = PaperFileManager.shared,
        downloadPDF: PDFDownloadClient? = nil,
        extractPDFSeed: PDFSeedClient? = nil,
        fetchWebpageMetadataClient: WebpageMetadataClient? = nil
    ) {
        self.viewContext = viewContext
        self.venueMaintenanceService = venueMaintenanceService
        self.metadataProvider = metadataProvider
        self.fileStorage = fileStorage
        self.downloadPDF = downloadPDF ?? { request in
            let (tempURL, _) = try await URLSession.shared.download(for: request)
            return tempURL
        }
        self.extractPDFSeed = extractPDFSeed ?? { PDFSeedExtractor.extract(from: $0) }
        self.fetchWebpageMetadataClient = fetchWebpageMetadataClient ?? { url in
            try await Self.fetchWebpageMetadata(from: url)
        }
    }

    private func syncVenueRelationship(for paper: Paper) {
        venueMaintenanceService.findOrCreateVenue(for: paper)
    }

    func importPDF(
        from url: URL,
        webpageMetadata: WebpageMetadata? = nil,
        existingPapers: [Paper],
        onStageChange: @escaping (WorkflowStage) -> Void,
        onPaperChanged: @escaping PaperChangeHandler = { _ in }
    ) async throws -> ImportReceipt {
        let queuedImport = try await queuePDFImport(
            from: url,
            webpageMetadata: webpageMetadata,
            existingPapers: existingPapers,
            onStageChange: onStageChange
        )
        onPaperChanged(queuedImport.objectID)
        let receipt = try await completeQueuedImport(
            queuedImport,
            existingPapers: existingPapers,
            onStageChange: onStageChange,
            onPaperChanged: onPaperChanged
        )
        return receipt
    }

    func queuePDFImport(
        from url: URL,
        webpageMetadata: WebpageMetadata? = nil,
        existingPapers: [Paper],
        onStageChange: @escaping (WorkflowStage) -> Void
    ) async throws -> QueuedImport {
        let resolvedWebpageMetadata = try await resolveBrowserPDFMetadata(
            from: normalizedWebpageMetadata(webpageMetadata),
            onStageChange: onStageChange
        )

        onStageChange(.checking)
        try assertNoDuplicate(
            arxivId: resolvedWebpageMetadata?.arxivId,
            doi: resolvedWebpageMetadata?.doi,
            fileURL: url,
            existingPapers: existingPapers
        )

        var draft = ImportDraft(
            sourcePDFURL: url,
            originalFilename: makeOriginalFilename(
                from: resolvedWebpageMetadata?.title
                    ?? resolvedWebpageMetadata?.doi
                    ?? resolvedWebpageMetadata?.arxivId
                    ?? url.lastPathComponent
            )
        )
        if let resolvedWebpageMetadata {
            draft.apply(webpageMetadata: resolvedWebpageMetadata)
        }
        draft.finalize()

        onStageChange(.saving)
        let objectID = try persistInitialImport(draft)
        return QueuedImport(objectID: objectID, sourcePDFURL: url, temporaryFiles: [])
    }

    private func mergedWebpageMetadata(
        preferred: WebpageMetadata?,
        fallback: WebpageMetadata?,
        defaultSourceURL: URL
    ) -> WebpageMetadata {
        var merged = fallback ?? WebpageMetadata()
        if let preferred {
            if let title = preferred.title { merged.title = title }
            if let authors = preferred.authors { merged.authors = authors }
            if let doi = preferred.doi { merged.doi = doi }
            if let arxivId = preferred.arxivId { merged.arxivId = arxivId }
            if let abstract = preferred.abstract { merged.abstract = abstract }
            if let venue = preferred.venue { merged.venue = venue }
            if preferred.year > 0 { merged.year = preferred.year }
            if let pdfURL = preferred.pdfURL { merged.pdfURL = pdfURL }
            if let sourceURL = preferred.sourceURL { merged.sourceURL = sourceURL }
        }
        if merged.sourceURL == nil {
            merged.sourceURL = defaultSourceURL
        }
        return merged
    }

    private func normalizedWebpageMetadata(_ metadata: WebpageMetadata?) -> WebpageMetadata? {
        guard var metadata else { return nil }
        metadata.title = normalizedNonEmpty(metadata.title)
        metadata.authors = normalizedNonEmpty(metadata.authors)
        metadata.doi = normalizedNonEmpty(metadata.doi)
        metadata.arxivId = normalizedNonEmpty(metadata.arxivId)
        metadata.abstract = normalizedNonEmpty(metadata.abstract)
        metadata.venue = normalizedNonEmpty(metadata.venue)
        if metadata.year < 0 {
            metadata.year = 0
        }

        guard metadata.title != nil
            || metadata.authors != nil
            || metadata.doi != nil
            || metadata.arxivId != nil
            || metadata.abstract != nil
            || metadata.venue != nil
            || metadata.year > 0
            || metadata.pdfURL != nil
            || metadata.sourceURL != nil else {
            return nil
        }
        return metadata
    }

    private func normalizedNonEmpty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func looksLikeDirectPDFURL(_ url: URL) -> Bool {
        let absolute = url.absoluteString.lowercased()
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        if url.pathExtension.lowercased() == "pdf" || absolute.contains("openreview.net/pdf?id=") {
            return true
        }
        if host.contains("arxiv.org") && path.contains("/pdf/") {
            return true
        }
        if host.contains("dl.acm.org") && (path.contains("/doi/pdf/") || path.contains("/doi/epdf/")) {
            return true
        }
        return false
    }

    nonisolated static func normalizedArxivID(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
    }

    private func findDuplicate(
        arxivId: String?,
        doi: String?,
        fileURL: URL?,
        existingPapers: [Paper]
    ) -> Paper? {
        if let normalizedArxivId = normalizedArxivLookupKey(arxivId),
           let existing = existingPapers.first(where: { normalizedArxivLookupKey($0.arxivId) == normalizedArxivId }) {
            return existing
        }
        if let normalizedDOI = normalizedDOILookupKey(doi),
           let existing = existingPapers.first(where: { normalizedDOILookupKey($0.doi) == normalizedDOI }) {
            return existing
        }
        if let fileURL, let incomingHash = fileHash(of: fileURL) {
            for paper in existingPapers {
                if let filePath = paper.filePath,
                   let existingHash = fileHash(of: URL(fileURLWithPath: filePath)),
                   existingHash == incomingHash {
                    return paper
                }
            }
        }
        return nil
    }

    private func assertNoDuplicate(
        arxivId: String?,
        doi: String?,
        fileURL: URL?,
        existingPapers: [Paper]
    ) throws {
        if let existing = findDuplicate(
            arxivId: arxivId,
            doi: doi,
            fileURL: fileURL,
            existingPapers: existingPapers
        ) {
            throw PaperImportError.duplicate(title: existing.displayTitle)
        }
    }

    private func fileHash(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1_048_576

        while true {
            guard let data = try? handle.read(upToCount: chunkSize), !data.isEmpty else {
                break
            }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func fetchWebpageMetadata(from url: URL) async throws -> WebpageMetadata {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw PaperImportError.downloadFailed
        }
        return WebpageMetadataExtractor.extract(from: html, pageURL: url)
    }

    private func resolveBrowserPDFMetadata(
        from incoming: WebpageMetadata?,
        onStageChange: @escaping (WorkflowStage) -> Void
    ) async throws -> WebpageMetadata? {
        guard let incoming else { return nil }
        guard let referrerURL = metadataContextURL(from: incoming) else {
            return incoming
        }

        onStageChange(.fetching)
        let fetched = try? await fetchWebpageMetadataClient(referrerURL)
        guard let fetched else {
            return incoming
        }

        var merged = mergedWebpageMetadata(
            preferred: fetched,
            fallback: incoming,
            defaultSourceURL: referrerURL
        )
        if let pdfURL = incoming.pdfURL {
            merged.pdfURL = pdfURL
        }
        if let sourceURL = incoming.sourceURL {
            merged.sourceURL = sourceURL
        }
        return normalizedWebpageMetadata(merged)
    }

    private func metadataContextURL(from metadata: WebpageMetadata) -> URL? {
        if let sourceURL = referrerMetadataURL(from: metadata) {
            return sourceURL
        }
        return inferredLandingPageURL(from: metadata.pdfURL)
    }

    private func referrerMetadataURL(from metadata: WebpageMetadata) -> URL? {
        guard let sourceURL = metadata.sourceURL,
              let scheme = sourceURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              !Self.looksLikeDirectPDFURL(sourceURL) else {
            return nil
        }

        if let pdfURL = metadata.pdfURL,
           normalizeLookupURL(sourceURL) == normalizeLookupURL(pdfURL) {
            return nil
        }

        let host = sourceURL.host?.lowercased() ?? ""
        if host.contains("scholar.google.") {
            return nil
        }

        return sourceURL
    }

    private func inferredLandingPageURL(from pdfURL: URL?) -> URL? {
        guard let pdfURL,
              let host = pdfURL.host?.lowercased(),
              host.contains("ieeexplore.ieee.org") else {
            return nil
        }

        guard pdfURL.path.lowercased().contains("/stamp/stamp.jsp"),
              let components = URLComponents(url: pdfURL, resolvingAgainstBaseURL: false),
              let arnumber = components.queryItems?.first(where: { $0.name.caseInsensitiveCompare("arnumber") == .orderedSame })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !arnumber.isEmpty else {
            return nil
        }

        return URL(string: "https://ieeexplore.ieee.org/document/\(arnumber)")
    }

    private func normalizeLookupURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    private func downloadPDF(from url: URL, displayName: String) async throws -> URL {
        do {
            var request = URLRequest(url: url)
            request.setValue("Papyrus/1.0", forHTTPHeaderField: "User-Agent")
            let tempURL = try await downloadPDF(request)
            if let handle = try? FileHandle(forReadingFrom: tempURL) {
                let header = handle.readData(ofLength: 4)
                handle.closeFile()
                guard header.starts(with: [0x25, 0x50, 0x44, 0x46]) else {
                    throw PaperImportError.downloadFailed
                }
            }
            let safeName = makeOriginalFilename(from: displayName)
            let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.moveItem(at: tempURL, to: destURL)
            return destURL
        } catch let error as PaperImportError {
            throw error
        } catch {
            throw PaperImportError.downloadFailed
        }
    }

    private func preparePDFDraft(
        from url: URL,
        preferredFilename: String?,
        existingPapers: [Paper],
        onStageChange: @escaping (WorkflowStage) -> Void
    ) async throws -> ImportDraft {
        onStageChange(.extracting)
        let pdfSeed = extractPDFSeed(url)
        var draft = ImportDraft(
            sourcePDFURL: url,
            originalFilename: makeOriginalFilename(from: preferredFilename ?? url.lastPathComponent)
        )
        draft.apply(pdfSeed: pdfSeed)
        draft.finalize()

        onStageChange(.checking)
        try assertNoDuplicate(
            arxivId: draft.arxivId,
            doi: draft.doi,
            fileURL: url,
            existingPapers: existingPapers
        )
        return draft
    }

    func completeQueuedImport(
        _ queuedImport: QueuedImport,
        existingPapers: [Paper],
        onStageChange: @escaping (WorkflowStage) -> Void,
        onPaperChanged: @escaping PaperChangeHandler
    ) async throws -> ImportReceipt {
        let workingSet = ImportWorkingSet()
        workingSet.temporaryFiles = queuedImport.temporaryFiles
        defer { cleanupTemporaryFiles(in: workingSet) }

        return try await runImportedPaperWorkflow(
            objectID: queuedImport.objectID,
            sourcePDFURL: queuedImport.sourcePDFURL,
            existingPapers: existingPapers,
            onStageChange: onStageChange,
            onPaperChanged: onPaperChanged
        )
    }

    func cleanupQueuedImportArtifacts(_ queuedImport: QueuedImport) {
        let workingSet = ImportWorkingSet()
        workingSet.temporaryFiles = queuedImport.temporaryFiles
        cleanupTemporaryFiles(in: workingSet)
    }

    private func runImportedPaperWorkflow(
        objectID: NSManagedObjectID,
        sourcePDFURL: URL?,
        existingPapers: [Paper],
        onStageChange: @escaping (WorkflowStage) -> Void,
        onPaperChanged: @escaping PaperChangeHandler
    ) async throws -> ImportReceipt {
        if let sourcePDFURL {
            do {
                onStageChange(.extracting)
                let pdfSeed = extractPDFSeed(sourcePDFURL)
                try applyPDFSeed(
                    pdfSeed,
                    to: objectID,
                    existingPapers: existingPapers
                )
            } catch let error as PaperImportError {
                if case .duplicate = error {
                    try rollbackImportedPaper(objectID)
                    onPaperChanged(objectID)
                    throw error
                }
                return ImportReceipt(objectID: objectID, shouldEnrich: false)
            } catch {
                return ImportReceipt(objectID: objectID, shouldEnrich: false)
            }
        }

        let shouldEnrich = shouldEnrichImportedPaper(objectID)
        try updateWorkflowStatus(
            for: objectID,
            fetch: shouldEnrich ? .queued : .skipped
        )
        onPaperChanged(objectID)

        return ImportReceipt(objectID: objectID, shouldEnrich: shouldEnrich)
    }

    private func persistInitialImport(_ draft: ImportDraft) throws -> NSManagedObjectID {
        let entity = NSEntityDescription.entity(forEntityName: "Paper", in: viewContext)!
        let paper = Paper(entity: entity, insertInto: viewContext)
        draft.apply(to: paper)

        var importedFileURL: URL?

        do {
            if let sourcePDFURL = draft.sourcePDFURL {
                let storedFileURL = try fileStorage.importPDF(from: sourcePDFURL, paper: paper)
                importedFileURL = storedFileURL
                paper.filePath = storedFileURL.path
            } else {
                paper.filePath = nil
            }
            syncVenueRelationship(for: paper)
            try viewContext.obtainPermanentIDs(for: [paper])
            try viewContext.save()
            return paper.objectID
        } catch {
            viewContext.rollback()
            if let importedFileURL,
               importedFileURL.path != (draft.sourcePDFURL?.path ?? ""),
               FileManager.default.fileExists(atPath: importedFileURL.path) {
                try? FileManager.default.removeItem(at: importedFileURL)
            }
            throw error
        }
    }

    private func applyPDFSeed(
        _ pdfSeed: PDFSeed,
        to objectID: NSManagedObjectID,
        existingPapers: [Paper]
    ) throws {
        guard let paper = try viewContext.existingObject(with: objectID) as? Paper,
              let filePath = paper.filePath else {
            throw PaperImportError.importFailed
        }

        var draft = ImportDraft(
            sourcePDFURL: URL(fileURLWithPath: filePath),
            originalFilename: paper.originalFilename ?? makeOriginalFilename(from: filePath)
        )
        draft.title = paper.seedTitle ?? paper.title
        draft.titleCandidates = paper.refreshMetadataSeed.titleCandidates
        draft.authors = paper.seedAuthors ?? paper.authors
        draft.venue = paper.seedVenue ?? paper.venue
        draft.year = paper.seedYear > 0 ? paper.seedYear : paper.year
        draft.doi = paper.seedDOI ?? paper.doi
        draft.arxivId = paper.seedArxivId ?? paper.arxivId
        draft.abstract = paper.seedAbstract ?? paper.abstract
        draft.publicationType = paper.seedPublicationType ?? paper.publicationType
        draft.apply(pdfSeed: pdfSeed)
        draft.finalize()

        try assertNoDuplicate(
            arxivId: draft.arxivId,
            doi: draft.doi,
            fileURL: URL(fileURLWithPath: filePath),
            existingPapers: existingPapers.filter { $0.objectID != objectID }
        )

        draft.applyMetadata(to: paper, updateDisplayedFields: true)
        syncVenueRelationship(for: paper)
        paper.dateModified = Date()
        try viewContext.save()
    }

    private func shouldEnrichImportedPaper(_ objectID: NSManagedObjectID) -> Bool {
        guard let paper = try? viewContext.existingObject(with: objectID) as? Paper else {
            return false
        }
        let seed = MetadataSeed(paper: paper)
        return seed.doi != nil || seed.arxivId != nil || !seed.searchTitles.isEmpty
    }

    private func rollbackImportedPaper(_ objectID: NSManagedObjectID) throws {
        guard let paper = try? viewContext.existingObject(with: objectID) as? Paper else {
            return
        }
        if let filePath = paper.filePath, FileManager.default.fileExists(atPath: filePath) {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: filePath))
        }
        fileStorage.removeAttachments(for: paper)
        viewContext.delete(paper)
        try viewContext.save()
    }

    private func updateWorkflowStatus(
        for objectID: NSManagedObjectID,
        fetch: PaperWorkflowPhase
    ) throws {
        guard try viewContext.existingObject(with: objectID) is Paper else {
            throw PaperImportError.importFailed
        }
        let status = PaperWorkflowStatus(fetch: fetch)
        PaperTransientStateStore.shared.setWorkflowStatus(status, for: objectID)
    }

    private func cleanupTemporaryFiles(in workingSet: ImportWorkingSet) {
        for url in workingSet.temporaryFiles where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func makeOriginalFilename(from raw: String?, requirePDFExtension: Bool = true) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = trimmed.isEmpty ? "paper" : trimmed
        let sanitized = fallback
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        guard requirePDFExtension else {
            return sanitized
        }
        if sanitized.lowercased().hasSuffix(".pdf") {
            return sanitized
        }
        return sanitized + ".pdf"
    }

    private func normalizedDOILookupKey(_ raw: String?) -> String? {
        guard let normalized = MetadataNormalization.normalizedDOI(raw)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    private func normalizedArxivLookupKey(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = Self.normalizedArxivID(raw)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return normalized.components(separatedBy: "v").first
    }
}
