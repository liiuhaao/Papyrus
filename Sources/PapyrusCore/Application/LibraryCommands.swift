import CoreData
import Foundation

package struct LibraryPaperDetail: Encodable {
    package let id: UUID
    package let title: String
    package let authors: String
    package let venue: String?
    package let year: Int
    package let doi: String?
    package let arxivId: String?
    package let abstract: String?
    package let tags: [String]
    package let flagged: Bool
    package let pinned: Bool
    package let readingStatus: String
    package let rating: Int
    package let filePath: String?
    package let dateAdded: Date
    package let dateModified: Date
}

package struct UpdatePaperCommand {
    package let id: UUID
    package let readingStatus: Paper.ReadingStatus?
    package let rating: Int?
    package let flagged: Bool?
    package let pinned: Bool?
    package let tagsToAdd: Set<String>
    package let tagsToRemove: Set<String>
    package let publicationType: String?

    package init(
        id: UUID,
        readingStatus: Paper.ReadingStatus? = nil,
        rating: Int? = nil,
        flagged: Bool? = nil,
        pinned: Bool? = nil,
        tagsToAdd: Set<String> = [],
        tagsToRemove: Set<String> = [],
        publicationType: String? = nil
    ) {
        self.id = id
        self.readingStatus = readingStatus
        self.rating = rating
        self.flagged = flagged
        self.pinned = pinned
        self.tagsToAdd = tagsToAdd
        self.tagsToRemove = tagsToRemove
        self.publicationType = publicationType
    }
}

package struct ImportPaperCommand {
    package let pdfURL: URL
    package let webpageMetadata: WebpageMetadata?

    package init(
        pdfURL: URL,
        webpageMetadata: WebpageMetadata? = nil
    ) {
        self.pdfURL = pdfURL
        self.webpageMetadata = webpageMetadata
    }
}

package enum LibraryCommandError: LocalizedError {
    case paperNotFound(UUID)
    case invalidRating(Int)

    package var errorDescription: String? {
        switch self {
        case .paperNotFound(let id):
            return "Paper not found: \(id.uuidString)"
        case .invalidRating(let rating):
            return "Rating must be between 0 and 5, got \(rating)"
        }
    }
}

