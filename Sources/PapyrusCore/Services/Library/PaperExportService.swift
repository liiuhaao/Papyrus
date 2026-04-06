import Foundation

enum PaperExportService {
    static func exportBibTeX(_ papers: [Paper]) -> String {
        papers.map { bibTeXEntry(for: $0) }.joined(separator: "\n\n")
    }

    static func exportCSV(_ papers: [Paper]) -> String {
        let header = "Title,Authors,Year,Venue,DOI,arXiv,Rating,Status,Tags"
        let rows = papers.map { paper -> String in
            let title = csvEscape(paper.title ?? "")
            let authors = csvEscape(paper.authors ?? "")
            let year = paper.year > 0 ? String(paper.year) : ""
            let venue = csvEscape(paper.venue ?? "")
            let doi = csvEscape(paper.doi ?? "")
            let arxiv = csvEscape(paper.arxivId ?? "")
            let rating = paper.rating > 0 ? String(paper.rating) : ""
            let status = paper.currentReadingStatus.rawValue
            let tags = csvEscape(paper.tagsList.joined(separator: "; "))
            return [title, authors, year, venue, doi, arxiv, rating, status, tags].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private static func bibTeXEntry(for paper: Paper) -> String {
        let authors = paper.authors ?? ""
        let lastName = (authors.components(separatedBy: ",").first ?? authors)
            .components(separatedBy: " ")
            .last ?? "unknown"
        let year = paper.year > 0 ? String(paper.year) : "0000"
        let slug = (paper.title ?? "")
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(3)
            .joined()
        let key = "\(lastName.lowercased())\(year)\(slug)"

        var lines = ["@article{\(key),"]
        if let title = paper.title, !title.isEmpty { lines.append("  title     = {\(title)},") }
        if !authors.isEmpty { lines.append("  author    = {\(authors)},") }
        if paper.year > 0 { lines.append("  year      = {\(paper.year)},") }
        if let venue = paper.venue, !venue.isEmpty { lines.append("  journal   = {\(venue)},") }
        if let doi = paper.doi, !doi.isEmpty { lines.append("  doi       = {\(doi)},") }
        if let arxivId = paper.arxivId, !arxivId.isEmpty {
            lines.append("  eprint    = {\(arxivId)},\n  archivePrefix = {arXiv},")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private static func csvEscape(_ string: String) -> String {
        guard string.contains(",") || string.contains("\"") || string.contains("\n") else { return string }
        return "\"" + string.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
