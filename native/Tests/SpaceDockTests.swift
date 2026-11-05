// SPDX-License-Identifier: MPL-2.0
import AppKit

// Route AppKit events inside a test window without stealing keyboard focus.
private final class DockTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
@main struct SpaceDockTests {
    static func main() {
        _ = NSApplication.shared
        let window = DockTestWindow(contentRect:NSRect(x:0,y:0,width:146,height:32),styleMask:.borderless,backing:.buffered,defer:false)
        let dock = SpaceDockView()
        window.contentView = dock; window.orderBack(nil)
        let items = ["sf:star.fill","😊","none","none","none","none","none","none","none"].enumerated().map {
            SpaceDockView.Item(id:String($0.offset),name:"Espace "+String($0.offset),icon:$0.element)
        }
        var clicks = [String]()
        func configure(_ selected: String) { dock.update(items,selectedID:selected,ink:.white,select:{ clicks.append($0) }) }
        configure("0"); dock.fit(width:146)
        let slots = dock.subviews.compactMap { $0 as? NSButton }
        func move(_ index:Int?) {
            let p = index.map { NSPoint(x:slots[$0].frame.midX,y:16) } ?? NSPoint(x:0,y:40)
            let event = NSEvent.mouseEvent(with:.mouseMoved,location:dock.convert(p,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:0,pressure:0)!
            dock.trackPointer(event)
        }
        func settle() { RunLoop.current.run(until:Date(timeIntervalSinceNow:0.45)) }
        // Count the actual painted area in a slot. A dot, enlarged dot, and
        // full-color emoji must be distinguishable even with Reduce Motion on.
        func area(_ index:Int) -> (ink:Int,color:Int) {
            let scale:CGFloat = 2, w = Int(dock.bounds.width*scale), h = 64
            let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bitmapFormat:[],bytesPerRow:0,bitsPerPixel:0)!
            let ctx = NSGraphicsContext(bitmapImageRep:rep)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
            ctx.cgContext.scaleBy(x:scale,y:scale); dock.draw(dock.bounds); NSGraphicsContext.restoreGraphicsState()
            var ink = 0, color = 0
            let slot = slots[index].frame
            for x in Int(ceil(slot.minX*scale))..<Int(floor(slot.maxX*scale)) {
                for y in 0..<h {
                    let c = rep.colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!
                    if c.alphaComponent > 0.09 { ink += 1 }
                    if c.alphaComponent > 0.5 && c.redComponent-c.blueComponent > 0.25 { color += 1 }
                }
            }
            return (ink,color)
        }
        let resting = area(0).ink, dot = area(1).ink
        precondition(resting > dot*2 && dot > 0)
        move(1); settle()
        precondition(area(1).color > 80 && area(0).ink <= dot+12 && clicks.isEmpty,"hover reveals only the inactive emoji without invoking it")
        configure("0") // A background render must not reset the pointer or the artwork.
        precondition(area(1).color > 80)
        for i in 2...7 { move(i); RunLoop.current.run(until:Date(timeIntervalSinceNow:0.012)) }
        settle()
        let litDot = area(7)
        precondition(litDot.ink > dot*2 && litDot.color == 0 && area(1).color == 0,"iconless focus grows into a dot and the old emoji disappears")
        slots[7].performClick(nil); precondition(clicks == ["7"])
        configure("7"); move(1); settle(); move(nil); settle()
        precondition(area(1).color == 0 && area(7).ink > dot*2,"leaving restores the newly selected space")
        window.orderOut(nil)
        print("PASS: rendered space dock at rest, emoji hover, sweep, background render, click and exit")
    }
}
