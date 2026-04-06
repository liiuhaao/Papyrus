import Foundation

enum MetadataSourcePhase {
    case direct
    case title
    case fallback
}

protocol MetadataSource: Sendable {
    var name: String { get }
    var phase: MetadataSourcePhase { get }
    func collectCandidates(for seed: MetadataSeed) async -> [MetadataCandidate]
}
