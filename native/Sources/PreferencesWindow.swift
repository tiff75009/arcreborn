import AppKit
import QuartzCore

struct PreferenceProfile {
    let id: String
    let name: String
    let spaces: Int
}

struct ProfileSettingsLink {
    let id: String, fr: String, en: String, symbol: String, address: String
    let color: NSColor
    static let all: [Self] = [
        .init(id:"privacy",fr:"Confidentialité et sécurité",en:"Privacy and security",symbol:"lock.fill",address:"arc://settings/privacy",color:.systemBlue),
        .init(id:"passwords",fr:"Mots de passe",en:"Passwords",symbol:"key.fill",address:"arc://password-manager/passwords",color:.systemGreen),
        .init(id:"payments",fr:"Cartes et moyens de paiement",en:"Cards and payment methods",symbol:"creditcard.fill",address:"arc://settings/payments",color:.systemYellow),
        .init(id:"notifications",fr:"Notifications",en:"Notifications",symbol:"bell.fill",address:"arc://settings/content/notifications",color:.systemOrange),
        .init(id:"clearData",fr:"Effacer les données de navigation",en:"Clear browsing data",symbol:"trash.fill",address:"arc://settings/privacy",color:.systemRed)
    ]
}

private final class PreferencesCanvas: NSView {
    override var isFlipped: Bool { true }
    var resized: (() -> Void)?
    override func layout() { super.layout(); resized?() }
}

private final class PreferencesCard: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:12,yRadius:12)
        NSColor.controlBackgroundColor.withAlphaComponent(0.58).setFill(); shape.fill()
        NSColor.separatorColor.withAlphaComponent(0.13).setStroke(); shape.lineWidth = 1; shape.stroke()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// Entire row is a keyboard-accessible button, with a restrained hover highlight.
private final class PreferenceRow: ActionButton {
    override var isFlipped: Bool { true }
    let label: String, detail: String, glyph: String, tint: NSColor
    let trailing: String
    var selected = false { didSet { needsDisplay = true } }
    private let hover = CALayer()
    private var area: NSTrackingArea?
    init(_ title:String,detail:String = "",symbol:String,color:NSColor = .controlAccentColor,trailing:String = "chevron.right",action:@escaping ()->Void) {
        label = title; self.detail = detail; glyph = symbol; tint = color; self.trailing = trailing
        super.init(title,action:action)
        wantsLayer = true; hover.cornerRadius = 8; hover.opacity = 0; layer?.addSublayer(hover)
        setAccessibilityLabel(detail.isEmpty ? title : title+", "+detail)
    }
    required init?(coder:NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func layout() {
        super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true)
        hover.frame = bounds.insetBy(dx:5,dy:3); hover.backgroundColor = NSColor.labelColor.withAlphaComponent(0.045).cgColor; CATransaction.commit()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let area { removeTrackingArea(area) }
        area = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self)
        addTrackingArea(area!)
    }
    override func mouseEntered(with event:NSEvent) { setHover(true) }
    override func mouseExited(with event:NSEvent) { setHover(false) }
    private func setHover(_ visible:Bool) {
        guard isEnabled else { return }
        CATransaction.begin(); CATransaction.setAnimationDuration(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14)
        hover.opacity = visible ? 1 : 0; CATransaction.commit()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true; needsLayout = true }
    override func draw(_ rect:NSRect) {
        let ink:NSColor = isEnabled ? .labelColor : .tertiaryLabelColor
        if selected {
            NSColor.controlAccentColor.withAlphaComponent(0.13).setFill()
            NSBezierPath(roundedRect:bounds.insetBy(dx:5,dy:3),xRadius:8,yRadius:8).fill()
        }
        let box = NSRect(x:14,y:bounds.midY-15,width:30,height:30)
        tint.withAlphaComponent(isEnabled ? 0.13 : 0.06).setFill(); NSBezierPath(roundedRect:box,xRadius:8,yRadius:8).fill()
        SpaceIcon.draw("sf:"+glyph,in:box.insetBy(dx:7,dy:7),color:isEnabled ? tint : .tertiaryLabelColor,size:16)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let labelY = detail.isEmpty ? bounds.midY-8 : bounds.midY-18
        (label as NSString).draw(in:NSRect(x:56,y:labelY,width:max(30,bounds.width-94),height:20),withAttributes:[.font:NSFont.systemFont(ofSize:13,weight:.medium),.foregroundColor:ink,.paragraphStyle:paragraph])
        if !detail.isEmpty {
            (detail as NSString).draw(in:NSRect(x:56,y:bounds.midY+3,width:max(30,bounds.width-94),height:18),withAttributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.secondaryLabelColor,.paragraphStyle:paragraph])
        }
        if !trailing.isEmpty { SpaceIcon.draw("sf:"+trailing,in:NSRect(x:bounds.width-29,y:bounds.midY-6,width:12,height:12),color:isEnabled ? (selected ? .controlAccentColor : .secondaryLabelColor) : .quaternaryLabelColor,size:11) }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke(); let focus = NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:2),xRadius:10,yRadius:10); focus.lineWidth = 2; focus.stroke()
        }
    }
}

