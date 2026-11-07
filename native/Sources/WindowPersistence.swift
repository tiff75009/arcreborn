import AppKit

struct BrowserWindowRecord: Codable {
    var kind: BrowserWindowKind
    var standalone: BrowserSession?
    var activeSpaceID: String
    var selections: [String:String]
    var sidebarHidden: Bool
    var classicSidebarHidden: Bool?
    var sidebarWidth: Double
    var frame: [Double]
    init(_ controller:BrowserController) {
        let state = controller.windowSession
        kind = controller.windowKind; standalone = kind == .blank ? state : nil
        activeSpaceID = state.activeSpaceID
        selections = Dictionary(uniqueKeysWithValues:state.spaces.compactMap { space in space.selectedTabID.map { (space.id,$0) } })
        sidebarHidden = state.sidebarHidden; sidebarWidth = state.sidebarWidth
        let rect = controller.window.frame; frame = [rect.minX,rect.minY,rect.width,rect.height]
    }
    func restoredSession(shared:BrowserSession, favoriteAliases:[String:String] = [:]) -> BrowserSession? {
        guard kind == .normal || kind == .blank else { return nil }
        var state = kind == .normal ? shared : standalone ?? shared
        state.interfaceStyle = shared.interfaceStyle
        state.tabPreviewsEnabled = shared.tabPreviewsEnabled
        state.classicSidebarHidden = nil
        if kind == .blank {
            for i in state.profiles.indices {
                if let current = shared.profiles.first(where:{ $0.id == state.profiles[i].id }) {
                    state.profiles[i].searchEngineID = current.searchEngineID
                    state.profiles[i].newTabAddress = current.newTabAddress
                    state.profiles[i].autoArchiveEnabledSince = current.autoArchiveEnabledSince
                    state.profiles[i].archiveAfterHours = current.archiveAfterHours
                }
            }
        }
        if state.spaces.contains(where: { $0.id == activeSpaceID }) { state.activeSpaceID = activeSpaceID }
        for i in state.spaces.indices {
            if let saved = selections[state.spaces[i].id] {
                let id = favoriteAliases[saved] ?? saved
                if state.canSelectTab(id,in:state.spaces[i].id) { state.spaces[i].selectedTabID = id }
            }
        }
        state.sidebarHidden = state.currentInterface == .classic ? classicSidebarHidden ?? sidebarHidden : sidebarHidden
        state.sidebarWidth = SidebarSizing.clamp(sidebarWidth)
        state.normalizeFavoriteTabs()
        return state.validated() ? state : nil
    }
}

struct WindowPersistence {
    let directory:URL
    private var file:URL { directory.appendingPathComponent("windows.json") }
    func load() -> [BrowserWindowRecord] {
        guard let info = try? file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]), info.isRegularFile == true, info.isSymbolicLink != true,
              (info.fileSize ?? Int.max) < 32*1024*1024, let data = try? Data(contentsOf:file),
              let records = try? JSONDecoder().decode([BrowserWindowRecord].self,from:data) else { return [] }
        return Array(records.prefix(20))
    }
    func save(_ controllers:[BrowserController]) throws {
        let records = controllers.filter { !$0.isPrivateWindow && $0.windowKind != .compact && !$0.isClosingWindow }.map(BrowserWindowRecord.init)
        let data = try JSONEncoder().encode(records)
        guard data.count <= 32*1024*1024 else { throw SessionStoreError.oversizedFile }
        if let values = try? file.resourceValues(forKeys:[.isSymbolicLinkKey]), values.isSymbolicLink == true { throw SessionStoreError.unsafePath }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try data.write(to:file,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
}
