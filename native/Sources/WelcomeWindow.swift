import AppKit
import QuartzCore

private final class WelcomeContent:NSView { override var isFlipped:Bool { true } }
private final class WelcomeSurface: NSView {
    override var isFlipped:Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
    }
}
@discardableResult private func welcomeText(_ text:String,x:CGFloat,y:CGFloat,width:CGFloat,height:CGFloat = 24,size:CGFloat = 13,weight:NSFont.Weight = .regular,color:NSColor = .labelColor,centered:Bool = false,in view:NSView)->NSTextField {
    let label = NSTextField(wrappingLabelWithString:text); label.frame = NSRect(x:x,y:y,width:width,height:height); label.font = .systemFont(ofSize:size,weight:weight); label.textColor = color; if centered { label.alignment = .center }; view.addSubview(label); return label
}
@discardableResult private func welcomeButton(_ title:String,x:CGFloat,y:CGFloat,width:CGFloat,primary:Bool = false,in view:NSView,action:@escaping()->Void)->ActionButton {
    let button = ActionButton(title,action:action); button.frame = NSRect(x:x,y:y,width:width,height:36); button.isBordered = true; button.bezelStyle = .rounded; button.controlSize = .large
    if primary { button.bezelColor = NSColor(calibratedRed:0.43,green:0.30,blue:0.88,alpha:1); button.keyEquivalent = "\r" }
    view.addSubview(button); return button
}

