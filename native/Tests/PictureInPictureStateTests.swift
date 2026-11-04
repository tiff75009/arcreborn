import Foundation

@main struct PictureInPictureStateTests {
    static func main() throws {
        var session = BrowserSession.fresh()
        let id = session.createTab(url:"https://www.example.com/watch?v=1")
        let tab = session.tabs.first { $0.id == id }!
        precondition(session.automaticPictureInPictureEnabled(for:tab))
        let oldData = try JSONEncoder().encode(session)
        precondition(!String(decoding:oldData,as:UTF8.self).contains("automaticPictureInPicture"))
        let oldSession = try JSONDecoder().decode(BrowserSession.self,from:oldData)
        precondition(oldSession.automaticPictureInPictureEnabled(for:tab),"Existing profiles default to enabled")
        session.setAutomaticPictureInPicture(false,for:tab)
        var sameSite = tab; sameSite.url = "https://www.example.com/another"
        precondition(!session.automaticPictureInPictureEnabled(for:sameSite),"Choice applies to the site, not one URL")
        var otherSite = tab; otherSite.url = "https://video.example.net/"
        precondition(session.automaticPictureInPictureEnabled(for:otherSite))
        session.profiles.append(NativeProfile(id:"other-profile",name:"Other"))
        session.spaces.append(NativeSpace(id:"other-space",name:"Other",color:"#5747D8",icon:"◈",profileID:"other-profile"))
        var otherProfile = tab; otherProfile.spaceID = "other-space"
        precondition(session.automaticPictureInPictureEnabled(for:otherProfile),"Profiles stay independent")
        let restored = try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(session))
        precondition(restored.validated())
        precondition(!restored.automaticPictureInPictureEnabled(for:tab))
        var internalTab = tab; internalTab.url = "chrome://settings/"
        precondition(!session.automaticPictureInPictureEnabled(for:internalTab))
        session.setAutomaticPictureInPicture(true,for:tab)
        precondition(session.automaticPictureInPictureEnabled(for:sameSite))
        print("PASS PiP defaults, old session decoding, per-site/profile isolation and persistence (10 checks)")
    }
}
