import Foundation

private final class RecordedActivity: NSUserActivity {
    var activations = 0
    var invalidations = 0
    override func becomeCurrent() { activations += 1 }
    override func invalidate() { invalidations += 1 }
}

@main struct BrowserHandoffTests {
    static func main() throws {
        var checks = 0
        func check(_ value:Bool,_ message:String) {
            precondition(value,message); checks += 1
        }
        let address = "https://example.com/caf%C3%A9?onglet=2#lecture"
        let title = "Café & idées — à reprendre"
        let page = BrowserHandoff.Page(address:address,title:title,isPrivate:false)!
        check(page.url.absoluteString == address && page.title == title,"URL, fragment and accented title preserved")
        for invalid in ["about:blank","chrome://history/","chrome-extension://"+String(repeating:"a",count:32)+"/","file:///tmp/document","javascript:alert(1)","data:text/html,test","https:","https:///","https://user:password@example.com/","https://example.com/\n", "https://example.com/"+String(repeating:"x",count:32769)] {
            check(BrowserHandoff.webURL(invalid) == nil,"reject non-web, malformed or credential-bearing URL: \(invalid.prefix(60))")
        }
        check(BrowserHandoff.webURL("http://example.com/") != nil,"HTTP is supported")
        check(BrowserHandoff.Page(address:address,title:title,isPrivate:true) == nil,"private browsing is never advertised")
        check(BrowserHandoff.Page(address:address,title:title,isPrivate:false,isAvailable:false) == nil,"hidden, closed or unavailable content is never advertised")

        var created:[RecordedActivity] = []
        let handoff = BrowserHandoff {
            let activity = RecordedActivity(activityType:NSUserActivityTypeBrowsingWeb)
            created.append(activity); return activity
        }
        handoff.update(page)
        let first = created[0]
        check(first.activations == 1 && first.webpageURL == page.url && first.title == title,"publishes active web page once")
        check(first.isEligibleForHandoff && !first.isEligibleForSearch && !first.isEligibleForPublicIndexing,"Handoff without search indexing")
        for _ in 0..<100 { handoff.update(page) }
        check(created.count == 1 && first.activations == 1 && first.invalidations == 0,"load progress and inactive-tab callbacks cannot churn the activity")
        handoff.update(.init(address:address,title:"Nouveau titre éphémère",isPrivate:false))
        check(created.count == 1 && first.title == "Nouveau titre éphémère" && first.needsSave,"a later title updates the existing activity")
        let secondURL = "https://example.com/notifications#r%C3%A9centes"
        handoff.update(.init(address:secondURL,title:"Notifications",isPrivate:false))
        check(first.invalidations == 1 && created.count == 2 && handoff.activity?.webpageURL?.absoluteString == secondURL,"SPA navigation replaces stale URL")
        handoff.update(nil)
        check(handoff.activity == nil && created[1].invalidations == 1,"private or internal selection clears the previous public page")
        handoff.update(nil)
        check(created[1].invalidations == 1,"repeated invalidation is safe")
        handoff.update(page); handoff.invalidate()
        check(handoff.activity == nil && created[2].invalidations == 1,"closing the final window or quitting withdraws the activity")

        var opened:[URL] = []
        let received = NSUserActivity(activityType:NSUserActivityTypeBrowsingWeb)
        received.webpageURL = page.url
        check(BrowserHandoff.receive(received) { opened.append($0) },"accept web activity from another device")
        check(opened == [page.url],"delivery opens exactly the supplied URL once")
        let unknown = NSUserActivity(activityType:"example.other-activity"); unknown.webpageURL = page.url
        check(!BrowserHandoff.receive(unknown) { opened.append($0) },"unsupported activities are declined")
        check(!BrowserHandoff.receive(NSUserActivity(activityType:NSUserActivityTypeBrowsingWeb)) { opened.append($0) },"missing URL is declined")
        received.webpageURL = URL(string:"https://user:secret@example.com/")
        check(!BrowserHandoff.receive(received) { opened.append($0) } && opened == [page.url],"rejected input never reaches navigation")

        let data = try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
        let plist = try PropertyListSerialization.propertyList(from:data,format:nil) as! [String:Any]
        check((plist["NSUserActivityTypes"] as? [String])?.contains(NSUserActivityTypeBrowsingWeb) == true,"app advertises browser Handoff to Launch Services")
        print("Handoff: \(checks) checks passed (receiving, metadata lifecycle, privacy, URL validation, accents and registration)")
    }
}
