import AppKit
import CryptoKit

/// Local, bounded image records. Restoring an icon never creates a browser or a request.
final class FaviconCache {
    private struct Record: Codable { let document: String; let profile: String?; let png: Data }
    private struct Entry { let document: String; let profile: String; let image: NSImage; let pixels: Data? }
    private var tabs: [String:Entry] = [:]
    private let sites = NSCache<NSString,NSImage>()
    private let directory: URL
    private let persistent: Bool
    private let writes = DispatchQueue(label:"local.browser.favicon-cache",qos:.utility)
    init(directory: URL, persistent:Bool = true) {
        self.persistent = persistent
        self.directory = directory.appendingPathComponent("favicons",isDirectory:true)
        sites.countLimit = 512
    }
    static func document(_ url: String) -> String {
        guard var parts = URLComponents(string:url) else { return url }
        parts.fragment = nil; return parts.string ?? url
    }
    /// The browser's origin boundary, including scheme and effective port. Never
    /// share a fallback between subdomains or opaque/internal URLs.
    static func origin(_ url: String) -> String? {
        guard var parts = URLComponents(string:url), let scheme = parts.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = parts.host?.lowercased(), !host.isEmpty else { return nil }
        parts.scheme = scheme; parts.host = host; parts.user = nil; parts.password = nil
        parts.path = ""; parts.query = nil; parts.fragment = nil
        if parts.port == (scheme == "https" ? 443 : 80) { parts.port = nil }
        return parts.string
    }
    static func canUse(_ document: String, for url: String) -> Bool {
        if document == url || document == Self.document(url) { return true }
        guard let origin = origin(document) else { return false }
        return origin == Self.origin(url)
    }
    private func siteKey(_ url: String, _ profile: String) -> NSString? {
        Self.origin(url).map { (profile + "\n" + $0) as NSString }
    }
    /// A page's own icon takes precedence over the first known icon for its site.
    func image(id: String, url: String, profile: String) -> NSImage? {
        if let entry = tabs[id], entry.profile == profile, Self.canUse(entry.document,for:url) { return entry.image }
        return siteKey(url,profile).flatMap { sites.object(forKey:$0) }
    }
    @discardableResult private func seedSite(_ image: NSImage, url: String, profile: String) -> Bool {
        guard let key = siteKey(url,profile), sites.object(forKey:key) == nil else { return false }
        sites.setObject(image,forKey:key); return true
    }
    private func file(_ id: String) -> URL {
        let key = SHA256.hash(data:Data(id.utf8)).map { String(format:"%02x",$0) }.joined()
        return directory.appendingPathComponent(key+".json")
    }
    func restore(id: String, url: String, profile: String) {
        guard persistent else { return }
        let path = file(id)
        guard let values = try? path.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 128*1024,
              let data = try? Data(contentsOf:path), let record = try? JSONDecoder().decode(Record.self,from:data),
              (record.profile == nil || record.profile == profile), Self.canUse(record.document,for:url), record.png.count <= 64*1024,
              let bitmap = NSBitmapImageRep(data:record.png), bitmap.pixelsWide <= 64, bitmap.pixelsHigh <= 64,
              bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return }
        let image = NSImage(size:NSSize(width:16,height:16)); image.addRepresentation(bitmap)
        tabs[id] = Entry(document:record.document,profile:profile,image:image,pixels:faviconPixels(image))
        seedSite(image,url:record.document,profile:profile)
    }
    /// Only images actually supplied by Chromium are persisted as tab icons.
    @discardableResult func save(_ image: NSImage, id: String, url: String, profile: String) -> (changed:Bool, firstSite:Bool) {
        let document = Self.document(url), pixels = faviconPixels(image), old = tabs[id]
        let samePixels = pixels != nil && old?.pixels == pixels && old?.profile == profile
        let icon = samePixels ? (old?.image ?? image) : image
        icon.size = NSSize(width:16,height:16)
        let firstSite = seedSite(icon,url:url,profile:profile)
        if samePixels && old?.document == document { return (false,firstSite) }
        tabs[id] = Entry(document:document,profile:profile,image:icon,pixels:pixels)
        persist(icon,id:id,document:document,profile:profile)
        return (true,firstSite)
    }
    private func persist(_ image: NSImage, id: String, document: String, profile: String) {
        guard persistent else { return }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:64,pixelsHigh:64,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:256,bitsPerPixel:32),
              let context = NSGraphicsContext(bitmapImageRep:bitmap), let bytes = bitmap.bitmapData else { return }
        memset(bytes,0,64*256)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        image.draw(in:NSRect(x:0,y:0,width:64,height:64),from:.zero,operation:.copy,fraction:1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using:.png,properties:[:]), png.count <= 64*1024,
              let data = try? JSONEncoder().encode(Record(document:document,profile:profile,png:png)) else { return }
        let destination = file(id), directory = directory
        writes.async {
            do {
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                try data.write(to:destination,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.path)
            } catch { NSLog("Unable to save favicon cache: %@",String(describing:error)) }
        }
    }
    /// A normal quit drains the small pending writes before CEF releases its images.
    func flush() { writes.sync {} }
}
