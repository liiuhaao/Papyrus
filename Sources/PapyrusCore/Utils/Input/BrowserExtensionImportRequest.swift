import Foundation

struct BrowserExtensionImportRequest {
    let pdfFileURL: URL?
    let webpageMetadata: WebpageMetadata?

    static func parse(from url: URL) -> BrowserExtensionImportRequest? {
        guard url.scheme?.lowercased() == "papyrus",
              url.host?.lowercased() == "import",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        func value(_ key: String) -> String? {
            components.queryItems?
                .last(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?
                .value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty
        }

        let doi = value("doi")
        let arxivId = value("arxivId")
        let inputURLString = value("inputURL")
        let pdfPath = value("pdfPath")
        let pdfURLString = value("pdfURL")
        let pdfFileURL = pdfPath.map(URL.init(fileURLWithPath:))

        guard pdfFileURL != nil else {
            return nil
        }

        var metadata = WebpageMetadata()
        metadata.title = value("title")
        metadata.authors = value("authors")
        metadata.doi = doi
        metadata.arxivId = arxivId
        metadata.abstract = value("abstract")
        metadata.venue = value("venue")
        metadata.year = parsedYear(from: value("year"))

        if let pdfURLString, let parsedPDFURL = URL(string: pdfURLString) {
            metadata.pdfURL = parsedPDFURL
        }

        if let sourceURLString = value("sourceURL"), let parsedSourceURL = URL(string: sourceURLString) {
            metadata.sourceURL = parsedSourceURL
        } else if let inputURLString, let parsedInputURL = URL(string: inputURLString) {
            metadata.sourceURL = parsedInputURL
        }

        return BrowserExtensionImportRequest(
            pdfFileURL: pdfFileURL,
            webpageMetadata: metadata.hasAnyValue ? metadata : nil
        )
    }

    private static func parsedYear(from raw: String?) -> Int16 {
        guard let raw else { return 0 }
        if let direct = Int16(raw), direct > 0 {
            return direct
        }
        guard let match = raw.range(of: #"(19|20)\d{2}"#, options: .regularExpression),
              let parsed = Int16(raw[match]) else {
            return 0
        }
        return parsed
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension WebpageMetadata {
    var hasAnyValue: Bool {
        title != nil
            || authors != nil
            || doi != nil
            || arxivId != nil
            || abstract != nil
            || venue != nil
            || year > 0
            || pdfURL != nil
            || sourceURL != nil
    }
}
