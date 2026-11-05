import AppKit

@main struct MenuCommandsHarness {
    static func main() throws {
        guard let directory = ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"],
              directory.contains("menus-check"), let address = ProcessInfo.processInfo.environment["BROWSER_MENU_TEST_URL"], address.hasPrefix("http://127.0.0.1:") else { fatalError("Isolated menu test only") }
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { print("FAIL \(name)"); fflush(stdout); exit(1) }
            checks += 1; print("PASS \(name)"); fflush(stdout)
        }
        let commands = BrowserCommands.all
        check(Set(commands.map(\.id)).count == commands.count,"stable unique command IDs")
        let defaults = BrowserCommands.resolved([:])
        check(commands.filter { $0.available && !$0.binding.key.isEmpty }.allSatisfy { defaults[$0.id] == $0.binding },"all defaults usable, no collisions")
        check(commands.filter { !$0.available }.allSatisfy { defaults[$0.id] == nil },"unavailable actions have no active shortcut")
        let custom = SplitKeyBinding(key:"r",modifiers:NSEvent.ModifierFlags([.command,.shift]).rawValue)
        let resolved = BrowserCommands.resolved(["split.add":custom,"newTab":.init(key:"",modifiers:0)])
        check(resolved["split.add"] == custom && resolved["forceReload"]?.key == "","existing custom Split shortcut beats new defaults")
        check(resolved["newTab"]?.key == "","explicitly removing a shortcut persists")
        check(BrowserCommands.resolved(["newTab":BrowserCommands.reserved[0]])["newTab"]?.key == "","editing shortcuts cannot be stolen")
        check(!BrowserCommands.valid(.init(key:"a",modifiers:0)),"bare letters rejected")
        var session = BrowserSession.fresh(language:"fr"); session.onboardingComplete = true
        let old = try JSONEncoder().encode(session)
        let legacy = try JSONDecoder().decode(BrowserSession.self,from:old)
        check(legacy.commandShortcuts == nil,"old session decodes without migration")
        let first = session.createTab(url:address)
        _ = session.createTab(url:address+"?second")
        _ = session.renameTab(id:first,name:"Première page")
        session.selectTab(id:first)
        session.splitShortcuts = ["add":custom]
        session.commandShortcuts = ["captureFull":.init(key:"9",modifiers:NSEvent.ModifierFlags([.command,.shift]).rawValue)]
        let restored = try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(session))
        check(restored == session && restored.validated(),"session and shortcuts round-trip without data loss")
        check(isAllowedBrowserURL("chrome://history/") && !isAllowedBrowserURL("chrome://history.evil/"),"history route is narrowly allowed")
        let store = SessionStore(directory:URL(fileURLWithPath:directory))
        let app = BrowserEngine.createApplication(); app.setActivationPolicy(.regular)
        let delegate = NativeAppDelegate(store:store,initial:session); app.delegate = delegate
        UserDefaults.standard.set("fr",forKey:"BrowserLanguage")
        let started = Date(); var done = false
        let timer = Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { timer in
            MainActor.assumeIsolated {
            if Date().timeIntervalSince(started) > 25 { print("FAIL menu runtime timeout"); fflush(stdout); exit(1) }
            guard !done, let controller = delegate.controller, Date().timeIntervalSince(started) > 2,
                  controller.browserCommandState("zoomIn").enabled else { return }
            done = true; timer.invalidate()
            func find(_ id: String, _ menu: NSMenu? = NSApp.mainMenu) -> NSMenuItem? {
                for item in menu?.items ?? [] {
                    if item.representedObject as? String == id { return item }
                    if let result = find(id,item.submenu), item.submenu != nil { return result }
                }
                return nil
            }
            let titles = NSApp.mainMenu?.items.map(\.title) ?? []
            check(["Arc Reborn","Fichier","Édition","Présentation","Espaces","Onglets","Archives","Extensions","Fenêtre","Aide"].allSatisfy(titles.contains),"complete native menu structure")
            check(NSApp.helpMenu != nil && NSApp.windowsMenu != nil && NSApp.servicesMenu != nil,"macOS Help, Window and Services registered")
            check(find("newEasel")?.action == nil && find("newWindow")?.action != nil,"available windows and unavailable Easels distinguished")
            check(find("split.add")?.keyEquivalent == "r" && find("forceReload")?.keyEquivalent == "","menu honors migrated shortcuts")
            check(find("captureFull")?.keyEquivalent == "9","literal custom shortcut preserved on AZERTY")
            check(BrowserCommands.displayedBindings(controller.commandOverrides)["capture"]?.key == find("capture")?.keyEquivalent,"preferences match localized default shortcuts")
            check(!controller.browserCommandState("split.close").enabled && !controller.browserCommandState("back").enabled,"contextual actions disabled correctly")
            // Exercise the real row, field editor and window event routing. In
            // 0.7.1 a click on the title's inset could bounce from the text field
            // back into the table until the main thread overflowed its stack.
            let window = controller.window
            func click(_ point:NSPoint, _ count:Int, forwardedTo table:NSTableView? = nil) {
                func event(_ type:NSEvent.EventType)->NSEvent {
                    NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                                       windowNumber:window.windowNumber,context:nil,eventNumber:count,clickCount:count,pressure:0)!
                }
                // Both the table and the field editor may track until mouse-up.
                NSApp.postEvent(event(.leftMouseUp),atStart:true)
                if let table { table.mouseDown(with:event(.leftMouseDown)) }
                else { window.sendEvent(event(.leftMouseDown)) }
                while let up = NSApp.nextEvent(matching:.leftMouseUp,until:.distantPast,inMode:.default,dequeue:true) { window.sendEvent(up) }
            }
            func firstTitle(in view:NSView) -> NSTextField? {
                if let label = view as? NSTextField, label.stringValue == "Première page" { return label }
                return view.subviews.lazy.compactMap { firstTitle(in:$0) }.first
            }
            controller.performBrowserCommand("tabNext")
            for count in 1...2 {
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.main.run(until:Date(timeIntervalSinceNow:0.04))
                guard let title = firstTitle(in:window.contentView!) else { check(false,"first tab title is visible"); return }
                click(title.convert(NSPoint(x:title.bounds.midX,y:title.bounds.midY),to:nil),count)
                RunLoop.main.run(until:Date(timeIntervalSinceNow:0.04))
                if count == 1 { check(controller.selectedWindowTabID == first && title.currentEditor() == nil,"first click activates an inactive tab without renaming") }
            }
            guard let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
                  let field = editor.delegate as? NSTextField else { check(false,"click on active title starts editing"); return }
            var ancestor: NSView? = field.superview
            while ancestor != nil && !(ancestor is NSTableView) { ancestor = ancestor?.superview }
            guard let table = ancestor as? NSTableView else { fatalError("missing sidebar table") }
            func clickTitle(_ x:CGFloat, _ count:Int, atInset:Bool = false) {
                let point = field.convert(NSPoint(x:x,y:atInset ? 0.2 : field.bounds.midY),to:nil)
                click(point,count,forwardedTo:atInset ? table : nil)
            }
            for count in 1...50 {
                clickTitle(count.isMultiple(of:2) ? 0.5 : field.bounds.midX, (count-1)%5+1)
                clickTitle(0.5, (count-1)%5+1, atInset:true)
            }
            check(window.firstResponder === editor && controller.windowSession.tabs.count == 2,"repeated title clicks keep the same editor and tabs")
            clickTitle(10,1)
            check(editor.selectedRange().length == 0,"clicking the text still places the caret")
            clickTitle(10,2)
            check(editor.selectedRange().length > 0,"double-click still selects text")
            editor.selectAll(nil); editor.insertText("Onglet vérifié",replacementRange:editor.selectedRange()); editor.doCommand(by:#selector(NSResponder.insertNewline(_:)))
            check(controller.windowSession.tabs.first(where:{ $0.id == first })?.customTitle == "Onglet vérifié","renaming still commits after rapid clicks")
            let bridge = BrowserEngine()
            controller.performBrowserCommand("zoomIn")
            check(abs(bridge.zoomLevel(controller.rendererID(for:first))-1)<0.01,"zoom command reaches Chromium")
            controller.performBrowserCommand("zoomReset")
            check(abs(bridge.zoomLevel(controller.rendererID(for:first)))<0.01 && !controller.browserCommandState("zoomReset").enabled,"actual-size command and menu state")
            controller.performBrowserCommand("developer")
            check(controller.browserCommandState("developer").checked,"developer menu follows current tab")
            controller.performBrowserCommand("tabNext")
            check(!controller.browserCommandState("developer").checked,"next tab includes temporary tabs")
            controller.performBrowserCommand("tabPrevious")
            check(controller.browserCommandState("developer").checked,"previous tab restores source tab")
            controller.performBrowserCommand("alwaysOnTop")
            check(controller.window.level == .floating,"stay-on-top action")
            controller.performBrowserCommand("alwaysOnTop")
            check(controller.window.level == .normal,"stay-on-top can be reverted")
            let originalTitle = controller.browserCommandState("sidebar").title
            controller.performBrowserCommand("sidebar")
            check(controller.browserCommandState("sidebar").title != originalTitle,"menu labels follow sidebar state")
            controller.performBrowserCommand("sidebar")
            check(find("space.1") != nil && !controller.browserCommandState("space.9").enabled,"dynamic spaces and unavailable slots")
            controller.performBrowserCommand("shortcuts")
            check(NSApp.windows.contains { $0.title == "Préférences" && $0.isVisible },"shortcut preferences open from Help")
            for window in NSApp.windows where window.title == "Préférences" { window.orderOut(nil) }
            print("PASS \(checks) menu and shortcut checks; save page supported: \(bridge.canSavePage(controller.rendererID(for:first)))"); fflush(stdout)
            delegate.requestQuit()
            }
        }
        guard BrowserEngine.start(cachePath:directory+"/Chromium") else { fatalError("engine startup") }
        withExtendedLifetime((delegate,timer)) { BrowserEngine.runMessageLoop() }
        BrowserEngine.shutdown()
    }
}
