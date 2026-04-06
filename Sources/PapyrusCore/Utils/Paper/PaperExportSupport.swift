import AppKit
import Foundation

enum PaperExportSupport {
    static func exportJSON(_ papers: [Paper]) -> String {
        let dicts: [[String: Any]] = papers.map { paper in
            var dict: [String: Any] = [:]
            dict["title"] = paper.title ?? ""
            dict["authors"] = paper.authors ?? ""
            dict["year"] = paper.year
            dict["venue"] = paper.venue ?? ""
            dict["doi"] = paper.doi ?? ""
            dict["arxivId"] = paper.arxivId ?? ""
            dict["rating"] = paper.rating
            dict["status"] = paper.currentReadingStatus.rawValue
            dict["tags"] = paper.tagsList
            dict["citationCount"] = paper.citationCount
            return dict
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: dicts,
            options: [.prettyPrinted, .sortedKeys]
        ),
        let output = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return output
    }

    static func exportToFile(ext: String, content: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.nameFieldStringValue = "Papyrus-export.\(ext)"
        panel.prompt = "Export"
        if panel.runModal() == .OK, let url = panel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
