import AppKit

@main struct PreferencesHarness {
    static var checks = 0
    static func check(_ value:Bool,_ name:String) {
        guard value else { print("FAIL \(name)"); fflush(stdout); exit(1) }
        checks += 1; print("PASS \(name)"); fflush(stdout)
    }
    static func main() throws {
        guard let path = ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"], path.contains("preferences-check") else { fatalError("Isolated preferences fixture only") }
        let root = URL(fileURLWithPath:path); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let links = ProfileSettingsLink.all
        check(links.map(\.address) == ["arc://settings/privacy","arc://password-manager/passwords","arc://settings/payments","arc://settings/content/notifications","arc://settings/privacy"],"five requested profile destinations")
        for item in links {
            let url = browserURL(item.address)!
            check(url.scheme == "chrome" && isAllowedBrowserURL(url.absoluteString) && browserDisplayAddress(url.absoluteString) == item.address,"internal route \(item.id)")
        }
        for invalid in ["chrome://password-manager.evil/passwords","chrome://user@password-manager/passwords","chrome://password-manager:80/passwords","chrome://crash/"] {
            check(settingsPageURL(invalid) == nil && !isAllowedBrowserURL(invalid),"reject unsupported internal authority")
        }
        var state = BrowserSession.fresh(language:"fr"); state.onboardingComplete = true
        let sourceProfile = state.profiles[0].id, sourceSpace = state.activeSpaceID
        let sourceTab = state.createTab(url:"https://example.com/")
        let other = NativeProfile(id:UUID().uuidString,name:"Travail")
        state.profiles.append(other)
        let settingsTab = state.openSettingsPage(links[1].address,profileID:other.id)
        check(settingsTab != nil && state.spaces.first(where:{$0.id == state.activeSpaceID})?.profileID == other.id,"unused profile receives a space with its own settings tab")
        check(state.tabs.first(where:{$0.id == sourceTab})?.spaceID == sourceSpace && state.spaces.first(where:{$0.id == sourceSpace})?.profileID == sourceProfile,"source profile and page preserved")
        state.activeSpaceID = sourceSpace
        let count = state.spaces.count
        _ = state.openSettingsPage(links[0].address,profileID:other.id)
        check(state.spaces.count == count && state.spaces.first(where:{$0.id == state.activeSpaceID})?.profileID == other.id,"selected profile reused instead of active profile")
        let previous = state
        check(state.openSettingsPage(links[0].address,profileID:"missing") == nil && state == previous,"invalid profile leaves state unchanged")
        check(state.renameProfile(id:other.id,name:"  Studio  ") && state.profiles.last?.name == "Studio","profile rename keeps identity")
        check(!state.renameProfile(id:other.id,name:"\n"),"empty profile name rejected")
        let restored = try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(state))
        check(state.validated() && restored == state,"settings survive session round trip")
        if ProcessInfo.processInfo.environment["PREFERENCES_RUNTIME"] == "1" { try runtime(root); return }
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let controller = BrowserPreferencesWindow(language:"fr",profiles:[.init(id:"personal",name:"Personnel",spaces:2),.init(id:"work",name:"Studio",spaces:0)],selectedProfileID:"personal",appearance:.dark,save:true,signIn:true,suggestions:true)
        controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps:true)
        func capture(_ name:String) {
            guard let view = controller.window?.contentView?.superview else { return }
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { fatalError("bitmap") }
            view.cacheDisplay(in:view.bounds,to:bitmap)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
            print("PREVIEW \(name)"); fflush(stdout)
        }
        var step = 0
        let timer = Timer.scheduledTimer(withTimeInterval:0.8,repeats:true) { timer in MainActor.assumeIsolated {
            switch step {
            case 0: capture("general"); controller.showProfiles("work")
            case 1:
                capture("profiles")
                var calls:[String] = []
                controller.onOpenProfilePage = { profile,address in check(profile == "work","profile link targets selection"); calls.append(address); return false }
                func visit(_ view:NSView) {
                    if let id = view.identifier?.rawValue, id.hasPrefix("profile-link."), let row = view as? ActionButton { row.performClick(nil) }
                    view.subviews.forEach(visit)
                }
                visit(controller.window!.contentView!)
                check(calls == links.map(\.address),"every displayed profile link is wired")
                controller.showShortcuts()
            case 2: capture("shortcuts"); controller.showProfiles(); controller.window?.appearance = NSAppearance(named:.aqua)
            default: capture("profiles-light"); timer.invalidate(); controller.close(); print("PASS \(checks) preferences checks"); fflush(stdout); app.stop(nil)
            }
            step += 1
        } }
        withExtendedLifetime((timer,controller)) { app.run() }
    }
    static func runtime(_ root:URL) throws {
        var state = BrowserSession.fresh(language:"fr"); state.onboardingComplete = true; _ = state.createTab()
        let profile = NativeProfile(id:UUID().uuidString,name:"Isolated profile"); state.profiles.append(profile)
        let store = SessionStore(directory:root); try store.save(state)
        try FileManager.default.createDirectory(at:root.appendingPathComponent("Chromium"),withIntermediateDirectories:true)
        let app = BrowserEngine.createApplication(); app.setActivationPolicy(.regular)
        let delegate = NativeAppDelegate(store:store,initial:state); app.delegate = delegate
        let routes = Array(ProfileSettingsLink.all.prefix(4)), advance = root.appendingPathComponent("advance")
        var step = -1, entered = Date()
        let timer = Timer.scheduledTimer(withTimeInterval:0.15,repeats:true) { timer in MainActor.assumeIsolated {
            guard let controller = delegate.controller else { return }
            if Date().timeIntervalSince(entered)>25 { check(false,"runtime settings timeout at \(step)") }
            guard step == -1 || (try? String(contentsOf:advance)) == String(step) else { return }
            step += 1; entered = Date()
            if step == routes.count {
                timer.invalidate(); check(delegate.controllers.count == 1,"settings remain inside one Browser window")
                print("PASS runtime profile settings"); fflush(stdout); delegate.requestQuit(); return
            }
            check(controller.openProfileSettings(routes[step].address,profileID:profile.id),"open native profile route \(routes[step].id)")
            check(controller.windowSession.spaces.first(where:{$0.id == controller.windowSession.activeSpaceID})?.profileID == profile.id,"runtime tab uses selected profile")
            print("ROUTE \(step) \(routes[step].address)"); fflush(stdout)
        } }
        guard BrowserEngine.start(cachePath:root.appendingPathComponent("Chromium").path) else { fatalError("CEF startup") }
        withExtendedLifetime((delegate,timer)) { BrowserEngine.runMessageLoop() }; BrowserEngine.shutdown()
    }
}
