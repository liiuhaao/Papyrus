import Foundation

final class ArxivClient {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func fetchFeed(arxivId: String) async throws -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "export.arxiv.org"
        components.path = "/api/query"
        components.queryItems = [URLQueryItem(name: "id_list", value: arxivId)]
        guard let url = components.url else {
            throw MetadataError.parseError
        }
        let (data, response) = try await performRequest {
            try await self.session.data(from: url)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MetadataError.networkError
        }
        guard let xml = String(data: data, encoding: .utf8) else {
            throw MetadataError.parseError
        }
        return xml
    }

    private func performRequest<T>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await MetadataRetrySupport.performRequest(operation: operation)
    }
}

final class OpenReviewClient {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func fetchNote(forumId: String) async throws -> [String: Any] {
        let url = URL(string: "https://api.openreview.net/notes?id=\(forumId)")!
        let (data, response) = try await performRequest {
            try await self.session.data(from: url)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MetadataError.networkError
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let notes = json["notes"] as? [[String: Any]],
              let first = notes.first else {
            throw MetadataError.parseError
        }
        return first
    }

    func searchNotes(title: String) async throws -> [String: Any] {
        var components = URLComponents(string: "https://api2.openreview.net/notes/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: title),
            URLQueryItem(name: "type", value: "json")
        ]
        guard let url = components.url else { throw MetadataError.parseError }
        let (data, response) = try await performRequest {
            try await self.session.data(from: url)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw MetadataError.networkError
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let notes = json["notes"] as? [[String: Any]],
              let first = notes.first else {
            throw MetadataError.notFound
        }
        return first
    }

    private func performRequest<T>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await MetadataRetrySupport.performRequest(operation: operation)
    }
}

final class CrossRefClient {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func fetchWorkJSON(doi: String) async throws -> [String: Any] {
        let encodedDOI = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let url = URL(string: "https://api.crossref.org/works/\(encodedDOI)")!

        var request = URLRequest(url: url)
        request.setValue("Papyrus/1.0 (mailto:your@email.com)", forHTTPHeaderField: "User-Agent")
        let preparedRequest = request

        let (data, response) = try await performRequest {
            try await self.session.data(for: preparedRequest)
        }
        guard let http = response as? HTTPURLResponse else {
            throw MetadataError.networkError
        }
        switch http.statusCode {
        case 200:
            break
        case 404:
            throw MetadataError.notFound
        default:
            throw MetadataError.networkError
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any] else {
            throw MetadataError.parseError
        }

        return message
    }

    func fetchBibTeX(doi: String) async throws -> String {
        let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let url = URL(string: "https://api.crossref.org/works/\(encoded)/transform/application/x-bibtex")!
        var request = URLRequest(url: url)
        request.setValue("Papyrus/1.0", forHTTPHeaderField: "User-Agent")
        let preparedRequest = request
        let (data, response) = try await performRequest {
            try await self.session.data(for: preparedRequest)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let bib = String(data: data, encoding: .utf8),
              !bib.isEmpty else {
            throw MetadataError.parseError
        }
        return bib
    }

    func searchWorks(title: String, limit: Int = 5) async throws -> [[String: Any]] {
        var components = URLComponents(string: "https://api.crossref.org/works")!
        components.queryItems = [
            URLQueryItem(name: "query.bibliographic", value: title),
            URLQueryItem(name: "rows", value: String(limit))
        ]
        guard let url = components.url else { throw MetadataError.parseError }

        var request = URLRequest(url: url)
        request.setValue("Papyrus/1.0 (mailto:your@email.com)", forHTTPHeaderField: "User-Agent")
        let preparedRequest = request

        let (data, response) = try await performRequest {
            try await self.session.data(for: preparedRequest)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw MetadataError.networkError
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let items = message["items"] as? [[String: Any]],
              !items.isEmpty else {
            throw MetadataError.notFound
        }
        return items
    }

    private func performRequest<T>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await MetadataRetrySupport.performRequest(operation: operation)
    }
}

final class SemanticScholarClient {
    private let session: URLSession
    private let s2Fields = "title,authors,year,abstract,venue,publicationVenue,externalIds,citationCount"

