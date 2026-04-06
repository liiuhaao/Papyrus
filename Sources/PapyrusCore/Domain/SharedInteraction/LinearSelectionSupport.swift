import Foundation

func orderedSelectedIDs<Item, ID: Hashable>(
    in items: [Item],
    selectedIDs: Set<ID>,
    id: KeyPath<Item, ID>
) -> [ID] {
    items.compactMap { item in
        let resolvedID = item[keyPath: id]
        return selectedIDs.contains(resolvedID) ? resolvedID : nil
    }
}

func resolvedPrimarySelectionID<ID: Hashable>(
    orderedIDs: [ID],
    preferredPrimaryID: ID?,
    currentPrimaryID: ID?,
    fallbackPrimaryID: ID?
) -> ID? {
    let selectionSet = Set(orderedIDs)

    if let preferredPrimaryID, selectionSet.contains(preferredPrimaryID) {
        return preferredPrimaryID
    }
    if let currentPrimaryID, selectionSet.contains(currentPrimaryID) {
        return currentPrimaryID
    }
    if let fallbackPrimaryID, selectionSet.contains(fallbackPrimaryID) {
        return fallbackPrimaryID
    }

    return orderedIDs.last
}

func nextLinearSelectionIndex(
    currentIndex: Int?,
    command: LinearNavigationCommand,
    count: Int,
    pageStep: Int = 10
) -> Int? {
    guard count > 0 else { return nil }

    switch command {
    case .top:
        return 0
    case .bottom:
        return count - 1
    case .pageUp:
        return max(0, (currentIndex ?? 0) - pageStep)
    case .pageDown:
        return min(count - 1, (currentIndex ?? -1) + pageStep)
    case .up, .left:
        return max(0, (currentIndex ?? 1) - 1)
    case .down, .right:
        return min(count - 1, (currentIndex ?? -1) + 1)
    }
}
