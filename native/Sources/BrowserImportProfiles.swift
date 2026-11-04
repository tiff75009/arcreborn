// SPDX-License-Identifier: MPL-2.0
import Foundation

struct BrowserImportProfile: Equatable {
    let name: String
    let url: URL
}

extension ImportBrowser {
    /// Discover locations first. The reader only opens the selected bookmarks or session on import.
    func importProfiles(in root: URL, english: Bool = false) throws -> [BrowserImportProfile] {
        switch bundleID {
        case "com.apple.Safari":
            // Do not probe Safari's protected Library when the welcome screen opens.
            return [.init(name:english ? "Safari bookmarks" : "Favoris de Safari",url:root.appendingPathComponent("Bookmarks.plist"))]
        case "company.thebrowser.Browser":
            let sidebar = root.appendingPathComponent("StorableSidebar.json")
            do {
                _ = try sidebar.resourceValues(forKeys:[.isRegularFileKey])
                return [.init(name:english ? "Arc sidebar" : "Barre latérale d’Arc",url:sidebar)]
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { }
            return try chromiumProfiles(in:root.appendingPathComponent("User Data"))
        case "org.mozilla.firefox":
            return try firefoxProfiles(in:root)
        default:
            return try chromiumProfiles(in:root)
        }
    }

    private func childDirectories(in root:URL) throws -> [URL] {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey],options:.skipsHiddenFiles)
            return urls.filter { (try? $0.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return [] }
    }

    private func chromiumProfiles(in root:URL) throws -> [BrowserImportProfile] {
        let directories = try childDirectories(in:root)
        let data = try? BrowserImportReader.read(root.appendingPathComponent("Local State"))
        let state = data.flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] }
        let meta = state?["profile"] as? [String:Any]
        let cache = meta?["info_cache"] as? [String:[String:Any]] ?? [:]
        let lastUsed = meta?["last_used"] as? String ?? "Default"
        let candidates = directories.filter {
            let id = $0.lastPathComponent
            return id != "Guest Profile" && id != "System Profile" && (id == "Default" || id.hasPrefix("Profile ") || cache[id] != nil)
        }.sorted {
            if ($0.lastPathComponent == lastUsed) != ($1.lastPathComponent == lastUsed) { return $0.lastPathComponent == lastUsed }
            return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        return candidates.map {
            let id = $0.lastPathComponent
            let label = cache[id]?["name"] as? String ?? ""
            return .init(name:label.isEmpty || label == id ? id : "\(label) · \(id)",url:$0)
        }
    }

    private func firefoxProfiles(in root:URL) throws -> [BrowserImportProfile] {
        let parent = root.deletingLastPathComponent()
        let ini = parent.appendingPathComponent("profiles.ini")
        var sections:[String:[String:String]] = [:], section = ""
        if let data = try? BrowserImportReader.read(ini), let text = String(data:data,encoding:.utf8) {
            for rawLine in text.components(separatedBy:.newlines) {
                let line = rawLine.trimmingCharacters(in:.whitespaces)
                if line.hasPrefix("["), line.hasSuffix("]") { section = String(line.dropFirst().dropLast()); continue }
                guard let split = line.firstIndex(of:"=") else { continue }
                sections[section,default:[:]][String(line[..<split])] = String(line[line.index(after:split)...])
            }
        }
        let defaults = Set(sections.filter { $0.key.hasPrefix("Install") }.compactMap { $0.value["Default"] })
        var result:[BrowserImportProfile] = [], seen = Set<URL>()
        for (key,entry) in sections.sorted(by:{ $0.key < $1.key }) where key.hasPrefix("Profile") {
            guard let path = entry["Path"], !path.isEmpty else { continue }
            let url = (entry["IsRelative"] == "0" ? URL(fileURLWithPath:path) : parent.appendingPathComponent(path)).standardizedFileURL
            guard (try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true, seen.insert(url).inserted else { continue }
            let profile = BrowserImportProfile(name:entry["Name"] ?? url.lastPathComponent,url:url)
            if defaults.contains(path) || entry["Default"] == "1" { result.insert(profile,at:0) } else { result.append(profile) }
        }
        if !result.isEmpty { return result }
        return try childDirectories(in:root).sorted { $0.lastPathComponent < $1.lastPathComponent }.map { .init(name:$0.lastPathComponent,url:$0) }
    }
}
