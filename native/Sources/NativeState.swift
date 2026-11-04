import Foundation

struct NativeProfile: Codable, Equatable { var id: String; var name: String }
struct NativeCloudCheckpoint: Codable, Equatable {
    var enabled: Bool
    var revision: Int
    var ciphertext: String?
    var lastSync: Date?
}
struct SpaceCreationDraft {
    var name = ""
    var icon = "🪐"
    var profileID: String
    var theme = SpaceTheme.solid("#5747D8")
    var appearance: ThemeAppearance
    var isValid: Bool { validLabel(name) && validIcon(icon) && theme.validated() }
}
struct NativeSpace: Codable, Equatable {
    var id: String
    var name: String
    var color: String
    var icon: String
    var profileID: String
    var selectedTabID: String?
    var theme: SpaceTheme? = nil
    var foldersCollapsed: Bool? = nil
}
struct NativeTab: Codable, Equatable {
    var id: String
    var spaceID: String
    var url: String
    var title: String
    var pinned: Bool
    var favorite: Bool
    var folderID: String?
    var sidebarOrder: Int? = nil
    var favoriteOrder: Int? = nil
    var favoriteSourceID: String? = nil
    var customIcon: String? = nil
    var customTitle: String? = nil
    var developerMode: Bool? = nil
    var developerCaptureColor: String? = nil
    var displayTitle: String { customTitle ?? title }
}
struct NativeFolder: Codable, Equatable {
    var id: String
    var spaceID: String
    var name: String
    var collapsed: Bool
    var liveHost: String? = nil
    var parentID: String? = nil
    var sidebarOrder: Int? = nil
}
struct BrowserSession: Codable, Equatable {
    static let maximumSpaces = 100
    @discardableResult mutating func renameProfile(id: String, name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validLabel(name), let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles[index].name = name
        return true
    }
    @discardableResult mutating func renameTab(id: String, name: String) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty || validLabel(name) else { return false }
        tabs[index].customTitle = name.isEmpty ? nil : name
        return true
    }
    var language: String
    var onboardingComplete: Bool
    var sidebarWidth: Double
    var sidebarHidden: Bool
    var profiles: [NativeProfile]
    var spaces: [NativeSpace]
    var tabs: [NativeTab]
    var folders: [NativeFolder]
    var closedTabs: [NativeTab]
    var activeSpaceID: String
    var themeAppearance: ThemeAppearance? = nil
    var savePasswords: Bool? = nil
    var automaticSignIn: Bool? = nil
    var formSuggestions: Bool? = nil
    var splitGroups: [NativeSplitGroup]? = nil
    var splitShortcuts: [String: SplitKeyBinding]? = nil
    var commandShortcuts: [String: SplitKeyBinding]? = nil
    // Optional for backward-compatible session decoding. Absence means enabled.
    var automaticPictureInPicture: [String: Bool]? = nil
    // Encrypted baseline, committed atomically with the local session. No key/token.
    var cloudSyncState: [String: NativeCloudCheckpoint]? = nil

    func pictureInPictureSiteKey(for tab: NativeTab) -> String? {
        guard let url = URLComponents(string: tab.url), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), !host.isEmpty,
              let profile = spaces.first(where: { $0.id == tab.spaceID })?.profileID else { return nil }
        return profile + "|" + host
    }

    func automaticPictureInPictureEnabled(for tab: NativeTab) -> Bool {
        guard let key = pictureInPictureSiteKey(for: tab) else { return false }
        return automaticPictureInPicture?[key] ?? true
    }

    mutating func setAutomaticPictureInPicture(_ enabled: Bool, for tab: NativeTab) {
        guard let key = pictureInPictureSiteKey(for: tab) else { return }
        if automaticPictureInPicture == nil { automaticPictureInPicture = [:] }
        automaticPictureInPicture?[key] = enabled
    }

    static func fresh(language: String = "fr") -> BrowserSession {
        let language = language == "en" ? "en" : "fr"
        let profileID = UUID().uuidString, spaceID = UUID().uuidString
        let name = language == "fr" ? "Personnel" : "Personal"
        return BrowserSession(language: language, onboardingComplete: false, sidebarWidth: 240,
            sidebarHidden: false, profiles: [NativeProfile(id: profileID, name: name)],
            spaces: [NativeSpace(id: spaceID, name: name, color: "#B367A5", icon: "◈", profileID: profileID, selectedTabID: nil)],
            tabs: [], folders: [], closedTabs: [], activeSpaceID: spaceID)
    }

    func validated() -> Bool {
        guard ["fr", "en"].contains(language), sidebarWidth.isFinite, (180...440).contains(sidebarWidth),
            !profiles.isEmpty, profiles.count <= 50, !spaces.isEmpty, spaces.count <= Self.maximumSpaces,
            tabs.count <= 5000, folders.count <= 1000, closedTabs.count <= 50,
            uniqueIDs(profiles.map(\.id)), uniqueIDs(spaces.map(\.id)), uniqueIDs(tabs.map(\.id)),
            uniqueIDs(folders.map(\.id)), uniqueIDs(closedTabs.map(\.id)),
            profiles.allSatisfy({ validLabel($0.name) }) else { return false }
        let profileIDs = Set(profiles.map(\.id)), spaceIDs = Set(spaces.map(\.id))
        guard spaceIDs.contains(activeSpaceID), spaces.allSatisfy({ space in
            validLabel(space.name) && validColor(space.color) && validIcon(space.icon) && profileIDs.contains(space.profileID)
            && (space.theme?.validated() ?? true)
        }), folders.allSatisfy({ validLabel($0.name) && spaceIDs.contains($0.spaceID) && ($0.liveHost == nil || normalizedLiveHost($0.liveHost!) == $0.liveHost) }) else { return false }
        let foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        for folder in folders {
            var visited: Set<String> = [folder.id]
            var parentID = folder.parentID
            while let id = parentID {
                guard visited.insert(id).inserted, let parent = foldersByID[id],
                      parent.spaceID == folder.spaceID, parent.liveHost == nil else { return false }
                parentID = parent.parentID
            }
        }
        let tabsByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        func validTab(_ tab: NativeTab) -> Bool {
            guard spaceIDs.contains(tab.spaceID), isAllowedBrowserURL(tab.url), tab.title.utf8.count <= 8192,
                !tab.title.contains("\0"), !tab.favorite || tab.pinned else { return false }
            if let name = tab.customTitle, !validLabel(name) { return false }
            if let color = tab.developerCaptureColor, !validColor(color) { return false }
            if let source = tab.favoriteSourceID {
                guard !tab.favorite, tab.folderID == nil, tab.pinned, tabsByID[source]?.favorite == true else { return false }
            }
            if let folderID = tab.folderID { return foldersByID[folderID]?.spaceID == tab.spaceID && foldersByID[folderID]?.liveHost == nil }
            return true
        }
        return tabs.allSatisfy(validTab) && closedTabs.allSatisfy(validTab)
            && closedTabs.allSatisfy { tabsByID[$0.id] == nil }
            && spaces.allSatisfy { space in
                guard let selected = space.selectedTabID else { return true }
                return tabsByID[selected]?.spaceID == space.id
            }
    }

    @discardableResult
    mutating func createSpace(name: String, color: String, icon: String, profileID: String? = nil) -> String {
        let targetProfile = profileID ?? spaces.first(where: { $0.id == activeSpaceID })?.profileID ?? profiles.first?.id
        guard let targetProfile, profiles.contains(where: { $0.id == targetProfile }), spaces.count < Self.maximumSpaces,
            validLabel(name), validColor(color), validIcon(icon) else { return "" }
        let id = UUID().uuidString
        spaces.append(NativeSpace(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), color: color,
            icon: icon, profileID: targetProfile, selectedTabID: nil))
        activeSpaceID = id
        return id
    }

    @discardableResult
    mutating func createSpace(from draft: SpaceCreationDraft) -> String {
        guard draft.isValid else { return "" }
        let id = createSpace(name:draft.name,color:draft.theme.points[0].color,icon:draft.icon,profileID:draft.profileID)
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return "" }
        spaces[index].theme = draft.theme; themeAppearance = draft.appearance
        return id
    }

    @discardableResult
    mutating func createTab(url: String = "about:blank", spaceID: String? = nil) -> String {
        let spaceID = spaceID ?? activeSpaceID
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }), tabs.count < 5000, isAllowedBrowserURL(url) else { return "" }
        let id = UUID().uuidString
        tabs.append(NativeTab(id: id, spaceID: spaceID, url: url, title: "", pinned: false, favorite: false, folderID: nil))
        spaces[spaceIndex].selectedTabID = id
        activeSpaceID = spaceID
        return id
    }

    mutating func closeTab(id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        var tab = tabs[index]
        if tab.favorite { detachFavoriteReferences(to:id) }
        tab.favoriteSourceID = nil
        let oldPeers = tabs.filter { $0.spaceID == tab.spaceID }
        let position = oldPeers.firstIndex(where: { $0.id == id }) ?? 0
        detachSplitTab(id)
        tabs.remove(at: index)
        closedTabs.removeAll { $0.id == id }
        closedTabs.append(tab)
        if closedTabs.count > 50 { closedTabs.removeFirst(closedTabs.count - 50) }
        if let spaceIndex = spaces.firstIndex(where: { $0.id == tab.spaceID }), spaces[spaceIndex].selectedTabID == id {
            let peers = tabs.filter { $0.spaceID == tab.spaceID }
            spaces[spaceIndex].selectedTabID = peers.isEmpty ? nil : peers[min(position, peers.count - 1)].id
        }
    }

    mutating func restoreTab() {
        guard tabs.count < 5000, let tab = closedTabs.last,
            let spaceIndex = spaces.firstIndex(where: { $0.id == tab.spaceID }), !tabs.contains(where: { $0.id == tab.id }) else { return }
        closedTabs.removeLast()
        var restored = tab
        if let folderID = restored.folderID, !folders.contains(where: { $0.id == folderID && $0.spaceID == restored.spaceID }) {
            restored.folderID = nil
        }
        tabs.append(restored)
        spaces[spaceIndex].selectedTabID = restored.id
        activeSpaceID = restored.spaceID
    }

    mutating func selectTab(id: String) {
        if tabs.contains(where: { $0.id == id && $0.favorite }) { _ = selectFavorite(id); return }
        guard let tab = tabs.first(where: { $0.id == id }), let index = spaces.firstIndex(where: { $0.id == tab.spaceID }) else { return }
        activeSpaceID = tab.spaceID
        spaces[index].selectedTabID = tab.id
    }

    mutating func removeSpace(id: String) {
        guard spaces.count > 1, spaces.contains(where: { $0.id == id }) else { return }
        let surviving = spaces.first { $0.id != id }!.id
        for i in tabs.indices where tabs[i].spaceID == id && tabs[i].favorite {
            tabs[i].spaceID = surviving; tabs[i].folderID = nil
        }
        spaces.removeAll { $0.id == id }
        tabs.removeAll { $0.spaceID == id }
        closedTabs.removeAll { $0.spaceID == id }
        folders.removeAll { $0.spaceID == id }
        if activeSpaceID == id { activeSpaceID = spaces[0].id }
    }
}

