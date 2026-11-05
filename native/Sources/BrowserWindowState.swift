import Foundation

enum BrowserWindowKind: String, Codable { case normal, blank, privateWindow, compact }

extension BrowserSession {
    /// Apply only edits made by this window. Background title updates cannot erase
    /// tabs added in another window, or overwrite an unrelated changed field.
    static func merging(base:Self, incoming:Self, latest:Self) throws -> Self {
        func fields<T:Codable>(_ before:T,_ edited:T,_ current:T) throws -> T {
            let encoder = JSONEncoder()
            let a = try JSONSerialization.jsonObject(with:encoder.encode(before)) as! [String:Any]
            let b = try JSONSerialization.jsonObject(with:encoder.encode(edited)) as! [String:Any]
            var c = try JSONSerialization.jsonObject(with:encoder.encode(current)) as! [String:Any]
            for key in Set(a.keys).union(b.keys) where !NSDictionary(dictionary:["v":a[key] ?? NSNull()]).isEqual(to:["v":b[key] ?? NSNull()]) {
                c[key] = b[key]
            }
            return try JSONDecoder().decode(T.self,from:JSONSerialization.data(withJSONObject:c))
        }
        func records<T:Codable & Equatable>(_ before:[T],_ edited:[T],_ current:[T],_ key:KeyPath<T,String>) throws -> [T] {
            let old = Dictionary(uniqueKeysWithValues:before.map { ($0[keyPath:key],$0) })
            let next = Dictionary(uniqueKeysWithValues:edited.map { ($0[keyPath:key],$0) })
            var result = current.filter { old[$0[keyPath:key]] == nil || next[$0[keyPath:key]] != nil }
            for value in edited {
                let id = value[keyPath:key]
                if let previous = old[id] {
                    if previous != value, let index = result.firstIndex(where: { $0[keyPath:key] == id }) { result[index] = try fields(previous,value,result[index]) }
                } else if !result.contains(where: { $0[keyPath:key] == id }) { result.append(value) }
            }
            // Reordering belongs to an explicit edit, not a stale snapshot.
            let common = Set(old.keys).intersection(next.keys)
            if before.map({$0[keyPath:key]}).filter(common.contains) != edited.map({$0[keyPath:key]}).filter(common.contains) {
                let order = Dictionary(uniqueKeysWithValues:edited.enumerated().map { ($0.element[keyPath:key],$0.offset) })
                result = result.enumerated().sorted { (order[$0.element[keyPath:key]] ?? edited.count+$0.offset) < (order[$1.element[keyPath:key]] ?? edited.count+$1.offset) }.map(\.element)
            }
            return result
        }
        var result = try fields(base,incoming,latest)
        result.profiles = try records(base.profiles,incoming.profiles,latest.profiles,\.id)
        result.spaces = try records(base.spaces,incoming.spaces,latest.spaces,\.id)
        result.tabs = try records(base.tabs,incoming.tabs,latest.tabs,\.id)
        result.folders = try records(base.folders,incoming.folders,latest.folders,\.id)
        result.closedTabs = Self.boundedArchive(try records(base.closedTabs,incoming.closedTabs,latest.closedTabs,\.id))
        result.splitGroups = try records(base.splitGroups ?? [],incoming.splitGroups ?? [],latest.splitGroups ?? [],\.id)
        let spaces = Set(result.spaces.map(\.id)), tabs = Set(result.tabs.map(\.id))
        result.tabs.removeAll { !spaces.contains($0.spaceID) }
        result.folders.removeAll { !spaces.contains($0.spaceID) }
        result.closedTabs.removeAll { tabs.contains($0.id) || !spaces.contains($0.spaceID) }
        for i in result.folders.indices {
            if let parent = result.folders[i].parentID, !result.folders.contains(where: { $0.id == parent && $0.spaceID == result.folders[i].spaceID }) { result.folders[i].parentID = nil }
        }
        for i in result.tabs.indices {
            if let folder = result.tabs[i].folderID, !result.folders.contains(where: { $0.id == folder && $0.spaceID == result.tabs[i].spaceID && $0.liveHost == nil }) { result.tabs[i].folderID = nil }
            if let source = result.tabs[i].favoriteSourceID, !result.tabs.contains(where: { $0.id == source && $0.favorite }) { result.tabs[i].favoriteSourceID = nil }
        }
        result.repairTabSelections()
        if !spaces.contains(result.activeSpaceID), let first = result.spaces.first { result.activeSpaceID = first.id }
        for i in result.closedTabs.indices {
            if let folder = result.closedTabs[i].folderID, !result.folders.contains(where: { $0.id == folder && $0.spaceID == result.closedTabs[i].spaceID && $0.liveHost == nil }) { result.closedTabs[i].folderID = nil }
            if let source = result.closedTabs[i].favoriteSourceID, !result.tabs.contains(where: { $0.id == source && $0.favorite }) { result.closedTabs[i].favoriteSourceID = nil }
        }
        result.normalizeSplits()
        guard result.validated() else { throw SessionStoreError.invalidState }
        return result
    }

    func standaloneWindow(privateProfile:String? = nil, compact:Bool = false, initialAddress:String? = nil) -> Self {
        var next = Self.fresh(language:language); next.onboardingComplete = true
        let source = spaces.first { $0.id == activeSpaceID }
        if let privateProfile {
            let origin = profile(forSpace:activeSpaceID)
            next.profiles = [.init(id:privateProfile,name:language == "fr" ? "Privé" : "Private",searchEngineID:origin?.searchEngineID,newTabAddress:origin?.homepage,archiveAfterHours:origin?.archiveAfterHours,autoArchiveEnabledSince:origin?.autoArchiveEnabledSince)]
            next.spaces[0].profileID = privateProfile
            next.spaces[0].name = language == "fr" ? "Navigation privée" : "Private Browsing"
            next.spaces[0].icon = "🔒"; next.spaces[0].color = "#403355"
        } else if let profile = profiles.first(where: { $0.id == source?.profileID }) {
            next.profiles = [profile]; next.spaces[0].profileID = profile.id
            next.spaces[0].name = language == "fr" ? "Fenêtre vide" : "Blank Window"
            next.spaces[0].color = source?.color ?? "#5747D8"; next.spaces[0].theme = source?.theme
        }
        next.interfaceStyle = interfaceStyle
        next.themeAppearance = themeAppearance; next.sidebarWidth = sidebarWidth; next.sidebarHidden = compact || sidebarHidden
        next.commandShortcuts = commandShortcuts; next.splitShortcuts = splitShortcuts
        next.savePasswords = privateProfile == nil ? savePasswords : false
        next.automaticSignIn = privateProfile == nil ? automaticSignIn : false
        next.formSuggestions = privateProfile == nil ? formSuggestions : false
        _ = next.createTab(url:initialAddress)
        return next
    }
}
