import Foundation

enum MetadataParsers {
    static func parseArxivXML(_ xml: String) throws -> PaperMetadata {
        var metadata = PaperMetadata()

        guard let entryStart = xml.range(of: "<entry>", options: .caseInsensitive),
              let entryEnd = xml.range(of: "</entry>", options: .caseInsensitive) else {
            throw MetadataError.parseError
        }
        let entry = String(xml[entryStart.lowerBound..<entryEnd.upperBound])

        metadata.title = extractXMLElement(named: "title", from: entry)?
            .replacingOccurrences(of: "\n", with: " ").trimmed()
        metadata.abstract = extractXMLElement(named: "summary", from: entry)?.trimmed()

        var authors: [String] = []
        var searchRange = entry.startIndex..<entry.endIndex
        let nameOpen = "<name>"
        let nameClose = "</name>"
        while let openRange = entry.range(of: nameOpen, options: .caseInsensitive, range: searchRange),
              let closeRange = entry.range(of: nameClose, options: .caseInsensitive, range: openRange.upperBound..<entry.endIndex) {
            let name = String(entry[openRange.upperBound..<closeRange.lowerBound]).trimmed()
            if !name.isEmpty { authors.append(name) }
            searchRange = closeRange.upperBound..<entry.endIndex
        }
        if !authors.isEmpty { metadata.authors = authors.joined(separator: ", ") }

        if let published = extractXMLElement(named: "published", from: entry),
           let year = Int(published.prefix(4)) {
            metadata.year = Int16(year)
        }

        metadata.arxivId = extractArxivIDFromArxivEntry(entry)
        metadata.doi = normalizedDOI(
            extractXMLElement(named: "arxiv:doi", from: entry)
                ?? extractXMLElement(named: "doi", from: entry)
        )
        metadata.venue = cleanedVenue(
            extractXMLElement(named: "arxiv:journal_ref", from: entry)
                ?? extractXMLElement(named: "journal_ref", from: entry)
        )
        metadata.publicationType = inferPublicationType(
            venue: metadata.venue,
            doi: metadata.doi,
            arxivId: metadata.arxivId
        )
        if metadata.publicationType == nil {
            metadata.publicationType = "preprint"
        }

        return metadata
    }

    static func parseCrossRefJSON(_ json: [String: Any]) -> PaperMetadata {
        var metadata = PaperMetadata()
        metadata.title = (json["title"] as? [String])?.first
        metadata.doi = json["DOI"] as? String

        if let authors = json["author"] as? [[String: Any]] {
            let authorNames = authors.compactMap { author -> String? in
                let family = author["family"] as? String ?? ""
                let given = author["given"] as? String ?? ""
                return given.isEmpty ? family : "\(given) \(family)"
            }
            metadata.authors = MetadataNormalization.normalizedAuthors(authorNames).joined(separator: ", ")
        }

        if let container = json["container-title"] as? [String],
           let first = container.first {
            metadata.venue = first
        } else if let shortContainer = json["short-container-title"] as? [String],
                  let first = shortContainer.first {
            metadata.venue = first
        }

        if let published = json["published-print"] as? [String: Any],
           let dateParts = published["date-parts"] as? [[Int]],
           let year = dateParts.first?.first {
            metadata.year = Int16(year)
        } else if let published = json["published-online"] as? [String: Any],
                  let dateParts = published["date-parts"] as? [[Int]],
                  let year = dateParts.first?.first {
            metadata.year = Int16(year)
        }

        if let type = json["type"] as? String {
            if type.contains("proceedings") {
                metadata.publicationType = "conference"
            } else if type.contains("journal") {
                metadata.publicationType = "journal"
            }
        }
        if metadata.publicationType == nil {
            metadata.publicationType = inferPublicationType(
                venue: metadata.venue,
                doi: metadata.doi,
                arxivId: metadata.arxivId
            )
        }

        return metadata
    }

    static func parseOpenAlexWork(_ json: [String: Any]) -> PaperMetadata {
        var metadata = PaperMetadata()
        metadata.title = json["title"] as? String
        metadata.abstract = abstractFromOpenAlex(json["abstract_inverted_index"] as? [String: Any])

        if let publicationYear = json["publication_year"] as? Int {
            metadata.year = Int16(publicationYear)
        }

        if let authorships = json["authorships"] as? [[String: Any]] {
            let names = authorships.compactMap { authorship -> String? in
                guard let author = authorship["author"] as? [String: Any] else { return nil }
                return author["display_name"] as? String
            }
            if !names.isEmpty {
                metadata.authors = MetadataNormalization.normalizedAuthors(names).joined(separator: ", ")
            }
        }

        if let primaryLocation = json["primary_location"] as? [String: Any],
           let source = primaryLocation["source"] as? [String: Any] {
            let sourceType = source["type"] as? String
            let isPublished = primaryLocation["is_published"] as? Bool ?? true
            if sourceType != "repository" && isPublished {
                metadata.venue = source["display_name"] as? String
            }
        } else if let hostVenue = json["host_venue"] as? [String: Any] {
            metadata.venue = hostVenue["display_name"] as? String
        }

        if let ids = json["ids"] as? [String: Any] {
            metadata.doi = normalizedDOI(ids["doi"] as? String) ?? metadata.doi
        }
        if let locations = json["locations"] as? [[String: Any]] {
            for location in locations {
                if let landing = location["landing_page_url"] as? String,
                   let arxivId = extractArxivID(from: landing) {
                    metadata.arxivId = arxivId
                    break
                }
            }
        }
        metadata.publicationType = inferPublicationType(
            venue: metadata.venue,
            doi: metadata.doi,
            arxivId: metadata.arxivId
        )
        return metadata
    }

