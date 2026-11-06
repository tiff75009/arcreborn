import Foundation

@main struct LibraryTests {
    static var passed = 0
    static func check(_ condition:Bool,_ message:String) { guard condition else { fputs("FAIL: \(message)\n",stderr); exit(1) }; passed += 1 }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("browser-library-unit-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let downloads = root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at:downloads,withIntermediateDirectories:true)
        for name in ["Photo Été.png","Clip.mov","Son.wav","document.txt",".hidden.png"] { try Data([0,1,2]).write(to:downloads.appendingPathComponent(name)) }
        try FileManager.default.createDirectory(at:downloads.appendingPathComponent("folder.png"),withIntermediateDirectories:true)
        try FileManager.default.createSymbolicLink(at:downloads.appendingPathComponent("link.png"),withDestinationURL:downloads.appendingPathComponent("Photo Été.png"))
        let media = try LibraryMediaScanner.scan(downloads)
        check(media.count == 3,"only regular, visible media files are indexed")
        check(Set(media.map(\.kind)) == ["image","video","audio"],"images movies and audio supported")
        check(LibraryMediaScanner.matching(media,query:"ete").count == 1,"accent insensitive media search")
        check(LibraryMediaScanner.matching(media,query:"  ").count == 3,"empty search preserves all files")
        check(LibraryMediaScanner.matching(media,query:"absent").isEmpty,"missing query returns no result")
        let changedDate = Date(timeIntervalSince1970:10)
        try FileManager.default.setAttributes([.modificationDate:changedDate],ofItemAtPath:downloads.appendingPathComponent("Photo Été.png").path)
        let updated = try LibraryMediaScanner.scan(downloads)
        check(updated.last?.name == "Photo Été.png","newest media appears first")
        check(updated.last?.cacheKey != media.first(where: { $0.name == "Photo Été.png" })?.cacheKey,"modified file invalidates thumbnail identity")
        let store = LibraryStore(directory:root,downloadsDirectory:downloads)
        check(!store.mediaEnabled && store.media.isEmpty,"no directory read before Show Media")
        check(store.lastSection == .media,"first opening keeps the existing default")
        check(!store.updateDownload(id:"one",name:"First",path:"",source:"https://example.test/a",profileID:"personal",received:0,total:10,state:"progress"),"no arrival before the destination is known")
        check(store.updateDownload(id:"one",name:"First",path:"/tmp/a",source:"https://example.test/a",profileID:"personal",received:5,total:10,state:"progress"),"accepted transfer animates once")
        check(store.updateDownload(id:"two",name:"Second",path:"/tmp/b",source:"https://example.test/b",profileID:"work",received:20,total:20,state:"complete"),"instant completion also signals an arrival")
        check(store.matchingDownloads(query:"",profiles:["work"]).map(\.id) == ["two"],"download profile isolation")
        check(store.matchingDownloads(query:"first",profiles:[]).map(\.id) == ["one"],"download search")
        check(store.downloads.first(where: { $0.id == "one" })?.fraction == 0.5,"download progress")
        check(!store.updateDownload(id:"one",name:"",path:"",source:"",profileID:"",received:7,total:10,state:"progress"),"subsequent progress does not relaunch the animation")
        check(store.downloads.count == 2 && store.downloads.first(where: { $0.id == "one" })?.profileID == "personal","callbacks preserve original profile and do not duplicate")
        store.flush()
        let secondWindow = LibraryStore(directory:root,downloadsDirectory:downloads)
        for section in [LibrarySection.downloads,.spaces,.archived,.media] {
            store.rememberSection(section)
            check(secondWindow.lastSection == section,"last section is shared with other windows")
        }
        secondWindow.rememberSection(.downloads)
        store.rememberSection(.notes)
        check(store.lastSection == .downloads,"disabled section cannot replace the last selection")
        store.flush()
        check(secondWindow.downloads.first(where: { $0.id == "one" })?.isActive == true,"a concurrent window sees the active transfer")
        // Load the on-disk snapshot without a live peer, as on a cold launch.
        func coldLaunch() throws -> LibraryStore {
            let restart = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:restart,withIntermediateDirectories:true)
            try FileManager.default.copyItem(at:root.appendingPathComponent("library.json"),to:restart.appendingPathComponent("library.json"))
            return LibraryStore(directory:restart,downloadsDirectory:downloads)
        }
        let restored = try coldLaunch()
        check(restored.lastSection == .downloads,"last library section survives a cold launch")
        check(restored.downloads.count == 2 && restored.downloads.first(where: { $0.id == "two" })?.state == "complete","download history persists")
        check(restored.downloads.first(where: { $0.id == "one" })?.state == "interrupted","unfinished download is interrupted after restart")
        let before = try Data(contentsOf:downloads.appendingPathComponent("Photo Été.png"))
        store.enableMedia(); store.flush()
        check(try coldLaunch().mediaEnabled,"media opt-in persists")
        check(try Data(contentsOf:downloads.appendingPathComponent("Photo Été.png")) == before,"indexing never modifies originals")
        do { _ = try LibraryMediaScanner.scan(root.appendingPathComponent("missing")); check(false,"missing directory must report an error") } catch { check(true,"missing directory reports an error") }
        let recentFiles = (0..<6).map { i -> LibraryMedia in
            let url = downloads.appendingPathComponent("recent-\(i).png")
            try! Data([0]).write(to:url)
            return LibraryMedia(url:url,date:Date(timeIntervalSince1970:Double(i)),size:1,kind:"image")
        }
        let recent = RecentLibraryFile.collect(media:recentFiles,downloads:[])
        check(recent.count == 4,"hover preview is limited to four files")
        check(recent.map { $0.url.lastPathComponent } == ["recent-2.png","recent-3.png","recent-4.png","recent-5.png"],"the four most recent files put the newest nearest the footer")
        let duplicate = LibraryDownload(id:"duplicate",name:"duplicate",path:recentFiles[5].url.path,source:"",profileID:"p",date:Date(timeIntervalSince1970:20),received:1,total:1,state:"complete")
        let combined = RecentLibraryFile.collect(media:recentFiles,downloads:[duplicate])
        check(combined.count == 4 && Set(combined.map(\.url)).count == 4 && combined.last?.date == duplicate.date,"media and download duplicates merge using latest date")
        var incomplete = duplicate; incomplete.state = "progress"
        check(RecentLibraryFile.collect(media:[],downloads:[incomplete]).isEmpty,"unfinished downloads are not opened by hover preview")
        var missing = duplicate; missing.path = root.appendingPathComponent("missing.pdf").path
        check(RecentLibraryFile.collect(media:[],downloads:[missing]).isEmpty,"deleted downloads are omitted")
        var document = duplicate; document.path = downloads.appendingPathComponent("document.txt").path
        check(RecentLibraryFile.collect(media:[],downloads:[document]).count == 1,"non-media completed downloads are included")
        check(store.unreadCount == 1,"new completion gets an unread badge")
        store.acknowledge(["one"])
        check(store.unreadCount == 1,"viewing active transfer does not mark unseen completion")
        store.acknowledge(["two"])
        check(store.unreadCount == 0,"only viewed completion is acknowledged")
        store.updateDownload(id:"two",name:"Second",path:"/tmp/b",source:"",profileID:"work",received:20,total:20,state:"complete")
        check(store.unreadCount == 0,"duplicate completion callback does not restore badge")
        var controls: [String] = []
        store.control = { controls.append($0+":"+$1) }
        store.request("one",action:"pause"); store.request("two",action:"pause"); store.request("one",action:"resume")
        check(controls == ["one:pause"],"control commands validate current transfer state")
        store.updateDownload(id:"one",name:"",path:"",source:"",profileID:"",received:7,total:10,state:"paused",speed:0)
        store.request("one",action:"resume"); store.request("one",action:"cancel")
        check(controls.suffix(2) == ["one:resume","one:cancel"],"paused download supports resume and cancel")
        for i in 0..<10 { store.updateDownload(id:"multi-\(i)",name:"Transfer \(i)",path:"",source:"",profileID:"work",received:10,total:100,state:"progress",speed:50) }
        check(store.activeDownloads.count == 11 && store.peekDownloads.count == 4,"all active transfers retained, shelf limited to four")
        check(store.peekDownloads.map(\.id) == ["multi-6","multi-7","multi-8","multi-9"],"newest active transfer sits at the bottom of the hover shelf")
        check(store.matchingDownloads(query:"Transfer",profiles:["work"]).count == 10,"full library contains all ten concurrent downloads")
        check(store.downloads.first(where: { $0.id == "multi-0" })?.speed == 50,"engine throughput is retained")
        store.updateDownload(id:"multi-0",name:"",path:"",source:"",profileID:"",received:100,total:100,state:"complete")
        store.flush()
        let afterTransfers = try coldLaunch()
        check(afterTransfers.unreadCount == 1,"unread completion survives restart")
        check(afterTransfers.downloads.first(where: { $0.id == "one" })?.state == "interrupted","paused transfer does not pretend to resume after restart")
        check(afterTransfers.activeDownloads.isEmpty,"stale runtime transfers are not controllable after restart")
        store.removeDownload("one")
        check(store.downloads.contains(where: { $0.id == "one" }),"active transfer cannot be removed without cancellation")
        let original = downloads.appendingPathComponent("recent-5.png")
        store.updateDownload(id:"remove",name:"recent-5.png",path:original.path,source:"",profileID:"p",received:1,total:1,state:"complete")
        store.removeDownload("remove")
        check(!store.downloads.contains(where: { $0.id == "remove" }) && FileManager.default.fileExists(atPath:original.path),"remove only deletes history, preserving disk file")
        check(!RecentLibraryFile.collect(media:recentFiles,downloads:[],excluding:store.hiddenRecents).contains(where: { $0.url == original }),"removed file stays out of recent shelf")
        store.flush()
        check(try coldLaunch().hiddenRecents.contains(original.path),"recent dismissal persists")
        for key in [nil,"unknown-future-section","notes"] as [String?] {
            let legacy = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:legacy,withIntermediateDirectories:true)
            var snapshot = try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("library.json"))) as! [String:Any]
            snapshot["lastSection"] = key
            try JSONSerialization.data(withJSONObject:snapshot).write(to:legacy.appendingPathComponent("library.json"))
            let old = LibraryStore(directory:legacy,downloadsDirectory:downloads)
            check(old.lastSection == .media,"old or unsupported section falls back safely")
            check(old.downloads.count == store.downloads.count && old.mediaEnabled && old.hiddenRecents == store.hiddenRecents,"legacy selection does not discard library metadata")
        }
        let privateStore = LibraryStore(directory:root,downloadsDirectory:downloads,persistent:false)
        privateStore.rememberSection(.archived); privateStore.flush()
        let afterPrivateWindow = try coldLaunch()
        check(store.lastSection == .downloads && afterPrivateWindow.lastSection == .downloads,"non-persistent window cannot overwrite the saved section")
        print("PASS: \(passed) library assertions")
    }
}
