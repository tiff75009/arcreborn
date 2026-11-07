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
        var order = BrowserSession.fresh()
        let space = order.activeSpaceID
        let a = order.createTab(), b = order.createTab(), c = order.createTab()
        func temporary(_ state:BrowserSession) -> [SidebarItem] {
            state.sidebarChildren(spaceID:space,parentID:nil,temporary:true)
        }
        expect(temporary(order) == [c,b,a].map(SidebarItem.tab),"New tabs appear first")
        // Mix legacy implicit positions with explicit drag positions.
        for i in order.tabs.indices { order.tabs[i].sidebarOrder = nil }
        _ = order.moveSidebarItem(.tab(c),spaceID:space,to:.init(parentID:nil,before:.tab(b),temporary:true))
        let relative = order.createTab(above:b)
        expect(temporary(order) == [a,c,relative,b].map(SidebarItem.tab),"Insert above an inactive, manually ordered tab")
        let plain = order.reserveExtensionTab(sourceTabID:c,active:false,pinned:false,index:-1)!
        expect(temporary(order).first == .tab(plain.id),"Implicit browser and extension tabs go to the top")
        let link = order.reserveExtensionTab(sourceTabID:c,active:false,pinned:false,index:-1,aboveSource:true)!
        expect(temporary(order) == [plain.id,a,link.id,c,relative,b].map(SidebarItem.tab) && order.spaces[0].selectedTabID == relative,
               "The link menu inserts above its source and preserves background selection")
        let indexed = order.reserveExtensionTab(sourceTabID:a,active:false,pinned:false,index:2)!
        expect(temporary(order)[2] == .tab(indexed.id),"Explicit extension positions take precedence")
        order.folders = [.init(id:"folder",spaceID:space,name:"Folder",collapsed:false)]
        _ = order.moveSidebarItem(.tab(a),spaceID:space,to:.init(parentID:"folder",before:nil))
        let sibling = order.createTab(above:a)
        expect(order.sidebarChildren(spaceID:space,parentID:"folder") == [sibling,a].map(SidebarItem.tab),"Context action stays in its folder")
        _ = order.mergeSplit(b,onto:c)
        let splitPeer = order.createTab(above:b)
        let peers = temporary(order)
        expect(peers.firstIndex(of:.tab(splitPeer))! + 1 == min(peers.firstIndex(of:.tab(c))!,peers.firstIndex(of:.tab(b))!),
               "A split occupies one sidebar row")
        let saved = try! JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(order))
        expect(temporary(saved) == peers && saved.validated(),"Order survives reopening the session")
        print("PASS: tab insertion order, relative context actions, source selection, rollback, folders, splits and persistence")
    }
}
