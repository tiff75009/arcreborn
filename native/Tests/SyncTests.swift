import Foundation

@main struct SyncTests {
    static func main() throws {
        var count = 0
        func check(_ condition:Bool,_ label:String) { precondition(condition,label); count += 1; print("PASS \(label)") }
        func rejects(_ label:String,_ body:()throws->Void) { do { try body(); preconditionFailure(label) } catch { check(true,label) } }
        var base = BrowserSession.fresh()
        let tab = base.createTab(url:"https://example.org/one")
        let key = ArcSyncCodec.newKey(), owner = "test-owner"
        let code = ArcSyncCodec.recoveryCode(key)
        check(try ArcSyncCodec.key(from:code.lowercased()) == key,"recovery code roundtrip")
        rejects("incomplete recovery code refused") { _ = try ArcSyncCodec.key(from:"AR1-0000") }
        let ciphertext = try ArcSyncCodec.encrypt(base,key:key,owner:owner)
        check(!ciphertext.contains("example.org"),"no plaintext URL in envelope")
        check(try ArcSyncCodec.decrypt(ciphertext,key:key,owner:owner) == ArcSyncCodec.canonical(base),"authenticated encryption roundtrip")
        rejects("wrong owner refused") { _ = try ArcSyncCodec.decrypt(ciphertext,key:key,owner:"another-owner") }
        rejects("wrong key refused") { _ = try ArcSyncCodec.decrypt(ciphertext,key:ArcSyncCodec.newKey(),owner:owner) }
        var damaged = Data(base64Encoded:ciphertext)!; damaged[damaged.count-1] ^= 1
        rejects("tampered ciphertext refused") { _ = try ArcSyncCodec.decrypt(damaged.base64EncodedString(),key:key,owner:owner) }
        rejects("private session refused") { _ = try ArcSyncCodec.encrypt(base.standaloneWindow(privateProfile:"private-test"),key:key,owner:owner) }
        var local = base, remote = base
        let addedLocal = local.createTab(url:"https://example.org/local")
        let addedRemote = remote.createTab(url:"https://example.org/remote")
        local.tabs[0].customTitle = "Mon titre"; remote.tabs[0].url = "https://example.org/updated"
        let merged = try ArcSyncCodec.merge(local:local,baseline:base,remote:remote)
        check(merged.tabs.contains(where:{$0.id == addedLocal}) && merged.tabs.contains(where:{$0.id == addedRemote}),"concurrent additions retained")
        check(merged.tabs[0].customTitle == "Mon titre" && merged.tabs[0].url == remote.tabs[0].url,"independent field edits retained")
        var closed = base; closed.closeTab(id:tab)
        let deletion = try ArcSyncCodec.merge(local:closed,baseline:base,remote:remote)
        check(!deletion.tabs.contains(where:{$0.id == tab}) && deletion.tabs.contains(where:{$0.id == addedRemote}),"deletion does not resurrect old tab")
        check(try ArcSyncCodec.merge(local:.fresh(),baseline:nil,remote:remote) == ArcSyncCodec.canonical(remote),"fresh install restores existing workspace")
        var second = BrowserSession.fresh(); _ = second.createTab(url:"https://second.example.org")
        let combined = try ArcSyncCodec.merge(local:second,baseline:nil,remote:remote)
        check(combined.spaces.count == 2 && combined.tabs.count == second.tabs.count+remote.tabs.count,"used device merges without replacing local workspace")
        var editedDuringRequest = local; editedDuringRequest.tabs[0].customTitle = "Titre récent"
        let reconciled = try ArcSyncCodec.merge(local:editedDuringRequest,baseline:local,remote:merged)
        check(reconciled.tabs[0].customTitle == "Titre récent" && reconciled.tabs.contains(where:{$0.id == addedRemote}),"edits during network request preserved")
        let checkpoint = NativeCloudCheckpoint(enabled:true,revision:1,ciphertext:ciphertext,lastSync:Date())
        local.sidebarHidden = true
        let applied = try ArcSyncCodec.applying(merged,to:local,checkpointKey:owner,checkpoint:checkpoint)
        check(applied.sidebarHidden && applied.cloudSyncState?[owner] == checkpoint,"local presentation and sync baseline retained")
        let reencrypted = try ArcSyncCodec.encrypt(applied,key:key,owner:owner)
        check(try ArcSyncCodec.decrypt(reencrypted,key:key,owner:owner).cloudSyncState == nil,"encrypted baseline never recursively uploaded")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("arc-sync-test-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = SessionStore(directory:directory)
        try store.save(applied)
        check(try store.load() == applied,"session and baseline persist together")
        let oldData = try JSONEncoder().encode(base)
        check(try JSONDecoder().decode(BrowserSession.self,from:oldData).cloudSyncState == nil,"old session without sync metadata remains readable")
        var favorites = base
        _ = favorites.moveToFavorites(tab,spaceID:favorites.activeSpaceID,at:0)
        let sharedSpace = favorites.createSpace(name:"Shared",color:"#112233",icon:"✦")
        favorites.selectTab(id:tab)
        var updated = favorites; updated.tabs[0].title = "Shared favorite title"
        let windowMerge = try BrowserSession.merging(base:favorites,incoming:updated,latest:favorites)
        check(windowMerge.spaces.first { $0.id == sharedSpace }?.selectedTabID == tab && windowMerge.validated(),"window merging preserves shared favorite selections")
        let syncedFavorites = try ArcSyncCodec.applying(ArcSyncCodec.canonical(updated),to:favorites,checkpointKey:owner,checkpoint:checkpoint)
        check(syncedFavorites.spaces.first { $0.id == sharedSpace }?.selectedTabID == tab && syncedFavorites.validated(),"sync restores same-profile shared favorite selections")
        var archivedSession = base
        let navigation = ArchivedNavigation(profileID:base.profiles[0].id,data:Data([1,2,3]))
        archivedSession.closeTab(id:tab,navigation:navigation)
        let cloud = try ArcSyncCodec.decrypt(ArcSyncCodec.encrypt(archivedSession,key:key,owner:owner),key:key,owner:owner)
        check(cloud.closedTabs.last?.id == tab && cloud.closedTabs.last?.archivedNavigation == nil,"tab navigation stays on the originating Mac")
        let refreshedArchive = try ArcSyncCodec.applying(cloud,to:archivedSession,checkpointKey:owner,checkpoint:checkpoint)
        check(refreshedArchive.closedTabs.last?.archivedNavigation == navigation,"cloud refresh preserves local archived navigation")
        var withFiles = base
        let file = withFiles.createTab(url:"file:///Users/test/Documents/caf%C3%A9.pdf")
        let archived = withFiles.createTab(url:"file:///Volumes/Disk/drawing.svg"); withFiles.closeTab(id:archived)
        _ = withFiles.mergeSplit(file,onto:tab)
        withFiles.selectTab(id:file)
        let filtered = try ArcSyncCodec.decrypt(ArcSyncCodec.encrypt(withFiles,key:key,owner:owner),key:key,owner:owner)
        check(filtered.validated() && !filtered.tabs.contains(where:{$0.id == file}) && !filtered.closedTabs.contains(where:{$0.id == archived}),"open and archived documents stay off the cloud")
        var changed = filtered; let remoteTab = changed.createTab(url:"https://example.com/elsewhere")
        let afterSync = try ArcSyncCodec.applying(changed,to:withFiles,checkpointKey:owner,checkpoint:checkpoint)
        check(afterSync.validated() && afterSync.tabs.contains(where:{$0.id == remoteTab}) && afterSync.spaces.first?.selectedTabID == file && afterSync.splitGroup(containing:file)?.tabIDs.contains(tab) == true && afterSync.closedTabs.contains(where:{$0.id == archived}),"receiving cloud edits keeps this Mac’s selected document, split and archive")
        print("PASS \(count) sync checks; real browser profile untouched")
    }
}
