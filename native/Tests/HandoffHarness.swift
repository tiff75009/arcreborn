import AppKit

@main struct HandoffHarness {
    static func main() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["BROWSER_NATIVE_TEST_DATA"], path.contains("handoff-check"),
              let origin = env["BROWSER_HANDOFF_TEST_URL"], origin.hasPrefix("http://127.0.0.1:") else { fatalError("Isolated Handoff fixture only") }
        var count = 0
        func check(_ value:Bool,_ label:String) {
            guard value else { print("FAIL \(label)"); fflush(stdout); exit(1) }
            count += 1; print("PASS \(label)"); fflush(stdout)
        }
        func activity(_ suffix:String) -> NSUserActivity {
            let value = NSUserActivity(activityType:NSUserActivityTypeBrowsingWeb)
            value.webpageURL = URL(string:origin+suffix); return value
        }
        var initial = BrowserSession.fresh(language:"fr"); initial.onboardingComplete = true
        let original = initial.createTab(url:origin+"/original")
        let root = URL(fileURLWithPath:path), store = SessionStore(directory:root)
        try FileManager.default.createDirectory(at:root.appendingPathComponent("Chromium"),withIntermediateDirectories:true)
        try store.save(initial)
        let app = BrowserEngine.createApplication(); app.setActivationPolicy(.regular)
        let delegate = NativeAppDelegate(store:store,initial:initial); app.delegate = delegate
        UserDefaults.standard.set("fr",forKey:"BrowserLanguage")
        check(delegate.application(app,willContinueUserActivityWithType:NSUserActivityTypeBrowsingWeb),"browser Handoff accepted before Chromium starts")
        check(!delegate.application(app,willContinueUserActivityWithType:"other"),"unknown activity declined by app delegate")
        check(delegate.application(app,continue:activity("/cold"),restorationHandler:{ _ in }),"cold-start Handoff queued")
        check(delegate.controllers.isEmpty && delegate.sharedSession.tabs.count == initial.tabs.count,"cold-start receipt does not create a premature renderer")
        var stage = 0, entered = Date()
        var regular:BrowserController?, privateWindow:BrowserController?, blank:BrowserController?
        func next(_ value:Int) { stage = value; entered = Date() }
        let timer = Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { timer in MainActor.assumeIsolated {
            if Date().timeIntervalSince(entered) > 18 { check(false,"timeout stage \(stage)"); return }
            switch stage {
            case 0:
                guard let c = delegate.controller, c.selectedWindowURL == origin+"/cold", delegate.handoff.activity?.title == "Reprise café" else { return }
                regular = c
                check(c.windowSession.tabs.count == initial.tabs.count+1 && c.windowSession.tabs.first(where:{$0.id == original})?.url == origin+"/original","cold-start receipt opens one new tab and preserves existing navigation")
                check(delegate.handoff.activity?.webpageURL?.absoluteString == c.selectedWindowURL,"active page advertised with its loaded title")
                next(1)
            case 1:
                guard let c = regular, c.selectedWindowURL == origin+"/details?fil=caf%C3%A9#lecture", delegate.handoff.activity?.title == "Détails — café" else { return }
                check(delegate.handoff.activity?.webpageURL?.absoluteString == c.selectedWindowURL,"real SPA navigation updates Handoff without returning to the original page")
                privateWindow = delegate.openWindow(.privateWindow,from:c,initialAddress:origin+"/private")
                next(2)
            case 2:
                guard let p = privateWindow, delegate.controller === p else { return }
                check(delegate.handoff.activity == nil && p.handoffPage == nil,"focusing a private window withdraws the public activity")
                let before = p.windowSession.tabs
                check(delegate.application(app,continue:activity("/incoming"),restorationHandler:{ _ in }),"Handoff received while private window is active")
                check(p.windowSession.tabs == before && delegate.controller === regular,"incoming page uses a regular window without altering private tabs")
                next(3)
            case 3:
                guard let c = regular, c.selectedWindowURL == origin+"/incoming", delegate.handoff.activity?.title == "Reprise reçue" else { return }
                check(c.windowSession.tabs.count == initial.tabs.count+2,"warm receipt creates exactly one additional tab")
                privateWindow?.requestWindowClose(); next(4)
            case 4:
                guard delegate.controllers.count == 1, let c = regular else { return }
                blank = delegate.openWindow(.blank,from:c,initialAddress:"about:blank")
                check(delegate.handoff.activity == nil,"blank/internal page withdraws Handoff")
                blank?.requestWindowClose(); next(5)
            case 5:
                guard delegate.controllers.count == 1, let c = regular else { return }
                c.show()
                check(delegate.handoff.activity?.webpageURL?.absoluteString == origin+"/incoming","return to the regular window restores its activity")
                timer.invalidate()
                delegate.requestQuit()
                check(delegate.handoff.activity == nil,"quitting withdraws the advertised activity")
                print("Handoff native integration: \(count) checks passed"); fflush(stdout)
            default: break
            }
        } }
        guard BrowserEngine.start(cachePath:root.appendingPathComponent("Chromium").path) else { fatalError("CEF initialization") }
        withExtendedLifetime((delegate,timer)) { BrowserEngine.runMessageLoop() }
        BrowserEngine.shutdown()
    }
}
