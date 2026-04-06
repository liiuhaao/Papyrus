import AppKit
import Foundation

enum PaperDragDrop {
    static let internalPaperType = "com.papyrus.internal-paper"

    static func makeDragPasteboardItem(filePath: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        let url = URL(fileURLWithPath: filePath)
        item.setString(url.absoluteString, forType: .fileURL)
        item.setString("1", forType: NSPasteboard.PasteboardType(internalPaperType))
        return item
    }

    static func droppedPDFURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return objects.filter { $0.pathExtension.lowercased() == "pdf" }
    }
}
