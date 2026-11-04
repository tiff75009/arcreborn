import AppKit

private class TestSurface: NSView {
    override var isFlipped: Bool { true }
    var color = NSColor.black
    override func draw(_ dirtyRect: NSRect) { color.setFill(); bounds.fill() }
}

@main struct SpaceTransitionTests {
    static var assertions = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard condition() else { fatalError(message) }
    }
    static func pixels(_ view: NSView) -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds)!
        view.cacheDisplay(in:view.bounds,to:bitmap)
        return bitmap
    }
    static func color(_ image: NSBitmapImageRep, x: Int, y: Int, size: NSSize) -> NSColor {
        image.colorAt(x:x*image.pixelsWide/Int(size.width),y:y*image.pixelsHigh/Int(size.height))!.usingColorSpace(.sRGB)!
    }
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:240,height:300),styleMask:.borderless,backing:.buffered,defer:false)
        let host = TestSurface(frame:NSRect(x:0,y:0,width:240,height:300)); host.wantsLayer = true
        window.contentView = host
        let header = TestSurface(frame:NSRect(x:10,y:40,width:210,height:24)); header.color = .red
        let folder = TestSurface(frame:NSRect(x:10,y:82,width:210,height:30)); folder.color = .green
        host.addSubview(header); host.addSubview(folder)
        let region = NSRect(x:0,y:35,width:240,height:230)
        let transition = SpaceSwitchTransition(host:host,views:[header,folder],region:region)
        header.color = .blue; header.needsDisplay = true
        folder.color = .yellow; folder.needsDisplay = true
        transition.captureIncoming(views:[header,folder],towardsRight:true)
        header.color = .red; header.needsDisplay = true
        folder.color = .green; folder.needsDisplay = true
        transition.conceal([header,folder]); transition.setProgress(0.5)
        let half = pixels(host)
        let oldHeader = color(half,x:30,y:50,size:host.bounds.size)
        let nextHeader = color(half,x:160,y:50,size:host.bounds.size)
        let oldFolder = color(half,x:30,y:95,size:host.bounds.size)
        let nextFolder = color(half,x:160,y:95,size:host.bounds.size)
        check(oldHeader.redComponent > 0.8 && oldHeader.blueComponent < 0.2,"outgoing header must stay at its original vertical position")
        check(nextHeader.blueComponent > 0.8 && nextHeader.redComponent < 0.2,"incoming header must be visible beside outgoing header")
        check(oldFolder.greenComponent > oldFolder.redComponent+0.25,"outgoing folder must remain visible while sliding")
        check(nextFolder.greenComponent > 0.8 && nextFolder.redComponent > 0.8,"incoming folder must appear progressively")
        transition.setProgress(0)
        let returned = color(pixels(host),x:30,y:50,size:host.bounds.size)
        check(returned.redComponent > 0.8 && returned.blueComponent < 0.2,"reversing restores original content position")
        transition.finish()
        check(header.alphaValue == 1 && folder.alphaValue == 1 && host.subviews.count == 2,"cancelling restores live views and removes snapshots")
        let backdrop = ThemeBackdropView(frame:host.bounds); backdrop.wantsLayer = true
        backdrop.theme = .solid("#FF0000"); host.addSubview(backdrop)
        backdrop.beginPreview(theme:.solid("#0000FF"),dark:false)
        backdrop.setPreviewProgress(0.5)
        let blended = color(pixels(backdrop),x:120,y:150,size:backdrop.bounds.size)
        check(blended.redComponent > 0.3 && blended.blueComponent > 0.3 && blended.greenComponent < 0.35,"theme must mix both colors at half gesture")
        backdrop.endPreview()
        let original = color(pixels(backdrop),x:120,y:150,size:backdrop.bounds.size)
        check(original.redComponent > 0.8 && original.blueComponent < 0.25,"cancelled theme preview restores original color")
        print("PASS: \(assertions) sidebar transition rendering assertions")
    }
}
