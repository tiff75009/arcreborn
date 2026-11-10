import Foundation

/// Rollback information for a native tab reserved while Chromium creates its
/// browsing context. This is transient and never saved in the session.
struct ExtensionTabReservation {
    let id: String
    let spaceID: String
    let previousActiveSpaceID: String
    let previousSelectedTabID: String?
    let previousFoldersCollapsed: Bool?
}

extension BrowserSession {
    mutating func reserveExtensionTab(sourceTabID: String, active: Bool,
                                     pinned: Bool, index: Int, aboveSource: Bool = false) -> ExtensionTabReservation? {
        guard let source = tabs.first(where: { $0.id == sourceTabID }),
              let spaceIndex = spaces.firstIndex(where: { $0.id == browsingSpaceID(for:source) }) else { return nil }
        let spaceID = spaces[spaceIndex].id
        let previousSpace = activeSpaceID
        let previousTab = spaces[spaceIndex].selectedTabID
        let previousCollapsed = spaces[spaceIndex].foldersCollapsed
        let id = createTab(url: "about:blank", spaceID: spaceID, above:aboveSource ? sourceTabID : nil, openerTabID:sourceTabID)
        guard !id.isEmpty else { return nil }
        if !active {
            activeSpaceID = previousSpace
            spaces[spaceIndex].selectedTabID = previousTab
        }
        // A pinned Chrome tab belongs among pinned tabs, never in Favorites.
        if pinned || index >= 0 {
            let peers = sidebarChildren(spaceID:spaceID,parentID:nil,temporary:!pinned).filter { $0 != .tab(id) }
            let insertion = min(max(index,0),peers.count)
            let before = insertion < peers.count ? peers[insertion] : nil
            _ = moveSidebarItem(.tab(id),spaceID:spaceID,to:SidebarDestination(parentID:nil,before:before,temporary:!pinned))
        }
        if !active { spaces[spaceIndex].foldersCollapsed = previousCollapsed }
        return ExtensionTabReservation(id: id, spaceID: spaceID,
                                       previousActiveSpaceID: previousSpace,
                                       previousSelectedTabID: previousTab,
                                       previousFoldersCollapsed: previousCollapsed)
    }

    mutating func cancelExtensionTab(_ reservation: ExtensionTabReservation) {
        tabs.removeAll { $0.id == reservation.id }
        if let i = spaces.firstIndex(where: { $0.id == reservation.spaceID }),
           spaces[i].selectedTabID == reservation.id {
            spaces[i].foldersCollapsed = reservation.previousFoldersCollapsed
            spaces[i].selectedTabID = reservation.previousSelectedTabID.flatMap { previous in
                canSelectTab(previous,in:reservation.spaceID) ? previous : nil
            }
            if activeSpaceID == reservation.spaceID,
               spaces.contains(where: { $0.id == reservation.previousActiveSpaceID }) {
                activeSpaceID = reservation.previousActiveSpaceID
            }
        }
    }
}