private func uniqueIDs(_ values: [String]) -> Bool {
    values.allSatisfy { $0.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil }
        && Set(values).count == values.count
}
private func validLabel(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= 120
        && value.rangeOfCharacter(from: .controlCharacters) == nil
}
private func validColor(_ value: String) -> Bool { value.range(of: "^#[a-fA-F0-9]{6}$", options: .regularExpression) != nil }
private func validIcon(_ value: String) -> Bool { !value.isEmpty && value.count <= 32 && value.rangeOfCharacter(from: .controlCharacters) == nil }

/// Stored/navigated URLs are stricter than address-bar input: no credentials, control characters or local schemes.
// Only explicitly supported Chromium pages are allowed; aliases entered in
// the address field are normalized before navigation and persistence.
func isExtensionsAddress(_ input: String) -> Bool {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return ["arc://extensions", "arc://extensions/", "browser://extensions", "browser://extensions/", "chrome://extensions", "chrome://extensions/"].contains(value)
}

func settingsPageURL(_ input: String) -> URL? {
    guard input.utf8.count <= 32768,
          input.rangeOfCharacter(from:.whitespacesAndNewlines.union(.controlCharacters)) == nil, !input.contains("\\"),
          var parts = URLComponents(string:input),
          ["arc","browser","chrome"].contains(parts.scheme?.lowercased() ?? ""), ["settings","password-manager"].contains(parts.host?.lowercased() ?? ""),
          parts.user == nil, parts.password == nil, parts.port == nil else { return nil }
    parts.scheme = "chrome"; parts.host = parts.host?.lowercased()
    if parts.path.isEmpty { parts.path = "/" }
    return parts.url
}

