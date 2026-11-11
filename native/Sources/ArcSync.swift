import Foundation
import CryptoKit
import Security

@MainActor final class ArcSync {
    static let shared = ArcSync()
    static let changed = Notification.Name("ArcRebornSyncChanged")
    struct Remote: Decodable { let format:Int; let revision:Int; let ciphertext:String? }
    private struct Upload: Encodable { let format = 1; let baseRevision:Int; let ciphertext:String }
    private struct Receipt: Decodable { let revision:Int }
    private var current: (() -> BrowserSession?)?
    private var apply: ((BrowserSession) throws -> Void)?
    private let extensionEngine = BrowserEngine()
    private var observer:NSObjectProtocol?, timer:Timer?, pending:Task<Void,Never>?
    private var running = false, generation = 0
    private(set) var status = "Désactivée sur ce Mac"
    private(set) var isWorking = false
    private(set) var reviewProfile:NativeProfile?
    var configured:Bool { current != nil }
    private var account:ArcAccount { .shared }
    private var identifier:String? {
        guard let user = account.user, let server = account.server else { return nil }
        return SHA256.hash(data:Data((server.absoluteString+"|"+user.id).utf8)).map { String(format:"%02x",$0) }.joined()
    }
    private var checkpoint:NativeCloudCheckpoint? { guard let identifier else { return nil }; return current?()?.cloudSyncState?[identifier] }
    var isEnabled:Bool { checkpoint?.enabled == true }
    var hasRecoveryCode:Bool { checkpoint != nil }

