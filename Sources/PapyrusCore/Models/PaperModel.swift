// PaperModel.swift
// Paper entity - Swift class for Core Data

import Foundation
import CoreData

@objc(Paper)
public class Paper: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Paper> {
        return NSFetchRequest<Paper>(entityName: "Paper")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var notes: String?
    @NSManaged public var enrichStatus: String?
    @NSManaged public var title: String?
    @NSManaged public var authors: String?
    @NSManaged public var venue: String?
    @NSManaged public var year: Int16
    @NSManaged public var doi: String?
    @NSManaged public var arxivId: String?
    @NSManaged public var seedTitle: String?
    @NSManaged public var seedAuthors: String?
    @NSManaged public var seedVenue: String?
    @NSManaged public var seedYear: Int16
    @NSManaged public var seedDOI: String?
    @NSManaged public var seedArxivId: String?
    @NSManaged public var seedAbstract: String?
    @NSManaged public var seedPublicationType: String?
    @NSManaged public var resolvedTitle: String?
    @NSManaged public var resolvedAuthors: String?
    @NSManaged public var resolvedVenue: String?
    @NSManaged public var resolvedYear: Int16
    @NSManaged public var resolvedDOI: String?
    @NSManaged public var resolvedArxivId: String?
    @NSManaged public var resolvedAbstract: String?
    @NSManaged public var resolvedPublicationType: String?
    @NSManaged public var resolvedCitationCount: Int32
    @NSManaged public var filePath: String?
    @NSManaged public var originalFilename: String?
    @NSManaged public var dateAdded: Date
    @NSManaged public var dateModified: Date
    @NSManaged public var abstract: String?
    @NSManaged public var tags: String?
    @NSManaged public var isFlagged: Bool
    @NSManaged public var isPinned: Bool
    @NSManaged public var readingStatus: String?
    @NSManaged public var rating: Int16
    @NSManaged public var citationCount: Int32
    @NSManaged public var pinOrder: Int32
    @NSManaged public var titleManual: Bool
    @NSManaged public var authorsManual: Bool
    @NSManaged public var venueManual: Bool
    @NSManaged public var yearManual: Bool
    @NSManaged public var doiManual: Bool
    @NSManaged public var arxivManual: Bool
    @NSManaged public var publicationType: String?
    @NSManaged public var publicationTypeManual: Bool
    @NSManaged public var venueObject: Venue?
}

extension Paper {
    package enum ReadingStatus: String, CaseIterable {
        case unread
        case reading
        case read

        package var label: String {
            switch self {
            case .unread: return "Unread"
            case .reading: return "Reading"
            case .read: return "Read"
            }
        }
    }

    @objc var displayTitle: String {
        return title ?? resolvedTitle ?? seedTitle ?? originalFilename ?? "Untitled Paper"
    }

    @objc var formattedAuthors: String {
        return authors ?? resolvedAuthors ?? seedAuthors ?? "Unknown Authors"
    }

    var currentReadingStatus: ReadingStatus {
        if let raw = readingStatus?.lowercased(), let status = ReadingStatus(rawValue: raw) {
            return status
        }
        return .unread
    }

    func setReadingStatus(_ status: ReadingStatus) {
        readingStatus = status.rawValue
    }

    func cycleReadingStatus() {
        switch currentReadingStatus {
        case .unread: setReadingStatus(.reading)
        case .reading: setReadingStatus(.read)
        case .read: setReadingStatus(.unread)
        }
    }

    func toggleFlag() {
        isFlagged.toggle()
    }

    var tagsList: [String] {
        Self.parseTags(tags)
    }

    var citationCountText: String {
        citationCount >= 0 ? "\(citationCount)" : "—"
    }

    static func parseTags(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func normalizedTagsString(from raw: String) -> String? {
        let tags = parseTags(raw)
        guard !tags.isEmpty else { return nil }

        var seen = Set<String>()
        var ordered: [String] = []
        for tag in tags {
            let key = tag.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                ordered.append(tag)
            }
        }
        return ordered.joined(separator: ", ")
    }