func siteSettingsURL(for site: String) -> URL? {
    guard isAllowedBrowserURL(site), let source = URL(string:site),
          ["http","https"].contains(source.scheme?.lowercased() ?? "") else { return nil }
    var parts = URLComponents(string:"chrome://settings/content/siteDetails")!
    parts.queryItems = [URLQueryItem(name:"site",value:site)]
    // Chromium reads this with URLSearchParams, where a bare '+' means a space.
    parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of:"+",with:"%2B")
    guard let url = parts.url, isAllowedBrowserURL(url.absoluteString) else { return nil }
    return url
}

func browserDisplayAddress(_ address: String) -> String {
    guard let url = settingsPageURL(address), var parts = URLComponents(url:url,resolvingAgainstBaseURL:false) else { return address }
    parts.scheme = "arc"
    return parts.string ?? address
}

func isAllowedBrowserURL(_ input: String) -> Bool {
    guard input.utf8.count <= 32768, input.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
        !input.contains("\\") else { return false }
    if input == "about:blank" || input == "chrome://extensions/" || input == "chrome://history/" { return true }
    if URLComponents(string:input)?.scheme?.lowercased() == "chrome", settingsPageURL(input) != nil { return true }
    if let url = URLComponents(string:input), url.scheme == "chrome-extension", let id = url.host,
       id.count == 32, id.allSatisfy({ ("a"..."p").contains(String($0)) }), url.user == nil, url.password == nil, url.port == nil { return true }
    guard let components = URLComponents(string: input), let scheme = components.scheme?.lowercased(),
        ["http", "https"].contains(scheme), let host = components.host, !host.isEmpty,
        components.user == nil, components.password == nil, components.url != nil else { return false }
    return true
}

