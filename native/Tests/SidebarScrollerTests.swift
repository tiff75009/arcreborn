// SPDX-License-Identifier: MPL-2.0
import AppKit

@main enum SidebarScrollerTests {
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:400),styleMask:[.borderless],backing:.buffered,defer:false)
        let scroll = SidebarScrollView(frame:NSRect(x:5,y:0,width:240,height:400))
        window.contentView!.addSubview(scroll)
        scroll.hasVerticalScroller = true; scroll.borderType = .noBorder
        scroll.drawsBackground = false; scroll.automaticallyAdjustsContentInsets = false
        let document = NSView(frame:NSRect(x:0,y:0,width:234,height:1800))
        scroll.documentView = document
        let close = NSButton(title:"×",target:nil,action:nil)
        document.addSubview(close)
        let scroller = scroll.verticalScroller as! SidebarScroller
        for style in [NSScroller.Style.overlay,.legacy] {
            scroll.scrollerStyle = style
            for width:CGFloat in [180,245,440] {
                scroll.frame.size.width = width-5; scroll.tile()
                document.frame.size.width = scroll.contentSize.width
                close.frame = NSRect(x:document.bounds.width-28,y:scroll.contentView.bounds.midY,width:22,height:22)
                let closeEdge = scroll.superview!.convert(NSPoint(x:close.bounds.maxX-2,y:close.bounds.midY),from:close)
                precondition(scroll.hitTest(closeEdge) === close,"transparent scroller padding must not intercept the close button")
                precondition(abs(scroll.contentSize.width-(width-11)) < 0.01,"tab width remains unchanged with the new edge rail")
                let slot = scroll.convert(scroller.rect(for:.knobSlot),from:scroller)
                precondition(abs(slot.maxX-scroll.bounds.maxX) < 0.01 && slot.minX >= scroll.contentView.frame.maxX,"scrollbar never covers tabs or close buttons")
                for value in [0.0,0.5,1.0] {
                    scroller.doubleValue = value; scroller.knobProportion = 0.22
                    let knob = scroller.rect(for:.knob)
                    let center = scroller.convert(NSPoint(x:knob.midX,y:knob.midY),to:nil)
                    precondition(scroller.testPart(center) == .knob,"thin thumb retains native dragging hit detection")
                    let image = NSImage(size:scroller.bounds.size,flipped:scroller.isFlipped) { _ in scroller.drawKnob(); return true }
                    let pixels = NSBitmapImageRep(cgImage:image.cgImage(forProposedRect:nil,context:nil,hints:nil)!)
                    // Scan the opaque span anywhere in the knob, ignoring fade.
                    let columns = (0..<pixels.pixelsWide).filter { x in (0..<pixels.pixelsHigh).contains { pixels.colorAt(x:x,y:$0)!.alphaComponent > 0.05 } }
                    let scale = CGFloat(pixels.pixelsWide)/scroller.bounds.width
                    precondition(!columns.isEmpty && abs(CGFloat(columns.count)/scale-3) < 0.6,"thumb remains three points wide at every position, including Retina")
                }
            }
        }
        let table = NSTableView()
        let data = TabRows()
        table.headerView = nil; table.intercellSpacing = .zero; table.rowHeight = 36
        table.addTableColumn(NSTableColumn(identifier:.init("tab"))); table.dataSource = data
        scroll.documentView = table
        for height:CGFloat in [240,500,800] {
            scroll.frame.size.height = height
            for count in [36,2] {
                data.count = count; table.reloadData(); table.sizeToFit(); scroll.tile()
                let clip = scroll.contentView
                var end = clip.bounds; end.origin.y = 10000
                clip.scroll(to:clip.constrainBoundsRect(end).origin)
                let gap = scroll.documentVisibleRect.maxY-table.rect(ofRow:count-1).maxY
                let expected = min(144,(height*0.25).rounded())
                if count == 36 {
                    precondition(gap >= expected-1 && gap <= expected+12,"stable space below the last row at the scroll limit")
                    precondition(table.row(at:NSPoint(x:15,y:scroll.documentVisibleRect.maxY-5)) == -1,"the gap contains no tab")
                } else { precondition(clip.bounds.minY == 0,"short lists need no extra scroll") }
            }
        }
        print("PASS: thin edge scrollbar, preserved tab width, no overlap and native thumb hit detection at three widths and positions")
    }
}

private final class TabRows: NSObject, NSTableViewDataSource {
    var count = 0
    func numberOfRows(in tableView:NSTableView) -> Int { count }
}
