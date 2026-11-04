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
        precondition(cache.image(id:"favorite",url:"https://example.com/") == nil)
        cache.save(red,id:"favorite",url:"https://example.com/#top"); cache.flush()
        let restarted = FaviconCache(directory:directory)
        let restored = restarted.image(id:"favorite",url:"https://example.com/#other")
        precondition(restored != nil,"An unloaded favorite must recover its icon from a previous process")
        precondition(faviconPixels(restored!) == faviconPixels(red),"Recovered icon keeps its visible pixels")
        precondition(restarted.image(id:"favorite",url:"https://other.example/") == nil,"A different site cannot inherit the previous favicon")
        precondition(restarted.image(id:"other-tab",url:"https://example.com/") == nil,"Tab identities remain distinct")
        cache.save(blue,id:"favorite",url:"https://example.com/"); cache.flush()
        precondition(faviconPixels(restarted.image(id:"favorite",url:"https://example.com/")!) == faviconPixels(blue),"Changed favicon replaces persisted pixels")
        let files = try FileManager.default.contentsOfDirectory(at:directory.appendingPathComponent("favicons"),includingPropertiesForKeys:nil)
        precondition(files.count == 1,"Updates replace one bounded record")
        let record = try JSONSerialization.jsonObject(with:Data(contentsOf:files[0])) as! [String:Any]
        let bitmap = NSBitmapImageRep(data:Data(base64Encoded:record["png"] as! String)!)!
        precondition(bitmap.pixelsWide == 64 && bitmap.pixelsHigh == 64,"Stored images have bounded resolution")
        try Data("broken".utf8).write(to:files[0])
        precondition(restarted.image(id:"favorite",url:"https://example.com/") == nil,"Corrupt cache does not break session restoration")
        cache.save(red,id:"../outside",url:"https://example.com/"); cache.flush()
        precondition(cache.image(id:"../outside",url:"https://example.com/") != nil && !FileManager.default.fileExists(atPath:directory.appendingPathComponent("outside").path),"Identifiers cannot escape the cache directory")
        let grid = FavoritesGrid(frame:NSRect(x:0,y:0,width:230,height:46))
        var favorite = FavoriteVisual(id:"favorite",title:"Example",image:restored,menu:NSMenu(),isLoaded:false)
        grid.update([favorite],activeID:nil,ink:.white)
        let tile = grid.subviews.compactMap { $0 as? NSButton }.first!
        let icon = tile.subviews.compactMap { $0 as? NSImageView }.first!
        precondition(icon.image === restored && icon.alphaValue > 0 && icon.alphaValue < 0.6,"Dormant favorite keeps its restored icon visible but dim")
        favorite.isLoaded = true; grid.update([favorite],activeID:"favorite",ink:.white)
        precondition(icon.alphaValue == 1,"Loaded page lights its icon")
        precondition(grid.subviews.contains(where: { $0 === tile }) && icon.image === restored,"Loading changes brightness without replacing tile or image")
        favorite.isLoaded = false; grid.update([favorite],activeID:nil,ink:.white)
        precondition(icon.alphaValue < 0.6 && icon.image != nil,"Unloaded page dims without losing its favicon")
        print("PASS: 14 favicon persistence and appearance assertions")
    }
}