    static func parseDBLPHit(_ json: [String: Any]) -> PaperMetadata {
        var metadata = PaperMetadata()
        metadata.title = cleanedDBLPTitle(json["title"])?.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if let authors = json["authors"] as? [String: Any] {
            if let authorList = authors["author"] as? [String] {
                metadata.authors = MetadataNormalization.normalizedAuthors(authorList).joined(separator: ", ")
            } else if let authorList = authors["author"] as? [[String: Any]] {
                metadata.authors = MetadataNormalization.normalizedAuthors(
                    authorList.compactMap { $0["text"] as? String ?? $0["@text"] as? String }
                ).joined(separator: ", ")
            } else if let singleAuthor = authors["author"] as? String {
                metadata.authors = MetadataNormalization.normalizedAuthorName(singleAuthor)
            }
        }
        metadata.venue = cleanedVenue(json["venue"] as? String)
            ?? cleanedVenue(json["journal"] as? String)
            ?? cleanedVenue(json["booktitle"] as? String)
        if let yearString = json["year"] as? String, let year = Int16(yearString) {
            metadata.year = year
        } else if let year = json["year"] as? Int {
            metadata.year = Int16(year)
        }
        metadata.doi = normalizedDOI(json["doi"] as? String)
        if let url = json["url"] as? String {
            metadata.arxivId = extractArxivID(from: url)
        }
        // DBLP CoRR records often store the arXiv link in the 'ee' field.
        if metadata.arxivId == nil, let ee = json["ee"] as? String {
            metadata.arxivId = extractArxivID(from: ee)
        }
        metadata.publicationType = inferPublicationType(
            venue: metadata.venue,
            doi: metadata.doi,
            arxivId: metadata.arxivId
        )
        return metadata
    }

    static func parseOpenReviewNote(_ note: [String: Any]) throws -> PaperMetadata {
        guard let content = note["content"] as? [String: Any] else {
            throw MetadataError.parseError
        }

        var metadata = PaperMetadata()

        if let title = content["title"] as? [String: Any],
           let value = title["value"] as? String {
            metadata.title = value
        }

        if let authors = content["authors"] as? [String: Any],
           let value = authors["value"] as? [String] {
            metadata.authors = value.joined(separator: ", ")
        }

        if let abstract = content["abstract"] as? [String: Any],
           let value = abstract["value"] as? String {
            metadata.abstract = value
        }

        if let invitation = note["invitation"] as? String {
            metadata.venue = extractVenueFromOpenReview(invitation)
        }

        return metadata
    }

    static func parseOpenReviewSearchResult(_ note: [String: Any]) throws -> PaperMetadata {
        guard let content = note["content"] as? [String: Any] else {
            throw MetadataError.notFound
        }

        var metadata = PaperMetadata()

        func strVal(_ key: String) -> String? {
            if let obj = content[key] as? [String: Any] { return obj["value"] as? String }
            return content[key] as? String
        }
        func arrVal(_ key: String) -> [String]? {
            if let obj = content[key] as? [String: Any] { return obj["value"] as? [String] }
            return content[key] as? [String]
        }

        metadata.title = strVal("title")
        metadata.abstract = strVal("abstract")

        if let authors = arrVal("authors") {
            metadata.authors = MetadataNormalization.normalizedAuthors(authors).joined(separator: ", ")
        }

        if let venueid = note["domain"] as? String ?? strVal("venueid") {
            if venueid.contains("ICLR") {
                let year = venueid.components(separatedBy: "/").first(where: { $0.count == 4 && Int($0) != nil }) ?? ""
                metadata.venue = year.isEmpty ? "ICLR" : "ICLR \(year)"
            } else if let venue = strVal("venue") {
                metadata.venue = venue
            }
        } else if let venue = strVal("venue") {
            metadata.venue = venue
        }

        if metadata.year == 0, let venue = metadata.venue {
            let digits = venue.components(separatedBy: .whitespaces).first(where: { Int($0) != nil })
            if let year = digits.flatMap({ Int($0) }) {
                metadata.year = Int16(year)
            }
        }

        return metadata
    }

