import Foundation
import CoreData

@MainActor
final class PaperMutationService {
    typealias PDFSeedClient = @Sendable (URL) -> PDFSeed

    struct MetadataRefreshReceipt {
        let objectID: NSManagedObjectID
        let shouldEnrich: Bool
    }

    private let viewContext: NSManagedObjectContext
    private let venueMaintenanceService: VenueMaintenanceService
    private let metadataProvider: MetadataProviding
    private let rankProvider: RankProviding
    private let venueAbbreviationProvider: VenueAbbreviationProviding
    private let fileStorage: FileStorageProviding
    private let extractPDFSeed: PDFSeedClient
    private let venueLookupTimeoutSeconds: Double = 8

    init(
        viewContext: NSManagedObjectContext,
        venueMaintenanceService: VenueMaintenanceService,
        metadataProvider: MetadataProviding = MetadataService.shared,
        rankProvider: RankProviding = JournalRankService.shared,
        venueAbbreviationProvider: VenueAbbreviationProviding = VenueAbbreviationService.shared,
        fileStorage: FileStorageProviding = PaperFileManager.shared,
        extractPDFSeed: PDFSeedClient? = nil
    ) {
        self.viewContext = viewContext
        self.venueMaintenanceService = venueMaintenanceService
        self.metadataProvider = metadataProvider
        self.rankProvider = rankProvider
        self.venueAbbreviationProvider = venueAbbreviationProvider
        self.fileStorage = fileStorage
        self.extractPDFSeed = extractPDFSeed ?? { PDFSeedExtractor.extract(from: $0) }
    }

    func deletePaper(_ paper: Paper) throws {
        if let filePath = paper.filePath {
            let fileURL = URL(fileURLWithPath: filePath)
            do {
                try FileManager.default.removeItem(at: fileURL)
                print("Deleted file: \(filePath)")
            } catch {
                print("Failed to delete file: \(error.localizedDescription)")
            }
        }
        fileStorage.removeAttachments(for: paper)

        viewContext.delete(paper)
        try viewContext.save()
    }

