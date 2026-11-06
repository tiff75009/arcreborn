// SPDX-License-Identifier: MPL-2.0
import AppKit

private final class Rows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var ids = [String]()
    func numberOfRows(in tableView: NSTableView) -> Int { ids.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView(frame: NSRect(x:0,y:0,width:220,height:36))
        cell.identifier = NSUserInterfaceItemIdentifier(ids[row]); cell.wantsLayer = true
        let title = NSTextField(labelWithString:ids[row]); title.frame = NSRect(x:12,y:8,width:190,height:20)
        cell.addSubview(title); return cell
    }
}
@main struct SidebarRowMotionTests {
    static func main() {
        _ = NSApplication.shared
        let heartbeat = SidebarDragHeartbeat()
        var refreshes = 0
        heartbeat.start { refreshes += 1 }
        // Exercise AppKit's actual drag mode, without treating a busy CI runner
        // as a 140 ms performance benchmark. The contract is repeated delivery.
        let deadline = Date(timeIntervalSinceNow:2)
        while refreshes < 3 && Date() < deadline {
            _ = RunLoop.main.run(mode:.eventTracking,before:Date(timeIntervalSinceNow:0.02))
        }
        precondition(refreshes >= 3,"a stationary pointer still updates proposals in the native drag run loop")
        heartbeat.stop(); let stopped = refreshes
        let stoppedDeadline = Date(timeIntervalSinceNow:0.1)
        while Date() < stoppedDeadline { _ = RunLoop.main.run(mode:.eventTracking,before:Date(timeIntervalSinceNow:0.02)) }
        RunLoop.main.run(until:Date(timeIntervalSinceNow:0.08))
        precondition(refreshes == stopped,"ending or cancelling the drag stops all proposal callbacks")
        print("PASS: drag proposals refresh while stationary and stop after cancellation")
        var intent = SidebarSplitDropIntent()
        let rect = NSRect(x:0,y:0,width:240,height:36)
        precondition(!intent.update(source:"a",target:"b",at:1))
        for step in 1...9 {
            let point = NSPoint(x:step % 2 == 0 ? 22 : 218,y:step % 3 == 0 ? 8 : 27)
            precondition(SidebarSplitDropIntent.contains(point,in:rect,retainingPreview:false))
            precondition(!intent.update(source:"a",target:"b",at:1+Double(step)*0.03),"adjusting either side preserves the short reorder interval")
        }
        precondition(intent.update(source:"a",target:"b",at:1.33),"side changes and jitter do not postpone split forever")
        precondition(intent.update(source:"a",target:"b",at:1.34),"the preview stays armed on the same row")
        precondition(!intent.update(source:"a",target:"c",at:1.35),"each target has its own dwell")
        precondition(!intent.update(source:"a",target:"c",at:1.60))
        precondition(intent.update(source:"a",target:"c",at:1.68))
        for y:CGFloat in [1,35] {
            precondition(!SidebarSplitDropIntent.contains(NSPoint(x:120,y:y),in:rect,retainingPreview:false),"top and bottom edges remain reorder lanes")
            precondition(!SidebarSplitDropIntent.contains(NSPoint(x:120,y:y),in:rect,retainingPreview:true))
        }
        let nearEdge = NSPoint(x:120,y:3.5)
        precondition(!SidebarSplitDropIntent.contains(nearEdge,in:rect,retainingPreview:false))
        precondition(SidebarSplitDropIntent.contains(nearEdge,in:rect,retainingPreview:true),"an open preview tolerates small vertical adjustments")
        intent.cancel()
        precondition(!intent.update(source:"a",target:"c",at:3),"leaving the target cancels split intent")
        precondition(!intent.update(source:"new",target:"c",at:4),"a new drag never inherits the previous dwell")
        for i in 0..<30 {
            precondition(!intent.update(source:"new",target:"row-\(i)",at:5+Double(i)*0.1),"quickly passing rows must never arm split")
        }
        print("PASS: 320 ms target dwell tolerates side changes and jitter; reorder lanes, preview hysteresis, quick passes, exits and new drags checked")
        let model = Rows(), table = NSTableView(frame:NSRect(x:0,y:0,width:230,height:500))
        table.addTableColumn(NSTableColumn(identifier:.init("tabs"))); table.headerView = nil
        table.dataSource = model; table.delegate = model; table.rowHeight = 36
        let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:245,height:600)); scroll.documentView = table
        let window = NSWindow(contentRect:scroll.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView = scroll; window.orderFront(nil)
        model.ids = ["a","b","c","d","e","f"]
        table.reloadData(); table.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        func advance(_ time:TimeInterval) { RunLoop.main.run(until:Date(timeIntervalSinceNow:time)) }
        func change(_ next:[String], animated:Bool = true) {
            let old = model.ids
            let retained = Dictionary(uniqueKeysWithValues:old.enumerated().compactMap { index,id -> (String,NSView)? in
                guard let view = table.view(atColumn:0,row:index,makeIfNecessary:true) else { return nil }; return (id,view)
            })
            model.ids = next
            SidebarRowMotion.update(table,from:old,to:next,animated:animated)
            advance(animated ? 0.38 : 0.02)
            precondition(table.numberOfRows == next.count)
            for (i,id) in next.enumerated() {
                let view = table.view(atColumn:0,row:i,makeIfNecessary:true)!
                precondition(view.identifier?.rawValue == id,"wrong content at row \(i): \(view.identifier?.rawValue ?? "nil") != \(id)")
                if let existing = retained[id] { precondition(view === existing,"retained rows must move rather than be recreated") }
            }
        }
        table.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false)
        let travelling = table.rowView(atRow:2,makeIfNecessary:true)!
        let start = travelling.frame.minY
        let before = model.ids; model.ids = ["c","a","d","b","f","e"]
        SidebarRowMotion.update(table,from:before,to:model.ids,animated:true)
        let end = table.rect(ofRow:0).minY
        var during = start
        let motionDeadline = Date(timeIntervalSinceNow:1)
        repeat {
            advance(0.008)
            during = travelling.layer?.presentation()?.frame.minY ?? travelling.frame.minY
        } while !(during > end+0.1 && during < start-0.1) && Date() < motionDeadline
        print("Native movement: \(start) → \(during) → \(end)")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            precondition(during > end+0.1 && during < start-0.1,"movement must have visible intermediate positions")
        }
        advance(0.34)
        change(["c","a","d","b","f","e"])
        precondition(model.ids[table.selectedRow] == "c","selection follows the tab")
        change(["folder","a","c","new","f","b"])
        precondition(model.ids[table.selectedRow] == "c")
        change(["b","f","new","c","a","folder"],animated:false)
        change(["c"]); change([]); change(["one","two","three"])
        for i in 0..<20 { change(i % 2 == 0 ? ["three","one","two"] : ["two","three","one"],animated:false) }
        for i in 0..<24 {
            let old = model.ids
            model.ids = i % 2 == 0 ? ["one","two","three"] : ["three","two","one"]
            SidebarRowMotion.update(table,from:old,to:model.ids,animated:true)
            advance(0.008)
        }
        advance(0.38)
        for (i,id) in model.ids.enumerated() {
            precondition(table.view(atColumn:0,row:i,makeIfNecessary:true)?.identifier?.rawValue == id,"rapid reversals retain the final order")
        }
        window.orderOut(nil)
        print("PASS: native row moves preserve identity, content and selection through reorders, folders, inserts, removals empty lists and rapid reversals")
    }
}
