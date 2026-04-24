import AppKit
import SwiftUI

enum NativeListSupport {
    static func makeScrollView<Coordinator: NSObject & NSTableViewDataSource & NSTableViewDelegate>(
        columnIdentifier: String,
        rowHeight: CGFloat,
        coordinator: Coordinator,
        configure: (NativeListTableView) -> Void = { _ in }
    ) -> (scrollView: NSScrollView, tableView: NativeListTableView) {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(columnIdentifier))
        column.resizingMask = .autoresizingMask

        let tableView = NativeListTableView()
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.usesAutomaticRowHeights = false
        tableView.rowHeight = rowHeight
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = []
        tableView.delegate = coordinator
        tableView.dataSource = coordinator
        tableView.target = coordinator

        configure(tableView)

        scrollView.documentView = tableView
        return (scrollView, tableView)
    }

    static func resolvedClickedRow(in tableView: NSTableView, event: NSEvent) -> Int {
        if tableView.clickedRow >= 0 {
            return tableView.clickedRow
        }
        let point = tableView.convert(event.locationInWindow, from: nil)
        return tableView.row(at: point)
    }

    static func resolvedSelectionIndexes<ItemID: Hashable>(
        in tableView: NSTableView,
        event: NSEvent,
        itemCount: Int,
        selectionAnchorRow: inout Int?,
        primarySelectionID: ItemID?,
        itemIDAtRow: (Int) -> ItemID
    ) -> (selection: IndexSet, interactedID: ItemID)? {
        let modifiers = event.modifierFlags.intersection([.command, .shift])
        let clickedRow = resolvedClickedRow(in: tableView, event: event)
        guard clickedRow >= 0, clickedRow < itemCount else {
            return nil
        }

        let interactedID = itemIDAtRow(clickedRow)

        if modifiers.contains(.shift) {
            let anchorRow = selectionAnchorRow
                ?? primarySelectionID.flatMap { row(for: $0, itemCount: itemCount, itemIDAtRow: itemIDAtRow) }
                ?? tableView.selectedRowIndexes.first
                ?? clickedRow
            selectionAnchorRow = anchorRow
            let range = IndexSet(integersIn: min(anchorRow, clickedRow)...max(anchorRow, clickedRow))
            if modifiers.contains(.command) {
                return (tableView.selectedRowIndexes.union(range), interactedID)
            }
            return (range, interactedID)
        }

        if modifiers.contains(.command) {
            selectionAnchorRow = clickedRow
            var toggled = tableView.selectedRowIndexes
            if toggled.contains(clickedRow) {
                toggled.remove(clickedRow)
            } else {
                toggled.insert(clickedRow)
            }
            return (toggled, interactedID)
        }

        selectionAnchorRow = clickedRow
        return (IndexSet(integer: clickedRow), interactedID)
    }

    static func updateSelectionAnchor<ItemID: Hashable>(
        using selectedIndexes: IndexSet,
        selectionAnchorRow: inout Int?,
        primarySelectionID: ItemID?,
        itemCount: Int,
        itemIDAtRow: (Int) -> ItemID
    ) {
        guard !selectedIndexes.isEmpty else {
            selectionAnchorRow = nil
            return
        }
        if selectedIndexes.count == 1 {
            selectionAnchorRow = selectedIndexes.first
            return
        }
        if let anchorRow = selectionAnchorRow, selectedIndexes.contains(anchorRow) {
            return
        }
        selectionAnchorRow = primarySelectionID.flatMap {
            row(for: $0, itemCount: itemCount, itemIDAtRow: itemIDAtRow)
        } ?? selectedIndexes.first
    }

    static func currentSelectionTrigger(default trigger: SelectionTrigger) -> SelectionTrigger {
        guard let event = NSApp.currentEvent else { return trigger }
        if event.type == .keyDown { return .keyboard }
        if event.type == .leftMouseDown || event.type == .leftMouseUp { return .mouse }
        return trigger
    }

    private static func row<ItemID: Hashable>(
        for itemID: ItemID,
        itemCount: Int,
        itemIDAtRow: (Int) -> ItemID
    ) -> Int? {
        (0..<itemCount).first { itemIDAtRow($0) == itemID }
    }
}

final class NativeListTableView: NSTableView {
    var modifierSelectionHandler: ((NativeListTableView, NSEvent) -> Bool)?
    var contextMenuProvider: ((NativeListTableView, NSEvent) -> NSMenu?)?
    var externalDropHoverDidChange: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        let modifiers = event.modifierFlags.intersection([.command, .shift])

        if clickedRow < 0 && modifiers.isEmpty {
            deselectAll(nil)
            return
        }
        if modifierSelectionHandler?(self, event) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        return contextMenuProvider?(self, event) ?? super.menu(for: event)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        externalDropHoverDidChange?(false)
        super.draggingExited(sender)
    }
}

final class NativeListHostingView: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = window?.currentEvent ?? NSApp.currentEvent else {
            return super.hitTest(point)
        }

        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp:
            return nil
        default:
            return self
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let rowView = superview(ofType: NSTableRowView.self) {
            rowView.mouseDown(with: event)
            return
        }
        if let tableView = nearestTableView {
            tableView.mouseDown(with: event)
            return
        }
        super.mouseDown(with: event)
    }
}

final class NativeListCellView: NSTableCellView {
    private var hostingView: NativeListHostingView?
    private var dividerView: NSView?

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        rootView: AnyView,
        showsBottomDivider: Bool,
        insets: EdgeInsets = EdgeInsets(
            top: ListRowLayoutMetrics.verticalPadding,
            leading: ListRowLayoutMetrics.horizontalPadding,
            bottom: ListRowLayoutMetrics.verticalPadding,
            trailing: ListRowLayoutMetrics.horizontalPadding
        )
    ) {
        let wrappedView = AnyView(
            VStack(spacing: 0) {
                rootView
                    .padding(insets)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        )

        // Tear down old hosting view to prevent KVO dependency accumulation
        hostingView?.removeFromSuperview()
        hostingView = nil
        dividerView?.removeFromSuperview()
        dividerView = nil

        let hosting = NativeListHostingView(rootView: wrappedView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)

        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor
            .withAlphaComponent(ListRowLayoutMetrics.dividerOpacity)
            .cgColor
        addSubview(divider)

        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ListRowLayoutMetrics.dividerInset),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ListRowLayoutMetrics.dividerInset),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        self.hostingView = hosting
        self.dividerView = divider

        dividerView?.layer?.backgroundColor = NSColor.separatorColor
            .withAlphaComponent(ListRowLayoutMetrics.dividerOpacity)
            .cgColor
        dividerView?.isHidden = !showsBottomDivider
    }
}
