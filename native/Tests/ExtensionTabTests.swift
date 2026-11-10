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
        var returns = BrowserSession.fresh()
        let returnSpace = returns.activeSpaceID
        let origin = returns.createTab(), unrelated = returns.createTab(), recent = returns.createTab()
        returns.selectTab(id:origin)
        let manual = returns.createTab()
        expect(returns.sidebarChildren(spaceID:returnSpace,parentID:nil,temporary:true).first == .tab(manual),
               "Manual new tabs stay at the top when the selected source is lower")
        returns.closeTab(id:manual)
        expect(returns.spaces[0].selectedTabID == origin,"Closing a manual new tab returns to its source, not the last array entry")
        let child = returns.createTab(above:unrelated)
        let sidebar = returns.sidebarChildren(spaceID:returnSpace,parentID:nil,temporary:true)
        expect(sidebar.firstIndex(of:.tab(child))!+1 == sidebar.firstIndex(of:.tab(unrelated))!,
               "A link opens directly above its actual source")
        returns.closeTab(id:child)
        expect(returns.spaces[0].selectedTabID == unrelated,"An inactive source remains the return destination")
        returns.selectTab(id:origin)
        let intermediate = returns.createTab(above:origin)
        let descendant = returns.createTab(above:intermediate)
        returns.closeTab(id:intermediate)
        expect(returns.spaces[0].selectedTabID == descendant,"Closing a background opener never steals selection")
        returns.closeTab(id:descendant)
        expect(returns.spaces[0].selectedTabID == origin,"A closed intermediate opener falls back to its surviving ancestor")
        let reordered = returns.createTab(above:origin)
        _ = returns.moveSidebarItem(.tab(reordered),spaceID:returnSpace,to:.init(parentID:nil,before:.tab(recent),temporary:true))
        var reopened = try! JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(returns))
        reopened.closeTab(id:reordered)
        expect(reopened.spaces[0].selectedTabID == origin && reopened.validated(),"Return destination survives reordering and session restart")
        let reserved = returns.reserveExtensionTab(sourceTabID:unrelated,active:true,pinned:false,index:0)!
        returns.closeTab(id:reserved.id)
        expect(returns.spaces[0].selectedTabID == unrelated,"An explicitly positioned engine tab returns to its actual source")
        let backgroundReturn = returns.reserveExtensionTab(sourceTabID:origin,active:false,pinned:false,index:-1,aboveSource:true)!
        returns.closeTab(id:backgroundReturn.id)
        expect(returns.spaces[0].selectedTabID == unrelated,"Closing a background link preserves the current selection")
        _ = returns.moveToFavorites(origin,spaceID:returnSpace,at:0)
        let displaySpace = returns.createSpace(name:"Shared",color:"#334455",icon:"◈")
        returns.selectTab(id:origin)
        let favoriteLink = returns.createTab(spaceID:displaySpace,above:origin)
        returns.closeTab(id:favoriteLink)
        expect(returns.activeSpaceID == displaySpace && returns.spaces.last?.selectedTabID == origin,
               "A link returns to a shared favorite without leaving its displaying space")
        let foreignSpace = returns.createSpace(name:"Isolated",color:"#334455",icon:"◈",profileID:returns.profiles[0].id)
        let foreign = returns.createTab(spaceID:foreignSpace)
        returns.selectTab(id:unrelated)
        let detached = returns.createTab()
        returns.tabs[returns.tabs.firstIndex(where:{ $0.id == detached })!].openerTabID = foreign
        returns.closeTab(id:detached)
        expect(returns.activeSpaceID == returnSpace && returns.spaces[0].selectedTabID != foreign && returns.validated(),
               "A moved or unavailable origin never selects an unrelated space")
        print("PASS: tab insertion order, relative context actions, source selection, rollback, folders, splits and persistence")
    }
}
