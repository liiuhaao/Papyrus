// VenueFormatter.swift
// Maps full venue names to standard abbreviations.
// Table: (lowercased-pattern, abbreviation), longest/most-specific first.

import Foundation

struct VenueFormatter {
    static func unifiedDisplayName(_ venue: String) -> String {
        let trimmed = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let abbreviation = abbreviate(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
        return abbreviation.isEmpty ? trimmed : abbreviation
    }

    static func unifiedFullName(_ venue: String) -> String {
        let trimmed = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let normalized = normalizeFullName(trimmed)
        return normalized.isEmpty ? trimmed : normalized
    }

    static func resolvedVenueParts(_ venue: String, abbreviation: String?) -> (full: String, abbr: String) {
        let raw = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return ("", "") }

        let full = unifiedFullName(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let fullValue = full.isEmpty ? raw : full

        let explicitAbbr = abbreviation?.trimmingCharacters(in: .whitespacesAndNewlines)
        let derived = abbreviate(fullValue).trimmingCharacters(in: .whitespacesAndNewlines)
        var abbr = (explicitAbbr?.isEmpty == false ? explicitAbbr! : derived)

        if abbr.isEmpty || equalsIgnoreCase(abbr, fullValue) {
            let fallback = fallbackAbbreviation(fullValue)
            abbr = fallback.isEmpty ? fullValue : fallback
        }

        return (fullValue, abbr)
    }

    // MARK: - Full-name canonicalisation

    /// Attempts to expand an abbreviation back to its canonical full name.
    /// Uses the reverse of the abbreviation table; best-effort capitalisation.
    static func expandedFullName(forAbbreviation abbr: String) -> String? {
        let needle = abbr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        for (pattern, abbreviation) in Self.table {
            if abbreviation.lowercased() == needle {
                return capitalizePattern(pattern)
            }
        }
        return nil
    }

    /// Given an arbitrary venue string, returns the canonical full name
    /// if the abbreviation table can match it.
    static func standardFullName(_ venue: String) -> String? {
        let abbr = abbreviate(venue)
        if abbr != venue, let full = expandedFullName(forAbbreviation: abbr) {
            return full
        }
        // Fallback: try direct substring match on the normalised form.
        let normalized = Self.normalize(venue)
        for (pattern, _) in Self.table {
            let normalizedPattern = pattern.replacingOccurrences(of: "/", with: " ")
            if normalized.contains(normalizedPattern) {
                return capitalizePattern(pattern)
            }
        }
        return nil
    }

    private static let acronymMap: [String: String] = [
        "ieee": "IEEE", "acm": "ACM", "cvf": "CVF",
        "usenix": "USENIX", "neurips": "NeurIPS", "nips": "NeurIPS",
        "icml": "ICML", "iclr": "ICLR", "iccv": "ICCV",
        "eccv": "ECCV", "cvpr": "CVPR", "acl": "ACL",
        "emnlp": "EMNLP", "naacl": "NAACL", "aaai": "AAAI",
        "ijcai": "IJCAI", "kdd": "KDD", "sigir": "SIGIR",
        "jmlr": "JMLR", "pmlr": "PMLR", "corr": "CoRR",
        "arxiv": "arXiv", "vldb": "VLDB", "pvldb": "PVLDB",
        "www": "WWW", "sigmod": "SIGMOD", "sigkdd": "SIGKDD",
        "siggraph": "SIGGRAPH", "sigspatial": "SIGSPATIAL",
        "sp": "S&P", "s&p": "S&P",
        "isca": "ISCA", "asplos": "ASPLOS", "micro": "MICRO", "hpca": "HPCA",
        "popl": "POPL", "pldi": "PLDI", "oopsla": "OOPSLA",
        "osdi": "OSDI", "sosp": "SOSP", "nsdi": "NSDI", "atc": "USENIX ATC",
        "ccs": "CCS", "pets": "PETS",
        "chi": "CHI", "uist": "UIST", "iui": "IUI",
        "colt": "COLT", "colm": "COLM", "corl": "CoRL",
        "crypto": "CRYPTO", "eurocrypt": "EUROCRYPT", "asiacrypt": "ASIACRYPT",
        "cade": "CADE", "sat": "SAT", "cp": "CP",
    ]

    private static func capitalizePattern(_ pattern: String) -> String {
        var clean = pattern
        // Strip surrounding quotes.
        if clean.hasPrefix("\"") { clean = String(clean.dropFirst()) }
        if clean.hasSuffix("\"") { clean = String(clean.dropLast()) }
        if clean.hasPrefix("'")  { clean = String(clean.dropFirst()) }
        if clean.hasSuffix("'")  { clean = String(clean.dropLast()) }

        let words = clean.components(separatedBy: .whitespacesAndNewlines)
        let result = words.map { word -> String in
            let w = word.trimmingCharacters(in: .punctuationCharacters)
            let lowerW = w.lowercased()
            // Handle slash-separated acronyms like "ieee/cvf".
            if w.contains("/") {
                return w.split(separator: "/").map { part -> String in
                    let p = String(part).trimmingCharacters(in: .punctuationCharacters)
                    let lowerP = p.lowercased()
                    if let acronym = acronymMap[lowerP] { return acronym }
                    return p.prefix(1).uppercased() + p.dropFirst()
                }.joined(separator: "/")
            }
            if let acronym = acronymMap[lowerW] { return acronym }
            if lowerW.count <= 3 && ["on", "of", "the", "and", "for", "in"].contains(lowerW) {
                return lowerW
            }
            return w.prefix(1).uppercased() + w.dropFirst()
        }.joined(separator: " ")

        return result
    }

    static func abbreviate(_ venue: String) -> String {
        // User custom venues take priority
        if let custom = VenueFormatterConfig.customVenues[venue] { return custom }

        // Cached abbreviation from Semantic Scholar or DBLP lookup
        if let cached = VenueAbbreviationService.shared.cached(venue: venue) { return cached }

        // Already looks like an abbreviation (short + majority uppercase)
        let letters = venue.filter { $0.isLetter }
        let upper   = letters.filter { $0.isUppercase }
        if venue.count <= 8 && !letters.isEmpty && upper.count * 2 >= letters.count {
            return venue
        }

        // Pass 1: known abbreviation appears verbatim as a token in the original string
        // e.g. "Proceedings of the 37th AAAI Conference" → token "AAAI" → "AAAI"
        let tokens = venue.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "&"))) }
        for token in tokens where !token.isEmpty {
            if let abbr = Self.knownAbbreviations[token]
                ?? Self.knownAbbreviations[token.uppercased()]
                ?? Self.knownAbbreviations[token.lowercased()] {
                return abbr
            }
        }

        // Pass 2: strip noise then substring-match the table with word boundaries
        let normalized = Self.normalize(venue)
        for (pattern, abbr) in Self.table {
            let searchPattern = pattern.replacingOccurrences(of: "/", with: " ")
            let regexPattern = "(^|\\s)\(NSRegularExpression.escapedPattern(for: searchPattern))(\\s|$)"
            guard let regex = try? NSRegularExpression(pattern: regexPattern) else { continue }
            if regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) != nil {
                return abbr
            }
        }

        return venue
    }

    // MARK: - Normalisation

    private static func normalize(_ venue: String) -> String {
        var s = venue.lowercased()
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        for prefix in ["proceedings of the ", "proceedings of "] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        if s.hasPrefix("the ") { s = String(s.dropFirst(4)) }

        let cleaned = s.components(separatedBy: .whitespaces).filter { token in
            guard !token.isEmpty else { return false }
            if Self.ordinalWords.contains(token) { return false }
            if token.first?.isNumber == true { return false }
            return true
        }.joined(separator: " ")

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    private static func normalizeFullName(_ venue: String) -> String {
        let rawTokens = venue.components(separatedBy: .whitespacesAndNewlines)
        let cleanedTokens = rawTokens.map { token in
            token.trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "&")))
        }

        var startIndex = 0
        let lowerTokens = cleanedTokens.map { $0.lowercased() }
        if lowerTokens.starts(with: ["proceedings", "of", "the"]) {
            startIndex = 3
        } else if lowerTokens.starts(with: ["proceedings", "of"]) {
            startIndex = 2
        }

        var output: [String] = []
        for token in cleanedTokens[startIndex...] {
            if token.isEmpty { continue }
            let lower = token.lowercased()
            if ordinalWords.contains(lower) { continue }
            if isNumericOrdinal(lower) { continue }
            output.append(token)
        }

        return output.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func equalsIgnoreCase(_ a: String, _ b: String) -> Bool {
        return a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static func isNumericOrdinal(_ token: String) -> Bool {
        let digits = token.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
        if digits.count == token.count { return true }
        if digits.isEmpty { return false }
        let suffix = token.dropFirst(digits.count)
        return ["st", "nd", "rd", "th"].contains(String(suffix))
    }

    private static func fallbackAbbreviation(_ venue: String) -> String {
        let tokens = venue.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard shouldDeriveFallbackAbbreviation(tokens) else { return "" }
        let letters = tokens.compactMap { $0.first }
        let abbr = letters.map { String($0).uppercased() }.joined()
        if abbr.isEmpty { return venue }
        if abbr.count <= 8 { return abbr }
        return String(abbr.prefix(8))
    }

    private static func shouldDeriveFallbackAbbreviation(_ tokens: [String]) -> Bool {
        let significant = tokens.filter { token in
            let lower = token.lowercased()
            return !token.isEmpty
                && !ordinalWords.contains(lower)
                && !isNumericOrdinal(lower)
        }
        return significant.count >= 2
    }

    private static let ordinalWords: Set<String> = [
        "first", "second", "third", "fourth", "fifth", "sixth",
        "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth",
        "thirteenth", "fourteenth", "fifteenth", "sixteenth",
        "seventeenth", "eighteenth", "nineteenth", "twentieth",
    ]

    // Token → abbreviation map (built from table + manual aliases)
    private static let knownAbbreviations: [String: String] = {
        var d: [String: String] = [:]
        for (_, abbr) in Self.table {
            d[abbr] = abbr
            d[abbr.lowercased()] = abbr
            d[abbr.uppercased()] = abbr
        }
        d["NeurIPS"] = "NeurIPS"; d["NIPS"] = "NeurIPS"; d["nips"] = "NeurIPS"; d["neurips"] = "NeurIPS"
        d["USENIX"] = "USENIX"
        return d
    }()

    // Ordered longest-pattern-first so more specific entries win.
    // Loaded from venue_abbreviations.json at runtime.
    private static let table: [(String, String)] = {
        guard let url = Bundle.module.url(forResource: "venue_abbreviations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String]] else {
            return [(String, String)]()
        }
        return json.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return (pair[0], pair[1])
        }
    }()
}
