import Foundation

@main struct SplitStateTests {
    static func require(_ value:Bool,_ message:String) {
        if !value { fatalError(message) }
    }
    static func main() throws {
        var session = BrowserSession.fresh()
        let ids = (0..<5).map { session.createTab(url:"https://example.com/\($0)") }
        require(session.mergeSplit(ids[1],onto:ids[0]),"create pair")
        require(session.mergeSplit(ids[2],onto:ids[0]),"third pane")
        require(session.mergeSplit(ids[3],onto:ids[0]),"fourth pane")
        let snapshot = try JSONEncoder().encode(session)
        require(!session.mergeSplit(ids[4],onto:ids[0]),"reject fifth pane")
        require(session.splitGroup(containing:ids[0])?.tabIDs.count == 4,"limit preserves group")
        let restored = try JSONDecoder().decode(BrowserSession.self,from:snapshot)
        require(restored.splitGroups == session.splitGroups,"persist groups")
        session.closeTab(id:ids[0])
        require(session.splitGroup(containing:ids[1])?.tabIDs.count == 3,"closing first preserves peers")
        session.detachSplitTab(ids[1])
        require(session.tabs.contains { $0.id == ids[1] },"separating preserves tab")
        require(session.splitGroup(containing:ids[2])?.tabIDs.count == 2,"separating preserves other pair")
        session.detachSplitTab(ids[2])
        require(session.splitGroups?.isEmpty == true,"single member becomes ordinary tab")
        let otherSpace = session.createSpace(name:"Other",color:"#223344",icon:"",profileID:session.spaces[0].profileID)
        let other = session.createTab(spaceID:otherSpace)
        require(!session.mergeSplit(other,onto:ids[4]),"cross-space merge rejected")
        var legacy = try JSONSerialization.jsonObject(with:snapshot) as! [String:Any]
        legacy.removeValue(forKey:"splitGroups"); legacy.removeValue(forKey:"splitShortcuts")
        let old = try JSONDecoder().decode(BrowserSession.self,from:JSONSerialization.data(withJSONObject:legacy))
        require(old.splitGroups == nil,"legacy profile loads")
        for before in [false,true] {
            var order = BrowserSession.fresh()
            let tabs = (0..<5).map { order.createTab(url:"https://example.com/route/\($0)") }
            for (i,id) in tabs.enumerated() {
                let index = order.tabs.firstIndex(where:{ $0.id == id })!
                order.tabs[index].sidebarOrder = i
            }
            let urls = Dictionary(uniqueKeysWithValues:order.tabs.map { ($0.id,$0.url) })
            require(order.mergeSplit(tabs[0],onto:tabs[3],sourceBefore:before),"merge source above destination")
            let pair = before ? [tabs[0],tabs[3]] : [tabs[3],tabs[0]]
            require(order.splitGroup(containing:tabs[3])?.tabIDs == pair,"pane order matches the preview side")
            let displayed = order.sidebarChildren(spaceID:order.activeSpaceID,parentID:nil,temporary:true)
            require(displayed == [.tab(tabs[1]),.tab(tabs[2])] + pair.map(SidebarItem.tab) + [.tab(tabs[4])],"the merged row remains at the destination, not the source")
            require(order.tabs.allSatisfy { urls[$0.id] == $0.url },"merging never modifies URLs")
            let roundTrip = try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(order))
            require(roundTrip.splitGroup(containing:tabs[3])?.tabIDs == pair,"left/right pane order persists")
        }
        for size in 2...4 {
            for grabbed in 0..<size {
                var state = BrowserSession.fresh()
                let space = state.activeSpaceID
                let ids = Array((0..<(size+3)).map { state.createTab(url:"https://example.com/group/\($0)") }.reversed())
                let members = Array(ids.prefix(size))
                let tail = Array(ids.dropFirst(size))
                let selected = members.last!
                for id in members.dropFirst() { require(state.mergeSplit(id,onto:ids[0]),"fixture split") }
                state.splitGroups![0].name = "Café"
                state.splitGroups![0].vertical = true
                state.splitGroups![0].weights = (1...size).map { 2 * Double($0) / Double(size*(size+1)) }
                state.selectTab(id:selected)
                state.folders = [NativeFolder(id:"folder",spaceID:space,name:"Dossier",collapsed:true)]
                let original = state.splitGroups
                let urls = state.tabs.map(\.url)
                let chip = SidebarItem.tab(members[grabbed])
                let end = SidebarDestination(parentID:nil,before:nil,temporary:true)
                let before = SidebarDestination(parentID:nil,before:.tab(tail[1]),temporary:true)
                let peers = { (s: BrowserSession) in s.sidebarChildren(spaceID:space,parentID:nil,temporary:true) }
                require(state.moveSidebarItem(chip,spaceID:space,to:end),"move group to end from every pane")
                require(peers(state) == (tail + members).map(SidebarItem.tab),"group stays contiguous and ordered")
                let first = state.sidebarEdgeDestination(for:chip,spaceID:space,first:true)!
                require(state.moveSidebarItem(chip,spaceID:space,to:first),"overshooting the top moves every pane to the start")
                require(peers(state) == (members + tail).map(SidebarItem.tab),"first row after overshooting")
                let last = state.sidebarEdgeDestination(for:chip,spaceID:space,first:false)!
                require(state.moveSidebarItem(chip,spaceID:space,to:last),"overshooting the bottom appends the group")
                require(peers(state) == (tail + members).map(SidebarItem.tab),"last row after overshooting")
                require(state.moveSidebarItem(chip,spaceID:space,to:before),"move back between rows")
                require(peers(state) == ([tail[0]] + members + tail.dropFirst()).map(SidebarItem.tab),"precise insertion")
                require(state.nextSidebarRow(after:.tab(members[0]),in:peers(state)) == .tab(tail[1]),"drop below a split skips its hidden peers")
                let snapshot = state
                require(!state.moveSidebarItem(chip,spaceID:space,to:.init(parentID:nil,before:.tab(selected),temporary:true)),"reject own group as anchor")
                require(!state.moveToFavorites(members[grabbed],spaceID:space,at:0),"a favorite drop cannot extract a pane")
                require(state == snapshot,"invalid drop has no side effects")
                require(state.moveSidebarItem(chip,spaceID:space,to:.init(parentID:"folder",before:nil)),"drop complete group inside a folder")
                require(state.sidebarEdgeDestination(for:chip,spaceID:space,first:false) == .init(parentID:"folder",before:nil),"overshoot keeps a folder group in its own list")
                require(state.sidebarChildren(spaceID:space,parentID:"folder") == members.map(SidebarItem.tab),"all members in folder")
                require(state.moveSidebarItem(chip,spaceID:space,to:.init(parentID:nil,before:.folder("folder"))),"move group into pinned section")
                require(state.moveSidebarItem(chip,spaceID:space,to:end),"return group to ordinary tabs")
                require(state.splitGroups == original && state.spaces.first?.selectedTabID == selected,"preserve identity, geometry, and focus")
                require(state.tabs.map(\.url) == urls,"preserve original pages")
                let restored = try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(state))
                require(restored.splitGroups == original && peers(restored) == peers(state),"reopen with same group and order")
                state.detachSplitTab(members[grabbed])
                require(state.splitGroup(containing:members[grabbed]) == nil,"explicit separation remains available")
            }
        }
        print("Split state: whole-group moves from every pane, folders, pinned tabs, favorites, persistence, focus and explicit separation passed")
    }
}
