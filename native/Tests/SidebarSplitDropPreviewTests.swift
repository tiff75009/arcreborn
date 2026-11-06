// SPDX-License-Identifier: MPL-2.0
import AppKit
private final class Canvas:NSView { override var isFlipped:Bool { true } }
@main struct SidebarSplitDropPreviewTests {
    static func main() {
        _ = NSApplication.shared
        let host = Canvas(frame:NSRect(x:0,y:0,width:245,height:60));host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(srgbRed:0.34,green:0.33,blue:0.45,alpha:1).cgColor
        let row = NSView(frame:NSRect(x:0,y:12,width:245,height:36));host.addSubview(row)
        let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView = host; window.orderFront(nil)
        let item = SidebarSplitDropPreview.Item(title:"Documentation du projet",image:NSImage(systemSymbolName:"globe",accessibilityDescription:nil))
        func tick(_ delay:Double) { RunLoop.main.run(until:Date(timeIntervalSinceNow:delay)) }
        let preview = SidebarSplitDropPreview(items:[item],incomingCount:1,ink:.white)
        preview.present(in:host,covering:row,frame:row.frame,before:false)
        tick(0.3)
        precondition(row.alphaValue == 0 && preview.superview === host)
        precondition(preview.hitTest(NSPoint(x:20,y:20)) == nil,"a visual preview cannot steal drag events")
        let slot = preview.subviews[0], label = preview.subviews[1]
        precondition(slot.frame.minX > label.frame.minX && slot.frame.width > 100 && slot.frame.width < 125)
        func capture(_ name:String) {
            let directory = URL(fileURLWithPath:"/tmp/arc-split-preview");try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            host.layoutSubtreeIfNeeded();host.displayIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds)!
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name+".png"))
        }
        capture("right")
        preview.setBefore(true);tick(0.3)
        precondition(slot.frame.maxX < label.frame.minX && preview.before)
        capture("left")
        preview.close(animated:true);tick(0.3)
        precondition(row.alphaValue == 1 && preview.superview == nil,"leaving restores the original row")
        for count in 1...3 {
            let p = SidebarSplitDropPreview(items:Array(repeating:item,count:count),incomingCount:4-count,ink:.white)
            p.present(in:host,covering:row,frame:row.frame,before:false,animated:false)
            p.setBefore(true);p.close(animated:true);p.close(animated:false)
            precondition(row.alphaValue == 1 && p.superview == nil,"interrupted previews always restore the row")
        }
        window.orderOut(nil)
        print("PASS: split preview left/right layout, pointer transparency, cancellation, interrupted exits and groups up to four panes")
    }
}
