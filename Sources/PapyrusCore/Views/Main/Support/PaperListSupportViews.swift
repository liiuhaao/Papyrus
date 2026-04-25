import CoreData
import SwiftUI

struct PaperRowView: View {
    let paper: Paper
    let searchText: String
    @ObservedObject private var appConfig = AppConfig.shared
    @ObservedObject private var stateStore = PaperTransientStateStore.shared

    private var rowSpacing: CGFloat { ListRowLayoutMetrics.stackSpacing }
    private var metaSpacing: CGFloat { ListRowLayoutMetrics.metaSpacing }
    private var flagSize: CGFloat { 11 * AppStyleConfig.fontScale }
    private var pinSize: CGFloat { 11 * AppStyleConfig.fontScale }
    private var ratingSize: CGFloat { 12 * AppStyleConfig.fontScale }

    private var rankPills: [(String, Color)] {
        guard appConfig.showRankInList else { return [] }
        let rankSources = paper.venueObject?.rankSources ?? [:]
        let orderedEntries: [(String, String)]
        let visibleKeys = RankSourceConfig.normalizedKeys(appConfig.rankBadgeSources)
        if visibleKeys.isEmpty {
            orderedEntries = RankProfiles.sortEntries(rankSources.map { ($0.key, $0.value) })
        } else {
            orderedEntries = visibleKeys.compactMap { key in
                guard let value = rankSources[key] else { return nil }
                return (key, value)
            }
        }
        return Array(orderedEntries.prefix(3)).map { key, value in
            (
                RankSourceConfig.displayLabel(for: key, value: value),
                rankColor(for: key, value: value)
            )
        }
    }

    private func rankColor(for key: String, value: String) -> Color {
        AppColors.rankColor(source: key, value: value)
    }

    private var listTags: [String] {
        guard appConfig.showTagsInList, appConfig.listTagCount > 0 else { return [] }

        let tags = paper.tagsList.filter { !$0.isEmpty }
        guard !tags.isEmpty else { return [] }

        let preferred = appConfig.listTagPreferredNamespaces
        var selected: [String] = []
        var seen = Set<String>()

        for namespace in preferred {
            let matches = tags.filter {
                TagNamespaceSupport.namespace(for: $0) == namespace
            }
            for tag in TagNamespaceSupport.sortTags(matches) where selected.count < appConfig.listTagCount {
                if seen.insert(tag.lowercased()).inserted {
                    selected.append(tag)
                }
            }
            if selected.count >= appConfig.listTagCount { return selected }
        }

        if appConfig.listTagFallbackToOther {
            let fallback = tags.filter { TagNamespaceSupport.namespace(for: $0) == nil }
            for tag in TagNamespaceSupport.sortTags(fallback) where selected.count < appConfig.listTagCount {
                if seen.insert(tag.lowercased()).inserted {
                    selected.append(tag)
                }
            }
        }

        if selected.count < appConfig.listTagCount {
            for tag in TagNamespaceSupport.sortTags(tags) where selected.count < appConfig.listTagCount {
                if seen.insert(tag.lowercased()).inserted {
                    selected.append(tag)
                }
            }
        }

        return selected
    }