private final class PreferenceSwitch: NSSwitch {
    var changed: ((Bool) -> Void)?
    init(value:Bool,changed:@escaping (Bool)->Void) { super.init(frame:.zero); state = value ? .on : .off; self.changed = changed; target = self; action = #selector(toggle) }
    required init?(coder:NSCoder) { fatalError() }
    @objc private func toggle() { changed?(state == .on) }
}
private final class PreferencePicker: NSPopUpButton {
    var changed: ((Int)->Void)?
    init(_ titles:[String],selected:Int,changed:@escaping (Int)->Void) {
        super.init(frame:.zero,pullsDown:false); addItems(withTitles:titles); selectItem(at:selected)
        self.changed = changed; target = self; action = #selector(selectValue)
    }
    required init?(coder:NSCoder) { fatalError() }
    @objc private func selectValue() { changed?(indexOfSelectedItem) }
}

final class BrowserPreferencesWindow: NSWindowController, NSToolbarDelegate, NSToolbarItemValidation {
    var commandBindings: [String:SplitKeyBinding] = [:]
    var onCommandBindings: (([String:SplitKeyBinding])->Void)?
    var onLanguage: ((String)->Void)?
    var onAppearance: ((ThemeAppearance)->Void)?
    var onCredentials: ((Bool,Bool,Bool)->Bool)?
    var onNewProfile: (()->Void)?
    var onRenameProfile: ((String,String)->Bool)?
    var onOpenProfilePage: ((String,String)->Bool)?
    var onWelcome: (()->Void)?
    var onImport: ((String)->Void)?
    var onDefaultBrowser: (()->Void)?
    private(set) var language: String
    private var profiles: [PreferenceProfile]
    private(set) var selectedProfileID: String
    private var savePasswords: Bool, automaticSignIn: Bool, formSuggestions: Bool
    private var appearance: ThemeAppearance
    private let privateWindow: Bool
    private var section = 1
    private let canvas = PreferencesCanvas(), pageContent = PreferencesCanvas()
    private let scroll = NSScrollView()
    private let toolbar = NSToolbar(identifier:"BrowserPreferences")
    private var shortcuts: CommandShortcutsPreferencesView?
    private var bodyWidth:CGFloat = 0
    private let titles = [("Compte","Account"),("Général","General"),("Profils","Profiles"),("Max","Max"),("Liens","Links"),("Raccourcis","Shortcuts"),("Icône","Icon"),("Avancé","Advanced")]
    private let symbols = ["person.crop.circle","gearshape","person.2","sparkles","link","keyboard","app.dashed","slider.horizontal.3"]
    private var available:Set<Int> { privateWindow ? [1,2,5,7] : [0,1,2,5,7] }