@MainActor
package struct LibraryCommands {
    private let viewContext: NSManagedObjectContext
    private let importPaperFromPDFUseCase: ImportPaperFromPDFUseCase
    private let deletePapersUseCase: DeletePapersUseCase
    private let refreshPaperMetadataUseCase: RefreshPaperMetadataUseCase
    private let fetchPaperMetadataUseCase: FetchPaperMetadataUseCase
    private let reextractPaperSeedUseCase: ReextractPaperSeedUseCase
    private let applyMetadataCandidateUseCase: ApplyMetadataCandidateUseCase
    private let applyBatchEditUseCase: ApplyBatchEditUseCase
    private let setFlagStateUseCase: SetFlagStateUseCase
    private let setPinnedStateUseCase: SetPinnedStateUseCase
    private let loadLibraryPapersUseCase: LoadLibraryPapersUseCase

    init(
        viewContext: NSManagedObjectContext,
        importPaperFromPDFUseCase: ImportPaperFromPDFUseCase,
        deletePapersUseCase: DeletePapersUseCase,
        refreshPaperMetadataUseCase: RefreshPaperMetadataUseCase,
        fetchPaperMetadataUseCase: FetchPaperMetadataUseCase,
        reextractPaperSeedUseCase: ReextractPaperSeedUseCase,
        applyMetadataCandidateUseCase: ApplyMetadataCandidateUseCase,
        applyBatchEditUseCase: ApplyBatchEditUseCase,
        setFlagStateUseCase: SetFlagStateUseCase,
        setPinnedStateUseCase: SetPinnedStateUseCase,
        loadLibraryPapersUseCase: LoadLibraryPapersUseCase
    ) {
        self.viewContext = viewContext
        self.importPaperFromPDFUseCase = importPaperFromPDFUseCase
        self.deletePapersUseCase = deletePapersUseCase
        self.refreshPaperMetadataUseCase = refreshPaperMetadataUseCase
        self.fetchPaperMetadataUseCase = fetchPaperMetadataUseCase
        self.reextractPaperSeedUseCase = reextractPaperSeedUseCase
        self.applyMetadataCandidateUseCase = applyMetadataCandidateUseCase
        self.applyBatchEditUseCase = applyBatchEditUseCase
        self.setFlagStateUseCase = setFlagStateUseCase
        self.setPinnedStateUseCase = setPinnedStateUseCase
        self.loadLibraryPapersUseCase = loadLibraryPapersUseCase
    }

    package func getPaper(id: UUID) throws -> LibraryPaperDetail {
        try Self.makeDetail(resolvePaper(id: id))
    }

    @discardableResult
    package func updatePaper(_ command: UpdatePaperCommand) throws -> LibraryPaperDetail {
        try updatePapers([command])
        return try getPaper(id: command.id)
    }

    package func updatePapers(_ commands: [UpdatePaperCommand]) throws {
        guard !commands.isEmpty else { return }

        let allPapers = try loadLibraryPapersUseCase.fetchAllPapers()
        let papersByID = Dictionary(uniqueKeysWithValues: allPapers.map { ($0.id, $0) })

        for command in commands {
            if let rating = command.rating, !(0...5).contains(rating) {
                throw LibraryCommandError.invalidRating(rating)
            }
            guard papersByID[command.id] != nil else {
                throw LibraryCommandError.paperNotFound(command.id)
            }
        }

        for command in commands {
            guard let paper = papersByID[command.id] else { continue }

            if command.readingStatus != nil
                || command.rating != nil
                || !command.tagsToAdd.isEmpty
                || !command.tagsToRemove.isEmpty
                || command.publicationType != nil {
                try applyBatchEditUseCase.execute(
                    to: [paper],
                    status: command.readingStatus,
                    rating: command.rating ?? -1,
                    tagsToAdd: command.tagsToAdd,
                    tagsToRemove: command.tagsToRemove,
                    publicationType: command.publicationType
                )
            }

            if let flagged = command.flagged {
                try setFlagStateUseCase.execute(flagged: flagged, papers: [paper])
            }

            if let pinned = command.pinned {
                try setPinnedStateUseCase.execute(
                    pinned: pinned,
                    papers: [paper],
                    allPapers: allPapers
                )
            }
        }

        if viewContext.hasChanges {
            try viewContext.save()
        }
    }

    @discardableResult
    package func importPaper(_ command: ImportPaperCommand) async throws -> LibraryPaperDetail {
        let existingPapers = try loadLibraryPapersUseCase.fetchAllPapers()
        let receipt = try await importPaperFromPDFUseCase.execute(
            from: command.pdfURL,
            webpageMetadata: command.webpageMetadata,
            existingPapers: existingPapers,
            onStageChange: { _ in }
        )

        if receipt.shouldEnrich,
           let paper = try? resolvePaper(objectID: receipt.objectID) {
            await fetchPaperMetadataUseCase.execute(
                for: paper,
                forceVenueRefresh: true,
                onStageChange: { _ in }
            )
        }

        return Self.makeDetail(try resolvePaper(objectID: receipt.objectID))
    }

    @discardableResult
    package func queueImportPaper(
        _ command: ImportPaperCommand,
        onStageChange: @escaping (WorkflowStage) -> Void = { _ in }
    ) async throws -> LibraryPaperDetail {
        let existingPapers = try loadLibraryPapersUseCase.fetchAllPapers()
        let queuedImport = try await importPaperFromPDFUseCase.queue(
            from: command.pdfURL,
            webpageMetadata: command.webpageMetadata,
            existingPapers: existingPapers,
            onStageChange: onStageChange
        )
        importPaperFromPDFUseCase.cleanupQueuedArtifacts(queuedImport)
        return Self.makeDetail(try resolvePaper(objectID: queuedImport.objectID))
    }

    package func deletePaper(id: UUID) throws {
        try deletePapers(ids: [id])
    }

    package func deletePapers(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        let allPapers = try loadLibraryPapersUseCase.fetchAllPapers()
        let papersByID = Dictionary(uniqueKeysWithValues: allPapers.map { ($0.id, $0) })
        let papersToDelete = try ids.map { id -> Paper in
            guard let paper = papersByID[id] else {
                throw LibraryCommandError.paperNotFound(id)
            }
            return paper
        }

        try deletePapersUseCase.execute(papersToDelete)
    }

    package func deleteAllPapers() throws {
        try deletePapersUseCase.deleteAll()
    }

    @discardableResult
    package func refreshMetadata(
        id: UUID,
        onStageChange: @escaping (WorkflowStage) -> Void = { _ in }
    ) async throws -> LibraryPaperDetail {
        let paper = try resolvePaper(id: id)
        let receipt = await refreshPaperMetadataUseCase.execute(
            for: paper,
            onStageChange: onStageChange
        )

        if receipt.shouldEnrich,
           let refreshedPaper = try? resolvePaper(objectID: receipt.objectID) {
            await fetchPaperMetadataUseCase.execute(
                for: refreshedPaper,
                forceVenueRefresh: true,
                onStageChange: onStageChange
            )
        }

        return Self.makeDetail(try resolvePaper(objectID: receipt.objectID))
    }

    @discardableResult
    package func fetchMetadata(
        id: UUID,
        forceVenueRefresh: Bool = false,
        onStageChange: @escaping (WorkflowStage) -> Void = { _ in }
    ) async throws -> LibraryPaperDetail {
        let paper = try resolvePaper(id: id)
        await fetchPaperMetadataUseCase.execute(
            for: paper,
            forceVenueRefresh: forceVenueRefresh,
            onStageChange: onStageChange
        )
        return try getPaper(id: id)
    }

    package func applyMetadataCandidate(id: UUID, candidate: MetadataCandidate) async throws {
        let paper = try resolvePaper(id: id)
        await applyMetadataCandidateUseCase.execute(for: paper, candidate: candidate)
    }

    @discardableResult
    package func reextractMetadataSeed(id: UUID) async throws -> LibraryPaperDetail {
        let paper = try resolvePaper(id: id)
        try await reextractPaperSeedUseCase.execute(for: paper)

        if viewContext.hasChanges {
            try viewContext.save()
        }

        return try getPaper(id: id)
    }

    private func resolvePaper(id: UUID) throws -> Paper {
        let request: NSFetchRequest<Paper> = Paper.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        if let paper = try viewContext.fetch(request).first {
            return paper
        }
        throw LibraryCommandError.paperNotFound(id)
    }

    private func resolvePaper(objectID: NSManagedObjectID) throws -> Paper {
        guard let paper = try viewContext.existingObject(with: objectID) as? Paper else {
            throw LibraryCommandError.paperNotFound(UUID())
        }
        return paper
    }

    private static func makeDetail(_ paper: Paper) -> LibraryPaperDetail {
        LibraryPaperDetail(
            id: paper.id,
            title: paper.displayTitle,
            authors: paper.formattedAuthors,
            venue: paper.venue,
            year: Int(paper.year),
            doi: paper.doi,
            arxivId: paper.arxivId,
            abstract: paper.abstract,
            tags: paper.tagsList,
            flagged: paper.isFlagged,
            pinned: paper.isPinned,
            readingStatus: paper.currentReadingStatus.rawValue,
            rating: Int(paper.rating),
            filePath: paper.filePath,
            dateAdded: paper.dateAdded,
            dateModified: paper.dateModified
        )
    }
}
