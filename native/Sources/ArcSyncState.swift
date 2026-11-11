import Foundation
import CryptoKit

enum ArcSyncCodec {
    struct Payload: Codable { let format: Int; let owner: String; let session: BrowserSession }
    static let maximumPlaintextBytes = 5 * 1024 * 1024
    static func newKey() -> Data { SymmetricKey(size:.bits256).withUnsafeBytes { Data($0) } }
    static func recoveryCode(_ key:Data) -> String {
        let text = key.map { String(format:"%02X",$0) }.joined()
        return "AR1-" + stride(from:0,to:text.count,by:8).map { offset in
            let start = text.index(text.startIndex,offsetBy:offset)
            return String(text[start..<text.index(start,offsetBy:8)])
        }.joined(separator:"-")
    }
    static func key(from code:String) throws -> Data {
        let raw = code.uppercased().filter { !$0.isWhitespace }
        guard raw.hasPrefix("AR1-") else { throw ArcAccount.Failure.message("Le code doit commencer par AR1-.") }
        let hex = String(raw.dropFirst(4)).replacingOccurrences(of:"-",with:"")
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { throw ArcAccount.Failure.message("Le code de récupération est incomplet.") }
        var data = Data()
        for offset in stride(from:0,to:64,by:2) {
            let start = hex.index(hex.startIndex,offsetBy:offset)
            guard let byte = UInt8(hex[start..<hex.index(start,offsetBy:2)],radix:16) else { throw ArcAccount.Failure.message("Code invalide.") }
            data.append(byte)
        }
        return data
    }
    static func canonical(_ session:BrowserSession) -> BrowserSession {
        var result = session
        result.cloudSyncState = nil
        for i in result.tabs.indices where result.tabs[i].archivedNavigation != nil { result.tabs[i].archivedNavigation = nil }
        for i in result.closedTabs.indices where result.closedTabs[i].archivedNavigation != nil { result.closedTabs[i].archivedNavigation = nil }
        result.onboardingComplete = true
        // Navigation selection and sidebar visibility belong to each device/window.
        result.classicSidebarHidden = nil
        result.sidebarHidden = false
        result.activeSpaceID = result.spaces.first?.id ?? result.activeSpaceID
        for i in result.spaces.indices { result.spaces[i].selectedTabID = nil }
        // A document URL and its title describe a file on this Mac only.
        let files = Set(result.tabs.lazy.filter { isLocalTabDocument($0.url) }.map(\.id))
        result.closedTabs.removeAll { isLocalTabDocument($0.url) }
        if !files.isEmpty {
            result.tabs.removeAll { files.contains($0.id) }
            result.splitGroups?.removeAll { $0.tabIDs.contains(where:files.contains) }
            for i in result.tabs.indices where result.tabs[i].favoriteSourceID.map(files.contains) == true { result.tabs[i].favoriteSourceID = nil }
            for i in result.closedTabs.indices where result.closedTabs[i].favoriteSourceID.map(files.contains) == true { result.closedTabs[i].favoriteSourceID = nil }
        }
        return result
    }
    static func storeIDs(in settings:[String:Any]) -> [String] {
        settings.compactMap { id, raw in
            guard NativeProfile.validStoreID(id), let item = raw as? [String:Any],
                  item["from_webstore"] as? Bool == true,
                  let location = item["location"] as? Int, [1, 6].contains(location),
                  item["path"] is String, item["was_installed_by_default"] as? Bool != true,
                  item["was_installed_by_oem"] as? Bool != true else { return nil }
            return id
        }.sorted()
    }