    init(language:String,profiles:[PreferenceProfile],selectedProfileID:String,appearance:ThemeAppearance,save:Bool,signIn:Bool,suggestions:Bool,privateWindow:Bool = false) {
        self.language = language; self.profiles = profiles; self.selectedProfileID = selectedProfileID
        self.appearance = appearance; self.privateWindow = privateWindow
        savePasswords = save; automaticSignIn = signIn; formSuggestions = suggestions
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:980,height:660),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        super.init(window:window)
        window.isReleasedWhenClosed = false; window.title = tr("Préférences","Preferences")
        window.titlebarAppearsTransparent = true; window.toolbarStyle = .preference
        window.contentMinSize = NSSize(width:900,height:560); window.contentMaxSize = NSSize(width:1240,height:1000)
        window.backgroundColor = .windowBackgroundColor; window.contentView = canvas
        window.appearance = appearance == .automatic ? nil : NSAppearance(named:appearance == .dark ? .darkAqua : .aqua)
        toolbar.delegate = self; toolbar.displayMode = .iconAndLabel; toolbar.allowsUserCustomization = false; toolbar.autosavesConfiguration = false
        window.toolbar = toolbar; toolbar.selectedItemIdentifier = identifier(section)
        scroll.drawsBackground = false; scroll.borderType = .noBorder; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = pageContent; canvas.addSubview(scroll)
        canvas.resized = { [weak self] in self?.layoutPage() }
        window.center(); layoutPage()
    }
    required init?(coder:NSCoder) { fatalError() }
    private func tr(_ fr:String,_ en:String)->String { language == "en" ? en : fr }
    private func identifier(_ index:Int)->NSToolbarItem.Identifier { .init("preferences.\(index)") }
    func toolbarAllowedItemIdentifiers(_ toolbar:NSToolbar)->[NSToolbarItem.Identifier] { titles.indices.map(identifier) }
    func toolbarDefaultItemIdentifiers(_ toolbar:NSToolbar)->[NSToolbarItem.Identifier] { toolbarAllowedItemIdentifiers(toolbar) }
    func toolbarSelectableItemIdentifiers(_ toolbar:NSToolbar)->[NSToolbarItem.Identifier] { titles.indices.filter(available.contains).map(identifier) }
    func toolbar(_ toolbar:NSToolbar,itemForItemIdentifier id:NSToolbarItem.Identifier,willBeInsertedIntoToolbar flag:Bool)->NSToolbarItem? {
        guard let index = Int(id.rawValue.split(separator:".").last ?? ""), titles.indices.contains(index) else { return nil }
        let item = NSToolbarItem(itemIdentifier:id)
        item.label = tr(titles[index].0,titles[index].1); item.paletteLabel = item.label
        item.image = NSImage(systemSymbolName:symbols[index],accessibilityDescription:item.label)
        item.target = self; item.action = #selector(selectToolbar(_:)); item.tag = index; item.isEnabled = available.contains(index)
        item.toolTip = item.isEnabled ? item.label : tr("Bientôt disponible","Coming soon")
        return item
    }
    func validateToolbarItem(_ item:NSToolbarItem)->Bool { available.contains(item.tag) }
    @objc private func selectToolbar(_ item:NSToolbarItem) { select(item.tag) }
    func showAccount() { select(0) }
    func showShortcuts() { select(5) }
    func showProfiles(_ id:String? = nil) { if let id, profiles.contains(where: { $0.id == id }) { selectedProfileID = id }; select(2) }
    private func select(_ index:Int) {
        guard available.contains(index) else { return }
        window?.makeFirstResponder(nil)
        section = index; toolbar.selectedItemIdentifier = identifier(index); shortcuts = nil
        scroll.contentView.scroll(to:.zero); rebuild()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = 0.72; fade.toValue = 1; fade.duration = 0.14
            pageContent.wantsLayer = true; pageContent.layer?.add(fade,forKey:"section")
        }
    }
    private func layoutPage() {
        scroll.frame = canvas.bounds
        if abs(bodyWidth-scroll.contentSize.width) > 0.5 { bodyWidth = scroll.contentSize.width; rebuild() }
        if let shortcuts { shortcuts.frame = NSRect(x:32,y:106,width:bodyWidth-64,height:max(360,canvas.bounds.height-126)) }
        if section == 5 { pageContent.frame.size.height = max(540,canvas.bounds.height) }
    }
    @discardableResult private func text(_ value:String,_ frame:NSRect,size:CGFloat = 13,weight:NSFont.Weight = .regular,color:NSColor = .labelColor,in parent:NSView? = nil)->NSTextField {
        let label = NSTextField(wrappingLabelWithString:value); label.frame = frame; label.font = .systemFont(ofSize:size,weight:weight); label.textColor = color
        (parent ?? pageContent).addSubview(label); return label
    }
    private func heading(_ title:String,_ detail:String) {
        text(title,NSRect(x:34,y:25,width:bodyWidth-68,height:36),size:26,weight:.bold)
        text(detail,NSRect(x:34,y:67,width:bodyWidth-68,height:38),size:12,color:.secondaryLabelColor)
    }
    private func card(_ frame:NSRect)->NSView { let view = PreferencesCard(frame:frame); pageContent.addSubview(view); return view }
    private func line(_ parent:NSView,y:CGFloat) {
        let view = NSBox(frame:NSRect(x:18,y:y,width:parent.bounds.width-36,height:1)); view.boxType = .separator; parent.addSubview(view)
    }
    private func sectionLabel(_ title:String,x:CGFloat,y:CGFloat,width:CGFloat) { text(title,NSRect(x:x+2,y:y,width:width-4,height:20),size:12,weight:.semibold,color:.secondaryLabelColor) }
    @discardableResult private func link(_ title:String,detail:String = "",symbol:String,color:NSColor = .controlAccentColor,frame:NSRect,parent:NSView,action:@escaping ()->Void)->PreferenceRow {
        let row = PreferenceRow(title,detail:detail,symbol:symbol,color:color,action:action); row.frame = frame; parent.addSubview(row); return row
    }
    private func rebuild() {
        guard bodyWidth > 0 else { return }
        if section == 5, let shortcuts {
            shortcuts.frame = NSRect(x:32,y:106,width:bodyWidth-64,height:max(360,canvas.bounds.height-126)); return
        }
        pageContent.subviews.forEach { $0.removeFromSuperview() }
        pageContent.frame = NSRect(x:0,y:0,width:bodyWidth,height:max(590,canvas.bounds.height))
        switch section {
        case 0: drawAccount()
        case 2: drawProfiles()
        case 5:
            heading(tr("Raccourcis","Shortcuts"),tr("Chaque geste, à votre façon. Cliquez sur une combinaison pour la modifier.","Make every action yours. Click a key combination to change it."))
            let view = CommandShortcutsPreferencesView(language:language,bindings:commandBindings); shortcuts = view
            view.changed = { [weak self] values in self?.commandBindings = values; self?.onCommandBindings?(values) }
            view.frame = NSRect(x:32,y:106,width:bodyWidth-64,height:max(360,canvas.bounds.height-126)); pageContent.addSubview(view)
        case 7: drawCredentials()
        default: drawGeneral()
        }
    }
    private func drawAccount() {
        heading(tr("Votre compte Arc Reborn","Your Arc Reborn account"),tr("Facultatif. Vos profils locaux restent accessibles sans compte.","Optional. Your local profiles stay available without an account."))
        let info = card(NSRect(x:32,y:122,width:bodyWidth*0.47-32,height:350))
        text(tr("Votre univers, partout.","Your world, everywhere."),NSRect(x:24,y:26,width:info.bounds.width-48,height:60),size:24,weight:.bold,in:info)
        text(tr("Retrouvez vos espaces, vos onglets, vos épingles et vos réglages sur vos appareils, ou après une réinstallation.","Recover your spaces, tabs, pinned pages and settings across devices or after reinstalling."),NSRect(x:24,y:105,width:info.bounds.width-48,height:90),size:14,color:.secondaryLabelColor,in:info)
        text(tr("Chiffrement de bout en bout","End-to-end encryption"),NSRect(x:24,y:231,width:info.bounds.width-48,height:25),weight:.semibold,in:info)
        text(tr("Vous choisissez quand l’activer. Votre code de récupération vous permet de retrouver vos données sur un nouvel appareil.","You choose when to enable it. Your recovery code unlocks your data on a new device."),NSRect(x:24,y:271,width:info.bounds.width-48,height:62),size:12,color:.secondaryLabelColor,in:info)
        let form = ArcAccountForm(frame:NSRect(x:bodyWidth*0.51,y:130,width:bodyWidth*0.49-40,height:470)); pageContent.addSubview(form)
        pageContent.frame.size.height = max(canvas.bounds.height,625)
    }
    private func drawGeneral() {
        heading(tr("Un navigateur qui vous ressemble.","A browser that feels like you."),tr("Les essentiels, simplement. Vos changements sont enregistrés automatiquement.","Just the essentials. Your changes are saved automatically."))
        let width = bodyWidth-64
        sectionLabel(tr("Apparence","Appearance"),x:32,y:114,width:width)
        let looks = card(NSRect(x:32,y:140,width:width,height:116))
        let modes:[ThemeAppearance] = [.automatic,.light,.dark]
        for (index,mode) in modes.enumerated() {
            let w = (width-32)/3
            let title = [tr("Système","System"),tr("Clair","Light"),tr("Sombre","Dark")][index]
            let detail = [tr("Suit votre Mac","Follows your Mac"),tr("Une interface lumineuse","A bright interface"),tr("Plus doux dans l’obscurité","Easy on the eyes")][index]
            let row = PreferenceRow(title,detail:detail,symbol:["circle.lefthalf.filled","sun.max","moon.stars"][index],trailing:appearance == mode ? "checkmark.circle.fill" : "") { [weak self] in
                guard let self else { return }; self.appearance = mode; self.onAppearance?(mode)
                self.window?.appearance = mode == .automatic ? nil : NSAppearance(named:mode == .dark ? .darkAqua : .aqua); self.rebuild()
            }
            row.frame = NSRect(x:12+CGFloat(index)*w,y:20,width:w-4,height:76); row.selected = appearance == mode; looks.addSubview(row)
        }
        sectionLabel(tr("Langue et navigation","Language and browsing"),x:32,y:278,width:width)
        let general = card(NSRect(x:32,y:304,width:width,height:130))
        text(tr("Langue du navigateur","Browser language"),NSRect(x:20,y:17,width:width-250,height:22),weight:.medium,in:general)
        text(tr("Interface et langues demandées aux sites.","Interface and languages requested from sites."),NSRect(x:20,y:41,width:width-250,height:19),size:11,color:.secondaryLabelColor,in:general)
        let picker = PreferencePicker(["Français","English"],selected:language == "en" ? 1 : 0) { [weak self] index in
            guard let self else { return }; self.language = index == 1 ? "en" : "fr"; self.onLanguage?(self.language)
            self.window?.title = self.tr("Préférences","Preferences")
            for item in self.toolbar.items { item.label = self.tr(self.titles[item.tag].0,self.titles[item.tag].1); item.toolTip = self.available.contains(item.tag) ? item.label : self.tr("Bientôt disponible","Coming soon") }
            self.rebuild()
        }
        picker.frame = NSRect(x:width-205,y:22,width:183,height:28); picker.setAccessibilityLabel(tr("Langue du navigateur","Browser language")); general.addSubview(picker)
        line(general,y:72)
        link(tr("Utiliser Arc Reborn par défaut…","Make Arc Reborn your default…"),symbol:"globe",frame:NSRect(x:1,y:76,width:width-2,height:50),parent:general) { [weak self] in self?.onDefaultBrowser?() }
        let quick = card(NSRect(x:32,y:455,width:width,height:110))
        link(tr("Profils et données personnelles","Profiles and personal data"),symbol:"person.crop.circle",frame:NSRect(x:1,y:3,width:width-2,height:51),parent:quick) { [weak self] in self?.select(2) }
        line(quick,y:55)
        link(tr("Personnaliser les raccourcis","Customize keyboard shortcuts"),symbol:"keyboard",frame:NSRect(x:1,y:57,width:width-2,height:50),parent:quick) { [weak self] in self?.select(5) }
        text(tr("Rechargez vos pages après un changement de langue. Certains menus changent au prochain lancement.","Reload pages after changing the language. Some menus update on the next launch."),NSRect(x:36,y:582,width:width-8,height:32),size:11,color:.secondaryLabelColor)
        let setup = card(NSRect(x:32,y:630,width:width,height:110))
        link(tr("Importer depuis un autre navigateur…","Import from another browser…"),symbol:"square.and.arrow.down",frame:NSRect(x:1,y:3,width:width-2,height:51),parent:setup) { [weak self] in guard let self else { return }; self.onImport?(self.selectedProfileID) }.isEnabled = !privateWindow
        line(setup,y:55)
        link(tr("Revoir l’accueil d’Arc Reborn","Replay the Arc Reborn welcome"),symbol:"sparkles",frame:NSRect(x:1,y:57,width:width-2,height:50),parent:setup) { [weak self] in self?.onWelcome?() }.isEnabled = !privateWindow
        sectionLabel(tr("Mises à jour", "Updates"),x:32,y:768,width:width)
        let updates = card(NSRect(x:32,y:794,width:width,height:272))
        link(tr("Rechercher une mise à jour…","Check for Updates…"),detail:"Arc Reborn \(BrowserUpdates.version) (\(BrowserUpdates.build))",symbol:"arrow.triangle.2.circlepath",frame:NSRect(x:1,y:3,width:width-2,height:64),parent:updates) { BrowserUpdates.shared.check() }.isEnabled = BrowserUpdates.shared.isAvailable
        line(updates,y:69)
        let downloadToggle = PreferenceSwitch(value:BrowserUpdates.shared.automaticallyDownloads) { value in
            BrowserUpdates.shared.automaticallyDownloads = value
        }
        downloadToggle.isEnabled = BrowserUpdates.shared.allowsAutomaticDownloads
        let checkToggle = PreferenceSwitch(value:BrowserUpdates.shared.automaticallyChecks) { value in
            BrowserUpdates.shared.automaticallyChecks = value
            downloadToggle.isEnabled = BrowserUpdates.shared.allowsAutomaticDownloads
            downloadToggle.state = BrowserUpdates.shared.automaticallyDownloads ? .on : .off
        }
        checkToggle.isEnabled = BrowserUpdates.shared.isAvailable
        let updateRows = [
            (tr("Rechercher automatiquement","Automatically check for updates"),tr("Toutes les 6 heures lorsque le navigateur est ouvert.","Every 6 hours while the browser is open."),checkToggle),
            (tr("Installer automatiquement","Automatically install updates"),tr("Téléchargement en arrière-plan, installation à la fermeture.","Download in the background and install when you quit."),downloadToggle)
        ]
        for (index,row) in updateRows.enumerated() {
            let y = CGFloat(82+index*64)
            text(row.0,NSRect(x:20,y:y,width:width-110,height:22),weight:.medium,in:updates)
            text(row.1,NSRect(x:20,y:y+23,width:width-110,height:19),size:11,color:.secondaryLabelColor,in:updates)
            row.2.frame = NSRect(x:width-67,y:y+7,width:42,height:26); row.2.setAccessibilityLabel(row.0); row.2.setAccessibilityHelp(row.1); updates.addSubview(row.2)
        }
        line(updates,y:212)
        link(tr("Voir les nouveautés de cette version","What’s new in this release"),symbol:"sparkles",frame:NSRect(x:1,y:215,width:width-2,height:54),parent:updates) { BrowserUpdates.shared.showNews() }
        if !BrowserUpdates.shared.isAvailable { text(tr("Version de développement : mises à jour officielles désactivées.","Development build: official updates disabled."),NSRect(x:36,y:1078,width:width-8,height:28),size:11,color:.secondaryLabelColor) }
        pageContent.frame.size.height = max(canvas.bounds.height,1122)
    }
    private func drawProfiles() {
        heading(tr("Vos profils, vos espaces.","Your profiles, your spaces."),tr("Séparez vos connexions, vos cookies et vos extensions. Un même profil peut être utilisé dans plusieurs espaces.","Keep sign-ins, cookies and extensions separate. One profile can be used across several spaces."))
        let left:CGFloat = 222, gap:CGFloat = 24, rightX = 32+left+gap, width = bodyWidth-rightX-32
        let selected = profiles.first(where: { $0.id == selectedProfileID }) ?? profiles.first
        guard let selected else { return }; selectedProfileID = selected.id
        sectionLabel(tr("Vos profils","Your profiles"),x:32,y:114,width:left)
        let list = card(NSRect(x:32,y:140,width:left,height:480))
        let profileScroll = NSScrollView(frame:NSRect(x:4,y:8,width:left-8,height:414)); profileScroll.drawsBackground = false; profileScroll.hasVerticalScroller = true; profileScroll.autohidesScrollers = true
        let profileDocument = PreferencesCanvas(frame:NSRect(x:0,y:0,width:left-14,height:max(414,CGFloat(profiles.count)*64)))
        for (index,profile) in profiles.enumerated() {
            let count = profile.spaces == 1 ? tr("1 espace","1 space") : "\(profile.spaces) "+tr("espaces","spaces")
            let row = PreferenceRow(profile.name,detail:count,symbol:"person.fill",trailing:"") { [weak self] in self?.selectedProfileID = profile.id; self?.rebuild() }
            row.frame = NSRect(x:0,y:CGFloat(index)*64,width:left-14,height:62); row.selected = profile.id == selectedProfileID; row.identifier = .init("profile."+profile.id)
            profileDocument.addSubview(row)
        }
        profileScroll.documentView = profileDocument; list.addSubview(profileScroll); line(list,y:430)
        let add = ActionButton("",symbol:"plus") { [weak self] in self?.close(); self?.onNewProfile?() }
        add.frame = NSRect(x:10,y:439,width:34,height:30); add.isEnabled = !privateWindow; add.toolTip = tr("Créer un profil","Create a profile"); add.setAccessibilityLabel(add.toolTip); list.addSubview(add)
        let rename = ActionButton(tr("Renommer…","Rename…"),symbol:"pencil") { [weak self] in self?.renameProfile() }
        rename.frame = NSRect(x:54,y:439,width:left-68,height:30); rename.isEnabled = !privateWindow; list.addSubview(rename)
        sectionLabel(tr("Données et confidentialité","Data and privacy"),x:rightX,y:114,width:width)
        let links = card(NSRect(x:rightX,y:140,width:width,height:276))
        for (index,item) in ProfileSettingsLink.all.enumerated() {
            let row = link(tr(item.fr,item.en),symbol:item.symbol,color:item.color,frame:NSRect(x:1,y:3+CGFloat(index)*54,width:width-2,height:54),parent:links) { [weak self] in self?.openProfilePage(item.address) }
            row.identifier = .init("profile-link."+item.id); row.isEnabled = !privateWindow
            row.toolTip = privateWindow ? tr("Disponible dans une fenêtre normale","Available in a regular window") : tr("Ouvrir dans un nouvel onglet du profil ","Open in a new tab for ")+selected.name
            if index < ProfileSettingsLink.all.count-1 { line(links,y:57+CGFloat(index)*54) }
        }
        text(privateWindow ? tr("Les données de cette fenêtre privée restent temporaires.","This private window uses temporary data.") : tr("Ces pages s’ouvrent dans le profil « \(selected.name) ».","These pages open in the “\(selected.name)” profile."),NSRect(x:rightX+3,y:426,width:width-6,height:26),size:11,color:.secondaryLabelColor)
        sectionLabel(tr("Navigation du profil","Profile browsing"),x:rightX,y:466,width:width)
        let options = card(NSRect(x:rightX,y:492,width:width,height:128))
        let search = link(tr("Moteur de recherche","Search engine"),detail:tr("Google · Personnalisation à venir","Google · Customization coming soon"),symbol:"magnifyingglass",frame:NSRect(x:1,y:4,width:width-2,height:60),parent:options) {}
        search.isEnabled = false; line(options,y:64)
        let archive = link(tr("Archivage automatique","Automatic archiving"),detail:tr("Bientôt disponible","Coming soon"),symbol:"archivebox",frame:NSRect(x:1,y:66,width:width-2,height:58),parent:options) {}
        archive.isEnabled = false
        let imports = card(NSRect(x:rightX,y:638,width:width,height:64))
        link(tr("Importer dans ce profil…","Import into this profile…"),symbol:"square.and.arrow.down",frame:NSRect(x:1,y:3,width:width-2,height:58),parent:imports) { [weak self] in guard let self else { return }; self.onImport?(self.selectedProfileID) }.isEnabled = !privateWindow
        pageContent.frame.size.height = max(canvas.bounds.height,724)
    }
    private func renameProfile() {
        guard let profile = profiles.first(where: { $0.id == selectedProfileID }), let window, !privateWindow else { return }
        let alert = NSAlert(); alert.messageText = tr("Renommer le profil","Rename profile")
        let field = NSTextField(string:profile.name); field.frame = NSRect(x:0,y:0,width:280,height:26); alert.accessoryView = field
        alert.addButton(withTitle:tr("Enregistrer","Save")); alert.addButton(withTitle:tr("Annuler","Cancel"))
        alert.beginSheetModal(for:window) { [weak self] result in
            guard let self, result == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
            guard self.onRenameProfile?(profile.id,name) == true else { NSSound.beep(); return }
            if let i = self.profiles.firstIndex(where: { $0.id == profile.id }) { self.profiles[i] = .init(id:profile.id,name:name,spaces:profile.spaces) }; self.rebuild()
        }
        alert.window.makeFirstResponder(field)
    }
    private func openProfilePage(_ address:String) {
        guard !privateWindow else { return }
        if onOpenProfilePage?(selectedProfileID,address) == true { window?.orderOut(nil) }
    }
    private func drawCredentials() {
        heading(tr("Mots de passe et saisie","Passwords and autofill"),tr("Choisissez ce qu’Arc Reborn peut proposer. Ces réglages s’appliquent à tous vos profils.","Choose what Arc Reborn can suggest. These settings apply to all your profiles."))
        let width = bodyWidth-64
        sectionLabel(tr("Identifiants et formulaires","Credentials and forms"),x:32,y:114,width:width)
        let panel = card(NSRect(x:32,y:140,width:width,height:294))
        let rows = [(tr("Proposer d’enregistrer les mots de passe","Offer to save passwords"),tr("Active aussi la génération de nouveaux mots de passe.","Also enables generation of new passwords."),savePasswords),
                    (tr("Connexion automatique","Automatic sign-in"),tr("Utiliser vos identifiants enregistrés pour vous connecter.","Use saved credentials to sign in."),automaticSignIn),
                    (tr("Suggestions dans les formulaires","Form suggestions"),tr("Proposer vos adresses et vos saisies précédentes.","Suggest saved addresses and previous entries."),formSuggestions)]
        for (index,row) in rows.enumerated() {
            let y = CGFloat(index)*98
            text(row.0,NSRect(x:22,y:y+24,width:width-115,height:24),size:14,weight:.medium,in:panel)
            text(row.1,NSRect(x:22,y:y+52,width:width-115,height:32),size:12,color:.secondaryLabelColor,in:panel)
            let control = PreferenceSwitch(value:row.2) { [weak self] value in self?.setCredential(index,value) }
            control.frame = NSRect(x:width-67,y:y+33,width:42,height:26); control.setAccessibilityLabel(row.0); panel.addSubview(control)
            if index < 2 { line(panel,y:y+98) }
        }
        let note = card(NSRect(x:32,y:455,width:width,height:88))
        text(tr("Vos mots de passe restent conservés.","Your saved passwords are kept."),NSRect(x:22,y:17,width:width-44,height:24),weight:.medium,in:note)
        text(tr("Ces options ne désactivent pas le remplissage des identifiants existants ni les suggestions de vos extensions.","These options do not disable filling existing credentials or suggestions from your extensions."),NSRect(x:22,y:44,width:width-44,height:34),size:12,color:.secondaryLabelColor,in:note)
        pageContent.frame.size.height = max(canvas.bounds.height,568)
    }
    private func setCredential(_ key:Int,_ value:Bool) {
        let save = key == 0 ? value : savePasswords, signIn = key == 1 ? value : automaticSignIn, suggestions = key == 2 ? value : formSuggestions
        if onCredentials?(save,signIn,suggestions) == true { savePasswords = save; automaticSignIn = signIn; formSuggestions = suggestions }
        else if let window {
            let alert = NSAlert(); alert.messageText = tr("Réglage non appliqué","Setting not applied")
            alert.informativeText = tr("Votre réglage précédent est conservé.","Your previous setting has been kept."); alert.beginSheetModal(for:window)
        }
        rebuild()
    }
}
