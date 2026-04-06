import AppKit
import Foundation

@MainActor
final class RefreshVenueRankingsUseCase {
    private let venueMaintenanceService: VenueMaintenanceService

    init(venueMaintenanceService: VenueMaintenanceService) {
        self.venueMaintenanceService = venueMaintenanceService
    }

    func execute(onComplete: @escaping () -> Void) {
        venueMaintenanceService.refreshAllVenueRankings(onComplete: onComplete)
    }
}

@MainActor
final class OpenPaperPDFUseCase {
    func execute(_ paper: Paper) {
        guard let filePath = paper.filePath else { return }
        let fileURL = URL(fileURLWithPath: filePath)
        switch AppConfig.shared.pdfOpenMode {
        case .defaultApp:
            NSWorkspace.shared.open(fileURL)
        case .customApp:
            let appPath = AppConfig.shared.pdfOpenAppPath
            guard !appPath.isEmpty else {
                NSWorkspace.shared.open(fileURL)
                return
            }
            NSWorkspace.shared.open(
                [fileURL],
                withApplicationAt: URL(fileURLWithPath: appPath),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }
}

@MainActor
final class ShowPaperInFinderUseCase {
    func execute(_ paper: Paper) {
        guard let filePath = paper.filePath else { return }
        let url = URL(fileURLWithPath: filePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

@MainActor
final class ExportLibraryUseCase {
    func exportBibTeX(_ papers: [Paper]) -> String {
        PaperExportService.exportBibTeX(papers)
    }

    func exportCSV(_ papers: [Paper]) -> String {
        PaperExportService.exportCSV(papers)
    }
}
