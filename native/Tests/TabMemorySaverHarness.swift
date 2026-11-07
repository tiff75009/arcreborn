// SPDX-License-Identifier: MPL-2.0
import AppKit

@main struct TabMemorySaverHarness {
    static func main() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["BROWSER_NATIVE_TEST_DATA"], path.contains("tab-saver-check-"),
              let origin = env["BROWSER_SAVER_ORIGIN"], origin.hasPrefix("http://127.0.0.1:"),
              let scenario = env["BROWSER_SAVER_SCENARIO"] else { fatalError("Requires the isolated test runner") }
        let app = BrowserEngine.createApplication()
        app.setActivationPolicy(.regular)
        let store = SessionStore(directory:URL(fileURLWithPath:path))
        let cache = store.directory.appendingPathComponent("Chromium")
        try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
        var session = BrowserSession.fresh(language:"fr")
        session.onboardingComplete = true
        let target = origin + "/" + scenario
        let willSleep = ["idle","history"].contains(scenario)
        let id = session.createTab(url:scenario == "history" ? origin+"/first" : target)
        let front = origin.replacingOccurrences(of:"127.0.0.1",with:"localhost") + "/front"
        if scenario == "media", let tab = session.tabs.first(where:{ $0.id == id }) {
            session.setAutomaticPictureInPicture(false,for:tab)
        }
        if scenario == "split" {
            let right = session.createTab(url:front)
            precondition(session.mergeSplit(id,onto:right))
        }
        try store.save(session)
        let delegate = NativeAppDelegate(store:store,initial:session)
        app.delegate = delegate
        var stage = 0, changed = Date()
        var saverControl: NSSwitch?
        func find<T:NSView>(_ type:T.Type, in view:NSView, where matches:(T)->Bool) -> T? {
            if let found = view as? T, matches(found) { return found }
            for child in view.subviews {
                if let result = find(type,in:child,where:matches) { return result }
            }
            return nil
        }
        func advance() { stage += 1; changed = Date() }
        func mark(_ name:String) {
            FileManager.default.createFile(atPath:path+"/"+name,contents:Data())
        }
        let timer = Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { timer in MainActor.assumeIsolated {
            let elapsed = -changed.timeIntervalSinceNow
            guard let window = delegate.controller else { return }
            let driver = WindowBrowserEngine(windowID:window.windowID)
            let tab = window.windowSession.tabs.first(where:{ $0.id == id })
            guard elapsed < 20 else { fatalError("Timeout in \(scenario), stage \(stage), title \(tab?.title ?? "-"), selected \(window.selectedWindowURL ?? "-"), loaded \(window.hasArchiveRenderer(id))") }
            let now = ProcessInfo.processInfo.systemUptime
            @MainActor func row(titled title:String) -> (NSTableView,Int) {
                guard let root = window.window.contentView,
                      let table = find(NSTableView.self,in:root,where:{ $0.delegate === window }) else { fatalError("Missing tab table") }
                for index in 0..<table.numberOfRows {
                    if let cell = table.view(atColumn:0,row:index,makeIfNecessary:true) as? TabCell, cell.titleLabel.stringValue == title {
                        return (table,index)
                    }
                }
                fatalError("Missing sidebar row for \(title)")
            }
            @MainActor func selectSidebarRow() {
                let (table,index) = row(titled:tab!.title)
                table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)
                precondition(window.selectedWindowURL == target,"Sidebar selection")
            }
            @MainActor func keepMenuItem(_ title:String) -> (NSMenu,NSMenuItem) {
                let (table,index) = row(titled:title)
                table.scrollRowToVisible(index)
                let rect = table.rect(ofRow:index)
                let point = table.convert(NSPoint(x:rect.midX,y:rect.midY),to:nil)
                let event = NSEvent.mouseEvent(with:.rightMouseDown,location:point,modifierFlags:[],timestamp:0,
                    windowNumber:window.window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
                guard let menu = table.menu(for:event), let item = menu.item(withTitle:"Toujours garder ce site actif") else {
                    fatalError("Missing context menu option")
                }
                return (menu,item)
            }
            func finish() {
                precondition(window.windowSession.closedTabs.isEmpty)
                print("PASS \(scenario)"); fflush(stdout)
                timer.invalidate(); delegate.requestQuit()
            }
            switch stage {
            case 0 where tab?.title == "Start audio":
                if !FileManager.default.fileExists(atPath:path+"/play") { mark("play") }
            case 0 where ["exception","fairness"].contains(scenario) && tab?.title == "ready":
                window.openExternalAddress(origin+"/plain"); advance()
            case 1 where ["exception","fairness"].contains(scenario):
                if window.windowSession.tabs.contains(where:{ $0.title == "plain" }) {
                    window.openExternalAddress(front); advance()
                }
            case 0 where scenario == "split":
                if tab?.title == "ready", window.windowSession.tabs.contains(where: { $0.title == "front" }) {
                    window.sleepIdleTab(now:now+2000,lowPower:true); advance()
                }
            case 1 where scenario == "split":
                if elapsed > 4 {
                    precondition(window.windowSession.tabs.allSatisfy { window.hasArchiveRenderer($0.id) })
                    finish()
                }
            case 0:
                if scenario == "history" && tab?.title == "first" { driver.navigateTab(id,url:target); advance() }
                else if scenario != "history" && tab?.title == "ready" { advance() }
            case 1 where tab?.title == "ready" && elapsed > 0.3:
                precondition(window.hasArchiveRenderer(id))
                window.openExternalAddress(front); advance()
            case 2 where window.selectedWindowURL == front && window.windowSession.tabs.contains(where:{ $0.url == front && $0.title == "front" }):
                if scenario == "idle" {
                    window.settingsAction(nil)
                    saverControl = NSApp.windows.compactMap { $0.contentView.flatMap { root in
                        find(NSSwitch.self,in:root,where:{ $0.identifier?.rawValue == "performance.memorySaver" })
                    } }.first
                    guard let control = saverControl, let card = control.superview else { fatalError("Missing General preference") }
                    control.scrollToVisible(control.bounds)
                    card.displayIfNeeded()
                    if let output = env["BROWSER_SAVER_SETTINGS_PROOF"],
                       let image = card.bitmapImageRepForCachingDisplay(in:card.bounds) {
                        card.cacheDisplay(in:card.bounds,to:image)
                        try! image.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output))
                    }
                    control.state = .off; _ = control.sendAction(control.action,to:control.target)
                } else { UserDefaults.standard.set(false,forKey:TabMemorySaver.setting) }
                precondition(!TabMemorySaver.enabled)
                window.sleepIdleTab(now:now+2000,lowPower:false); advance()
            case 3 where elapsed > 0.6:
                precondition(window.hasArchiveRenderer(id),"Disabled saver slept a tab")
                if let control = saverControl {
                    control.state = .on; _ = control.sendAction(control.action,to:control.target)
                    control.window?.close(); saverControl = nil
                } else { UserDefaults.standard.set(true,forKey:TabMemorySaver.setting) }
                precondition(TabMemorySaver.enabled)
                window.sleepIdleTab(now:now+550,lowPower:true)
                window.sleepIdleTab(now:now+650,lowPower:false); advance()
            case 4 where elapsed > 0.6:
                precondition(window.hasArchiveRenderer(id),"Tab slept ahead of the deadline")
                mark("before"); advance()
            case 5 where elapsed > 1.1:
                window.sleepIdleTab(now:now+(scenario == "idle" ? 650 : 1900), lowPower:scenario == "idle")
                if scenario == "reselect" { selectSidebarRow() }
                advance()
            case 6 where scenario == "exception":
                if !window.hasArchiveRenderer(id) {
                    let (menu,item) = keepMenuItem("ready"); precondition(item.state == .off)
                    menu.performActionForItem(at:menu.index(of:item))
                    precondition(window.selectedWindowURL == front && window.hasArchiveRenderer(id))
                    advance()
                }
            case 7 where scenario == "exception":
                if tab?.title == "awake", let sibling = window.windowSession.tabs.first(where:{ $0.title == "plain" }) {
                    let (_,item) = keepMenuItem("plain"); precondition(item.state == .on)
                    precondition(window.archiveProtectedIDs.isSuperset(of:[id,sibling.id]))
                    window.sleepIdleTab(now:now+2600,lowPower:true); advance()
                }
            case 8 where scenario == "exception":
                if elapsed > 4, let sibling = window.windowSession.tabs.first(where:{ $0.title == "plain" }) {
                    precondition(window.hasArchiveRenderer(id) && window.hasArchiveRenderer(sibling.id))
                    let (menu,item) = keepMenuItem("plain"); menu.performActionForItem(at:menu.index(of:item))
                    precondition(keepMenuItem("awake").1.state == .off && window.selectedWindowURL == front)
                    window.sleepIdleTab(now:now+2800,lowPower:false); advance()
                }
            case 9 where scenario == "exception":
                if let sibling = window.windowSession.tabs.first(where:{ $0.title == "plain" }), !window.hasArchiveRenderer(sibling.id) {
                    finish()
                }
            case 6 where scenario == "fairness":
                if elapsed > 4 {
                    precondition(window.hasArchiveRenderer(id))
                    // The oldest protected tab is already eligible for a retry.
                    window.sleepIdleTab(now:now+2800,lowPower:false); advance()
                }
            case 7 where scenario == "fairness":
                if let other = window.windowSession.tabs.first(where:{ $0.title == "plain" }), !window.hasArchiveRenderer(other.id) {
                    precondition(window.hasArchiveRenderer(id) && window.selectedWindowURL == front)
                    finish()
                }
            case 6 where willSleep && !window.hasArchiveRenderer(id):
                precondition(tab?.url == target && tab?.title == "ready" && window.selectedWindowURL == front)
                precondition(window.windowSession.tabs.count == 2 && window.windowSession.closedTabs.isEmpty)
                if scenario == "history" { precondition(tab?.archivedNavigation != nil) }
                advance()
            case 6 where !willSleep && elapsed > 4:
                precondition(window.hasArchiveRenderer(id), "Protected page lost its renderer")
                if scenario != "reselect" { selectSidebarRow() }
                mark("validate"); advance()
            case 7 where willSleep && elapsed > 1:
                mark("after"); advance()
            case 7 where !willSleep && window.selectedWindowURL == target && tab?.title == "intact":
                finish()
            case 8 where elapsed > 0.5:
                selectSidebarRow(); advance()
            case 9 where window.selectedWindowURL == target && tab?.title == "awake":
                precondition(window.hasArchiveRenderer(id))
                if scenario == "history" {
                    window.backAction(nil); advance()
                } else {
                    driver.navigateTab(id,url:origin+"/next"); advance()
                }
            case 10 where scenario == "history" && tab?.title == "first":
                window.forwardAction(nil); advance()
            case 10 where scenario == "idle" && tab?.title == "next":
                advance()
            case 11 where elapsed > 0.8:
                precondition(tab?.url == (scenario == "idle" ? origin+"/next" : target))
                finish()
            default: break
            }
        } }
        guard BrowserEngine.start(cachePath:cache.path) else { fatalError("CEF initialization") }
        withExtendedLifetime((delegate,timer)) { BrowserEngine.runMessageLoop() }
        BrowserEngine.shutdown()
    }
}
