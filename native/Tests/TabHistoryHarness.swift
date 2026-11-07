import AppKit

@main struct TabHistoryHarness {
    static func main() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["BROWSER_NATIVE_TEST_DATA"], path.contains("tab-history-check"),
              let origin = env["BROWSER_HISTORY_ORIGIN"], origin.hasPrefix("http://127.0.0.1:") else {
            fatalError("This fixture requires an isolated profile and loopback server")
        }
        let restart = env["BROWSER_HISTORY_RESTART"] == "1"
        let app = BrowserEngine.createApplication()
        app.setActivationPolicy(.regular)
        let store = SessionStore(directory:URL(fileURLWithPath:path))
        let cache = store.directory.appendingPathComponent("Chromium")
        try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
        var session = try store.load() ?? BrowserSession.fresh(language:"fr")
        let a = origin + "/a", b = origin.replacingOccurrences(of:"127.0.0.1",with:"localhost") + "/b", c = origin + "/c"
        if !restart {
            session.onboardingComplete = true
            _ = session.createTab(url:a)
            try store.save(session)
        }
        let tabID = (restart ? session.closedTabs.last : session.tabs.last)!.id
        let delegate = NativeAppDelegate(store:store,initial:session)
        app.delegate = delegate
        var stage = restart ? 7 : 0
        var deadline = Date().addingTimeInterval(20)
        func advance() { stage += 1; deadline = Date().addingTimeInterval(20) }
        let timer = Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { timer in MainActor.assumeIsolated {
            guard Date() < deadline else { fatalError("Timed out at history stage \(stage)") }
            guard let window = delegate.controller else { return }
            func at(_ address:String) -> Bool {
                window.selectedWindowURL == address &&
                window.windowSession.tabs.first(where:{ $0.id == tabID })?.title == URL(string:address)?.lastPathComponent
            }
            let driver = WindowBrowserEngine(windowID:window.windowID)
            let canBack = window.browserCommandState("back").enabled
            let canForward = window.browserCommandState("forward").enabled
            switch stage {
            case 0 where at(a):
                driver.navigateTab(tabID,url:b); advance()
            case 1 where at(b) && canBack:
                driver.navigateTab(tabID,url:c); advance()
            case 2 where at(c) && canBack:
                window.performBrowserCommand("closeTab"); advance()
            case 3 where window.windowSession.closedTabs.last?.id == tabID:
                precondition(window.windowSession.closedTabs.last?.archivedNavigation != nil, "Missing Chromium history on close")
                let shortcut = CGEvent(keyboardEventSource:nil,virtualKey:17,keyDown:true)!
                shortcut.flags = [.maskCommand,.maskShift]
                let event = NSEvent(cgEvent:shortcut)!
                precondition(NSApp.mainMenu?.performKeyEquivalent(with:event) == true, "⇧⌘T must reach the restore command")
                advance()
            case 4 where at(c) && canBack && !canForward:
                window.performBrowserCommand("back"); advance()
            case 5 where at(b) && canBack && canForward:
                print("PASS reopen C, then cross-origin Back to B"); fflush(stdout)
                window.performBrowserCommand("closeTab"); advance()
            case 6 where window.windowSession.closedTabs.last?.id == tabID:
                precondition(ArcSyncCodec.canonical(window.windowSession).closedTabs.last?.archivedNavigation == nil)
                timer.invalidate(); delegate.requestQuit()
            case 7 where window.browserCommandState("restoreTab").enabled:
                window.performBrowserCommand("restoreTab"); advance()
            case 8 where at(b) && canBack && canForward:
                window.performBrowserCommand("forward"); advance()
            case 9 where at(c) && canBack && !canForward:
                window.performBrowserCommand("back"); advance()
            case 10 where at(b) && canBack && canForward:
                window.performBrowserCommand("back"); advance()
            case 11 where at(a) && !canBack && canForward:
                print("PASS persisted cursor B, Forward to C and Back twice to A"); fflush(stdout)
                driver.navigateTab(tabID,url:origin+"/d"); advance()
            case 12 where at(origin+"/d") && canBack && !canForward:
                print("PASS navigating from A removes the old forward branch"); fflush(stdout)
                driver.navigateTab(tabID,url:origin+"/spa"); advance()
            case 13 where window.selectedWindowURL == origin+"/spa?chapter=2" && window.windowSession.tabs.first(where:{ $0.id == tabID })?.title == "chapter ready":
                window.performBrowserCommand("clearToday"); advance()
            case 14 where window.windowSession.closedTabs.last?.id == tabID:
                window.performBrowserCommand("restoreTab"); advance()
            case 15 where window.selectedWindowURL == origin+"/spa?chapter=2" && window.windowSession.tabs.first(where:{ $0.id == tabID })?.title == "chapter restored":
                print("PASS bulk archive and restore preserves same-document history.state"); fflush(stdout)
                window.openExternalAddress(origin+"/other")
                _ = delegate.openWindow(.normal,from:window); advance()
            case 16 where delegate.controllers.count == 2 && window.selectedWindowURL == origin+"/other":
                window.performBrowserCommand("clearToday"); advance()
            case 17 where window.windowSession.closedTabs.contains(where:{ $0.id == tabID }):
                precondition(window.windowSession.closedTabs.first(where:{ $0.id == tabID })?.archivedNavigation != nil)
                print("PASS archiving from another window captures the owning renderer’s history"); fflush(stdout)
                timer.invalidate(); delegate.requestQuit()
            default: break
            }
        } }
        guard BrowserEngine.start(cachePath:cache.path) else { fatalError("CEF initialization") }
        withExtendedLifetime((delegate,timer)) { BrowserEngine.runMessageLoop() }
        BrowserEngine.shutdown()
    }
}
