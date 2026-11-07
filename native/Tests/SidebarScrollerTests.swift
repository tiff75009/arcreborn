// SPDX-License-Identifier: MPL-2.0
import AppKit

@main enum SidebarScrollerTests {
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:400),styleMask:[.borderless],backing:.buffered,defer:false)
        let scroll = SidebarScrollView(frame:NSRect(x:5,y:0,width:240,height:400))
        window.contentView!.addSubview(scroll)
        scroll.contentView = SidebarClipView()
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
        let table = SidebarTabsTableView()
        let data = TabRows()
        table.headerView = nil; table.intercellSpacing = .zero; table.rowHeight = 36
        table.addTableColumn(NSTableColumn(identifier:.init("tab"))); table.dataSource = data
        let clicks = ClickRecorder()
        table.target = clicks; table.action = #selector(ClickRecorder.clicked(_:))
        scroll.documentView = table
        window.orderBack(nil)
        for height:CGFloat in [240,500,800] {
            window.setContentSize(NSSize(width:440, height:height))
            scroll.frame.size.height = height
            let almostFull = Int(height / table.rowHeight)
            for count in [36,almostFull,2] {
                data.count = count; table.reloadData(); table.sizeToFit(); scroll.tile()
                let clip = scroll.contentView
                for offset in [CGFloat.zero, table.rect(ofRow:count / 2).minY] {
                    var viewport = clip.bounds
                    viewport.origin.y = offset
                    clip.scroll(to:clip.constrainBoundsRect(viewport).origin)
                    let visible = scroll.documentVisibleRect
                    for row in 0..<count {
                        let center = NSPoint(x:45, y:table.rect(ofRow:row).midY)
                        guard visible.contains(center) else { continue }
                        let point = scroll.superview!.convert(center, from:table)
                        let hit = scroll.hitTest(point)
                        precondition(hit === table || hit?.isDescendant(of:table) == true,
                                     "visible row \(row) must receive clicks, including at the bottom edge")
                    }
                }
                if count == 36 {
                    var middle = clip.bounds; middle.origin.y = 203
                    clip.scroll(to:clip.constrainBoundsRect(middle).origin)
                    // Exercise both partially visible edges with fixed window coordinates.
                    let viewport = scroll.documentVisibleRect
                    let ys = [viewport.maxY-2, viewport.minY+2, viewport.maxY-39]
                    checkClicks(ys, in: table, recorder: clicks, window: window)
                }
                let wheel = CGEvent(scrollWheelEvent2Source:nil, units:.pixel, wheelCount:1,
                                    wheel1:-300, wheel2:0, wheel3:0)!
                for _ in 0..<12 { scroll.scrollWheel(with:NSEvent(cgEvent:wheel)!) }
                let gap = scroll.documentVisibleRect.maxY-table.rect(ofRow:count-1).maxY
                let expected = min(144,(height*0.25).rounded())
                if count != 2 {
                    precondition(gap >= expected-1 && gap <= expected+12,"stable space below the last row at the scroll limit")
                    precondition(table.row(at:NSPoint(x:15,y:scroll.documentVisibleRect.maxY-5)) == -1,"the gap contains no tab")
                } else { precondition(clip.bounds.minY == 0,"short lists need no extra scroll") }
                let lastCenters = [count-2, count-1, count-2].map { table.rect(ofRow:$0).midY }
                checkClicks(lastCenters, in:table, recorder:clicks, window:window)
                table.scrollRowToVisible(0)
                precondition(scroll.documentVisibleRect.minY == 0, "explicit row reveal still works")
            }
        }
        print("PASS: scrolling leaves space below the tabs and clicks keep the original row and viewport")
    }

    private static func checkClicks(_ positions: [CGFloat], in table: NSTableView, recorder: ClickRecorder, window: NSWindow) {
        let clip = table.enclosingScrollView!.contentView
        let origin = clip.bounds.origin
        let clicks = positions.map { y -> (Int, NSPoint) in
            let point = NSPoint(x:35, y:y)
            return (table.row(at:point), table.convert(point, to:nil))
        }
        clip.postsBoundsChangedNotifications = true
        let observer = NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification, object:clip, queue:nil) { _ in
            precondition(clip.bounds.origin == origin, "the list moved during the click")
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        for (row, point) in clicks {
            precondition(row >= 0)
            let time = ProcessInfo.processInfo.systemUptime
            func event(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with:type, location:point, modifierFlags:[], timestamp:time,
                                   windowNumber:window.windowNumber, context:nil, eventNumber:1,
                                   clickCount:1, pressure:type == .leftMouseDown ? 1 : 0)!
            }
            recorder.row = nil
            NSApp.postEvent(event(.leftMouseUp), atStart:true)
            window.sendEvent(event(.leftMouseDown))
            precondition(recorder.row == row, "clicked a different row from the one under the pointer")
            precondition(clip.bounds.origin == origin, "the list shifted on selection")
        }
    }
}

private final class ClickRecorder: NSObject {
    var row: Int?
    @objc func clicked(_ table: NSTableView) { row = table.clickedRow }
}

private final class TabRows: NSObject, NSTableViewDataSource {
    var count = 0
    func tableView(_ tableView:NSTableView, objectValueFor column:NSTableColumn?, row:Int) -> Any? { "Tab \(row)" }
    func numberOfRows(in tableView:NSTableView) -> Int { count }
}
