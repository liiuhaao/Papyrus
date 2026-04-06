import Foundation

struct PDFSeed {
    let title: String?
    let titleCandidates: [String]
    let authors: String?
    let venue: String?
    let year: Int16
    let doi: String?
    let arxivId: String?
    let abstract: String?
}

extension PDFSeed {
    var hasMeaningfulMetadata: Bool {
        title != nil
            || authors != nil
            || venue != nil
            || year > 0
            || doi != nil
            || arxivId != nil
            || abstract != nil
    }

    var canFetchMetadata: Bool {
        doi != nil || arxivId != nil || !titleCandidates.isEmpty
    }
}

enum PDFSeedExtractor {
    static func extract(
        from fileURL: URL,
        maxPages: Int = 2
    ) async -> PDFSeed {
        let snapshot = PDFExtractor.extractContent(from: fileURL, maxPages: maxPages)
        let raw = extractRawFields(from: snapshot)
        let normalized = normalize(raw: raw)

        return PDFSeed(
            title: normalized.title,
            titleCandidates: [normalized.title].compactMap { $0 },
            authors: normalized.authors,
            venue: normalized.venue,
            year: normalized.year,
            doi: normalized.doi,
            arxivId: normalized.arxivId,
            abstract: normalized.abstract
        )
    }

    private struct RawFields {
        var title: String?
        var authors: [String]
        var venue: String?
        var year: Int?
        var doi: String?
        var arxivId: String?
        var abstract: String?
    }

    private static func extractRawFields(from snapshot: PDFContentSnapshot) -> RawFields {
        guard !snapshot.rawText.isEmpty else {
            return RawFields(title: nil, authors: [], venue: nil, year: nil, doi: nil, arxivId: nil, abstract: nil)
        }

        let firstPageLines = splitLines(snapshot.firstPageText)
        let allLines = splitLines(snapshot.rawText)
        let title = extractTitle(from: firstPageLines)
        let authors = extractAuthors(from: firstPageLines, title: title)
        let venue = extractVenue(from: firstPageLines)
        let year = extractYear(from: firstPageLines)
        let doi = extractDOI(from: snapshot.rawText)
        let arxivId = extractArxivId(from: snapshot.rawText)
        let abstract = extractAbstract(from: allLines)

        return RawFields(
            title: title,
            authors: authors,
            venue: venue,
            year: year,
            doi: doi,
            arxivId: arxivId,
            abstract: abstract
        )
    }

    private static func normalize(
        raw: RawFields
    ) -> (title: String?, authors: String?, venue: String?, year: Int16, doi: String?, arxivId: String?, abstract: String?) {
        let year: Int16
        if let rawYear = raw.year, (1900...2100).contains(rawYear) {
            year = Int16(rawYear)
        } else {
            year = 0
        }

        let authors = MetadataNormalization.normalizedAuthors(raw.authors).joined(separator: ", ")
        let normalizedAuthors = authors.isEmpty ? nil : authors

        let normalizedDOI = MetadataNormalization.normalizedDOI(raw.doi)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let normalizedArxivID = raw.arxivId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)

