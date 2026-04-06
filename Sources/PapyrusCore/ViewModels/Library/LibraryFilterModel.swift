import Combine
import Foundation

package enum PaperSortField: String, CaseIterable {
    case dateAdded = "Date Added"
    case year = "Year"
    case title = "Title"
    case citations = "Citations"
}

@MainActor
final class LibraryFilterModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var sortField: PaperSortField = .dateAdded
    @Published var sortAscending: Bool = false
    @Published var filterRankKeywords: Set<String> = []
    @Published var filterReadingStatus: Set<String> = []
    @Published var filterMinRating: Int = 0
    @Published var filterVenueAbbr: Set<String> = []
    @Published var filterYear: Set<Int> = []
    @Published var filterPublicationType: Set<String> = []
    @Published var filterTags: Set<String> = []
    @Published var filterFlaggedOnly = false

    var hasActiveFilters: Bool {
        !filterRankKeywords.isEmpty
            || !filterReadingStatus.isEmpty || filterMinRating > 0
            || !filterVenueAbbr.isEmpty || !filterYear.isEmpty
            || !filterPublicationType.isEmpty || !filterTags.isEmpty
            || filterFlaggedOnly
    }

    func clearFilters() {
        filterRankKeywords = []
        filterReadingStatus = []
        filterMinRating = 0
        filterVenueAbbr = []
        filterYear = []
        filterPublicationType = []
        filterTags = []
        filterFlaggedOnly = false
    }
}
