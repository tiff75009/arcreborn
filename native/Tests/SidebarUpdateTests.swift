// SPDX-License-Identifier: MPL-2.0
import AppKit

private final class UpdateTestCanvas:NSView { override var isFlipped:Bool { true } }

@main enum SidebarUpdateTests {
    static func main() {
        _ = NSApplication.shared
        let session = SidebarUpdateSession()
        var downloads = 0, installs = 0, retries = 0
        session.offer(ready:false) { downloads += 1; session.downloading(0.1) }
        session.activate(); session.activate()
        precondition(downloads == 1 && session.phase == .downloading && !session.actionable)
        session.preparing(0.5)
        session.ready { installs += 1; session.installing() }
        precondition(installs == 1 && session.phase == .installing,"one explicit click completes the Sparkle flow")
        session.awaitingTermination { retries += 1 }
        session.activate(); session.activate()
        precondition(retries == 1 && !session.actionable,"beforeunload retries are explicit and single use")
        session.finish(); session.ready { installs += 1 }
        precondition(installs == 1 && session.phase == .ready,"a finished session cannot authorize a subsequent update")
        session.finish(); session.activate(); precondition(installs == 1)
        session.downloading(.infinity); precondition(session.progress == nil)
        session.downloading(-1); precondition(session.progress == 0)
        session.downloading(2); precondition(session.progress == 1)

        let host = NSView(frame:NSRect(x:0,y:0,width:300,height:500))
        let card = SidebarUpdateCard(frame:NSRect(x:8,y:20,width:229,height:94))
        host.addSubview(card)
        func update(_ phase:SidebarUpdateSession.Phase = .ready, language:String = "fr") {
            card.update(phase:phase,progress:nil,actionable:true,automatic:false,allowsAutomatic:true,accent:.systemIndigo,ink:.white,language:language)
            card.layoutSubtreeIfNeeded(); card.layout()
        }
        func labels(_ view:NSView) -> [String] { view.subviews.flatMap { ($0 as? NSTextField).map { [$0.stringValue] } ?? labels($0) } }
        func buttons(_ view:NSView) -> [NSButton] { view.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? buttons($0) } }
        func point(_ y:CGFloat) -> NSPoint { host.convert(NSPoint(x:100,y:y),from:card) }
        update()
        precondition(card.hitTest(point(10)) == nil,"collapsed empty area leaves tabs reachable")
        precondition(card.hitTest(point(85)) != nil,"pill owns input")
        card.setExpanded(true,animated:false)
        precondition(card.hitTest(point(10)) != nil && card.occupiedHeight == 94,"expanded card intercepts all covered rows")
        precondition(labels(card).contains("Nouvelle version disponible"))
        var toggled = false, clicks = 0
        card.toggleAutomatic = { toggled = $0 }; card.activate = { clicks += 1 }
        buttons(card).first(where: { $0.title == "Mises à jour automatiques" })!.performClick(nil)
        buttons(card).first(where: { $0.title == "Redémarrer et mettre à jour" })!.performClick(nil)
        precondition(toggled && clicks == 1)
        for _ in 0..<40 { card.setExpanded(false); card.setExpanded(true) }
        RunLoop.main.run(until:Date(timeIntervalSinceNow:0.5))
        precondition(card.isExpanded && card.hitTest(point(10)) != nil)
        card.setSuppressed(true); precondition(card.hitTest(point(85)) == nil)
        card.setSuppressed(false); precondition(!card.isExpanded && card.hitTest(point(85)) != nil)
        update(language:"en"); precondition(buttons(card).contains { $0.title == "Restart and Update" })
        for width:CGFloat in [208,229,384] {
            card.frame.size.width = width; card.setExpanded(true,animated:false); card.layout()
            let surface = card.subviews[0]
            precondition(buttons(card).allSatisfy { surface.bounds.contains($0.frame) },"controls remain inside narrow/wide sidebars")
        }
        update(.hidden); precondition(card.hitTest(point(85)) == nil && !card.isExpanded)
        // Exercise the complete hit-test hierarchy, not just the card in
        // isolation. The transparent margins used to reach hidden tab rows.
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:300,height:500),styleMask:[.borderless],backing:.buffered,defer:false)
        let canvas = UpdateTestCanvas(frame:NSRect(x:0,y:0,width:300,height:500))
        window.contentView = canvas
        let items = SidebarPeekContent(frame:canvas.bounds)
        let tab = NSButton(title:"Underlying tab",target:nil,action:nil); tab.frame = items.bounds
        items.addSubview(tab); canvas.addSubview(items)
        let footer = SidebarFooterBarrier(frame:NSRect(x:0,y:417,width:300,height:83))
        canvas.addSubview(footer)
        card.removeFromSuperview(); card.frame = NSRect(x:8,y:356,width:284,height:94)
        canvas.addSubview(card); update(); card.setExpanded(false,animated:false)
        items.blocksInputAt = { point in footer.frame.contains(canvas.convert(point,from:nil)) || card.contains(point) }
        func target(_ x:CGFloat,_ y:CGFloat) -> NSView? {
            canvas.hitTest(canvas.superview!.convert(NSPoint(x:x,y:y),from:canvas))
        }
        for x in stride(from:CGFloat(0),to:300,by:4) {
            for y in stride(from:CGFloat(417),to:500,by:3) {
                precondition(target(x,y) !== tab,"entire footer, including pill margins, shields the tab list")
            }
        }
        precondition(target(100,360) === tab,"area above a collapsed pill remains scrollable")
        card.setExpanded(true,animated:false)
        for x in stride(from:CGFloat(9),to:291,by:4) {
            for y in stride(from:CGFloat(357),to:449,by:3) {
                precondition(target(x,y) !== tab,"expanded card cannot click through any descendant of the tab list")
            }
        }
        let separator = SidebarListSeparator(frame:NSRect(x:0,y:417,width:300,height:0.5))
        canvas.addSubview(separator)
        precondition(target(1,417) === footer,"separator keeps footer input protection")
        print("PASS: update replies, reentrancy, no repeated installs, restart cancellation, state reset, FR/EN, hit shielding, rapid animation reversals and narrow sidebars")
    }
}
