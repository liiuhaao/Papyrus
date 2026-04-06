import Foundation

enum MetadataBibTeXSupport {
    static func constructBibTeX(for paper: Paper) -> String {
        let authors = paper.authors ?? ""
        let firstAuthorLast = authors
            .components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").last ?? "unknown"
        let year = paper.year > 0 ? "\(paper.year)" : "????"
        let titleWord = (paper.title ?? "paper")
            .components(separatedBy: .whitespaces)
            .first(where: { $0.count > 3 })?
            .lowercased() ?? "paper"
        let key = "\(firstAuthorLast.lowercased())\(year)\(titleWord)"

        let hasVenue = paper.venue != nil && !(paper.venue!.isEmpty)
        let entryType = hasVenue ? "inproceedings" : "article"

        var lines = ["@\(entryType){\(key),"]
        lines.append("  title     = {\(paper.title ?? "")},")
        lines.append("  author    = {\(bibAuthors(authors))},")
        if let venue = paper.venue, !venue.isEmpty {
            let field = entryType == "inproceedings" ? "booktitle" : "journal"
            lines.append("  \(field.padding(toLength: 9, withPad: " ", startingAt: 0)) = {\(venue)},")
        }
        lines.append("  year      = {\(year)},")
        if let arxiv = paper.arxivId, !arxiv.isEmpty {
            lines.append("  eprint    = {\(arxiv)},")
            lines.append("  archivePrefix = {arXiv},")
        }
        if let doi = paper.doi, !doi.isEmpty {
            lines.append("  doi       = {\(doi)},")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private static func bibAuthors(_ authors: String) -> String {
        authors.components(separatedBy: ", ").map { name in
            let parts = name.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            guard parts.count >= 2, let last = parts.last else { return name }
            return "\(last), \(parts.dropLast().joined(separator: " "))"
        }.joined(separator: " and ")
    }
}
