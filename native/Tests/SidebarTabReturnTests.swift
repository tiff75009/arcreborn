// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

private final class ReturnCanvas:NSView { override var isFlipped:Bool { true } }

@main enum SidebarTabReturnTests {
    static func main() {
        _ = NSApplication.shared
        let document = NSRect(x:0,y:0,width:245,height:3000)
        let visible = NSRect(x:0,y:500,width:245,height:300)
        let above = NSRect(x:0,y:200,width:245,height:36), below = NSRect(x:0,y:1400,width:245,height:60)
        precondition(SidebarTabReturnGeometry.edge(of:above,visible:visible) == .above)
        precondition(SidebarTabReturnGeometry.edge(of:below,visible:visible) == .below)
        for y:CGFloat in [480,500,680,790] {
            precondition(SidebarTabReturnGeometry.edge(of:NSRect(x:0,y:y,width:245,height:36),visible:visible) == nil,"partly or fully visible active rows need no arrow")
        }
        precondition(SidebarTabReturnGeometry.destination(for:above,edge:.above,visible:visible,document:document) == above.minY)
        precondition(SidebarTabReturnGeometry.destination(for:below,edge:.below,visible:visible,document:document) == below.maxY-visible.height)
        precondition(SidebarTabReturnGeometry.destination(for:above,edge:.below,visible:visible,document:document) == 0)
        let last = NSRect(x:0,y:2964,width:245,height:36)
        precondition(SidebarTabReturnGeometry.destination(for:last,edge:.above,visible:visible,document:document) == 2700)

        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:245,height:400),styleMask:[.borderless],backing:.buffered,defer:false)
        let root = ReturnCanvas(frame:NSRect(x:0,y:0,width:245,height:400)); window.contentView = root
        let underlying = NSButton(title:"Tab underneath",target:nil,action:nil); underlying.frame = root.bounds; root.addSubview(underlying)
        var clicks = 0
        let up = SidebarTabReturnButton(edge:.above), down = SidebarTabReturnButton(edge:.below)
        up.frame.origin = NSPoint(x:108,y:6); down.frame.origin = NSPoint(x:108,y:350)
        root.addSubview(up); root.addSubview(down); up.invoke = { clicks += 1 }
        func advance(_ time:TimeInterval) { RunLoop.main.run(until:Date(timeIntervalSinceNow:time)) }
        func hit(_ button:NSView) -> NSView? {
            let p = root.superview!.convert(NSPoint(x:button.bounds.midX,y:button.bounds.midY),from:button)
            return root.hitTest(p)
        }
        up.setShown(true); down.setShown(true)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            for (button,sign) in [(up,CGFloat(-1)),(down,CGFloat(1))] {
                let motion = button.layer!.animation(forKey:"return-motion") as! CAKeyframeAnimation
                let transforms = motion.values!.map { ($0 as! NSValue).caTransform3DValue }
                let first = transforms[0]
                let dy = button.bounds.midY*first.m22+first.m42-button.bounds.midY
                precondition(dy*sign > 9 && first.m11 < 0.7 && transforms[1].m11 > 1 && transforms[1].m11 < 1.1,"directional entrance grows into a small rebound")
                let start = motion.beginTime
                button.setShown(true)
                precondition(button.layer!.animation(forKey:"return-motion")?.beginTime == start,"scroll updates do not replay the entrance")
            }
        }
        precondition(hit(up) === up && hit(down) === down,"floating arrows own clicks above tab content")
        up.performClick(nil); precondition(clicks == 1)
        up.setShown(false)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { precondition(hit(up) === up,"outgoing arrow still shields underlying rows") }
        up.performClick(nil); precondition(clicks == 1,"outgoing arrow cannot trigger another jump")
        advance(0.18); precondition(up.isHidden && hit(up) === underlying)
        for _ in 0..<40 { up.setShown(true); up.setShown(false); up.setShown(true) }
        advance(0.45); precondition(up.shown && !up.isHidden)
        up.setShown(false,animated:false); down.setShown(false,animated:false)
        precondition(up.isHidden && down.isHidden && up.layer!.animationKeys() == nil)

        let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:245,height:300))
        scroll.documentView = ReturnCanvas(frame:document)
        let motion = SidebarTabReturnMotion()
        var completions = 0
        scroll.contentView.scroll(to:NSPoint(x:0,y:500))
        motion.scroll(scroll,to:above.minY) { completions += 1 }
        advance(0.5)
        precondition(abs(scroll.contentView.bounds.minY-above.minY)<0.1 && completions == 1 && !motion.isRunning,"upper return aligns the active row at the top")
        let bottom = below.maxY-scroll.contentView.bounds.height
        motion.scroll(scroll,to:bottom) { completions += 1 }
        advance(0.5)
        precondition(abs(scroll.contentView.bounds.maxY-below.maxY)<0.1 && completions == 2,"lower return aligns the active row at the bottom")
        motion.scroll(scroll,to:0) { completions += 1 }; advance(0.04); motion.cancel()
        let stopped = scroll.contentView.bounds.origin
        advance(0.45); precondition(scroll.contentView.bounds.origin == stopped && completions == 3,"manual scrolling can stop the jump without later drift")
        motion.scroll(scroll,to:600,animated:false) { completions += 1 }
        precondition(scroll.contentView.bounds.minY == 600 && !motion.isRunning && completions == 4)
        print("PASS: offscreen geometry, top/bottom alignment, directional bounce, reduced motion, input shielding, reversal and scroll interruption")
    }
}