    init(session: URLSession) {
        self.session = session
    }

    func fetchPaperByArxivID(_ arxivId: String, apiKey: String) async throws -> [String: Any] {
        let url = URL(string: "https://api.semanticscholar.org/graph/v1/paper/arXiv:\(arxivId)?fields=\(s2Fields)")!
        return try await fetchPaper(from: url, apiKey: apiKey)
    }

    func fetchPaperByDOI(_ doi: String, apiKey: String) async throws -> [String: Any] {
        let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let url = URL(string: "https://api.semanticscholar.org/graph/v1/paper/DOI:\(encoded)?fields=\(s2Fields)")!
        return try await fetchPaper(from: url, apiKey: apiKey)
    }

    func searchPapersByTitle(_ title: String, limit: Int = 5) async throws -> [[String: Any]] {
        var components = URLComponents(string: "https://api.semanticscholar.org/graph/v1/paper/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "fields", value: s2Fields),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else { throw MetadataError.parseError }

        let (data, response) = try await performRequest {
            try await self.session.data(from: url)
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            print("[S2 search] HTTP \(statusCode)")
            throw MetadataError.networkError
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["data"] as? [[String: Any]],
              !results.isEmpty else {
            throw MetadataError.notFound
        }
        return results
    }

    private func fetchPaper(from url: URL, apiKey: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Papyrus/1.0", forHTTPHeaderField: "User-Agent")
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        let preparedRequest = request
        let (data, response) = try await performRequest {
            try await self.session.data(for: preparedRequest)
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            print("[S2 fetch] HTTP \(statusCode)")
            throw MetadataError.notFound
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MetadataError.parseError
        }
        return json
    }

    private func performRequest<T>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await MetadataRetrySupport.performRequest(operation: operation)
    }
}

final class OpenAlexClient {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func fetchWork(doi: String) async throws -> [String: Any] {
        let encodedDOI = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let url = URL(string: "https://api.openalex.org/works/https://doi.org/\(encodedDOI)")!
        return try await fetchJSON(url: url)
    }

    func searchWorks(title: String, limit: Int = 5) async throws -> [[String: Any]] {
        var components = URLComponents(string: "https://api.openalex.org/works")!
        components.queryItems = [
            URLQueryItem(name: "search", value: title),
            URLQueryItem(name: "per-page", value: String(limit))
        ]
        guard let url = components.url else { throw MetadataError.parseError }
        let json = try await fetchJSON(url: url)
        guard let results = json["results"] as? [[String: Any]], !results.isEmpty else {
            throw MetadataError.notFound
        }
        return results
    }

    func fetchBestOAPDFURL(doi: String) async throws -> URL {
        let work = try await fetchWork(doi: doi)
        if let best = work["best_oa_location"] as? [String: Any],
           let pdfURL = extractPDFURL(from: best) {
            return pdfURL
        }
        if let locations = work["locations"] as? [[String: Any]] {
            for location in locations {
                if let pdfURL = extractPDFURL(from: location) {
                    return pdfURL
                }
            }
        }
        throw MetadataError.notFound
    }

    private func extractPDFURL(from location: [String: Any]) -> URL? {
        if let pdfURL = location["pdf_url"] as? String,
           let url = URL(string: pdfURL) {
            return url
        }
        if let source = location["source"] as? [String: Any],
           let host = source["host_organization_name"] as? String,
           host.lowercased().contains("arxiv"),
           let landing = location["landing_page_url"] as? String {
            return URL(string: landing.replacingOccurrences(of: "/abs/", with: "/pdf/") + ".pdf")
        }
        return nil
    }

