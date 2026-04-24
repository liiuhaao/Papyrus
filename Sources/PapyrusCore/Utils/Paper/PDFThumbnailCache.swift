import Foundation
import AppKit
import PDFKit

final class PDFThumbnailCache {
    static let shared = PDFThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private let pdfCache = NSCache<NSString, PDFDocument>()
    private let inFlightLock = NSLock()
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]

    // Limit concurrent PDF opens to avoid memory spikes when many cells are visible
    private static let renderSemaphore = DispatchSemaphore(value: 4)

    private init() {
        // Keep thumbnail memory bounded. PDF page rasters are roughly 4 bytes per pixel.
        cache.countLimit = 50
        cache.totalCostLimit = 64 * 1024 * 1024
        // Cache a small number of PDF documents to avoid repeated file opens
        pdfCache.countLimit = 10
    }

    func cachedThumbnail(for url: URL, size: CGSize) -> NSImage? {
        let key = cacheKey(url: url, size: size)
        return cache.object(forKey: key)
    }

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let key = cacheKey(url: url, size: size)
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let task = inFlightTask(for: url, size: size, key: key)
        return await task.value
    }

    private func renderThumbnail(url: URL, size: CGSize) -> NSImage? {
        Self.renderSemaphore.wait()
        defer { Self.renderSemaphore.signal() }

        let document = cachedPDFDocument(for: url)
        guard let page = document?.page(at: 0) else {
            return nil
        }
        return page.thumbnail(of: size, for: .cropBox)
    }

    private func cachedPDFDocument(for url: URL) -> PDFDocument? {
        let key = url.path as NSString
        if let cached = pdfCache.object(forKey: key) {
            return cached
        }
        guard let document = PDFDocument(url: url) else { return nil }
        pdfCache.setObject(document, forKey: key)
        return document
    }

    private func cacheKey(url: URL, size: CGSize) -> NSString {
        let mod = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        return "\(url.path)|\(Int(size.width))x\(Int(size.height))|\(Int(mod))" as NSString
    }

    private func inFlightTask(for url: URL, size: CGSize, key: NSString) -> Task<NSImage?, Never> {
        let taskKey = key as String

        inFlightLock.lock()
        if let existing = inFlightTasks[taskKey] {
            inFlightLock.unlock()
            return existing
        }

        let task: Task<NSImage?, Never> = Task.detached(priority: .userInitiated) { [self] in
            defer { finishInFlightTask(for: taskKey) }

            if let cached = cache.object(forKey: key) {
                return cached
            }

            guard let image = renderThumbnail(url: url, size: size) else { return Optional<NSImage>.none }
            let pixelWidth = max(1, Int(size.width.rounded(.up)))
            let pixelHeight = max(1, Int(size.height.rounded(.up)))
            let cost = pixelWidth * pixelHeight * 4
            cache.setObject(image, forKey: key, cost: cost)
            return image
        }
        inFlightTasks[taskKey] = task
        inFlightLock.unlock()
        return task
    }

    private func finishInFlightTask(for key: String) {
        inFlightLock.lock()
        inFlightTasks.removeValue(forKey: key)
        inFlightLock.unlock()
    }
}
