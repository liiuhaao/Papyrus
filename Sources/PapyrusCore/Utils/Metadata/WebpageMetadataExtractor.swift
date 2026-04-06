import Foundation

package struct WebpageMetadata {
    package var title: String?
    package var authors: String?
    package var doi: String?
    package var arxivId: String?
    package var abstract: String?
    package var venue: String?
    package var year: Int16 = 0
    package var pdfURL: URL?
    package var sourceURL: URL?
}

enum WebpageMetadataExtractor {
    static func extract(from html: String, pageURL: URL) -> WebpageMetadata {
        var metadata = WebpageMetadata()
        metadata.sourceURL = pageURL
        applySiteSpecificMetadata(html: html, pageURL: pageURL, metadata: &metadata)
        applyJSONLDMetadata(html: html, metadata: &metadata)

        let metaTags = extractMetaTags(from: html)
        guard !metaTags.isEmpty else {
            metadata.doi = doiFromPageURL(pageURL)
            metadata.arxivId = arxivIDFromPageURL(pageURL)
            return metadata
        }

        var authors: [String] = []
        for tag in metaTags {
            let name = (tag["name"] ?? tag["property"] ?? "").lowercased()
            let content = (tag["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let scheme = (tag["scheme"] ?? "").lowercased()
            guard !content.isEmpty else { continue }

            switch name {
            case "citation_title", "dc.title", "og:title":
                if metadata.title == nil { metadata.title = content }
            case "citation_author", "dc.creator":
                authors.append(content)
            case "citation_publication_date", "citation_online_date", "dc.date", "article:published_time", "og:published_time":
                if metadata.year == 0, let year = parseYear(from: content) {
                    metadata.year = year
                }
            case "citation_doi", "publication_doi":
                if metadata.doi == nil {
                    metadata.doi = MetadataNormalization.normalizedDOI(content)
                }
            case "citation_conference_title", "citation_journal_title", "citation_journal_abbrev":
                if metadata.venue == nil { metadata.venue = content }
            case "citation_abstract", "description", "dc.description", "og:description":
                if metadata.abstract == nil { metadata.abstract = content }
            case "dc.identifier":
                if scheme == "doi", metadata.doi == nil {
                    metadata.doi = MetadataNormalization.normalizedDOI(content)
                }
            case "citation_pdf_url":
                if metadata.pdfURL == nil {
                    metadata.pdfURL = resolveURL(content, relativeTo: pageURL)
                }
            default:
                break
            }
        }

        if !authors.isEmpty {
            metadata.authors = authors.joined(separator: ", ")
        }
        if metadata.doi == nil {
            metadata.doi = doiFromPageURL(pageURL)
        }
        if metadata.arxivId == nil {
            metadata.arxivId = arxivIDFromPageURL(pageURL)
        }
        if metadata.pdfURL == nil, let doi = metadata.doi {
            metadata.pdfURL = inferredDOIPDFURL(from: pageURL, doi: doi)
        }
        if metadata.pdfURL == nil {
            metadata.pdfURL = inferredGenericPDFURL(from: html, relativeTo: pageURL)
        }
        if metadata.title == nil {
            metadata.title = extractHTMLTitle(from: html, suffixToStrip: siteTitleSuffix(for: pageURL))
        }

        return metadata
    }

    private static func applyJSONLDMetadata(html: String, metadata: inout WebpageMetadata) {
        let scripts = allCaptures(
            in: html,
            pattern: #"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        for script in scripts {
            guard let data = script.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            for object in flattenJSONLD(json) {
                if metadata.title == nil {
                    metadata.title = stringValue(for: "name", in: object) ?? stringValue(for: "headline", in: object)
                }
                if metadata.abstract == nil {
                    metadata.abstract = stringValue(for: "description", in: object)
                }
                if metadata.doi == nil {
                    metadata.doi = MetadataNormalization.normalizedDOI(stringValue(for: "doi", in: object))
                }
                if metadata.venue == nil {
                    metadata.venue = nestedStringValue(path: ["isPartOf", "name"], in: object)
                        ?? nestedStringValue(path: ["publication", "name"], in: object)
                }
                if metadata.year == 0,
                   let yearText = stringValue(for: "datePublished", in: object),
                   let year = parseYear(from: yearText) {
                    metadata.year = year
                }
                if metadata.authors == nil,
                   let authors = authorNames(in: object), !authors.isEmpty {
                    metadata.authors = authors.joined(separator: ", ")
                }
            }
        }
    }

    private static func applySiteSpecificMetadata(html: String, pageURL: URL, metadata: inout WebpageMetadata) {
        let host = pageURL.host?.lowercased() ?? ""
        if host.contains("ieeexplore.ieee.org") {
            applyIEEEMetadata(html: html, metadata: &metadata)
        } else if host.contains("dl.acm.org") {
            applyACMMetadata(html: html, pageURL: pageURL, metadata: &metadata)
        } else if host.contains("openreview.net") {
            applyOpenReviewMetadata(html: html, pageURL: pageURL, metadata: &metadata)
        } else if host.contains("scholar.google.") {
            applyGoogleScholarMetadata(html: html, metadata: &metadata)
        }
    }

    private static func applyIEEEMetadata(html: String, metadata: inout WebpageMetadata) {
        guard let script = firstMatch(in: html, pattern: #"xplGlobal\.document\.metadata\s*=\s*(\{.*?\});"#) else {
            return
        }
        if metadata.title == nil {
            if let rawTitle = capture(in: script, pattern: #""title":"(.*?)""#) {
                let decoded = rawTitle.removingPercentEncoding ?? rawTitle
                metadata.title = decoded.replacingOccurrences(of: #"\\u002F"#, with: "/", options: .regularExpression)
            }
        }
        if metadata.venue == nil {
            metadata.venue = capture(in: script, pattern: #""publicationTitle":"(.*?)""#)
        }
        if metadata.doi == nil {
            metadata.doi = MetadataNormalization.normalizedDOI(capture(in: script, pattern: #""doi":"(.*?)""#))
        }
        if metadata.year == 0, let yearText = capture(in: script, pattern: #""publicationYear":"(.*?)""#), let year = parseYear(from: yearText) {
            metadata.year = year
        }
        if metadata.pdfURL == nil,
           let pdfPath = capture(in: script, pattern: #""pdfPath":"(.*?)""#) {
            metadata.pdfURL = URL(string: "https://ieeexplore.ieee.org\(pdfPath.replacingOccurrences(of: "iel7", with: "ielx7"))")
        }

        let firstNames = allCaptures(in: script, pattern: #""firstName":"(.*?)""#)
        let lastNames = allCaptures(in: script, pattern: #""lastName":"(.*?)""#)
        if metadata.authors == nil, !firstNames.isEmpty, firstNames.count == lastNames.count {
            metadata.authors = zip(firstNames, lastNames).map { "\($0) \($1)" }.joined(separator: ", ")
        }
    }

    private static func applyACMMetadata(html: String, pageURL: URL, metadata: inout WebpageMetadata) {
        if metadata.title == nil {
            metadata.title = firstMatch(in: html, pattern: #"<h1[^>]*>(.*?)</h1>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
                .map(stripHTML)
        }
        if metadata.pdfURL == nil, let doi = metadata.doi ?? doiFromPageURL(pageURL) {
            metadata.pdfURL = URL(string: "https://dl.acm.org/doi/pdf/\(doi)")
        }
    }

    private static func applyOpenReviewMetadata(html: String, pageURL: URL, metadata: inout WebpageMetadata) {
        if metadata.title == nil {
            metadata.title = extractHTMLTitle(from: html, suffixToStrip: " | OpenReview")
        }
        if metadata.pdfURL == nil,
           let forumId = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "id" })?.value {
            metadata.pdfURL = URL(string: "https://openreview.net/pdf?id=\(forumId)")
        }
        if metadata.venue == nil {
            metadata.venue = "OpenReview"
        }
    }

    private static func applyGoogleScholarMetadata(html: String, metadata: inout WebpageMetadata) {
        if metadata.title == nil,
           let rawTitle = firstMatch(in: html, pattern: #"<h3[^>]*class="[^"]*gs_rt[^"]*"[^>]*>(.*?)</h3>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            metadata.title = stripHTML(rawTitle)
        }
        if metadata.pdfURL == nil,
           let rawPDF = firstMatch(in: html, pattern: #"<div[^>]*class="[^"]*gs_or_ggsm[^"]*"[^>]*>.*?<a[^>]*href="([^"]+)""#, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            metadata.pdfURL = URL(string: rawPDF)
        }
        if metadata.authors == nil,
           let rawAuthorLine = firstMatch(in: html, pattern: #"<div[^>]*class="[^"]*gs_a[^"]*"[^>]*>(.*?)</div>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let line = stripHTML(rawAuthorLine)
            let authorPart = line.components(separatedBy: " - ").first ?? line
            let authors = authorPart
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.contains("…") }
            if !authors.isEmpty {
                metadata.authors = authors.joined(separator: ", ")
            }
            if metadata.year == 0, let year = parseYear(from: line) {
                metadata.year = year
            }
        }
    }

    private static func extractMetaTags(from html: String) -> [[String: String]] {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\s+[^>]*>"#, options: [.caseInsensitive]) else {
            return []
        }
        let nsHTML = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).compactMap { match in
            let tag = nsHTML.substring(with: match.range)
            return parseAttributes(from: tag)
        }
    }

    private static func parseAttributes(from tag: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))"#,
            options: []
        ) else {
            return [:]
        }

        let nsTag = tag as NSString
        var attributes: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(location: 0, length: nsTag.length)) {
            let key = nsTag.substring(with: match.range(at: 1)).lowercased()
            let valueRange: NSRange
            if match.range(at: 3).location != NSNotFound {
                valueRange = match.range(at: 3)
            } else if match.range(at: 4).location != NSNotFound {
                valueRange = match.range(at: 4)
            } else {
                valueRange = match.range(at: 5)
            }
            attributes[key] = nsTag.substring(with: valueRange)
        }
        return attributes
    }

