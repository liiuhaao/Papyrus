import Foundation
import PDFKit

struct PDFContentPage: Sendable, Equatable {
    let pageIndex: Int
    let text: String
}

struct PDFContentSnapshot: Sendable, Equatable {
    let pages: [PDFContentPage]
    let rawText: String
    let firstPageText: String
}

enum PDFExtractor {
    static func extractContent(from fileURL: URL, maxPages: Int = 2) -> PDFContentSnapshot {
        guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else {
            return PDFContentSnapshot(
                pages: [],
                rawText: "",
                firstPageText: ""
            )
        }

        let pageLimit = max(1, min(maxPages, document.pageCount))
        let pages = (0..<pageLimit).compactMap { pageIndex -> PDFContentPage? in
            guard let page = document.page(at: pageIndex) else { return nil }
            let text = normalizedPageText(page.string ?? "")
            guard !text.isEmpty else { return nil }
            return PDFContentPage(pageIndex: pageIndex, text: text)
        }

        let rawText = pages.map(\.text).joined(separator: "\n\n")
        return PDFContentSnapshot(
            pages: pages,
            rawText: rawText,
            firstPageText: pages.first?.text ?? ""
        )
    }

    private static func normalizedPageText(_ raw: String) -> String {
        raw
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
