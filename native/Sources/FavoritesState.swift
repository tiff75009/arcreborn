import Foundation
import CoreGraphics

struct FavoriteGridLayout {
    static let gap: Double = 8
    static let tileHeight: Double = 46
    let count: Int
    var columns: Int { min(3,max(1,count)) }
    var height: Double { count == 0 ? 0 : Double((count+2)/3)*54-8 }
    func frame(at index: Int, width: Double) -> CGRect {
        let cellWidth = max(1,(width-Double(columns-1)*Self.gap)/Double(columns))
        return CGRect(x:Double(index%columns)*(cellWidth+Self.gap),y:Double(index/columns)*54,width:cellWidth,height:Self.tileHeight)
    }
    func insertionIndex(x: Double, y: Double, width: Double) -> Int {
        let cellWidth = max(1,(width-Double(columns-1)*Self.gap)/Double(columns))
        let column = max(0,min(columns-1,Int(x/(cellWidth+Self.gap))))
        let row = max(0,Int(y/54))
        return min(max(0,count-1),row*columns+column)
    }
}
extension BrowserSession {
    func favoriteTabs(spaceID: String) -> [NativeTab] {
        tabs.enumerated().filter { $0.element.favorite }.sorted {
            let lhs = $0.element.favoriteOrder ?? $0.offset, rhs = $1.element.favoriteOrder ?? $1.offset
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }.map(\.element)
    }
    /// A shared favorite opens in the current space's profile, without changing spaces.
    mutating func localFavoriteTab(_ id: String, spaceID: String) -> String? {
        guard let favorite = tabs.first(where: { $0.id == id && $0.favorite }), spaces.contains(where: { $0.id == spaceID }) else { return nil }
        if favorite.spaceID == spaceID { return id }
        if let existing = tabs.first(where: { $0.spaceID == spaceID && $0.favoriteSourceID == id }) { return existing.id }
        guard tabs.count < 5000 else { return nil }
        let localID = UUID().uuidString
        tabs.append(NativeTab(id:localID,spaceID:spaceID,url:favorite.url,title:favorite.title,pinned:true,favorite:false,folderID:nil,favoriteSourceID:id,customTitle:favorite.customTitle))
        return localID
    }
    @discardableResult mutating func selectFavorite(_ id: String) -> String? {
        guard let index = spaces.firstIndex(where: { $0.id == activeSpaceID }), let local = localFavoriteTab(id,spaceID:activeSpaceID) else { return nil }
        spaces[index].selectedTabID = local; return local
    }
    mutating func detachFavoriteReferences(to id: String) {
        for i in tabs.indices where tabs[i].favoriteSourceID == id { tabs[i].favoriteSourceID = nil; tabs[i].pinned = false; tabs[i].lastViewedAt = Date() }
        for i in closedTabs.indices where closedTabs[i].favoriteSourceID == id { closedTabs[i].favoriteSourceID = nil; closedTabs[i].pinned = false }
    }
    @discardableResult mutating func moveToFavorites(_ id: String, spaceID: String, at position: Int) -> Bool {
        guard spaces.contains(where: { $0.id == spaceID }), let index = tabs.firstIndex(where: { $0.id == id && ($0.spaceID == spaceID || $0.favorite) }) else { return false }
        if let source = tabs[index].favoriteSourceID { return moveToFavorites(source,spaceID:spaceID,at:position) }
        var order = favoriteTabs(spaceID:spaceID).map(\.id).filter { $0 != id }
        order.insert(id,at:max(0,min(position,order.count)))
        tabs[index].favorite = true; tabs[index].pinned = true; tabs[index].folderID = nil
        for (position,id) in order.enumerated() {
            if let index = tabs.firstIndex(where: { $0.id == id }) { tabs[index].favoriteOrder = position }
        }
        return true
    }
}
