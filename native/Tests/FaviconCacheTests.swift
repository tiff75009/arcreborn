import AppKit

@main struct FaviconCacheTests {
    static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("browser-favicon-test-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let red = NSImage(size:NSSize(width:64,height:64),flipped:false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let blue = NSImage(size:NSSize(width:64,height:64),flipped:false) { rect in
            NSColor.blue.setFill(); rect.fill(); return true
        }
        let cache = FaviconCache(directory:directory)
        let profile = "personal", site = "https://x.com", feed = site+"/home"
        precondition(cache.image(id:"favorite",url:feed,profile:profile) == nil)
        cache.save(red,id:"favorite",url:site+"/post/123#top",profile:profile); cache.flush()
        let files = try FileManager.default.contentsOfDirectory(at:directory.appendingPathComponent("favicons"),includingPropertiesForKeys:nil)
        // Reproduce a pre-fix record: same tab ID, old route, no profile field.
        var record = try JSONSerialization.jsonObject(with:Data(contentsOf:files[0])) as! [String:Any]
        record.removeValue(forKey:"profile")
        try JSONSerialization.data(withJSONObject:record).write(to:files[0])
        let bitmap = NSBitmapImageRep(data:Data(base64Encoded:record["png"] as! String)!)!
        precondition(bitmap.pixelsWide == 64 && bitmap.pixelsHigh == 64)
        let restarted = FaviconCache(directory:directory)
        restarted.restore(id:"favorite",url:feed,profile:profile)
        let restored = restarted.image(id:"favorite",url:feed,profile:profile)
        precondition(restored != nil && faviconPixels(restored!) == faviconPixels(red),"Recover the existing icon after a route change and restart")
        precondition(restarted.image(id:"blank-tab",url:"https://X.com:443/notifications?filter=all",profile:profile) === restored,"Unloaded peer can use the known site icon")
        precondition(restarted.image(id:"favorite",url:feed,profile:"work") == nil,"In-memory tab and origin lookups respect profiles")
        for url in ["https://other.example/","https://help.x.com/home","http://x.com/home","https://x.com:444/home","about:blank"] {
            precondition(restarted.image(id:"favorite",url:url,profile:profile) == nil,"Different origins cannot inherit an icon")
        }
        let changed = restarted.save(blue,id:"blank-tab",url:feed,profile:profile)
        precondition(changed.changed && !changed.firstSite)
        precondition(restarted.image(id:"blank-tab",url:feed+"?tab=2",profile:profile) === blue,"A page's own icon wins over a borrowed site icon")
        precondition(restarted.image(id:"favorite",url:feed,profile:profile) === restored,"A different page keeps its own icon")
        precondition(!restarted.save(blue,id:"blank-tab",url:feed,profile:profile).changed,"Duplicate pixels do not rebuild the sidebar")
        restarted.flush()
        let foreign = FaviconCache(directory:directory)
        foreign.restore(id:"blank-tab",url:feed,profile:"work")
        precondition(foreign.image(id:"blank-tab",url:feed,profile:"work") == nil,"New records also enforce profile isolation on disk")
        let privateCache = FaviconCache(directory:directory,persistent:false)
        privateCache.restore(id:"favorite",url:feed,profile:profile)
        precondition(privateCache.image(id:"favorite",url:feed,profile:profile) == nil)
        privateCache.save(blue,id:"favorite",url:feed,profile:profile); privateCache.flush()
        precondition(privateCache.image(id:"peer",url:feed,profile:profile) === blue)
        let privateCheck = FaviconCache(directory:directory)
        privateCheck.restore(id:"favorite",url:feed,profile:profile)
        precondition(faviconPixels(privateCheck.image(id:"favorite",url:feed,profile:profile)!) == faviconPixels(red),"Private browsing must not change the saved icon")
        try Data("broken".utf8).write(to:files[0])
        let corrupt = FaviconCache(directory:directory)
        corrupt.restore(id:"favorite",url:feed,profile:profile)
        precondition(corrupt.image(id:"favorite",url:feed,profile:profile) == nil,"Corrupt cache does not break restoration")
        cache.save(red,id:"../outside",url:feed,profile:profile); cache.flush()
        let checked = FaviconCache(directory:directory)
        checked.restore(id:"../outside",url:feed,profile:profile)
        precondition(checked.image(id:"../outside",url:feed,profile:profile) != nil && !FileManager.default.fileExists(atPath:directory.appendingPathComponent("outside").path),"Identifiers cannot escape the cache directory")
        let grid = FavoritesGrid(frame:NSRect(x:0,y:0,width:230,height:46))
        var favorite = FavoriteVisual(id:"favorite",title:"Example",image:restored,menu:NSMenu(),isLoaded:false)
        grid.update([favorite],activeID:nil,ink:.white)
        let tile = grid.subviews.compactMap { $0 as? NSButton }.first!
        let icon = tile.subviews.compactMap { $0 as? NSImageView }.first!
        precondition(icon.image === restored && icon.alphaValue > 0 && icon.alphaValue < 0.6,"Dormant favorite keeps its restored icon visible but dim")
        favorite.isLoaded = true; grid.update([favorite],activeID:"favorite",ink:.white)
        precondition(icon.alphaValue == 1,"Loaded page lights its icon")
        var unread = FavoriteUnread()
        let mailbox = "https://mail.google.com/mail/u/0/#inbox"
        unread.update(title:"Boîte de réception (1 234) – Gmail",address:mailbox)
        precondition(unread.visible)
        unread.update(title:"Un sujet de conversation – Gmail",address:mailbox+"/thread")
        precondition(unread.visible,"Opening a thread does not mark the inbox as read")
        unread.updateInbox(false,document:mailbox,address:mailbox+"/thread")
        precondition(!unread.visible,"Reading the last message clears the inbox dot inside a thread")
        unread.update(title:"Inbox (3) - Gmail",address:mailbox)
        unread.navigate(to:"https://mail.google.com/mail/u/1/#inbox")
        unread.updateInbox(true,document:mailbox,address:"https://mail.google.com/mail/u/1/#inbox")
        precondition(!unread.visible,"An old mailbox cannot light another account")
        unread.update(title:"Inbox (2) - Gmail",address:mailbox)
        unread.update(title:"Inbox - Gmail",address:mailbox)
        precondition(!unread.visible)
        unread.update(title:"(2) WhatsApp",address:"https://web.whatsapp.com")
        precondition(unread.visible)
        unread.update(title:"(2026) A film",address:"https://cinema.example")
        precondition(!unread.visible,"An ordinary number in a page title is not an unread signal")
        unread.update(title:"(3 non lus) Courrier",address:"https://site.example")
        precondition(unread.visible)
        unread.update(title:"(0 non lus) Courrier",address:"https://site.example")
        precondition(!unread.visible)
        favorite.unreadLabel = "Messages non lus"
        grid.update([favorite],activeID:"favorite",ink:.white)
        precondition(tile.accessibilityLabel()?.contains("Messages non lus") == true,"Selecting the favorite keeps its unread indicator")
        favorite.unreadLabel = nil; grid.update([favorite],activeID:"favorite",ink:.white)
        precondition(tile.accessibilityLabel() == "Example")
        precondition(grid.subviews.contains(where: { $0 === tile }) && icon.image === restored,"Loading changes brightness without replacing tile or image")
        favorite.isLoaded = false; grid.update([favorite],activeID:nil,ink:.white)
        precondition(icon.alphaValue < 0.6 && icon.image != nil,"Unloaded page dims without losing its favicon")
        print("PASS: favicon routing, restoration, isolation and appearance")
    }
}
