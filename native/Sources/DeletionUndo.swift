import Foundation

/// A deletion delta, rather than a whole-session rewind: unrelated later edits survive.
struct DeletionUndo {
    enum Kind { case tabs, space }
    let kind: Kind
    private let spaces: [(Int,NativeSpace)]
    private let folders: [(Int,NativeFolder)]
    private let tabs: [(Int,NativeTab)]
    private let history: [(Int,NativeTab)]
    private let movedFavorites: [(NativeTab,NativeTab)]
    private let selections: [(String,String?,String?)]
    private let activeBefore: String
    private let activeAfter: String
    var removedTabIDs: Set<String> { Set(tabs.map { $0.1.id }) }
    var reloadTabIDs: Set<String> { Set(movedFavorites.map { $0.0.id }) }
    var isEmpty: Bool { spaces.isEmpty && tabs.isEmpty }
    init(kind: Kind, before: BrowserSession, after: BrowserSession) {
        self.kind = kind
        spaces = before.spaces.enumerated().compactMap { i,s in after.spaces.contains(where: { $0.id == s.id }) ? nil : (i,s) }
        folders = before.folders.enumerated().compactMap { i,f in after.folders.contains(where: { $0.id == f.id }) ? nil : (i,f) }
        tabs = before.tabs.enumerated().compactMap { i,t in after.tabs.contains(where: { $0.id == t.id }) ? nil : (i,t) }
        history = before.closedTabs.enumerated().compactMap { i,t in after.closedTabs.contains(where: { $0.id == t.id }) ? nil : (i,t) }
        movedFavorites = before.tabs.compactMap { old in
            guard old.favorite, let new = after.tabs.first(where: { $0.id == old.id }), old.spaceID != new.spaceID else { return nil }
            return (old,new)
        }
        selections = before.spaces.compactMap { old in
            guard let new = after.spaces.first(where: { $0.id == old.id }), old.selectedTabID != new.selectedTabID else { return nil }
            return (old.id,old.selectedTabID,new.selectedTabID)
        }
        activeBefore = before.activeSpaceID; activeAfter = after.activeSpaceID
    }
    func restoring(_ current: BrowserSession) -> BrowserSession? {
        var result = current
        for (index,space) in spaces where !result.spaces.contains(where: { $0.id == space.id }) {
            result.spaces.insert(space,at:min(index,result.spaces.count))
        }
        for (index,folder) in folders where !result.folders.contains(where: { $0.id == folder.id }) {
            result.folders.insert(folder,at:min(index,result.folders.count))
        }
        for (index,tab) in tabs where !result.tabs.contains(where: { $0.id == tab.id }) {
            result.tabs.insert(tab,at:min(index,result.tabs.count))
        }
        for (old,new) in movedFavorites {
            if let index = result.tabs.firstIndex(where: { $0.id == old.id && $0.favorite && $0.spaceID == new.spaceID }) {
                result.tabs[index].spaceID = old.spaceID
                result.tabs[index].folderID = old.folderID
            }
        }
        let restoredIDs = removedTabIDs
        result.closedTabs.removeAll { restoredIDs.contains($0.id) }
        for (index,tab) in history where !result.closedTabs.contains(where: { $0.id == tab.id }) && !result.tabs.contains(where: { $0.id == tab.id }) {
            result.closedTabs.insert(tab,at:min(index,result.closedTabs.count))
        }
        if result.closedTabs.count > 50 { result.closedTabs = Array(result.closedTabs.suffix(50)) }
        for (id,old,new) in selections {
            if let index = result.spaces.firstIndex(where: { $0.id == id && $0.selectedTabID == new }),
               old == nil || result.tabs.contains(where: { $0.id == old && $0.spaceID == id }) {
                result.spaces[index].selectedTabID = old
            }
        }
        if result.activeSpaceID == activeAfter && result.spaces.contains(where: { $0.id == activeBefore }) { result.activeSpaceID = activeBefore }
        return result.validated() ? result : nil
    }
}
