import Foundation
import PDFKit

struct PDFContentLine: Sendable, Equatable, Codable {
    let text: String
    let fontSize: CGFloat
    let fontName: String
    let isBold: Bool
    let isItalic: Bool
}

struct PDFContentPage: Sendable, Equatable {
    let pageIndex: Int
    let text: String
    let lines: [PDFContentLine]
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
            let richLines = extractRichLines(from: page)
            let text = richLines.map(\.text).joined(separator: "\n")
            guard !text.isEmpty else { return nil }
            return PDFContentPage(pageIndex: pageIndex, text: text, lines: richLines)
        }

        let rawText = pages.map(\.text).joined(separator: "\n\n")
        return PDFContentSnapshot(
            pages: pages,
            rawText: rawText,
            firstPageText: pages.first?.text ?? ""
        )
    }

    private static func extractRichLines(from page: PDFPage) -> [PDFContentLine] {
        // Use page.string for line splitting (reliable across PDF generators)
        // and attributedString for font attribution.
        let stringLines = (page.string ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let attributedString = page.attributedString, !attributedString.string.isEmpty else {
            return stringLines.map {
                PDFContentLine(text: $0, fontSize: 12, fontName: "", isBold: false, isItalic: false)
            }
        }

        let attrString = attributedString.string
        var result: [PDFContentLine] = []

        for line in stringLines {
            guard !line.isEmpty else { continue }

            // Find the first character of this line in the attributed string
            // to derive the line's font properties.
            guard let firstCharRange = attrString.range(of: line) else {
                result.append(PDFContentLine(text: line, fontSize: 12, fontName: "", isBold: false, isItalic: false))
                continue
            }

            let nsRange = NSRange(firstCharRange, in: attrString)
            var effectiveRange = NSRange()
            let attrs = attributedString.attributes(at: nsRange.location, effectiveRange: &effectiveRange)
            let font = attrs[.font] as? NSFont
            let size = font?.pointSize ?? 12
            let name = font?.fontName ?? ""
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let bold = traits.contains(.bold)
            let italic = traits.contains(.italic)

            result.append(PDFContentLine(
                text: line,
                fontSize: size,
                fontName: name,
                isBold: bold,
                isItalic: italic
            ))
        }

        return result
    }
}