    private var venueLine: String? {
        guard appConfig.showVenueInList else { return nil }
        let parts = VenueFormatter.resolvedVenueParts(
            (paper.venueObject?.name ?? paper.venue ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            abbreviation: (paper.venueObject?.abbreviation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let venueText: String = {
            let full = parts.full.trimmingCharacters(in: .whitespacesAndNewlines)
            let abbr = parts.abbr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !abbr.isEmpty && !full.isEmpty {
                return "\(abbr) · \(full)"
            }
            return full.isEmpty ? abbr : full
        }()

        guard !venueText.isEmpty else {
            return paper.year > 0 ? "\(paper.year)" : nil
        }
        if paper.year > 0 {
            return "\(paper.year)  ·  \(venueText)"
        }
        return venueText
    }

    private var searchQuery: PaperQueryService.SearchQuery {
        PaperQueryService.parseSearch(searchText)
    }

    private var titleText: AttributedString {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AttributedString(paper.displayTitle)
        }
        let terms = PaperQueryService.highlightTerms(for: .title, query: searchQuery)
        return highlightedText(paper.displayTitle, terms: terms)
    }

    private var authorsText: AttributedString {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AttributedString(paper.formattedAuthors)
        }
        let terms = PaperQueryService.highlightTerms(for: .authors, query: searchQuery)
        return highlightedText(paper.formattedAuthors, terms: terms)
    }

    private var hasNotesSearchMatch: Bool {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let notes = paper.notes ?? ""
        guard !notes.isEmpty else { return false }
        let terms = PaperQueryService.highlightTerms(for: .notes, query: searchQuery)
        return terms.contains { term in
            notes.localizedCaseInsensitiveContains(term)
        }
    }

    private var metaText: AttributedString? {
        let venueValue: AttributedString? = {
            guard let venueLine else { return nil }
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return AttributedString(venueLine)
            }
            let terms = PaperQueryService.highlightTerms(for: .venue, query: searchQuery)
                + PaperQueryService.highlightTerms(for: .year, query: searchQuery)
            return highlightedText(venueLine, terms: terms)
        }()

        return venueValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            HStack(alignment: .top, spacing: metaSpacing) {
                Text(titleText)
                    .font(AppTypography.bodyStrong)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    if appConfig.showFlagInList && paper.isFlagged {
                        Image(systemName: "flag.fill")
                            .font(.system(size: flagSize, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    if paper.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: pinSize, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.top, 2)
            }

            HStack(alignment: .firstTextBaseline, spacing: metaSpacing) {
                Text(authorsText)
                    .font(AppTypography.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !listTags.isEmpty {
                    HStack(spacing: max(4, AppMetrics.badgeVertical + 3)) {
                        ForEach(listTags, id: \.self) { tag in
                            Text(tag)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .appBadgePill(
                                    AppColors.tagColor(tag),
                                    horizontal: AppMetrics.badgeHorizontal - 1,
                                    vertical: AppMetrics.badgeVertical
                                )
                        }
                    }
                }
            }

            HStack(alignment: .center, spacing: metaSpacing) {
                if let metaText {
                    Text(metaText)
                        .font(AppTypography.label)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if !rankPills.isEmpty {
                    HStack(spacing: max(4, AppMetrics.badgeVertical + 3)) {
                        ForEach(Array(rankPills.enumerated()), id: \.offset) { _, pill in
                            Text(pill.0)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .appBadgePill(pill.1, horizontal: AppMetrics.badgeHorizontal - 1, vertical: AppMetrics.badgeVertical)
                        }
                    }
                }

                Spacer(minLength: 0)

                if hasNotesSearchMatch {
                    Label("Notes Hit", systemImage: "doc.text.magnifyingglass")
                        .font(AppTypography.labelStrong)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .help("Matched in notes")
                }

                if appConfig.showRatingInList && paper.rating > 0 {
                    Text("★ \(paper.rating)")
                        .font(.system(size: ratingSize, weight: .semibold))
                        .foregroundStyle(AppColors.star)
                        .frame(height: ListRowLayoutMetrics.statusSlotHeight, alignment: .center)
                }

                let workflowStatus = stateStore.workflowStatus(for: paper.objectID)
                if let workflowStatus, workflowStatus.hasVisiblePhases {
                    WorkflowStatusStrip(status: workflowStatus)
                        .frame(height: ListRowLayoutMetrics.statusSlotHeight, alignment: .center)
                } else if appConfig.showStatusInList {
                    Image(systemName: AppStatusStyle.icon(for: paper.currentReadingStatus))
                        .font(AppTypography.labelStrong)
                        .foregroundStyle(AppStatusStyle.tint(for: paper.currentReadingStatus))
                        .frame(height: ListRowLayoutMetrics.statusSlotHeight, alignment: .center)
                }
            }
        }
    }
}

struct WorkflowStatusStrip: View {
    let status: PaperWorkflowStatus

    var body: some View {
        HStack(spacing: 6) {
            if status.fetch.isVisible {
                WorkflowPhaseBadge(title: "Fetch", phase: status.fetch)
            }
        }
    }
}

private struct WorkflowPhaseBadge: View {
    let title: String
    let phase: PaperWorkflowPhase

    private var tint: Color {
        switch phase {
        case .idle:
            return .secondary
        case .queued:
            return .secondary
        case .running:
            return .accentColor
        case .done:
            return .green
        case .failed:
            return .orange
        case .skipped:
            return .secondary
        }
    }

    private var icon: String {
        switch phase {
        case .idle:
            return "circle"
        case .queued:
            return "clock"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .done:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .skipped:
            return "minus.circle"
        }
    }

    private var label: String {
        switch phase {
        case .idle:
            return "Idle"
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .done:
            return "Done"
        case .failed:
            return "Failed"
        case .skipped:
            return "Skipped"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if phase == .running {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.65)
                    .frame(width: 10, height: 10)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 10 * AppStyleConfig.fontScale, weight: .semibold))
                    .frame(width: 10, height: 10)
            }
            Text("\(title) \(label)")
                .lineLimit(1)
        }
        .font(AppTypography.label)
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct PaperListSummaryBar: View {
    @ObservedObject private var appConfig = AppConfig.shared
    let resultCount: Int
    let totalCount: Int
    let searchText: String
    let activeFilters: [String]
    let onClearSearch: () -> Void
    let onClearFilters: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(summaryText)
                .font(AppTypography.bodySmall)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if !searchText.isEmpty {
                summaryPill("Search: \(searchText)", action: onClearSearch)
            }

            if !activeFilters.isEmpty {
                summaryPill(activeFilters.joined(separator: ", "), action: onClearFilters)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, max(8, AppMetrics.inlineRowVertical * 2.5))
        .appCardSurface(
            fill: Color.primary.opacity(0.028),
            stroke: Color.clear,
            cornerRadius: 0
        )
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var summaryText: String {
        if resultCount == totalCount {
            return "\(totalCount) papers"
        }
        return "\(resultCount) of \(totalCount) papers"
    }

    private func summaryPill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 8 * AppStyleConfig.fontScale, weight: .semibold))
            }
            .appPill(
                background: Color.primary.opacity(0.06),
                foreground: .secondary,
                horizontal: 8,
                vertical: 4
            )
        }
        .buttonStyle(.plain)
        .help("Clear")
    }
}