    var refreshMetadataSeed: MetadataSeed {
        MetadataSeed(
            title: titleManual ? title : (seedTitle ?? title),
            titleCandidates: [
                titleManual ? title : (seedTitle ?? title)
            ].compactMap { $0 },
            authors: authorsManual ? authors : (seedAuthors ?? authors),
            doi: doiManual ? doi : (seedDOI ?? doi),
            arxivId: arxivManual ? arxivId : (seedArxivId ?? arxivId),
            abstract: seedAbstract ?? abstract,
            venue: venueManual ? venue : (seedVenue ?? venue),
            year: yearManual ? year : (seedYear > 0 ? seedYear : year),
            originalFilename: originalFilename
        )
    }

    func applySourceSeed(
        title: String?,
        authors: String?,
        venue: String?,
        year: Int16,
        doi: String?,
        arxivId: String?,
        abstract: String?,
        publicationType: String?,
        updateDisplayedFields: Bool
    ) {
        seedTitle = MetadataNormalization.normalizeTitle(title)
        seedAuthors = MetadataNormalization.normalizedAuthorsString(authors)
        seedVenue = MetadataNormalization.normalizeVenue(venue)
        seedYear = max(0, year)
        seedDOI = MetadataNormalization.normalizedDOI(doi)
        seedArxivId = Self.normalizedArxivID(arxivId)
        seedAbstract = MetadataNormalization.normalizeAbstract(abstract)
        seedPublicationType = Self.normalizedPublicationType(publicationType)

        if updateDisplayedFields {
            if !titleManual { self.title = seedTitle }
            if !authorsManual { self.authors = seedAuthors }
            if !venueManual { self.venue = seedVenue }
            if !yearManual { self.year = seedYear }
            if !doiManual { self.doi = seedDOI }
            if !arxivManual { self.arxivId = seedArxivId }
            self.abstract = seedAbstract
            if !publicationTypeManual { self.publicationType = seedPublicationType }
        }
    }

    func resetResolvedMetadata() {
        resolvedTitle = nil
        resolvedAuthors = nil
        resolvedVenue = nil
        resolvedYear = 0
        resolvedDOI = nil
        resolvedArxivId = nil
        resolvedAbstract = nil
        resolvedPublicationType = nil
        resolvedCitationCount = -1
    }

    func applyMetadataEdit(
        title: String?,
        authors: String?,
        venue: String?,
        year: Int16,
        doi: String?,
        arxivId: String?,
        publicationType: String?,
        isManual: Bool
    ) {
        if isManual {
            self.title = MetadataNormalization.normalizeTitle(title)
            self.authors = MetadataNormalization.normalizedAuthorsString(authors)
            self.venue = MetadataNormalization.normalizeVenue(venue)
            self.year = max(0, year)
            self.doi = MetadataNormalization.normalizedDOI(doi)
            self.arxivId = Self.normalizedArxivID(arxivId)
            self.publicationType = Self.normalizedPublicationType(publicationType)
            titleManual = true
            authorsManual = true
            venueManual = true
            yearManual = true
            doiManual = true
            arxivManual = true
            publicationTypeManual = true
        } else {
            titleManual = false
            authorsManual = false
            venueManual = false
            yearManual = false
            doiManual = false
            arxivManual = false
            publicationTypeManual = false
            applySourceSeed(
                title: title,
                authors: authors,
                venue: venue,
                year: year,
                doi: doi,
                arxivId: arxivId,
                abstract: seedAbstract,
                publicationType: publicationType,
                updateDisplayedFields: true
            )
        }
        dateModified = Date()
        try? managedObjectContext?.save()
    }

    private static func normalizedArxivID(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let value = raw
            .replacingOccurrences(of: "https://arxiv.org/abs/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://arxiv.org/abs/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "https://arxiv.org/pdf/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://arxiv.org/pdf/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "arxiv:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalizedPublicationType(_ raw: String?) -> String? {
        let value = raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
