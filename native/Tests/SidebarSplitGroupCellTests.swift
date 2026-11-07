// SPDX-License-Identifier: MPL-2.0
import AppKit

private final class GroupWindow: NSWindow {
    var pointer = NSPoint(x:-100,y:-100)
    override var mouseLocationOutsideOfEventStream:NSPoint { pointer }
}
@main struct SidebarSplitGroupCellTests {
    static func main() throws {
        _ = NSApplication.shared
        let window = GroupWindow(contentRect:NSRect(x:90,y:90,width:260,height:60),styleMask:.borderless,backing:.buffered,defer:false)
        let root = NSView(frame:NSRect(x:0,y:0,width:260,height:60))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(srgbRed:0.38,green:0.37,blue:0.47,alpha:1).cgColor
        window.contentView = root
        func symbol(_ name:String, _ color:NSColor) -> NSImage? {
            NSImage(systemSymbolName:name,accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[color]))
        }
        for count in 2...4 {
            var state = BrowserSession.fresh()
            let ids = (0..<count).map { state.createTab(url:"https://example.com/\($0)") }
            for id in ids.dropFirst() { precondition(state.mergeSplit(id,onto:ids[0])) }
            let other = state.createTab(url:"https://example.com/other")
            let chips = ids.enumerated().map { i,id in
                SplitTabChip(id:id,title:["AppKeeper","Perplexity","Carnet","Lecture"][i],
                             image:i == 0 ? symbol("app.badge.fill",.systemRed) : symbol("sparkles.rectangle.stack.fill",.black))
            }
            let group = SplitGroupCell(chips:chips,ink:.white,title:nil,icon:nil,focusedID:other)
            root.addSubview(group)
            group.frame = NSRect(x:5,y:5,width:212,height:36)
            var allowed = true
            group.acceptsPointerAt = { _ in allowed }
            for chip in chips { chip.archive.invoke = { state.closeTab(id:chip.id) } }
            group.archive.invoke = { ids.forEach { state.closeTab(id:$0) } }
            func pointer(_ p:NSPoint?) {
                window.pointer = p ?? NSPoint(x:-100,y:-100)
                group.updateHover(at:p)
                root.layoutSubtreeIfNeeded()
            }
            func capture(_ name:String) throws {
                guard count == 2, let dir = ProcessInfo.processInfo.environment["ARC_TIP_PREVIEWS"] else { return }
                let rep = root.bitmapImageRepForCachingDisplay(in:root.bounds)!
                root.cacheDisplay(in:root.bounds,to:rep)
                try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:dir).appendingPathComponent("groupe-"+name+".png"))
            }
            pointer(nil)
            precondition(group.layer!.backgroundColor!.alpha == 0 && chips.allSatisfy { $0.layer!.backgroundColor!.alpha == 0 })
            let dividers = group.layer!.sublayers!.filter { $0.bounds.height == 15 && $0.bounds.width <= 1 }
            precondition(dividers.count == count-1 && dividers.allSatisfy { !$0.isHidden })
            precondition(group.archive.isHidden && chips.allSatisfy { $0.archive.isHidden })
            try capture("repos")
            let onTitle = group.convert(NSPoint(x:31,y:18),to:nil)
            pointer(onTitle)
            precondition(!group.archive.isHidden && chips.allSatisfy { $0.archive.isHidden })
            let groupPoint = group.archive.convert(NSPoint(x:11,y:11),to:root)
            precondition(group.hitTest(groupPoint) === group.archive)
            try capture("survol")
            let inactive = state
            group.archive.performClick(nil)
            precondition(Set(state.closedTabs.map(\.id)) == Set(ids) && state.spaces[0].selectedTabID == other)
            state = inactive
            state.selectTab(id:ids[0])
            group.setFocus(ids[0]); pointer(onTitle)
            precondition(group.archive.isHidden && chips.allSatisfy { !$0.archive.isHidden } && dividers.allSatisfy(\.isHidden))
            for chip in chips {
                let p = chip.archive.convert(NSPoint(x:11,y:11),to:root)
                precondition(group.hitTest(p) === chip.archive)
                precondition(chip.label.isHidden || chip.label.frame.maxX <= chip.archive.frame.minX)
                precondition(chip.icon.isHidden || chip.icon.frame.maxX <= chip.archive.frame.minX)
            }
            try capture("actif")
            let focused = state
            chips.last!.archive.performClick(nil)
            precondition(state.closedTabs.map(\.id) == [ids.last!] && state.spaces[0].selectedTabID == ids.first)
            state = focused
            chips[0].archive.performClick(nil)
            precondition(state.closedTabs.map(\.id) == [ids[0]] && state.spaces[0].selectedTabID == ids[1])
            allowed = false; pointer(onTitle)
            precondition(group.archive.isHidden && chips.allSatisfy { $0.archive.isHidden })
            group.removeFromSuperview()
        }
        print("PASS: rendered 2–4 pane groups, resting separators, group and per-pane archive clicks, light hit targets, focus and overlay dismissal")
    }
}
