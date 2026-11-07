import Foundation
import UniformTypeIdentifiers

enum LibrarySection: String, CaseIterable {
    case media, downloads, notes, spaces, archived
    var index: Int { Self.allCases.firstIndex(of:self)! }
}

struct LibraryDownload: Codable, Equatable {
    var id: String
    var name: String
    var path: String
    var source: String
    var profileID: String
    var date: Date
    var received: Int64
    var total: Int64
    var state: String
    var speed: Int64? = nil
    var unread: Bool? = nil
    var guid: String?
    var originalURL: String?
    var originatingPage: String?
    var canContinue: Bool?
    var runtimeID: String?
    var isRecovering: Bool { state == "recovering" }
    var isBlocked: Bool { state == "blocked" }
    static func blockedLabel(_ language: String) -> String {
        language == "fr" ? "Bloqué pour votre sécurité" : "Blocked for your safety"
    }
    var recoveryAction: String? {
        guard state == "interrupted", !profileID.isEmpty else { return nil }
        if Self.isWebAddress(originalURL ?? source) {
            return canContinue == true && guid?.isEmpty == false ? "resume" : "restart"
        }
        return originatingPage.map(Self.isWebAddress) == true ? "page" : nil
    }
    static func isWebAddress(_ address:String) -> Bool {
        guard let url = URLComponents(string:address), url.host?.isEmpty == false else { return false }
        return ["http","https"].contains(url.scheme?.lowercased() ?? "")
    }
    mutating func checkPartialFile() {
        guard canContinue == true else { return }
        let file = try? URL(fileURLWithPath:path).resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        canContinue = file?.isRegularFile == true && file?.isSymbolicLink != true && (file?.fileSize ?? 0) > 0
    }
    var isActive: Bool { state == "progress" || state == "paused" }
    var fraction: Double { total > 0 ? max(0,min(1,Double(received)/Double(total))) : 0 }
}
struct LibraryMedia: Equatable {
    let url: URL
    let date: Date
    let size: Int64
    let kind: String
    var name: String { url.lastPathComponent }
    var cacheKey: String { url.path + "|\(date.timeIntervalSince1970)|\(size)" }
}
enum LibraryMediaScanner {
    static func scan(_ directory: URL) throws -> [LibraryMedia] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey,.isSymbolicLinkKey,.contentTypeKey,.contentModificationDateKey,.creationDateKey,.fileSizeKey,.isUbiquitousItemKey,.ubiquitousItemDownloadingStatusKey]
        return try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:Array(keys),options:[.skipsHiddenFiles]).compactMap { url in
            guard let values = try? url.resourceValues(forKeys:keys), values.isRegularFile == true, values.isSymbolicLink != true,
                  !(values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded),
                  let type = values.contentType ?? UTType(filenameExtension:url.pathExtension) else { return nil }
            let kind: String
            if type.conforms(to:.image) { kind = "image" }
            else if type.conforms(to:.movie) { kind = "video" }
            else if type.conforms(to:.audio) { kind = "audio" }
            else { return nil }
            return LibraryMedia(url:url,date:values.contentModificationDate ?? values.creationDate ?? .distantPast,size:Int64(values.fileSize ?? 0),kind:kind)
        }.sorted { $0.date == $1.date ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.date > $1.date }
    }
    static func matching(_ media: [LibraryMedia], query: String) -> [LibraryMedia] {
        let query = query.trimmingCharacters(in:.whitespacesAndNewlines)
        return query.isEmpty ? media : media.filter { $0.name.localizedStandardContains(query) }
    }
}
final class LibraryStore {
    private final class WeakStore { weak var value:LibraryStore?; init(_ value:LibraryStore) { self.value = value } }
    private static var instances:[WeakStore] = []
    private var peers:[LibraryStore] { Self.instances.compactMap(\.value).filter { $0 !== self && $0.persistent && $0.file == file } }
    private func publishMetadata() {
        guard persistent else { return }
        for peer in peers { peer.saved = saved; peer.captures = captures; peer.downloadsChanged?(); peer.changed?() }
    }
    private struct Saved: Codable {
        var mediaEnabled = false
        var downloads: [LibraryDownload] = []
        var hiddenRecents: [String]? = nil
        var lastSection: String? = nil
    }
    private var saved: Saved
    private let file: URL
    private let persistent: Bool
    private(set) var downloadsDirectory: URL
    let capturesDirectory: URL
    private var captures: [LibraryMedia] = []
    private let queue = DispatchQueue(label:"Browser.Library.scan",qos:.utility)
    private var saveTask: DispatchWorkItem?
    private var scanning = false
    private var scanAgain = false
    private var generation = 0
    private var timer: Timer?
    var changed: (() -> Void)?
    var downloadsChanged: (() -> Void)?
    var downloadBlocked: (() -> Void)?
    var identifyLegacy: ((LibraryDownload,UInt32,@escaping (String?) -> Void) -> Void)?
    private var checkingLegacy = Set<String>()
    var openDownloadPage: ((LibraryDownload, String) -> Void)?
    var recover: ((LibraryDownload, String) -> Void)?
    var control: ((String,String) -> Void)?
    var unreadCount: Int { saved.downloads.filter { $0.state == "complete" && $0.unread == true }.count }
    var activeDownloads: [LibraryDownload] { downloads.filter(\.isActive) }
    var peekDownloads: [LibraryDownload] {
        (activeDownloads + downloads.filter { $0.state == "complete" || $0.isBlocked }).prefix(4).sorted { $0.date < $1.date }
    }
    func acknowledge(_ ids: Set<String>) {
        var modified = false
        for i in saved.downloads.indices where ids.contains(saved.downloads[i].id) && saved.downloads[i].state == "complete" && saved.downloads[i].unread == true {
            saved.downloads[i].unread = false; modified = true
        }
        if modified { persist(); downloadsChanged?() }
    }
    func checkLegacyDownload(_ item:LibraryDownload) {
        guard item.recoveryAction == "restart", item.guid == nil, item.canContinue == nil, item.received > 0,
              item.path.hasSuffix(".crdownload"), let suffix = item.id.split(separator:"-").last,
              let key = UInt64(suffix), key >> 32 != 0, let identifyLegacy, !checkingLegacy.contains(item.id) else { return }
        checkingLegacy.insert(item.id)
        let finish: (String?) -> Void = { [weak self] guid in
            guard let self else { return }
            self.checkingLegacy.remove(item.id)
            guard let i = self.saved.downloads.firstIndex(where:{ $0.id == item.id }),
                  self.saved.downloads[i].state == "interrupted", self.saved.downloads[i].guid == nil else { return }
            self.saved.downloads[i].guid = guid
            self.saved.downloads[i].canContinue = guid != nil
            self.persist(); self.downloadsChanged?(); self.changed?()
        }
        // Configure collection items first. A synchronous bridge failure can refresh them.
        DispatchQueue.main.async {
            if FileManager.default.fileExists(atPath:item.path) {
                identifyLegacy(item,UInt32(truncatingIfNeeded:key),finish)
            } else { finish(nil) }
        }
    }
    func request(_ id: String, action: String) {
        guard let i = saved.downloads.firstIndex(where: { $0.id == id }) else { return }
        if saved.downloads[i].isBlocked {
            if action == "remove" { removeDownload(id) }
            return
        }
        if action == "details", saved.downloads[i].isActive {
            openDownloadPage?(saved.downloads[i], "chrome://downloads/")
            return
        }
        if saved.downloads[i].state == "interrupted" {
            guard saved.downloads[i].recoveryAction == action else { return }
            if action == "page", let page = saved.downloads[i].originatingPage { openDownloadPage?(saved.downloads[i],page); return }
            guard let recover else { return }
            saved.downloads[i].checkPartialFile()
            if saved.downloads[i].recoveryAction != action {
                persist(); downloadsChanged?(); changed?()
                return
            }
            let item = saved.downloads[i]
            saved.downloads[i].state = "recovering"
            persist(); downloadsChanged?(); changed?()
            recover(item,action)
            return
        }
        let item = saved.downloads[i]
        guard item.isActive, action == "cancel" || (action == "pause" && item.state == "progress") ||
              (action == "resume" && item.state == "paused") else { return }
        control?(item.runtimeID ?? id,action)
    }
    func recoveryFailed(_ id:String) {
        guard let i = saved.downloads.firstIndex(where: { $0.id == id }), saved.downloads[i].state != "complete", !saved.downloads[i].isBlocked else { return }
        saved.downloads[i].state = "interrupted"
        saved.downloads[i].canContinue = false
        persist(); downloadsChanged?(); changed?()
    }
    private var scannedMedia: [LibraryMedia] = []
    var media: [LibraryMedia] { (captures+scannedMedia).sorted { $0.date > $1.date } }
    var hasCaptures: Bool { !captures.isEmpty }
    private(set) var mediaError: String?
    private(set) var loading = false
    var mediaEnabled: Bool { saved.mediaEnabled }
    var lastSection: LibrarySection {
        guard let key = saved.lastSection, let section = LibrarySection(rawValue:key), section != .notes else { return .media }
        return section
    }
    func rememberSection(_ section: LibrarySection) {
        guard section != .notes, saved.lastSection != section.rawValue else { return }
        saved.lastSection = section.rawValue
        persist()
    }
    var hiddenRecents: Set<String> { Set(saved.hiddenRecents ?? []) }
    func removeDownload(_ id: String) {
        guard let record = saved.downloads.first(where: { $0.id == id }), !record.isActive, !record.isRecovering else { return }
        saved.downloads.removeAll { $0.id == id }
        if !record.path.isEmpty { saved.hiddenRecents = Array(hiddenRecents.union([URL(fileURLWithPath:record.path).standardizedFileURL.path])).suffix(1000).map { $0 } }
        persist(); downloadsChanged?(); changed?()
    }
    func dismissRecentFile(_ url: URL) {
        let path = url.standardizedFileURL.path
        saved.downloads.removeAll { !$0.isActive && !$0.isRecovering && URL(fileURLWithPath:$0.path).standardizedFileURL.path == path }
        saved.hiddenRecents = Array(hiddenRecents.union([path])).suffix(1000).map { $0 }
        persist(); downloadsChanged?(); changed?()
    }
    var downloads: [LibraryDownload] { saved.downloads.sorted { $0.date > $1.date } }
    init(directory: URL, downloadsDirectory: URL? = nil, persistent:Bool = true) {
        self.persistent = persistent
        file = directory.appendingPathComponent("library.json")
        capturesDirectory = directory.appendingPathComponent("Captures",isDirectory:true)
        captures = (try? LibraryMediaScanner.scan(capturesDirectory)) ?? []
        self.downloadsDirectory = downloadsDirectory ?? FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask)[0]
        if let data = try? Data(contentsOf:file), data.count < 4_000_000, let value = try? JSONDecoder().decode(Saved.self,from:data) { saved = value }
        else { saved = Saved() }
        if !persistent { saved.downloads = [] }
        else if let peer = peers.first { saved = peer.saved }
        else {
            for i in saved.downloads.indices {
                if saved.downloads[i].isActive || saved.downloads[i].isRecovering { saved.downloads[i].state = "interrupted" }
                if saved.downloads[i].state == "interrupted" { saved.downloads[i].checkPartialFile() }
            }
        }
        Self.instances.removeAll { $0.value == nil }; Self.instances.append(WeakStore(self))
    }
    func enableMedia() { saved.mediaEnabled = true; persist(); refreshMedia() }
    func useDownloadsDirectory(_ directory:URL) {
        guard directory != downloadsDirectory else { return }
        downloadsDirectory = directory
        generation += 1; scanning = false; scanAgain = false; loading = false
        scannedMedia = []; mediaError = nil
        if mediaEnabled { refreshMedia() } else { changed?() }
    }
    @discardableResult func saveCapture(_ data: Data) throws -> URL {
        try FileManager.default.createDirectory(at:capturesDirectory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let date = DateFormatter(); date.locale = Locale(identifier:"en_US_POSIX"); date.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = capturesDirectory.appendingPathComponent("Capture \(date.string(from:Date())) \(UUID().uuidString.prefix(5)).png")
        try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        captures = try LibraryMediaScanner.scan(capturesDirectory); publishMetadata(); changed?(); return url
    }
    func startObserving() {
        guard timer == nil else { return }
        if mediaEnabled { refreshMedia() }
        // Poll as a fallback for folder replacement and access grants; scanning is off the UI thread.
        timer = Timer.scheduledTimer(withTimeInterval:4,repeats:true) { [weak self] _ in self?.refreshMedia() }
    }
    func stopObserving() { timer?.invalidate(); timer = nil }
    func refreshMedia() {
        guard mediaEnabled else { return }
        if scanning { scanAgain = true; return }
        scanning = true; loading = media.isEmpty; generation += 1
        let token = generation, directory = downloadsDirectory
        changed?()
        queue.async { [weak self] in
            let result = Result { try LibraryMediaScanner.scan(directory) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.scanning = false; self.loading = false
                switch result {
                case .success(let files): self.scannedMedia = files; self.mediaError = nil
                case .failure(let error): self.mediaError = error.localizedDescription
                }
                self.changed?()
                if self.scanAgain { self.scanAgain = false; self.refreshMedia() }
            }
        }
    }
    @discardableResult func receiveDownload(_ values:[String:Any], run:String, profileID:String, recovering id:String? = nil) -> Bool {
        guard let number = values["id"] as? NSNumber, let state = values["state"] as? String else { return false }
        let runtimeID = run+"-"+number.stringValue
        return updateDownload(id:id ?? runtimeID, name:values["name"] as? String ?? "", path:values["path"] as? String ?? "",
                              source:values["url"] as? String ?? "", profileID:profileID, received:(values["received"] as? NSNumber)?.int64Value ?? 0,
                              total:(values["total"] as? NSNumber)?.int64Value ?? 0, state:state, speed:(values["speed"] as? NSNumber)?.int64Value ?? 0,
                              guid:values["guid"] as? String, originalURL:values["originalURL"] as? String,
                              canContinue:values["canContinue"] as? Bool, runtimeID:runtimeID, originatingPage:values["originatingPage"] as? String)
    }
    /// Returns true once a new transfer has a destination, including tiny files
    /// whose first update is already complete. A cancelled save dialog has none.
    @discardableResult func updateDownload(id: String, name: String, path: String, source: String, profileID: String, received: Int64, total: Int64, state: String, speed: Int64 = 0, guid:String? = nil, originalURL:String? = nil, canContinue:Bool? = nil, runtimeID:String? = nil, originatingPage:String? = nil) -> Bool {
        let index = saved.downloads.firstIndex(where: { $0.id == id })
        let previous = index.map { saved.downloads[$0] }
        // A stale cancellation/recovery callback cannot make this transfer retryable.
        if previous?.isBlocked == true { return false }
        let started = (previous?.path ?? "").isEmpty && !path.isEmpty && (state == "progress" || state == "paused" || state == "complete")
        let completed = state == "complete" && previous?.state != "complete"
        if let i = index {
            saved.downloads[i].name = name.isEmpty ? saved.downloads[i].name : name
            saved.downloads[i].path = path.isEmpty ? saved.downloads[i].path : path
            saved.downloads[i].speed = max(0,speed)
            if completed { saved.downloads[i].unread = true }
            saved.downloads[i].received = received; saved.downloads[i].total = total; saved.downloads[i].state = state
        } else {
            saved.downloads.append(LibraryDownload(id:id,name:name,path:path,source:source,profileID:profileID,date:Date(),received:received,total:total,state:state,speed:max(0,speed),unread:completed))
        }
        let row = index ?? saved.downloads.index(before:saved.downloads.endIndex)
        if state == "blocked" { saved.downloads[row].path = "" }
        if !source.isEmpty { saved.downloads[row].source = source }
        if saved.downloads[row].originatingPage == nil, let originatingPage, LibraryDownload.isWebAddress(originatingPage) {
            saved.downloads[row].originatingPage = originatingPage
        }
        if let guid { saved.downloads[row].guid = guid }
        if let originalURL, !originalURL.isEmpty { saved.downloads[row].originalURL = originalURL }
        saved.downloads[row].canContinue = canContinue
        saved.downloads[row].runtimeID = runtimeID == id ? nil : runtimeID
        if state == "interrupted" { saved.downloads[row].checkPartialFile() }
        while saved.downloads.count > 1000, let index = saved.downloads.firstIndex(where: { !$0.isActive && !$0.isRecovering && $0.unread != true }) { saved.downloads.remove(at:index) }
        if completed { saved.hiddenRecents?.removeAll { $0 == URL(fileURLWithPath:path).standardizedFileURL.path } }
        persist(); downloadsChanged?(); changed?()
        if state == "blocked" { downloadBlocked?() }
        if completed { refreshMedia() }
        return started
    }
    func matchingDownloads(query: String, profiles: Set<String>) -> [LibraryDownload] {
        downloads.filter { (profiles.isEmpty || profiles.contains($0.profileID)) && (query.isEmpty || $0.name.localizedStandardContains(query)) }
    }
    private func persist() {
        publishMetadata()
        guard persistent else { return }
        guard saveTask == nil else { return }
        let task = DispatchWorkItem { [weak self] in self?.flush() }; saveTask = task
        DispatchQueue.main.asyncAfter(deadline:.now()+0.4,execute:task)
    }
    func flush() {
        saveTask?.cancel(); saveTask = nil
        guard persistent else { return }
        do {
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try JSONEncoder().encode(saved).write(to:file,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
        } catch { NSLog("Library persistence failed: %@",error.localizedDescription) }
    }
    deinit { timer?.invalidate(); saveTask?.cancel() }
}

struct RecentLibraryFile: Equatable {
    let url: URL
    let date: Date
    static func collect(media: [LibraryMedia], downloads: [LibraryDownload], excluding: Set<String> = []) -> [Self] {
        let candidates = media.map { Self(url:$0.url,date:$0.date) } + downloads.filter { $0.state == "complete" && !$0.path.isEmpty }.map { Self(url:URL(fileURLWithPath:$0.path),date:$0.date) }
        var seen = Set<String>()
        return Array(candidates.sorted { $0.date == $1.date ? $0.url.path < $1.url.path : $0.date > $1.date }.filter {
            let path = $0.url.standardizedFileURL.resolvingSymlinksInPath().path
            var directory: ObjCBool = false
            return !excluding.contains($0.url.standardizedFileURL.path) && FileManager.default.fileExists(atPath:path,isDirectory:&directory) && !directory.boolValue && seen.insert(path).inserted
        }.prefix(4).reversed())
    }
}

