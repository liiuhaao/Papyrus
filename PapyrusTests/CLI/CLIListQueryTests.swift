import Foundation
import Testing
@testable import PapyrusCore

struct CLIListQueryTests {
    @Test
    func parseListQueryBuildsStructuredFilters() throws {
        let query = try CLISupport.parseListQuery([
            "list",
            "--query", "graph agents",
            "--status", "reading,read",
            "--tag", "agents,ml",
            "--year", "2024,2025",
            "--publication-type", "journal,conference",
            "--min-rating", "3",
            "--flagged", "true",
            "--pinned", "true",
            "--sort", "year",
            "--ascending", "true",
            "--limit", "5"
        ])

        #expect(query.searchText == "graph agents")
        #expect(query.readingStatuses == [Paper.ReadingStatus.reading.rawValue, Paper.ReadingStatus.read.rawValue])
        #expect(query.tags == ["agents", "ml"])
        #expect(query.years == [2024, 2025])
        #expect(query.publicationTypes == ["journal", "conference"])
        #expect(query.minRating == 3)
        #expect(query.flaggedOnly == true)
        #expect(query.pinnedOnly == true)
        #expect(query.sortField == .year)
        #expect(query.sortAscending == true)
        #expect(query.limit == 5)
    }

    @Test
    func parseListQueryRejectsInvalidSortField() {
        #expect(throws: CLISupport.CLIError.self) {
            _ = try CLISupport.parseListQuery([
                "list",
                "--sort", "random"
            ])
        }
    }
}
