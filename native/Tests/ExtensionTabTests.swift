import Foundation

@main struct ExtensionTabTests {
    static func expect(_ value: Bool, _ description: String) {
        guard value else { fatalError(description) }
    }
    static func main() {
        var session = BrowserSession.fresh()
        let firstSpace = session.activeSpaceID
        let source = session.createTab(url: "https://example.com/")
        session.spaces[0].foldersCollapsed = true
        let secondSpace = session.createSpace(name: "Second", color: "#334455", icon: "◈")
        let secondTab = session.createTab(url: "https://example.org/", spaceID: secondSpace)
        let background = session.reserveExtensionTab(sourceTabID: source, active: false, pinned: true, index: 0)!
        expect(session.activeSpaceID == secondSpace && session.spaces[1].selectedTabID == secondTab,
               "Background creation must not switch spaces or select the new tab")
        expect(session.spaces[0].selectedTabID == source && session.spaces[0].foldersCollapsed == true,
               "Background creation must preserve the source space's selection and collapse state")
        let newTab = session.tabs.first { $0.id == background.id }!
        expect(newTab.spaceID == firstSpace && newTab.pinned && !newTab.favorite,
               "Pinned extension tabs remain in the source space, outside Favorites")
        expect(session.sidebarChildren(spaceID: firstSpace, parentID: nil).first == .tab(background.id),
               "Requested insertion position is honored")
        session.cancelExtensionTab(background)
        expect(!session.tabs.contains { $0.id == background.id } && session.closedTabs.isEmpty,
               "Failed creation must leave no phantom tab or archive entry")
        let foreground = session.reserveExtensionTab(sourceTabID: source, active: true, pinned: false, index: -1)!
        expect(session.activeSpaceID == firstSpace && session.spaces[0].selectedTabID == foreground.id,
               "Foreground creation selects its tab in the source space")
        session.cancelExtensionTab(foreground)
        expect(session.activeSpaceID == secondSpace && session.spaces[0].selectedTabID == source && session.validated(),
               "Failure restores valid selections across spaces")
        let before = session
        expect(session.reserveExtensionTab(sourceTabID: "missing", active: true, pinned: false, index: 0) == nil && session == before,
               "Unknown sources must not mutate the session")
        _ = session.moveToFavorites(source,spaceID:firstSpace,at:0)
        session.selectTab(id:source)
        let sharedPopup = session.reserveExtensionTab(sourceTabID:source,active:true,pinned:false,index:-1)!
        expect(sharedPopup.spaceID == secondSpace && session.activeSpaceID == secondSpace,
               "A link from a shared favorite belongs to the displaying space")
        session.cancelExtensionTab(sharedPopup)
        expect(session.spaces[1].selectedTabID == source && session.validated(),
               "Failed creation restores the shared favorite selection")
        print("Extension tab state: 10 checks passed")
    }
}
