import AppKit

struct ImportBrowser: Equatable {
    let name: String, bundleID: String, relativeDirectory: String
    var application: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundleID) }
    var directory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativeDirectory) }
    static let all: [Self] = [
        .init(name:"Safari",bundleID:"com.apple.Safari",relativeDirectory:"Library/Safari"),
        .init(name:"Chrome",bundleID:"com.google.Chrome",relativeDirectory:"Library/Application Support/Google/Chrome"),
        .init(name:"Firefox",bundleID:"org.mozilla.firefox",relativeDirectory:"Library/Application Support/Firefox/Profiles"),
        .init(name:"Arc",bundleID:"company.thebrowser.Browser",relativeDirectory:"Library/Application Support/Arc")
    ]
}
struct ImportedLink: Equatable {
    var url: String, title: String, folder: String
    var pinned: Bool
}
struct BrowserImportPreview {
    var links: [ImportedLink] = []
    var warnings: [String] = []
    var bookmarkCount: Int { links.filter(\.pinned).count }
    var tabCount: Int { links.count-bookmarkCount }
}
enum BrowserImportError: LocalizedError {
    case invalid(String)
    var errorDescription:String? { if case let .invalid(message) = self { return message }; return nil }
}

/// Reads the chosen source profile or export without modifying it.
enum BrowserImportReader {
    static let maximumBytes = 32 * 1024 * 1024
    static func read(_ url:URL) throws -> Data {
        let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? maximumBytes+1
        guard size <= maximumBytes else { throw BrowserImportError.invalid("Ce fichier dépasse la limite de 32 Mo.") }
        let handle = try FileHandle(forReadingFrom:url); defer { try? handle.close() }
        let data = try handle.read(upToCount:maximumBytes+1) ?? Data()
        guard data.count <= maximumBytes else { throw BrowserImportError.invalid("Ce fichier dépasse la limite de 32 Mo.") }; return data
    }
    static func cleanURL(_ value:String) -> String? {
        guard value.utf8.count < 16384, value.rangeOfCharacter(from:.whitespacesAndNewlines.union(.controlCharacters)) == nil, !value.contains("\\"), let url = URL(string:value), ["http","https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return value
    }
    static func preview(at url:URL,browser:ImportBrowser) throws -> BrowserImportPreview {
        // Keep the underlying permission error so the UI can offer an access grant.
        let isDirectory = try url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory == true
        var result = BrowserImportPreview()
        func addFile(_ file:URL) throws {
            let name = file.lastPathComponent.lowercased()
            let data = try read(file)
            if name.hasSuffix(".html") || name.hasSuffix(".htm") { result.links += html(data); return }
            if name == "bookmarks.plist" {
                let root = try PropertyListSerialization.propertyList(from:data,options:[],format:nil)
                result.links += bookmarks(root); return
            }
            if name.hasPrefix("session_") || name == "current session" || name == "last session" {
                result.links += try chromiumSession(data); return
            }
            let decoded = name.hasSuffix("jsonlz4") || name.hasSuffix("baklz4") ? try decompressMozilla(data) : data
            let root = try JSONSerialization.jsonObject(with:decoded)
            if name == "storablesidebar.json" { result.links += arc(root) }
            else if let object = root as? [String:Any], let windows = object["windows"] as? [[String:Any]] {
                for window in windows { for tab in window["tabs"] as? [[String:Any]] ?? [] {
                    let entries = tab["entries"] as? [[String:Any]] ?? [], selected = (tab["index"] as? Int ?? entries.count)-1
                    guard entries.indices.contains(selected), let address = entries[selected]["url"] as? String, let safe = cleanURL(address) else { continue }
                    result.links.append(.init(url:safe,title:entries[selected]["title"] as? String ?? safe,folder:"",pinned:tab["pinned"] as? Bool ?? false))
                } }
            } else { result.links += bookmarks(root) }
        }
        if !isDirectory { try addFile(url) }
        else {
            let fm = FileManager.default
            let names = Set(try fm.contentsOfDirectory(atPath:url.path))
            var candidates:[URL] = []
            func append(_ path:String) { let file = url.appendingPathComponent(path); if fm.fileExists(atPath:file.path) { candidates.append(file) } }
            if browser.name == "Arc", names.contains("StorableSidebar.json") {
                return try preview(at:url.appendingPathComponent("StorableSidebar.json"),browser:browser)
            }
            if browser.name == "Safari" { append("Bookmarks.plist") }
            if browser.name == "Chrome" || browser.name == "Arc" {
                append("Bookmarks")
                // Choose a single Chromium profile; never silently combine accounts.
                if candidates.isEmpty { append("Default/Bookmarks"); append("User Data/Default/Bookmarks") }
                let roots = [url,url.appendingPathComponent("Default"),url.appendingPathComponent("User Data/Default")]
                for root in roots {
                    let sessions = root.appendingPathComponent("Sessions")
                    let files = (try? fm.contentsOfDirectory(at:sessions,includingPropertiesForKeys:nil)) ?? []
                    if let latest = files.filter({$0.lastPathComponent.hasPrefix("Session_")}).sorted(by:{$0.lastPathComponent > $1.lastPathComponent}).first { candidates.append(latest); break }
                }
            }
            if browser.name == "Firefox" {
                append("sessionstore.jsonlz4")
                if candidates.isEmpty { append("sessionstore-backups/recovery.jsonlz4"); if candidates.isEmpty { append("sessionstore-backups/previous.jsonlz4") } }
                let backups = (try? fm.contentsOfDirectory(at:url.appendingPathComponent("bookmarkbackups"),includingPropertiesForKeys:nil)) ?? []
                if let latest = backups.filter({$0.pathExtension == "jsonlz4"}).sorted(by:{$0.lastPathComponent > $1.lastPathComponent}).first { candidates.append(latest) }
            }
            guard !candidates.isEmpty else { throw BrowserImportError.invalid("Aucun favori ou onglet compatible trouvé dans ce profil.") }
            var firstError:Error?
            for file in candidates {
                do { try addFile(file) }
                catch {
                    firstError = firstError ?? error
                    result.warnings.append("\(file.lastPathComponent) n’a pas pu être lu. Fermez le navigateur source avant de réessayer.")
                }
            }
            if result.links.isEmpty, let firstError { throw firstError }
        }
        // Duplicates inside one import are ignored. Applying another import also checks existing URLs.
        var seen = Set<String>()
        result.links = result.links.filter { seen.insert("\($0.pinned)|\($0.folder)|\($0.url)").inserted }
        guard result.links.count <= 4000 else { throw BrowserImportError.invalid("Cet import contient plus de 4 000 éléments. Importez un dossier de favoris à la fois.") }
        guard !result.links.isEmpty else { throw BrowserImportError.invalid(result.warnings.first ?? "Aucun favori ou onglet web trouvé dans ce fichier.") }
        return result
    }
    static func bookmarks(_ root:Any,folder:String = "",depth:Int = 0) -> [ImportedLink] {
        guard depth < 24 else { return [] }
        if let array = root as? [Any] { return array.flatMap { bookmarks($0,folder:folder,depth:depth+1) } }
        guard let object = root as? [String:Any] else { return [] }
        let title = object["name"] as? String ?? object["title"] as? String ?? (object["URIDictionary"] as? [String:Any])?["title"] as? String ?? ""
        if let raw = object["url"] as? String ?? object["uri"] as? String ?? object["URLString"] as? String, let url = cleanURL(raw) { return [.init(url:url,title:title.isEmpty ? url : title,folder:folder,pinned:true)] }
        let next = title.isEmpty ? folder : title
        if let roots = object["roots"] as? [String:Any] { return roots.keys.sorted().flatMap { bookmarks(roots[$0]!,folder:folder,depth:depth+1) } }
        return bookmarks(object["children"] ?? object["Children"] ?? [],folder:next,depth:depth+1)
    }
    static func html(_ data:Data) -> [ImportedLink] {
        guard let string = String(data:data,encoding:.utf8) ?? String(data:data,encoding:.utf16) else { return [] }
        // Parse only exported anchor records; do not render HTML or execute scripts.
        guard let regex = try? NSRegularExpression(pattern:"<a\\b[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a\\s*>",options:[.caseInsensitive,.dotMatchesLineSeparators]) else { return [] }
        let ns = string as NSString
        func decode(_ value:String)->String {
            var text = value
            for (a,b) in [("&amp;","&"),("&quot;","\""),("&#39;","'"),("&lt;","<"),("&gt;",">")] { text = text.replacingOccurrences(of:a,with:b) }
            return text
        }
        return regex.matches(in:string,range:NSRange(location:0,length:ns.length)).compactMap { match in
            guard let url = cleanURL(decode(ns.substring(with:match.range(at:1)))) else { return nil }
            return ImportedLink(url:url,title:decode(ns.substring(with:match.range(at:2))).replacingOccurrences(of:"<[^>]*>",with:"",options:.regularExpression),folder:"Favoris importés",pinned:true)
        }
    }
    static func arc(_ root:Any) -> [ImportedLink] {
        guard let root = root as? [String:Any], let sidebar = root["sidebar"] as? [String:Any], let containers = sidebar["containers"] as? [Any] else { return [] }
        var output:[ImportedLink] = []
        for case let container as [String:Any] in containers {
            let values = (container["items"] as? [Any] ?? []).compactMap { $0 as? [String:Any] }
            var byID:[String:[String:Any]] = [:]
            for item in values { if let id = item["id"] as? String { byID[id] = item } }
            var unpinned = Set<String>(), favorites = Set<String>()
            let tops = container["topAppsContainerIDs"] as? [Any] ?? []
            for case let id as String in tops { favorites.insert(id) }
            for case let space as [String:Any] in container["spaces"] as? [Any] ?? [] {
                let ids = space["newContainerIDs"] as? [Any] ?? []
                for index in ids.indices where index+1 < ids.count {
                    if let type = ids[index] as? [String:Any], type["unpinned"] != nil, let id = ids[index+1] as? String { unpinned.insert(id) }
                }
            }
            for item in values {
                guard let tab = (item["data"] as? [String:Any])?["tab"] as? [String:Any], let raw = tab["savedURL"] as? String, let url = cleanURL(raw) else { continue }
                var parent = item["parentID"] as? String, seen = Set<String>(), pinned = true, folder = "Épingles Arc"
                while let id = parent, seen.insert(id).inserted, seen.count < 32 {
                    if unpinned.contains(id) { pinned = false; folder = ""; break }
                    if favorites.contains(id) { folder = "Favoris Arc"; break }
                    if let node = byID[id] { if let name = node["title"] as? String, !name.isEmpty { folder = name }; parent = node["parentID"] as? String } else { break }
                }
                output.append(.init(url:url,title:item["title"] as? String ?? tab["savedTitle"] as? String ?? url,folder:folder,pinned:pinned))
            }
        }
        return output
    }
    static func decompressMozilla(_ data:Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, Array(bytes.prefix(8)) == Array("mozLz40\0".utf8) else { throw BrowserImportError.invalid("Format Firefox non reconnu.") }
        let expected = Int(bytes[8]) | Int(bytes[9])<<8 | Int(bytes[10])<<16 | Int(bytes[11])<<24
        guard expected > 0, expected <= maximumBytes else { throw BrowserImportError.invalid("Export Firefox trop volumineux.") }
        var out = [UInt8](); out.reserveCapacity(expected); var cursor = 12
        func length(_ base:Int) throws -> Int {
            var count = base
            if base == 15 { while true { guard cursor < bytes.count else { throw BrowserImportError.invalid("Export Firefox incomplet.") }; let n = Int(bytes[cursor]); cursor += 1; count += n; if n != 255 { break } } }
            return count
        }
        while cursor < bytes.count {
            let token = bytes[cursor]; cursor += 1
            let literals = try length(Int(token>>4))
            guard literals <= bytes.count-cursor, out.count+literals <= expected else { throw BrowserImportError.invalid("Export Firefox invalide.") }
            out.append(contentsOf:bytes[cursor..<cursor+literals]); cursor += literals
            if cursor == bytes.count { break }
            guard cursor+2 <= bytes.count else { throw BrowserImportError.invalid("Export Firefox incomplet.") }
            let offset = Int(bytes[cursor]) | Int(bytes[cursor+1])<<8; cursor += 2
            let matches = try length(Int(token & 15))+4
            guard offset > 0, offset <= out.count, out.count+matches <= expected else { throw BrowserImportError.invalid("Export Firefox invalide.") }
            for _ in 0..<matches { out.append(out[out.count-offset]) }
        }
        guard out.count == expected else { throw BrowserImportError.invalid("Export Firefox incomplet.") }; return Data(out)
    }
    static func chromiumSession(_ data:Data) throws -> [ImportedLink] {
        let b = [UInt8](data)
        func int(_ offset:Int)->Int? { guard offset >= 0, offset+4 <= b.count else { return nil }; return Int(Int32(bitPattern:UInt32(b[offset]) | UInt32(b[offset+1])<<8 | UInt32(b[offset+2])<<16 | UInt32(b[offset+3])<<24)) }
        guard b.count >= 8, Array(b.prefix(4)) == Array("SNSS".utf8), let version = int(4), [1,3].contains(version) else { throw BrowserImportError.invalid("Ce format de session Chrome n’est pas pris en charge.") }
        var position = 8, navigation:[Int:[Int:ImportedLink]] = [:], selected:[Int:Int] = [:], pinned:Set<Int> = [], order:[Int:Int] = [:], closed:Set<Int> = [], windows:[Int:Int] = [:], closedWindows:Set<Int> = []
        while position+3 <= b.count {
            let size = Int(b[position]) | Int(b[position+1])<<8; position += 2
            guard size >= 1, position+size <= b.count else { throw BrowserImportError.invalid("La session est en cours d’écriture ou incomplète. Fermez le navigateur source puis réessayez.") }
            let command = b[position], payload = position+1, end = position+size; defer { position = end }
            if command == 6, payload+12 <= end, let id = int(payload+4), let index = int(payload+8) {
                var p = payload+12
                func string(_ wide:Bool)->String? {
                    guard let count = int(p), count >= 0 else { return nil }; p += 4
                    let bytes = count * (wide ? 2 : 1); guard bytes <= end-p else { return nil }
                    let text = String(data:Data(b[p..<p+bytes]),encoding:wide ? .utf16LittleEndian : .utf8); p += (bytes+3) & ~3; return text
                }
                if let raw = string(false), let title = string(true), let url = cleanURL(raw) { navigation[id,default:[:]][index] = .init(url:url,title:title,folder:"",pinned:false); closed.remove(id) }
            } else if command == 7, payload+8 <= end, let id = int(payload), let index = int(payload+4) { selected[id] = index }
            else if command == 2, payload+8 <= end, let id = int(payload), let index = int(payload+4) { order[id] = index }
            else if command == 12, payload+5 <= end, let id = int(payload) { if b[payload+4] == 1 { pinned.insert(id) } else { pinned.remove(id) } }
            else if command == 0, payload+8 <= end, let window = int(payload), let tab = int(payload+4) { windows[tab] = window }
            else if command == 17, payload+4 <= end, let window = int(payload) { closedWindows.insert(window) }
            else if command == 16, let id = int(payload), payload+4 <= end { closed.insert(id) }
        }
        return navigation.keys.filter { !closed.contains($0) && !closedWindows.contains(windows[$0] ?? -1) }.sorted { (order[$0] ?? $0) < (order[$1] ?? $1) }.compactMap { id in
            guard let entries = navigation[id], let index = selected[id] ?? entries.keys.max(), var link = entries[index] else { return nil }
            link.pinned = pinned.contains(id); return link
        }
    }
}
extension BrowserSession {
    /// Transactional: validate the whole candidate before committing; never replace a user's current space.
    mutating func importLinks(_ links:[ImportedLink],from source:String,profileID:String) throws -> Int {
        var copy = self
        let targetSpaces = Set(spaces.filter { $0.profileID == profileID }.map(\.id))
        var existing = Set(tabs.filter { targetSpaces.contains($0.spaceID) }.map(\.url))
        let incoming = links.filter { BrowserImportReader.cleanURL($0.url) != nil && existing.insert($0.url).inserted }
        if incoming.isEmpty { return 0 }
        guard incoming.count+tabs.count <= 5000 else { throw BrowserImportError.invalid("L’import dépasserait la limite de 5 000 onglets.") }
        let space = copy.createSpace(name:String("Import · \(source)".prefix(80)),color:"#6255CF",icon:"sf:tray.and.arrow.down",profileID:profileID)
        guard !space.isEmpty else { throw BrowserImportError.invalid("Impossible de créer l’espace d’import.") }
        var folders:[String:String] = [:]
        for link in incoming {
            var folderID:String?
            if link.pinned, !link.folder.isEmpty {
                let name = String(link.folder.components(separatedBy:.controlCharacters).joined(separator:" ").trimmingCharacters(in:.whitespacesAndNewlines).prefix(80))
                if !name.isEmpty, folders[name] == nil { let id = UUID().uuidString; folders[name] = id; copy.folders.append(.init(id:id,spaceID:space,name:name,collapsed:true)) }
                folderID = folders[name]
            }
            copy.tabs.append(.init(id:UUID().uuidString,spaceID:space,url:link.url,title:String(link.title.replacingOccurrences(of:"\0",with:"").prefix(2048)),pinned:link.pinned,favorite:false,folderID:folderID))
        }
        copy.spaces[copy.spaces.count-1].selectedTabID = copy.tabs[tabs.count].id
        guard copy.validated() else { throw BrowserImportError.invalid("Les données importées ne sont pas valides. Aucun changement n’a été enregistré.") }
        self = copy; return incoming.count
    }
}
