import Combine
import Foundation

@MainActor
final class FeedInteractionModel: ObservableObject {
    @Published var selectedIDs: Set<UUID> = []
    @Published var primarySelectionID: UUID?
    @Published var lastSelectionTrigger: SelectionTrigger = .programmatic

    func selectedItem(in items: [FeedItem]) -> FeedItem? {
        guard !selectedIDs.isEmpty else { return nil }
        if let primarySelectionID {
            return items.first(where: { $0.id == primarySelectionID })
        }
        return items.first(where: { selectedIDs.contains($0.id) })
    }

    func selectedItems(in items: [FeedItem]) -> [FeedItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    func selectItem(_ item: FeedItem?) {
        let nextSelectedIDs: Set<UUID>
        let nextPrimarySelectionID: UUID?
        if let item {
            nextSelectedIDs = [item.id]
            nextPrimarySelectionID = item.id
        } else {
            nextSelectedIDs = []
            nextPrimarySelectionID = nil
        }

        if selectedIDs != nextSelectedIDs {
            selectedIDs = nextSelectedIDs
        }
        if primarySelectionID != nextPrimarySelectionID {
            primarySelectionID = nextPrimarySelectionID
        }
        if lastSelectionTrigger != .programmatic {
            lastSelectionTrigger = .programmatic
        }
    }

    func applyExternalSelection(
        orderedIDs: [UUID],
        preferredPrimaryID: UUID?,
        trigger: SelectionTrigger
    ) {
        let nextSelectedIDs = Set(orderedIDs)
        let nextPrimarySelectionID = resolvedPrimarySelectionID(
            orderedIDs: orderedIDs,
            preferredPrimaryID: preferredPrimaryID,
            currentPrimaryID: primarySelectionID,
            fallbackPrimaryID: nil
        )

        if selectedIDs != nextSelectedIDs {
            selectedIDs = nextSelectedIDs
        }
        if primarySelectionID != nextPrimarySelectionID {
            primarySelectionID = nextPrimarySelectionID
        }
        if lastSelectionTrigger != trigger {
            lastSelectionTrigger = trigger
        }
    }

    func clearSelection() {
        if !selectedIDs.isEmpty {
            selectedIDs = []
        }
        if primarySelectionID != nil {
            primarySelectionID = nil
        }
        if lastSelectionTrigger != .programmatic {
            lastSelectionTrigger = .programmatic
        }
    }

    func handleExternalSelectionChange(in items: [FeedItem]) {
        applyExternalSelection(
            orderedIDs: orderedSelectedIDs(in: items, selectedIDs: selectedIDs, id: \.id),
            preferredPrimaryID: primarySelectionID,
            trigger: lastSelectionTrigger
        )
    }

    func syncSelectionToVisibleResults(_ items: [FeedItem]) {
        guard !items.isEmpty else {
            if !selectedIDs.isEmpty {
                selectedIDs = []
            }
            if primarySelectionID != nil {
                primarySelectionID = nil
            }
            return
        }

        if let selected = selectedItem(in: items),
           items.contains(where: { $0.id == selected.id }) {
            return
        }

        let first = items[0]
        let nextSelectedIDs: Set<UUID> = [first.id]
        if selectedIDs != nextSelectedIDs {
            selectedIDs = nextSelectedIDs
        }
        if primarySelectionID != first.id {
            primarySelectionID = first.id
        }
    }

    func reconcileSelection(validIDs: Set<UUID>) {
        let newSelection = selectedIDs.intersection(validIDs)
        if newSelection != selectedIDs {
            selectedIDs = newSelection
        }

        let nextPrimarySelectionID: UUID?
        if let primarySelectionID, newSelection.contains(primarySelectionID) {
            nextPrimarySelectionID = primarySelectionID
        } else {
            nextPrimarySelectionID = newSelection.first
        }

        if primarySelectionID != nextPrimarySelectionID {
            primarySelectionID = nextPrimarySelectionID
        }
    }

    func handleNavigation(_ command: LinearNavigationCommand, in items: [FeedItem]) {
        let currentIndex = selectedItem(in: items).flatMap { selected in
            items.firstIndex(where: { $0.id == selected.id })
        }
        guard let nextIndex = nextLinearSelectionIndex(
            currentIndex: currentIndex,
            command: command,
            count: items.count
        ) else { return }

        let nextItem = items[nextIndex]
        let nextSelectedIDs: Set<UUID> = [nextItem.id]
        if selectedIDs != nextSelectedIDs {
            selectedIDs = nextSelectedIDs
        }
        if primarySelectionID != nextItem.id {
            primarySelectionID = nextItem.id
        }
        if lastSelectionTrigger != .keyboard {
            lastSelectionTrigger = .keyboard
        }
    }
}
