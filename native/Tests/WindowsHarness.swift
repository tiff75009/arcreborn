import AppKit

@main struct WindowsHarness {
    static func main() throws {
        guard let path = ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"], path.contains("windows-check"),
              let url = ProcessInfo.processInfo.environment["BROWSER_WINDOW_TEST_URL"], url.hasPrefix("http://127.0.0.1:") else { fatalError("Isolated windows fixture only") }
        var checks = 0
        func check(_ condition:@autoclosure ()->Bool,_ name:String) {
            guard condition() else { print("FAIL \(name)"); fflush(stdout); exit(1) }
            checks += 1; print("PASS \(name)"); fflush(stdout)
        }
        var initial = BrowserSession.fresh(language:"fr"); initial.onboardingComplete = true
        let firstID = initial.createTab(url:url+"?set=regular")
        var a = initial, b = initial
        let added = a.createTab(url:url+"?added"); b.tabs[0].title = "updated"
        let combined = try BrowserSession.merging(base:initial,incoming:b,latest:a)
        check(combined.tabs.contains { $0.id == added } && combined.tabs[0].title == "updated","independent window edits merge")
        a.closeTab(id:firstID)
        let noResurrection = try BrowserSession.merging(base:initial,incoming:b,latest:a)
        check(!noResurrection.tabs.contains { $0.id == firstID },"late title does not resurrect closed tab")
        let defaults = BrowserCommands.resolved([:])
        check(BrowserCommands.all.filter { $0.available && !$0.binding.key.isEmpty }.allSatisfy { defaults[$0.id] == $0.binding },"window shortcuts are available without collisions")
        let root = URL(fileURLWithPath:path), store = SessionStore(directory:root)
        try FileManager.default.createDirectory(at:root.appendingPathComponent("Chromium"),withIntermediateDirectories:true)
        try store.save(initial)
        let metadataA = LibraryStore(directory:root), metadataB = LibraryStore(directory:root)
        metadataA.updateDownload(id:"test-one",name:"one",path:"",source:"",profileID:"test",received:1,total:3,state:"progress")
        check(metadataB.activeDownloads.count == 1,"downloads synchronize across windows")
        let metadataC = LibraryStore(directory:root)
        check(metadataC.activeDownloads.count == 1,"opening window does not interrupt active download")
        metadataB.updateDownload(id:"test-two",name:"two",path:"",source:"",profileID:"test",received:1,total:3,state:"progress")
        check(metadataA.activeDownloads.count == 2,"independent downloads are preserved")
        let app = BrowserEngine.createApplication(); app.setActivationPolicy(.regular)
        let delegate = NativeAppDelegate(store:store,initial:initial); app.delegate = delegate
        UserDefaults.standard.set("fr",forKey:"BrowserLanguage")
        var stage = 0, entered = Date(), main:BrowserController?, second:BrowserController?, blank:BrowserController?, p1:BrowserController?, p2:BrowserController?, compact:BrowserController?, sharedID = ""
        func title(_ c:BrowserController?) -> String { c?.windowSession.tabs.first(where: { $0.id == c?.selectedWindowTabID })?.title ?? "" }
        func advance(_ n:Int) { stage=n; entered=Date() }
        let timer = Timer.scheduledTimer(withTimeInterval:0.15,repeats:true) { timer in MainActor.assumeIsolated {
            if Date().timeIntervalSince(entered)>18 { print("FAIL timeout stage \(stage), titles \(title(main)), \(title(blank)), \(title(p1)), \(title(p2))"); fflush(stdout); exit(1) }
            switch stage {
            case 0:
                guard let c=delegate.controller, title(c)=="windowtest=regular|regular" else { return }
                main=c
                c.performBrowserCommand("manageSpaces")
                check(c.isManagingSpaces && c.window.attachedSheet == nil,"Manage Spaces opens existing library section")
                second=delegate.openWindow(.normal,from:c); advance(1)
            case 1:
                guard let m=main, let s=second, title(s)=="windowtest=regular|regular" else { return }
                check(s.selectedWindowTabID==firstID && m.rendererID(for:firstID) != s.rendererID(for:firstID),"normal windows share tabs with independent Chromium views")
                check(delegate.controller === s,"menus target active window")
                var reply = delegate.sharedSession
                reply.profiles[0].name = "Profil synchronisé"
                let details = url+"?details"
                // Deliver the cloud reply in the same turn as Chromium's URL
                // callback, before the navigating window's save timer fires.
                s.browserURLChanged(firstID,url:details)
                do { try delegate.applyCloudSession(reply) }
                catch { check(false,"apply overlapping navigation and cloud edits"); return }
                check(s.selectedWindowURL == details && m.selectedWindowURL == details,"a sync reply preserves the in-page navigation in both windows")
                let saved = try? store.load()
                check(saved?.tabs.first(where:{$0.id == firstID})?.url == details && saved?.profiles[0].name == "Profil synchronisé","latest page and independent remote edit persist together")
                s.openExternalAddress(url+"?shared"); sharedID=s.selectedWindowTabID ?? ""; advance(2)
            case 2:
                guard let m=main, m.windowSession.tabs.contains(where:{$0.id==sharedID}) else { return }
                check(m.selectedWindowTabID==firstID,"shared tabs preserve each window selection")
                blank=delegate.openWindow(.blank,from:second)
                check(blank!.windowSession.tabs.count==1 && blank!.selectedWindowURL=="about:blank","blank window has independent empty workspace")
                blank!.openExternalAddress(url+"?blank"); advance(3)
            case 3:
                guard title(blank)=="windowtest=regular|regular" else { return }
                check(!main!.windowSession.tabs.contains { $0.url.contains("?blank") },"blank tabs do not modify main spaces")
                p1=delegate.openWindow(.privateWindow,from:main); p1!.openExternalAddress(url+"?private-read"); advance(4)
            case 4:
                guard title(p1)=="none|none" else { return }
                check(p1!.isPrivateWindow,"private cookies and localStorage isolated from regular profile")
                p1!.openExternalAddress(url+"?set=secret-private"); advance(5)
            case 5:
                guard title(p1)=="windowtest=secret-private|secret-private" else { return }
                p2=delegate.openWindow(.privateWindow,from:p1); p2!.openExternalAddress(url+"?private-peer"); advance(6)
            case 6:
                guard title(p2)=="windowtest=secret-private|secret-private" else { return }
                check(true,"private windows share only their in-memory context")
                let records=WindowPersistence(directory:root).load()
                check(records.count==3 && records.allSatisfy { $0.kind == .normal || $0.kind == .blank },"private windows excluded from restoration")
                let persisted=(try? String(contentsOf:root.appendingPathComponent("session.json"))) ?? ""
                let windows=(try? String(contentsOf:root.appendingPathComponent("windows.json"))) ?? ""
                check(!persisted.contains("secret-private") && !windows.contains("secret-private"),"private addresses excluded from saved session and windows")
                p1!.requestWindowClose(); p2!.requestWindowClose(); advance(7)
            case 7:
                guard !delegate.controllers.contains(where:{$0.isPrivateWindow}) else { return }
                check(delegate.controllers.count==3 && !delegate.quitting,"closing private windows leaves regular windows running")
                p1=nil; p2=nil
                p1=delegate.openWindow(.privateWindow,from:main); p1!.openExternalAddress(url+"?private-fresh"); advance(8)
            case 8:
                guard title(p1)=="none|none" else { return }
                check(true,"last private window closure clears cookies and storage")
                compact=delegate.openWindow(.compact,from:main)
                check(compact!.window.frame.width<900 && compact!.windowSession.sidebarHidden,"compact window has small address-bar layout")
                compact!.openExternalAddress(url+"?compact"); advance(9)
            case 9:
                guard title(compact)=="windowtest=regular|regular" else { return }
                check(true,"compact window uses selected regular profile")
                compact!.promoteWindowRequested?(); advance(10)
            case 10:
                guard !delegate.controllers.contains(where:{$0 === compact}), let promoted=delegate.controller, promoted.windowKind == .normal else { return }
                check(promoted.selectedWindowURL==url+"?compact","compact page opens in full window")
                let records=WindowPersistence(directory:root).load()
                check(records.count==4 && records.compactMap { $0.restoredSession(shared:delegate.sharedSession) }.count==4,"normal and blank windows restore valid sessions")
                for c in delegate.controllers { c.requestWindowClose() }; advance(11)
            case 11:
                guard delegate.controllers.isEmpty else { return }
                check(!delegate.quitting,"app remains available with all windows closed")
                func find(_ menu:NSMenu?) -> NSMenuItem? {
                    for item in menu?.items ?? [] { if item.representedObject as? String == "newWindow" { return item }; if let sub=item.submenu, let found=find(sub) { return found } }; return nil
                }
                guard let item=find(NSApp.mainMenu), let target=item.target as? NSMenuItemValidation else { check(false,"window menu exists without active controller"); return }
                check(target.validateMenuItem(item),"New Window stays enabled with no open window")
                check(NSApp.sendAction(item.action!,to:item.target,from:item),"menu reopens a real window")
                advance(12)
            case 12:
                guard delegate.controllers.count==1 else { return }
                check(delegate.controller!.windowSession.tabs.contains { $0.id==firstID },"reopened normal window preserves main session")
                let files=(try? FileManager.default.contentsOfDirectory(atPath:root.appendingPathComponent("Chromium/MockKeychain").path)) ?? []
                check(!files.contains { $0.hasPrefix("Profile-private-") },"no private disk profile created")
                timer.invalidate(); print("PASS \(checks) windows checks"); fflush(stdout); delegate.requestQuit()
                DispatchQueue.main.asyncAfter(deadline:.now()+8) { check(false,"graceful shutdown timeout") }
            default: break
            }
        } }
        guard BrowserEngine.start(cachePath:root.appendingPathComponent("Chromium").path) else { fatalError("CEF startup") }
        withExtendedLifetime((delegate,timer,metadataA,metadataB,metadataC)) { BrowserEngine.runMessageLoop() }
        BrowserEngine.shutdown()
        check(true,"CEF shutdown completes after closing private and regular windows")
    }
}
