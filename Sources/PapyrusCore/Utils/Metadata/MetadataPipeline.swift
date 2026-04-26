import Foundation

struct MetadataPipeline {
    let sources: [MetadataSource]
    let resolver: MetadataResolver

    func resolve(seed: MetadataSeed) async -> MetadataResolution {
        var allCandidates: [MetadataCandidate] = []

        let directSources = sources.filter { $0.phase == .direct }
        let directCandidates = await collectCandidates(from: directSources, seed: seed)
        allCandidates.append(contentsOf: directCandidates)

        let directResolution = resolver.resolve(seed: seed, candidates: allCandidates)
        if shouldEarlyStop(after: directResolution) {
            return directResolution
        }

        let titleSources = sources.filter { $0.phase == .title }
        let titleCandidates = await collectCandidates(from: titleSources, seed: seed)
        allCandidates.append(contentsOf: titleCandidates)

        let titleResolution = resolver.resolve(seed: seed, candidates: allCandidates)
        if shouldSkipFallback(after: titleResolution) {
            return titleResolution
        }

        let fallbackSources = sources.filter { $0.phase == .fallback }
        let fallbackCandidates = await collectCandidates(from: fallbackSources, seed: seed)
        allCandidates.append(contentsOf: fallbackCandidates)

        return resolver.resolve(seed: seed, candidates: allCandidates)
    }

    private func collectCandidates(from sources: [MetadataSource], seed: MetadataSeed) async -> [MetadataCandidate] {
        await withTaskGroup(of: [MetadataCandidate].self) { group in
            for source in sources {
                group.addTask {
                    await source.collectCandidates(for: seed)
                }
            }

            var collected: [MetadataCandidate] = []
            for await candidates in group {
                collected.append(contentsOf: candidates)
            }
            return collected
        }
    }

    private func shouldEarlyStop(after resolution: MetadataResolution) -> Bool {
        guard resolution.metadata != nil,
              let best = resolution.candidates.first else {
            return false
        }
        switch best.matchKind {
        case .doi:
            return MetadataCompleteness.score(best.metadata) >= 0.9
        case .arxiv:
            if MetadataCompleteness.isPreprint(best.metadata) {
                return false
            }
            return MetadataCompleteness.score(best.metadata) >= 0.9
        case .exactTitle, .fuzzyTitle:
            return false
        }
    }

    private func shouldSkipFallback(after resolution: MetadataResolution) -> Bool {
        guard resolution.metadata != nil,
              let best = resolution.candidates.first else {
            return false
        }
        if case .doi = best.matchKind {
            return MetadataCompleteness.score(best.metadata) >= 0.92
        }
        if case .arxiv = best.matchKind {
            if MetadataCompleteness.isPreprint(best.metadata) {
                return false
            }
            return MetadataCompleteness.score(best.metadata) >= 0.92
        }
        return MetadataCompleteness.score(best.metadata) >= 0.88
    }
}
