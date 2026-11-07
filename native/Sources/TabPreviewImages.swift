// SPDX-License-Identifier: MPL-2.0
import AppKit
import ImageIO

/// Per-window, memory-only. Chromium supplies pixels from an already visible
/// document. A navigation, profile change or disabled setting invalidates replies.
final class TabPreviewImages {
    struct Document: Equatable {
        let tabID: String
        let profileID: String
        let url: String
        var key: NSString { [tabID, profileID, url].joined(separator: "\u{0}") as NSString }
    }
    private final class Entry: NSObject {
        let image: NSImage
        let time = ProcessInfo.processInfo.systemUptime
        init(_ image: NSImage) { self.image = image }
    }
    private let images = NSCache<NSString, Entry>()
    private var pending: [String: UUID] = [:]
    private let decoding = DispatchQueue(label: "browser.tab-preview.thumbnail", qos: .utility)
    init() {
        images.countLimit = 32
        images.totalCostLimit = 16 * 1024 * 1024
    }
    func image(for document: Document) -> NSImage? { images.object(forKey: document.key)?.image }
    func remove(_ document: Document) {
        pending.removeValue(forKey: document.tabID)
        images.removeObject(forKey: document.key)
    }
    func reset() { pending.removeAll(); images.removeAllObjects() }

    func capture(_ document: Document, request: (@escaping (Data?) -> Void) -> Void,
                 isCurrent: @escaping () -> Bool, ready: @escaping () -> Void) {
        guard pending[document.tabID] == nil else { return }
        if let entry = images.object(forKey: document.key), ProcessInfo.processInfo.systemUptime - entry.time < 2 { return }
        let ticket = UUID()
        pending[document.tabID] = ticket
        request { [weak self] data in
            guard let self, self.pending[document.tabID] == ticket else { return }
            guard let data, isCurrent() else { self.pending.removeValue(forKey: document.tabID); return }
            self.decoding.async { [weak self] in
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 540, kCGImageSourceShouldCacheImmediately: true]
                let source = CGImageSourceCreateWithData(data as CFData, nil)
                let pixels = source.flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary) }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.pending[document.tabID] == ticket else { return }
                    self.pending.removeValue(forKey: document.tabID)
                    guard let pixels, isCurrent() else { return }
                    let image = NSImage(cgImage: pixels, size: NSSize(width: pixels.width, height: pixels.height))
                    self.images.setObject(Entry(image), forKey: document.key, cost: pixels.bytesPerRow * pixels.height)
                    ready()
                }
            }
        }
    }
}
