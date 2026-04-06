import SwiftUI
import AppKit

struct FeedDetailPane: View {
    let selectedItems: [FeedItem]
    let onStatusChange: (UUID, FeedItem.Status) -> Void

    var body: some View {
        switch selectedItems.count {
        case 0:  noSelectionState
        case 1:  singleItemView(selectedItems[0])
        default: multiItemView
        }
    }

    // MARK: - No Selection

    private var noSelectionState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Select an item")
                .font(AppTypography.bodySmall)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Single Item

    private func singleItemView(_ item: FeedItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header — matches PaperDetailHeaderSection
                VStack(alignment: .leading, spacing: max(8, AppMetrics.inlineRowVertical * 2.5)) {
                    Text(item.title)
                        .font(AppTypography.titleMedium)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.displayAuthors)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppMetrics.panelPadding - 8)
                .padding(.top, max(6, AppMetrics.inlineRowVertical * 2))
                .padding(.bottom, AppMetrics.cardPadding)

                Divider()

                // Overview rows — matches PaperOverviewSection
                VStack(alignment: .leading, spacing: max(10, AppMetrics.cardPadding)) {
                    detailRow("Year", value: String(item.year))
                    if let venue = item.venue, !venue.isEmpty {
                        detailRow("Venue", value: venue)
                    }
                    detailRow("Source", value: item.subscriptionLabel)
                    detailCustomRow("Status") {
                        HStack(spacing: 6) {
                            ForEach(feedStatuses, id: \.rawValue) { status in
                                let selected = item.status == status
                                Button {
                                    onStatusChange(item.id, status)
                                } label: {
                                    Text(status.label)
                                        .appBadgePill(
                                            selected ? statusColor(status) : .secondary,
                                            horizontal: AppMetrics.pillHorizontal,
                                            vertical: AppMetrics.pillVertical
                                        )
                                        .opacity(selected ? 1 : 0.8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let arxivId = item.arxivId {
                        detailRow("arXiv", value: arxivId)
                    }
                    if let doi = item.doi {
                        detailRow("DOI", value: doi)
                    }
                    detailCustomRow("Fetched") {
                        Text(item.fetchedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(.primary)
                    }

                    // Abstract — matches PaperAbstractSection
                    if let abstract = item.abstract, !abstract.isEmpty {
                        Divider().padding(.vertical, 16)
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
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Multi-Item

    private var multiItemView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                Text("\(selectedItems.count) items selected")
                    .font(AppTypography.titleSmall)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private var feedStatuses: [FeedItem.Status] {
        [.unread, .read]
    }

    private func statusColor(_ status: FeedItem.Status) -> Color {
        switch status {
        case .unread: return .blue
        case .read:   return .green
        }
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

    private func detailCustomRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
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
}