final class BrowserImportView:NSView {
    private final class FolderGrant {
        let url:URL
        let scoped:Bool
        init(_ url:URL) { self.url = url; scoped = url.startAccessingSecurityScopedResource() }
        deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
    }
    override var isFlipped:Bool { true }
    var apply:(([ImportedLink],String)throws->Int)?
    var openSettings:((String)->Void)?
    private var selected = 0, reading = false
    private var profiles:[BrowserImportProfile] = []
    private let profilePicker = NSPopUpButton(frame:.zero,pullsDown:false)
    private var manualButton:ActionButton?
    private var requestID = UUID()
    private var needsAccess = false
    private var grant:FolderGrant?
    private var status:NSTextField?, importButton:ActionButton?
    private let language:String
    private var tiles:[ImportSourceTile] = []
    private func tr(_ fr:String,_ en:String)->String { language == "en" ? en : fr }
    init(frame:NSRect,language:String) { self.language = language; super.init(frame:frame); build() }
    required init?(coder:NSCoder) { fatalError() }
    private func build() {
        let w = bounds.width, gap:CGFloat = 10, tileWidth = (w-3*gap)/4
        welcomeText(tr("Navigateur d’origine","Source browser"),x:0,y:0,width:w,height:23,size:15,weight:.semibold,in:self)
        for (index,browser) in ImportBrowser.all.enumerated() {
            let tile = ImportSourceTile(browser:browser,english:language == "en") { [weak self] in self?.changeBrowser(index) }
            tile.frame = NSRect(x:CGFloat(index)*(tileWidth+gap),y:32,width:tileWidth,height:64)
            tiles.append(tile); addSubview(tile)
        }
        let split:CGFloat = 436
        addSubview(ChapterPlate(NSRect(x:0,y:118,width:split,height:261)))
        addSubview(ChapterPlate(NSRect(x:split+12,y:118,width:w-split-12,height:261)))
        func button(_ title:String,_ x:CGFloat,_ y:CGFloat,_ width:CGFloat,_ style:ChapterButton.Style,action:@escaping()->Void)->ChapterButton {
            let b = ChapterButton(title,style:style,action:action); b.frame = NSRect(x:x,y:y,width:width,height:37); addSubview(b); return b
        }
        welcomeText(tr("Favoris et onglets","Bookmarks and tabs"),x:20,y:140,width:split-40,height:30,size:21,weight:.semibold,in:self)
        welcomeText(tr("Profil","Profile"),x:20,y:181,width:57,height:24,weight:.medium,in:self)
        profilePicker.frame = NSRect(x:76,y:173,width:split-96,height:32)
        profilePicker.setAccessibilityLabel(tr("Profil à importer","Profile to import"))
        profilePicker.target = self; profilePicker.action = #selector(profileChanged)
        addSubview(profilePicker)
        status = welcomeText("",x:20,y:220,width:split-40,height:58,size:13,color:.secondaryLabelColor,in:self)
        importButton = button(tr("Importer","Import"),20,281,split-40,.solid) { [weak self] in self?.importSelected() }
        manualButton = button(tr("Autres options…","Other options…"),20,327,split-40,.link) { [weak self] in self?.showOptions() }
        welcomeText(tr("Autres données","Other data"),x:split+32,y:140,width:w-split-54,height:30,size:21,weight:.semibold,in:self)
        welcomeText(tr("Pour les mots de passe, utilisez un export CSV. L’assistant avancé permet aussi d’importer l’historique selon le navigateur.","Use a CSV export for passwords. The advanced assistant can also import history from supported browsers."),x:split+32,y:180,width:w-split-52,height:82,color:.secondaryLabelColor,in:self)
        _ = button(tr("Mots de passe…","Passwords…"),split+32,270,w-split-52,.soft) { [weak self] in self?.openSettings?("arc://password-manager/settings") }
        _ = button(tr("Import avancé…","Advanced import…"),split+32,319,w-split-52,.soft) { [weak self] in self?.openSettings?("arc://settings/importData") }
        changeBrowser(ImportBrowser.all.firstIndex { $0.application != nil } ?? 0)
    }
    private func changeBrowser(_ index:Int) {
        guard !reading else { return }
        grant = nil
        selected = index
        for (i,tile) in tiles.enumerated() { tile.selected = i == index }
        discoverProfiles()
    }
    private func discoverProfiles() {
        let browser = ImportBrowser.all[selected]
        let folderGrant = grant
        let english = language == "en"
        let token = UUID()
        requestID = token; profiles = []; needsAccess = false
        profilePicker.removeAllItems(); profilePicker.isEnabled = false
        setImportTitle(tr("Importer depuis ","Import from ")+browser.name)
        importButton?.isEnabled = false
        status?.stringValue = tr("Recherche des profils sur ce Mac…","Looking for profiles on this Mac…")
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result = Result { try withExtendedLifetime(folderGrant) {
                try browser.importProfiles(in:folderGrant?.url ?? browser.directory,english:english)
            } }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requestID == token else { return }
                switch result {
                case .success(let profiles):
                    self.profiles = profiles
                    self.profilePicker.addItems(withTitles:profiles.map(\.name))
                    if profiles.isEmpty {
                        self.profilePicker.addItem(withTitle:self.tr("Aucun profil détecté","No profiles found"))
                        self.status?.stringValue = self.tr("Aucun profil local trouvé. Si vous avez une sauvegarde, ouvrez « Autres options ».","No local profile was found. To use a backup, open Other options.")
                    } else { self.profilePicker.selectItem(at:0); self.profileChanged() }
                    self.profilePicker.isEnabled = profiles.count > 1
                case .failure(let error): self.showFailure(error)
                }
            }
        }
    }
    private func setImportTitle(_ title:String) {
        importButton?.title = title; importButton?.setAccessibilityLabel(title); importButton?.needsDisplay = true
    }
    @objc private func profileChanged() {
        guard profiles.indices.contains(profilePicker.indexOfSelectedItem) else { return }
        let hint:String
        switch ImportBrowser.all[selected].bundleID {
        case "com.apple.Safari": hint = tr("Vos favoris Safari seront ajoutés dans un nouvel espace.","Your Safari bookmarks will be added to a new space.")
        case "company.thebrowser.Browser": hint = tr("Vos favoris, épingles et onglets seront ajoutés dans un nouvel espace.","Your favorites, pins and tabs will be added to a new space.")
        default: hint = tr("Les favoris et les onglets de session disponibles seront ajoutés dans un nouvel espace.","Available bookmarks and session tabs will be added to a new space.")
        }
        needsAccess = false; setImportTitle(tr("Importer depuis ","Import from ")+ImportBrowser.all[selected].name)
        importButton?.isEnabled = !reading; status?.stringValue = hint
    }
    private func importSelected() {
        if needsAccess { choose(directory:true,discoverAfterGrant:profiles.isEmpty); return }
        guard profiles.indices.contains(profilePicker.indexOfSelectedItem) else { return }
        readAndImport(profiles[profilePicker.indexOfSelectedItem].url,grantedByPanel:false)
    }
    @objc private func selectFolder() { choose(directory:true) }
    @objc private func selectFile() { choose(directory:false) }
    private func showOptions() {
        guard let manualButton, !reading else { return }
        let menu = NSMenu()
        for (title,action) in [(tr("Importer un fichier exporté…","Import an exported file…"),#selector(selectFile)),(tr("Choisir un autre dossier de profil…","Choose another profile folder…"),#selector(selectFolder))] {
            menu.addItem(withTitle:title,action:action,keyEquivalent:"").target = self
        }
        menu.popUp(positioning:nil,at:NSPoint(x:0,y:manualButton.bounds.maxY),in:manualButton)
    }
    private func choose(directory:Bool,discoverAfterGrant:Bool = false) {
        guard !reading, let window else { return }
        let browser = ImportBrowser.all[selected]
        let panel = NSOpenPanel()
        panel.title = tr("Importer depuis ","Import from ")+browser.name
        panel.prompt = discoverAfterGrant ? tr("Autoriser","Allow") : tr("Importer","Import")
        panel.canChooseDirectories = directory; panel.canChooseFiles = !directory
        panel.allowsMultipleSelection = false
        if directory {
            let index = profilePicker.indexOfSelectedItem
            let location = profiles.indices.contains(index) ? profiles[index].url : browser.directory
            panel.directoryURL = location.lastPathComponent == "Bookmarks.plist" || location.lastPathComponent == "StorableSidebar.json" ? location.deletingLastPathComponent() : location
        }
        panel.beginSheetModal(for:window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            if discoverAfterGrant {
                self.grant = FolderGrant(url); self.discoverProfiles()
            } else { self.readAndImport(url,grantedByPanel:true) }
        }
    }
    private func showFailure(_ error:Error) {
        let browser = ImportBrowser.all[selected]
        let problem = error as NSError
        let denied = (problem.domain == NSCocoaErrorDomain && problem.code == NSFileReadNoPermissionError) || (problem.domain == NSPOSIXErrorDomain && [Int(EPERM),Int(EACCES)].contains(problem.code))
        needsAccess = denied
        if denied {
            status?.stringValue = tr("macOS protège ces données. Autorisez l’accès au dossier de "+browser.name+" pour continuer.","macOS protects this data. Grant access to the "+browser.name+" folder to continue.")
            setImportTitle(tr("Autoriser l’accès…","Allow access…"))
        } else if problem.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(problem.code) {
            status?.stringValue = tr("Aucune donnée compatible trouvée pour ce profil.","No supported data was found for this profile.")
        } else { status?.stringValue = error.localizedDescription }
        importButton?.isEnabled = denied || !profiles.isEmpty
    }
    private func readAndImport(_ url:URL,grantedByPanel:Bool) {
        guard !reading else { return }
        let browser = ImportBrowser.all[selected]
        let token = UUID(); requestID = token
        let folderGrant = grant
        reading = true; profilePicker.isEnabled = false; tiles.forEach { $0.isEnabled = false }
        manualButton?.isEnabled = false; importButton?.isEnabled = false
        status?.stringValue = tr("Importation en cours…","Importing…")
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let access = grantedByPanel && url.startAccessingSecurityScopedResource()
            let result = Result { try withExtendedLifetime(folderGrant) { try BrowserImportReader.preview(at:url,browser:browser) } }
            if access { url.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.requestID == token else { return }
                self.reading = false; self.tiles.forEach { $0.isEnabled = true }; self.manualButton?.isEnabled = true
                self.profilePicker.isEnabled = self.profiles.count > 1
                do {
                    let data = try result.get()
                    guard let apply = self.apply else { return }
                    let count = try apply(data.links,browser.name)
                    let message = count == 0 ? self.tr("Ces éléments sont déjà présents.","These items have already been imported.") : self.tr("\(count) éléments importés dans le nouvel espace.","Imported \(count) items into a new space.")
                    self.status?.stringValue = ([message] + data.warnings.prefix(1)).joined(separator:"\n")
                    self.needsAccess = false; self.setImportTitle(self.tr("Import terminé","Import complete"))
                } catch { self.showFailure(error) }
            }
        }
    }

}

