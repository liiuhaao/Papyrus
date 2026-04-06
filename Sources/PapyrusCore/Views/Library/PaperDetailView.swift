// PaperDetailView.swift
// Detail view for a single paper

import SwiftUI
import AppKit

struct PaperDetailView: View {
    @ObservedObject var paper: Paper
    @ObservedObject var viewModel: PaperListViewModel
    @ObservedObject var taskState: LibraryTaskStateModel
    @ObservedObject var detailModel: LibraryDetailModel
    @ObservedObject private var appConfig = AppConfig.shared
    @AppStorage("detail.notesCollapsed") private var notesCollapsed = false

    var body: some View {
        Group {
            if paper.isDeleted || paper.managedObjectContext == nil {
                EmptyView()
            } else {
                detailTab
            }
        }
        .textSelection(.enabled)
        .onAppear { handlePendingEditRequest() }
        .onChange(of: taskState.pendingMetadataEditPaperID) { _, _ in
            handlePendingEditRequest()
        }
    }

    // MARK: - Detail Tab

    private var detailTab: some View {
        let snapshot = makeSnapshot()
        return DetailNotesSplitView(
            top: AnyView(detailContent(snapshot: snapshot)),
            bottom: AnyView(PaperNotesPanel(paper: paper)),
            requestedBottomThickness: notesCollapsed ? notesCollapsedHeight : notesDefaultHeight,
            minimumBottomThickness: notesCollapsed ? notesCollapsedHeight : notesMinHeight
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notesMinHeight: CGFloat {
        max(124, 140 * AppStyleConfig.spacingScale)
    }

    private var notesDefaultHeight: CGFloat {
        max(220, 260 * AppStyleConfig.spacingScale)
    }

    private var notesCollapsedHeight: CGFloat {
        max(44, 50 * AppStyleConfig.spacingScale)
    }

    private func detailContent(snapshot: PaperDetailSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperDetailHeaderSection(snapshot: snapshot)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    PaperOverviewSection(
                        snapshot: snapshot,
                        currentStatus: paper.currentReadingStatus,
                        onStatusChange: { status in
                            applyOverviewMutation {
                                paper.setReadingStatus(status)
                            }
                        },
                        onFlagToggle: {
                            paper.toggleFlag()
                            paper.dateModified = Date()
                            try? paper.managedObjectContext?.save()
                            viewModel.fetchPapers()
                        },
                        onPinToggle: {
                            viewModel.setPinned(!paper.isPinned, for: [paper])
                        },
                        rating: Binding(
                            get: { Int(paper.rating) },
                            set: { value in
                                applyOverviewMutation {
                                    paper.rating = Int16(value)
                                }
                            }
                        )
                    )
                    if let abstract = paper.abstract, !abstract.isEmpty {
                        Divider().padding(.vertical, 16)
                        PaperAbstractSection(abstract: abstract)
                    }
                    Divider().padding(.vertical, 16)
                    PaperRawRecordSection(paper: paper)
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func makeSnapshot() -> PaperDetailSnapshot {
        let tags = paper.tagsList.filter { !$0.isEmpty }
        let displayTags = tags.count <= 10 ? tags : Array(tags.prefix(10)) + ["+\(tags.count - 10)"]
        var rankPills: [(String, Color)] = []
        if let venueObject = paper.venueObject {
            rankPills = venueObject.orderedRankEntries(visibleSourceKeys: appConfig.rankBadgeSources).map { key, value in
                (
                    RankSourceConfig.displayLabel(for: key, value: value),
                    rankColor(for: key, value: value)
                )
            }
        }

        return PaperDetailSnapshot(
            title: paper.displayTitle,
            authors: paper.formattedAuthors,
            venue: displayVenueName,
            year: Int(paper.year),
            citationCountText: paper.citationCountText,
            doi: paper.doi,
            arxivId: paper.arxivId,
            dateAdded: paper.dateAdded,
            isFlagged: paper.isFlagged,
            isPinned: paper.isPinned,
            tags: displayTags,
            rankPills: rankPills
        )
    }

    private var venueDisplay: String {
        let rawVenue = (paper.venueObject?.name ?? paper.venue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawVenue.isEmpty else { return "Unknown" }
        let parts = VenueFormatter.resolvedVenueParts(rawVenue, abbreviation: paper.venueObject?.abbreviation)
        let full = parts.full.trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? rawVenue : full
    }

    private var displayVenueName: String? {
        let value = venueDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == "Unknown" ? nil : value
    }

    private func rankColor(for key: String, value: String) -> Color {
        AppColors.rankColor(source: key, value: value)
    }

    private func publicationTypeDisplay(_ raw: String) -> String {
        switch raw {
        case "conference": return "Conference"
        case "journal": return "Journal"
        case "workshop": return "Workshop"
        case "preprint": return "Preprint"
        case "book": return "Book/Chapter"
        case "other": return "Other"
        default: return raw
        }
    }

    private var doiURL: URL? {
        guard let raw = paper.doi?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let normalized = raw
            .replacingOccurrences(of: "https://doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "doi:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return URL(string: "https://doi.org/\(normalized)")
    }

    private var arxivURL: URL? {
        guard let raw = paper.arxivId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let normalized = raw
            .replacingOccurrences(of: "https://arxiv.org/abs/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://arxiv.org/abs/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "arxiv:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return URL(string: "https://arxiv.org/abs/\(normalized)")
    }

    private var scholarURL: URL? {
        let query: String
        if let doi = paper.doi?.trimmingCharacters(in: .whitespacesAndNewlines), !doi.isEmpty {
            query = "doi:\(doi)"
        } else if let arxiv = paper.arxivId?.trimmingCharacters(in: .whitespacesAndNewlines), !arxiv.isEmpty {
            query = "arxiv:\(arxiv)"
        } else {
            let title = paper.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            query = title
        }
        return queryURL(base: "https://scholar.google.com/scholar", query: query)
    }

    private var semanticScholarURL: URL? {
        let query: String
        if let doi = paper.doi?.trimmingCharacters(in: .whitespacesAndNewlines), !doi.isEmpty {
            query = "DOI:\(doi)"
        } else if let arxiv = paper.arxivId?.trimmingCharacters(in: .whitespacesAndNewlines), !arxiv.isEmpty {
            query = "arXiv:\(arxiv)"
        } else {
            let title = paper.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            query = title
        }
        return queryURL(base: "https://www.semanticscholar.org/search", query: query)
    }

    private func queryURL(base: String, query: String) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }

    private func handlePendingEditRequest() {
        guard let target = taskState.pendingMetadataEditPaperID else { return }
        guard target == paper.objectID else { return }
        detailModel.requestEditMetadata(for: paper)
        taskState.pendingMetadataEditPaperID = nil
    }

    private func applyOverviewMutation(_ mutation: () -> Void) {
        mutation()
        paper.dateModified = Date()
        try? paper.managedObjectContext?.save()
        viewModel.fetchPapers()
    }
}

private struct DetailNotesSplitView: NSViewControllerRepresentable {
    let top: AnyView
    let bottom: AnyView
    let requestedBottomThickness: CGFloat
    let minimumBottomThickness: CGFloat

    func makeNSViewController(context: Context) -> DetailNotesSplitViewController {
        DetailNotesSplitViewController(
            top: top,
            bottom: bottom,
            requestedBottomThickness: requestedBottomThickness,
            minimumBottomThickness: minimumBottomThickness
        )
    }

    func updateNSViewController(_ controller: DetailNotesSplitViewController, context: Context) {
        controller.update(
            top: top,
            bottom: bottom,
            requestedBottomThickness: requestedBottomThickness,
            minimumBottomThickness: minimumBottomThickness
        )
    }
}

private final class DetailNotesSplitViewController: NSSplitViewController {
    private let topHostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private let bottomHostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private let topItem: NSSplitViewItem
    private let bottomItem: NSSplitViewItem

    private var pendingBottomThickness: CGFloat?
    private var lastRequestedBottomThickness: CGFloat?

    init(
        top: AnyView,
        bottom: AnyView,
        requestedBottomThickness: CGFloat,
        minimumBottomThickness: CGFloat
    ) {
        topItem = NSSplitViewItem(viewController: topHostingController)
        bottomItem = NSSplitViewItem(viewController: bottomHostingController)
        super.init(nibName: nil, bundle: nil)

        splitView = NotesDividerSplitView()
        splitView.isVertical = false

        topItem.canCollapse = false
        bottomItem.canCollapse = false
        bottomItem.minimumThickness = minimumBottomThickness

        addSplitViewItem(topItem)
        addSplitViewItem(bottomItem)

        update(
            top: top,
            bottom: bottom,
            requestedBottomThickness: requestedBottomThickness,
            minimumBottomThickness: minimumBottomThickness,
            forceBottomThicknessApply: true
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let pendingBottomThickness else { return }
        applyBottomThickness(pendingBottomThickness)
    }

    func update(
        top: AnyView,
        bottom: AnyView,
        requestedBottomThickness: CGFloat,
        minimumBottomThickness: CGFloat,
        forceBottomThicknessApply: Bool = false
    ) {
        topHostingController.rootView = top
        bottomHostingController.rootView = bottom
        bottomItem.minimumThickness = minimumBottomThickness

        guard forceBottomThicknessApply || shouldApplyBottomThickness(requestedBottomThickness) else { return }
        lastRequestedBottomThickness = requestedBottomThickness
        pendingBottomThickness = requestedBottomThickness
        if isViewLoaded {
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
        }
    }

    private func shouldApplyBottomThickness(_ thickness: CGFloat) -> Bool {
        guard let lastRequestedBottomThickness else { return true }
        return abs(lastRequestedBottomThickness - thickness) > 0.5
    }

    private func applyBottomThickness(_ thickness: CGFloat) {
        guard splitView.arrangedSubviews.count >= 2 else { return }
        let totalHeight = splitView.bounds.height
        guard totalHeight > 0 else { return }

        let dividerThickness = splitView.dividerThickness
        let proposedPosition = totalHeight - thickness - dividerThickness
        let minPosition = splitView.minPossiblePositionOfDivider(at: 0)
        let maxPosition = splitView.maxPossiblePositionOfDivider(at: 0)
        let clampedPosition = max(minPosition, min(maxPosition, proposedPosition))

        splitView.setPosition(clampedPosition, ofDividerAt: 0)
        pendingBottomThickness = nil
    }
}

private final class NotesDividerSplitView: NSSplitView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isVertical = false
        dividerStyle = .thin
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var dividerColor: NSColor {
        NSColor.separatorColor.withAlphaComponent(0.28)
    }

    override func drawDivider(in rect: NSRect) {
        dividerColor.setFill()
        rect.fill()
    }
}

struct RawRow: View {
    let label: String
    let value: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(AppTypography.labelStrong)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text(value ?? "—")
                .font(AppTypography.bodySmall)
                .foregroundStyle(value != nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .textSelection(.enabled)
            Spacer()
        }
    }
}

struct StarRating: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = (rating == star) ? 0 : star
                } label: {
                    Text("★")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.star)
                        .opacity(star <= rating ? 1 : 0.22)
                        .frame(width: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
