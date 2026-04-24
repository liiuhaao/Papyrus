import Foundation
import AppKit
import PDFKit

final class PDFThumbnailCache {
    static let shared = PDFThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private let inFlightLock = NSLock()
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]

    private init() {
        // Keep thumbnail memory bounded. PDF page rasters are roughly 4 bytes per pixel.
        cache.countLimit = 50
        cache.totalCostLimit = 64 * 1024 * 1024
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
        guard let document = PDFDocument(url: url),
              let page = document.page(at: 0) else {
            return nil
        }
        return page.thumbnail(of: size, for: .cropBox)
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