    static func parseSemanticScholarPaper(_ json: [String: Any]) -> PaperMetadata {
        var metadata = PaperMetadata()
        metadata.title = json["title"] as? String
        metadata.abstract = json["abstract"] as? String
        if let year = json["year"] as? Int { metadata.year = Int16(year) }
        if let count = json["citationCount"] as? Int {
            metadata.citationCount = Int32(count)
        }

        if let authors = json["authors"] as? [[String: Any]] {
            metadata.authors = MetadataNormalization.normalizedAuthors(
                authors.compactMap { $0["name"] as? String }
            ).joined(separator: ", ")
        }

        if let pubVenue = json["publicationVenue"] as? [String: Any],
           let name = pubVenue["name"] as? String {
            metadata.venue = name
            metadata.venueAcronym = pubVenue["acronym"] as? String
        } else {
            metadata.venue = json["venue"] as? String
        }
        metadata.publicationType = inferPublicationType(
            venue: metadata.venue,
            doi: metadata.doi,
            arxivId: metadata.arxivId
        )

        if let ids = json["externalIds"] as? [String: Any] {
            if metadata.doi == nil { metadata.doi = ids["DOI"] as? String }
            if metadata.arxivId == nil { metadata.arxivId = ids["ArXiv"] as? String }
        }

        return metadata
    }

    static func inferPublicationType(venue: String?, doi: String?, arxivId: String?) -> String? {
        let venueText = (venue ?? "").lowercased()
        let conferenceHints = ["conference", "symposium", "workshop", "proceedings", "neurips", "iclr", "icml", "cvpr", "iccv", "eccv", "acl", "emnlp", "naacl", "aaai", "ijcai"]
        let journalHints = ["journal", "transactions", "trans.", "letters", "review", "nature", "science", "communications"]
        let preprintHints = ["corr", "arxiv", "biorxiv", "medrxiv", "ssrn", "hal ", "preprint", "chemrxiv", "eartharxiv", "psyarxiv", "socarxiv"]

        if preprintHints.contains(where: { venueText.contains($0) }) { return "preprint" }
        if conferenceHints.contains(where: { venueText.contains($0) }) { return "conference" }
        if journalHints.contains(where: { venueText.contains($0) }) { return "journal" }
        if venueText.isEmpty, let doi, !doi.isEmpty { return "journal" }
        if let arxivId, !arxivId.isEmpty { return "preprint" }
        if venueText.isEmpty { return nil }
        return "other"
    }

    private static func extractXMLElement(named elementName: String, from xml: String) -> String? {
        let openTag = "<" + elementName
        guard let startRange = xml.range(of: openTag, options: .caseInsensitive) else {
            return nil
        }
        let afterOpen = xml[startRange.upperBound...]
        guard let closeBracket = afterOpen.firstIndex(of: ">") else {
            return nil
        }
        let contentStart = afterOpen.index(after: closeBracket)
        let remaining = xml[contentStart...]
        let closeTag = "</" + elementName
        guard let endRange = remaining.range(of: closeTag, options: .caseInsensitive) else {
            if let nextTag = remaining.firstIndex(of: "<") {
                let content = String(remaining[..<nextTag])
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let content = String(remaining[..<endRange.lowerBound])
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractVenueFromOpenReview(_ invitation: String) -> String? {
        let venues = ["ICLR", "NeurIPS", "ICML", "ACL", "EMNLP", "NAACL", "CVPR", "ICCV"]
        for venue in venues where invitation.uppercased().contains(venue.uppercased()) {
            return venue
        }
        return nil
    }

    private static func abstractFromOpenAlex(_ index: [String: Any]?) -> String? {
        guard let index, !index.isEmpty else { return nil }
        var positionedWords: [(Int, String)] = []
        for (word, positionsAny) in index {
            guard let positions = positionsAny as? [Int] else { continue }
            for position in positions {
                positionedWords.append((position, word))
            }
        }
        guard !positionedWords.isEmpty else { return nil }
        return positionedWords
            .sorted { $0.0 < $1.0 }
            .map(\.1)
            .joined(separator: " ")
    }

    private static func normalizedDOI(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
            .replacingOccurrences(of: "https://doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "doi:", with: "", options: .caseInsensitive)
    }

    private static func extractArxivID(from urlString: String) -> String? {
        let pattern = #"arxiv\.org/(?:abs|pdf)/([a-z\-]+/\d{7}|\d{4}\.\d{4,5})(?:v\d+)?(?:\.pdf)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
              let range = Range(match.range(at: 1), in: urlString) else {
            return nil
        }
        return String(urlString[range])
    }

    private static func extractArxivIDFromArxivEntry(_ entry: String) -> String? {
        let primaryID = extractXMLElement(named: "id", from: entry)
        if let primaryID, let extracted = extractArxivID(from: primaryID) {
            return extracted
        }
        return nil
    }

    private static func cleanedDBLPTitle(_ raw: Any?) -> String? {
        let value: String?
        if let raw = raw as? String {
            value = raw
        } else if let raw = raw as? [String: Any] {
            value = raw["text"] as? String ?? raw["@text"] as? String
        } else {
            value = nil
        }
        guard let value else { return nil }
        return nonEmpty(value
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.isEmpty ? nil : value
    }

    private static func cleanedVenue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return cleaned.isEmpty ? nil : cleaned
    }
}
