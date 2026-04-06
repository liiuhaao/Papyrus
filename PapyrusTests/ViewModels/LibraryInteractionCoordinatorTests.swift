import CoreData
import Testing
@testable import PapyrusCore

struct LibraryInteractionCoordinatorTests {
    @MainActor
    @Test
    func listModeTracksSinglePrimarySelection() throws {
        let context = TestSupport.makeInMemoryContext()
        let first = TestSupport.makePaper(in: context, title: "First")
        let second = TestSupport.makePaper(in: context, title: "Second")
        try context.save()

        let coordinator = LibraryInteractionCoordinator()
        coordinator.updateMode(.list, visiblePapers: [first, second], selectedPaper: nil)
        coordinator.listSelection.selectedIDs = [second.objectID]

        coordinator.handleListSelectionChange(in: [first, second])

        #expect(coordinator.primarySelectionID == second.objectID)
        #expect(coordinator.activeSelectedPaper(in: [first, second])?.objectID == second.objectID)
    }

    @MainActor
    @Test
    func galleryModeSupportsRangeSelectionAndNavigation() {
        let context = TestSupport.makeInMemoryContext()
        let papers = [
            TestSupport.makePaper(in: context, title: "0"),
            TestSupport.makePaper(in: context, title: "1"),
            TestSupport.makePaper(in: context, title: "2"),
            TestSupport.makePaper(in: context, title: "3"),
            TestSupport.makePaper(in: context, title: "4"),
            TestSupport.makePaper(in: context, title: "5")
        ]

        let coordinator = LibraryInteractionCoordinator()
        coordinator.updateMode(.gallery, visiblePapers: papers, selectedPaper: nil)
        coordinator.gallerySelection.gridColumnCount = 3
        coordinator.gallerySelection.updateCurrentPapers(papers)
        coordinator.gallerySelection.selectPaper(papers[0])
        coordinator.gallerySelection.toggleSelection(for: papers[2], modifiers: [.shift])

        #expect(coordinator.selectedIDs == [papers[0].objectID, papers[1].objectID, papers[2].objectID])

        coordinator.gallerySelection.selectPaper(papers[1])
        GalleryViewInputAdapter().handleNavigation(.down, interactions: coordinator, visiblePapers: papers)

        #expect(coordinator.primarySelectionID == papers[4].objectID)
        #expect(coordinator.selectedIDs == [papers[4].objectID])
    }

    @MainActor
    @Test
    func galleryExternalSelectionKeepsPrimaryAndAnchorStateAligned() {
        let context = TestSupport.makeInMemoryContext()
        let first = TestSupport.makePaper(in: context, title: "First")
        let second = TestSupport.makePaper(in: context, title: "Second")

        let model = GalleryInteractionModel()
        model.updateCurrentPapers([first, second])
        model.gridColumnCount = 2
        model.applyExternalSelection(
            orderedIDs: [second.objectID],
            preferredPrimaryID: second.objectID,
            trigger: .mouse
        )

        #expect(model.selectedIDs == [second.objectID])
        #expect(model.primarySelectionID == second.objectID)
        #expect(model.lastSelectionTrigger == .mouse)

        model.handleNavigation(.left, in: [first, second])

        #expect(model.selectedIDs == [first.objectID])
        #expect(model.primarySelectionID == first.objectID)
    }

    @MainActor
    @Test
    func reconcileSelectionClearsMissingIDsAcrossModes() {
        let context = TestSupport.makeInMemoryContext()
        let kept = TestSupport.makePaper(in: context, title: "Kept")
        let removed = TestSupport.makePaper(in: context, title: "Removed")

        let coordinator = LibraryInteractionCoordinator()
        coordinator.updateMode(.list, visiblePapers: [kept], selectedPaper: nil)
        coordinator.listSelection.selectedIDs = [removed.objectID]
        coordinator.listSelection.primarySelectionID = removed.objectID

        coordinator.reconcileSelection(with: [kept])

        #expect(coordinator.selectedIDs.isEmpty)
        #expect(coordinator.primarySelectionID == nil)
    }
}
