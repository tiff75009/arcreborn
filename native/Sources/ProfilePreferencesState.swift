import Foundation

extension BrowserSession {
    /// Open settings in the selected profile, including profiles not yet used by
    /// a space. A settings tab must never silently use the currently active one.
    @discardableResult mutating func openSettingsPage(_ address:String,profileID:String) -> String? {
        guard let profile = profiles.first(where: { $0.id == profileID }), let url = settingsPageURL(address), isAllowedBrowserURL(url.absoluteString), tabs.count < 5000 else { return nil }
        var space = spaces.first(where: { $0.id == activeSpaceID && $0.profileID == profileID }) ?? spaces.first(where: { $0.profileID == profileID })
        if space == nil {
            guard spaces.count < Self.maximumSpaces else { return nil }
            let id = createSpace(name:profile.name,color:"#5747D8",icon:"sf:person",profileID:profileID)
            space = spaces.first { $0.id == id }
        }
        guard let space else { return nil }
        let id = createTab(url:url.absoluteString,spaceID:space.id)
        guard !id.isEmpty else { return nil }
        activeSpaceID = space.id
        if let i = tabs.firstIndex(where: { $0.id == id }) { tabs[i].title = language == "fr" ? "Paramètres" : "Settings" }
        return id
    }
}
