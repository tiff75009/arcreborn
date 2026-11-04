import Foundation

/// Stable identities shared by the persistent tree and native drag destinations.
enum SidebarItem: Equatable, Hashable {
    case folder(String), tab(String)
}
struct SidebarTreeRow {
    var item: SidebarItem
    var depth: Int
    var parentID: String?
}
struct SidebarDestination: Equatable {
    var parentID: String?
    var before: SidebarItem?
    var temporary = false
}
/// View-only exceptions captured when a container folds; never serialized.
enum SidebarCollapseScope: Hashable { case space(String), folder(String) }
struct SidebarCollapseState {
    private(set) var retainedTabs: [SidebarCollapseScope:String] = [:]
    mutating func toggle(_ scope: SidebarCollapseScope, in session: inout BrowserSession) {
        let spaceID: String
        let closing: Bool
        switch scope {
        case .space(let id):
            guard let space = session.spaces.first(where: { $0.id == id }) else { return }
            spaceID = id; closing = space.foldersCollapsed != true
        case .folder(let id):
            guard let folder = session.folders.first(where: { $0.id == id }) else { return }
            spaceID = folder.spaceID; closing = !folder.collapsed
        }
        let selected = session.spaces.first(where: { $0.id == spaceID })?.selectedTabID
        let visible = session.sidebarTree(spaceID:spaceID,retainedTabs:retainedTabs)
        retainedTabs.removeValue(forKey:scope)
        switch scope {
        case .space(let id):
            if let i = session.spaces.firstIndex(where: { $0.id == id }) { session.spaces[i].foldersCollapsed = closing }
        case .folder(let id):
            if let i = session.folders.firstIndex(where: { $0.id == id }) { session.folders[i].collapsed = closing }
        }
        if closing, let id = selected, visible.contains(where: { $0.item == .tab(id) }),
           !session.sidebarTree(spaceID:spaceID,retainedTabs:retainedTabs).contains(where: { $0.item == .tab(id) }) {
            retainedTabs[scope] = id
        }
        // A moved/deleted tab or container cannot leave a dangling visual exception.
        retainedTabs = retainedTabs.filter { session.retainedSidebarTab($0.value,in:$0.key) != nil }
    }
}
extension BrowserSession {
    func sidebarChildren(spaceID: String, parentID: String?, temporary: Bool = false) -> [SidebarItem] {
        var ordered: [(SidebarItem, Int, Int)] = []
        for tab in tabs where tab.spaceID == spaceID && tab.folderID == parentID && !tab.favorite && tab.favoriteSourceID == nil && (parentID != nil || tab.pinned != temporary) {
            ordered.append((.tab(tab.id),tab.sidebarOrder ?? ordered.count,ordered.count))
        }
        if !temporary {
            for folder in folders where folder.spaceID == spaceID && folder.parentID == parentID {
                ordered.append((.folder(folder.id),folder.sidebarOrder ?? ordered.count,ordered.count))
            }
        }
        return ordered.sorted { $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 < $1.1 }.map { $0.0 }
    }
    func sidebarTree(spaceID: String, retainedTabs: [SidebarCollapseScope:String] = [:]) -> [SidebarTreeRow] {
        if spaces.first(where: { $0.id == spaceID })?.foldersCollapsed == true {
            let scope = SidebarCollapseScope.space(spaceID)
            guard let id = retainedTabs[scope], let tab = retainedSidebarTab(id,in:scope) else { return [] }
            return [SidebarTreeRow(item:.tab(id),depth:0,parentID:tab.folderID)]
        }
        let byID = Dictionary(uniqueKeysWithValues:folders.map { ($0.id,$0) })
        var pending = sidebarChildren(spaceID:spaceID,parentID:nil).reversed().map { SidebarTreeRow(item:$0,depth:0,parentID:nil) }
        var result: [SidebarTreeRow] = []
        var visited = Set<String>()
        while let row = pending.popLast() {
            result.append(row)
            guard case .folder(let id) = row.item, visited.insert(id).inserted,
                  let folder = byID[id] else { continue }
            if folder.collapsed {
                let scope = SidebarCollapseScope.folder(id)
                if let tabID = retainedTabs[scope], let tab = retainedSidebarTab(tabID,in:scope) {
                    result.append(SidebarTreeRow(item:.tab(tabID),depth:row.depth+1,parentID:tab.folderID))
                }
                continue
            }
            let children = folder.liveHost == nil ? sidebarChildren(spaceID:spaceID,parentID:id) : tabs(in:folder).map { SidebarItem.tab($0.id) }
            pending += children.reversed().map { SidebarTreeRow(item:$0,depth:row.depth+1,parentID:id) }
        }
        return result
    }
    fileprivate func retainedSidebarTab(_ id: String, in scope: SidebarCollapseScope) -> NativeTab? {
        guard let tab = tabs.first(where: { $0.id == id }), !tab.favorite, tab.favoriteSourceID == nil else { return nil }
        switch scope {
        case .space(let spaceID):
            return tab.spaceID == spaceID && spaces.contains(where: { $0.id == spaceID }) && (tab.pinned || tab.folderID != nil) ? tab : nil
        case .folder(let folderID):
            guard let folder = folders.first(where: { $0.id == folderID && $0.spaceID == tab.spaceID }) else { return nil }
            if folder.liveHost != nil { return tabs(in:folder).contains(where: { $0.id == id }) ? tab : nil }
            var parent = tab.folderID, visited = Set<String>()
            while let current = parent, visited.insert(current).inserted {
                if current == folderID { return tab }
                parent = folders.first(where: { $0.id == current })?.parentID
            }
            return nil
        }
    }
    func canMoveSidebarItem(_ item: SidebarItem, spaceID: String, to destination: SidebarDestination) -> Bool {
        guard spaces.contains(where: { $0.id == spaceID }) else { return false }
        if destination.temporary && destination.parentID != nil { return false }
        if let parentID = destination.parentID {
            guard let parent = folders.first(where: { $0.id == parentID }), parent.spaceID == spaceID, parent.liveHost == nil else { return false }
        }
        switch item {
        case .folder(let id):
            guard !destination.temporary, folders.contains(where: { $0.id == id && $0.spaceID == spaceID }) else { return false }
            var ancestor = destination.parentID
            var visited = Set<String>()
            while let current = ancestor {
                guard current != id, visited.insert(current).inserted else { return false }
                ancestor = folders.first(where: { $0.id == current })?.parentID
            }
        case .tab(let id):
            guard tabs.contains(where: { $0.id == id && ($0.spaceID == spaceID || $0.favorite) }) else { return false }
        }
        if let before = destination.before {
            guard before != item, sidebarChildren(spaceID:spaceID,parentID:destination.parentID,temporary:destination.temporary).contains(before) else { return false }
        }
        return true
    }
    @discardableResult mutating func moveSidebarItem(_ item: SidebarItem, spaceID: String, to destination: SidebarDestination) -> Bool {
        guard canMoveSidebarItem(item,spaceID:spaceID,to:destination) else { return false }
        if case .tab(let id) = item, let tab = tabs.first(where: { $0.id == id }), tab.favorite && tab.spaceID != spaceID {
            var candidate = self
            guard let local = candidate.localFavoriteTab(id,spaceID:spaceID), let index = candidate.tabs.firstIndex(where: { $0.id == id }) else { return false }
            candidate.tabs[index].favorite = false; candidate.tabs[index].pinned = false
            candidate.detachFavoriteReferences(to:id)
            guard candidate.moveSidebarItem(.tab(local),spaceID:spaceID,to:destination) else { return false }
            self = candidate; return true
        }
        var peers = sidebarChildren(spaceID:spaceID,parentID:destination.parentID,temporary:destination.temporary).filter { $0 != item }
        let index = destination.before.flatMap { peers.firstIndex(of:$0) } ?? peers.count
        peers.insert(item,at:index)
        switch item {
        case .folder(let id):
            guard let i = folders.firstIndex(where: { $0.id == id }) else { return false }
            folders[i].parentID = destination.parentID
        case .tab(let id):
            guard let i = tabs.firstIndex(where: { $0.id == id }) else { return false }
            if tabs[i].favorite { detachFavoriteReferences(to:id) }
            tabs[i].favoriteSourceID = nil
            tabs[i].folderID = destination.parentID; tabs[i].pinned = !destination.temporary; tabs[i].favorite = false
        }
        orderSidebarItems(peers)
        if let parentID = destination.parentID, let i = folders.firstIndex(where: { $0.id == parentID }) { folders[i].collapsed = false }
        if !destination.temporary, let i = spaces.firstIndex(where: { $0.id == spaceID }) { spaces[i].foldersCollapsed = false }
        return true
    }
    private mutating func orderSidebarItems(_ items: [SidebarItem]) {
        for (order,item) in items.enumerated() {
            switch item {
            case .folder(let id): if let i = folders.firstIndex(where: { $0.id == id }) { folders[i].sidebarOrder = order }
            case .tab(let id): if let i = tabs.firstIndex(where: { $0.id == id }) { tabs[i].sidebarOrder = order }
            }
        }
    }
    /// Removing a container preserves its contents and promotes them in place.
    mutating func removeFolder(_ id: String) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        var peers = sidebarChildren(spaceID:folder.spaceID,parentID:folder.parentID)
        let index = peers.firstIndex(of:.folder(id)) ?? peers.count
        peers.removeAll { $0 == .folder(id) }
        let children = folder.liveHost == nil ? sidebarChildren(spaceID:folder.spaceID,parentID:id) : []
        peers.insert(contentsOf:children,at:min(index,peers.count))
        for i in folders.indices where folders[i].parentID == id { folders[i].parentID = folder.parentID }
        for i in tabs.indices where tabs[i].folderID == id { tabs[i].folderID = folder.parentID; tabs[i].pinned = true }
        for i in closedTabs.indices where closedTabs[i].folderID == id { closedTabs[i].folderID = folder.parentID }
        folders.removeAll { $0.id == id }
        orderSidebarItems(peers)
    }
}
