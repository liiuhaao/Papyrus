// FilterPanelView.swift
// Left-panel faceted filter for paper browsing

import SwiftUI

struct FilterPanelView: View {
    @ObservedObject var viewModel: PaperListViewModel
    @ObservedObject var feedViewModel: FeedViewModel
    @ObservedObject private var appConfig = AppConfig.shared
    var onImport: () -> Void = {}
    var onDeleteAll: () -> Void = {}
    @Binding var showingFeed: Bool

    @State private var expandedSections: Set<String> = []
    @State private var collapsedSectionBlocks: Set<String> = []

    private let defaultVisibleCount = 3
    private var rowHeight: CGFloat { max(26, 26 * AppStyleConfig.spacingScale) }
    private var rowHorizontalInset: CGFloat { AppMetrics.tabBarHorizontal }
    private var rowTrailingInset: CGFloat { max(12, AppMetrics.tabBarHorizontal - 2) }
    private var groupedTagCounts: [TagNamespaceGroup] {
        TagNamespaceSupport.groupedTagCounts(viewModel.tagCounts)
    }
    private var orderedVisibleSections: [FilterPanelSection] {
        let visible = Set(appConfig.visibleFilterSections)
        return appConfig.filterPanelOrder.compactMap(FilterPanelSection.init(rawValue:)).filter {
            visible.contains($0.rawValue)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Horizontal tab bar — same style as inspector (Details | References)
            HStack(spacing: 0) {
                tabButton(title: "Library", selected: !showingFeed) {
                    showingFeed = false
                }
                tabButton(title: "Feed", selected: showingFeed) {
                    showingFeed = true
                    Task { await feedViewModel.selectFilter(UUID?.none) }
                }
            }
            .padding(.horizontal, 4)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    if showingFeed {
                        feedContent
                    } else {
                        libraryContent
                    }
                }
            }
        }
        .focusable(false)
        .toolbar {
            if !showingFeed && viewModel.filters.hasActiveFilters {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") { viewModel.filters.clearFilters() }
                        .foregroundStyle(.red)
                        .focusable(false)
                }
            }
        }
    }

    private func tabButton(title: String, selected: Bool, badge: Int? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Text(title)
                    .font(selected ? AppTypography.labelStrong : AppTypography.labelMedium)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        if selected {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                        }
                    }
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                        .offset(x: -4, y: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .focusable(false)
    }

    // MARK: - Library Entry

    // MARK: - Tab Contents

    @ViewBuilder
    private var libraryContent: some View {
        ForEach(Array(orderedVisibleSections.enumerated()), id: \.element.rawValue) { index, section in
            if index > 0 { Divider() }
            filterSectionContent(section)
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        VStack(spacing: 0) {
            // STATUS section
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 10 * AppStyleConfig.fontScale, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                Text("STATUS")
                    .font(AppTypography.overline)
                    .kerning(0.8)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, rowHorizontalInset)
            .padding(.top, AppMetrics.tabBarTop)
            .padding(.bottom, max(4, AppMetrics.inlineRowVertical + 2))

            ForEach([FeedItem.Status.unread, FeedItem.Status.read], id: \.self) { status in
                let count = feedViewModel.countByStatus[status] ?? 0
                let isSelected = feedViewModel.feedStatusFilter.contains(status)
                FilterRow(
                    label: status.label,
                    count: count,
                    isSelected: isSelected,
                    rowHeight: rowHeight,
                    leadingInset: rowHorizontalInset,
                    trailingInset: rowTrailingInset
                ) {
                    Task { await feedViewModel.toggleStatusFilter(status) }
                }
            }

            Divider()

            // SOURCE section
            HStack(spacing: 5) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 10 * AppStyleConfig.fontScale, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                Text("SUBSCRIPTION")
                    .font(AppTypography.overline)
                    .kerning(0.8)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, rowHorizontalInset)
            .padding(.top, AppMetrics.tabBarTop)
            .padding(.bottom, max(4, AppMetrics.inlineRowVertical + 2))

            ForEach(feedViewModel.subscriptions) { sub in
                let count = feedViewModel.itemCountBySubscription[sub.id] ?? 0
                FilterRow(
                    label: sub.displayLabel,
                    count: count,
                    isSelected: feedViewModel.selectedSubscriptionFilter == sub.id,
                    rowHeight: rowHeight,
                    leadingInset: rowHorizontalInset,
                    trailingInset: rowTrailingInset
                ) {
                    Task { await feedViewModel.selectFilter(
                        feedViewModel.selectedSubscriptionFilter == sub.id ? nil : sub.id
                    ) }
                }
            }
        }
        .padding(.bottom, max(4, AppMetrics.inlineRowVertical + 2))
    }

    // MARK: - Section Container

    @ViewBuilder
    private func filterSectionContent(_ section: FilterPanelSection) -> some View {
        switch section {
        case .flagged:
            sectionBlock(section.title) {
                flaggedRow()
            }
        case .status:
            sectionBlock(section.title, collapsible: true) {
                statusRows()
            }
        case .year:
            if !viewModel.yearCounts.isEmpty {
                sectionBlock(section.title, collapsible: true) {
                    expandableRows(
                        title: section.title,
                        items: viewModel.yearCounts.map { (String($0.year), $0.count) },
                        isSelected: { viewModel.filters.filterYear.contains(Int($0) ?? 0) },
                        label: { $0 },
                        toggle: { yr in
                            if let y = Int(yr) {
                                if viewModel.filters.filterYear.contains(y) { viewModel.filters.filterYear.remove(y) }
                                else { viewModel.filters.filterYear.insert(y) }
                            }
                        }
                    )
                }
            }
        case .tags:
            if !viewModel.tagCounts.isEmpty {
                sectionBlock(section.title, collapsible: true) {
                    VStack(spacing: 0) {
                        ForEach(groupedTagCounts) { group in
                            tagNamespaceBlock(group: group) {
                                expandableRows(
                                    title: "\(section.title).\(group.id)",
                                    items: group.items,
                                    isSelected: { viewModel.filters.filterTags.contains($0) },
                                    label: { $0 },
                                    toggle: { tag in
                                        if viewModel.filters.filterTags.contains(tag) { viewModel.filters.filterTags.remove(tag) }
                                        else { viewModel.filters.filterTags.insert(tag) }
                                    }
                                )
                            }
                        }
                    }
                }
            }
        case .ranks:
            if !viewModel.rankKeywordCounts.isEmpty {
                sectionBlock(section.title, collapsible: true) {
                    expandableRows(
                        title: section.title,
                        items: viewModel.rankKeywordCounts.map { ($0.keyword, $0.count) },
                        isSelected: { viewModel.filters.filterRankKeywords.contains($0) },
                        label: { $0 },
                        toggle: { keyword in
                            if viewModel.filters.filterRankKeywords.contains(keyword) { viewModel.filters.filterRankKeywords.remove(keyword) }
                            else { viewModel.filters.filterRankKeywords.insert(keyword) }
                        }
                    )
                }
            }
        case .venue:
            if !viewModel.venueCounts.isEmpty {
                sectionBlock(section.title, collapsible: true) {
                    expandableRows(
                        title: section.title,
                        items: viewModel.venueCounts.map { ($0.venue, $0.count) },
                        isSelected: { viewModel.filters.filterVenueAbbr.contains($0) },
                        label: { $0 },
                        toggle: { venue in
                            if viewModel.filters.filterVenueAbbr.contains(venue) { viewModel.filters.filterVenueAbbr.remove(venue) }
                            else { viewModel.filters.filterVenueAbbr.insert(venue) }
                        }
                    )
                }
            }
        case .publicationType:
            if !viewModel.publicationTypeCounts.isEmpty {
                sectionBlock(section.title, collapsible: true) {
                    expandableRows(
                        title: section.title,
                        items: viewModel.publicationTypeCounts.map { ($0.type, $0.count) },
                        isSelected: { viewModel.filters.filterPublicationType.contains($0) },
                        label: { publicationTypeLabel($0) },
                        toggle: { type in
                            if viewModel.filters.filterPublicationType.contains(type) { viewModel.filters.filterPublicationType.remove(type) }
                            else { viewModel.filters.filterPublicationType.insert(type) }
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func sectionBlock<Content: View>(
        _ title: String,
        collapsible: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isCollapsed = collapsedSectionBlocks.contains(title)
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if collapsible {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if isCollapsed { collapsedSectionBlocks.remove(title) }
                            else { collapsedSectionBlocks.insert(title) }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: sectionIcon(title))
                                .font(.system(size: 10 * AppStyleConfig.fontScale, weight: .semibold))
                                .foregroundStyle(Color.accentColor.opacity(0.7))
                            Text(title.uppercased())
                                .font(AppTypography.overline)
                                .kerning(0.8)
                                .foregroundStyle(.tertiary)
                            Spacer(minLength: 0)
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 10 * AppStyleConfig.fontScale, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: sectionIcon(title))
                            .font(.system(size: 10 * AppStyleConfig.fontScale, weight: .semibold))
                            .foregroundStyle(Color.accentColor.opacity(0.7))
                        Text(title.uppercased())
                            .font(AppTypography.overline)
                            .kerning(0.8)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, rowHorizontalInset)
            .padding(.top, AppMetrics.tabBarTop)
            .padding(.bottom, max(4, AppMetrics.inlineRowVertical + 2))
            if !isCollapsed {
                content()
                    .padding(.bottom, max(4, AppMetrics.inlineRowVertical + 2))
            }
        }
    }

    private func sectionIcon(_ title: String) -> String {
        switch title.lowercased() {
        case "flagged":           return "flag.fill"
        case "status":            return "gauge.with.dots.needle.33percent"
        case "year":              return "calendar"
        case "ranks":             return "chart.bar.fill"
        case "tags":              return "tag.fill"
        case "venue":             return "building.columns.fill"
        case "publication type":  return "doc.text.fill"
        default:                  return "line.3.horizontal.decrease"
        }
    }

    @ViewBuilder
    private func tagNamespaceBlock<Content: View>(group: TagNamespaceGroup, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.label)
                .font(AppTypography.labelMedium)
                .foregroundStyle(.tertiary)
            .padding(.horizontal, rowHorizontalInset)
            .padding(.bottom, max(3, AppMetrics.badgeVertical + 3))
            content()
        }
    }

    // MARK: - Expandable Rows (embedded in sectionBlock)

    @ViewBuilder
    private func expandableRows(
        title: String,
        items: [(String, Int)],
        isSelected: @escaping (String) -> Bool,
        label: @escaping (String) -> String,
        toggle: @escaping (String) -> Void
    ) -> some View {
        let expanded = expandedSections.contains(title)
        let visible  = expanded ? items : Array(items.prefix(defaultVisibleCount))
        let hasMore  = items.count > defaultVisibleCount
        let remaining = items.count - defaultVisibleCount

        VStack(spacing: 0) {
            ForEach(visible, id: \.0) { (key, count) in
                FilterRow(
                    label: label(key),
                    count: count,
                    isSelected: isSelected(key),
                    rowHeight: rowHeight,
                    leadingInset: rowHorizontalInset,
                    trailingInset: rowTrailingInset
                ) {
                    toggle(key)
                }
            }

            if hasMore {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if expanded { expandedSections.remove(title) }
                        else { expandedSections.insert(title) }
                    }
                } label: {
                    Text(expanded ? "Show less" : "Show \(remaining) more")
                        .font(AppTypography.label)
                        .foregroundStyle(Color.accentColor.opacity(0.75))
                        .padding(.horizontal, rowHorizontalInset)
                        .padding(.vertical, max(4, AppMetrics.inlineRowVertical + 1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Status Rows

    private func flaggedRow() -> some View {
        Button {
            viewModel.filters.filterFlaggedOnly.toggle()
        } label: {
            HStack(spacing: 0) {
                Text("Flagged")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(viewModel.filters.filterFlaggedOnly ? .primary : .secondary)
                    .fontWeight(viewModel.filters.filterFlaggedOnly ? .medium : .regular)
                    .padding(.leading, rowHorizontalInset)
                Spacer(minLength: 8)
                Text("\(viewModel.flaggedCount)")
                    .font(AppTypography.monoLabel)
                    .foregroundStyle(.quaternary)
                    .monospacedDigit()
                    .padding(.trailing, rowTrailingInset)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: rowHeight)
            .appSelectableRowSurface(selected: viewModel.filters.filterFlaggedOnly)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusRows() -> some View {
        VStack(spacing: 0) {
            ForEach(Paper.ReadingStatus.allCases, id: \.self) { status in
                let count = viewModel.papers.filter { $0.currentReadingStatus == status }.count
                let isSelected = viewModel.filters.filterReadingStatus.contains(status.rawValue)
                Button { toggleStatus(status.rawValue) } label: {
                    HStack(spacing: 0) {
                        Text(status.rawValue.capitalized)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .fontWeight(isSelected ? .medium : .regular)
                            .padding(.leading, rowHorizontalInset)
                        Spacer(minLength: 8)
                        Text("\(count)")
                            .font(AppTypography.monoLabel)
                            .foregroundStyle(.quaternary)
                            .monospacedDigit()
                            .padding(.trailing, rowTrailingInset)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: rowHeight)
                    .appSelectableRowSurface(selected: isSelected)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func toggleStatus(_ status: String) {
        if viewModel.filters.filterReadingStatus.contains(status) { viewModel.filters.filterReadingStatus.remove(status) }
        else { viewModel.filters.filterReadingStatus.insert(status) }
    }

    private func publicationTypeLabel(_ raw: String) -> String {
        switch raw {
        case "conference": return "Conference"
        case "journal":    return "Journal"
        case "workshop":   return "Workshop"
        case "preprint":   return "Preprint"
        case "book":       return "Book/Chapter"
        case "other":      return "Other"
        default:           return raw
        }
    }

}

// MARK: - FilterRow

    private struct FilterRow: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let rowHeight: CGFloat
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(label)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .fontWeight(isSelected ? .medium : .regular)
                    .lineLimit(1)
                    .padding(.leading, leadingInset)

                Spacer(minLength: 8)

                Text("\(count)")
                    .font(AppTypography.monoLabel)
                    .foregroundStyle(.quaternary)
                    .monospacedDigit()
                    .padding(.trailing, trailingInset)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: rowHeight)
            .appSelectableRowSurface(selected: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}
