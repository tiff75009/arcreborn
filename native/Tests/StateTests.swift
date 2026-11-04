import Foundation
import CoreGraphics

@main struct StateTests {
    static var passed = 0
    static func check(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        passed += 1
    }
    static func mustThrow(_ message: String, _ action: () throws -> Void) {
        do { try action(); fputs("FAIL: \(message) did not throw\n", stderr); exit(1) }
        catch { passed += 1 }
    }
    static func main() throws {
        for address in ["arc://extensions/", " browser://extensions \n", "CHROME://EXTENSIONS/"] {
            check(isExtensionsAddress(address), "extensions command recognized: \(address)")
            check(!isAllowedBrowserURL(address), "internal command never becomes an ordinary web tab")
        }
        for address in ["https://extensions/", "arc://extensions.evil/", "arc://user@extensions/", "arc://extensions/?url=https://example.com", "chrome://settings/", "arc://extensions/../settings"] {
            check(!isExtensionsAddress(address), "only the exact extension command is accepted: \(address)")
        }
        try tabRenameTests()
        try spaceReorderTests()
        try spaceIconPersistenceTests()
        try spaceCreationTests()
        try folderTreeTests()
        try collapsedSelectionTests()
        try favoriteTests()
        try sharedFavoriteTests()
        spaceNavigationTests()
        deletionUndoTests()
        var harmony = SpaceTheme.solid("#0086A6").preparedForColorWheel()
        check(harmony.pickerVersion == 1 && harmony.points[0].color == "#0086A6", "opening wheel preserves saved color")
        harmony.addHarmonyColor(); harmony.addHarmonyColor(); harmony.addHarmonyColor()
        check(harmony.points.count == 3 && harmony.validated(), "three linked colors maximum")
        check(try JSONDecoder().decode(SpaceTheme.self,from:JSONEncoder().encode(harmony)) == harmony, "linked wheel survives serialization")
        let moved = harmony.movingColor(0,toX:0.82,y:0.65)
        check(zip(harmony.points,moved.points).allSatisfy { $0.color != $1.color && ($0.x != $1.x || $0.y != $1.y) }, "drag changes every linked color and position")
        func angleBetween(_ theme: SpaceTheme) -> Double {
            let a = theme.points[0], b = theme.points[1]
            return atan2((a.x-0.5)*(b.y-0.5)-(a.y-0.5)*(b.x-0.5),(a.x-0.5)*(b.x-0.5)+(a.y-0.5)*(b.y-0.5))
        }
        check(abs(cos(angleBetween(harmony))-cos(angleBetween(moved))) < 0.000001, "drag preserves harmony angle")
        let edge = harmony.movingColor(1,toX:4,y:-3)
        check(edge.validated() && edge.points.allSatisfy { hypot($0.x-0.5,$0.y-0.5) <= 0.460001 }, "all colors stay bounded together")
        check(harmony.movingColor(0,toX:Double.nan,y:0) == harmony, "invalid pointer ignored")
        let reversed = moved.movingColor(0,toX:harmony.points[0].x,y:harmony.points[0].y)
        check(zip(reversed.points,harmony.points).allSatisfy { abs($0.x-$1.x) < 0.000001 && abs($0.y-$1.y) < 0.000001 }, "linked movement is reversible without coordinate drift")
        var legacyFour = SpaceTheme.solid("#B367A5"); legacyFour.points = Array(repeating:legacyFour.points[0],count:4)
        check(legacyFour.validated() && legacyFour.preparedForColorWheel().points.count == 3, "legacy four-color session opens safely with three handles")
        var excess = harmony; excess.points.append(harmony.points[0]); check(!excess.validated(), "new wheel rejects fourth color")
        var themed = BrowserSession.fresh()
        let legacyJSON = try JSONEncoder().encode(themed)
        check(try JSONDecoder().decode(BrowserSession.self,from:legacyJSON).spaces[0].theme == nil, "legacy session has optional theme")
        var theme = SpaceTheme.solid("#b367a5")
        check(theme.validated() && theme.gradient == 0, "legacy solid appearance preserved")
        check(SpaceTheme.normalizedHex(" 00acca ") == "#00ACCA", "precise color normalized")
        check(SpaceTheme.normalizedHex("#xyz123") == nil, "invalid precise color rejected")
        theme.points.append(ThemePoint(color:"#00ACCA",x:1,y:0)); theme.grain = 0.62; theme.gradient = 0.83
        themed.spaces[0].theme = theme; themed.themeAppearance = .dark
        check(themed.validated(), "multicolor theme valid")
        let decodedTheme = try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(themed))
        check(decodedTheme == themed, "appearance gradient points and grain survive reload")
        for amount in [-0.1,1.1,Double.infinity,Double.nan] {
            var bad = theme; bad.grain = amount; check(!bad.validated(), "reject invalid grain")
            bad = theme; bad.gradient = amount; check(!bad.validated(), "reject invalid gradient")
        }
        var badTheme = theme; badTheme.points = []; check(!badTheme.validated(), "at least one color required")
        badTheme.points = Array(repeating:theme.points[0],count:5); check(!badTheme.validated(), "limit gradient colors")
        badTheme = theme; badTheme.points[0].x = -1; check(!badTheme.validated(), "reject out of range handle")
        themed.spaces[0].theme = badTheme; check(!themed.validated(), "session rejects invalid theme")
        check(normalizedLiveHost("  GitHub.COM. ") == "github.com", "live domain normalized")
        for invalidHost in ["", ".", "https://github.com", "github.com/a", "a@github.com", "github.com?x=1", "-bad.com", "bad..com"] {
            check(normalizedLiveHost(invalidHost) == nil, "reject malformed live domain")
        }
        var content = BrowserSession.fresh()
        let source = content.activeSpaceID
        let sourceTab = content.createTab(url:"https://github.com/org?a=1&b=2")
        _ = content.createTab(url:"https://docs.github.com/en")
        _ = content.createTab(url:"https://notgithub.com")
        content.tabs[0].title = "<script> & \"test\""
        let live = NativeFolder(id:"live-test",spaceID:source,name:"GitHub",collapsed:false,liveHost:"github.com")
        content.folders.append(live)
        check(content.tabs(in:live).count == 2, "live folder matches domain and subdomains only")
        let legacyFolder = try JSONDecoder().decode(NativeFolder.self,from:Data(#"{"id":"legacy","spaceID":"space","name":"Old","collapsed":false}"#.utf8))
        check(legacyFolder.liveHost == nil, "old folders decode without a live rule")
        let html = content.bookmarksHTML(for:source)
        check(html.contains("&lt;script&gt; &amp; &quot;test&quot;") && html.contains("a=1&amp;b=2"), "export escapes markup and URL attributes")
        let originalTabs = content.tabs
        let target = content.createSpace(name:"Target",color:"#B367A5",icon:"◇")
        check(content.exportSpaceIntoFolder(source,targetID:target), "export creates target folder")
        check(content.tabs.filter { $0.spaceID == source } == originalTabs, "export preserves source tabs")
        check(content.tabs.filter { $0.spaceID == target }.allSatisfy { $0.pinned && !$0.favorite && $0.id != sourceTab && $0.folderID != nil }, "export copies fresh pinned identities")
        check(content.validated(), "live folder and export form valid session")
        let exported = content
        check(!content.exportSpaceIntoFolder(source,targetID:source) && content == exported, "invalid export has no partial mutation")
        check(content.shareText(for:source).contains("https://github.com/org?a=1&b=2"), "share contains original links")
        var session = BrowserSession.fresh()
        check(session.validated(), "initial session validates")
        check(session.language == "fr" && session.tabs.isEmpty && !session.onboardingComplete, "first run is blank and French")
        check(BrowserSession.fresh(language: "en").spaces[0].name == "Personal", "English initial name")
        check(BrowserSession.fresh(language: "unknown").language == "fr", "unsupported initial language falls back")
        let firstSpace = session.activeSpaceID
        session.removeSpace(id: firstSpace)
        check(session.spaces.count == 1, "last space is protected")
        let tab1 = session.createTab(url: "https://example.com/one")
        let tab2 = session.createTab(url: "https://example.com/two")
        check(session.spaces[0].selectedTabID == tab2, "new tab is selected")
        session.closeTab(id: tab2)
        check(session.spaces[0].selectedTabID == tab1, "closing active tab selects sibling")
        session.restoreTab()
        check(session.tabs.last?.id == tab2 && session.closedTabs.isEmpty, "restore retains identity")
        let profile = NativeProfile(id: UUID().uuidString, name: "Travail")
        session.profiles.append(profile)
        let second = session.createSpace(name: "Travail", color: "#abcdef", icon: "W", profileID: profile.id)
        check(!second.isEmpty && session.spaces[1].profileID != session.spaces[0].profileID, "space has separate profile")
        let secondTab = session.createTab(url: "https://example.com/", spaceID: second)
        session.selectTab(id: tab1)
        check(session.activeSpaceID == firstSpace, "tab selection selects owning space")
        session.selectTab(id: secondTab)
        session.closeTab(id: secondTab)
        session.removeSpace(id: second)
        check(session.closedTabs.isEmpty && session.activeSpaceID == firstSpace && session.validated(), "delete space cleans references")
        check(session.createTab(url: "javascript:alert(1)").isEmpty, "unsafe tab rejected")
        check(session.createSpace(name: "", color: "#ffffff", icon: "X").isEmpty, "blank space name rejected")
        let before = session
        session.selectTab(id: "missing"); session.closeTab(id: "missing"); session.removeSpace(id: "missing")
        check(session == before, "unknown identities do not mutate state")
        var invalid = session
        invalid.spaces[0].selectedTabID = "unknown"
        check(!invalid.validated(), "dangling selected tab rejected")
        invalid = session; invalid.spaces[0].profileID = "unknown"
        check(!invalid.validated(), "dangling profile rejected")
        invalid = session; invalid.tabs[0].url = "file:///etc/passwd"
        check(!invalid.validated(), "persisted local file URL rejected")
        invalid = session; invalid.spaces.append(invalid.spaces[0])
        check(!invalid.validated(), "duplicate IDs rejected")
        invalid = session; invalid.sidebarWidth = .infinity
        check(!invalid.validated(), "nonfinite width rejected")
        invalid = session; invalid.tabs[0].favorite = true; invalid.tabs[0].pinned = false
        check(!invalid.validated(), "un-pinned favorite rejected")
        for _ in 0..<60 { let id = session.createTab(); session.closeTab(id: id) }
        check(session.closedTabs.count == 50 && session.validated(), "closed history bounded")

        check(browserURL("example.com/path")?.absoluteString == "https://example.com/path", "bare domain resolution")
        check(browserURL("localhost:3000/path")?.absoluteString == "http://localhost:3000/path", "localhost resolution")
        check(browserURL("[::1]:8080")?.absoluteString == "http://[::1]:8080", "IPv6 localhost resolution")
        check(browserURL("")?.absoluteString == "about:blank", "empty input yields blank page")
        for input in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,x", "https://user:pass@example.com/", "about:config", "blob:https://example.com/id", "https://example.com/\npath", "https://example.com\\@evil.com"] {
            check(browserURL(input) == nil && !isAllowedBrowserURL(input), "unsafe input rejected: \(input)")
        }
        let query = "bonjour &source=evil # monde"
        let components = URLComponents(url: browserURL(query)!, resolvingAgainstBaseURL: false)!
        check(components.host == "www.google.com" && components.queryItems == [URLQueryItem(name: "q", value: query)], "search escapes query parameters")
        check(isAllowedBrowserURL("https://example.com/a%20b"), "encoded path allowed")
        check(!isAllowedBrowserURL("https://example.com/a b"), "raw whitespace rejected")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("browser-native-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        check(tryValue { try store.load() } == nil, "empty store loads no state")
        try store.save(session)
        check(try store.load() == session, "saved state round-trips")
        let original = session
        session.language = "en"
        try store.save(session)
        let mode = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber
        check(mode?.intValue == 0o600, "state permissions are private")
        try Data("{broken".utf8).write(to: store.fileURL)
        let recovered = try store.load()
        check(recovered == original, "corrupted primary recovers previous generation")
        check(store.recoveryNotice?.contains("recovered") == true, "recovery is reported")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let corrupt = names.first { $0.hasPrefix("session.corrupt-") }!
        check(try String(contentsOf: directory.appendingPathComponent(corrupt), encoding: .utf8) == "{broken", "corrupt bytes preserved")
        mustThrow("invalid state persistence") { try store.save(invalid) }
        try FileManager.default.removeItem(at: store.fileURL)
        let outside = directory.appendingPathComponent("outside.json")
        try Data("do not touch".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: store.fileURL, withDestinationURL: outside)
        mustThrow("symlink read") { _ = try store.load() }
        mustThrow("symlink write") { try store.save(original) }
        check(try String(contentsOf: outside, encoding: .utf8) == "do not touch", "outside symlink target untouched")
        print("PASS: \(passed) native state assertions")
    }
    static func spaceIconPersistenceTests() throws {
        for icon in ["🪐", "sf:heart.fill", "none"] {
            var state = BrowserSession.fresh()
            state.spaces[0].icon = icon
            check(state.validated(), "emoji, native symbol and removed icon validate")
            let decoded = try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(state))
            check(decoded.spaces[0].icon == icon, "space icon persists without conversion")
        }
    }
    static func spaceReorderTests() throws {
        var state = BrowserSession.fresh()
        let first = state.spaces[0].id
        let second = state.createSpace(name:"Second",color:"#ABCDEF",icon:"◈")
        let third = state.createSpace(name:"Third",color:"#123456",icon:"✦")
        let original = state
        check(state.reorderSpace(id:first,to:2) && state.spaces.map(\.id) == [second,third,first],"moving first space to end shifts intermediate spaces")
        check(state.activeSpaceID == original.activeSpaceID && state.tabs == original.tabs && state.folders == original.folders && state.profiles == original.profiles,"reorder preserves active space and all browsing content")
        check(state.reorderSpace(id:first,to:0) && state == original,"reverse move restores exact session")
        check(!state.reorderSpace(id:first,to:0) && !state.reorderSpace(id:first,to:-1) && !state.reorderSpace(id:first,to:3) && !state.reorderSpace(id:"missing",to:1) && state == original,"invalid and no-op moves preserve session")
        _ = state.reorderSpace(id:third,to:0)
        check(try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(state)).spaces.map(\.id) == [third,first,second],"space order survives persistence")
    }
    static func spaceCreationTests() throws {
        var state = BrowserSession.fresh()
        let original = state
        var draft = SpaceCreationDraft(profileID:state.profiles[0].id,appearance:.dark)
        check(!draft.isValid && state.createSpace(from:draft).isEmpty && state == original,"empty space draft does not mutate session")
        draft.name = "  Travail  "; draft.icon = "💼"; draft.theme.addHarmonyColor(); draft.theme.grain = 0.4
        check(state == original,"editing space draft leaves existing spaces untouched")
        let id = state.createSpace(from:draft)
        check(!id.isEmpty && state.activeSpaceID == id && state.spaces.last?.name == "Travail","valid draft creates and selects named space")
        check(state.spaces.last?.theme == draft.theme && state.spaces.last?.icon == "💼" && state.spaces.last?.profileID == draft.profileID && state.themeAppearance == .dark,"draft theme icon profile and appearance are committed together")
        check(state.tabs == original.tabs && state.folders == original.folders && state.profiles == original.profiles,"space creation preserves other tabs folders and profiles")
        let committed = state
        draft.profileID = "missing"
        check(state.createSpace(from:draft).isEmpty && state == committed,"invalid draft profile is rejected atomically")
        draft.profileID = original.profiles[0].id; draft.theme.grain = 2
        check(state.createSpace(from:draft).isEmpty && state == committed,"invalid draft theme is rejected atomically")
        check(try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(state)) == state && state.validated(),"created space survives session roundtrip")
    }
    static func deletionUndoTests() {
        var before = BrowserSession.fresh(); let first = before.activeSpaceID
        let original = before.createTab(url:"https://example.com/original")
        let favorite = before.createTab(url:"https://example.com/favorite")
        _ = before.moveToFavorites(favorite,spaceID:first,at:0)
        let second = before.createSpace(name:"Work",color:"#112233",icon:"W")
        before.spaces[1].theme = .solid("#445566")
        before.folders.append(NativeFolder(id:"parent",spaceID:second,name:"Parent",collapsed:false))
        before.folders.append(NativeFolder(id:"child",spaceID:second,name:"Child",collapsed:true,parentID:"parent"))
        let nested = before.createTab(url:"https://example.com/nested")
        _ = before.moveSidebarItem(.tab(nested),spaceID:second,to:SidebarDestination(parentID:"child",before:nil))
        let temporary = before.createTab(url:"https://example.com/temp")
        let baseline = before
        var removed = before; removed.removeSpace(id:second)
        let removal = DeletionUndo(kind:.space,before:before,after:removed)
        check(!removal.isEmpty && removal.removedTabIDs == Set([nested,temporary]),"space deletion records all removed tabs")
        check(removal.restoring(removed) == baseline,"undo space restores exact order, selection, theme, nested folders and tabs")
        let later = removed.createTab(url:"https://example.com/later",spaceID:first)
        removed.spaces[0].name = "Renamed later"
        let merged = removal.restoring(removed)!
        check(merged.tabs.contains(where: { $0.id == later }) && merged.spaces[0].name == "Renamed later","undo preserves unrelated later edits")
        check(merged.spaces[0].selectedTabID == later,"undo preserves a newer selected tab")
        var ownerRemoved = baseline; ownerRemoved.removeSpace(id:first)
        let favoriteUndo = DeletionUndo(kind:.space,before:baseline,after:ownerRemoved)
        check(favoriteUndo.reloadTabIDs == [favorite] && favoriteUndo.restoring(ownerRemoved) == baseline,"undo restores shared favorite ownership without duplicating it")
        var many = BrowserSession.fresh(); let space = many.activeSpaceID
        for i in 0..<80 { _ = many.createTab(url:"https://example.com/\(i)") }
        let ids = many.tabs.map(\.id)
        var cleared = many
        for id in ids { cleared.closeTab(id:id) }
        let clearUndo = DeletionUndo(kind:.tabs,before:many,after:cleared)
        check(cleared.closedTabs.count == 50 && clearUndo.restoring(cleared) == many,"undo cleanup restores all 80 tabs despite archive cap of 50")
        cleared.restoreTab()
        let reopened = clearUndo.restoring(cleared)!
        check(reopened.tabs.count == 80 && Set(reopened.tabs.map(\.id)).count == 80,"reopening a tab before undo does not duplicate it")
        check(reopened.closedTabs.isEmpty && reopened.validated(),"undo removes restored tabs from closed history")
        var firstClear = baseline; firstClear.closeTab(id:temporary)
        let one = DeletionUndo(kind:.tabs,before:baseline,after:firstClear)
        var secondClear = firstClear; secondClear.closeTab(id:original)
        let two = DeletionUndo(kind:.tabs,before:firstClear,after:secondClear)
        check(one.restoring(two.restoring(secondClear)!) == baseline,"successive deletions undo in reverse order")
        check(DeletionUndo(kind:.tabs,before:baseline,after:baseline).isEmpty,"empty cleanup does not register an undo action")
        var missingSpace = cleared; _ = missingSpace.createSpace(name:"Other",color:"#112233",icon:"O"); missingSpace.removeSpace(id:space)
        check(clearUndo.restoring(missingSpace) == nil,"undo cannot create invalid tabs in a separately deleted space")
    }
    static func spaceNavigationTests() {
        let small = SpaceIndicatorLayout(count:2,available:152,activeIndex:0)
        let many = SpaceIndicatorLayout(count:10,available:152,activeIndex:4)
        let huge = SpaceIndicatorLayout(count:100,available:152,activeIndex:99)
        check(small.dotDiameter == 8 && many.dotDiameter == 4,"indicators compact progressively")
        check(many.width <= 152 && huge.width > 152 && huge.inactiveWidth >= 12,"large counts overflow rather than becoming microscopic")
        check(many.frame(4).width >= 24 && huge.frame(99).width >= 24,"active icon stays legible")
        check(many.frame(5).x >= many.frame(4).x+many.frame(4).width,"indicator hit regions never overlap")
        var gesture = SpaceSwipeState()
        let first = gesture.update(dx:-1,dy:0,phase:.began,momentum:false,eligible:true,time:0)
        check(first.consume && first.offset == -1,"first horizontal pixel starts interactive preview")
        let partial = gesture.update(dx:-39,dy:2,phase:.changed,momentum:false,eligible:true,time:0.08)
        check(partial.offset == -40 && partial.direction == 1 && !partial.ended,"preview follows continuous finger distance without switching")
        let reverse = gesture.update(dx:20,dy:0,phase:.changed,momentum:false,eligible:true,time:0.15)
        check(reverse.offset == -20,"reversing fingers reverses preview immediately")
        let cross = gesture.update(dx:40,dy:0,phase:.changed,momentum:false,eligible:true,time:0.22)
        check(cross.offset == 20 && cross.direction == -1,"crossing origin previews the opposite neighbor")
        let held = gesture.update(dx:0,dy:0,phase:.ended,momentum:false,eligible:true,time:0.5)
        check(held.ended && !held.shouldCommit(width:240),"short held gesture returns to original space")
        let momentum = gesture.update(dx:500,dy:0,phase:.changed,momentum:true,eligible:true,time:0.52)
        check(momentum.consume && momentum.offset == held.offset && !momentum.ended,"momentum cannot advance or settle another space")
        _ = gesture.update(dx:-1,dy:0,phase:.began,momentum:false,eligible:true,time:1)
        _ = gesture.update(dx:-90,dy:0,phase:.changed,momentum:false,eligible:true,time:1.2)
        let long = gesture.update(dx:0,dy:0,phase:.ended,momentum:false,eligible:true,time:1.5)
        check(long.shouldCommit(width:240),"long slow swipe commits by distance")
        _ = gesture.update(dx:1,dy:0,phase:.began,momentum:false,eligible:true,time:2)
        _ = gesture.update(dx:25,dy:0,phase:.changed,momentum:false,eligible:true,time:2.02)
        let flick = gesture.update(dx:0,dy:0,phase:.ended,momentum:false,eligible:true,time:2.03)
        check(flick.shouldCommit(width:240),"short quick flick commits by velocity")
        check(!gesture.update(dx:0,dy:0,phase:.cancelled,momentum:false,eligible:true,time:2.04).shouldCommit(width:240),"cancelled short swipe has no projected velocity")
        gesture.reset()
        check(!gesture.update(dx:2,dy:20,phase:.began,momentum:false,eligible:true,time:3).consume,"vertical sidebar scrolling passes through")
        check(!gesture.update(dx:100,dy:0,phase:.changed,momentum:false,eligible:true,time:3.1).consume,"vertical gesture cannot turn into space swipe")
        gesture.reset()
        check(!gesture.update(dx:60,dy:0,phase:.began,momentum:false,eligible:false,time:4).consume,"web content never switches spaces")
        check(gesture.update(dx:60,dy:0,phase:.changed,momentum:false,eligible:true,time:4.1).direction == nil,"gesture started outside cannot activate on entering sidebar")
        check(gesture.update(dx:-45,dy:0,phase:.began,momentum:false,eligible:true,time:5).direction == 1,"next separate gesture is immediately available")
        let leave = gesture.update(dx:60,dy:0,phase:.changed,momentum:false,eligible:false,time:5.1)
        check(leave.cancelled && leave.ended,"leaving sidebar cancels preview")
    }
    static func sharedFavoriteTests() throws {
        var state = BrowserSession.fresh(); let first = state.activeSpaceID
        let favorite = state.createTab(url:"https://example.com")
        _ = state.moveToFavorites(favorite,spaceID:first,at:0)
        state.profiles.append(NativeProfile(id:"other-profile",name:"Other"))
        let second = state.createSpace(name:"Second",color:"#112233",icon:"✦",profileID:"other-profile")
        check(state.favoriteTabs(spaceID:first).map(\.id) == state.favoriteTabs(spaceID:second).map(\.id),"favorites are identical across spaces and profiles")
        let local = state.selectFavorite(favorite)!
        check(state.activeSpaceID == second && local != favorite && state.tabs.first(where: { $0.id == local })?.spaceID == second,"opening shared favorite stays in current profile and space")
        let count = state.tabs.count
        check(state.selectFavorite(favorite) == local && state.tabs.count == count,"repeated favorite activation reuses local tab")
        check(state.sidebarChildren(spaceID:second,parentID:nil).isEmpty && state.sidebarChildren(spaceID:second,parentID:nil,temporary:true).isEmpty,"favorite local tabs do not leak into sidebar lists")
        check(state.validated(),"shared favorite session validates")
        check(try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(state)) == state,"shared favorites persist with local selections")
        var deleted = state; deleted.removeSpace(id:first)
        check(deleted.favoriteTabs(spaceID:second).map(\.id) == [favorite] && deleted.validated(),"deleting original space preserves shared favorites")
        var closed = state; closed.closeTab(id:favorite)
        check(closed.tabs.first(where: { $0.id == local })?.favoriteSourceID == nil && closed.validated(),"closing favorite preserves opened local page as ordinary tab")
        let original = state
        check(!state.moveSidebarItem(.tab(favorite),spaceID:second,to:SidebarDestination(parentID:"missing",before:nil)) && state == original,"invalid shared drop remains atomic")
        state.folders.append(NativeFolder(id:"shared-folder",spaceID:second,name:"Folder",collapsed:false))
        check(state.moveSidebarItem(.tab(favorite),spaceID:second,to:SidebarDestination(parentID:"shared-folder",before:nil)),"shared favorite can be dropped into current space folder")
        check(state.favoriteTabs(spaceID:first).isEmpty && state.tabs.first(where: { $0.id == local })?.folderID == "shared-folder" && state.validated(),"dropping shared favorite removes it globally without losing opened pages")
        var full = BrowserSession.fresh()
        for i in 1..<BrowserSession.maximumSpaces { _ = full.createSpace(name:"Space \(i)",color:"#112233",icon:"✦") }
        let before = full
        check(full.createSpace(name:"Overflow",color:"#112233",icon:"✦").isEmpty && full == before && full.validated(),"100-space storage limit rejects creation atomically")
    }
    static func favoriteTests() throws {
        check(FavoriteGridLayout(count:1).frame(at:0,width:230).width == 230,"one favorite fills the row")
        let two = FavoriteGridLayout(count:2)
        check(two.frame(at:0,width:230).width == 111 && two.frame(at:1,width:230).maxX == 230,"two favorites share the row with an 8 pt gap")
        let five = FavoriteGridLayout(count:5)
        check(five.columns == 3 && five.height == 100,"favorites have at most three columns")
        check(five.frame(at:0,width:230).width == five.frame(at:4,width:230).width && five.frame(at:4,width:230).minY == 54,"last partial row retains three-column widths")
        check(FavoriteGridLayout(count:0).height == 0 && FavoriteGridLayout(count:6).height == 100 && FavoriteGridLayout(count:7).height == 154,"grid height at row boundaries")
        check(five.insertionIndex(x:500,y:1000,width:230) == 4 && five.insertionIndex(x:-10,y:-20,width:230) == 0,"drop positions clamp to grid")
        var state = BrowserSession.fresh()
        let space = state.activeSpaceID
        let a = state.createTab(), b = state.createTab(), c = state.createTab()
        check(state.moveToFavorites(a,spaceID:space,at:0) && state.moveToFavorites(b,spaceID:space,at:1) && state.moveToFavorites(c,spaceID:space,at:1),"insert favorite at proposed position")
        check(state.favoriteTabs(spaceID:space).map(\.id) == [a,c,b],"favorite ordering is explicit")
        check(state.moveToFavorites(b,spaceID:space,at:0) && state.favoriteTabs(spaceID:space).map(\.id) == [b,a,c],"reorder favorite before first")
        check(state.moveToFavorites(b,spaceID:space,at:2) && state.favoriteTabs(spaceID:space).map(\.id) == [a,c,b],"reorder favorite after last without off-by-one")
        state.folders.append(NativeFolder(id:"f",spaceID:space,name:"Folder",collapsed:true))
        check(state.moveSidebarItem(.tab(a),spaceID:space,to:SidebarDestination(parentID:"f",before:nil)),"drag favorite into folder")
        check(state.tabs.first(where: { $0.id == a })?.favorite == false && state.tabs.first(where: { $0.id == a })?.folderID == "f","folder drop removes favorite flag")
        check(state.moveToFavorites(a,spaceID:space,at:1) && state.tabs.first(where: { $0.id == a })?.folderID == nil,"drag folder tab back to favorites")
        check(state.moveSidebarItem(.tab(b),spaceID:space,to:SidebarDestination(parentID:nil,before:nil,temporary:true)),"drag favorite to temporary tabs")
        check(state.tabs.first(where: { $0.id == b })?.favorite == false && state.tabs.first(where: { $0.id == b })?.pinned == false,"temporary drop clears both favorite and pinned")
        let original = state
        check(!state.moveToFavorites("f",spaceID:space,at:0) && state == original,"reject folder as favorite without mutation")
        check(!state.moveToFavorites(a,spaceID:"foreign",at:0) && state == original,"reject cross-space favorite without mutation")
        check(try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(state)) == state && state.validated(),"favorites ordering and transfers survive serialization")
        check(state.tabs.count == 3 && Set(state.tabs.map(\.id)).count == 3,"moving favorites never duplicates tabs")
    }
    static func folderTreeTests() throws {
        var state = BrowserSession.fresh()
        let space = state.activeSpaceID
        state.folders = [NativeFolder(id:"a",spaceID:space,name:"A",collapsed:false), NativeFolder(id:"b",spaceID:space,name:"B",collapsed:false), NativeFolder(id:"c",spaceID:space,name:"C",collapsed:false)]
        let tab = state.createTab(url:"https://example.com")
        check(state.moveSidebarItem(.folder("b"),spaceID:space,to:SidebarDestination(parentID:"a",before:nil)),"nest a folder")
        check(state.moveSidebarItem(.folder("c"),spaceID:space,to:SidebarDestination(parentID:"b",before:nil)),"nest two levels")
        check(state.sidebarTree(spaceID:space).map(\.depth) == [0,1,2],"recursive folder indentation")
        let beforeCycle = state
        check(!state.moveSidebarItem(.folder("a"),spaceID:space,to:SidebarDestination(parentID:"c",before:nil)) && state == beforeCycle,"reject ancestor into descendant atomically")
        check(!state.moveSidebarItem(.folder("b"),spaceID:space,to:SidebarDestination(parentID:"b",before:nil)),"reject folder into itself")
        check(state.moveSidebarItem(.tab(tab),spaceID:space,to:SidebarDestination(parentID:"c",before:nil)),"tab enters nested folder")
        check(state.tabs[0].pinned && state.tabs[0].folderID == "c" && state.validated(),"nested tab becomes pinned")
        state.folders[1].collapsed = true
        check(state.sidebarTree(spaceID:space).count == 2,"collapsed parent hides all descendants")
        state.spaces[0].foldersCollapsed = true
        check(state.sidebarTree(spaceID:space).isEmpty,"space header folds the tree")
        let encoded = try JSONEncoder().encode(state)
        check(try JSONDecoder().decode(BrowserSession.self,from:encoded) == state,"hierarchy and collapse survive restart")
        check(state.moveSidebarItem(.folder("c"),spaceID:space,to:SidebarDestination(parentID:nil,before:.folder("a"))),"extract folder before root sibling")
        check(state.sidebarChildren(spaceID:space,parentID:nil) == [.folder("c"),.folder("a")],"root ordering preserved")
        check(state.moveSidebarItem(.folder("c"),spaceID:space,to:SidebarDestination(parentID:nil,before:nil)),"move folder after root sibling")
        check(state.sidebarChildren(spaceID:space,parentID:nil) == [.folder("a"),.folder("c")],"append root ordering")
        check(state.moveSidebarItem(.tab(tab),spaceID:space,to:SidebarDestination(parentID:nil,before:.folder("c"))),"interleave tab and folders")
        check(state.sidebarChildren(spaceID:space,parentID:nil) == [.folder("a"),.tab(tab),.folder("c")],"mixed sibling order")
        check(state.moveSidebarItem(.tab(tab),spaceID:space,to:SidebarDestination(parentID:nil,before:nil,temporary:true)) && !state.tabs[0].pinned,"extract tab to temporary section")
        state.folders.append(NativeFolder(id:"live",spaceID:space,name:"Live",collapsed:false,liveHost:"example.com"))
        let beforeLive = state
        check(!state.moveSidebarItem(.folder("c"),spaceID:space,to:SidebarDestination(parentID:"live",before:nil)) && state == beforeLive,"live folders reject manual contents")
        var invalid = state; invalid.folders[0].parentID = "b"
        check(!invalid.validated(),"persisted cycle rejected")
        invalid = state; invalid.folders[0].parentID = "missing"
        check(!invalid.validated(),"orphaned folder rejected")
        let otherSpace = state.createSpace(name:"Other",color:"#B367A5",icon:"X")
        check(!state.moveSidebarItem(.folder("a"),spaceID:otherSpace,to:SidebarDestination(parentID:nil,before:nil)),"cross-space identity rejected")
        invalid = state; invalid.folders.append(NativeFolder(id:"foreign",spaceID:otherSpace,name:"Foreign",collapsed:false,parentID:"a"))
        check(!invalid.validated(),"cross-space parent rejected")
        _ = state.moveSidebarItem(.tab(tab),spaceID:space,to:SidebarDestination(parentID:"a",before:nil))
        state.closeTab(id:tab)
        state.removeFolder("a")
        check(state.folders.first(where: { $0.id == "b" })?.parentID == nil,"deleting container promotes subfolders")
        check(state.closedTabs.first?.folderID == nil && state.validated(),"deleting container repairs closed tabs")
        state.restoreTab()
        check(state.tabs.contains(where: { $0.id == tab }),"closed tab still restores")
        var json = try JSONSerialization.jsonObject(with:JSONEncoder().encode(BrowserSession.fresh())) as! [String:Any]
        var spaces = json["spaces"] as! [[String:Any]]; spaces[0].removeValue(forKey:"foldersCollapsed"); json["spaces"] = spaces
        let legacy = try JSONDecoder().decode(BrowserSession.self,from:JSONSerialization.data(withJSONObject:json))
        check(legacy.validated() && legacy.spaces[0].foldersCollapsed == nil,"old sessions load expanded")
    }
    static func collapsedSelectionTests() throws {
        var session = BrowserSession.fresh(), visibility = SidebarCollapseState()
        let space = session.activeSpaceID
        session.folders = [NativeFolder(id:"parent",spaceID:space,name:"Parent",collapsed:false),
                           NativeFolder(id:"child",spaceID:space,name:"Child",collapsed:false,parentID:"parent")]
        let tab = session.createTab(url:"https://example.com")
        _ = session.moveSidebarItem(.tab(tab),spaceID:space,to:SidebarDestination(parentID:"child",before:nil))
        let other = session.createTab(url:"https://example.org")
        session.spaces[0].selectedTabID = tab
        func rows() -> [SidebarTreeRow] { session.sidebarTree(spaceID:space,retainedTabs:visibility.retainedTabs) }
        visibility.toggle(.folder("parent"),in:&session)
        check(rows().map(\.item) == [.folder("parent"),.tab(tab)],"folded ancestor retains selected nested tab")
        check(rows().last?.depth == 1 && session.tabs.first(where: { $0.id == tab })?.folderID == "child","retained tab compacts indentation without moving data")
        session.spaces[0].selectedTabID = other
        check(rows().contains(where: { $0.item == .tab(tab) }),"retained tab survives selection change")
        visibility.toggle(.folder("parent"),in:&session)
        check(rows().filter { $0.item == .tab(tab) }.count == 1,"opening folder does not duplicate retained tab")
        visibility.toggle(.folder("parent"),in:&session)
        check(rows().map(\.item) == [.folder("parent")],"next fold hides previous inactive tab")
        visibility.toggle(.folder("parent"),in:&session)
        session.spaces[0].selectedTabID = tab
        visibility.toggle(.space(space),in:&session)
        check(rows().map(\.item) == [.tab(tab)] && rows().first?.depth == 0,"folded space retains selected tab at root")
        session.spaces[0].selectedTabID = other
        check(rows().map(\.item) == [.tab(tab)],"folded space keeps prior tab when selection changes")
        let restored = try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(session))
        check(restored.sidebarTree(spaceID:space).isEmpty && restored.tabs.count == session.tabs.count,"restart resets only visual retention")
        visibility.toggle(.space(space),in:&session); visibility.toggle(.space(space),in:&session)
        check(rows().isEmpty,"space reopen/refold removes inactive exception")
        visibility.toggle(.space(space),in:&session)
        session.spaces[0].selectedTabID = tab
        visibility.toggle(.folder("child"),in:&session)
        visibility.toggle(.space(space),in:&session)
        check(rows().map(\.item) == [.tab(tab)],"space fold captures tab retained by nested folder")
        let second = session.createSpace(name:"Second",color:"#ABCDEF",icon:"◈")
        check(session.sidebarTree(spaceID:second,retainedTabs:visibility.retainedTabs).isEmpty,"retention remains scoped to original space")
        session.closeTab(id:tab)
        check(rows().isEmpty,"closing retained tab removes visual exception")
        session.activeSpaceID = space
        visibility.toggle(.space(space),in:&session)
        visibility.toggle(.folder("child"),in:&session)
        let moved = session.createTab(url:"https://example.net")
        _ = session.moveSidebarItem(.tab(moved),spaceID:space,to:SidebarDestination(parentID:"child",before:nil))
        visibility.toggle(.folder("child"),in:&session)
        _ = session.moveSidebarItem(.tab(moved),spaceID:space,to:SidebarDestination(parentID:nil,before:nil,temporary:true))
        check(!rows().contains(where: { $0.item == .tab(moved) }),"moving retained tab out removes stale folder row")
        check(session.validated(),"visual retention preserves valid persisted hierarchy")
    }
    static func tryValue<T>(_ action: () throws -> T?) -> T? { try? action() }
    static func tabRenameTests() throws {
        var session = BrowserSession.fresh()
        let id = session.createTab(url: "https://example.com")
        session.tabs[0].title = "Site title"
        check(session.renameTab(id:id,name:"  Mon onglet  "), "rename accepts trimmed name")
        check(session.tabs[0].displayTitle == "Mon onglet", "custom title displayed")
        session.tabs[0].title = "Updated by website"
        check(session.tabs[0].displayTitle == "Mon onglet", "page update preserves custom name")
        let data = try JSONEncoder().encode(session)
        let restored = try JSONDecoder().decode(BrowserSession.self,from:data)
        check(restored.validated() && restored.tabs[0].displayTitle == "Mon onglet", "renamed tab survives restart")
        check(!session.renameTab(id:id,name:String(repeating:"x",count:121)), "oversized name rejected")
        check(!session.renameTab(id:id,name:"a\0b"), "control characters rejected")
        check(session.renameTab(id:id,name:" ") && session.tabs[0].displayTitle == "Updated by website", "empty name resets to current page title")
        var object = try JSONSerialization.jsonObject(with:data) as! [String:Any]
        var tabs = object["tabs"] as! [[String:Any]]; tabs[0].removeValue(forKey:"customTitle"); object["tabs"] = tabs
        let legacy = try JSONDecoder().decode(BrowserSession.self,from:JSONSerialization.data(withJSONObject:object))
        check(legacy.validated() && legacy.tabs[0].customTitle == nil, "legacy tabs decode without name override")
    }

}
