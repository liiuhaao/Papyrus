import CoreData
import Foundation

@MainActor
final class LoadLibraryPapersUseCase {
    private let viewContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }

    func fetchAllPapers() throws -> [Paper] {
        let request: NSFetchRequest<Paper> = Paper.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Paper.dateAdded, ascending: false)]
        request.fetchBatchSize = 50
        return try viewContext.fetch(request)
    }

    func fetchFilteredPapers(state: PaperFilterState) throws -> [Paper] {
        let request = PaperQueryService.buildFilteredFetchRequest(state: state)
        return try viewContext.fetch(request)
    }

    func filterPapers(
        allPapers: [Paper],
        state: PaperFilterState,
        visibleRankSourceKeys: [String]
    ) -> [Paper] {
        let query = PaperQueryService.parseSearch(state.searchText)
        let structured = PaperQueryService.applyStructuredFilters(
            papers: allPapers,
            state: state
        )
        let searched = query.isEmpty
            ? PaperQueryService.sortPapers(
                structured,
                sortField: state.sortField,
                sortAscending: state.sortAscending
            )
            : PaperQueryService.applySearch(
                papers: structured,
                query: query,
                sortField: state.sortField,
                sortAscending: state.sortAscending
            )
        if state.filterRankKeywords.isEmpty {
            return searched
        }
        return searched.filter { paper in
            guard let venue = paper.venueObject else { return false }
            let labels = Set(venue.orderedRankEntries(visibleSourceKeys: visibleRankSourceKeys).map { key, value in
                RankSourceConfig.displayLabel(for: key, value: value)
            })
            return !labels.isDisjoint(with: state.filterRankKeywords)
        }
    }
}

@MainActor
final class MaintainVenuesUseCase {
    private let venueMaintenanceService: VenueMaintenanceService

    init(venueMaintenanceService: VenueMaintenanceService) {
        self.venueMaintenanceService = venueMaintenanceService
    }

    func findOrCreateVenue(for paper: Paper) {
        venueMaintenanceService.findOrCreateVenue(for: paper)
    }
}
