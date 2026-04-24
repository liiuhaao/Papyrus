import Foundation
import CoreData

struct PaperFilterState {
    let searchText: String
    let sortField: PaperSortField
    let sortAscending: Bool
    let filterRankKeywords: Set<String>
    let filterReadingStatus: Set<String>
    let filterMinRating: Int
    let filterVenueAbbr: Set<String>
    let filterYear: Set<Int>
    let filterPublicationType: Set<String>
    let filterTags: Set<String>
    let filterFlaggedOnly: Bool
}

enum PaperQueryService {
    static func buildFilteredFetchRequest(
        state: PaperFilterState,
        includeSearch: Bool = true
    ) -> NSFetchRequest<Paper> {
        let request: NSFetchRequest<Paper> = Paper.fetchRequest()
        request.fetchBatchSize = 50
        request.returnsObjectsAsFaults = true
        var predicates: [NSPredicate] = []

        if includeSearch && !state.searchText.isEmpty {
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "title CONTAINS[cd] %@", state.searchText),
                NSPredicate(format: "authors CONTAINS[cd] %@", state.searchText),
                NSPredicate(format: "venue CONTAINS[cd] %@", state.searchText),
                NSPredicate(format: "abstract CONTAINS[cd] %@", state.searchText),
                NSPredicate(format: "notes CONTAINS[cd] %@", state.searchText),
                NSPredicate(format: "tags CONTAINS[cd] %@", state.searchText),
            ]))
        }

        if !state.filterReadingStatus.isEmpty {
            predicates.append(NSPredicate(format: "readingStatus IN %@", state.filterReadingStatus))
        }
        if state.filterMinRating > 0 {
            predicates.append(NSPredicate(format: "rating >= %d", state.filterMinRating))
        }
        if !state.filterYear.isEmpty {
            predicates.append(NSPredicate(format: "year IN %@", state.filterYear.map { NSNumber(value: $0) }))
        }
        if !state.filterPublicationType.isEmpty {
            predicates.append(NSPredicate(format: "publicationType IN %@", state.filterPublicationType))
        }
        if !state.filterTags.isEmpty {
            let tagPredicates = state.filterTags.map { NSPredicate(format: "tags CONTAINS[cd] %@", $0) }
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: tagPredicates))
        }
        if state.filterFlaggedOnly {
            predicates.append(NSPredicate(format: "isFlagged == YES"))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        let sortKey: String
        switch state.sortField {
        case .dateAdded: sortKey = "dateAdded"
        case .year: sortKey = "year"
        case .title: sortKey = "title"
        case .citations: sortKey = "citationCount"
        }
        request.sortDescriptors = [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "pinOrder", ascending: true),
            NSSortDescriptor(key: sortKey, ascending: state.sortAscending),
        ]
        return request
    }

    static func applyStructuredFilters(
        papers: [Paper],
        state: PaperFilterState
    ) -> [Paper] {
        let selectedVenues = Set(state.filterVenueAbbr.map(normalizeVenueFilterValue))
        return papers.filter { paper in
            if !state.filterReadingStatus.isEmpty,
               !state.filterReadingStatus.contains(paper.readingStatus ?? "") {
                return false
            }
            if state.filterMinRating > 0, paper.rating < state.filterMinRating {
                return false
            }
            if !state.filterYear.isEmpty, !state.filterYear.contains(Int(paper.year)) {
                return false
            }
            if !state.filterPublicationType.isEmpty,
               !state.filterPublicationType.contains(paper.publicationType ?? "") {
                return false
            }
            if !state.filterTags.isEmpty {
                let rawTags = paper.tags ?? ""
                let matchesTag = state.filterTags.contains { tag in
                    rawTags.localizedCaseInsensitiveContains(tag)
                }
                if !matchesTag {
                    return false
                }
            }
            if state.filterFlaggedOnly, !paper.isFlagged {
                return false
            }
            if !selectedVenues.isEmpty,
               selectedVenues.isDisjoint(with: venueFilterKeys(for: paper)) {
                return false
            }
            return true
        }
    }

    static func sortPapers(
        _ papers: [Paper],
        sortField: PaperSortField,
        sortAscending: Bool
    ) -> [Paper] {
        papers.sorted { lhs, rhs in
            compare(lhs, rhs, sortField: sortField, ascending: sortAscending)
        }
    }

    struct SearchQuery {
        enum Field: String {
            case title
            case authors
            case venue
            case abstract
            case notes
            case tags
            case year
            case status
            case type
            case doi
            case arxiv
        }

        var terms: [String] = []

        var isEmpty: Bool {
            terms.isEmpty
        }
    }

    static func highlightTerms(for field: SearchQuery.Field, query: SearchQuery) -> [String] {
        let normalized = query.terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        var output: [String] = []
        for term in normalized {
            let key = term.lowercased()
            if seen.insert(key).inserted {
                output.append(term)
            }
        }
        return output
    }

    static func parseSearch(_ raw: String) -> SearchQuery {
        var query = SearchQuery()
        let tokens = tokenizeSearch(raw)
        query.terms = tokens
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return query
    }

    private static func tokenizeSearch(_ raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        for ch in raw {
            if let q = quote {
                if ch == q {
                    quote = nil
                } else {
                    current.append(ch)
                }
                continue
            }
            if ch == "\"" || ch == "'" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                quote = ch
                continue
            }
            if ch.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    static func applySearch(
        papers: [Paper],
        query: SearchQuery,
        sortField: PaperSortField,
        sortAscending: Bool
    ) -> [Paper] {
        guard !query.isEmpty else { return papers }
        var scored: [(paper: Paper, score: Int)] = []
        scored.reserveCapacity(papers.count)
        for paper in papers {
            let result = matchAndScore(paper, query: query)
            if result.match {
                scored.append((paper, result.score))
            }
        }
        return scored.sorted { left, right in
            if left.paper.isPinned != right.paper.isPinned {
                return left.paper.isPinned && !right.paper.isPinned
            }
            if left.paper.isPinned && right.paper.isPinned, left.paper.pinOrder != right.paper.pinOrder {
                return left.paper.pinOrder < right.paper.pinOrder
            }
            if left.score != right.score { return left.score > right.score }
            return compareBySortField(left.paper, right.paper, sortField: sortField, ascending: sortAscending)
        }.map(\.paper)
    }

    private static func compareBySortField(
        _ lhs: Paper,
        _ rhs: Paper,
        sortField: PaperSortField,
        ascending: Bool
    ) -> Bool {
        let comparison: ComparisonResult
        switch sortField {
        case .dateAdded:
            comparison = lhs.dateAdded.compare(rhs.dateAdded)
        case .year:
            comparison = lhs.year == rhs.year ? .orderedSame : (lhs.year < rhs.year ? .orderedAscending : .orderedDescending)
        case .title:
            comparison = (lhs.title ?? "").localizedCaseInsensitiveCompare(rhs.title ?? "")
        case .citations:
            comparison = lhs.citationCount == rhs.citationCount ? .orderedSame : (lhs.citationCount < rhs.citationCount ? .orderedAscending : .orderedDescending)
        }
        switch comparison {
        case .orderedAscending:
            return ascending
        case .orderedDescending:
            return !ascending
        case .orderedSame:
            let leftTitle = lhs.displayTitle
            let rightTitle = rhs.displayTitle
            let titleComparison = leftTitle.localizedCaseInsensitiveCompare(rightTitle)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
            return lhs.objectID.uriRepresentation().absoluteString < rhs.objectID.uriRepresentation().absoluteString
        }
    }

    private static func compare(
        _ lhs: Paper,
        _ rhs: Paper,
        sortField: PaperSortField,
        ascending: Bool
    ) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }
        if lhs.isPinned && rhs.isPinned && lhs.pinOrder != rhs.pinOrder {
            return lhs.pinOrder < rhs.pinOrder
        }
        return compareBySortField(lhs, rhs, sortField: sortField, ascending: ascending)
    }

    private static func matchAndScore(_ paper: Paper, query: SearchQuery) -> (match: Bool, score: Int) {
        func fieldText(_ field: SearchQuery.Field) -> String {
            switch field {
            case .title: return paper.title ?? ""
            case .authors: return paper.authors ?? ""
            case .venue: return paper.venue ?? ""
            case .abstract: return paper.abstract ?? ""
            case .notes: return paper.notes ?? ""
            case .tags: return (paper.tags ?? "")
            case .doi: return paper.doi ?? ""
            case .arxiv: return paper.arxivId ?? ""
            case .status: return paper.readingStatus ?? ""
            case .type: return paper.publicationType ?? ""
            case .year: return paper.year > 0 ? "\(paper.year)" : ""
            }
        }

        func contains(_ field: SearchQuery.Field, _ term: String) -> Bool {
            if field == .tags {
                return paper.tagsList.contains { $0.localizedCaseInsensitiveContains(term) }
            }
            if field == .venue {
                let rawVenue = fieldText(.venue)
                if rawVenue.localizedCaseInsensitiveContains(term) { return true }
                let unified = VenueFormatter.unifiedDisplayName(rawVenue)
                if unified.localizedCaseInsensitiveContains(term) { return true }
                let abbr = VenueFormatter.abbreviate(rawVenue)
                if abbr.localizedCaseInsensitiveContains(term) { return true }
                if let venueAbbr = paper.venueObject?.abbreviation,
                   venueAbbr.localizedCaseInsensitiveContains(term) {
                    return true
                }
                if let venueName = paper.venueObject?.name,
                   venueName.localizedCaseInsensitiveContains(term) {
                    return true
                }
                return false
            }
            return fieldText(field).localizedCaseInsensitiveContains(term)
        }

        // General terms (AND across terms, OR across fields)
        for term in query.terms {
            let yearMatch = matchYear(term, year: Int(paper.year))
            let anyMatch = contains(.title, term)
                || contains(.authors, term)
                || contains(.venue, term)
                || contains(.abstract, term)
                || contains(.notes, term)
                || contains(.tags, term)
                || contains(.doi, term)
                || contains(.arxiv, term)
                || yearMatch
            if !anyMatch {
                return (false, 0)
            }
        }

        // Scoring
        var score = 0
        let weights: [SearchQuery.Field: Int] = [
            .title: 5,
            .authors: 4,
            .venue: 3,
            .tags: 3,
            .doi: 2,
            .arxiv: 2,
            .year: 2,
            .abstract: 1,
            .notes: 1,
            .status: 1,
            .type: 1,
        ]

        for term in query.terms {
            var matchedFields: [SearchQuery.Field] = [
                .title, .authors, .venue, .tags, .doi, .arxiv, .abstract, .notes
            ].filter { contains($0, term) }
            if matchYear(term, year: Int(paper.year)) {
                matchedFields.append(.year)
            }
            if let best = matchedFields.compactMap({ weights[$0] }).max() {
                score += best
            }
        }

        return (true, score)
    }

    private static func matchYear(_ term: String, year: Int) -> Bool {
        guard term.count == 4, let value = Int(term), year > 0 else { return false }
        return value == year
    }

    static func venueCounts(in papers: [Paper]) -> [(venue: String, count: Int)] {
        var counts: [String: (count: Int, rankSource: String?, rankValue: String?)] = [:]

        for paper in papers {
            let label = displayVenueLabel(for: paper)
            guard !label.isEmpty else { continue }
            let existing = counts[label]
            var rankSource = existing?.rankSource
            var rankValue = existing?.rankValue
            if let venue = paper.venueObject {
                if let top = RankProfiles.sortEntries(Array(venue.rankSources)).first {
                    rankSource = rankSource ?? top.0
                    rankValue = rankValue ?? top.1
                }
            }
            counts[label] = ((existing?.count ?? 0) + 1, rankSource, rankValue)
        }

        return counts.sorted {
            let leftRank = RankProfiles.rankSortKey(source: $0.value.rankSource ?? "", raw: $0.value.rankValue ?? "")
            let rightRank = RankProfiles.rankSortKey(source: $1.value.rankSource ?? "", raw: $1.value.rankValue ?? "")
            if leftRank != rightRank { return leftRank < rightRank }
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            return $0.key < $1.key
        }
        .map { (venue: $0.key, count: $0.value.count) }
    }

    private static func displayVenueLabel(for paper: Paper) -> String {
        let rawVenue = (paper.venueObject?.name ?? paper.venue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawVenue.isEmpty else { return "" }
        let parts = VenueFormatter.resolvedVenueParts(rawVenue, abbreviation: paper.venueObject?.abbreviation)
        let label = parts.abbr.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? parts.full.trimmingCharacters(in: .whitespacesAndNewlines) : label
    }

    package static func venueFilterKeys(for paper: Paper) -> Set<String> {
        let rawVenue = (paper.venueObject?.name ?? paper.venue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawVenue.isEmpty else { return [] }
        let parts = VenueFormatter.resolvedVenueParts(rawVenue, abbreviation: paper.venueObject?.abbreviation)
        let values = [
            rawVenue,
            parts.full,
            parts.abbr,
            paper.venueObject?.abbreviation,
            paper.venueObject?.name,
            VenueFormatter.unifiedDisplayName(rawVenue),
            VenueFormatter.unifiedFullName(rawVenue),
            VenueFormatter.abbreviate(rawVenue),
        ]
        return Set(values.compactMap { value in
            let normalized = normalizeVenueFilterValue(value)
            return normalized.isEmpty ? nil : normalized
        })
    }

    package static func normalizeVenueFilterValue(_ raw: String?) -> String {
        raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    static func yearCounts(in papers: [Paper]) -> [(year: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for paper in papers {
            let year = Int(paper.year)
            if year > 0 { counts[year, default: 0] += 1 }
        }
        return counts.sorted { $0.key > $1.key }.map { (year: $0.key, count: $0.value) }
    }

    static func publicationTypeCounts(in papers: [Paper]) -> [(type: String, count: Int)] {
        let order = ["conference", "journal", "workshop", "preprint", "book", "other"]
        var counts: [String: Int] = [:]
        for paper in papers {
            guard let type = paper.publicationType, !type.isEmpty else { continue }
            counts[type, default: 0] += 1
        }
        return counts.sorted {
            let leftIndex = order.firstIndex(of: $0.key) ?? order.count
            let rightIndex = order.firstIndex(of: $1.key) ?? order.count
            return leftIndex < rightIndex
        }
        .map { (type: $0.key, count: $0.value) }
    }

    static func tagCounts(in papers: [Paper]) -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for paper in papers {
            for tag in paper.tagsList {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }
        .map { (tag: $0.key, count: $0.value) }
    }

    static func rankKeywordCounts(in papers: [Paper], visibleSourceKeys: [String]) -> [(keyword: String, count: Int)] {
        var counts: [String: Int] = [:]
        var keywordMeta: [String: (source: String, value: String)] = [:]
        for paper in papers {
            guard let venue = paper.venueObject else { continue }
            for (key, value) in venue.orderedRankEntries(visibleSourceKeys: visibleSourceKeys) {
                let label = RankSourceConfig.displayLabel(for: key, value: value)
                counts[label, default: 0] += 1
                keywordMeta[label] = (key, value)
            }
        }
        return counts.sorted {
            let leftMeta = keywordMeta[$0.key] ?? ("", "")
            let rightMeta = keywordMeta[$1.key] ?? ("", "")
            let leftSourceOrder = RankProfiles.sourceSortKey(leftMeta.source)
            let rightSourceOrder = RankProfiles.sourceSortKey(rightMeta.source)
            if leftSourceOrder != rightSourceOrder { return leftSourceOrder < rightSourceOrder }

            let leftRankOrder = RankProfiles.rankSortKey(source: leftMeta.source, raw: leftMeta.value)
            let rightRankOrder = RankProfiles.rankSortKey(source: rightMeta.source, raw: rightMeta.value)
            if leftRankOrder != rightRankOrder { return leftRankOrder < rightRankOrder }

            return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }
        .map { (keyword: $0.key, count: $0.value) }
    }

    // MARK: - Database-aggregated counts (avoid iterating full Paper array)

    static func fetchYearCounts(context: NSManagedObjectContext) -> [(year: Int, count: Int)] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Paper")
        let countExpr = NSExpressionDescription()
        countExpr.name = "count"
        countExpr.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "year")])
        countExpr.expressionResultType = .integer32AttributeType
        request.propertiesToFetch = ["year", countExpr]
        request.propertiesToGroupBy = ["year"]
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "year > 0")
        guard let results = try? context.fetch(request) else { return [] }
        return results.compactMap { dict in
            guard let year = (dict["year"] as? NSNumber)?.intValue,
                  let count = (dict["count"] as? NSNumber)?.intValue else { return nil }
            return (year, count)
        }.sorted { $0.year > $1.year }
    }

    static func fetchPublicationTypeCounts(context: NSManagedObjectContext) -> [(type: String, count: Int)] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Paper")
        let countExpr = NSExpressionDescription()
        countExpr.name = "count"
        countExpr.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "publicationType")])
        countExpr.expressionResultType = .integer32AttributeType
        request.propertiesToFetch = ["publicationType", countExpr]
        request.propertiesToGroupBy = ["publicationType"]
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "publicationType != nil AND publicationType != ''")
        guard let results = try? context.fetch(request) else { return [] }
        let order = ["conference", "journal", "workshop", "preprint", "book", "other"]
        return results.compactMap { dict in
            guard let type = dict["publicationType"] as? String,
                  let count = (dict["count"] as? NSNumber)?.intValue else { return nil }
            return (type, count)
        }.sorted {
            let leftIndex = order.firstIndex(of: $0.type) ?? order.count
            let rightIndex = order.firstIndex(of: $1.type) ?? order.count
            return leftIndex < rightIndex
        }
    }

    static func fetchFlaggedCount(context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<NSNumber>(entityName: "Paper")
        request.resultType = .countResultType
        request.predicate = NSPredicate(format: "isFlagged == YES")
        return (try? context.fetch(request).first?.intValue) ?? 0
    }

    static func fetchTagCounts(context: NSManagedObjectContext) -> [(tag: String, count: Int)] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Paper")
        request.propertiesToFetch = ["tags"]
        request.resultType = .dictionaryResultType
        guard let results = try? context.fetch(request) else { return [] }
        var counts: [String: Int] = [:]
        for dict in results {
            guard let tagsStr = dict["tags"] as? String else { continue }
            for tag in tagsStr.components(separatedBy: ",") {
                let trimmed = tag.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    counts[trimmed, default: 0] += 1
                }
            }
        }
        return counts.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }.map { (tag: $0.key, count: $0.value) }
    }

    static func fetchVenueCounts(context: NSManagedObjectContext) -> [(venue: String, count: Int)] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Paper")
        request.propertiesToFetch = ["venue", "venueObject"]
        request.resultType = .dictionaryResultType
        guard let results = try? context.fetch(request) else { return [] }

        var counts: [String: (count: Int, rankSource: String?, rankValue: String?)] = [:]

        for dict in results {
            guard let paperDict = dict as? [String: Any] else { continue }
            let venueStr = paperDict["venue"] as? String
            let venueObj = paperDict["venueObject"] as? Venue

            let rawVenue = (venueObj?.name ?? venueStr ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawVenue.isEmpty else { continue }
            let parts = VenueFormatter.resolvedVenueParts(rawVenue, abbreviation: venueObj?.abbreviation)
            let label = parts.abbr.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayLabel = label.isEmpty ? parts.full.trimmingCharacters(in: .whitespacesAndNewlines) : label

            var rankSource: String?
            var rankValue: String?
            if let vo = venueObj, let top = RankProfiles.sortEntries(Array(vo.rankSources)).first {
                rankSource = top.0
                rankValue = top.1
            }

            let existing = counts[displayLabel]
            counts[displayLabel] = (
                (existing?.count ?? 0) + 1,
                existing?.rankSource ?? rankSource,
                existing?.rankValue ?? rankValue
            )
        }

        return counts.sorted {
            let leftRank = RankProfiles.rankSortKey(source: $0.value.rankSource ?? "", raw: $0.value.rankValue ?? "")
            let rightRank = RankProfiles.rankSortKey(source: $1.value.rankSource ?? "", raw: $1.value.rankValue ?? "")
            if leftRank != rightRank { return leftRank < rightRank }
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            return $0.key < $1.key
        }.map { (venue: $0.key, count: $0.value.count) }
    }

    static func fetchRankKeywordCounts(context: NSManagedObjectContext, visibleSourceKeys: [String]) -> [(keyword: String, count: Int)] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Paper")
        request.propertiesToFetch = ["venueObject"]
        request.resultType = .dictionaryResultType
        guard let results = try? context.fetch(request) else { return [] }

        var counts: [String: Int] = [:]
        var keywordMeta: [String: (source: String, value: String)] = [:]

        for dict in results {
            guard let venueObj = (dict as? [String: Any])?["venueObject"] as? Venue else { continue }
            for (key, value) in venueObj.orderedRankEntries(visibleSourceKeys: visibleSourceKeys) {
                let label = RankSourceConfig.displayLabel(for: key, value: value)
                counts[label, default: 0] += 1
                keywordMeta[label] = (key, value)
            }
        }

        return counts.sorted {
            let leftMeta = keywordMeta[$0.key] ?? ("", "")
            let rightMeta = keywordMeta[$1.key] ?? ("", "")
            let leftSourceOrder = RankProfiles.sourceSortKey(leftMeta.source)
            let rightSourceOrder = RankProfiles.sourceSortKey(rightMeta.source)
            if leftSourceOrder != rightSourceOrder { return leftSourceOrder < rightSourceOrder }

            let leftRankOrder = RankProfiles.rankSortKey(source: leftMeta.source, raw: leftMeta.value)
            let rightRankOrder = RankProfiles.rankSortKey(source: rightMeta.source, raw: rightMeta.value)
            if leftRankOrder != rightRankOrder { return leftRankOrder < rightRankOrder }

            return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }.map { (keyword: $0.key, count: $0.value) }
    }
}
