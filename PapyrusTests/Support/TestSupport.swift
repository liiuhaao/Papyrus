import CoreData
import AppKit
import PDFKit
import Testing
@testable import PapyrusCore

@MainActor
enum TestSupport {
    static func makeInMemoryContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    static func makePaper(
        in context: NSManagedObjectContext,
        title: String = "Test Paper",
        isPinned: Bool = false,
        pinOrder: Int32 = 0
    ) -> Paper {
        let entity = NSEntityDescription.entity(forEntityName: "Paper", in: context)!
        let paper = Paper(entity: entity, insertInto: context)
        paper.id = UUID()
        paper.title = title
        paper.dateAdded = Date()
        paper.dateModified = Date()
        paper.isPinned = isPinned
        paper.pinOrder = pinOrder
        paper.isFlagged = false
        paper.readingStatus = Paper.ReadingStatus.unread.rawValue
        paper.rating = 0
        paper.citationCount = -1
        return paper
    }

    static func makeVenue(
        in context: NSManagedObjectContext,
        name: String,
        abbreviation: String? = nil,
        rankSources: [String: String] = [:]
    ) -> Venue {
        let entity = NSEntityDescription.entity(forEntityName: "Venue", in: context)!
        let venue = Venue(entity: entity, insertInto: context)
        venue.name = name
        venue.abbreviation = abbreviation
        venue.setRankSources(rankSources)
        return venue
    }

    static func makeTempPDF(
        named name: String = UUID().uuidString,
        size: CGSize = CGSize(width: 400, height: 400)
    ) throws -> URL {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()

        let document = PDFDocument()
        let page = try #require(PDFPage(image: image))
        document.insert(page, at: 0)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name).appendingPathExtension("pdf")
        try? FileManager.default.removeItem(at: url)
        try #require(document.dataRepresentation()).write(to: url)
        return url
    }

    static func makeTempTextPDF(
        named name: String = UUID().uuidString,
        lines: [String],
        size: CGSize = CGSize(width: 612, height: 792)
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension("pdf")
        try? FileManager.default.removeItem(at: url)

        var mediaBox = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        context.beginPDFPage(nil)

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        var y = size.height - 72.0
        for (index, line) in lines.enumerated() {
            let fontSize: CGFloat
            if index == 0 {
                fontSize = 11
            } else if index <= 2 {
                fontSize = 24
            } else if index <= 5 {
                fontSize = 14
            } else {
                fontSize = 11
            }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.black
            ]
            NSString(string: line).draw(at: CGPoint(x: 72, y: y), withAttributes: attrs)
            y -= max(18, fontSize + 6)
        }

        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        return url
    }
}
