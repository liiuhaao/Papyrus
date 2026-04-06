import SwiftUI

struct PaperDetailSnapshot {
    let title: String
    let authors: String
    let venue: String?
    let year: Int
    let citationCountText: String
    let doi: String?
    let arxivId: String?
    let dateAdded: Date
    let isFlagged: Bool
    let isPinned: Bool
    let tags: [String]
    let rankPills: [(String, Color)]
}

private struct PaperRawRecordSnapshot {
    let title: String?
    let originalFilename: String?
    let authors: String?
    let venue: String?
    let yearText: String?
    let doi: String?
    let arxivId: String?
    let publicationType: String?
    let rankSources: String?
    let tags: String?
    let readingStatus: String
    let rating: String
    let citationCount: String?
    let filePath: String?
    let dateAdded: String?
    let dateModified: String?
    let abstract: String?
}

struct PaperDetailHeaderSection: View {
    @ObservedObject private var appConfig = AppConfig.shared
    let snapshot: PaperDetailSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: max(8, AppMetrics.inlineRowVertical * 2.5)) {
            Text(snapshot.title)
                .font(AppTypography.titleMedium)
                .fixedSize(horizontal: false, vertical: true)

            Text(snapshot.authors)
                .font(AppTypography.bodySmall)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppMetrics.panelPadding - 8)
        .padding(.top, max(6, AppMetrics.inlineRowVertical * 2))
        .padding(.bottom, AppMetrics.cardPadding)
    }
}

