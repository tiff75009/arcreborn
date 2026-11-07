import Foundation

@main struct SiteSettingsTests {
    static var checks = 0
    static func require(_ condition:Bool,_ message:String) {
        precondition(condition,message); checks += 1
    }
    static func main() throws {
        let site = "https://example.com/club"
        let address = siteSettingsURL(for:site)!
        require(address.absoluteString == "chrome://settings/content/siteDetails?site="+site,"route to the real Chromium settings page")
        let displayed = browserDisplayAddress(address.absoluteString)
        require(displayed == "arc://settings/content/siteDetails?site="+site,"display the Arc alias")
        require(browserURL(displayed) == address,"typing the displayed alias opens the same page")
        require(browserURL("browser://settings/")?.absoluteString == "chrome://settings/","browser alias")
        require(browserURL("arc://components")?.absoluteString == "chrome://components/","open the component updater")
        require(isAllowedBrowserURL("chrome://components/"),"restore the component updater")
        require(browserURL("arc://downloads")?.absoluteString == "chrome://downloads/" && isAllowedBrowserURL("chrome://downloads/"),"open Chromium download decisions in the profile")
        require(settingsPageURL("chrome://downloads/other") == nil && settingsPageURL("chrome://downloads/?q=x") == nil,"only allow the downloads root")
        for invalid in ["chrome://components/other","chrome://components/?q=update","arc://user@components/","arc://components/#x"] {
            require(settingsPageURL(invalid) == nil,"reject unsupported component routes")
        }
        let complexSite = "https://example.com:8443/a+b?x=1&y=a+b%26c#part"
        let complexAddress = siteSettingsURL(for:complexSite)!
        let parts = URLComponents(url:complexAddress,resolvingAgainstBaseURL:false)!
        require(parts.queryItems == [URLQueryItem(name:"site",value:complexSite)],"keep the full site URL as one query parameter")
        require(parts.percentEncodedQuery?.contains("+") == false,"URLSearchParams must preserve literal plus signs")
        for invalid in ["file:///tmp/a","about:blank","javascript:alert(1)","https://user:password@example.com/"] {
            require(siteSettingsURL(for:invalid) == nil,"reject invalid site: "+invalid)
        }
        for invalid in ["chrome://settings.evil/","chrome://user@settings/","chrome://settings:80/","chrome://crash/","arc://settings\\@example.com/","chrome://settings/\n"] {
            require(!isAllowedBrowserURL(invalid),"reject unsupported internal page: "+invalid)
        }
        var session = BrowserSession.fresh()
        let sourceID = session.createTab(url:site)
        var source = session.tabs.first { $0.id == sourceID }!
        let settingsID = session.createTab(url:address.absoluteString,spaceID:source.spaceID)
        require(!settingsID.isEmpty && settingsID != sourceID,"settings opens in a new tab")
        source.sidebarOrder = (source.sidebarOrder ?? 0) + 1
        require(session.tabs.first { $0.id == sourceID } == source,"inserting settings above the source changes only its sidebar position")
        require(session.tabs.first { $0.id == settingsID }?.spaceID == source.spaceID,"use the source space and its profile")
        require(session.validated(),"settings tab can be persisted")
        let restored = try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(session))
        require(restored == session,"restore settings tabs without invalidating the session")
        print("Site settings: \(checks) checks passed")
    }
}
