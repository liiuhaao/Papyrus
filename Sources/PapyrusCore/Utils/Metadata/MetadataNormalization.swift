import Foundation

enum MetadataNormalization {
    static func normalizeMetadata(_ metadata: PaperMetadata) -> PaperMetadata {
        var normalized = metadata
        normalized.title = normalizeTitle(metadata.title)
        normalized.authors = normalizedAuthorsString(metadata.authors)
        normalized.venue = normalizeVenue(metadata.venue)
        normalized.doi = normalizedDOI(metadata.doi)
        normalized.abstract = normalizeAbstract(metadata.abstract)
        if let arxivId = metadata.arxivId?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !arxivId.isEmpty {
            normalized.arxivId = arxivId
        } else {
            normalized.arxivId = nil
        }
        return normalized
    }

    static func normalizeTitle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[‐‑–—]"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":,;."))
        let deDated = stripLeadingDatePrefix(cleaned)
        return deDated.isEmpty ? nil : deDated
    }

    static func titleSearchQueries(_ raw: String?) -> [String] {
        guard let normalized = normalizeTitle(raw), normalized.count > 10 else { return [] }

        var queries: [String] = [normalized]
        let withoutBracketed = normalized
            .replacingOccurrences(of: #"\[[^\]]+\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\([^\)]+\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if withoutBracketed.count > 10 {
            queries.append(withoutBracketed)
        }

        if let colonIndex = normalized.firstIndex(of: ":") {
            let prefix = normalized[..<colonIndex].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if prefix.count >= 16 {
                queries.append(prefix)
            }
            let suffixStart = normalized.index(after: colonIndex)
            let suffix = normalized[suffixStart...].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if suffix.count >= 24 {
                queries.append(suffix)
            }
        }

        let deNoised = normalized
            .replacingOccurrences(
                of: #"^(?:extended abstract|short paper|poster|demo|supplementary material|supplementary)\s*[:\-]\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if deNoised.count > 10 {
            queries.append(deNoised)
        }

        var seen = Set<String>()
        return queries.filter { query in
            let key = query.lowercased()
            return seen.insert(key).inserted
        }
    }

    static func titleSimilarity(_ lhs: String?, _ rhs: String?) -> Double {
        guard let lhs = normalizeTitle(lhs), let rhs = normalizeTitle(rhs) else { return 0 }
        let lhsTokens = significantTokens(lhs)
        let rhsTokens = significantTokens(rhs)
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let overlap = lhsTokens.intersection(rhsTokens).count
        let tokenScore = Double(overlap) / Double(max(lhsTokens.count, rhsTokens.count))

        let lhsCompact = lhs.lowercased().replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
        let rhsCompact = rhs.lowercased().replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
        let prefixBonus = lhsCompact.hasPrefix(rhsCompact) || rhsCompact.hasPrefix(lhsCompact) ? 0.08 : 0
        return min(1.0, tokenScore + prefixBonus)
    }

    static func titleTokenCoverage(_ lhs: String?, _ rhs: String?) -> Double {
        guard let lhs = normalizeTitle(lhs), let rhs = normalizeTitle(rhs) else { return 0 }
        let lhsTokens = distinctiveTokens(lhs)
        let rhsTokens = distinctiveTokens(rhs)
        guard !lhsTokens.isEmpty else { return 0 }
        let overlap = lhsTokens.intersection(rhsTokens).count
        return Double(overlap) / Double(lhsTokens.count)
    }

    static func titleBigramOverlap(_ lhs: String?, _ rhs: String?) -> Double {
        guard let lhs = normalizeTitle(lhs), let rhs = normalizeTitle(rhs) else { return 0 }
        let lhsBigrams = bigrams(from: distinctiveTokensInOrder(lhs))
        let rhsBigrams = bigrams(from: distinctiveTokensInOrder(rhs))
        guard !lhsBigrams.isEmpty else { return 0 }
        let overlap = lhsBigrams.intersection(rhsBigrams).count
        return Double(overlap) / Double(lhsBigrams.count)
    }

    static func titleAnchoredTokenCoverage(_ lhs: String?, _ rhs: String?) -> Double {
        guard let lhs = normalizeTitle(lhs), let rhs = normalizeTitle(rhs) else { return 0 }
        let lhsAnchors = anchoredDistinctiveTokens(lhs)
        let rhsTokens = Set(distinctiveTokensInOrder(rhs))
        guard !lhsAnchors.isEmpty else { return 0 }
        let overlap = lhsAnchors.intersection(rhsTokens).count
        return Double(overlap) / Double(lhsAnchors.count)
    }

    static func authorTokens(_ authors: String?) -> Set<String> {
        guard let authors else { return [] }
        let parts = authors.lowercased()
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Set(parts.compactMap { author in
            let items = author.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
            return items.last
        })
    }

    static func normalizedDOI(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .replacingOccurrences(of: "https://doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "doi:", with: "", options: .caseInsensitive)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func normalizedAuthorsString(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let names = raw.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
        let normalized = normalizedAuthors(names).joined(separator: ", ")
        return normalized.isEmpty ? nil : normalized
    }

    static func normalizedAuthorName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: #"\s+\d{4,}$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+\d{1,3}$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
        return cleaned.isEmpty ? nil : cleaned
    }

    static func normalizedAuthors(_ authors: [String]) -> [String] {
        var seen = Set<String>()
        return authors.compactMap(normalizedAuthorName).filter { name in
            let key = name.lowercased()
            return seen.insert(key).inserted
        }
    }

    static func normalizeVenue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
        return cleaned.isEmpty ? nil : cleaned
    }

    static func normalizeAbstract(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func significantTokens(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 2 })
    }

    private static func distinctiveTokens(_ text: String) -> Set<String> {
        Set(distinctiveTokensInOrder(text))
    }

    private static func distinctiveTokensInOrder(_ text: String) -> [String] {
        let stopwords: Set<String> = [
            "the", "a", "an", "and", "or", "for", "of", "in", "on", "to", "with",
            "towards", "toward", "via", "using", "from", "by", "at", "into", "over",
            "under", "through", "based", "new"
        ]
        return text.lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 4 && !stopwords.contains($0) }
    }

    private static func anchoredDistinctiveTokens(_ text: String) -> Set<String> {
        let tokens = distinctiveTokensInOrder(text)
        guard !tokens.isEmpty else { return [] }

        let anchorCount: Int
        if tokens.count >= 5 {
            anchorCount = 2
        } else if tokens.count >= 3 {
            anchorCount = 1
        } else {
            anchorCount = tokens.count
        }

        return Set(tokens.prefix(anchorCount))
    }

    private static func bigrams(from tokens: [String]) -> Set<String> {
        guard tokens.count >= 2 else { return [] }
        var out = Set<String>()
        for index in 0..<(tokens.count - 1) {
            out.insert(tokens[index] + " " + tokens[index + 1])
        }
        return out
    }

    private static func stripLeadingDatePrefix(_ text: String) -> String {
        let month = #"(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"#
        let patterns = [
            #"^\d{1,2}\s+\#(month)\s+\d{4}\s*[:\-]?\s+"#,
            #"^\#(month)\s+\d{1,2},?\s+\d{4}\s*[:\-]?\s+"#,
            #"^\d{4}[./-]\d{1,2}[./-]\d{1,2}\s*[:\-]?\s+"#,
            #"^\d{1,2}[./-]\d{1,2}[./-]\d{2,4}\s*[:\-]?\s+"#
        ]

        var output = text
        for pattern in patterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
