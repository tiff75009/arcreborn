import AppKit
import ImageIO

struct BrowserExtension {
    let id:String
    let name:String
    let image:NSImage?
}

/// Read-only metadata. Chromium remains the only writer of its installation,
/// permission and integrity-protected preferences. Pins are Browser UI state.
final class ExtensionCatalog {
    private let directory:URL
    private let liveSettings:(String)->[String:Any]?
    private var cache:[String:(Date,[BrowserExtension])] = [:]
    private var confirmedInstalls:[String:[String:(Date,BrowserExtension)]] = [:]
    func installed(_ item:BrowserExtension, profile:String) {
        confirmedInstalls[profile,default:[:]][item.id] = (Date(),item)
        cache.removeValue(forKey:profile)
    }
    init(directory:URL, liveSettings:@escaping (String)->[String:Any]? = { _ in nil }) {
        self.directory = directory; self.liveSettings = liveSettings
    }
    func invalidate(profile:String) {
        cache.removeValue(forKey:profile)
        // A live preference event supersedes the temporary installation notice.
        confirmedInstalls.removeValue(forKey:profile)
    }
    func entries(profile:String, force:Bool = false) -> [BrowserExtension] {
        if !force, let cached = cache[profile], Date().timeIntervalSince(cached.0) < 2 { return cached.1 }
        guard !profile.isEmpty, profile.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return [] }
        let root = directory.appendingPathComponent("Chromium/Profile-"+profile)
        func json(_ url:URL) -> [String:Any] {
            guard let size = try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize, size < 16_000_000,
                  let data = try? Data(contentsOf:url), let value = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
            return value
        }
        let live = liveSettings(profile)
        let prefs = live == nil ? json(root.appendingPathComponent("Secure Preferences")) : [:]
        let settings = (live ?? (prefs["extensions"] as? [String:Any])?["settings"] as? [String:Any] ?? [:]) as? [String:[String:Any]] ?? [:]
        if live != nil {
            // Prune only from authoritative in-memory state, never a failed or
            // delayed disk read. Disabled extensions keep their pin preference.
            let previous = pins(profile:profile)
            let retained = previous.filter { settings[$0] != nil }
            if previous != retained { UserDefaults.standard.set(retained,forKey:"BrowserExtensionPins."+profile) }
        }
        var entries = settings.compactMap { id, value -> BrowserExtension? in
            guard id.count == 32, id.allSatisfy({ ("a"..."p").contains(String($0)) }),
                  (value["disable_reasons"] as? [Any] ?? []).isEmpty,
                  (value["disable_reasons"] as? Int ?? 0) == 0,
                  let path = value["path"] as? String else { return nil }
            let folder = path.hasPrefix("/") ? URL(fileURLWithPath:path) : root.appendingPathComponent("Extensions").appendingPathComponent(path)
            let manifest = value["manifest"] as? [String:Any] ?? json(folder.appendingPathComponent("manifest.json"))
            guard manifest["action"] != nil || manifest["browser_action"] != nil || manifest["page_action"] != nil else { return nil }
            var name = manifest["name"] as? String ?? id
            if name.hasPrefix("__MSG_"), name.hasSuffix("__"), let locale = manifest["default_locale"] as? String,
               locale.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "_" || $0 == "-") }) {
                let key = String(name.dropFirst(6).dropLast(2))
                name = (json(folder.appendingPathComponent("_locales/"+locale+"/messages.json"))[key] as? [String:Any])?["message"] as? String ?? name
            }
            let icons = manifest["icons"] as? [String:String] ?? [:]
            // Prefer enough source pixels for Retina, without upscaling a 16px asset.
            let sizes = icons.keys.compactMap(Int.init).sorted()
            let preferredSize = sizes.first(where: { $0 >= 64 }) ?? sizes.last
            let icon = preferredSize.flatMap { icons[String($0)] }
            var image:NSImage?
            if let icon {
                let file = folder.appendingPathComponent(icon).resolvingSymlinksInPath()
                if file.path.hasPrefix(folder.resolvingSymlinksInPath().path+"/"),
                   let source = CGImageSourceCreateWithURL(file as CFURL,nil),
                   let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:64] as CFDictionary) {
                    image = NSImage(cgImage:cg,size:NSSize(width:cg.width,height:cg.height))
                }
            }
            return BrowserExtension(id:id,name:name,image:image)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        // Chromium flushes Secure Preferences asynchronously. A native install
        // success event can populate the UI immediately while that write settles.
        if live == nil, let pending = confirmedInstalls[profile] {
            for (id,value) in pending {
                if settings[id] != nil || Date().timeIntervalSince(value.0) > 30 {
                    confirmedInstalls[profile]?.removeValue(forKey:id)
                } else { entries.append(value.1) }
            }
        }
        cache[profile] = (Date(),entries)
        return entries
    }
    func pins(profile:String) -> [String] { UserDefaults.standard.stringArray(forKey:"BrowserExtensionPins."+profile) ?? [] }
    func togglePin(_ id:String, profile:String) {
        var values = pins(profile:profile)
        if values.contains(id) { values.removeAll { $0 == id } } else { values.append(id) }
        UserDefaults.standard.set(values,forKey:"BrowserExtensionPins."+profile)
    }
}

final class ExtensionActionButton: NavigationButton {
    init(_ item:BrowserExtension, action:@escaping ()->Void) {
        super.init(item.name,action:action)
        identifier = NSUserInterfaceItemIdentifier(item.id)
        image = item.image ?? NSImage(systemSymbolName:"puzzlepiece.extension.fill",accessibilityDescription:item.name)
        imageScaling = .scaleProportionallyDown
        toolTip = item.name
    }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ rect:NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let side = max(0, min(20, min(bounds.width, bounds.height)-10))
        let scale = side / max(image.size.width, image.size.height)
        let size = NSSize(width:image.size.width*scale,height:image.size.height*scale)
        let box = NSRect(x:bounds.midX-size.width/2,y:bounds.midY-size.height/2,width:size.width,height:size.height)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in:box,from:.zero,operation:.sourceOver,fraction:isEnabled ? 1 : 0.4,respectFlipped:true,hints:nil)
    }
}

/// The badge has its own hit target; its glyph never scales to the whole tile.
final class ExtensionPinButton: NavigationButton {
    var pinned = false { didSet { needsDisplay = true } }
    override func draw(_ rect:NSRect) {
        NSColor(white:0.38,alpha:1).setFill()
        NSBezierPath(ovalIn:bounds.insetBy(dx:0.5,dy:0.5)).fill()
        SpaceIcon.draw("sf:"+(pinned ? "pin.fill" : "pin"),
            in:NSRect(x:bounds.midX-5,y:bounds.midY-5,width:10,height:10),color:.white,size:10)
    }
}

extension ExtensionCatalog {
    /// Profiles which have not started yet still have an installation catalog.
    /// Read metadata only; Chromium remains the sole writer of extension state.
    static func passwordManagerSettings(directory:URL,profile:String) -> [String:Any] {
        guard !profile.isEmpty, profile.count <= 100, profile.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return [:] }
        let file = directory.appendingPathComponent("Chromium/Profile-"+profile+"/Secure Preferences")
        guard let size = try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize, size < 16_000_000,
              let data = try? Data(contentsOf:file), let json = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let extensions = json["extensions"] as? [String:Any] else { return [:] }
        return extensions["settings"] as? [String:Any] ?? [:]
    }
}

