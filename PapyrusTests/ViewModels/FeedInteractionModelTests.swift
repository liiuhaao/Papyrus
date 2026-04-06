import Foundation
import Testing
@testable import PapyrusCore

struct FeedInteractionModelTests {
    @MainActor
    @Test
    func externalSelectionTracksPrimarySelection() {
        let items = makeItems(count: 3)
        let model = FeedInteractionModel()

        model.selectedIDs = [items[1].id]
        model.handleExternalSelectionChange(in: items)

        #expect(model.primarySelectionID == items[1].id)
        #expect(model.selectedItem(in: items)?.id == items[1].id)
    }

    @MainActor
    @Test
    func navigationMovesPrimarySelectionThroughVisibleItems() {
        let items = makeItems(count: 4)
        let model = FeedInteractionModel()

        model.selectItem(items[0])
        model.handleNavigation(.down, in: items)
        #expect(model.primarySelectionID == items[1].id)

        model.handleNavigation(.bottom, in: items)
        #expect(model.primarySelectionID == items[3].id)

        model.handleNavigation(.up, in: items)
        #expect(model.primarySelectionID == items[2].id)
    }

    @MainActor
    @Test
    func syncSelectionFallsBackToFirstVisibleItem() {
        let items = makeItems(count: 2)
        let model = FeedInteractionModel()

        model.selectedIDs = [UUID()]
        model.primarySelectionID = UUID()

        model.syncSelectionToVisibleResults(items)

        #expect(model.selectedIDs == [items[0].id])
        #expect(model.primarySelectionID == items[0].id)
    }

    @MainActor
    @Test
    func reconcileSelectionClearsMissingIDs() {
        let items = makeItems(count: 2)
        let model = FeedInteractionModel()

        model.selectedIDs = [items[1].id]
        model.primarySelectionID = items[1].id

        model.reconcileSelection(validIDs: [items[0].id])

        #expect(model.selectedIDs.isEmpty)
        #expect(model.primarySelectionID == nil)
    }

    private func makeItems(count: Int) -> [FeedItem] {
        (0..<count).map { index in
            FeedItem(
                id: UUID(),
                arxivId: nil,
                doi: nil,
                title: "Item \(index)",
                authors: "Author \(index)",
                abstract: index.isMultiple(of: 2) ? "Abstract \(index)" : nil,
                year: 2024,
                venue: "Venue \(index)",
                pdfURL: nil,
                landingURL: "https://example.com/\(index)",
                fetchedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                subscriptionId: UUID(),
                subscriptionLabel: "Feed",
                status: .unread
            )
        }
    }
}
