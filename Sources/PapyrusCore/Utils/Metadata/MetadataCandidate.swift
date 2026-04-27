import Foundation

package struct MetadataCandidate: Sendable, Codable {
    package enum MatchKind: String, Sendable, Codable {
        case doi
        case arxiv
        case exactTitle
        case fuzzyTitle
    }

    package let metadata: PaperMetadata
    package let source: String
    package let matchKind: MatchKind
    package let sourcePriority: Double
    package let sourceConfidence: Double
    package let trace: String
}

package struct MetadataResolution: Sendable, Codable {
    package let metadata: PaperMetadata?
    package let candidates: [MetadataCandidate]
    package let trace: String
    package let selectedSource: String?
    package let selectedScore: Double?
}

package extension MetadataCandidate {
    var uniqueKey: String {
        [
            MetadataNormalization.normalizeTitle(metadata.title) ?? "",
            MetadataNormalization.normalizedDOI(metadata.doi) ?? "",
            metadata.arxivId?.lowercased() ?? "",
            source
        ].joined(separator: "|")
    }
}
