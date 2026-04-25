import Foundation

public struct PDFSeed {
    public let title: String?
    public let titleCandidates: [String]
    public let authors: String?
    public let venue: String?
    public let year: Int16
    public let doi: String?
    public let arxivId: String?
    public let abstract: String?
}

public extension PDFSeed {
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

public enum PDFSeedExtractor {
    public static func extract(
        from fileURL: URL,
        maxPages: Int = 2
    ) -> PDFSeed {
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

        let allRichLines = snapshot.pages.flatMap(\.lines)
        let allPageTexts = allRichLines.map(\.text)
        let allLines = splitLines(snapshot.rawText)
        let blocks = extractTypographicBlocks(from: allRichLines)
        let contentStartIndex = allRichLines.firstIndex {
            isAbstractHeading($0.text)
            || $0.text.lowercased() == "introduction"
            || $0.text.lowercased().hasPrefix("1. introduction")
            || $0.text.lowercased().hasPrefix("i. introduction")
        } ?? allRichLines.count
        let title = extractTitle(from: blocks, abstractLineIndex: contentStartIndex)
        let authors = extractAuthors(from: blocks, title: title, abstractLineIndex: contentStartIndex)
        let venue = extractVenue(from: allPageTexts)
        let year = extractYear(from: allPageTexts)
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

    private struct TypographicBlock: Sendable, Equatable {
        let fontSize: CGFloat
        let lines: [String]
        let startIndex: Int
        let endIndex: Int
        let isBold: Bool
        let isItalic: Bool
        var text: String { lines.joined(separator: " ") }
    }

    private static func extractTypographicBlocks(from lines: [PDFContentLine]) -> [TypographicBlock] {
        guard !lines.isEmpty else { return [] }
        var blocks: [TypographicBlock] = []
        var currentLines: [String] = [lines[0].text]
        var currentFontSize = lines[0].fontSize
        var currentIsBold = lines[0].isBold
        var currentIsItalic = lines[0].isItalic
        var startIndex = 0
        for i in 1..<lines.count {
            let line = lines[i]
            let ratio = min(line.fontSize, currentFontSize) / max(line.fontSize, currentFontSize)
            // Group lines into the same typographic block when their font sizes are
            // visually indistinguishable: either within 5% ratio or < 0.5pt absolute delta.
            if ratio >= 0.95 || abs(line.fontSize - currentFontSize) < 0.5 {
                currentLines.append(line.text)
                if line.isBold { currentIsBold = true }
                if line.isItalic { currentIsItalic = true }
            } else {
                blocks.append(TypographicBlock(fontSize: currentFontSize, lines: currentLines, startIndex: startIndex, endIndex: i, isBold: currentIsBold, isItalic: currentIsItalic))
                currentLines = [line.text]
                currentFontSize = line.fontSize
                currentIsBold = line.isBold
                currentIsItalic = line.isItalic
                startIndex = i
            }
        }
        blocks.append(TypographicBlock(fontSize: currentFontSize, lines: currentLines, startIndex: startIndex, endIndex: lines.count, isBold: currentIsBold, isItalic: currentIsItalic))
        return blocks
    }

    private static func isVenueHeaderOrCopyrightBlock(_ block: TypographicBlock) -> Bool {
        let text = block.text.lowercased()
        if text.contains("content may change") || text.contains("all rights reserved") { return true }
        if text.contains("publishers") || text.contains("manufactured") || text.contains("copyright") { return true }
        if block.text.range(of: #",\s*\d{1,4}\s*[–-]\s*\d{1,4}\s*,\s*\d{4}"#, options: .regularExpression) != nil { return true }
        if isLikelyVenueHeaderLine(block.text) { return true }
        // arXiv-derived publication markers (e.g. "Published as a conference paper at ICLR 2025")
        if text.contains("published as a conference paper") || text.contains("published as a workshop paper") { return true }

        return false
    }

    private static func extractTitleLinesFromBlock(_ block: TypographicBlock) -> [String] {
        var titleLines: [String] = []
        for line in block.lines {
            let lowered = line.lowercased()
            // Only break on standalone Abstract/Introduction headings, not on titles
            // that contain these words (e.g. "Abstract Interpretation for...")
            if lowered == "abstract" || lowered == "introduction"
                || lowered.hasPrefix("abstract ") || lowered.hasPrefix("introduction ")
                || lowered.hasPrefix("abstract:") || lowered.hasPrefix("introduction:")
                || lowered.hasPrefix("abstract-") || lowered.hasPrefix("introduction-") {
                break
            }
            if line.contains("@") { break }
            if looksLikeAffiliationLine(line) { break }
            if looksLikeAuthorLine(line) { break }
            // Within the same typographic block, allow up to 4 title lines before
            // enabling body-text truncation. Long descriptive titles (5–9 words)
            // often span 3+ lines and would otherwise be truncated by looksLikeBodyText.
            if looksLikeBodyText(line) && titleLines.count >= 5 { break }
            // Skip arXiv header lines that are mixed into the title block
            if lowered.hasPrefix("arxiv:") && line.range(of: #"\d{4}\.\d{5}"#, options: .regularExpression) != nil {
                continue
            }
            // Break on venue/journal header lines
            if (lowered.contains("ieee transactions") || lowered.contains("acm transactions") || lowered.contains("transactions on")) && lowered.contains("vol.") {
                break
            }
            titleLines.append(line)
        }
        return titleLines
    }

    // MARK: - Score-based Title Selection

    private struct TitleCandidate {
        let text: String
        let block: TypographicBlock
        let score: Double
    }

    private static func scoreTitleCandidate(
        text: String,
        block: TypographicBlock,
        allBlocks: [TypographicBlock],
        maxFontSize: CGFloat,
        bodyBaseline: CGFloat
    ) -> Double {
        var score: Double = 0

        // 1. Font size: larger is better, weighted heavily (0–25).
        // Use body baseline as the reference instead of maxFontSize,
        // because maxFontSize can be distorted by drop caps, logos, or outliers.
        // Typical paper titles are 1.5–2.5× the body baseline.
        let baselineRatio = bodyBaseline > 0 ? Double(block.fontSize / bodyBaseline) : 0
        score += min(baselineRatio * 15, 30)

        // Also retain a mild relative-to-max bonus for intra-page competition
        let maxRatio = maxFontSize > 0 ? Double(block.fontSize / maxFontSize) : 0
        score += maxRatio * 10

        // 2. Length sweet spot: 30–120 chars is ideal
        let length = text.count
        switch length {
        case 30...120:  score += 20
        case 15..<30:   score += 10
        case 120...200: score += 10
        case ..<15:     score -= 20
        default:        score -= 10
        }

        // 4. Position: earlier blocks are more likely to be the title
        if let index = allBlocks.firstIndex(where: { $0.startIndex == block.startIndex }) {
            if index <= 2 {
                score += 15
            } else if index <= 5 {
                score += 5
            } else {
                score -= min(Double(index) * 2, 20)
            }
        }

        // 3. Content penalties
        let lowered = text.lowercased()
        if lowered.contains("abstract") || lowered.contains("introduction") {
            score -= 20
        }
        if isLikelyVenueHeaderLine(text) {
            score -= 30
        }

        return score
    }

    private static func computeBodyBaseline(from blocks: [TypographicBlock]) -> CGFloat {
        // Compute the mode (most common) font size among all blocks.
        // Body text blocks outnumber title blocks, so the mode is a robust baseline.
        var sizeCounts: [CGFloat: Int] = [:]
        for block in blocks {
            let rounded = round(block.fontSize * 10) / 10
            sizeCounts[rounded, default: 0] += block.lines.count
        }
        if let mostCommon = sizeCounts.max(by: { $0.value < $1.value }) {
            return mostCommon.key
        }
        return 10
    }

    private static func extractTitle(from blocks: [TypographicBlock], abstractLineIndex: Int = Int.max) -> String? {
        let contentBlocks = blocks.filter { !isVenueHeaderOrCopyrightBlock($0) }
        guard !contentBlocks.isEmpty else { return nil }
        // Filter out oversized fonts (>28pt) which are usually section headings,
        // figure captions, diagrams, or poster titles — not paper titles.
        let reasonableBlocks = contentBlocks.filter { $0.fontSize <= 28 }
        let candidatePool = reasonableBlocks.isEmpty ? contentBlocks : reasonableBlocks
        let maxFontSize = candidatePool.map(\.fontSize).max() ?? 1

        // Compute body baseline: the most common font size on the page.
        // This is more stable than maxFontSize for title scoring.
        let bodyBaseline = computeBodyBaseline(from: blocks)

        var candidates: [TitleCandidate] = []

        for candidate in candidatePool {
            guard candidate.startIndex < abstractLineIndex else { continue }
            let titleLines = extractTitleLinesFromBlock(candidate)
            let joined = titleLines.joined(separator: " ")
            guard let normalized = MetadataNormalization.normalizeTitle(joined) else { continue }
            // Reject URL-only candidates (JSTOR terms pages, etc.)
            if normalized.range(of: #"^https?://"#, options: .regularExpression) != nil { continue }

            var bestText = normalized

            // Try subtitle merge for short titles
            if normalized.count < 30,
               candidate.lines.count == 1,
               let originalIndex = blocks.firstIndex(where: { $0.startIndex == candidate.startIndex }),
               originalIndex + 1 < blocks.count {
                let nextBlock = blocks[originalIndex + 1]
                if !isVenueHeaderOrCopyrightBlock(nextBlock)
                    && nextBlock.fontSize < candidate.fontSize
                    && nextBlock.fontSize >= candidate.fontSize * 0.65
                    && nextBlock.fontSize >= 12 {
                    let nextTitleLines = extractTitleLinesFromBlock(nextBlock)
                    let nextJoined = nextTitleLines.joined(separator: " ")
                    if nextJoined.count > 30
                        && !nextJoined.contains("@")
                        && !looksLikeAffiliationLine(nextJoined)
                        && !nextJoined.lowercased().contains("abstract")
                        && !nextJoined.lowercased().contains("introduction") {
                        let mergedLines = titleLines + nextTitleLines
                        let mergedJoined = mergedLines.joined(separator: " ")
                        if let mergedNormalized = MetadataNormalization.normalizeTitle(mergedJoined),
                           mergedNormalized.count > normalized.count + 10 {
                            bestText = mergedNormalized
                        }
                    }
                }
            }

            // Try hyphenated continuation
            if bestText.hasSuffix("-"),
               candidate.lines.count == 1,
               let originalIndex = blocks.firstIndex(where: { $0.startIndex == candidate.startIndex }),
               originalIndex + 1 < blocks.count {
                let nextBlock = blocks[originalIndex + 1]
                if !isVenueHeaderOrCopyrightBlock(nextBlock)
                    && nextBlock.fontSize < candidate.fontSize
                    && nextBlock.fontSize >= candidate.fontSize * 0.65
                    && nextBlock.fontSize >= 12 {
                    let nextText = nextBlock.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if nextText.count > 3 && nextText.count < 30,
                       !nextText.contains("@"),
                       !looksLikeAffiliationLine(nextText),
                       !nextText.lowercased().contains("abstract"),
                       !nextText.lowercased().contains("introduction") {
                        let base = String(bestText.dropLast())
                        let merged = base + nextText
                        if let mergedNormalized = MetadataNormalization.normalizeTitle(merged),
                           mergedNormalized.count > bestText.count + 3 {
                            bestText = mergedNormalized
                        }
                    }
                }
            }

            let score = scoreTitleCandidate(text: bestText, block: candidate, allBlocks: blocks, maxFontSize: maxFontSize, bodyBaseline: bodyBaseline)
            candidates.append(TitleCandidate(text: bestText, block: candidate, score: score))
        }

        // Fallback: only scan short titles if no viable candidates were found
        if candidates.isEmpty {
            for candidate in candidatePool {
                guard candidate.startIndex < abstractLineIndex else { continue }
                let titleLines = extractTitleLinesFromBlock(candidate)
                let joined = titleLines.joined(separator: " ")
                if let normalized = MetadataNormalization.normalizeTitle(joined), normalized.count < 15 {
                    let score = scoreTitleCandidate(text: normalized, block: candidate, allBlocks: blocks, maxFontSize: maxFontSize, bodyBaseline: bodyBaseline)
                    candidates.append(TitleCandidate(text: normalized, block: candidate, score: score))
                }
            }
        }

        candidates.sort(by: { $0.score > $1.score })
        return candidates.first?.text
    }

    private static func extractAuthorsFromBlock(_ block: TypographicBlock) -> [String] {
        let text = block.text
        if looksLikeAuthorLine(text) {
            var names: [String] = []
            for line in block.lines {
                let lineNames = line
                    .split(separator: ",")
                    .map { cleanAuthorCandidate(String($0)) }
                    .filter { !$0.isEmpty }
                names.append(contentsOf: lineNames)
            }
            let personLike = names.filter { isLikelyPersonName($0) }
            if personLike.count >= 2 {
                return personLike
            }
        }
        // Skip blocks that are clearly figure captions or diagram labels
        let loweredText = text.lowercased()
        if loweredText.contains("figure") || loweredText.contains("table") {
            return []
        }

        let stylized = extractStylizedAuthorNames(from: text)
        if stylized.count >= 2 {
            return stylized
        }
        // Skip dense extraction on blocks that are clearly affiliation/institution text
        let hasInstitutionKeyword = loweredText.contains("university") || loweredText.contains("department")
            || loweredText.contains("institute") || loweredText.contains("laboratory")
            || loweredText.contains("foundation") || loweredText.contains("college")
            || loweredText.contains("school of")
        let dense: [String]
        if !hasInstitutionKeyword {
            dense = extractDenseAuthorNames(from: text)
            let normalizedDense = dense.compactMap { MetadataNormalization.normalizedAuthorName($0) }
            if normalizedDense.count >= 2 {
                return normalizedDense
            }
        } else {
            dense = []
        }

        // Per-line single-author scanning for multi-line blocks (e.g. author + email/affiliation)
        var lineAuthors: [String] = []
        for line in block.lines {
            if line.contains("@") { continue }
            if looksLikeAffiliationLine(line) {
                if !lineAuthors.isEmpty { break } else { continue }
            }
            if looksLikeBodyText(line) && lineAuthors.isEmpty { continue }
            let lowered = line.lowercased()
            if lowered.contains("abstract") || lowered.contains("introduction") { break }
            // JSTOR-style "Author(s): Name1 and Name2"
            if lowered.hasPrefix("author") && line.contains(":") {
                let suffix = String(line.drop(while: { $0 != ":" }).dropFirst())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let names = suffix
                    .split(separator: ",")
                    .map { cleanAuthorCandidate(String($0)) }
                    .filter { !$0.isEmpty }
                let personLike = names.filter { isLikelyPersonName($0) }
                if personLike.count >= 2 {
                    return personLike
                }
                let dense = extractDenseAuthorNames(from: suffix)
                let normalizedDense = dense.compactMap { MetadataNormalization.normalizedAuthorName($0) }
                if normalizedDense.count >= 2 {
                    return normalizedDense
                }
                continue
            }
            // Standard comma-separated author lines (per-line, so institution text in same block doesn't block)
            if looksLikeAuthorLine(line) {
                let names = line
                    .split(separator: ",")
                    .map { cleanAuthorCandidate(String($0)) }
                    .filter { !$0.isEmpty }
                let personLike = names.filter { isLikelyPersonName($0) }
                if personLike.count >= 1 {
                    lineAuthors.append(contentsOf: personLike)
                }
                continue
            }
            // Stylized space-separated author lines with markers (per-line to avoid institution-block guard)
            let stylized = extractStylizedAuthorNames(from: line)
            let stylizedThreshold = lineAuthors.isEmpty ? 2 : 1
            if stylized.count >= stylizedThreshold {
                lineAuthors.append(contentsOf: stylized)
                continue
            }
            // Dense author name extraction
            let lineDense = extractDenseAuthorNames(from: line)
            let effectiveDense = lineDense
            let denseThreshold = lineAuthors.isEmpty ? 2 : 1
            if effectiveDense.count >= denseThreshold {
                lineAuthors.append(contentsOf: effectiveDense.compactMap { MetadataNormalization.normalizedAuthorName($0) })
                continue
            }
            if effectiveDense.count == 1 && line.count <= 35 {
                if let normalized = MetadataNormalization.normalizedAuthorName(effectiveDense[0]) {
                    lineAuthors.append(normalized)
                    continue
                }
            }
            // If we're already accumulating authors, skip comma-only continuation lines
            // and break on any other non-author line.
            if !lineAuthors.isEmpty {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == "," || trimmed.hasPrefix(",") {
                    continue
                }
                break
            }
        }
        if lineAuthors.count >= 2 {
            return lineAuthors
        }
        return []
    }

    // MARK: - Score-based Author Selection

    private struct AuthorCandidate {
        let authors: [String]
        let block: TypographicBlock
        let score: Double
    }

    private static func scoreAuthorList(
        _ authors: [String],
        block: TypographicBlock,
        blockIndex: Int,
        titleBlockIndex: Int?
    ) -> Double {
        var score: Double = 0

        // 1. Author count: sweet spot is 2–8
        let count = authors.count
        switch count {
        case 3...8:   score += 20
        case 2:       score += 15
        case 9...15:  score += 10
        case 16...30: score += 5
        case 1:       score += 3
        default:      score -= 10
        }

        // 2. Distance from title block: closer is better
        if let tbi = titleBlockIndex {
            let distance = blockIndex - tbi
            switch distance {
            case 1:  score += 15
            case 2:  score += 10
            case 3:  score += 5
            case 4...5: score += 3
            default: score -= min(Double(distance) * 2, 15)
            }
        }

        // 3. Person-name ratio: higher is better
        let personCount = authors.filter { isLikelyPersonName($0) }.count
        let personRatio = authors.isEmpty ? 0 : Double(personCount) / Double(authors.count)
        score += personRatio * 15

        // 4. Institution penalty
        let lowered = block.text.lowercased()
        let institutionWords = ["university", "department", "institute", "laboratory",
                                "foundation", "college", "school of"]
        if institutionWords.contains(where: { lowered.contains($0) }) {
            score -= 20
        }

        return score
    }

    private static func extractAuthors(from blocks: [TypographicBlock], title: String?, abstractLineIndex: Int = Int.max) -> [String] {
        guard !blocks.isEmpty else { return [] }
        let titleBlockIndex = blocks.firstIndex { block in
            guard let t = title else { return false }
            let blockText = block.text
            if blockText.contains(t) { return true }
            if t.contains(blockText) && blockText.count > 20 { return true }
            return false
        }

        var candidates: [AuthorCandidate] = []
        let scanStart = titleBlockIndex.map { $0 + 1 } ?? 0

        for i in scanStart..<blocks.count {
            let block = blocks[i]
            if block.startIndex >= abstractLineIndex { break }
            if block.fontSize < 6 { continue }
            if let t = title, t.contains(block.text) { continue }
            if isVenueHeaderOrCopyrightBlock(block) {
                if block.lines.contains(where: { isAbstractHeading($0) || $0.lowercased() == "introduction" }) {
                    break
                }
                continue
            }

            let blockAuthors = extractAuthorsFromBlock(block)
            if !blockAuthors.isEmpty {
                let score = scoreAuthorList(blockAuthors, block: block, blockIndex: i, titleBlockIndex: titleBlockIndex)
                candidates.append(AuthorCandidate(authors: blockAuthors, block: block, score: score))
            }

            if block.lines.contains(where: { isAbstractHeading($0) || $0.lowercased() == "introduction" }) {
                break
            }
            if block.lines.allSatisfy({ looksLikeAffiliationLine($0) || $0.contains("@") }) {
                break
            }
        }

        // Title block remaining lines
        if let titleBlockIdx = titleBlockIndex {
            let titleBlock = blocks[titleBlockIdx]
            let titleLines = extractTitleLinesFromBlock(titleBlock)
            if titleBlock.lines.first == titleLines.first {
                let remainingLines = Array(titleBlock.lines.dropFirst(titleLines.count))
                if !remainingLines.isEmpty {
                    let remainingBlock = TypographicBlock(
                        fontSize: titleBlock.fontSize,
                        lines: remainingLines,
                        startIndex: titleBlock.startIndex + titleLines.count,
                        endIndex: titleBlock.endIndex,
                        isBold: titleBlock.isBold,
                        isItalic: titleBlock.isItalic
                    )
                    let remainingAuthors = extractAuthorsFromBlock(remainingBlock)
                    if !remainingAuthors.isEmpty {
                        let score = scoreAuthorList(remainingAuthors, block: remainingBlock, blockIndex: titleBlockIdx, titleBlockIndex: titleBlockIndex)
                        candidates.append(AuthorCandidate(authors: remainingAuthors, block: remainingBlock, score: score))
                    }
                }
            }
        }

        // Prefer multi-author candidates by score
        let multiAuthorCandidates = candidates.filter { $0.authors.count >= 2 }
        if !multiAuthorCandidates.isEmpty {
            let best = multiAuthorCandidates.max(by: { $0.score < $1.score })!
            return MetadataNormalization.normalizedAuthors(best.authors)
        }

        // Fallback: accumulate single-author candidates
        let singleCandidates = candidates.filter { $0.authors.count == 1 }
        if !singleCandidates.isEmpty {
            let allSingles = singleCandidates.flatMap { $0.authors }
            return MetadataNormalization.normalizedAuthors(allSingles)
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
        // Cap abstract length at ~1600 chars to avoid pulling in the entire introduction.
        while cursor < lines.count && chunks.joined(separator: " ").count < 1600 {
            let line = lines[cursor]
            if isSectionHeading(line) { break }
            chunks.append(line)
            cursor += 1
        }

        let text = chunks.joined(separator: " ")
        return MetadataNormalization.normalizeAbstract(text)
    }

    /// Detects prose-style body text (as opposed to title text).
    /// Used to cut off title collection when the font size hasn't changed
    /// but the content has clearly shifted into the abstract/introduction.
    private static func looksLikeBodyText(_ line: String) -> Bool {
        let words = line
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && $0.allSatisfy({ $0.isLetter }) }
        let lowercaseWords = words.filter { word in
            guard let first = word.first else { return false }
            return first.isLowercase && word.count > 2
        }
        return lowercaseWords.count >= 4
    }

    private static func looksLikeAuthorLine(_ line: String) -> Bool {
        // Reject body text immediately — paragraphs with many lowercase words are never author lines.
        if looksLikeBodyText(line) {
            return false
        }
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
            
            .split(separator: ",")
            .map { cleanAuthorCandidate(String($0)) }
            .filter { !$0.isEmpty }
        if names.count < 2 { return false }

        let personLike = names.filter { name in
            guard name.count <= 30 else { return false }
            return isLikelyPersonName(name)
        }
        return personLike.count >= 2
    }

    private static func looksLikeAffiliationLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.contains("university")
            || lowered.contains("institute")
            || lowered.contains("department")
            || lowered.contains("school of")
            || lowered.contains("laboratory")
            || lowered.contains("research center")
            || lowered.contains("college")
            || lowered.contains("academy")
    }

    private static func extractDenseAuthorNames(from line: String) -> [String] {
        let cleaned = stripAuthorMarkers(from: line, replacement: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        // Note: no trailing \b because names may be glued to digits (e.g. "Wang1")
        // and \b does not match between a letter and a digit in ICU.
        guard let regex = try? NSRegularExpression(
            pattern: #"\b([A-Z][a-zA-Z'\-]+(?:\s+[A-Z]\.){0,2}(?:\s+[A-Z][a-zA-Z'\-]+))"#
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

    private static func containsLowercaseNameTokens(_ value: String) -> Bool {
        let parts = value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard parts.count >= 2 else { return false }
        // Allow all-caps names with middle initials (e.g. "LUDMILA I. KUNCHEVA")
        let hasInitial = parts.contains { $0.range(of: #"^[A-Z]\.$"#, options: .regularExpression) != nil }
        if hasInitial { return true }
        let commonAcronyms: Set<String> = ["AI", "ML", "LLM", "RL", "NLP", "CV"]
        // Require at least one part to contain lowercase letters (or be a known acronym).
        // Requiring ALL parts to have lowercase was over-filtering Chinese surnames
        // (e.g. "Xunzhuo Liu" — "Liu" has no lowercase but is clearly a name).
        return parts.contains { part in
            if commonAcronyms.contains(part.uppercased()) { return true }
            return part.range(of: #"[a-z]"#, options: .regularExpression) != nil
        }
    }

    private static func stripAuthorMarkers(from value: String, replacement: String = "") -> String {
        value
            .replacingOccurrences(of: "*", with: replacement)
            .replacingOccurrences(of: "\u{2217}", with: replacement)
            .replacingOccurrences(of: "†", with: replacement)
            .replacingOccurrences(of: "‡", with: replacement)
    }

    private static func cleanAuthorCandidate(_ value: String) -> String {
        stripAuthorMarkers(from: value)
            .replacingOccurrences(of: #"\d+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
    }

    private static func isLikelyPersonName(_ value: String) -> Bool {
        let parts = value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard (2...5).contains(parts.count) else { return false }
        // Reject tokens that contain lowercase words longer than 4 chars — these are
        // almost certainly common English words (e.g. "introduce", "comparable")
        // rather than name particles like "van", "der", "de".
        let longLowercaseCount = parts.filter { part in
            let cleaned = part.trimmingCharacters(in: .punctuationCharacters)
            guard let first = cleaned.first else { return false }
            return first.isLowercase && cleaned.count > 4
        }.count
        guard longLowercaseCount == 0 else { return false }
        let lowered = value.lowercased()
        // Reject common institutional/team/corporate keywords
        let institutionWords = [
            "team", "lab", "laboratory", "group", "inc", "ltd",
            "research", "artificial", "intelligence", "school", "college",
            "university", "institute", "department", "foundation", "center", "centre",
            "technology", "corporation", "company", "organization"
        ]
        let words = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
        if words.contains(where: { institutionWords.contains($0) }) {
            return false
        }
        // Require at least one standard name-format word (initial cap, rest lowercase)
        let hasStandardNameWord = parts.contains { part in
            let cleaned = part.trimmingCharacters(in: .punctuationCharacters)
            guard cleaned.count >= 2 else { return false }
            guard let first = cleaned.first else { return false }
            return first.isUppercase && cleaned.dropFirst().allSatisfy({ $0.isLowercase })
        }
        // All-caps names with initials (e.g. "LUDMILA I. KUNCHEVA") should also pass
        let hasInitial = parts.contains { $0.range(of: #"^[A-Z]\.$"#, options: .regularExpression) != nil }
        guard hasStandardNameWord || hasInitial else {
            return false
        }
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
        let cleaned2 = stripAuthorMarkers(from: cleaned, replacement: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned2.isEmpty else { return [] }

        // Note: no trailing \b because names may be glued to digits (e.g. "Wang1")
        guard let regex = try? NSRegularExpression(pattern: #"\b([A-Z][a-zA-Z'\-]+\s+[A-Z][a-zA-Z'\-]+)"#) else {
            return []
        }
        let range = NSRange(cleaned2.startIndex..<cleaned2.endIndex, in: cleaned2)
        let matches = regex.matches(in: cleaned2, range: range)

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
        let hasMarkerSymbols = line.range(
            of: #"\d|[\u{00A7}\u{00B6}\u{2020}-\u{2023}\u{25A0}-\u{25FF}\u{2600}-\u{26FF}]"#,
            options: .regularExpression
        ) != nil
        guard hasMarkerSymbols else { return [] }
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
        // Only merge dense names when we already have at least one marker match.
        // Without this guard, lines that happen to contain digits (e.g. copyright
        // headers) but no actual author markers can false-positive via dense names.
        if markerNames.count >= 1 && denseNames.count > markerNames.count {
            return MetadataNormalization.normalizedAuthors(markerNames + denseNames)
        }
        // Fallback: line carries marker symbols but no explicit marker-digit matches.
        if markerNames.isEmpty && denseNames.count >= 2 && hasMarkerSymbols {
            return MetadataNormalization.normalizedAuthors(denseNames)
        }
        return markerNames
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
        guard let digitRange = line.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        let beforeDigit = String(line[..<digitRange.lowerBound])
        guard let nameRegex = try? NSRegularExpression(
            pattern: #"\b([A-Z][a-zA-Z']+\s+[A-Z][a-zA-Z']+)\s*$"#
        ) else { return nil }
        let range = NSRange(beforeDigit.startIndex..<beforeDigit.endIndex, in: beforeDigit)
        guard let match = nameRegex.firstMatch(in: beforeDigit, options: [], range: range),
              let swiftRange = Range(match.range(at: 1), in: beforeDigit) else { return nil }
        let prefix = String(beforeDigit[..<swiftRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? nil : prefix
    }

    // Note: no trailing \b because names may be glued to digits (e.g. "Wang1")
    // and \b does not match between a letter and a digit in ICU.
    private static let markerBoundAuthorPattern =
        "\\b([A-Z][a-zA-Z']+(?:\\s+(?:[A-Z]\\.|[A-Z][a-z]{1,3}))?\\s+[A-Z][a-zA-Z']+)\\s*[\u{002A}\u{2217}\u{2020}\u{2021}\u{00A7}\u{00B6}\u{2200}-\u{22FF}\u{25A0}-\u{25FF}\u{2600}-\u{26FF}]?\\s*\\d+"

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
        // Titles often contain colons (e.g. "R2-ROUTER: A New Paradigm...");
        // author lines with superscripts almost never do.
        if line.contains(":") {
            return false
        }
        // Exclude publisher/copyright boilerplate (e.g. "©2003 Kluwer Academic Publishers")
        if lowered.contains("publishers")
            || lowered.contains("manufactured")
            || lowered.contains("copyright")
            || lowered.contains("all rights reserved") {
            return false
        }
        // Stylized author lines usually carry affiliation markers such as superscript digits/symbols.
        let hasMarkers = line.range(
            of: #"\d|[\u{00A7}\u{00B6}\u{2020}-\u{2023}\u{25A0}-\u{25FF}\u{2600}-\u{26FF}]"#,
            options: .regularExpression
        ) != nil
        guard hasMarkers else { return false }

        // Note: no trailing \b because names may be glued to digits (e.g. "Wang1")
        // and \b does not match between a letter and a digit in ICU.
        guard let regex = try? NSRegularExpression(pattern: #"\b[A-Z][a-zA-Z'\-]+(?:\s+[A-Z][a-zA-Z'\-]+){1,2}"#) else {
            return false
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let count = regex.numberOfMatches(in: line, range: range)
        return count >= 2
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
