import Foundation

enum MetadataCompleteness {
    static func score(_ metadata: PaperMetadata) -> Double {
        var score = 0.0
        if let title = metadata.title, !title.isEmpty { score += 0.22 }
        if let authors = metadata.authors, !authors.isEmpty { score += 0.18 }
        if let venue = metadata.venue, !venue.isEmpty { score += 0.18 }
        if metadata.year > 0 { score += 0.12 }
        if let doi = metadata.doi, !doi.isEmpty { score += 0.14 }
        if let abstract = metadata.abstract, !abstract.isEmpty { score += 0.08 }
        if let publicationType = metadata.publicationType, !publicationType.isEmpty { score += 0.08 }
        return min(1.0, score)
    }

    static func isFormalPublication(_ metadata: PaperMetadata) -> Bool {
        if let doi = metadata.doi, !doi.isEmpty, !(metadata.publicationType ?? "").contains("preprint") {
            return true
        }
        let venueText = (metadata.venue ?? "").lowercased()
        if venueText.isEmpty { return false }
        let formalHints = [
            "conference", "proceedings", "journal", "transactions",
            "neurips", "nips", "iclr", "icml", "cvpr", "iccv", "eccv",
            "acl", "emnlp", "naacl", "aaai", "ijcai", "kdd", "sigir"
        ]
        return formalHints.contains { venueText.contains($0) }
    }

    static func isPreprint(_ metadata: PaperMetadata) -> Bool {
        if let arxiv = metadata.arxivId, !arxiv.isEmpty { return true }
        let venueText = (metadata.venue ?? "").lowercased()
        return ["arxiv", "openreview", "biorxiv", "medrxiv", "chemrxiv", "corr"].contains {
            venueText.contains($0)
        }
    }
}