struct EmptyStateView: View {
    @ObservedObject private var appConfig = AppConfig.shared
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 64 * AppStyleConfig.fontScale))
                .foregroundStyle(.tertiary)
            Text("No Paper Selected")
                .font(AppTypography.titleMedium)
                .foregroundStyle(.secondary)
            Text("Select a paper from the list, or import a PDF")
                .font(AppTypography.label)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MultiSelectionDetailView: View {
    @ObservedObject private var appConfig = AppConfig.shared
    let papers: [Paper]
    let onBatchEdit: () -> Void
    let onRefreshSelection: () -> Void
    let onDeleteSelection: () -> Void

    private var sortedPapers: [Paper] {
        papers.sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }

    private var statusSummary: [(String, Int)] {
        Paper.ReadingStatus.allCases.map { status in
            (status.label, papers.filter { $0.currentReadingStatus == status }.count)
        }
        .filter { $0.1 > 0 }
    }

    private var yearSummary: [(String, Int)] {
        Dictionary(grouping: papers.filter { $0.year > 0 }, by: { Int($0.year) })
            .map { (String($0.key), $0.value.count) }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0 > $1.0
            }
            .prefix(4)
            .map { $0 }
    }

    private var venueSummary: [(String, Int)] {
        Dictionary(grouping: papers.compactMap { paper -> String? in
            let rawVenue = (paper.venue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let value = (paper.venueObject?.abbreviation ?? VenueFormatter.unifiedDisplayName(rawVenue))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }, by: { $0 })
        .map { ($0.key, $0.value.count) }
        .sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
        }
        .prefix(4)
        .map { $0 }
    }

    private var selectionCaption: String {
        let unread = papers.filter { $0.currentReadingStatus == .unread }.count
        let reading = papers.filter { $0.currentReadingStatus == .reading }.count
        let read = papers.filter { $0.currentReadingStatus == .read }.count
        return "\(unread) unread  ·  \(reading) reading  ·  \(read) read"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(papers.count) Papers Selected")
                        .font(AppTypography.titleMedium)
                        .foregroundStyle(.primary)
                    Text(selectionCaption)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Batch Edit", action: onBatchEdit)
                            .buttonStyle(.borderedProminent)
                        Button("Refresh", action: onRefreshSelection)
                            .buttonStyle(.bordered)
                        Button("Delete", role: .destructive, action: onDeleteSelection)
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 14)

                Divider()

                VStack(alignment: .leading, spacing: 18) {
                    if !statusSummary.isEmpty {
                        summarySection("Status") {
                            summaryRows(statusSummary) { label in
                                switch label {
                                case "Unread": return AppStatusStyle.tint(for: .unread)
                                case "Reading": return AppStatusStyle.tint(for: .reading)
                                default: return AppStatusStyle.tint(for: .read)
                                }
                            }
                        }
                    }

                    if !yearSummary.isEmpty {
                        summarySection("Years") {
                            summaryRows(yearSummary) { _ in .blue }
                        }
                    }

                    if !venueSummary.isEmpty {
                        summarySection("Top Venues") {
                            summaryRows(venueSummary) { _ in .secondary }
                        }
                    }

                    summarySection("Selected Papers") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(sortedPapers.prefix(8).enumerated()), id: \.offset) { _, paper in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(paper.displayTitle)
                                        .font(AppTypography.bodySmallMedium)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(paper.formattedAuthors)
                                        .font(AppTypography.label)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 2)
                            }
                            if papers.count > 8 {
                                Text("+\(papers.count - 8) more")
                                    .font(AppTypography.label)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .textSelection(.enabled)
    }

    private func summarySection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppTypography.labelStrong)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .kerning(0.5)
            content()
        }
    }

    private func summaryRows(_ items: [(String, Int)], tint: @escaping (String) -> Color) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(tint(item.0).opacity(0.85))
                        .frame(width: 6, height: 6)
                    Text(item.0)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(item.1)")
                        .font(AppTypography.monoLabel)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}
