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
        for before in [false,true] {
            var panes = BrowserSession.fresh()
            let ids = (0..<6).map { panes.createTab(url:"https://example.com/extract/\($0)") }
            require(panes.mergeSplit(ids[1],onto:ids[0]),"pair for extraction")
            require(panes.mergeSplit(ids[2],onto:ids[0]),"triple for extraction")
            let originalID = panes.splitGroup(containing:ids[0])!.id
            let originalCount = panes.tabs.count
            require(panes.splitMergeIDs(ids[1],onto:ids[3],sourceOnly:true)?.count == 2,"preview counts one incoming pane")
            require(panes.mergeSplit(ids[1],onto:ids[3],sourceBefore:before,sourceOnly:true),"extract exactly one pane onto another tab")
            require(panes.splitGroup(containing:ids[0])?.id == originalID,"unmoved peers keep their group")
            require(panes.splitGroup(containing:ids[0])?.tabIDs == [ids[0],ids[2]],"original group loses only the dragged pane")
            require(panes.splitGroup(containing:ids[3])?.tabIDs == (before ? [ids[1],ids[3]] : [ids[3],ids[1]]),"target receives one pane, not the source group")
            require(panes.tabs.count == originalCount,"no tab is created during extraction")
            let priorGroups = panes.splitGroups
            require(!panes.mergeSplit(ids[1],onto:ids[3],sourceOnly:true),"dropping onto own group does not merge it again")
            require(panes.splitGroups == priorGroups,"rejected merge does not detach anything")
            panes.detachSplitTab(ids[1])
            require(panes.moveSidebarItem(.tab(ids[1]),spaceID:panes.activeSpaceID,to:SidebarDestination(parentID:nil,before:.tab(ids[5]),temporary:true)),"extract into the ordinary list")
            require(panes.splitGroup(containing:ids[1]) == nil && panes.splitGroup(containing:ids[3]) == nil,"both sides of the former pair become standalone tabs")
            require(panes.splitGroup(containing:ids[0])?.tabIDs == [ids[0],ids[2]],"unrelated group remains intact")
        }
        for size in 2...4 {
            var panes = BrowserSession.fresh()
            let ids = (0..<8).map { panes.createTab(url:"https://example.com/capacity/\($0)") }
            for i in 1..<size { require(panes.mergeSplit(ids[i],onto:ids[0]),"source group for capacity check") }
            for i in 5...7 { require(panes.mergeSplit(ids[i],onto:ids[4]),"full destination group") }
            let unchanged = panes.splitGroups
            let urls = panes.tabs.map { ($0.id,$0.url) }
            require(!panes.mergeSplit(ids[0],onto:ids[4],sourceOnly:true),"reject pane into full destination")
            require(panes.splitGroups == unchanged,"rejected extraction keeps source and target intact")
            panes.detachSplitTab(ids[7])
            require(panes.mergeSplit(ids[0],onto:ids[4],sourceOnly:true),"one extracted pane fits in a triple")
            require(panes.splitGroup(containing:ids[4])?.tabIDs == [ids[4],ids[5],ids[6],ids[0]],"only the dragged pane joins the destination")
            require(panes.splitGroup(containing:ids[1])?.tabIDs == (size == 2 ? nil : Array(ids[1..<size])),"remaining source panes stay together")
            require(panes.tabs.count == urls.count && zip(panes.tabs,urls).allSatisfy { $0.id == $1.0 && $0.url == $1.1 },"extraction preserves every tab and URL")
        }
        print("Split state: pane extraction, no duplication, intact peers, legacy checks, left/right drop order, destination anchoring, persistence and unchanged URLs passed")
    }
}
