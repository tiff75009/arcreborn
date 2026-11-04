import AppKit

@main struct OnboardingTests {
    static func main() throws {
        var checks = 0
        func check(_ ok:Bool,_ name:String) { guard ok else { fatalError(name) }; checks += 1; print("PASS \(name)") }
        let payload:[String:Any] = ["roots":["bookmark_bar":["name":"Travail","children":[["name":"Documentation","url":"https://example.com/docs"],["name":"Unsafe","url":"javascript:alert(1)"]]]]]
        let bookmarks = BrowserImportReader.bookmarks(payload)
        check(bookmarks.count == 1 && bookmarks[0].folder == "Travail","bookmarks filter active URLs and retain folders")
        let html = Data("<DL><DT><A HREF=\"https://example.org/?a=1&amp;b=2\">A &amp; B</A><A HREF=\"file:///private\">No</A></DL>".utf8)
        let links = BrowserImportReader.html(html)
        check(links.count == 1 && links[0].title == "A & B" && links[0].url.hasSuffix("a=1&b=2"),"HTML export decodes entities without rendering")
        check(BrowserImportReader.cleanURL("https://user:secret@example.com") == nil,"embedded credentials rejected")
        let json = Data("{\"windows\":[]}".utf8)
        var moz = Data("mozLz40\0".utf8)
        func int32(_ value:Int)->Data { var n = UInt32(value).littleEndian; return withUnsafeBytes(of:&n) { Data($0) } }
        moz.append(int32(json.count)); moz.append(UInt8(min(15,json.count)<<4)); if json.count>=15 { moz.append(UInt8(json.count-15)) }; moz.append(json)
        let decoded = try BrowserImportReader.decompressMozilla(moz)
        check(decoded == json,"Firefox bounded LZ4 decodes")
        do { _ = try BrowserImportReader.decompressMozilla(Data("mozLz40\0".utf8)); check(false,"truncated Firefox") } catch { check(true,"truncated Firefox rejected") }
        var sessionData = Data("SNSS".utf8); sessionData.append(int32(3))
        func pickleString(_ text:String,wide:Bool)->Data { let data = wide ? text.data(using:.utf16LittleEndian)! : Data(text.utf8); var out = int32(wide ? text.utf16.count : data.count); out.append(data); while out.count%4 != 0 { out.append(0) }; return out }
        func command(_ id:UInt8,_ payload:Data) { let size = payload.count+1; sessionData.append(UInt8(size&255)); sessionData.append(UInt8((size>>8)&255)); sessionData.append(id); sessionData.append(payload) }
        var nav = int32(42); nav.append(int32(0)); nav.append(pickleString("https://example.net",wide:false)); nav.append(pickleString("Onglet",wide:true)); var pickle = int32(nav.count); pickle.append(nav); command(6,pickle)
        var selected = int32(42); selected.append(int32(0)); command(7,selected)
        var pinned = int32(42); pinned.append(1); pinned.append(contentsOf:[0,0,0]); command(12,pinned)
        let tabs = try BrowserImportReader.chromiumSession(sessionData)
        check(tabs.count == 1 && tabs[0].title == "Onglet" && tabs[0].pinned,"Chrome session restores selected navigation and pins")
        command(16,int32(42)); check(try BrowserImportReader.chromiumSession(sessionData).isEmpty,"closed Chrome tabs are excluded")
        let arc:[String:Any] = ["sidebar":["containers":[["items":["t",["id":"t","parentID":"recent","data":["tab":["savedURL":"https://example.net/arc","savedTitle":"Arc"]]]],"spaces":["s",["newContainerIDs":[["unpinned":[:]],"recent"]]]]]]]
        check(BrowserImportReader.arc(arc).first?.pinned == false,"Arc recent tab remains unpinned")
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:fixture) }
        func write(_ bytes:Data,_ path:String) throws {
            let url = fixture.appendingPathComponent(path)
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try bytes.write(to:url)
        }
        let localState = ["profile":["last_used":"Profile 2","info_cache":["Profile 2":["name":"Work"]]]] as [String:Any]
        try write(try JSONSerialization.data(withJSONObject:localState),"Chrome/Local State")
        for id in ["Default","Profile 2","Guest Profile"] {
            let entry = ["name":id,"url":"https://example.net/"+id.replacingOccurrences(of:" ",with:"-")]
            try write(try JSONSerialization.data(withJSONObject:[entry]),"Chrome/"+id+"/Bookmarks")
        }
        let sources = ImportBrowser.all
        let discovered = try sources[1].importProfiles(in:fixture.appendingPathComponent("Chrome"))
        check(discovered.map { $0.url.lastPathComponent } == ["Profile 2","Default"],"discovers Chrome profiles with last used first and excludes guests")
        let found = try BrowserImportReader.preview(at:discovered[0].url,browser:sources[1])
        check(found.links.map(\.title) == ["Profile 2"],"direct import reads only the selected profile")
        try write(try JSONSerialization.data(withJSONObject:arc),"Arc/StorableSidebar.json")
        let arcSources = try sources[3].importProfiles(in:fixture.appendingPathComponent("Arc"))
        check(arcSources.count == 1 && (try? BrowserImportReader.preview(at:arcSources[0].url,browser:sources[3]).links.count) == 1,"Arc sidebar is imported directly")
        try write(Data("[Profile0]\nName=Personal\nIsRelative=1\nPath=Profiles/abc.default-release\n".utf8),"Firefox/profiles.ini")
        try write(Data(),"Firefox/Profiles/abc.default-release/.fixture")
        let fox = try sources[2].importProfiles(in:fixture.appendingPathComponent("Firefox/Profiles"))
        check(fox.count == 1 && fox.first?.name == "Personal","Firefox profile registry maps labels to the real folder")
        var state = BrowserSession.fresh(language:"fr"); _ = state.createTab(url:"https://existing.test")
        let before = state, profile = state.profiles[0].id
        let count = try state.importLinks(bookmarks+links,from:"Chrome",profileID:profile)
        check(count == 2 && state.tabs.contains(before.tabs[0]) && state.spaces.count == 2 && state.validated(),"import preserves current session and creates a separate space")
        let after = state; let duplicateCount = try state.importLinks(bookmarks+links,from:"Chrome",profileID:profile)
        check(duplicateCount == 0 && state == after,"repeat import is idempotent")
        do { _ = try state.importLinks([.init(url:"https://new.test",title:"",folder:"",pinned:false)],from:"Safari",profileID:"missing"); check(false,"missing profile") } catch { check(state == after,"failed import is atomic") }
        check(ArcAccount.registrationError(username:"valid_user",email:"user@example.test",password:"Une phrase solide 42!",confirmation:"Une phrase solide 42!") == nil,"strong passphrase accepted")
        check(ArcAccount.registrationError(username:"valid_user",email:"user@example.test",password:"aaaaaaaaaaaaaaaa",confirmation:"aaaaaaaaaaaaaaaa") != nil,"repeated password rejected")
        check(BrowserCommands.command("importBrowser")?.available == true,"import is reachable from system menu")
        print("PASS \(checks) onboarding/import checks"); fflush(stdout)
        guard CommandLine.arguments.contains("--preview") else { return }
        let output = URL(fileURLWithPath:CommandLine.arguments.last!,isDirectory:true); try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let welcome = WelcomeWindow(language:"fr"); welcome.window?.center(); welcome.showWindow(nil); welcome.window?.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps:true)
        var step = 0
        let timer = Timer.scheduledTimer(withTimeInterval:0.6,repeats:true) { timer in
            let view = welcome.window!.contentView!; view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap); try! bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("step-\(step).png")) }
            step += 1
            if let next = WelcomeWindow.Step(rawValue:step) { welcome.select(next) }
            else { timer.invalidate(); welcome.close(); app.stop(nil) }
        }
        withExtendedLifetime((timer,welcome)) { app.run() }
    }
}