/// Resolve an address or a search query. Unsupported schemes return nil rather than execute.
func browserURL(_ input: String) -> URL? {
    guard input.utf8.count <= 32768 else { return nil }
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty || text == "about:blank" { return URL(string: "about:blank") }
    guard text.rangeOfCharacter(from: .controlCharacters) == nil, !text.contains("\\") else { return nil }
    if let settings = settingsPageURL(text) { return settings }
    let local = text.range(of: "^(?:localhost|\\[[0-9a-fA-F:]+\\]|[0-9]{1,3}(?:\\.[0-9]{1,3}){3})(?::[0-9]+)?(?:[/?#]|$)", options: .regularExpression) != nil
    let hostPort = text.range(of: "^[^\\s/:?#]+:[0-9]+(?:[/?#]|$)", options: .regularExpression) != nil
    let scheme = text.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*:", options: .regularExpression) != nil
    if scheme && !local && !hostPort { return isAllowedBrowserURL(text) ? URL(string: text) : nil }
    let domain = text.range(of: "^[^/?#]+\\.[^/?#]+(?:[/?#]|$)", options: .regularExpression) != nil
    if text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil && (local || hostPort || domain) {
        let address = "\(local ? "http" : "https")://\(text)"
        return isAllowedBrowserURL(address) ? URL(string: address) : nil
    }
    var search = URLComponents(string: "https://www.google.com/search")!
    search.queryItems = [URLQueryItem(name: "q", value: text)]
    return search.url
}