    private static func parseYear(from text: String) -> Int16? {
        guard let regex = try? NSRegularExpression(pattern: #"(19|20)\d{2}"#, options: []) else {
            return nil
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return nil
        }
        return Int16(nsText.substring(with: match.range)) ?? nil
    }

    private static func resolveURL(_ raw: String, relativeTo baseURL: URL) -> URL? {
        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }
        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }

    private static func doiFromPageURL(_ url: URL) -> String? {
        let absolute = url.absoluteString
        if let match = absolute.range(
            of: #"10\.\d{4,9}/[-._;()/:A-Za-z0-9]+"#,
            options: .regularExpression
        ) {
            return MetadataNormalization.normalizedDOI(String(absolute[match]))
        }
        return nil
    }

    private static func arxivIDFromPageURL(_ url: URL) -> String? {
        let absolute = url.absoluteString
        if let match = absolute.range(
            of: #"(?:(?:abs|pdf)/)?([a-z\-]+/\d{7}(?:v\d+)?|\d{4}\.\d{4,5}(?:v\d+)?)"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let value = String(absolute[match])
            if value.hasPrefix("abs/") || value.hasPrefix("pdf/") {
                return String(value.dropFirst(4)).replacingOccurrences(of: ".pdf", with: "")
            }
            return value.replacingOccurrences(of: ".pdf", with: "")
        }
        return nil
    }

    private static func inferredDOIPDFURL(from pageURL: URL, doi: String) -> URL? {
        let absolute = pageURL.absoluteString
        guard absolute.range(
            of: #"/doi/((?:abs|abstract|full|figure|ref|citedby|book|epdf|pdf)?/?)10\.\d{4,9}/[-._;()/:A-Za-z0-9]+$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil else {
            return nil
        }
        let replaced = absolute.replacingOccurrences(
            of: #"/doi/((?:abs|abstract|full|figure|ref|citedby|book|epdf|pdf)?/?)10\.\d{4,9}/[-._;()/:A-Za-z0-9]+$"#,
            with: "/doi/pdf/\(doi)",
            options: [.regularExpression, .caseInsensitive]
        )
        return URL(string: replaced)
    }

    private static func inferredGenericPDFURL(from html: String, relativeTo pageURL: URL) -> URL? {
        if let raw = firstMatch(in: html, pattern: #"<a[^>]+href=["']([^"']+\.pdf(?:\?[^"']*)?)["']"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            return resolveURL(raw, relativeTo: pageURL)
        }
        return nil
    }

    private static func extractHTMLTitle(from html: String, suffixToStrip: String?) -> String? {
        guard let raw = firstMatch(in: html, pattern: #"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        var cleaned = stripHTML(raw)
        if let suffixToStrip, cleaned.hasSuffix(suffixToStrip) {
            cleaned.removeLast(suffixToStrip.count)
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func siteTitleSuffix(for url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if host.contains("openreview.net") { return " | OpenReview" }
        if host.contains("ieeexplore.ieee.org") { return " - IEEE Xplore" }
        if host.contains("dl.acm.org") { return " | ACM Digital Library" }
        if host.contains("scholar.google.") { return " - Google Scholar" }
        return nil
    }

    private static func stripHTML(_ input: String) -> String {
        input
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        capture(in: text, pattern: pattern, options: options)
    }

    private static func capture(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1))
    }

    private static func allCaptures(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return nsText.substring(with: match.range(at: 1))
        }
    }

    private static func flattenJSONLD(_ json: Any) -> [[String: Any]] {
        if let object = json as? [String: Any] {
            if let graph = object["@graph"] as? [[String: Any]] {
                return graph + [object]
            }
            return [object]
        }
        if let array = json as? [[String: Any]] {
            return array
        }
        return []
    }

    private static func stringValue(for key: String, in object: [String: Any]) -> String? {
        object[key] as? String
    }

    private static func nestedStringValue(path: [String], in object: [String: Any]) -> String? {
        guard let first = path.first else { return nil }
        if path.count == 1 {
            return object[first] as? String
        }
        guard let nested = object[first] as? [String: Any] else { return nil }
        return nestedStringValue(path: Array(path.dropFirst()), in: nested)
    }

    private static func authorNames(in object: [String: Any]) -> [String]? {
        guard let authors = object["author"] else { return nil }
        if let list = authors as? [[String: Any]] {
            return list.compactMap { $0["name"] as? String }
        }
        if let one = authors as? [String: Any], let name = one["name"] as? String {
            return [name]
        }
        return nil
    }
}
