import AppKit
import CryptoKit

/// Local, bounded image records. Restoring an icon never creates a browser or a request.
final class FaviconCache {
    private struct Record: Codable { let document: String; let png: Data }
    private let directory: URL
    private let persistent: Bool
    private let writes = DispatchQueue(label:"local.browser.favicon-cache",qos:.utility)
    init(directory: URL, persistent:Bool = true) { self.persistent = persistent; self.directory = directory.appendingPathComponent("favicons",isDirectory:true) }
    static func document(_ url: String) -> String {
        guard var parts = URLComponents(string:url) else { return url }
        parts.fragment = nil; return parts.string ?? url
    }
    private func file(_ id: String) -> URL {
        let key = SHA256.hash(data:Data(id.utf8)).map { String(format:"%02x",$0) }.joined()
        return directory.appendingPathComponent(key+".json")
    }
    func image(id: String, url: String) -> NSImage? {
        guard persistent else { return nil }
        let path = file(id)
        guard let values = try? path.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 128*1024,
              let data = try? Data(contentsOf:path), let record = try? JSONDecoder().decode(Record.self,from:data),
              record.document == Self.document(url), record.png.count <= 64*1024,
              let bitmap = NSBitmapImageRep(data:record.png), bitmap.pixelsWide <= 64, bitmap.pixelsHigh <= 64,
              bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return nil }
        let image = NSImage(size:NSSize(width:16,height:16)); image.addRepresentation(bitmap); return image
    }
    func save(_ image: NSImage, id: String, url: String) {
        guard persistent else { return }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:64,pixelsHigh:64,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:256,bitsPerPixel:32),
              let context = NSGraphicsContext(bitmapImageRep:bitmap), let bytes = bitmap.bitmapData else { return }
        memset(bytes,0,64*256)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        image.draw(in:NSRect(x:0,y:0,width:64,height:64),from:.zero,operation:.copy,fraction:1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using:.png,properties:[:]), png.count <= 64*1024,
              let data = try? JSONEncoder().encode(Record(document:Self.document(url),png:png)) else { return }
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