    private func fetchJSON(url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Papyrus/1.0 (mailto:papyrus@app.local)", forHTTPHeaderField: "User-Agent")
        let preparedRequest = request
        let (data, response) = try await performRequest {
            try await self.session.data(for: preparedRequest)
        }
        guard let http = response as? HTTPURLResponse else {
            throw MetadataError.networkError
        }
        switch http.statusCode {
        case 200:
            break
        case 404:
            throw MetadataError.notFound
        default:
            throw MetadataError.networkError
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MetadataError.parseError
        }
        return json
    }

    private func performRequest<T>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await MetadataRetrySupport.performRequest(operation: operation)
    }
}

final class DBLPClient {
    private let session: URLSession
    private let endpoints = [
        "https://dblp.org/search/publ/api",
        "https://dblp.uni-trier.de/search/publ/api"
    ]

    init(session: URLSession) {
        self.session = session
    }

    func searchPublications(title: String, limit: Int = 8) async throws -> [[String: Any]] {
        var lastError: Error = MetadataError.notFound
        for endpoint in endpoints {
            do {
                var components = URLComponents(string: endpoint)!
                components.queryItems = [
                    URLQueryItem(name: "q", value: title),
                    URLQueryItem(name: "h", value: String(limit)),
                    URLQueryItem(name: "format", value: "json")
                ]
                guard let url = components.url else { throw MetadataError.parseError }

                var request = URLRequest(url: url)
                request.setValue("Papyrus/1.0", forHTTPHeaderField: "User-Agent")
                let preparedRequest = request
                let (data, response) = try await performRequest {
                    try await self.session.data(for: preparedRequest)
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw MetadataError.networkError
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = json["result"] as? [String: Any],
                      let hits = result["hits"] as? [String: Any] else {
                    throw MetadataError.parseError
                }

                let hitObject = hits["hit"]
                let rawHits: [[String: Any]]
                if let array = hitObject as? [[String: Any]] {
                    rawHits = array
                } else if let single = hitObject as? [String: Any] {
                    rawHits = [single]
                } else {
                    throw MetadataError.notFound
                }

                let infos = rawHits.compactMap { $0["info"] as? [String: Any] }
                if infos.isEmpty { throw MetadataError.notFound }
                return infos
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func performRequest<T>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await MetadataRetrySupport.performRequest(operation: operation)
    }
}

final class SemanticScholarGraphClient {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func fetchReferences(for paper: Paper, apiKey: String) async throws -> [PaperReference] {
        let pathID = try pathID(for: paper)
        let url = URL(string: "https://api.semanticscholar.org/graph/v1/paper/\(pathID)/references?fields=title,authors,year,externalIds&limit=100")!
        let json = try await fetchJSON(from: url, apiKey: apiKey)
        guard let items = json["data"] as? [[String: Any]] else {
            throw MetadataError.parseError
        }
        return items.compactMap { item in
            guard let cited = item["citedPaper"] as? [String: Any] else { return nil }
            return PaperReference(from: cited)
        }
    }

    func fetchCitations(for paper: Paper, apiKey: String) async throws -> [PaperReference] {
        let pathID = try pathID(for: paper)
        let url = URL(string: "https://api.semanticscholar.org/graph/v1/paper/\(pathID)/citations?fields=title,authors,year,externalIds&limit=50")!
        let json = try await fetchJSON(from: url, apiKey: apiKey)
        guard let items = json["data"] as? [[String: Any]] else {
            throw MetadataError.parseError
        }
        return items.compactMap { item in
            guard let citing = item["citingPaper"] as? [String: Any] else { return nil }
            return PaperReference(from: citing)
        }
    }

    private func fetchJSON(from url: URL, apiKey: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Papyrus/1.0", forHTTPHeaderField: "User-Agent")
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        let preparedRequest = request
        let (data, response) = try await performRequest {
            try await self.session.data(for: preparedRequest)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw MetadataError.networkError }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MetadataError.parseError
        }
        return json
    }

    private func pathID(for paper: Paper) throws -> String {
        if let arxiv = paper.arxivId, !arxiv.isEmpty { return "arXiv:\(arxiv)" }
        if let doi = paper.doi, !doi.isEmpty,
           let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            return "DOI:\(encoded)"
        }
        throw MetadataError.notFound
    }

    private func performRequest<T>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await MetadataRetrySupport.performRequest(operation: operation)
    }
}

final class PDFResolverClient {
    private let session: URLSession
    private let openAlexClient: OpenAlexClient

