import Foundation

enum PaperCitationStyle {
    case gbt7714
    case apa
    case mla

    var label: String {
        switch self {
        case .gbt7714: return "GB/T 7714"
        case .apa: return "APA"
        case .mla: return "MLA"
        }
    }
}

enum PaperCitationSupport {
    private struct ParsedAuthor {
        let first: String
        let last: String
        let full: String

        var initials: String {
            let parts = first.split(separator: " ").filter { !$0.isEmpty }
            let letters = parts.compactMap { $0.first }
            return letters.map { "\($0)." }.joined(separator: " ")
        }

        var lastFirst: String {
            guard !first.isEmpty else { return last }
            return "\(last), \(first)"
        }

        var lastInitial: String {
            let initials = self.initials
            guard !initials.isEmpty else { return last }
            return "\(last), \(initials)"
        }
    }

    static func normalizeBibTeX(_ bib: String, for paper: Paper) -> String {
        let (entryType, venueField) = bibTeXEntryTypeAndVenueField(for: paper)
        let venue = venueText(for: paper)
        let fieldLine: String? = {
            guard let venue, !venue.isEmpty, let venueField else { return nil }
            return "  \(venueField) = {\(venue)},"
        }()

        let lines = bib.components(separatedBy: .newlines)
        var output: [String] = []
        var inserted = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("@"), let braceIndex = trimmed.firstIndex(of: "{") {
                let rest = trimmed[braceIndex...]
                output.append("@\(entryType)\(rest)")
                continue
            }
            if trimmed.lowercased().hasPrefix("journal")
                || trimmed.lowercased().hasPrefix("booktitle") {
                if let fieldLine, !inserted {
                    output.append(fieldLine)
                    inserted = true
                }
                continue
            }
            if trimmed == "}" && !inserted, let fieldLine {
                output.append(fieldLine)
                inserted = true
            }
            output.append(line)
        }
        return output.joined(separator: "\n")
    }

    static func formatCitation(for paper: Paper, style: PaperCitationStyle) -> String {
        let authors = parseAuthors(from: paper.authors)
        let authorsText = formatAuthors(authors, style: style)
        let yearText = paper.year > 0 ? "\(paper.year)" : "n.d."
        let rawTitle = paper.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty ? "Untitled Paper" : rawTitle
        let venue = venueText(for: paper)
        let doi = normalizedDOI(paper.doi)

        switch style {
        case .gbt7714:
            var parts: [String] = []
            if !authorsText.isEmpty { parts.append(ensureTrailingPeriod(authorsText)) }
            parts.append("\(title).")
            if let venue { parts.append("\(venue),") }
            parts.append(yearText + ".")
            var output = parts.joined(separator: " ")
            if let doi { output += " DOI: \(doi)." }
            return output
        case .apa:
            var parts: [String] = []
            if !authorsText.isEmpty { parts.append(authorsText) }
            parts.append("(\(yearText)).")
            parts.append("\(title).")
            if let venue { parts.append("\(venue).") }
            var output = parts.joined(separator: " ")
            if let doi { output += " https://doi.org/\(doi)" }
            return output
        case .mla:
            var output = ""
            if !authorsText.isEmpty { output += ensureTrailingPeriod(authorsText) + " " }
            output += "\"\(title).\""
            if let venue { output += " \(venue)," }
            output += paper.year > 0 ? " \(yearText)." : " n.d."
            if let doi { output += " https://doi.org/\(doi)." }
            return output
        }
    }

    static func bibTeXEntry(for paper: Paper) -> String {
        let authors = paper.authors ?? ""
        let lastName = (authors.components(separatedBy: ",").first ?? authors)
            .components(separatedBy: " ").last ?? "unknown"
        let year = paper.year > 0 ? String(paper.year) : "0000"
        let slug = (paper.title ?? "").lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(3)
            .joined()
        let key = "\(lastName.lowercased())\(year)\(slug)"
        let (entryType, venueField) = bibTeXEntryTypeAndVenueField(for: paper)

        var lines = ["@\(entryType){\(key),"]
        if let title = paper.title, !title.isEmpty { lines.append("  title     = {\(title)},") }
        if !authors.isEmpty { lines.append("  author    = {\(authors)},") }
        if paper.year > 0 { lines.append("  year      = {\(paper.year)},") }
        if let venue = venueText(for: paper), !venue.isEmpty, let venueField {
            lines.append("  \(venueField) = {\(venue)},")
        }
        if let doi = paper.doi, !doi.isEmpty { lines.append("  doi       = {\(doi)},") }
        if let arxivID = paper.arxivId, !arxivID.isEmpty {
            lines.append("  eprint    = {\(arxivID)},\n  archivePrefix = {arXiv},")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    static func scholarURL(for paper: Paper) -> URL? {
        let q = paper.doi.flatMap { $0.isEmpty ? nil : "doi:\($0)" }
            ?? paper.arxivId.flatMap { $0.isEmpty ? nil : "arxiv:\($0)" }
            ?? (paper.displayTitle.isEmpty ? nil : paper.displayTitle)
        guard let q else { return nil }
        return queryURL("https://scholar.google.com/scholar", q: q)
    }

    static func semanticScholarURL(for paper: Paper) -> URL? {
        let q = paper.doi.flatMap { $0.isEmpty ? nil : "DOI:\($0)" }
            ?? paper.arxivId.flatMap { $0.isEmpty ? nil : "arXiv:\($0)" }
            ?? (paper.displayTitle.isEmpty ? nil : paper.displayTitle)
        guard let q else { return nil }
        return queryURL("https://www.semanticscholar.org/search", q: q)
    }

    static func doiURL(for paper: Paper) -> URL? {
        guard let doi = paper.doi, !doi.isEmpty else { return nil }
        return URL(string: "https://doi.org/\(doi)")
    }

    static func arxivURL(for paper: Paper) -> URL? {
        guard let raw = paper.arxivId, !raw.isEmpty else { return nil }
        let id = raw
            .replacingOccurrences(of: "https://arxiv.org/abs/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "arxiv:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : URL(string: "https://arxiv.org/abs/\(id)")
    }

    static func dblpURL(for paper: Paper) -> URL? {
        let q = paper.doi.flatMap { $0.isEmpty ? nil : $0 }
            ?? paper.arxivId.flatMap { $0.isEmpty ? nil : $0 }
            ?? (paper.displayTitle.isEmpty ? nil : paper.displayTitle)
        guard let q else { return nil }
        return queryURL("https://dblp.org/search", q: q)
    }

    static func venueText(for paper: Paper) -> String? {
        let rawVenue = (paper.venueObject?.name ?? paper.venue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if rawVenue.isEmpty { return nil }
        let parts = VenueFormatter.resolvedVenueParts(rawVenue, abbreviation: paper.venueObject?.abbreviation)
        let fullTrimmed = parts.full.trimmingCharacters(in: .whitespacesAndNewlines)
        let abbrTrimmed = parts.abbr.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullValue = fullTrimmed.isEmpty ? nil : fullTrimmed
        let abbrValue = abbrTrimmed.isEmpty ? nil : abbrTrimmed
        if let fullValue, let abbrValue {
            return "\(fullValue) (\(abbrValue))"
        }
        return fullValue ?? abbrValue
    }

    private static func formatAuthors(_ authors: [ParsedAuthor], style: PaperCitationStyle) -> String {
        guard !authors.isEmpty else { return "" }
        switch style {
        case .gbt7714:
            if authors.count == 1 { return authors[0].full }
            if authors.count == 2 { return "\(authors[0].full), \(authors[1].full)" }
            return "\(authors[0].full), et al."
        case .apa:
            if authors.count == 1 { return authors[0].lastInitial }
            if authors.count == 2 { return "\(authors[0].lastInitial), & \(authors[1].lastInitial)" }
            return "\(authors[0].lastInitial), et al."
        case .mla:
            if authors.count == 1 { return authors[0].lastFirst }
            if authors.count == 2 { return "\(authors[0].lastFirst), and \(authors[1].full)" }
            return "\(authors[0].lastFirst), et al."
        }
    }

    private static func parseAuthors(from raw: String?) -> [ParsedAuthor] {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return [] }
        let normalized = raw.replacingOccurrences(of: " and ", with: ", ")
        let chunks = normalized
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return chunks.map { name in
            let parts = name.split(separator: " ").map(String.init)
            if parts.count <= 1 {
                return ParsedAuthor(first: "", last: name, full: name)
            }
            let last = parts.last ?? ""
            let first = parts.dropLast().joined(separator: " ")
            let full = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedAuthor(first: first, last: last, full: full.isEmpty ? name : full)
        }
    }

    private static func normalizedDOI(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: "https://doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "doi:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func ensureTrailingPeriod(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        return trimmed.hasSuffix(".") ? trimmed : trimmed + "."
    }

    private static func queryURL(_ base: String, q: String) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: q)]
        return components.url
    }

    private static func bibTeXEntryTypeAndVenueField(for paper: Paper) -> (String, String?) {
        let type = paper.publicationType?.lowercased()
        switch type {
        case "conference", "workshop":
            return ("inproceedings", "booktitle")
        case "chapter", "incollection":
            return ("incollection", "booktitle")
        case "book":
            return ("book", nil)
        case "journal", "preprint":
            return ("article", "journal")
        default:
            return ("article", "journal")
        }
    }
}
