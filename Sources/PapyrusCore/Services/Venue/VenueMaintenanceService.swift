import Foundation
import CoreData

@MainActor
final class VenueMaintenanceService {
    private let viewContext: NSManagedObjectContext
    private let rankProvider: RankProviding
    private let venueAbbreviationProvider: VenueAbbreviationProviding

    init(
        viewContext: NSManagedObjectContext,
        rankProvider: RankProviding = JournalRankService.shared,
        venueAbbreviationProvider: VenueAbbreviationProviding = VenueAbbreviationService.shared
    ) {
        self.viewContext = viewContext
        self.rankProvider = rankProvider
        self.venueAbbreviationProvider = venueAbbreviationProvider
    }

    func findOrCreateVenue(for paper: Paper) {
        guard let venueName = paper.venue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !venueName.isEmpty else {
            paper.venueObject = nil
            return
        }

        let request: NSFetchRequest<Venue> = Venue.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", venueName)
        request.fetchLimit = 1

        let venue: Venue
        if let existing = (try? viewContext.fetch(request))?.first {
            venue = existing
        } else {
            let entity = NSEntityDescription.entity(forEntityName: "Venue", in: viewContext)!
            venue = Venue(entity: entity, insertInto: viewContext)
            venue.name = venueName
        }

        if let info = rankProvider.cached(venue: venueName) {
            venue.setRankSources(info.sources)
        }
        if let abbreviation = venueAbbreviationProvider.cached(venue: venueName) {
            venue.abbreviation = abbreviation
        } else {
            let formatted = VenueFormatter.abbreviate(venueName)
            if formatted != venueName { venue.abbreviation = formatted }
        }

        paper.venueObject = venue
    }
    func refreshAllVenueRankings(onComplete: @escaping () -> Void) {
        Task {
            let request: NSFetchRequest<Venue> = Venue.fetchRequest()
            guard let venues = try? viewContext.fetch(request), !venues.isEmpty else {
                await MainActor.run { onComplete() }
                return
            }

            for venue in venues {
                let name = venue.name
                await rankProvider.fetchForce(venue: name)
                if let info = rankProvider.cached(venue: name) {
                    venue.setRankSources(info.sources)
                }
                await venueAbbreviationProvider.fetchFromDBLPIfNeeded(venue: name)
                if let abbreviation = venueAbbreviationProvider.cached(venue: name) {
                    venue.abbreviation = abbreviation
                }
            }

            try? viewContext.save()
            print("[Venue refresh] Updated rankings for \(venues.count) venues")
            await MainActor.run { onComplete() }
        }
    }
}
