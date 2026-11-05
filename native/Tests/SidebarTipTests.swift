// SPDX-License-Identifier: MPL-2.0
import AppKit

private final class TipTestWindow: NSWindow { override var isKeyWindow: Bool { true } }
@main struct SidebarTipTests {
    static func main() throws {
        _ = NSApplication.shared
        let parent = TipTestWindow(contentRect:NSRect(x:120,y:180,width:220,height:130),styleMask:.borderless,backing:.buffered,defer:false)
        parent.orderBack(nil)
        let tips = SidebarHoverTip(parent:parent)
        let anchor = NSRect(x:216,y:202,width:18,height:32)
        func wait(_ duration: Double) { RunLoop.main.run(until:Date(timeIntervalSinceNow:duration)) }
        func panel() -> NSWindow? { parent.childWindows?.first(where:{ $0.isVisible }) }
        func labels(_ v:NSView) -> [String] { (v as? NSTextField).map { [$0.stringValue] } ?? v.subviews.flatMap(labels) }
        tips.track(.space("a")) { .init(content:.space(name:"Archives",keys:[]),anchor:anchor) }
        wait(0.22)
        tips.track(.space("b")) { .init(content:.space(name:"Études",keys:["⌃","4"]),anchor:anchor) }
        wait(0.78)
        precondition(panel() == nil,"sweeping between spaces must restart dwell")
        wait(0.34)
        let space = panel()!
        precondition(Set(labels(space.contentView!)) == Set(["Études","⌃","4"]))
        precondition(space.frame.minY > anchor.maxY && abs(space.frame.midX-anchor.midX)<1)
        precondition(!space.canBecomeKey && space.ignoresMouseEvents)
        func snapshot(_ view:NSView,_ file:String) throws {
            guard let dir = ProcessInfo.processInfo.environment["ARC_TIP_PREVIEWS"] else { return }
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
            let im = view.bitmapImageRepForCachingDisplay(in:view.bounds)!
            view.cacheDisplay(in:view.bounds,to:im)
            try im.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:dir).appendingPathComponent(file))
        }
        try snapshot(space.contentView!,"espace.png")
        var active = false
        tips.track(.tab("c")) {
            .init(content:.tab(title:"Étude des couleurs et de la lumière",hint:L10n.text(active ? "tabRenameActiveHint" : "tabRenameInactiveHint",language:"fr")),anchor:anchor)
        }
        precondition(panel() == nil,"leaving a space removes its bubble immediately")
        wait(0.80)
        precondition(labels(panel()!.contentView!).last == "Double-cliquez pour renommer")
        active = true; tips.refreshIfVisible()
        precondition(labels(panel()!.contentView!) == ["Étude des couleurs et de la lumière","Cliquez pour renommer"])
        try snapshot(panel()!.contentView!,"onglet.png")
        tips.dismiss(); precondition(panel() == nil)
        tips.track(.space("stale")) { nil }; wait(1.02); precondition(panel() == nil,"removed or obscured targets must never show")
        parent.orderOut(nil)
        print("PASS: tooltip dwell, retargeting, anchoring, shortcut badges, localized rename hints and focus")
    }
}
