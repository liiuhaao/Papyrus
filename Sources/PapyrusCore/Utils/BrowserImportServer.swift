// BrowserImportServer.swift
// Papyrus - Academic Paper Manager for macOS
//
// Local HTTP server for browser extension communication.
// Both Safari and Chrome extensions POST PDF data here instead of
// passing it through URL scheme parameters.

import Foundation
import Network

// MARK: - Payload types

struct BrowserImportPayload: Codable {
    let pdfBase64: String
    let filename: String?
    let metadata: BrowserImportHTTPMetadata?
}

struct BrowserImportHTTPMetadata: Codable {
    let title: String?
    let authors: String?
    let doi: String?
    let arxivId: String?
    let abstract: String?
    let venue: String?
    let year: Int?
    let pdfURL: String?
    let sourceURL: String?
}

// MARK: - Server

package final class BrowserImportServer {
    package static let shared = BrowserImportServer()
    package static let port: UInt16 = 52431

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.papyrus.browser-import-server", qos: .utility)

    package func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!) else {
            return
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    package func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        accumulate(connection: connection)
    }

    private func accumulate(connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, isComplete, error in
            guard let self, error == nil else { connection.cancel(); return }

            var buffer = buffer
            if let chunk { buffer.append(chunk) }

            let separator = Data("\r\n\r\n".utf8)
            guard let headerRange = buffer.range(of: separator) else {
                if !isComplete { self.accumulate(connection: connection, buffer: buffer) }
                else { connection.cancel() }
                return
            }

            let headerString = String(data: buffer[..<headerRange.lowerBound], encoding: .utf8) ?? ""
            var contentLength = 0
            for line in headerString.components(separatedBy: "\r\n").dropFirst() {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2,
                   parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                    contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                    break
                }
            }

            let bodyStart = headerRange.upperBound
            let bodyReceived = buffer.count - bodyStart

            if bodyReceived >= contentLength {
                let body = contentLength > 0 ? Data(buffer[bodyStart..<(bodyStart + contentLength)]) : Data()
                self.process(connection: connection, requestLine: headerString.components(separatedBy: "\r\n").first ?? "", body: body)
            } else if !isComplete {
                self.accumulate(connection: connection, buffer: buffer)
            } else {
                connection.cancel()
            }
        }
    }

    private func process(connection: NWConnection, requestLine: String, body: Data) {
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { respond(connection, status: 400, body: #"{"ok":false,"error":"Bad request"}"#); return }

        let method = String(parts[0])
        let path = String(parts[1])

        switch (method, path) {
        case ("OPTIONS", _):
            respond(connection, status: 200, body: "")

        case ("GET", "/ping"):
            respond(connection, status: 200, body: #"{"ok":true}"#)

        case ("POST", "/import"):
            do {
                let payload = try JSONDecoder().decode(BrowserImportPayload.self, from: body)
                try handleImport(payload)
                respond(connection, status: 200, body: #"{"ok":true}"#)
            } catch {
                let msg = error.localizedDescription.replacingOccurrences(of: "\"", with: "'")
                respond(connection, status: 400, body: #"{"ok":false,"error":"\#(msg)"}"#)
            }

        default:
            respond(connection, status: 404, body: #"{"ok":false,"error":"Not found"}"#)
        }
    }

    // MARK: - Import handling

    private func handleImport(_ payload: BrowserImportPayload) throws {
        guard let pdfData = Data(base64Encoded: payload.pdfBase64),
              pdfData.starts(with: [0x25, 0x50, 0x44, 0x46]) else {
            throw BrowserImportError.invalidPDF
        }

        let filename = sanitizedFilename(payload.filename)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(filename)

        try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try pdfData.write(to: tempURL, options: .atomic)

        guard let importURL = buildImportURL(pdfPath: tempURL.path, metadata: payload.metadata) else {
            throw BrowserImportError.invalidURL
        }

        Task { @MainActor in
            BrowserImportURLDispatcher.shared.enqueue(importURL)
        }
    }

    private func buildImportURL(pdfPath: String, metadata: BrowserImportHTTPMetadata?) -> URL? {
        var components = URLComponents()
        components.scheme = "papyrus"
        components.host = "import"

        var items: [URLQueryItem] = [URLQueryItem(name: "pdfPath", value: pdfPath)]

        func add(_ name: String, _ value: String?) {
            if let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                items.append(URLQueryItem(name: name, value: v))
            }
        }

        if let m = metadata {
            add("title", m.title)
            add("authors", m.authors)
            add("doi", m.doi)
            add("arxivId", m.arxivId)
            add("pdfURL", m.pdfURL)
            add("abstract", m.abstract)
            add("venue", m.venue)
            add("sourceURL", m.sourceURL)
            if let year = m.year, year > 0 {
                items.append(URLQueryItem(name: "year", value: String(year)))
            }
        }

        components.queryItems = items
        return components.url
    }

    // MARK: - HTTP response

    private func respond(_ connection: NWConnection, status: Int, body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default:  statusText = "Error"
        }

        let headers = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Access-Control-Allow-Private-Network: true",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")

        var response = headers.data(using: .utf8)!
        response.append(bodyData)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Helpers

    private func sanitizedFilename(_ raw: String?) -> String {
        let base = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (base?.isEmpty == false ? base! : "paper.pdf")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return name.lowercased().hasSuffix(".pdf") ? name : name + ".pdf"
    }
}

// MARK: - Errors

private enum BrowserImportError: LocalizedError {
    case invalidPDF
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidPDF: return "Data is not a valid PDF."
        case .invalidURL: return "Failed to build Papyrus import URL."
        }
    }
}
