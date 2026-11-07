// SPDX-License-Identifier: MPL-2.0
import AppKit

@main struct TabPreviewImagesTests {
    static func main() {
        _ = NSApplication.shared
        let cache = TabPreviewImages()
        let doc = TabPreviewImages.Document(tabID: "tab", profileID: "profile", url: "https://example.test/café")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 600,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        let png = bitmap.representation(using: .png, properties: [:])!
        var calls = 0, notifications = 0
        var reply: ((Data?) -> Void)?
        func request() {
            cache.capture(doc, request: { calls += 1; reply = $0 }, isCurrent: { true }, ready: { notifications += 1 })
        }
        request(); request()
        precondition(calls == 1, "only one capture per tab may be in flight")
        cache.remove(doc); reply?(png)
        precondition(notifications == 0 && cache.image(for: doc) == nil, "late captures from an old document are discarded")
        request(); reply?(nil)
        request(); reply?(png)
        let deadline = Date(timeIntervalSinceNow: 3)
        while notifications == 0 && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        precondition(cache.image(for: doc)?.size == NSSize(width: 540, height: 360))
        precondition(cache.image(for: .init(tabID: doc.tabID, profileID: "private", url: doc.url)) == nil)
        precondition(cache.image(for: .init(tabID: doc.tabID, profileID: doc.profileID, url: doc.url + "/other")) == nil)
        request()
        precondition(calls == 3, "displaying a fresh image must not recapture")
        cache.reset(); request(); cache.reset(); reply?(png)
        precondition(cache.image(for: doc) == nil && notifications == 1, "disabling previews invalidates in-flight captures")
        print("PASS: bounded thumbnail, document/profile isolation, duplicate requests, capture failure, navigation and disabled mode")
    }
}
