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
        print("Split state: 11 checks passed")
    }
}