    static func samplingExtensions(in session:BrowserSession, baseline:BrowserSession?,
                                   previous:[String:[String]], inventory:(String)->[String]?)
        -> (session:BrowserSession, observed:[String:[String]]) {
        var local = session, observations = [String:[String]]()
        for i in local.profiles.indices {
            let profile = local.profiles[i].id
            let saved = baseline?.profiles.first { $0.id == profile }?.storeExtensionIDs
            local.profiles[i].storeExtensionIDs = saved
            guard !profile.hasPrefix("private-") else { continue }
            guard let installed = inventory(profile) else {
                observations[profile] = previous[profile]
                continue
            }
            observations[profile] = installed
            let now = Set(installed), before = Set(previous[profile] ?? [])
            let desired = Set(saved ?? []).subtracting(before.subtracting(now))
                .union(saved == nil ? now : now.subtracting(before))
            local.profiles[i].storeExtensionIDs = desired.sorted()
        }
        return (local,observations)
    }
    static func encrypt(_ session:BrowserSession,key:Data,owner:String) throws -> String {
        let state = canonical(session)
        guard key.count == 32, state.validated(), !state.profiles.contains(where:{ $0.id.hasPrefix("private-") }) else { throw SessionStoreError.invalidState }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Payload(format:1,owner:owner,session:state))
        guard bytes.count <= maximumPlaintextBytes else { throw ArcAccount.Failure.message("Votre session est trop volumineuse pour être synchronisée. Elle reste enregistrée sur ce Mac.") }
        let sealed = try AES.GCM.seal(bytes,using:SymmetricKey(data:key),authenticating:Data(("arc-reborn/sync/v1/"+owner).utf8))
        return sealed.combined!.base64EncodedString()
    }
    static func decrypt(_ ciphertext:String,key:Data,owner:String) throws -> BrowserSession {
        guard key.count == 32, ciphertext.utf8.count <= 8*1024*1024,
              let bytes = Data(base64Encoded:ciphertext), bytes.count >= 28 else { throw SessionStoreError.invalidState }
        let plaintext:Data
        do { plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined:bytes),using:SymmetricKey(data:key),authenticating:Data(("arc-reborn/sync/v1/"+owner).utf8)) }
        catch { throw ArcAccount.Failure.message("Ce code ne permet pas de déchiffrer votre compte. Vos données locales sont conservées.") }
        guard plaintext.count <= maximumPlaintextBytes else { throw SessionStoreError.oversizedFile }
        let payload = try JSONDecoder().decode(Payload.self,from:plaintext)
        guard payload.format == 1, payload.owner == owner, payload.session.validated(), payload.session.cloudSyncState == nil,
              !payload.session.profiles.contains(where: { $0.id.hasPrefix("private-") }) else { throw SessionStoreError.invalidState }
        return canonical(payload.session)
    }
    static func merge(local:BrowserSession,baseline:BrowserSession?,remote:BrowserSession) throws -> BrowserSession {
        let hasLocalDocuments = local.tabs.contains { isLocalTabDocument($0.url) } || local.closedTabs.contains { isLocalTabDocument($0.url) }
        let local = canonical(local), remote = canonical(remote)
        // A fresh installation restores the existing workspace without adding an
        // extra empty Personal space. A used installation merges by stable ID.
        if baseline == nil && !hasLocalDocuments && local.profiles.count == 1 && local.profiles[0].storeExtensionIDs?.isEmpty != false && local.spaces.count == 1 && local.folders.isEmpty && local.closedTabs.isEmpty
            && local.tabs.allSatisfy({ $0.url == "about:blank" && !$0.pinned }) { return remote }
        var empty = local
        empty.profiles = []; empty.spaces = []; empty.tabs = []; empty.closedTabs = []; empty.folders = []; empty.splitGroups = nil
        let base = baseline.map(canonical) ?? empty
        var merged = try BrowserSession.merging(base:base,incoming:local,latest:remote)
        for i in merged.profiles.indices {
            let id = merged.profiles[i].id
            let old = base.profiles.first { $0.id == id }?.storeExtensionIDs
            let incoming = local.profiles.first { $0.id == id }?.storeExtensionIDs
            let latest = remote.profiles.first { $0.id == id }?.storeExtensionIDs
            guard old != nil || incoming != nil || latest != nil else { continue }
            // Missing metadata from an older client is not an uninstall. Apply
            // changes per extension so concurrent installations both survive.
            let before = Set(old ?? []), edited = Set(incoming ?? old ?? [])
            merged.profiles[i].storeExtensionIDs = Set(latest ?? old ?? [])
                .subtracting(before.subtracting(edited)).union(edited.subtracting(before)).sorted()
        }
        return canonical(merged)
    }
    static func applying(_ merged:BrowserSession,to latest:BrowserSession,checkpointKey:String,checkpoint:NativeCloudCheckpoint) throws -> BrowserSession {
        var result = merged
        func hasLocalData(_ tab:NativeTab) -> Bool { tab.archivedNavigation != nil || isLocalTabDocument(tab.url) }
        if latest.tabs.contains(where:hasLocalData) || latest.closedTabs.contains(where:hasLocalData) {
            // Merge cloud edits over the full session to keep local documents,
            // split groups and this Mac's navigation snapshots.
            result = try BrowserSession.merging(base:canonical(latest),incoming:merged,latest:latest)
        }
        result.onboardingComplete = latest.onboardingComplete
        result.classicSidebarHidden = nil
        result.sidebarHidden = latest.sidebarHidden
        if result.spaces.contains(where: { $0.id == latest.activeSpaceID }) { result.activeSpaceID = latest.activeSpaceID }
        for i in result.spaces.indices {
            let localSelected = latest.spaces.first(where: { $0.id == result.spaces[i].id })?.selectedTabID
            result.spaces[i].selectedTabID = localSelected.flatMap { result.canSelectTab($0,in:result.spaces[i].id) ? $0 : nil }
                ?? result.tabs.first(where: { $0.spaceID == result.spaces[i].id })?.id
        }
        result.cloudSyncState = latest.cloudSyncState ?? [:]
        result.cloudSyncState?[checkpointKey] = checkpoint
        return result
    }
}
