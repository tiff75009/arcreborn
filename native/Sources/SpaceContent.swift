import Foundation

func normalizedLiveHost(_ input: String) -> String? {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !text.isEmpty, text.count <= 253, !text.contains("/"), !text.contains(":"),
          !text.contains("@"), !text.contains("?"), !text.contains("#"),
          text.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
          let url = URL(string: "https://" + text), let host = url.host, !host.isEmpty else { return nil }
    let normalized = host.hasSuffix(".") ? String(host.dropLast()) : host
    guard normalized.range(of:"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$",options:.regularExpression) != nil else { return nil }
    return normalized
}

extension BrowserSession {
    func tabs(in folder: NativeFolder) -> [NativeTab] {
        tabs.filter { tab in
            guard tab.spaceID == folder.spaceID, tab.favoriteSourceID == nil else { return false }
            guard let rule = folder.liveHost else { return tab.folderID == folder.id && !tab.favorite && tab.favoriteSourceID == nil }
            guard let host = URL(string: tab.url)?.host?.lowercased() else { return false }
            return host == rule || host.hasSuffix("." + rule)
        }
    }

    /// Copy links only. A target space always keeps its own profile and cookies.
    @discardableResult mutating func exportSpaceIntoFolder(_ sourceID: String, targetID: String) -> Bool {
        guard sourceID != targetID, let source = spaces.first(where: { $0.id == sourceID }),
              spaces.contains(where: { $0.id == targetID }), folders.count < 1000 else { return false }
        let sourceTabs = tabs.filter { $0.spaceID == sourceID }
        guard tabs.count + sourceTabs.count <= 5000 else { return false }
        let folder = NativeFolder(id: UUID().uuidString, spaceID: targetID, name: source.name, collapsed: false)
        folders.append(folder)
        for tab in sourceTabs {
            tabs.append(NativeTab(id: UUID().uuidString, spaceID: targetID, url: tab.url, title: tab.title,
                                  pinned: true, favorite: false, folderID: folder.id))
        }
        return true
    }
    func shareText(for spaceID: String) -> String {
        let name = spaces.first { $0.id == spaceID }?.name ?? "Arc Reborn"
        return ([name] + tabs.filter { $0.spaceID == spaceID && $0.url != "about:blank" }.map {
            ($0.title.isEmpty ? $0.url : $0.title) + "\n" + $0.url
        }).joined(separator: "\n\n")
    }
    func bookmarksHTML(for spaceID: String) -> String {
        func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let name = escape(spaces.first { $0.id == spaceID }?.name ?? "Arc Reborn")
        let links = tabs.filter { $0.spaceID == spaceID && $0.url != "about:blank" }.map {
            "<DT><A HREF=\"\(escape($0.url))\">\(escape($0.title.isEmpty ? $0.url : $0.title))</A>"
        }.joined(separator: "\n")
        return "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n<TITLE>\(name)</TITLE>\n<H1>\(name)</H1>\n<DL><p>\n<DT><H3>\(name)</H3>\n<DL><p>\n\(links)\n</DL><p>\n</DL><p>\n"
    }
}
