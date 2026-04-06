import CoreData
import Testing
@testable import PapyrusCore

struct LibraryCommandUseCasesTests {
    @MainActor
    @Test
    func setPinnedStateAssignsNextPinOrderAndCanUnpin() throws {
        let context = TestSupport.makeInMemoryContext()
        let existingPinned = TestSupport.makePaper(
            in: context,
            title: "Pinned",
            isPinned: true,
            pinOrder: 3
        )
        let target = TestSupport.makePaper(in: context, title: "Target")
        try context.save()

        let useCase = SetPinnedStateUseCase(viewContext: context)
        try useCase.execute(pinned: true, papers: [target], allPapers: [existingPinned, target])

        #expect(target.isPinned == true)
        #expect(target.pinOrder == 4)

        try useCase.execute(pinned: false, papers: [target], allPapers: [existingPinned, target])

        #expect(target.isPinned == false)
        #expect(target.pinOrder == 0)
    }

    @MainActor
    @Test
    func reorderPinnedPapersOnlyReordersVisibleSubset() throws {
        let context = TestSupport.makeInMemoryContext()

        let first = TestSupport.makePaper(in: context, title: "First", isPinned: true, pinOrder: 0)
        let second = TestSupport.makePaper(in: context, title: "Second", isPinned: true, pinOrder: 1)
        let third = TestSupport.makePaper(in: context, title: "Third", isPinned: true, pinOrder: 2)
        let hidden = TestSupport.makePaper(in: context, title: "Hidden", isPinned: true, pinOrder: 3)
        try context.save()

        let useCase = ReorderPinnedPapersUseCase(viewContext: context)
        try useCase.execute(
            from: IndexSet(integer: 0),
            to: 2,
            visiblePinned: [first, third],
            allPapers: [first, second, third, hidden]
        )

        #expect(first.pinOrder == 2)
        #expect(second.pinOrder == 1)
        #expect(third.pinOrder == 0)
        #expect(hidden.pinOrder == 3)
    }
}