struct PaperOverviewSection: View {
    @ObservedObject private var appConfig = AppConfig.shared
    let snapshot: PaperDetailSnapshot
    let currentStatus: Paper.ReadingStatus
    let onStatusChange: (Paper.ReadingStatus) -> Void
    let onFlagToggle: () -> Void
    let onPinToggle: () -> Void
    let rating: Binding<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: max(10, AppMetrics.cardPadding)) {
            if let venue = snapshot.venue, !venue.isEmpty {
                detailRow("Venue", value: venue)
            }
            if snapshot.year > 0 {
                detailRow("Year", value: String(snapshot.year))
            }
            if !snapshot.rankPills.isEmpty {
                detailCustomRow("Ranks") {
                    pillFlow(snapshot.rankPills)
                }
            }
            detailCustomRow("Pin") {
                Button(action: onPinToggle) {
                    HStack(spacing: 6) {
                        Image(systemName: snapshot.isPinned ? "pin.fill" : "pin")
                        Text(snapshot.isPinned ? "Pinned" : "Pin")
                    }
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(snapshot.isPinned ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            detailCustomRow("Flag") {
                Button(action: onFlagToggle) {
                    HStack(spacing: 6) {
                        Image(systemName: snapshot.isFlagged ? "flag.fill" : "flag")
                        Text(snapshot.isFlagged ? "Flagged" : "Mark")
                    }
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(snapshot.isFlagged ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            detailCustomRow("Status") {
                HStack(spacing: 6) {
                    ForEach(Paper.ReadingStatus.allCases, id: \.rawValue) { status in
                        let selected = currentStatus == status
                        Button {
                            onStatusChange(status)
                        } label: {
                            Text(status.label)
                                .appBadgePill(
                                    selected ? AppStatusStyle.tint(for: status) : .secondary,
                                    horizontal: AppMetrics.pillHorizontal,
                                    vertical: AppMetrics.pillVertical
                                )
                                .opacity(selected ? 1 : 0.8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            detailCustomRow("Rating") {
                StarRating(rating: rating)
            }
            detailCustomRow("Added") {
                Text(snapshot.dateAdded.formatted(date: .abbreviated, time: .omitted))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.primary)
            }
            detailCustomRow("Cited") {
                Text(snapshot.citationCountText)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.primary)
            }
            if !snapshot.tags.isEmpty {
                detailCustomRow("Tags") {
                    pillFlow(snapshot.tags.map { ($0, AppColors.tagColor($0)) })
                }
            }
            if let doi = snapshot.doi, !doi.isEmpty {
                detailRow("DOI", value: doi)
            }
            if let arxiv = snapshot.arxivId, !arxiv.isEmpty {
                detailRow("arXiv", value: arxiv)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        detailCustomRow(label) {
            Text(value)
                .font(AppTypography.bodySmall)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .textSelection(.enabled)
        }
    }

    private func detailCustomRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: max(10, AppMetrics.inlineRowVertical * 3)) {
            Text(label)
                .font(AppTypography.label)
                .foregroundStyle(.tertiary)
                .frame(width: 56 * AppStyleConfig.spacingScale, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    private func pillFlow(_ pills: [(String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
                Text(pill.0)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .appBadgePill(pill.1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct PaperAbstractSection: View {
    @ObservedObject private var appConfig = AppConfig.shared
    let abstract: String

    var body: some View {
        VStack(alignment: .leading, spacing: max(6, AppMetrics.inlineRowVertical * 2)) {
            Text("ABSTRACT")
                .font(AppTypography.overline)
                .kerning(0.8)
                .foregroundStyle(.tertiary)
            Text(abstract)
                .font(AppTypography.bodySmall)
                .foregroundStyle(.primary.opacity(0.85))
                .lineSpacing(max(4, AppMetrics.inlineRowVertical + 1))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PaperRawRecordSection: View {
    @ObservedObject var paper: Paper
    @ObservedObject private var appConfig = AppConfig.shared
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if isExpanded {
                let snapshot = rawRecordSnapshot()
                VStack(alignment: .leading, spacing: max(6, AppMetrics.inlineRowVertical * 2)) {
                    RawRow(label: "title", value: snapshot.title)
                    RawRow(label: "originalFilename", value: snapshot.originalFilename)
                    RawRow(label: "authors", value: snapshot.authors)
                    RawRow(label: "venue", value: snapshot.venue)
                    RawRow(label: "year", value: snapshot.yearText)
                    RawRow(label: "doi", value: snapshot.doi)
                    RawRow(label: "arxivId", value: snapshot.arxivId)
                    RawRow(label: "publicationType", value: snapshot.publicationType)
                    RawRow(label: "rankSources", value: snapshot.rankSources)
                    RawRow(label: "tags", value: snapshot.tags)
                    RawRow(label: "readingStatus", value: snapshot.readingStatus)
                    RawRow(label: "rating", value: snapshot.rating)
                    RawRow(label: "citationCount", value: snapshot.citationCount)
                    RawRow(label: "filePath", value: snapshot.filePath)
                    RawRow(label: "dateAdded", value: snapshot.dateAdded)
                    RawRow(label: "dateModified", value: snapshot.dateModified)
                    if let abstract = snapshot.abstract, !abstract.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("abstract")
                                .font(AppTypography.labelStrong)
                                .foregroundStyle(.secondary)
                            Text(abstract)
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(.primary)
                                .lineLimit(6)
                        }
                    }
                }
                .padding(.top, 8)
            }
        } label: {
            Label("Raw Record", systemImage: "doc.text.magnifyingglass")
                .font(AppTypography.labelMedium)
                .foregroundStyle(.secondary)
        }
    }

    private func rawRecordSnapshot() -> PaperRawRecordSnapshot {
        PaperRawRecordSnapshot(
            title: paper.title,
            originalFilename: paper.originalFilename,
            authors: paper.authors,
            venue: paper.venue,
            yearText: paper.year > 0 ? "\(paper.year)" : nil,
            doi: paper.doi,
            arxivId: paper.arxivId,
            publicationType: paper.publicationType,
            rankSources: paper.venueObject?.rankSourceJSON,
            tags: paper.tags,
            readingStatus: paper.currentReadingStatus.rawValue,
            rating: "\(paper.rating)",
            citationCount: paper.citationCount >= 0 ? "\(paper.citationCount)" : nil,
            filePath: paper.filePath,
            dateAdded: (paper.value(forKey: "dateAdded") as? Date)?.formatted(.dateTime),
            dateModified: (paper.value(forKey: "dateModified") as? Date)?.formatted(.dateTime),
            abstract: paper.abstract
        )
    }
}
