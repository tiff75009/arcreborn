// SPDX-License-Identifier: MPL-2.0
import AppKit

private final class TestPageDrag: NSObject, NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    let draggingSourceOperationMask: NSDragOperation = .move
    var draggingLocation = NSPoint.zero
    let draggedImageLocation = NSPoint.zero
    let draggedImage: NSImage? = nil
    let draggingPasteboard = NSPasteboard.withUniqueName()
    let draggingSource: Any? = nil
    let draggingSequenceNumber = 1
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    let springLoadingHighlight: NSSpringLoadingHighlight = .none
    let item = NSDraggingItem(pasteboardWriter:NSPasteboardItem())
    init(window: NSWindow) { draggingDestinationWindow = window }
    func resetSpringLoading() {}
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?,
                                classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        block(item, 0, &stop)
    }
}

@main struct PageSplitDropTests {
    static func main() {
        _ = NSApplication.shared
        let rect = NSRect(x:0,y:0,width:900,height:500)
        let window = NSWindow(contentRect:rect,styleMask:.borderless,backing:.buffered,defer:false)
        let root = NSView(frame:rect), page = NSView(frame:rect), shadow = NSView(frame:rect)
        let target = PageSplitDropView(frame:rect)
        window.contentView = root
        for view in [shadow,page,target] { view.wantsLayer = true; root.addSubview(view) }
        let info = TestPageDrag(window:window)
        var commits: [PageSplitDropView.Side] = []
        var eligible = true
        target.accepts = { _,_ in eligible }
        target.commit = { _,side in commits.append(side); return true }
        func begin(_ total: Int = 2) {
            target.begin(.init(source:"incoming",target:"visible",incomingCount:1,totalCount:total),
                         page:page,shadow:shadow,title:"Carnet de voyage",icon:nil,dark:true)
        }
        func point(_ x: CGFloat) { info.draggingLocation = target.convert(.init(x:x,y:250), to:nil) }
        for edge in [PageSplitDropView.Side.left, .right] {
            begin(); point(edge == .left ? 60 : 840)
            precondition(target.draggingEntered(info) == .move && target.side == edge)
            precondition(info.item.draggingFrame.size == NSSize(width:184,height:270))
            precondition(page.bounds == rect && page.layer?.mask?.bounds.width == 446)
            point(450)
            precondition(target.draggingUpdated(info).isEmpty && !target.prepareForDragOperation(info))
            precondition(!target.performDragOperation(info) && page.layer?.mask?.bounds.width == 900)
            point(edge == .left ? 840 : 60)
            precondition(target.draggingUpdated(info) == .move)
            point(edge == .left ? 60 : 840)
            precondition(target.prepareForDragOperation(info) && target.performDragOperation(info))
            precondition(target.isHidden && page.layer?.mask == nil && shadow.layer?.opacity == 1)
        }
        precondition(commits == [.left,.right])
        begin(3); target.coveredLeadingWidth = 140
        point(45); precondition(target.draggingEntered(info).isEmpty)
        point(190); precondition(target.draggingUpdated(info) == .move)
        target.draggingExited(info)
        precondition(target.side == nil && !target.isHidden)
        eligible = false; point(890)
        precondition(!target.performDragOperation(info))
        target.finish(animated:false)
        precondition(page.frame == rect && page.layer?.mask == nil && commits.count == 2)
        print("PASS: page-edge split, both sides, center cancellation, reversal, covered sidebar, drag card, original page geometry and stale drops")
    }
}
