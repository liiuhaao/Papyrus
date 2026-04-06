import Foundation

struct MetadataCandidate: Sendable {
    enum MatchKind: Sendable {
        case doi
        case arxiv
        case exactTitle
        case fuzzyTitle
    }

    let metadata: PaperMetadata
    let source: String
    let matchKind: MatchKind
    let sourcePriority: Double
    let sourceConfidence: Double
    let trace: String
}

struct MetadataResolution: Sendable {
    let metadata: PaperMetadata?
    let candidates: [MetadataCandidate]
    let trace: String
}