enum SessionStoreError: LocalizedError {
    case invalidState, unsafePath, oversizedFile
    var errorDescription: String? {
        switch self {
        case .invalidState: return "The browser session is invalid. It was not saved."
        case .unsafePath: return "The session path must be an ordinary file in a real directory."
        case .oversizedFile: return "The browser session exceeds the 32 MiB limit."
        }
    }
}

/// Calls are serialized by a lock; writes use a same-directory temporary and an atomic rename.
final class SessionStore {
    let directory: URL
    let fileURL: URL
    let backupURL: URL
    private(set) var recoveryNotice: String?
    private let lock = NSLock()
    private let manager = FileManager.default
    private let maximumBytes = 32 * 1024 * 1024
    var saveHandler: ((BrowserSession) throws -> Void)?
    var memoryOnly = false

    init(directory: URL) {
        self.directory = directory.standardizedFileURL
        self.fileURL = self.directory.appendingPathComponent("session.json")
        self.backupURL = self.directory.appendingPathComponent("session.backup.json")
    }

    func load() throws -> BrowserSession? {
        lock.lock(); defer { lock.unlock() }
        try prepare()
        if let data = try read(fileURL) {
            if let state = decode(data) { return state }
            let corrupt = directory.appendingPathComponent("session.corrupt-\(UUID().uuidString).json")
            try manager.moveItem(at: fileURL, to: corrupt)
            recoveryNotice = "Invalid session preserved at \(corrupt.path)."
        }
        if let data = try read(backupURL) {
            if let state = decode(data) {
                try atomicWrite(data, to: fileURL)
                recoveryNotice = (recoveryNotice.map { $0 + " " } ?? "") + "Previous session recovered."
                return state
            }
            recoveryNotice = (recoveryNotice.map { $0 + " " } ?? "") + "Invalid backup was left intact."
        }
        return nil
    }

    func save(_ state: BrowserSession) throws {
        guard state.validated() else { throw SessionStoreError.invalidState }
        if let saveHandler { try saveHandler(state); return }
        if memoryOnly { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= maximumBytes else { throw SessionStoreError.oversizedFile }
        lock.lock(); defer { lock.unlock() }
        try prepare()
        if let previous = try read(fileURL), decode(previous) != nil { try atomicWrite(previous, to: backupURL) }
        try atomicWrite(data, to: fileURL)
    }

    private func prepare() throws {
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try manager.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw SessionStoreError.unsafePath }
    }
    private func read(_ url: URL) throws -> Data? {
        do {
            let attributes = try manager.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw SessionStoreError.unsafePath }
            guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= maximumBytes else { throw SessionStoreError.oversizedFile }
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }
    private func decode(_ data: Data) -> BrowserSession? {
        guard let state = try? JSONDecoder().decode(BrowserSession.self, from: data), state.validated() else { return nil }
        return state
    }
    private func atomicWrite(_ data: Data, to destination: URL) throws {
        // A symlink is rejected instead of replacing an unexpected destination.
        _ = try read(destination)
        let temporary = directory.appendingPathComponent(".session-\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw SessionStoreError.unsafePath }
        defer { try? manager.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        // POSIX rename replaces atomically without a missing-file window.
        let status = temporary.path.withCString { source in destination.path.withCString { target in rename(source, target) } }
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
