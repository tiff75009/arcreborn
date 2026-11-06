// SPDX-License-Identifier: MPL-2.0
import AppKit

private final class PointerWindow:NSWindow {
    var pointer = NSPoint(x:-1000,y:-1000)
    override var mouseLocationOutsideOfEventStream:NSPoint { pointer }
}
private final class Canvas:NSView { override var isFlipped:Bool { true } }
private final class Rows:NSObject,NSTableViewDataSource,NSTableViewDelegate {
    var reused = 0
    func numberOfRows(in tableView:NSTableView) -> Int { 80 }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("tabCell")
        let existing = tableView.makeView(withIdentifier:identifier,owner:self) as? TabCell
        if existing != nil { reused += 1 }
        let cell = existing ?? TabCell(frame:.zero)
        cell.clearHover(); cell.identifier = identifier; cell.canClose = true
        cell.active = row == 0; cell.ink = .white; cell.titleLabel.stringValue = "Onglet \(row) · Café"
        return cell
    }
}
@main enum HoverTests {
    static func main() {
        _ = NSApplication.shared
        let window = PointerWindow(contentRect:NSRect(x:0,y:0,width:260,height:330),styleMask:[.borderless],backing:.buffered,defer:false)
        let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:260,height:300))
        window.contentView = NSView(frame:NSRect(x:0,y:0,width:260,height:330)); window.contentView!.addSubview(scroll)
        let document = Canvas(frame:NSRect(x:0,y:0,width:260,height:38*80))
        scroll.documentView = document
        let cells = (0..<80).map { i -> TabCell in
            let cell = TabCell(frame:NSRect(x:5,y:CGFloat(i)*38,width:240,height:36))
            cell.canClose = true; cell.ink = .white; cell.acceptsPointerAt = { _ in true }; document.addSubview(cell)
            return cell
        }
        window.pointer = scroll.contentView.convert(NSPoint(x:100,y:150),to:nil)
        let point = window.pointer
        let event = NSEvent.enterExitEvent(with:.mouseEntered,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,trackingNumber:0,userData:nil)!
        for step in (0..<120).map({ $0*21 }) + (0..<120).reversed().map({ $0*21 }) {
            scroll.contentView.scroll(to:NSPoint(x:0,y:step)); scroll.reflectScrolledClipView(scroll.contentView)
            cells.forEach { $0.updateTrackingAreas(); $0.mouseEntered(with:event) }
            let expected = cells.filter { $0.bounds.contains($0.convert(point,from:nil)) }
            let highlighted = cells.filter { !$0.closeButton.isHidden }
            precondition(expected.count <= 1 && expected == highlighted,"only the clipped row beneath the stationary pointer may be hovered")
        }
        cells[0].active = true
        cells.forEach { $0.acceptsPointerAt = { _ in false }; $0.mouseEntered(with:event) }
        precondition(cells.allSatisfy { $0.closeButton.isHidden },"update card and footer veto hover")
        precondition(cells[0].active && cells[0].layer!.backgroundColor!.alpha > 0,"hover cannot clear the real active tab")
        cells.forEach { $0.acceptsPointerAt = { _ in true } }
        let target = cells.first { $0.bounds.contains($0.convert(point,from:nil)) }!
        target.updateHover(at:point); precondition(!target.closeButton.isHidden)
        target.layoutSubtreeIfNeeded()
        func closeBackgroundAlpha() -> CGFloat {
            let button = target.closeButton
            let image = NSImage(size:button.bounds.size,flipped:button.isFlipped) { _ in button.draw(button.bounds); return true }
            let pixels = NSBitmapImageRep(cgImage:image.cgImage(forProposedRect:nil,context:nil,hints:nil)!)
            return pixels.colorAt(x:3,y:pixels.pixelsHigh/2)!.alphaComponent
        }
        let titlePoint = target.convert(NSPoint(x:50,y:18),to:nil)
        let closePoint = target.closeButton.convert(NSPoint(x:11,y:11),to:nil)
        window.pointer = titlePoint; target.updateHover(at:titlePoint)
        precondition(closeBackgroundAlpha() < 0.01,"hovering the title must not paint the close-button background, even when visibleRect extends outside its bounds")
        window.pointer = closePoint; target.updateHover(at:closePoint)
        precondition(closeBackgroundAlpha() > 0.1,"the close-button background appears only over the button")
        window.pointer = titlePoint; target.updateHover(at:titlePoint)
        precondition(closeBackgroundAlpha() < 0.01,"leaving the close button clears its background immediately")
        window.pointer = point
        target.clearHover(); target.canClose = false; target.canClose = true
        precondition(target.closeButton.isHidden,"recycled row starts without stale hover")
        target.updateHover(at:point); target.removeFromSuperview()
        precondition(target.closeButton.isHidden,"detached row loses hover")
        window.pointer = NSPoint(x:-1000,y:-1000)
        cells.forEach { $0.mouseEntered(with:event) }
        precondition(cells.allSatisfy { $0.closeButton.isHidden },"late enters use current pointer, not obsolete event position")
        print("PASS: 240 bidirectional scroll positions over 80 native rows, queued events, clipped rows, reuse, detachment, overlay and real selection")
        let table = NSTableView(), rows = Rows()
        table.addTableColumn(NSTableColumn(identifier:.init("tabs"))); table.headerView = nil
        table.rowHeight = 36; table.intercellSpacing = NSSize(width:0,height:2)
        table.delegate = rows; table.dataSource = rows
        scroll.documentView = table; table.reloadData(); table.layoutSubtreeIfNeeded()
        window.pointer = point
        for row in Array(stride(from:0,to:80,by:4)) + Array(stride(from:79,through:0,by:-4)) {
            table.scrollRowToVisible(row); table.layoutSubtreeIfNeeded()
            RunLoop.main.run(until:Date(timeIntervalSinceNow:0.002))
            var current:[TabCell] = []
            table.enumerateAvailableRowViews { view,_ in
                for case let cell as TabCell in view.subviews {
                    cell.updateHover(at:point); cell.updateTrackingAreas(); cell.mouseEntered(with:event)
                    current.append(cell)
                }
            }
            let expected = current.filter { $0.bounds.contains($0.convert(point,from:nil)) }
            precondition(expected.count <= 1 && current.filter { !$0.closeButton.isHidden } == expected)
            precondition(table.selectedRow == -1,"scroll and hover never select or navigate a tab")
        }
        precondition(rows.reused > 0,"exercise actual NSTableView recycling")
        print("PASS: actual NSTableView scroll/recycling (\(rows.reused) reused rows), without changing selection")
    }
}
