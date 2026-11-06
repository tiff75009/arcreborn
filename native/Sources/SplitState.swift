import Foundation

struct NativeSplitGroup: Codable, Equatable {
    var id = UUID().uuidString
    var tabIDs: [String]
    var vertical = false
    var weights: [Double] = []
    var name: String? = nil
    var icon: String? = nil
}
struct SplitKeyBinding: Codable, Equatable {
    var key: String
    var modifiers: UInt
}
extension BrowserSession {
    func splitGroup(containing id: String) -> NativeSplitGroup? {
        splitGroups?.first { $0.tabIDs.contains(id) }
    }
    mutating func normalizeSplits() {
        var used = Set<String>()
        splitGroups = (splitGroups ?? []).compactMap { original in
            var group = original
            guard let first = group.tabIDs.compactMap({ id in tabs.first(where: { $0.id == id }) }).first else { return nil }
            group.tabIDs = group.tabIDs.filter { id in
                guard !used.contains(id), let tab = tabs.first(where: { $0.id == id }) else { return false }
                return !tab.favorite && tab.spaceID == first.spaceID && tab.folderID == first.folderID && tab.pinned == first.pinned
            }
            guard (2...4).contains(group.tabIDs.count), Set(group.tabIDs).count == group.tabIDs.count else { return nil }
            used.formUnion(group.tabIDs)
            if group.weights.count != group.tabIDs.count || group.weights.contains(where: { !$0.isFinite || $0 <= 0 }) {
                group.weights = Array(repeating: 1 / Double(group.tabIDs.count), count: group.tabIDs.count)
            } else {
                let total = group.weights.reduce(0,+); group.weights = group.weights.map { $0 / total }
            }
            return group
        }
    }
    func splitMergeIDs(_ source: String, onto target: String, sourceBefore:Bool = false, sourceOnly:Bool = false) -> [String]? {
        guard source != target, let a = tabs.first(where: { $0.id == source }), let b = tabs.first(where: { $0.id == target }),
              a.spaceID == b.spaceID, !a.favorite, !b.favorite else { return nil }
        let destination = splitGroup(containing: target)?.tabIDs ?? [target]
        guard !destination.contains(source) else { return nil }
        let incoming = sourceOnly ? [source] : (splitGroup(containing: source)?.tabIDs ?? [source])
        return sourceBefore ? incoming + destination : destination + incoming
    }
    @discardableResult mutating func mergeSplit(_ source: String, onto target: String, sourceBefore:Bool = false, sourceOnly:Bool = false) -> Bool {
        guard let ids = splitMergeIDs(source, onto: target, sourceBefore:sourceBefore, sourceOnly:sourceOnly), ids.count <= 4,
              let destination = tabs.first(where: { $0.id == target }) else { return false }
        // A chip represents one pane, not its entire group. Validate first, so
        // rejected drops leave both groups untouched, then detach only this pane.
        if sourceOnly { detachSplitTab(source) }
        var group = splitGroup(containing: target) ?? NativeSplitGroup(tabIDs: [target])
        let destinationIDs = Set(group.tabIDs), mergedIDs = Set(ids)
        let peers = sidebarChildren(spaceID:destination.spaceID,parentID:destination.folderID,temporary:!destination.pinned)
        let anchor = peers.firstIndex { if case .tab(let id) = $0 { return destinationIDs.contains(id) }; return false } ?? peers.count
        let merged: (SidebarItem) -> Bool = { if case .tab(let id) = $0 { return mergedIDs.contains(id) }; return false }
        let insertion = peers.prefix(anchor).filter { !merged($0) }.count
        var ordered = peers.filter { !merged($0) }
        ordered.insert(contentsOf:ids.map(SidebarItem.tab),at:insertion)
        splitGroups = (splitGroups ?? []).filter { !($0.tabIDs.contains(source) || $0.tabIDs.contains(target)) }
        for id in ids {
            if let index = tabs.firstIndex(where: { $0.id == id }) {
                tabs[index].folderID = destination.folderID; tabs[index].pinned = destination.pinned
            }
        }
        // The preview is anchored on the destination row, even if the incoming
        // tab used to precede it. Pane order follows the chosen left/right side.
        for (order,item) in ordered.enumerated() {
            switch item {
            case .tab(let id): if let i = tabs.firstIndex(where:{ $0.id == id }) { tabs[i].sidebarOrder = order }
            case .folder(let id): if let i = folders.firstIndex(where:{ $0.id == id }) { folders[i].sidebarOrder = order }
            }
        }
        group.tabIDs = ids; group.weights = []
        splitGroups?.append(group); normalizeSplits(); selectTab(id: target)
        return true
    }
    mutating func detachSplitTab(_ id: String) {
        // Closing an ordinary tab must not normalize nil into [] or reset the
        // divider weights of unrelated split groups.
        guard let groups = splitGroups else { return }
        let affected = groups.indices.filter { groups[$0].tabIDs.contains(id) }
        guard !affected.isEmpty else { return }
        for i in affected { splitGroups?[i].tabIDs.removeAll { $0 == id }; splitGroups?[i].weights = [] }
        normalizeSplits()
    }
}
