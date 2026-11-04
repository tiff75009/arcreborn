import AppKit

@main struct FaviconPixelsTests {
    static func main() {
        func icon(_ color: NSColor, size: CGFloat = 16) -> NSImage {
            NSImage(size:NSSize(width:size,height:size),flipped:false) { rect in
                color.setFill(); rect.fill(); return true
            }
        }
        let first = icon(.systemRed)
        let identical = icon(.systemRed)
        precondition(first !== identical && faviconPixels(first) == faviconPixels(identical), "Redownloaded identical pixels must not replace the icon")
        precondition(faviconPixels(first) == faviconPixels(icon(.systemRed,size:64)), "Equivalent representations normalize to display pixels")
        precondition(faviconPixels(first) != faviconPixels(icon(.systemBlue)), "Changed colors must replace the icon")
        precondition(faviconPixels(first) != faviconPixels(icon(.clear)), "Transparency changes must replace the icon")
        precondition(faviconPixels(first)?.count == 4096, "The comparison has a fixed small memory cost")
        print("PASS: 5 favicon pixel assertions")
    }
}