    func deletePapers(_ papers: [Paper]) throws {
        for paper in papers {
            if let filePath = paper.filePath {
                let fileURL = URL(fileURLWithPath: filePath)
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    print("Deleted file: \(filePath)")
                } catch {
                    print("Failed to delete file: \(error.localizedDescription)")
                }
            }
            fileStorage.removeAttachments(for: paper)
            viewContext.delete(paper)
        }
        try viewContext.save()
    }

    func deleteAllPapers() throws {
        let libraryURL = fileStorage.libraryURL
        do {
            let files = try FileManager.default.contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: nil)
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
            print("Deleted all files in library")
        } catch {
            print("Failed to list files: \(error)")
        }

        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Paper.fetchRequest()
        let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        batchDelete.resultType = .resultTypeObjectIDs

        let result = try viewContext.execute(batchDelete) as? NSBatchDeleteResult
        if let objectIDs = result?.result as? [NSManagedObjectID] {
            let changes = [NSDeletedObjectsKey: objectIDs]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
        }
        try viewContext.save()
    }

    func refreshMetadata(
        for paper: Paper,
        onStageChange: @escaping (WorkflowStage) -> Void
    ) async -> MetadataRefreshReceipt {
        onStageChange(.extracting)
        do {
            _ = try await refreshPDFStage(for: paper)
        } catch {
            let shouldEnrich = canFetchMetadata(for: paper)
            let status = PaperWorkflowStatus(fetch: shouldEnrich ? .queued : .skipped)
            persistWorkflowStatus(status, for: paper)
            return MetadataRefreshReceipt(
                objectID: paper.objectID,
                shouldEnrich: shouldEnrich
            )
        }

        let shouldEnrich = canFetchMetadata(for: paper)
        let status = PaperWorkflowStatus(fetch: shouldEnrich ? .queued : .skipped)
        persistWorkflowStatus(status, for: paper)
        return MetadataRefreshReceipt(
            objectID: paper.objectID,
            shouldEnrich: shouldEnrich
        )
    }

    func fetchResolvedMetadata(
        for paper: Paper,
        forceVenueRefresh: Bool = false,
        onStageChange: @escaping (WorkflowStage) -> Void
    ) async {
        var seed = MetadataSeed(paper: paper)
        if seed.doi == nil, seed.arxivId == nil, seed.searchTitles.isEmpty {
            _ = try? await refreshPDFStage(for: paper)
            seed = MetadataSeed(paper: paper)
        }
        guard seed.doi != nil || seed.arxivId != nil || !seed.searchTitles.isEmpty else {
            persistWorkflowStatus(PaperWorkflowStatus(fetch: .skipped), for: paper)
            return
        }

        persistWorkflowStatus(PaperWorkflowStatus(fetch: .running), for: paper)

        onStageChange(.fetching)
        let resolution = await metadataProvider.enrichMetadata(paper: paper)
        let didEnrich = resolution.metadata != nil

        onStageChange(.saving)
        if let newURL = try? fileStorage.renameFile(for: paper) {
            paper.filePath = newURL.path
        }
        persistWorkflowStatus(PaperWorkflowStatus(fetch: didEnrich ? .done : .failed), for: paper)
        if didEnrich { onStageChange(.done) }

        let paperID = paper.objectID
        Task { @MainActor [self] in
            await refreshVenueDataIfNeeded(for: paperID, forceRefresh: forceVenueRefresh)
        }
    }

    func applyMetadataCandidate(for paper: Paper, candidate: MetadataCandidate) async {
        let existingCandidates: [MetadataCandidate]
        if let json = paper.fetchCandidatesJSON,
           let data = json.data(using: .utf8) {
            existingCandidates = (try? JSONDecoder().decode([MetadataCandidate].self, from: data)) ?? []
        } else {
            existingCandidates = []
        }
        MetadataUpdatePolicy.apply(
            metadata: candidate.metadata,
            from: candidate.source,
            score: nil,
            candidates: existingCandidates,
            trace: "manual=\(candidate.source)",
            to: paper
        )
        syncVenueRelationship(for: paper)
    }

    func reextractSourceSeed(for paper: Paper) async throws -> PDFSeed {
        guard let filePath = paper.filePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !filePath.isEmpty else {
            return PDFSeed(
                title: nil,
                titleCandidates: [],
                authors: nil,
                venue: nil,
                year: 0,
                doi: nil,
                arxivId: nil,
                abstract: nil
            )
        }

        let pdfSeed = extractPDFSeed(URL(fileURLWithPath: filePath))
        paper.applySourceSeed(
            title: pdfSeed.title,
            authors: pdfSeed.authors,
            venue: pdfSeed.venue,
            year: pdfSeed.year,
            doi: pdfSeed.doi,
            arxivId: pdfSeed.arxivId,
            abstract: pdfSeed.abstract,
            publicationType: MetadataParsers.inferPublicationType(
                venue: pdfSeed.venue,
                doi: pdfSeed.doi,
                arxivId: pdfSeed.arxivId
            ),
            updateDisplayedFields: true
        )
        paper.dateModified = Date()
        syncVenueRelationship(for: paper)
        return pdfSeed
    }

    private func persistWorkflowStatus(_ status: PaperWorkflowStatus, for paper: Paper) {
        PaperTransientStateStore.shared.setWorkflowStatus(status, for: paper.objectID)
    }

    private func refreshPDFStage(for paper: Paper) async throws -> Bool {
        guard let filePath = paper.filePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !filePath.isEmpty else {
            return false
        }

        let pdfSeed = extractPDFSeed(URL(fileURLWithPath: filePath))
        guard pdfSeed.hasMeaningfulMetadata else {
            return false
        }

        paper.applySourceSeed(
            title: pdfSeed.title,
            authors: pdfSeed.authors,
            venue: pdfSeed.venue,
            year: pdfSeed.year,
            doi: pdfSeed.doi,
            arxivId: pdfSeed.arxivId,
            abstract: pdfSeed.abstract,
            publicationType: MetadataParsers.inferPublicationType(
                venue: pdfSeed.venue,
                doi: pdfSeed.doi,
                arxivId: pdfSeed.arxivId
            ),
            updateDisplayedFields: true
        )
        paper.dateModified = Date()
        syncVenueRelationship(for: paper)
        return true
    }

    private func canFetchMetadata(for paper: Paper) -> Bool {
        let seed = MetadataSeed(paper: paper)
        return seed.doi != nil || seed.arxivId != nil || !seed.searchTitles.isEmpty
    }

    private func refreshVenueDataIfNeeded(for objectID: NSManagedObjectID, forceRefresh: Bool) async {
        guard let paper = try? viewContext.existingObject(with: objectID) as? Paper,
              let venue = paper.venue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !venue.isEmpty else {
            return
        }

        _ = await AsyncTimeout.run(seconds: venueLookupTimeoutSeconds) {
            if forceRefresh {
                await self.rankProvider.fetchForce(venue: venue)
            } else {
                await self.rankProvider.fetchIfNeeded(venue: venue)
            }
            await self.venueAbbreviationProvider.fetchFromDBLPIfNeeded(venue: venue)
        }
        venueMaintenanceService.findOrCreateVenue(for: paper)
        try? viewContext.save()
    }

    private func syncVenueRelationship(for paper: Paper) {
        venueMaintenanceService.findOrCreateVenue(for: paper)
        try? viewContext.save()
    }

    func applyBatchEdit(
        to papers: [Paper],
        status: Paper.ReadingStatus?,
        rating: Int,
        tagsToAdd: Set<String>,
        tagsToRemove: Set<String>,
        publicationType: String?
    ) throws {
        for paper in papers {
            if let status { paper.setReadingStatus(status) }
            if rating == 0 {
                paper.rating = 0
            } else if rating > 0 {
                paper.rating = Int16(rating)
            }
            if !tagsToAdd.isEmpty || !tagsToRemove.isEmpty {
                var current = Set(paper.tagsList)
                current.formUnion(tagsToAdd)
                current.subtract(tagsToRemove)
                paper.tags = Paper.normalizedTagsString(from: current.sorted().joined(separator: ", "))
            }
            if let publicationType {
                paper.publicationType = publicationType
                paper.publicationTypeManual = true
            }
            paper.dateModified = Date()
        }
        try viewContext.save()
    }
}