final class WelcomeWindow:NSWindowController {
    enum Step:Int { case welcome, account, browserImport }
    var finish:((String,String?)->Void)?
    var importLinks:(([ImportedLink],String)throws->Int)?
    private(set) var step:Step
    let soundtrack = WelcomeSoundtrack()
    private let standalone:Bool
    private var language:String
    private let surface = WelcomeSurface(), content = WelcomeContent(), viewport = NSScrollView()
    init(language:String,start:Step = .welcome,standalone:Bool = false) {
        self.language = language; self.step = start; self.standalone = standalone
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width:1024,height:900)
        let frame = NSRect(x:0,y:0,width:min(840,visible.width-32),height:min(740,visible.height-48))
        let window = NSPanel(contentRect:frame,styleMask:[.titled,.fullSizeContentView],backing:.buffered,defer:false)
        super.init(window:window); window.title = "Arc Reborn"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false; window.contentView = surface
        viewport.frame = surface.bounds; viewport.autoresizingMask = [.width,.height]; viewport.borderType = .noBorder
        viewport.drawsBackground = false; viewport.scrollerStyle = .overlay; viewport.autohidesScrollers = true
        viewport.automaticallyAdjustsContentInsets = false; viewport.hasVerticalScroller = true; viewport.hasHorizontalScroller = true
        surface.addSubview(viewport); viewport.documentView = content; build()
    }
    required init?(coder:NSCoder) { fatalError() }
    func select(_ step:Step) { if self.step == .welcome && step != .welcome { soundtrack.stop() }; self.step = step; build(); if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { let animation = CABasicAnimation(keyPath:"opacity"); animation.fromValue = 0; animation.toValue = 1; animation.duration = 0.2; content.wantsLayer = true; content.layer?.add(animation,forKey:"page") } }
    private func tr(_ fr:String,_ en:String)->String { language == "en" ? en : fr }
    override func close() { soundtrack.stop(); super.close() }
    @discardableResult private func navigation(_ title:String,at previous:Step,action:@escaping()->Void) -> ArrivalButton {
        let rule = NSBox(frame:NSRect(x:54,y:642,width:732,height:1)); rule.boxType = .separator; content.addSubview(rule)
        if !standalone {
            let back = ChapterButton(tr("Retour","Back"),style:.soft) { [weak self] in self?.select(previous) }
            back.frame = NSRect(x:54,y:667,width:88,height:42); content.addSubview(back)
        }
        let next = ArrivalButton(action:action); next.title = title; next.keyEquivalent = step == .account ? "" : "\r"
        next.frame = NSRect(x:544,y:664,width:242,height:48); content.addSubview(next); return next
    }
    private func build() {
        window?.makeFirstResponder(nil); content.subviews.forEach { $0.removeFromSuperview() }
        content.setFrameSize(step == .welcome ? surface.bounds.size : NSSize(width:840,height:740))
        content.scroll(.zero)
        if step != .welcome {
            content.addSubview(WelcomeChapterArt(frame:content.bounds,account:step == .account))
            let topic = step == .account ? tr("VOTRE COMPTE","YOUR ACCOUNT") : tr("VOS DONNÉES","YOUR DATA")
            let index = step == .account ? "02 / 03" : "03 / 03"
            let tag = welcomeText(standalone ? topic : index+"   ·   "+topic,x:54,y:31,width:420,size:11,weight:.medium,color:.secondaryLabelColor,in:content)
            tag.font = .monospacedSystemFont(ofSize:10.5,weight:.medium)
            welcomeText("Arc Reborn.",x:653,y:27,width:133,height:26,size:15,weight:.semibold,color:.secondaryLabelColor,in:content).alignment = .right
        }
        switch step {
        case .welcome:
            let intro = WelcomeIntro(frame:content.bounds,language:language,soundtrack:soundtrack,chooseLanguage:{ [weak self] in self?.language = $0 },proceed:{ [weak self] in self?.select(.account) })
            intro.autoresizingMask = [.width,.height]; content.addSubview(intro)
        case .account:
            welcomeText(tr("Votre espace,\npartout.","Your space,\nanywhere."),x:52,y:95,width:350,height:145,size:49,weight:.semibold,in:content)
            welcomeText(tr("Retrouvez vos espaces, vos onglets et vos réglages sur vos appareils.","Keep your spaces, tabs and settings with you across devices."),x:55,y:245,width:318,height:79,size:17,color:.secondaryLabelColor,in:content)
            welcomeText(tr("À vous de choisir.","It’s your choice."),x:54,y:507,width:318,height:31,size:20,weight:.semibold,in:content)
            welcomeText(tr("Votre navigateur fonctionne aussi sans compte. Vous pourrez activer la synchronisation chiffrée plus tard.","You can browse without an account and turn on encrypted sync later."),x:54,y:545,width:319,height:65,size:14,color:.secondaryLabelColor,in:content)
            content.addSubview(ChapterPlate(NSRect(x:405,y:86,width:381,height:529)))
            let form = ArcAccountForm(frame:NSRect(x:430,y:110,width:331,height:479),chapterLanguage:language); content.addSubview(form)
            let nextTitle = standalone ? tr("Terminé","Done") : (ArcAccount.shared.user == nil ? tr("Continuer sans compte","Continue without an account") : tr("Continuer","Continue"))
            let next = navigation(nextTitle,at:.welcome) { [weak self] in guard let self else { return }; if self.standalone { self.finish?(self.language,nil) } else { self.select(.browserImport) } }
            form.completed = { [weak self,weak next] in guard let self else { return }; next?.title = self.standalone ? self.tr("Terminé","Done") : self.tr("Continuer","Continue") }
        case .browserImport:
            welcomeText(tr("Emportez l’essentiel.","Bring your favorites."),x:52,y:90,width:550,height:70,size:49,weight:.semibold,in:content)
            welcomeText(tr("Repartez avec vos favoris et vos onglets. Vos données d’origine restent intactes.","Bring your bookmarks and tabs along. Your original data stays untouched."),x:55,y:161,width:494,height:54,size:16,color:.secondaryLabelColor,in:content)
            let imports = BrowserImportView(frame:NSRect(x:54,y:235,width:732,height:385),language:language); content.addSubview(imports)
            imports.apply = { [weak self] links,source in guard let action = self?.importLinks else { return 0 }; return try action(links,source) }
            imports.openSettings = { [weak self] address in guard let self else { return }; self.finish?(self.language,address) }
            navigation(standalone ? tr("Terminé","Done") : tr("Ouvrir Arc Reborn","Open Arc Reborn"),at:.account) { [weak self] in guard let self else { return }; self.finish?(self.language,nil) }
        }
    }
}