        return (
            MetadataNormalization.normalizeTitle(raw.title),
            normalizedAuthors,
            MetadataNormalization.normalizeVenue(raw.venue),
            year,
            normalizedDOI?.isEmpty == false ? normalizedDOI : nil,
            normalizedArxivID?.isEmpty == false ? normalizedArxivID : nil,
            MetadataNormalization.normalizeAbstract(raw.abstract)
        )
    }

    private static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                // Drop OCR/index noise such as "000", "001", ...
                if line.range(of: #"^\d{1,3}$"#, options: .regularExpression) != nil {
                    return false
                }
                return true
            }
            .flatMap(splitMergedArxivAndTitleLine)
            .flatMap(splitMergedVenueAndTitleLine)
    }

    private static func extractTitle(from lines: [String]) -> String? {
        guard !lines.isEmpty else { return nil }
        let limit = min(120, lines.count)
        let prefix = Array(lines.prefix(limit))

        var startIndex: Int?
        for (index, line) in prefix.enumerated() {
            guard isLikelyTitleLine(line) else { continue }
            startIndex = index
            break
        }

        guard let startIndex else { return nil }
        var collected: [String] = []

        for line in prefix[startIndex...] {
            if isTitleBoundary(line) {
                if collected.isEmpty,
                   let inlineTitle = extractInlineTitlePrefix(from: line) {
                    collected.append(inlineTitle)
                }
                break
            }
            if line.count < 4 { break }
            collected.append(line)
            if collected.count >= 3 { break }
        }

        let joined = collected.joined(separator: " ")
        return MetadataNormalization.normalizeTitle(joined)
    }

    private static func extractAuthors(from lines: [String], title: String?) -> [String] {
        guard !lines.isEmpty else { return [] }
        let titleLine = title?.lowercased()
        let limit = min(24, lines.count)
        let prefix = Array(lines.prefix(limit))

        for (index, line) in prefix.enumerated() {
            let lowered = line.lowercased()
            if let titleLine, lowered == titleLine { continue }
            if lowered.contains("abstract") || lowered.contains("introduction") { break }
            if let commaBlockAuthors = extractCommaLeadingAuthorBlock(from: index, lines: prefix) {
                return commaBlockAuthors
            }
            if !looksLikeAuthorLine(line) {
                var stylized: [String] = extractStylizedAuthorNames(from: line)
                if !stylized.isEmpty {
                    var cursor = index + 1
                    while cursor < prefix.count {
                        let continuation = prefix[cursor]
                        let continuationLowered = continuation.lowercased()
                        if continuationLowered.contains("abstract")
                                || continuationLowered.contains("introduction")
                                || looksLikeAffiliationLine(continuation) {
                                break
                        }
                        let stylizedExtra = extractStylizedAuthorNames(from: continuation)
                        let extra = stylizedExtra.isEmpty ? extractDenseAuthorNames(from: continuation) : stylizedExtra
                        if extra.isEmpty { break }
                        stylized.append(contentsOf: extra)
                        cursor += 1
                    }
                }
                let normalizedStylized = MetadataNormalization.normalizedAuthors(stylized)
                if normalizedStylized.count >= 2 {
                    return normalizedStylized
                }
                if isLikelyDenseAuthorLine(line) {
                    var dense = extractDenseAuthorNames(from: line)
                    if !dense.isEmpty {
                        var cursor = index + 1
                        while cursor < prefix.count {
                            let continuation = prefix[cursor]
                            let continuationLowered = continuation.lowercased()
                            if continuationLowered.contains("abstract")
                                || continuationLowered.contains("introduction")
                                || looksLikeAffiliationLine(continuation) {
                                break
                            }
                            let extra = extractDenseAuthorNames(from: continuation)
                            if extra.isEmpty { break }
                            dense.append(contentsOf: extra)
                            cursor += 1
                        }
                    }
                    let normalizedDense = MetadataNormalization.normalizedAuthors(dense)
                    if normalizedDense.count >= 2 {
                        return normalizedDense
                    }
                }
                continue
            }

            var mergedAuthorLine = line
            var cursor = index + 1
            while cursor < prefix.count {
                let continuation = prefix[cursor]
                if isLikelyAuthorContinuationLine(continuation) {
                    mergedAuthorLine += ", " + continuation
                    cursor += 1
                    continue
                }
                break
            }

            let rawTokens = mergedAuthorLine
                .replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
                .split(separator: ",")
                .map { String($0) }
            let stitchedTokens = stitchLikelySplitAuthorTokens(rawTokens)
            let candidates = stitchedTokens
                .compactMap { MetadataNormalization.normalizedAuthorName(cleanAuthorCandidate($0)) }
                .filter { isLikelyPersonName($0) }

            let normalized = MetadataNormalization.normalizedAuthors(candidates)
            if normalized.count >= 2 { return normalized }
        }

        return []
    }

    private static func extractVenue(from lines: [String]) -> String? {
        let limit = min(120, lines.count)
        for index in 0..<limit {
            let line = lines[index]
            let lowered = line.lowercased()
            if lowered.contains("preliminary work")
                || lowered.contains("under review")
                || lowered.contains("anonymous authors") {
                continue
            }
            if lowered.contains("published as")
                || lowered.contains("conference")
                || lowered.contains("workshop")
                || lowered.contains("symposium")
                || lowered.contains("proceedings")
                || lowered.contains("journal") {
                let merged = mergeVenueContinuationIfNeeded(baseLine: line, index: index, lines: lines)
                return MetadataNormalization.normalizeVenue(cleanVenueCandidate(merged))
            }
        }
        return nil
    }

    private static func extractYear(from lines: [String]) -> Int? {
        let limit = min(120, lines.count)

        for index in 0..<limit {
            let line = lines[index]
            let lowered = line.lowercased()
            guard lowered.contains("published as")
                || lowered.contains("conference")
                || lowered.contains("workshop")
                || lowered.contains("symposium")
                || lowered.contains("proceedings")
                || lowered.contains("journal")
                || lowered.contains("copyright") else {
                continue
            }

            let nearby = [line, index > 0 ? lines[index - 1] : "", index + 1 < lines.count ? lines[index + 1] : ""]
            for probe in nearby {
                guard let year = firstMatch(in: probe, pattern: #"\b(19|20)\d{2}\b"#),
                      let value = Int(year),
                      (1900...2100).contains(value) else { continue }
                return value
            }
        }
        return nil
    }

    private static func extractDOI(from text: String) -> String? {
        firstMatch(in: text, pattern: #"10\.\d{4,9}/[-._;()/:A-Za-z0-9]+"#)
    }

    private static func extractArxivId(from text: String) -> String? {
        if let value = firstMatch(
            in: text,
            pattern: #"(?i)\barxiv\s*[:]\s*([a-z\-]+/\d{7}(?:v\d+)?|\d{4}\.\d{4,5}(?:v\d+)?)"#,
            captureGroup: 1
        ) {
            return value
        }
        return firstMatch(
            in: text,
            pattern: #"arxiv\.org/(?:abs|pdf)/([a-z\-]+/\d{7}(?:v\d+)?|\d{4}\.\d{4,5}(?:v\d+)?)(?:\.pdf)?"#,
            captureGroup: 1
        )
    }

    private static func extractAbstract(from lines: [String]) -> String? {
        guard !lines.isEmpty else { return nil }
        guard let abstractIndex = lines.firstIndex(where: isAbstractHeading) else { return nil }

        var chunks: [String] = []
        let headingLine = lines[abstractIndex]
        let inlineAbstract = headingLine
            .replacingOccurrences(of: #"(?i)^abstract[\s:\-]*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !inlineAbstract.isEmpty {
            chunks.append(inlineAbstract)
        }

        var cursor = abstractIndex + 1
        while cursor < lines.count && chunks.joined(separator: " ").count < 1600 {
            let line = lines[cursor]
            if isSectionHeading(line) { break }
            chunks.append(line)
            cursor += 1
        }

        let text = chunks.joined(separator: " ")
        return MetadataNormalization.normalizeAbstract(text)
    }

    private static func isLikelyTitleLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.contains("@") || lowered.contains("http://") || lowered.contains("https://") {
            return false
        }
        if lowered.hasPrefix("published as ") {
            return false
        }
        if lowered.hasPrefix("abstract") || lowered.hasPrefix("introduction") {
            return false
        }
        if lowered.contains("arxiv:") || lowered.contains("doi:") {
            return false
        }
        if isLikelyVenueHeaderLine(line) {
            return false
        }
        if line.range(of: #"^\d{1,3}$"#, options: .regularExpression) != nil {
            return false
        }
        if line.count < 10 || line.count > 180 {
            return false
        }
        return true
    }

    private static func isTitleBoundary(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.hasPrefix("abstract") || lowered.hasPrefix("introduction") {
            return true
        }
        if lowered.contains("anonymous author") {
            return true
        }
        if lowered.contains("@") {
            return true
        }
        if isLikelyCommaLeadingAuthorLine(line) {
            return true
        }
        if looksLikeAuthorLine(line) || looksLikeAffiliationLine(line) {
            return true
        }
        if isLikelyDenseAuthorLine(line) {
            return true
        }
        if isLikelyStylizedAuthorLine(line) {
            return true
        }
        return false
    }

    private static func looksLikeAuthorLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.contains("university") || lowered.contains("institute") || lowered.contains("department") {
            return false
        }
        if isLikelyVenueHeaderLine(line)
            || lowered.contains("preliminary work")
            || lowered.contains("under review")
            || lowered.contains("anonymous authors") {
            return false
        }
        // Regular author lines are typically comma-separated; single-title lines may also contain "and".
        // We handle non-comma superscript styles via `extractStylizedAuthorNames`.
        if !line.contains(",") {
            return false
        }

        let names = line
            .replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
            .split(separator: ",")
            .map { cleanAuthorCandidate(String($0)) }
            .filter { !$0.isEmpty }
        if names.count < 2 { return false }
        if looksLikeUppercaseTitleSegments(names) {
            return false
        }
        let personLike = names.filter { isLikelyPersonName($0) }
        return personLike.count >= 2
    }

    private static func looksLikeUppercaseTitleSegments(_ segments: [String]) -> Bool {
        segments.contains { segment in
            let words = segment
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            guard words.count >= 3 else { return false }
            let hasLowercase = segment.range(of: #"[a-z]"#, options: .regularExpression) != nil
            if hasLowercase { return false }
            let uppercaseLetterCount = segment.unicodeScalars.filter { CharacterSet.uppercaseLetters.contains($0) }.count
            return uppercaseLetterCount >= 6
        }
    }

    private static func looksLikeAffiliationLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.contains("university")
            || lowered.contains("institute")
            || lowered.contains("department")
            || lowered.contains("school of")
            || lowered.contains("laboratory")
    }

    private static func isLikelyDenseAuthorLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.contains("abstract")
            || lowered.contains("introduction")
            || lowered.contains("published as")
            || lowered.contains("arxiv:")
            || lowered.contains("doi:")
            || lowered.contains("http://")
            || lowered.contains("https://")
            || looksLikeAffiliationLine(line)
            || isLikelyVenueHeaderLine(line) {
            return false
        }
        if line.contains(":") {
            return false
        }
        if lowered.range(
            of: #"\b(of|and|for|to|in|on|with|without|from|by|a|an|the)\b"#,
            options: .regularExpression
        ) != nil {
            return false
        }
        let hasMarkerOrDigit = line.range(of: #"[0-9*†‡]"#, options: .regularExpression) != nil
        guard hasMarkerOrDigit else { return false }
        if line.contains(",") {
            return false
        }
        let names = extractDenseAuthorNames(from: line)
        return names.count >= 2
    }

    private static func extractDenseAuthorNames(from line: String) -> [String] {
        let cleaned = line
            .replacingOccurrences(of: #"[*†‡]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        guard let regex = try? NSRegularExpression(
            pattern: #"\b([A-Z][a-zA-Z'\-]+\s+[A-Z][a-zA-Z'\-]+)\b"#
        ) else { return [] }

        let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        var names: [String] = []
        for match in regex.matches(in: cleaned, range: range) {
            guard match.numberOfRanges >= 2,
                  let swiftRange = Range(match.range(at: 1), in: cleaned) else { continue }
            let raw = String(cleaned[swiftRange])
            if let normalized = MetadataNormalization.normalizedAuthorName(raw),
               containsLowercaseNameTokens(normalized),
               isLikelyPersonName(normalized) {
                names.append(normalized)
            }
        }
        return MetadataNormalization.normalizedAuthors(names)
    }

    private static func extractCommaLeadingAuthorBlock(from startIndex: Int, lines: [String]) -> [String]? {
        guard lines.indices.contains(startIndex) else { return nil }
        guard isLikelyCommaLeadingAuthorLine(lines[startIndex]) else { return nil }
        let startsWithComma = lines[startIndex].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(",")
        let nextStartsWithComma: Bool = {
            let next = startIndex + 1
            guard lines.indices.contains(next) else { return false }
            return lines[next].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(",")
        }()
        guard startsWithComma || nextStartsWithComma else { return nil }

        var collected: [String] = []
        var cursor = startIndex
        while cursor < lines.count {
            let line = lines[cursor]
            let lowered = line.lowercased()
            if lowered.contains("abstract")
                || lowered.contains("introduction")
                || looksLikeAffiliationLine(line) {
                break
            }

            let names = extractCommaLeadingAuthorNames(from: line)
            if names.isEmpty {
                if !isLikelyCommaLeadingAuthorLine(line) { break }
            } else {
                collected.append(contentsOf: names)
            }
            cursor += 1
        }

        let normalized = MetadataNormalization.normalizedAuthors(collected)
        return normalized.count >= 2 ? normalized : nil
    }

    private static func isLikelyCommaLeadingAuthorLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.contains("abstract")
            || lowered.contains("introduction")
            || lowered.contains("published as")
            || lowered.contains("arxiv:")
            || lowered.contains("doi:")
            || lowered.contains("http://")
            || lowered.contains("https://")
            || looksLikeAffiliationLine(line)
            || isLikelyVenueHeaderLine(line) {
            return false
        }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "," || trimmed.hasPrefix(",") {
            return true
        }
        guard line.range(of: #"[*†‡]"#, options: .regularExpression) != nil else { return false }
        return !extractCommaLeadingAuthorNames(from: line).isEmpty
    }

    private static func extractCommaLeadingAuthorNames(from line: String) -> [String] {
        let cleaned = line
            .replacingOccurrences(of: #"^\s*,\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*†‡]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        guard let regex = try? NSRegularExpression(
            pattern: #"\b([A-Z][a-zA-Z'\-]+(?:\s+[A-Z]\.)?(?:\s+[A-Z][a-zA-Z'\-]+)+)\b"#
        ) else { return [] }

        let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        var names: [String] = []
        for match in regex.matches(in: cleaned, range: range) {
            guard match.numberOfRanges >= 2,
                  let swiftRange = Range(match.range(at: 1), in: cleaned) else { continue }
            let raw = String(cleaned[swiftRange])
            if let normalized = MetadataNormalization.normalizedAuthorName(raw),
               isLikelyPersonName(normalized) {
                names.append(normalized)
            }
        }
        return MetadataNormalization.normalizedAuthors(names)
    }

    private static func containsLowercaseNameTokens(_ value: String) -> Bool {
        let parts = value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            part.range(of: #"[a-z]"#, options: .regularExpression) != nil
        }
    }

    private static func cleanAuthorCandidate(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\d+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[†‡*]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
    }

    private static func isLikelyPersonName(_ value: String) -> Bool {
        let parts = value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard (2...5).contains(parts.count) else { return false }
        return parts.allSatisfy { part in
            let cleaned = part.trimmingCharacters(in: .punctuationCharacters)
            guard let first = cleaned.first else { return false }
            return first.isLetter
        }
    }

    private static func extractStylizedAuthorNames(from line: String) -> [String] {
        let lowered = line.lowercased()
        if lowered.contains("@")
            || lowered.contains("correspondence")
            || lowered.contains("university")
            || lowered.contains("institute")
            || lowered.contains("department")
            || isLikelyVenueHeaderLine(line)
            || lowered.contains("preliminary work")
            || lowered.contains("under review")
            || lowered.contains("anonymous authors") {
            return []
        }
        let markerSeparated = extractMarkerSeparatedAuthorNames(from: line)
        if markerSeparated.count >= 2 {
            return markerSeparated
        }
        guard isLikelyStylizedAuthorLine(line) else { return [] }

        let markerSource = line
        if let markerRegex = try? NSRegularExpression(
            pattern: markerBoundAuthorPattern
        ) {
            let range = NSRange(markerSource.startIndex..<markerSource.endIndex, in: markerSource)
            var markerNames: [String] = []
            for match in markerRegex.matches(in: markerSource, range: range) {
                guard match.numberOfRanges >= 2,
                      let swiftRange = Range(match.range(at: 1), in: markerSource) else { continue }
                let raw = String(markerSource[swiftRange])
                if let normalized = MetadataNormalization.normalizedAuthorName(raw),
                   isLikelyPersonName(normalized) {
                    markerNames.append(normalized)
                }
            }
            let normalized = MetadataNormalization.normalizedAuthors(markerNames)
            if normalized.count >= 2 {
                return normalized
            }
        }

        let cleaned = line
            .replacingOccurrences(of: #"\d+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[†‡*]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        guard let regex = try? NSRegularExpression(pattern: #"\b([A-Z][a-zA-Z'\-]+\s+[A-Z][a-zA-Z'\-]+)\b"#) else {
            return []
        }
        let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        let matches = regex.matches(in: cleaned, range: range)

        let blacklist: Set<String> = [
            "Abstract", "Introduction", "Proceedings", "Conference", "Machine Learning", "Large Language Models"
        ]
        var names: [String] = []
        for match in matches {
            guard match.numberOfRanges >= 2,
                  let swiftRange = Range(match.range(at: 1), in: cleaned) else { continue }
            let raw = String(cleaned[swiftRange])
            let normalized = MetadataNormalization.normalizedAuthorName(raw) ?? raw
            if blacklist.contains(normalized) { continue }
            if containsLowercaseNameTokens(normalized), isLikelyPersonName(normalized) {
                names.append(normalized)
            }
        }
        return names
    }

    private static func extractMarkerSeparatedAuthorNames(from line: String) -> [String] {
        guard line.range(of: #"\d"#, options: .regularExpression) != nil else { return [] }
        let candidateLine = trimLeadingTitleContextFromMarkedAuthorLine(line)
        guard let markerRegex = try? NSRegularExpression(
            pattern: markerBoundAuthorPattern
        ) else { return [] }

        let range = NSRange(candidateLine.startIndex..<candidateLine.endIndex, in: candidateLine)
        var names: [String] = []
        for match in markerRegex.matches(in: candidateLine, range: range) {
            guard match.numberOfRanges >= 2,
                  let swiftRange = Range(match.range(at: 1), in: candidateLine) else { continue }
            let raw = String(candidateLine[swiftRange])
            if let normalized = MetadataNormalization.normalizedAuthorName(raw),
               isLikelyPersonName(normalized) {
                names.append(normalized)
            }
        }
        let markerNames = MetadataNormalization.normalizedAuthors(names)
        let denseNames = extractDenseAuthorNames(from: candidateLine)
        if denseNames.count > markerNames.count {
            return MetadataNormalization.normalizedAuthors(markerNames + denseNames)
        }
        return markerNames
    }

    private static func extractInlineTitlePrefix(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let prefix = extractInlinePrefixBeforeMarkedAuthorSpan(in: trimmed) ?? trimmed
        let normalized = MetadataNormalization.normalizeTitle(prefix)
        guard let normalized, normalized.count >= 10 else { return nil }
        return normalized
    }

    private static func trimLeadingTitleContextFromMarkedAuthorLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return line }
        guard let prefix = extractInlinePrefixBeforeMarkedAuthorSpan(in: trimmed),
              !prefix.isEmpty else {
            return trimmed
        }
        let start = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
        let suffix = String(trimmed[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? trimmed : suffix
    }

    private static func extractInlinePrefixBeforeMarkedAuthorSpan(in line: String) -> String? {
        guard let boundaryRegex = try? NSRegularExpression(
            pattern: markerBoundAuthorBoundaryPattern
        ) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = boundaryRegex.firstMatch(in: line, range: range),
              let swiftRange = Range(match.range, in: line) else { return nil }
        let prefix = String(line[..<swiftRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? nil : prefix
    }

    private static let markerBoundAuthorPattern =
        #"\b([A-Z][a-zA-Z'\-]+(?:\s+(?:[A-Z]\.|[A-Z][a-z]{1,3}))?\s+[A-Z][a-zA-Z'\-]+)\s*[*†‡]?\s*\d+\b"#

    private static let markerBoundAuthorBoundaryPattern =
        #"\b[A-Z][a-zA-Z'\-]+\s+[A-Z][a-zA-Z'\-]+\s*[*†‡]?\s*\d+\b"#

    private static func isLikelyStylizedAuthorLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.hasPrefix("abstract") || lowered.hasPrefix("introduction") {
            return false
        }
        if isLikelyVenueHeaderLine(line)
            || lowered.contains("preliminary work")
            || lowered.contains("under review")
            || lowered.contains("anonymous authors") {
            return false
        }
        // Stylized author lines usually carry affiliation markers such as superscript digits/symbols.
        let hasMarkers = line.range(of: #"[0-9*†‡]"#, options: .regularExpression) != nil
        guard hasMarkers else { return false }

        guard let regex = try? NSRegularExpression(pattern: #"\b[A-Z][a-zA-Z'\-]+(?:\s+[A-Z][a-zA-Z'\-]+){1,2}\b"#) else {
            return false
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let count = regex.numberOfMatches(in: line, range: range)
        return count >= 2
    }

    private static func isLikelyAuthorContinuationLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.contains("abstract")
            || lowered.contains("introduction")
            || lowered.contains("correspondence")
            || looksLikeAffiliationLine(line)
            || isLikelyVenueHeaderLine(line)
            || lowered.contains("preliminary work")
            || lowered.contains("under review") {
            return false
        }
        // Continuations often start with a trailing surname and include separators/author markers.
        if line.contains(",")
            || line.range(of: #"[0-9*†‡]"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func isLikelyVenueHeaderLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.hasPrefix("proceedings of")
            || lowered.hasPrefix("proceeding of")
            || lowered.hasPrefix("in proceedings of") {
            return true
        }
        if lowered.contains("conference on")
            || lowered.contains("symposium on")
            || lowered.contains("workshop on")
            || lowered.contains("journal of") {
            return true
        }
        return false
    }

    private static func stitchLikelySplitAuthorTokens(_ rawTokens: [String]) -> [String] {
        var output: [String] = []
        var index = 0

        func isSingleNameToken(_ token: String) -> Bool {
            let cleaned = cleanAuthorCandidate(token)
            let parts = cleaned.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            guard parts.count == 1, let word = parts.first else { return false }
            guard word.count >= 2 else { return false }
            guard let first = word.first, first.isUppercase else { return false }
            return word.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" }
        }

        while index < rawTokens.count {
            let current = rawTokens[index]
            if index + 1 < rawTokens.count,
               isSingleNameToken(current),
               isSingleNameToken(rawTokens[index + 1]) {
                output.append(current + " " + rawTokens[index + 1])
                index += 2
                continue
            }
            output.append(current)
            index += 1
        }
        return output
    }

    private static func mergeVenueContinuationIfNeeded(baseLine: String, index: Int, lines: [String]) -> String {
        var merged = baseLine
        guard index + 1 < lines.count else { return merged }

        let next = lines[index + 1]
        let nextLowered = next.lowercased()
        let nextLooksLikeVenueContinuation =
            nextLowered.contains("pmlr")
            || nextLowered.contains("proceedings")
            || nextLowered.contains("conference")
            || nextLowered.contains("journal")
            || next.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil

        if nextLooksLikeVenueContinuation {
            merged += " " + next
        }
        return merged
    }

    private static func cleanVenueCandidate(_ value: String) -> String {
        var cleaned = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        cleaned = cleaned.replacingOccurrences(
            of: #"^.*?\b(Published as\b.*)$"#,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"^\d+\s*(?=Proceedings\b)"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?i),\s*pages\s+\d+\s*[–-]\s*\d+.*$"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\bCopyright\b.*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\bCorrespondence to:.*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isAbstractHeading(_ line: String) -> Bool {
        line.range(of: #"(?i)^abstract(?:[\s:\-]|$)"#, options: .regularExpression) != nil
    }

    private static func isSectionHeading(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.range(of: #"^(keywords|index terms|introduction|references|acknowledg(e)?ments?)$"#, options: .regularExpression) != nil {
            return true
        }
        if lowered.hasPrefix("doi:") || lowered.hasPrefix("arxiv:") {
            return true
        }
        if lowered.range(of: #"^\d+(\.\d+)*\s+[a-z]"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func splitMergedVenueAndTitleLine(_ line: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^(published as .*?\b(?:19|20)\d{2})\s+([A-Z][A-Z0-9\-: ]{10,})$"#
        ) else {
            return [line]
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges == 3,
              let venueRange = Range(match.range(at: 1), in: line),
              let titleRange = Range(match.range(at: 2), in: line) else {
            return [line]
        }

        let venue = line[venueRange].trimmingCharacters(in: .whitespacesAndNewlines)
        let title = line[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
        if venue.isEmpty || title.isEmpty {
            return [line]
        }
        return [venue, title]
    }

    private static func splitMergedArxivAndTitleLine(_ line: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^(arxiv:[^\n]*?(?:19|20)\d{2})\s+([A-Z][A-Z0-9\-: ]{10,})$"#
        ) else {
            return [line]
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges == 3,
              let prefixRange = Range(match.range(at: 1), in: line),
              let titleRange = Range(match.range(at: 2), in: line) else {
            return [line]
        }

        let prefix = line[prefixRange].trimmingCharacters(in: .whitespacesAndNewlines)
        let title = line[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
        if prefix.isEmpty || title.isEmpty {
            return [line]
        }
        return [prefix, title]
    }

    private static func firstMatch(in text: String, pattern: String, captureGroup: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              captureGroup < match.numberOfRanges,
              let swiftRange = Range(match.range(at: captureGroup), in: text) else {
            return nil
        }
        return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
