import SwiftUI
import AppKit

struct FeedListPane: View {
    @ObservedObject var feedViewModel: FeedViewModel
    @ObservedObject var selectionModel: FeedInteractionModel
    let searchText: String

    private var visibleItems: [FeedItem] {
        feedViewModel.feedItems.filter { $0.matchesSearch(searchText) }
    }

    var body: some View {
        Group {
            if visibleItems.isEmpty {
                emptyState
            } else {
                NativeFeedListView(
                    items: visibleItems,
                    contentRevision: feedViewModel.feedItemsRevision,
                    searchText: searchText,
                    selectionModel: selectionModel,
                    feedViewModel: feedViewModel
                )
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("Feed is empty")
                .font(AppTypography.titleSmall)
                .foregroundStyle(.secondary)
            if !searchText.isEmpty {
                Text("No results for \"\(searchText)\"")
                    .font(AppTypography.label)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else if feedViewModel.subscriptions.isEmpty {
                Text("Add a subscription to start discovering papers.")
                    .font(AppTypography.label)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else if feedViewModel.selectedSubscriptionFilter != nil {
                Text("No new papers for this subscription.")
                    .font(AppTypography.label)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Click refresh to check for new papers.")
                    .font(AppTypography.label)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
}

private struct NativeFeedListView: NSViewRepresentable {
    let items: [FeedItem]
    let contentRevision: Int
    let searchText: String
    @ObservedObject var selectionModel: FeedInteractionModel
    @ObservedObject var feedViewModel: FeedViewModel

    static func estimatedRowHeight() -> CGFloat {
        let scale = AppStyleConfig.fontScale
        let titleLineHeight = 13.0 * scale * 1.22
        let labelHeight = 12.0 * scale * 1.18
        let stackSpacing = ListRowLayoutMetrics.stackSpacing * 2
        let verticalPadding = ListRowLayoutMetrics.verticalPadding * 2
        return ceil(titleLineHeight + labelHeight * 2 + stackSpacing + verticalPadding)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let components = NativeListSupport.makeScrollView(
            columnIdentifier: "feed",
            rowHeight: Self.estimatedRowHeight(),
            coordinator: context.coordinator
        )
        let scrollView = components.scrollView
        let tableView = components.tableView
        tableView.doubleAction = #selector(Coordinator.tableViewDoubleClicked(_:))
        tableView.modifierSelectionHandler = { [weak coordinator = context.coordinator] tableView, event in
            coordinator?.handleModifierSelection(in: tableView, event: event) ?? false
        }
        tableView.contextMenuProvider = { [weak coordinator = context.coordinator] tableView, event in
            coordinator?.makeContextMenu(in: tableView, event: event)
        }

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.scheduleTableUpdate()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativeFeedListView
        weak var tableView: NativeListTableView?
        var isSyncingSelection = false
        var lastRenderedContentRevision: Int?
        var lastRenderedSearchText = ""
        var selectionAnchorRow: Int?
        var lastInteractedItemID: UUID?
        var contextMenuItemIDs: [UUID] = []
        var contextMenuPrimaryItemID: UUID?
        private var hasScheduledTableUpdate = false

        init(parent: NativeFeedListView) {
            self.parent = parent
        }

        func scheduleTableUpdate() {
            guard !hasScheduledTableUpdate else { return }
            hasScheduledTableUpdate = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.hasScheduledTableUpdate = false
                self.reloadIfNeeded()
                self.syncSelectionFromBinding()
            }
        }

        func reloadIfNeeded() {
            guard parent.contentRevision != lastRenderedContentRevision
                || parent.searchText != lastRenderedSearchText else { return }
            tableView?.reloadData()
            lastRenderedContentRevision = parent.contentRevision
            lastRenderedSearchText = parent.searchText
        }

        func syncSelectionFromBinding() {
            guard let tableView else { return }
            let selectedIndexes = IndexSet(
                parent.items.indices.filter { parent.selectionModel.selectedIDs.contains(parent.items[$0].id) }
            )
            guard tableView.selectedRowIndexes != selectedIndexes else { return }
            isSyncingSelection = true
            tableView.selectRowIndexes(selectedIndexes, byExtendingSelection: false)
            isSyncingSelection = false
            updateSelectionAnchor(using: selectedIndexes)
        }

        @objc
        func tableViewDoubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < parent.items.count else { return }
            guard let rawURL = parent.items[row].landingURL, let url = URL(string: rawURL) else { return }
            NSWorkspace.shared.open(url)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.items.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.items.count else { return nil }
            let item = parent.items[row]
            let id = NSUserInterfaceItemIdentifier("FeedListCell")
            var cellView = tableView.makeView(withIdentifier: id, owner: nil) as? NativeListCellView
            if cellView == nil {
                cellView = NativeListCellView()
                cellView?.identifier = id
            }
            cellView?.configure(
                rootView: AnyView(FeedRowView(item: item).id(item.id)),
                showsBottomDivider: row < parent.items.count - 1
            )
            return cellView
        }

        func tableView(
            _ tableView: NSTableView,
            selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet
        ) -> IndexSet {
            guard let event = NSApp.currentEvent else { return proposedSelectionIndexes }
            return resolvedSelectionIndexes(for: tableView, event: event)?.selection ?? proposedSelectionIndexes
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            Self.parentType.estimatedRowHeight()
        }

        private static var parentType: NativeFeedListView.Type { NativeFeedListView.self }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let tableView else { return }
            let orderedIDs = tableView.selectedRowIndexes
                .filter { $0 < parent.items.count }
                .map { parent.items[$0].id }
            parent.selectionModel.applyExternalSelection(
                orderedIDs: orderedIDs,
                preferredPrimaryID: lastInteractedItemID,
                trigger: NativeListSupport.currentSelectionTrigger(default: .mouse)
            )
            updateSelectionAnchor(using: tableView.selectedRowIndexes)
        }

        func makeContextMenu(in tableView: NativeListTableView, event: NSEvent) -> NSMenu? {
            let clickedRow = resolvedClickedRow(in: tableView, event: event)
            guard clickedRow >= 0, clickedRow < parent.items.count else { return nil }

            if !tableView.selectedRowIndexes.contains(clickedRow) {
                isSyncingSelection = true
                tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
                isSyncingSelection = false
                tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification, object: tableView))
            }

            let selectedRows = tableView.selectedRowIndexes.filter { $0 < parent.items.count }
            let selectedItems = selectedRows.map { parent.items[$0] }
            guard !selectedItems.isEmpty else { return nil }

            contextMenuItemIDs = selectedItems.map(\.id)
            contextMenuPrimaryItemID = parent.items[clickedRow].id

            let primaryItem = parent.items[clickedRow]
            let isMulti = selectedItems.count > 1
            let menu = NSMenu()

            if !isMulti, let rawURL = primaryItem.landingURL, let url = URL(string: rawURL) {
                let item = NSMenuItem(title: "Open Online", action: #selector(contextOpenOnline), keyEquivalent: "")
                item.target = self
                item.representedObject = url
                menu.addItem(item)
                menu.addItem(.separator())
            }

            let copyTitleItem = NSMenuItem(title: isMulti ? "Copy Titles" : "Copy Title", action: #selector(contextCopyTitles), keyEquivalent: "")
            copyTitleItem.target = self
            menu.addItem(copyTitleItem)
            menu.addItem(.separator())

            if selectedItems.contains(where: { $0.status != .unread }) {
                let unreadItem = NSMenuItem(title: "Mark as Unread", action: #selector(contextMarkUnread), keyEquivalent: "")
                unreadItem.target = self
                menu.addItem(unreadItem)
            }

            let unreadCount = selectedItems.filter { $0.status == .unread }.count
            if unreadCount > 0 {
                let title = isMulti ? "Mark \(unreadCount) as Read" : "Mark as Read"
                let readItem = NSMenuItem(title: title, action: #selector(contextMarkRead), keyEquivalent: "")
                readItem.target = self
                menu.addItem(readItem)
            }

            return menu
        }

        @objc private func contextOpenOnline(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            NSWorkspace.shared.open(url)
        }

        @objc private func contextCopyTitles() {
            let titles = contextMenuItems().map(\.title).joined(separator: "\n")
            guard !titles.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(titles, forType: .string)
        }

        @objc private func contextMarkUnread() {
            let items = contextMenuItems()
            guard !items.isEmpty else { return }
            if items.count > 1 {
                Task { await parent.feedViewModel.batchMarkUnread(ids: Set(items.map(\.id))) }
            } else if let item = items.first {
                Task { await parent.feedViewModel.markUnread(item) }
            }
        }

        @objc private func contextMarkRead() {
            let items = contextMenuItems()
            guard !items.isEmpty else { return }
            if items.count > 1 {
                Task { await parent.feedViewModel.batchMarkRead(ids: Set(items.map(\.id))) }
            } else if let item = items.first {
                Task { await parent.feedViewModel.markRead(item) }
            }
        }

        func handleModifierSelection(in tableView: NativeListTableView, event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection([.command, .shift])
            guard modifiers.contains(.command) || modifiers.contains(.shift) else { return false }
            guard event.type == .leftMouseDown else { return false }
            guard let selection = resolvedSelectionIndexes(for: tableView, event: event) else { return false }

            isSyncingSelection = true
            tableView.selectRowIndexes(selection.selection, byExtendingSelection: false)
            isSyncingSelection = false
            tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification, object: tableView))
            return true
        }

        private func contextMenuItems() -> [FeedItem] {
            let ids = Set(contextMenuItemIDs)
            return parent.items.filter { ids.contains($0.id) }
        }

        private func resolvedClickedRow(in tableView: NSTableView, event: NSEvent) -> Int {
            NativeListSupport.resolvedClickedRow(in: tableView, event: event)
        }

        private func resolvedSelectionIndexes(
            for tableView: NSTableView,
            event: NSEvent
        ) -> (selection: IndexSet, interactedID: UUID)? {
            let result = NativeListSupport.resolvedSelectionIndexes(
                in: tableView,
                event: event,
                itemCount: parent.items.count,
                selectionAnchorRow: &selectionAnchorRow,
                primarySelectionID: parent.selectionModel.primarySelectionID,
                itemIDAtRow: { parent.items[$0].id }
            )
            lastInteractedItemID = result?.interactedID
            return result
        }

        private func updateSelectionAnchor(using selectedIndexes: IndexSet) {
            NativeListSupport.updateSelectionAnchor(
                using: selectedIndexes,
                selectionAnchorRow: &selectionAnchorRow,
                primarySelectionID: parent.selectionModel.primarySelectionID,
                itemCount: parent.items.count,
                itemIDAtRow: { parent.items[$0].id }
            )
        }
    }
}

private struct FeedRowView: View {
    let item: FeedItem

    private var rowSpacing: CGFloat { ListRowLayoutMetrics.stackSpacing }
    private var metaSpacing: CGFloat { ListRowLayoutMetrics.metaSpacing }

    private var metaLine: String {
        var parts: [String] = []
        if item.year > 0 {
            parts.append(String(item.year))
        }
        if let venue = item.venue?.trimmingCharacters(in: .whitespacesAndNewlines), !venue.isEmpty {
            parts.append(venue)
        }
        parts.append(item.subscriptionLabel)
        return parts.joined(separator: "  ·  ")
    }

    private var statusIcon: String {
        switch item.status {
        case .unread: return "circle"
        case .read: return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .unread: return .blue
        case .read: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            Text(item.title)
                .font(AppTypography.bodyStrong)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.displayAuthors)
                .font(AppTypography.label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: metaSpacing) {
                Text(metaLine)
                    .font(AppTypography.label)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(item.fetchedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(AppTypography.label)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Image(systemName: statusIcon)
                    .font(AppTypography.labelStrong)
                    .foregroundStyle(statusColor)
                    .frame(height: ListRowLayoutMetrics.statusSlotHeight, alignment: .center)
            }
        }
    }
}
