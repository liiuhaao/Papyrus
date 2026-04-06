import CoreData
import Foundation

@MainActor
final class DeletePapersUseCase {
    private let mutationService: PaperMutationService

    init(mutationService: PaperMutationService) {
        self.mutationService = mutationService
    }

    func execute(_ paper: Paper) throws {
        try mutationService.deletePaper(paper)
    }

    func execute(_ papers: [Paper]) throws {
        try mutationService.deletePapers(papers)
    }

    func deleteAll() throws {
        try mutationService.deleteAllPapers()
    }
}

@MainActor
final class RefreshPaperMetadataUseCase {
    private let mutationService: PaperMutationService

    init(mutationService: PaperMutationService) {
        self.mutationService = mutationService
    }

    func execute(
        for paper: Paper,
        onStageChange: @escaping (WorkflowStage) -> Void
    ) async -> PaperMutationService.MetadataRefreshReceipt {
        await mutationService.refreshMetadata(for: paper, onStageChange: onStageChange)
    }
}

@MainActor
final class FetchPaperMetadataUseCase {
    private let mutationService: PaperMutationService

    init(mutationService: PaperMutationService) {
        self.mutationService = mutationService
    }

    func execute(
        for paper: Paper,
        forceVenueRefresh: Bool = false,
        onStageChange: @escaping (WorkflowStage) -> Void
    ) async {
        await mutationService.fetchResolvedMetadata(
            for: paper,
            forceVenueRefresh: forceVenueRefresh,
            onStageChange: onStageChange
        )
    }
}

@MainActor
final class ReextractPaperSeedUseCase {
    private let mutationService: PaperMutationService

    init(mutationService: PaperMutationService) {
        self.mutationService = mutationService
    }

    func execute(for paper: Paper) async throws {
        _ = try await mutationService.reextractSourceSeed(for: paper)
    }
}

@MainActor
final class SetPinnedStateUseCase {
    private let viewContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }

    func execute(pinned: Bool, papers: [Paper], allPapers: [Paper]) throws {
        guard !papers.isEmpty else { return }

        var nextOrder = nextPinOrder(in: allPapers)
        for paper in papers {
            if pinned {
                if !paper.isPinned {
                    paper.isPinned = true
                    paper.pinOrder = nextOrder
                    nextOrder += 1
                }
            } else {
                paper.isPinned = false
                paper.pinOrder = 0
            }
            paper.dateModified = Date()
        }

        try viewContext.save()
    }

    private func nextPinOrder(in papers: [Paper]) -> Int32 {
        let maxOrder = papers.filter(\.isPinned).map(\.pinOrder).max() ?? -1
        return maxOrder + 1
    }
}

@MainActor
final class SetFlagStateUseCase {
    private let viewContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }

    func execute(flagged: Bool, papers: [Paper]) throws {
        guard !papers.isEmpty else { return }

        for paper in papers {
            paper.isFlagged = flagged
            paper.dateModified = Date()
        }

        try viewContext.save()
    }
}

@MainActor
final class ReorderPinnedPapersUseCase {
    private let viewContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }

    func execute(
        from source: IndexSet,
        to destination: Int,
        visiblePinned: [Paper],
        allPapers: [Paper]
    ) throws {
        guard !source.isEmpty else { return }

        let fullPinned = allPapers.filter(\.isPinned).sorted { $0.pinOrder < $1.pinOrder }
        let visibleIDs = Set(visiblePinned.map(\.objectID))
        let visibleOnly = fullPinned.filter { visibleIDs.contains($0.objectID) }
        guard !visibleOnly.isEmpty else { return }

        var updatedVisible = visibleOnly
        updatedVisible.move(fromOffsets: source, toOffset: destination)

        let updatedIDs = Set(updatedVisible.map(\.objectID))
        let visibleQueue = Array(updatedVisible)
        var visibleIndex = 0

        var rebuilt: [Paper] = []
        rebuilt.reserveCapacity(fullPinned.count)
        for paper in fullPinned {
            if updatedIDs.contains(paper.objectID) {
                rebuilt.append(visibleQueue[visibleIndex])
                visibleIndex += 1
            } else {
                rebuilt.append(paper)
            }
        }

        for (index, paper) in rebuilt.enumerated() {
            paper.pinOrder = Int32(index)
        }

        try viewContext.save()
    }
}

@MainActor
final class ApplyBatchEditUseCase {
    private let mutationService: PaperMutationService

    init(mutationService: PaperMutationService) {
        self.mutationService = mutationService
    }

    func execute(
        to papers: [Paper],
        status: Paper.ReadingStatus?,
        rating: Int,
        tagsToAdd: Set<String>,
        tagsToRemove: Set<String>,
        publicationType: String?
    ) throws {
        try mutationService.applyBatchEdit(
            to: papers,
            status: status,
            rating: rating,
            tagsToAdd: tagsToAdd,
            tagsToRemove: tagsToRemove,
            publicationType: publicationType
        )
    }
}
