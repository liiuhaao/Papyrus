import Foundation

@MainActor
final class ImportPaperFromPDFUseCase {
    private let importService: PaperImportService

    init(importService: PaperImportService) {
        self.importService = importService
    }

    func execute(
        from url: URL,
        webpageMetadata: WebpageMetadata? = nil,
        existingPapers: [Paper],
        onStageChange: @escaping (WorkflowStage) -> Void,
        onPaperChanged: @escaping PaperImportService.PaperChangeHandler = { _ in }
    ) async throws -> PaperImportService.ImportReceipt {
        try await importService.importPDF(
            from: url,
            webpageMetadata: webpageMetadata,
            existingPapers: existingPapers,
            onStageChange: onStageChange,
            onPaperChanged: onPaperChanged
        )
    }

    func queue(
        from url: URL,
        webpageMetadata: WebpageMetadata? = nil,
        existingPapers: [Paper],
        onStageChange: @escaping (WorkflowStage) -> Void
    ) async throws -> PaperImportService.QueuedImport {
        try await importService.queuePDFImport(
            from: url,
            webpageMetadata: webpageMetadata,
            existingPapers: existingPapers,
            onStageChange: onStageChange
        )
    }

    func completeQueued(
        _ queuedImport: PaperImportService.QueuedImport,
        existingPapers: [Paper],
        onStageChange: @escaping (WorkflowStage) -> Void,
        onPaperChanged: @escaping PaperImportService.PaperChangeHandler = { _ in }
    ) async throws -> PaperImportService.ImportReceipt {
        try await importService.completeQueuedImport(
            queuedImport,
            existingPapers: existingPapers,
            onStageChange: onStageChange,
            onPaperChanged: onPaperChanged
        )
    }

    func cleanupQueuedArtifacts(_ queuedImport: PaperImportService.QueuedImport) {
        importService.cleanupQueuedImportArtifacts(queuedImport)
    }
}
