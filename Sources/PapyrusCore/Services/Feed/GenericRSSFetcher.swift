import Foundation

struct GenericRSSEntry {
    let title: String
    let authors: String
    let abstract: String?
    let publishedDate: Date?
    let landingURL: String?
    let doi: String?
    let arxivId: String?
}

final class GenericRSSFetcher {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchEntries(url: URL, after cutoff: Date?) async throws -> [GenericRSSEntry] {
        var request = URLRequest(url: url)
        request.setValue("Papyrus/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        // Try UTF-8 first, fall back to Latin-1 for legacy feeds
        guard let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw URLError(.cannotDecodeContentData)
        }

        let entries = GenericFeedParser(xml: xml).parse()

        if let cutoff {
            return entries.filter { ($0.publishedDate ?? .distantPast) > cutoff }
        }
        return entries
    }
}

// MARK: - Generic RSS 2.0 + Atom Parser

private final class GenericFeedParser: NSObject, XMLParserDelegate {
    private let xml: String
    private var entries: [GenericRSSEntry] = []

    private var isAtom = false

    // Per-entry state
    private var inEntry = false
    private var inAuthor = false
    private var currentText = ""

    private var eTitle = ""
    private var eLink = ""
    private var eDescription = ""
    private var eAuthors: [String] = []
    private var ePubDate = ""
    private var eId = ""

    init(xml: String) { self.xml = xml }

    func parse() -> [GenericRSSEntry] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.parse()
        return entries
    }

    func parser(_ parser: XMLParser,
                didStartElement name: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attrs: [String: String] = [:]) {
        let local = localName(name)
        currentText = ""

        switch local {
        case "feed":
            isAtom = true
        case "entry" where isAtom, "item":
            inEntry = true
            eTitle = ""; eLink = ""; eDescription = ""; eAuthors = []; ePubDate = ""; eId = ""
        case "author" where inEntry:
            inAuthor = true
        case "link" where inEntry && isAtom:
            // Atom <link> is self-closing with attributes
            let rel = attrs["rel"] ?? "alternate"
            if rel == "alternate" || rel.isEmpty {
                eLink = attrs["href"] ?? ""
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser,
                didEndElement name: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let local = localName(name)
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { currentText = "" }

        guard inEntry else { return }

        switch local {
        case "title":
            eTitle = normalize(text)
        case "link" where !isAtom:
            if eLink.isEmpty { eLink = text }
        case "description", "summary", "content":
            if eDescription.isEmpty { eDescription = text }
        case "pubDate", "published", "updated", "date":
            if ePubDate.isEmpty { ePubDate = text }
        case "creator" where !inAuthor, "author" where !inAuthor:
            // dc:creator or RSS 2.0 <author>email (Name)</author>
            let a = parseRSSAuthor(text)
            if !a.isEmpty { eAuthors.append(a) }
        case "name" where inAuthor:
            if !text.isEmpty { eAuthors.append(text) }
        case "author":
            inAuthor = false
        case "id":
            eId = text
        case "entry" where isAtom, "item":
            inEntry = false
            guard !eTitle.isEmpty else { return }

            let urlString = eLink.isEmpty ? eId : eLink
            let doi = extractDOI(from: urlString) ?? extractDOI(from: eDescription)
            let arxivId = extractArxivId(from: urlString) ?? extractArxivId(from: eDescription)
            let date = parseDate(ePubDate)
            let abstract = eDescription.isEmpty ? nil : stripHTML(eDescription)

            entries.append(GenericRSSEntry(
                title: eTitle,
                authors: eAuthors.joined(separator: ", "),
                abstract: abstract,
                publishedDate: date,
                landingURL: eLink.isEmpty ? nil : eLink,
                doi: doi,
                arxivId: arxivId
            ))
        default:
            break
        }
    }

    // MARK: - Helpers

    private func localName(_ qName: String) -> String {
        qName.components(separatedBy: ":").last ?? qName
    }

    private func normalize(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// "email@example.com (Full Name)" → "Full Name"; otherwise returns raw
    private func parseRSSAuthor(_ raw: String) -> String {
        if let start = raw.firstIndex(of: "("), let end = raw.lastIndex(of: ")"),
           start < end {
            return String(raw[raw.index(after: start)..<end])
        }
        return raw
    }

    private func extractDOI(from text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let patterns = ["doi\\.org/([^\\s\"'<>&]+)", "DOI:\\s*([^\\s\"'<>&]+)"]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            return String(text[range])
        }
        return nil
    }

    private func extractArxivId(from text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        guard let range = text.range(of: "/abs/") ?? text.range(of: "arxiv.org/pdf/") else { return nil }
        var id = String(text[range.upperBound...])
        id = id.components(separatedBy: CharacterSet(charactersIn: "\"'<> ?#")).first ?? id
        // Strip version suffix vN
        if let vIdx = id.lastIndex(of: "v"),
           id[id.index(after: vIdx)...].allSatisfy(\.isNumber) {
            id = String(id[..<vIdx])
        }
        return id.isEmpty ? nil : id
    }

    private func stripHTML(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities: [(String, String)] = [("&amp;","&"),("&lt;","<"),("&gt;",">"),("&quot;","\""),("&#39;","'"),("&nbsp;"," ")]
        for (entity, char) in entities { s = s.replacingOccurrences(of: entity, with: char) }
        return s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // RFC 2822 + ISO 8601
    private static let rfc2822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()
    private static let rfc2822tz: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()
    private static let iso8601full = ISO8601DateFormatter()
    private static let iso8601short: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseDate(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        if let d = Self.iso8601full.date(from: s) { return d }
        if let d = Self.iso8601short.date(from: s) { return d }
        if let d = Self.rfc2822.date(from: s) { return d }
        if let d = Self.rfc2822tz.date(from: s) { return d }
        return nil
    }
}