    func configure(current:@escaping()->BrowserSession?,apply:@escaping(BrowserSession)throws->Void) {
        guard self.current == nil else { return }
        self.current = current; self.apply = apply
        observer = NotificationCenter.default.addObserver(forName:ArcAccount.changed,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.accountChanged() }
        }
        timer = Timer.scheduledTimer(withTimeInterval:30,repeats:true) { [weak self] _ in
            Task { @MainActor in await self?.synchronize() }
        }
        Task { await account.refresh(); accountChanged() }
    }
    private func accountChanged() {
        generation += 1; pending?.cancel()
        reviewProfile = nil
        updateStatus(isEnabled ? "Synchronisation…" : "Désactivée sur ce Mac")
        localChanged()
    }
    private func updateStatus(_ value:String,working:Bool = false) {
        status = value; isWorking = working
        NotificationCenter.default.post(name:Self.changed,object:nil)
    }
    func localChanged() {
        guard isEnabled else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:3_000_000_000); try Task.checkCancellation() }
            catch { return }
            self?.pending = nil
            await self?.synchronize()
        }
    }
    private func extensionSettings(_ profile:String) -> [String:Any]? {
        if let live = extensionEngine.extensionSettings(profile:profile) { return live }
        // An unopened profile may already have installs. nil from a profile
        // being initialized or an unreadable file is not an empty inventory.
        guard let directory = BrowserEngine.historyImportDirectory(for:profile,initialize:false) else { return nil }
        return ExtensionCatalog.diskSettings(in:directory)
    }
    func reviewRestoredExtensions() {
        guard isEnabled, let profile = reviewProfile else { return }
        _ = extensionEngine.showExtensions(profile:profile.id,name:profile.name,store:false)
    }
    private func keyQuery(_ identifier:String)->[String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"app.arc-reborn.sync",kSecAttrAccount as String:identifier]
    }
    private func readKey(_ identifier:String) throws -> Data? {
        var query = keyQuery(identifier); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value:CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary,&value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data, data.count == 32 else { throw ArcAccount.Failure.message("Déverrouillez le trousseau pour reprendre la synchronisation.") }
        return data
    }
    private func rememberKey(_ key:Data,identifier:String) throws {
        let query = keyQuery(identifier)
        let status = SecItemUpdate(query as CFDictionary,[kSecValueData as String:key] as CFDictionary)
        if status == errSecItemNotFound {
            var record = query; record[kSecValueData as String] = key
            record[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(record as CFDictionary,nil) == errSecSuccess else { throw ArcAccount.Failure.message("La clé n’a pas pu être enregistrée dans le trousseau.") }
        } else if status != errSecSuccess { throw ArcAccount.Failure.message("Le trousseau n’est pas accessible.") }
    }
    func recoveryCode() throws -> String {
        guard let identifier, let key = try readKey(identifier) else { throw ArcAccount.Failure.message("Aucune clé enregistrée sur ce Mac.") }
        return ArcSyncCodec.recoveryCode(key)
    }
    func remoteExists() async throws -> Bool { try await remote().revision > 0 }
    private func remote() async throws -> Remote {
        let data = try await account.syncRequest()
        let value = try JSONDecoder().decode(Remote.self,from:data)
        guard value.format == 1, value.revision >= 0, (value.revision == 0) == (value.ciphertext == nil) else { throw SessionStoreError.invalidState }
        return value
    }
    private func ensureCurrent(_ owner:String,_ epoch:Int) throws {
        guard account.user?.id == owner, generation == epoch, isEnabled else { throw CancellationError() }
    }
    func enable(key:Data) async throws {
        guard configured, let owner = account.user?.id, let identifier else { throw ArcAccount.Failure.message("Connectez-vous à votre compte dans la fenêtre principale.") }
        let epoch = generation
        let remote = try await remote()
        if let ciphertext = remote.ciphertext { _ = try await Task.detached(priority:.utility) { try ArcSyncCodec.decrypt(ciphertext,key:key,owner:owner) }.value }
        guard account.user?.id == owner, generation == epoch, var local = current?() else { throw CancellationError() }
        try rememberKey(key,identifier:identifier)
        var entry = local.cloudSyncState?[identifier] ?? NativeCloudCheckpoint(enabled:false,revision:0,ciphertext:nil,lastSync:nil)
        entry.enabled = true
        if local.cloudSyncState == nil { local.cloudSyncState = [:] }; local.cloudSyncState?[identifier] = entry
        try apply?(local)
        await synchronize()
    }
    func pause() throws {
        guard let identifier, var local = current?(), var entry = checkpoint else { return }
        generation += 1; pending?.cancel(); entry.enabled = false; local.cloudSyncState?[identifier] = entry
        try apply?(local); reviewProfile = nil; updateStatus("En pause sur ce Mac")
    }
    func synchronize() async {
        guard !running, isEnabled, let owner = account.user?.id, let identifier, let initial = current?() else { return }
        running = true; let epoch = generation
        defer { running = false }
        updateStatus("Synchronisation…",working:true)
        do {
            guard let key = try readKey(identifier) else { throw ArcAccount.Failure.message("Saisissez votre code de récupération pour déverrouiller la synchronisation sur ce Mac.") }
            let baseCiphertext = initial.cloudSyncState?[identifier]?.ciphertext
            let observed = initial.cloudSyncState?[identifier]?.observedExtensions ?? [:]
            let baseline = try await Task.detached(priority:.utility) { try baseCiphertext.map { try ArcSyncCodec.decrypt($0,key:key,owner:owner) } }.value
            for _ in 0..<3 {
                try ensureCurrent(owner,epoch)
                let remote = try await remote()
                try ensureCurrent(owner,epoch)
                guard let state = current?() else { return }
                let sample = ArcSyncCodec.samplingExtensions(in:state,baseline:baseline,previous:observed) { profile in
                    extensionSettings(profile).map(ArcSyncCodec.storeIDs)
                }
                let local = sample.session
                let result = try await Task.detached(priority:.utility) { () throws -> (BrowserSession,String?,Bool) in
                    let cloud = try remote.ciphertext.map { try ArcSyncCodec.decrypt($0,key:key,owner:owner) }
                    let merged = try cloud.map { try ArcSyncCodec.merge(local:local,baseline:baseline,remote:$0) } ?? ArcSyncCodec.canonical(local)
                    let needsUpload = cloud != merged
                    return (merged,needsUpload ? try ArcSyncCodec.encrypt(merged,key:key,owner:owner) : remote.ciphertext,needsUpload)
                }.value
                try ensureCurrent(owner,epoch)
                var revision = remote.revision
                if result.2 {
                    let payload = try JSONEncoder().encode(Upload(baseRevision:revision,ciphertext:result.1!))
                    do {
                        let reply = try await account.syncRequest(body:payload)
                        let receipt = try JSONDecoder().decode(Receipt.self,from:reply)
                        guard receipt.revision == revision+1 else { throw SessionStoreError.invalidState }
                        revision = receipt.revision
                    } catch ArcAccount.Failure.service(409) { continue }
                }
                try ensureCurrent(owner,epoch)
                guard let latest = current?() else { return }
                // Preserve edits made on this Mac while the network was in flight.
                var approvals = [String:Set<String>](), registered = [String:Set<String>]()
                let latestSample = ArcSyncCodec.samplingExtensions(in:latest,baseline:baseline,previous:observed) { profile in
                    guard let settings = extensionSettings(profile) else { return nil }
                    registered[profile] = Set(settings.keys)
                    let ids = ArcSyncCodec.storeIDs(in:settings)
                    approvals[profile] = Set(ids.filter { id in
                        let item = settings[id] as? [String:Any]
                        // Chromium DISABLE_EXTERNAL_EXTENSION. A deliberate user
                        // disable, a policy block or a revoked install is distinct.
                        return (item?["disable_reasons"] as? [Int])?.contains(1 << 13) == true
                    })
                    return ids
                }
                let applied = try ArcSyncCodec.merge(local:latestSample.session,baseline:local,remote:result.0)
                var entry = NativeCloudCheckpoint(enabled:true,revision:revision,ciphertext:result.1,lastSync:Date(),observedExtensions:sample.observed)
                var withdrawals = [String:[String]]()
                for profile in applied.profiles {
                    let old = baseline?.profiles.first { $0.id == profile.id }?.storeExtensionIDs ?? []
                    let retry = initial.cloudSyncState?[identifier]?.pendingExtensionWithdrawals?[profile.id] ?? []
                    let withdrawn = Set(old).union(retry).subtracting(profile.storeExtensionIDs ?? [])
                    if !withdrawn.isEmpty && !extensionEngine.restoreStoreExtensions([],withdrawPending:withdrawn.sorted(),profile:profile.id) {
                        withdrawals[profile.id] = withdrawn.sorted()
                    }
                }
                entry.pendingExtensionWithdrawals = withdrawals.isEmpty ? nil : withdrawals
                let next = try ArcSyncCodec.applying(applied,to:latest,checkpointKey:identifier,checkpoint:entry)
                guard next.validated() else { throw SessionStoreError.invalidState }
                try apply?(next)
                var awaitingExtensions = false
                reviewProfile = nil
                for profile in applied.profiles {
                    let wanted = Set(profile.storeExtensionIDs ?? [])
                    if reviewProfile == nil, !wanted.isDisjoint(with:approvals[profile.id] ?? []) {
                        reviewProfile = profile
                    }
                    let missing = wanted.subtracting(registered[profile.id] ?? Set(latestSample.observed[profile.id] ?? []))
                    if !missing.isEmpty {
                        awaitingExtensions = true
                        _ = extensionEngine.restoreStoreExtensions(missing.sorted(),withdrawPending:[],profile:profile.id)
                    }
                }
                if let profile = reviewProfile {
                    updateStatus("Extensions à activer dans le profil « "+profile.name+" ».")
                } else {
                    updateStatus(awaitingExtensions ? "Restauration des extensions en cours…" : "À jour · "+DateFormatter.localizedString(from:Date(),dateStyle:.none,timeStyle:.short))
                }
                // Applying the reply also incorporates edits still in window memory.
                if ArcSyncCodec.canonical(current?() ?? next) != result.0 { localChanged() }
                return
            }
            throw ArcAccount.Failure.message("Un autre appareil modifie vos données. La synchronisation réessaiera automatiquement.")
        } catch is CancellationError { /* Account switch/pause must not apply an old response. */ }
        catch {
            guard generation == epoch else { return }
            updateStatus(error.localizedDescription)
        }
    }
}
