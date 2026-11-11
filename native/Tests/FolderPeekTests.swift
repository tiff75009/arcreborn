// SPDX-License-Identifier: MPL-2.0
import AppKit

@main enum FolderPeekTests {
    static func main() {
        let app = NSApplication.shared
        var session = BrowserSession.fresh()
        let space = session.activeSpaceID
        let folder = NativeFolder(id:"parent",spaceID:space,name:"Parent",collapsed:true)
        let child = NativeFolder(id:"child",spaceID:space,name:"Nested",collapsed:true,parentID:folder.id)
        let other = NativeFolder(id:"other",spaceID:space,name:"Other",collapsed:true)
        session.folders = [folder, child, other]
        let tab = session.createTab(url:"https://example.test/")
        _ = session.moveSidebarItem(.tab(tab),spaceID:space,to:.init(parentID:child.id,before:nil))
        var collapse = SidebarCollapseState()
        collapse.toggle(.folder(child.id),in:&session)
        var opened: [(String,String)] = []
        let peek = FolderPeek(session:session,folder:folder,artwork:{ _ in nil }) { opened.append(($0,$1)) }!
        let parent = NSWindow(contentRect:NSRect(x:100,y:100,width:650,height:420),styleMask:[.titled],backing:.buffered,defer:false)
        parent.orderFront(nil)
        peek.show(parent:parent,anchor:NSRect(x:110,y:280,width:110,height:30),available:parent.frame)
        defer { peek.close(animated:false); parent.orderOut(nil) }
        let panel = parent.childWindows!.first!
        func table(in view:NSView) -> NSTableView? {
            if let list = view as? NSTableView { return list }
            return view.subviews.lazy.compactMap { table(in:$0) }.first
        }
        let list = table(in:panel.contentView!)!
        func event(_ type:NSEvent.EventType, at point:NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with:type,location:parent.convertPoint(fromScreen:point),modifierFlags:[],
                               timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:parent.windowNumber,
                               context:nil,eventNumber:0,clickCount:1,pressure:1)!
        }
        func pointOnRow() -> NSPoint {
            let row = list.rect(ofRow:0)
            return panel.convertPoint(toScreen:list.convert(NSPoint(x:row.midX,y:row.midY),to:nil))
        }
        func clickRow() {
            let point = pointOnRow()
            app.sendEvent(event(.leftMouseDown,at:point))
            app.sendEvent(event(.leftMouseUp,at:point))
        }
        let point = pointOnRow()
        let hit = panel.contentView!.hitTest(panel.convertPoint(fromScreen:point))
        precondition(hit === list && list.acceptsFirstMouse(for:nil),"The first click on row content must reach the table")
        clickRow() // Enter the nested folder without selecting a browser tab.
        let nestedPoint = pointOnRow()
        app.sendEvent(event(.leftMouseDown,at:nestedPoint))
        app.sendEvent(event(.leftMouseUp,at:NSPoint(x:parent.frame.minX,y:parent.frame.minY)))
        precondition(opened.isEmpty,"Releasing outside the row must cancel the click")
        clickRow()
        precondition(opened.count == 1 && opened[0].0 == tab && opened[0].1 == child.id,
                     "A click addressed to the parent must open the hit once, with its actual folder")
        collapse.expandPath(to:opened[0].1,spaceID:space,in:&session)
        precondition(session.folders.filter { !$0.collapsed }.map(\.id) == [folder.id,child.id])
        precondition(collapse.retainedTabs.isEmpty && session.sidebarTree(spaceID:space).contains { $0.item == .tab(tab) && $0.depth == 2 })
        print("PASS: folder preview first click, cancelled release and nested reveal")
    }
}
