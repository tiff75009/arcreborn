import AppKit

final class ArcSyncSettingsView:NSView {
    override var isFlipped:Bool { true }
    private let status = NSTextField(wrappingLabelWithString:"")
    private var activation:ActionButton!, syncNow:ActionButton!, recovery:ActionButton!, review:ActionButton!
    private var observer:NSObjectProtocol?, task:Task<Void,Never>?
    private var busy = false
    override init(frame:NSRect) {
        super.init(frame:frame)
        let title = NSTextField(labelWithString:"Synchronisation chiffrée")
        title.font = .systemFont(ofSize:16,weight:.semibold); title.frame = NSRect(x:0,y:0,width:bounds.width,height:24); addSubview(title)
        let detail = NSTextField(wrappingLabelWithString:"Vos espaces, onglets, épingles, extensions du Chrome Web Store et réglages natifs. Les mots de passe des sites et les fenêtres privées restent sur ce Mac.")
        detail.font = .systemFont(ofSize:12); detail.textColor = .secondaryLabelColor; detail.frame = NSRect(x:0,y:31,width:bounds.width,height:61); addSubview(detail)
        status.frame = NSRect(x:0,y:101,width:bounds.width,height:54); status.font = .systemFont(ofSize:12); status.textColor = .secondaryLabelColor; addSubview(status)
        review = button("Vérifier les extensions…",rect:NSRect(x:0,y:130,width:bounds.width,height:28)) { ArcSync.shared.reviewRestoredExtensions() }
        activation = button("",rect:NSRect(x:0,y:166,width:bounds.width,height:32)) { [weak self] in self?.toggle() }
        syncNow = button("Synchroniser",rect:NSRect(x:0,y:208,width:bounds.width*0.44,height:30)) { [weak self] in
            self?.task = Task { await ArcSync.shared.synchronize() }
        }
        recovery = button("Code de récupération…",rect:NSRect(x:bounds.width*0.46,y:208,width:bounds.width*0.54,height:30)) { [weak self] in self?.showRecovery() }
        observer = NotificationCenter.default.addObserver(forName:ArcSync.changed,object:nil,queue:.main) { [weak self] _ in self?.refresh() }
        refresh()
    }
    required init?(coder:NSCoder) { fatalError() }
    deinit { task?.cancel(); if let observer { NotificationCenter.default.removeObserver(observer) } }
    private func button(_ title:String,rect:NSRect,action:@escaping()->Void)->ActionButton {
        let button = ChapterButton(title,style:.soft,action:action); button.frame = rect; addSubview(button); return button
    }
    private func refresh() {
        let sync = ArcSync.shared
        status.stringValue = sync.status
        review.isHidden = !sync.isEnabled || sync.reviewProfile == nil
        status.frame.size.height = review.isHidden ? 54 : 28
        activation.title = sync.isEnabled ? "Mettre en pause sur ce Mac" : "Activer sur ce Mac…"
        activation.isEnabled = !busy && sync.configured
        syncNow.isEnabled = sync.isEnabled && !busy && !sync.isWorking
        recovery.isEnabled = !busy && sync.hasRecoveryCode
    }
    private func codeDialog(importing:Bool,code:String,showOnly:Bool = false) async -> String? {
        guard let window else { return nil }
        let alert = NSAlert()
        alert.messageText = importing ? "Retrouvez votre navigateur" : "Votre code de récupération"
        alert.informativeText = importing
            ? "Collez le code enregistré lors de l’activation sur votre premier appareil. Les données de ce Mac seront fusionnées avec votre compte."
            : "Enregistrez ce code dans votre gestionnaire de mots de passe. Il sera nécessaire sur un nouvel appareil. Sans ce code ni un appareil déjà connecté, vos données chiffrées ne pourront pas être récupérées, même après un changement de mot de passe."
        alert.addButton(withTitle:showOnly ? "Fermer" : (importing ? "Déverrouiller et synchroniser" : "J’ai enregistré mon code"))
        if !showOnly { alert.addButton(withTitle:"Annuler") }
        let accessory = NSView(frame:NSRect(x:0,y:0,width:380,height:106))
        let field = NSTextField(string:code)
        field.frame = NSRect(x:0,y:40,width:380,height:62); field.font = .monospacedSystemFont(ofSize:12,weight:.medium)
        field.isEditable = importing; field.isSelectable = true; field.placeholderString = "AR1-…"; field.cell?.wraps = true; field.cell?.isScrollable = false
        field.setAccessibilityLabel("Code de récupération de la synchronisation")
        accessory.addSubview(field)
        if !importing {
            let copy = ActionButton("Copier le code") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code,forType:.string) }
            copy.isBordered = true; copy.bezelStyle = .rounded; copy.frame = NSRect(x:0,y:0,width:150,height:32); accessory.addSubview(copy)
        }
        alert.accessoryView = accessory
        let response = await withCheckedContinuation { continuation in alert.beginSheetModal(for:window) { continuation.resume(returning:$0) } }
        return response == .alertFirstButtonReturn ? field.stringValue : nil
    }
    private func toggle() {
        guard !busy else { return }
        if ArcSync.shared.isEnabled {
            do { try ArcSync.shared.pause() } catch { status.stringValue = error.localizedDescription }
            refresh(); return
        }
        let owner = ArcAccount.shared.user?.id
        busy = true; refresh()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let key:Data
                if let code = try? ArcSync.shared.recoveryCode() { key = try ArcSyncCodec.key(from:code) }
                else if try await ArcSync.shared.remoteExists() {
                    guard let code = await self.codeDialog(importing:true,code:"") else { self.busy = false; self.refresh(); return }
                    key = try ArcSyncCodec.key(from:code)
                } else {
                    key = ArcSyncCodec.newKey()
                    guard await self.codeDialog(importing:false,code:ArcSyncCodec.recoveryCode(key)) != nil else { self.busy = false; self.refresh(); return }
                }
                guard !Task.isCancelled, ArcAccount.shared.user?.id == owner else { throw CancellationError() }
                try await ArcSync.shared.enable(key:key)
                self.busy = false; self.refresh()
            } catch { self.busy = false; self.refresh(); self.status.stringValue = error.localizedDescription }
        }
    }
    private func showRecovery() {
        guard !busy else { return }
        do {
            let code = try ArcSync.shared.recoveryCode()
            task = Task { [weak self] in _ = await self?.codeDialog(importing:false,code:code,showOnly:true) }
        } catch { status.stringValue = error.localizedDescription }
    }
}
