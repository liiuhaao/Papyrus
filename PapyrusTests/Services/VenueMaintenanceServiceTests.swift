import CoreData
import Testing
@testable import PapyrusCore

final class MockRankProvider: RankProviding {
    var cachedValues: [String: JournalRankInfo] = [:]
    var fetchIfNeededCalls: [String] = []
    var fetchForceCalls: [String] = []

    func cached(venue: String) -> JournalRankInfo? {
        cachedValues[venue.lowercased()]
    }

    func fetchIfNeeded(venue: String) async {
        fetchIfNeededCalls.append(venue)
    }

    func fetchForce(venue: String) async {
        fetchForceCalls.append(venue)
    }
}

final class MockVenueAbbreviationProvider: VenueAbbreviationProviding {
    var cachedValues: [String: String] = [:]
    var fetchCalls: [String] = []

    func cached(venue: String) -> String? {
        cachedValues[venue.lowercased()]
    }

    func fetchFromDBLPIfNeeded(venue: String) async {
        fetchCalls.append(venue)
    }
}

struct VenueMaintenanceServiceTests {
    @MainActor
    @Test
    func findOrCreateVenueUsesCachedRankAndAbbreviation() throws {
        let context = TestSupport.makeInMemoryContext()
        let paper = TestSupport.makePaper(in: context, title: "Paper")
        paper.venue = "International Conference on Machine Learning"

        let rankProvider = MockRankProvider()
        rankProvider.cachedValues["international conference on machine learning"] =
            JournalRankInfo(sources: ["ccf": "A"])

        let abbrProvider = MockVenueAbbreviationProvider()
        abbrProvider.cachedValues["international conference on machine learning"] = "ICML"

        let service = VenueMaintenanceService(
            viewContext: context,
            rankProvider: rankProvider,
            venueAbbreviationProvider: abbrProvider
        )

        service.findOrCreateVenue(for: paper)

        let venue = try #require(paper.venueObject)
        #expect(venue.name == "International Conference on Machine Learning")
        #expect(venue.abbreviation == "ICML")
        #expect(venue.rankSources["ccf"] == "A")
    }

    @MainActor
    @Test
    func findOrCreateVenueReusesExistingVenueRecord() throws {
        let context = TestSupport.makeInMemoryContext()
        let existingVenue = TestSupport.makeVenue(
            in: context,
            name: "Conference on Neural Information Processing Systems",
            abbreviation: "NeurIPS",
            rankSources: ["ccf": "A"]
        )
        let firstPaper = TestSupport.makePaper(in: context, title: "First")
        firstPaper.venue = existingVenue.name
        firstPaper.venueObject = existingVenue

        let secondPaper = TestSupport.makePaper(in: context, title: "Second")
        secondPaper.venue = existingVenue.name
        try context.save()

        let service = VenueMaintenanceService(
            viewContext: context,
            rankProvider: MockRankProvider(),
            venueAbbreviationProvider: MockVenueAbbreviationProvider()
        )

        service.findOrCreateVenue(for: secondPaper)

        #expect(secondPaper.venueObject?.objectID == existingVenue.objectID)

        let request: NSFetchRequest<Venue> = Venue.fetchRequest()
        let venues = try context.fetch(request)
        #expect(venues.count == 1)
    }

    @MainActor
    @Test
    func findOrCreateVenueFallsBackToFormatterAbbreviationWhenCacheMissing() throws {
        let context = TestSupport.makeInMemoryContext()
        let paper = TestSupport.makePaper(in: context, title: "Paper")
        paper.venue = "International Conference on Learning Representations"

        let service = VenueMaintenanceService(
            viewContext: context,
            rankProvider: MockRankProvider(),
            venueAbbreviationProvider: MockVenueAbbreviationProvider()
        )

        service.findOrCreateVenue(for: paper)

        let venue = try #require(paper.venueObject)
        #expect(venue.abbreviation == "ICLR")
    }

    @MainActor
    @Test
    func findOrCreateVenueDoesNothingForEmptyVenueName() {
        let context = TestSupport.makeInMemoryContext()
        let paper = TestSupport.makePaper(in: context, title: "Paper")
        paper.venue = ""

        let service = VenueMaintenanceService(
            viewContext: context,
            rankProvider: MockRankProvider(),
            venueAbbreviationProvider: MockVenueAbbreviationProvider()
        )

        service.findOrCreateVenue(for: paper)

        #expect(paper.venueObject == nil)
    }

    @MainActor
    @Test
    func findOrCreateVenueClearsExistingVenueWhenVenueNameIsRemoved() throws {
        let context = TestSupport.makeInMemoryContext()
        let existingVenue = TestSupport.makeVenue(
            in: context,
            name: "International Conference on Machine Learning",
            abbreviation: "ICML",
            rankSources: ["ccf": "A"]
        )
        let paper = TestSupport.makePaper(in: context, title: "Paper")
        paper.venue = existingVenue.name
        paper.venueObject = existingVenue
        try context.save()

        let service = VenueMaintenanceService(
            viewContext: context,
            rankProvider: MockRankProvider(),
            venueAbbreviationProvider: MockVenueAbbreviationProvider()
        )

        paper.venue = "  "
        service.findOrCreateVenue(for: paper)

        #expect(paper.venueObject == nil)
    }

    @MainActor
    @Test
    func refreshAllVenueRankingsRefreshesExistingVenueObjects() async throws {
        let context = TestSupport.makeInMemoryContext()
        let venue = TestSupport.makeVenue(
            in: context,
            name: "International Conference on Learning Representations"
        )
        try context.save()

        let rankProvider = MockRankProvider()
        rankProvider.cachedValues["international conference on learning representations"] =
            JournalRankInfo(sources: ["core": "A*"])

        let abbrProvider = MockVenueAbbreviationProvider()
        abbrProvider.cachedValues["international conference on learning representations"] = "ICLR"

        let service = VenueMaintenanceService(
            viewContext: context,
            rankProvider: rankProvider,
            venueAbbreviationProvider: abbrProvider
        )

        await withCheckedContinuation { continuation in
            service.refreshAllVenueRankings {
                continuation.resume()
            }
        }

        #expect(rankProvider.fetchForceCalls == ["International Conference on Learning Representations"])
        #expect(abbrProvider.fetchCalls == ["International Conference on Learning Representations"])
        #expect(venue.abbreviation == "ICLR")
        #expect(venue.rankSources["core"] == "A*")
    }
}