    init(session: URLSession, openAlexClient: OpenAlexClient) {
        self.session = session
        self.openAlexClient = openAlexClient
    }

    func fetchPDFURL(arxivId: String? = nil, doi: String? = nil) async throws -> URL {
        if let arxivId, !arxivId.isEmpty {
            let baseID = arxivId.components(separatedBy: "v").first ?? arxivId
            return URL(string: "https://arxiv.org/pdf/\(baseID).pdf")!
        }
        if let doi, !doi.isEmpty {
            if let pdfURL = try? await openAlexClient.fetchBestOAPDFURL(doi: doi) {
                return pdfURL
            }
            if let pdfURL = try? await fetchUnpaywallPDFURL(doi: doi) {
                return pdfURL
            }
            return try await fetchSciHubPDFURL(doi: doi)
        }
        throw MetadataError.notFound
    }

    private func fetchUnpaywallPDFURL(doi: String) async throws -> URL {
        let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let url = URL(string: "https://api.unpaywall.org/v2/\(encoded)?email=papyrus@app.local")!
        let (data, response) = try await performRequest {
            try await self.session.data(from: url)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MetadataError.notFound }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MetadataError.parseError
        }
        if let best = json["best_oa_location"] as? [String: Any],
           let urlStr = best["url_for_pdf"] as? String,
           let pdfURL = URL(string: urlStr) {
            return pdfURL
        }
        if let locations = json["oa_locations"] as? [[String: Any]] {
            for location in locations {
                if let urlStr = location["url_for_pdf"] as? String,
                   let pdfURL = URL(string: urlStr) {
                    return pdfURL
                }
            }
        }
        throw MetadataError.notFound
    }

    private func fetchSciHubPDFURL(doi: String) async throws -> URL {
        let mirrors = ["https://sci-hub.se", "https://sci-hub.st", "https://sci-hub.ru"]
        var lastError: Error = MetadataError.notFound
        for mirror in mirrors {
            do {
                let pageURL = URL(string: "\(mirror)/\(doi)")!
                var request = URLRequest(url: pageURL)
                request.setValue(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                    forHTTPHeaderField: "User-Agent"
                )
                request.timeoutInterval = 12
                let preparedRequest = request
                let (data, response) = try await performRequest {
                    try await self.session.data(for: preparedRequest)
                }
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let html = String(data: data, encoding: .utf8) else {
                    throw MetadataError.notFound
                }
                if let pdfURL = extractSciHubPDFURL(from: html, mirror: mirror) {
                    return pdfURL
                }
                throw MetadataError.notFound
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func extractSciHubPDFURL(from html: String, mirror: String) -> URL? {
        let patterns = [
            #"(?:iframe|embed)[^>]+src=["']([^"']+\.pdf[^"']*)"#,
            #"(?:iframe|embed)[^>]+src=["']([^"']+)["']"#,
            #"#pdf=([^&"'\s]+)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            guard let match = regex.firstMatch(in: html, range: range),
                  let captureRange = Range(match.range(at: 1), in: html) else { continue }
            var urlStr = String(html[captureRange])
            if urlStr.hasPrefix("//") { urlStr = "https:" + urlStr }
            if urlStr.hasPrefix("/") { urlStr = mirror + urlStr }
            if let url = URL(string: urlStr) { return url }
        }
        return nil
    }

    private func performRequest<T>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await MetadataRetrySupport.performRequest(operation: operation)
    }
}
