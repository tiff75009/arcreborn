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

private final class PreferencesClipView: NSClipView {
    override var isFlipped: Bool { true }
}

private final class PreferencesCard: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:12,yRadius:12)
        ChapterInk.surface.setFill(); shape.fill()
        ChapterInk.line.setStroke(); shape.lineWidth = 1; shape.stroke()
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
    init(_ title:String,detail:String = "",symbol:String,color:NSColor = ChapterInk.accent,trailing:String = "chevron.right",action:@escaping ()->Void) {
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
            ChapterInk.selected.setFill()
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

private final class PreferencesTab:ChapterButton {
    let symbol:String
    var chosen:Bool { didSet { setAccessibilityValue(chosen ? 1 : 0); needsDisplay = true } }
    init(_ name:String,symbol:String,selected:Bool,action:@escaping()->Void) {
        self.symbol = symbol; chosen = selected; super.init(name,style:.link,action:action)
        setAccessibilityRole(.radioButton); setAccessibilityLabel(name); setAccessibilityValue(selected ? 1 : 0)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ rect:NSRect) {
        let p = NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:10,yRadius:10)
        if chosen || isHighlighted { ChapterInk.selected.setFill(); p.fill(); ChapterInk.line.setStroke(); p.stroke() }
        let ink:NSColor = !isEnabled ? .tertiaryLabelColor : chosen ? ChapterInk.accent : .secondaryLabelColor
        let attrs:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:12,weight:chosen ? .semibold : .medium),.foregroundColor:ink]
        let label = title as NSString, sz = label.size(withAttributes:attrs), x = floor((bounds.width-sz.width-21)/2)
        SpaceIcon.draw("sf:"+symbol,in:NSRect(x:x,y:bounds.midY-7.5,width:15,height:15),color:ink,size:14)
        label.draw(at:NSPoint(x:x+21,y:floor(bounds.midY-sz.height/2)),withAttributes:attrs)
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

final class BrowserPreferencesWindow: NSWindowController {
    var commandBindings: [String:SplitKeyBinding] = [:]
    var onCommandBindings: (([String:SplitKeyBinding])->Void)?
    var onLanguage: ((String)->Void)?
    var onInterfaceChange: ((BrowserInterface) -> Bool)?
    var onSidebarVisibilityChange: ((Bool) -> Void)?
    private var sidebarHidden: Bool
    private weak var visibilityControl: NSSegmentedControl?
    private weak var visibilityHint: NSTextField?
    var previewTheme: (() -> SpaceTheme)?
    private var interfaceMode: BrowserInterface
    var onAppearance: ((ThemeAppearance)->Void)?
    var onCredentials: ((Bool,Bool,Bool)->Bool)?
    var onNewProfile: (()->Void)?
    var onRenameProfile: ((String,String)->Bool)?
    var navigationProfile: ((String)->NativeProfile?)?
    var onNavigationEdit: ((String,ProfileNavigationEdit)->Bool)?
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
    private let nav = PreferencesCanvas()
    private var tabButtons:[ChapterButton] = []
    private let sheetWidth:CGFloat = 832
    private var shortcuts: CommandShortcutsPreferencesView?
    private var bodyWidth:CGFloat = 0
    private let titles = [("Compte","Account"),("Général","General"),("Profils","Profiles"),("Interface","Interface"),("Liens","Links"),("Raccourcis","Shortcuts"),("Icône","Icon"),("Avancé","Advanced")]
    private let symbols = ["person.crop.circle","gearshape","person.2","macwindow","link","keyboard","app.dashed","slider.horizontal.3"]
    private var available:Set<Int> { privateWindow ? [1,2,3,5,7] : [0,1,2,3,5,7] }

    init(language:String,profiles:[PreferenceProfile],selectedProfileID:String,interfaceMode:BrowserInterface = .compact,sidebarHidden:Bool = false,appearance:ThemeAppearance,save:Bool,signIn:Bool,suggestions:Bool,privateWindow:Bool = false) {
        self.language = language; self.profiles = profiles; self.selectedProfileID = selectedProfileID
        self.interfaceMode = interfaceMode
        self.sidebarHidden = sidebarHidden
        self.appearance = appearance; self.privateWindow = privateWindow
        savePasswords = save; automaticSignIn = signIn; formSuggestions = suggestions
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:908,height:638),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        super.init(window:window)
        window.isReleasedWhenClosed = false; window.title = tr("Préférences","Preferences")
        window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width:858,height:535); window.contentMaxSize = NSSize(width:1240,height:1000)
        window.backgroundColor = .windowBackgroundColor; window.contentView = canvas
        window.appearance = appearance == .automatic ? nil : NSAppearance(named:appearance == .dark ? .darkAqua : .aqua)
        let paper = WelcomePaper(frame:canvas.bounds); paper.autoresizingMask = [.width,.height]; canvas.addSubview(paper)
        scroll.contentView = PreferencesClipView(frame:.zero)
        scroll.drawsBackground = false; scroll.borderType = .noBorder; scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay; scroll.autohidesScrollers = true; scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = pageContent; canvas.addSubview(scroll); canvas.addSubview(nav)
        buildNavigation()
        canvas.resized = { [weak self] in self?.layoutPage() }
        window.center(); layoutPage()
    }
    required init?(coder:NSCoder) { fatalError() }
    private func tr(_ fr:String,_ en:String)->String { language == "en" ? en : fr }
    private func buildNavigation() {
        nav.subviews.forEach { $0.removeFromSuperview() }; tabButtons.removeAll()
        let widths:[CGFloat] = language == "en" ? [95,94,96,103,72,114,67,101] : [90,96,85,102,74,118,75,95]
        let total = widths.reduce(0,+)+CGFloat(widths.count-1)*3
        var x = (sheetWidth-total)/2
        for i in titles.indices {
            let name = tr(titles[i].0,titles[i].1)
            let tab = PreferencesTab(name,symbol:symbols[i],selected:i == section) { [weak self] in self?.select(i) }
            tab.isEnabled = available.contains(i); tab.toolTip = tab.isEnabled ? name : tr("Bientôt disponible","Coming soon")
            tab.frame = NSRect(x:x,y:8,width:widths[i],height:34); nav.addSubview(tab); tabButtons.append(tab); x += widths[i]+3
        }
        let rule = NSBox(frame:NSRect(x:26,y:50,width:sheetWidth-52,height:1)); rule.boxType = .separator; nav.addSubview(rule)
    }
    func showInterface() { select(3) }
    func refreshSidebarVisibility(_ hidden:Bool) {
        sidebarHidden = hidden
        visibilityControl?.selectedSegment = hidden ? 1 : 0
        visibilityHint?.stringValue = hidden
            ? tr("Survolez le bord gauche pour la révéler.","Hover over the left edge to reveal it.")
            : tr("Vos onglets restent visibles à côté de la page.","Your tabs stay visible beside the page.")
        for card in pageContent.subviews.compactMap({ $0 as? InterfaceChoice }) { card.sidebarHidden = hidden }
    }
    @objc private func changeSidebarVisibility(_ sender:NSSegmentedControl) {
        guard let onSidebarVisibilityChange else { return }
        onSidebarVisibilityChange(sender.selectedSegment == 1)
    }
    func refreshInterface(_ mode:BrowserInterface) {
        interfaceMode = mode
        for card in pageContent.subviews.compactMap({ $0 as? InterfaceChoice }) { card.selected = card.mode == mode }
    }
    func showAccount() { select(0) }
    func showShortcuts() { select(5) }
    func showProfiles(_ id:String? = nil) { if let id, profiles.contains(where: { $0.id == id }) { selectedProfileID = id }; select(2) }
    private func select(_ index:Int) {
        guard available.contains(index) else { return }
        window?.makeFirstResponder(nil)
        section = index; shortcuts = nil
        for (i,tab) in tabButtons.enumerated() { (tab as? PreferencesTab)?.chosen = i == index }
        rebuild()
        scroll.layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to:.zero); scroll.reflectScrolledClipView(scroll.contentView)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.section == index else { return }
            self.scroll.contentView.scroll(to:.zero); self.scroll.reflectScrolledClipView(self.scroll.contentView)
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = 0.72; fade.toValue = 1; fade.duration = 0.14
            pageContent.wantsLayer = true; pageContent.layer?.add(fade,forKey:"section")
        }
    }
    private func layoutPage() {
        let x = floor((canvas.bounds.width-sheetWidth)/2)
        nav.frame = NSRect(x:x,y:0,width:sheetWidth,height:52)
        scroll.frame = NSRect(x:x,y:52,width:sheetWidth,height:max(1,canvas.bounds.height-52))
        // Center a stable reading column; resizing must never detach a live field editor.
        if bodyWidth != sheetWidth { bodyWidth = sheetWidth; rebuild() }
        if let shortcuts { shortcuts.frame = NSRect(x:28,y:97,width:bodyWidth-56,height:max(330,scroll.bounds.height-110))
            pageContent.frame.size.height = max(442,scroll.bounds.height) }
    }
    @discardableResult private func text(_ value:String,_ frame:NSRect,size:CGFloat = 13,weight:NSFont.Weight = .regular,color:NSColor = .labelColor,in parent:NSView? = nil)->NSTextField {
        let label = NSTextField(wrappingLabelWithString:value); label.frame = frame; label.font = .systemFont(ofSize:size,weight:weight); label.textColor = color
        (parent ?? pageContent).addSubview(label); return label
    }
    private func heading(_ title:String,_ detail:String) {
        let folio = text("ARC REBORN   /   "+tr(titles[section].0,titles[section].1).uppercased(),NSRect(x:29,y:13,width:bodyWidth-58,height:14),size:9.5,weight:.semibold,color:ChapterInk.accent)
        folio.font = .monospacedSystemFont(ofSize:9.5,weight:.semibold)
        text(title,NSRect(x:27,y:30,width:bodyWidth-56,height:35),size:26,weight:.semibold)
        text(detail,NSRect(x:29,y:66,width:bodyWidth-58,height:28),size:12,color:.secondaryLabelColor)
    }
    private func card(_ frame:NSRect)->NSView { let view = PreferencesCard(frame:frame); pageContent.addSubview(view); return view }
    private func line(_ parent:NSView,y:CGFloat) {
        let view = NSBox(frame:NSRect(x:18,y:y,width:parent.bounds.width-36,height:1)); view.boxType = .separator; parent.addSubview(view)
    }
    private func sectionLabel(_ title:String,x:CGFloat,y:CGFloat,width:CGFloat) { text(title.uppercased(),NSRect(x:x+2,y:y,width:width-4,height:16),size:9.5,weight:.semibold,color:ChapterInk.accent).font = .monospacedSystemFont(ofSize:9.5,weight:.semibold) }
    @discardableResult private func link(_ title:String,detail:String = "",symbol:String,color:NSColor = ChapterInk.accent,frame:NSRect,parent:NSView,action:@escaping ()->Void)->PreferenceRow {
        let row = PreferenceRow(title,detail:detail,symbol:symbol,color:color,action:action); row.frame = frame; parent.addSubview(row); return row
    }
    private func rebuild() {
        guard bodyWidth > 0 else { return }
        if section == 5, let shortcuts {
            shortcuts.frame = NSRect(x:28,y:97,width:bodyWidth-56,height:max(330,scroll.bounds.height-110)); return
        }
        pageContent.subviews.forEach { $0.removeFromSuperview() }
        pageContent.frame = NSRect(x:0,y:0,width:bodyWidth,height:max(590,canvas.bounds.height))
        switch section {
        case 0: drawAccount()
        case 2: drawProfiles()
        case 3: drawInterface()
        case 5:
            heading(tr("Raccourcis","Shortcuts"),tr("Chaque geste, à votre façon. Cliquez sur une combinaison pour la modifier.","Make every action yours. Click a key combination to change it."))
            let view = CommandShortcutsPreferencesView(language:language,bindings:commandBindings); shortcuts = view
            view.changed = { [weak self] values in self?.commandBindings = values; self?.onCommandBindings?(values) }
            view.frame = NSRect(x:28,y:97,width:bodyWidth-56,height:max(330,scroll.bounds.height-110)); pageContent.addSubview(view)
        case 7: drawCredentials()
        default: drawGeneral()
        }
    }
    private func drawAccount() {
        let formX:CGFloat = 399
        let kicker = text(tr("ARC REBORN   /   COMPTE","ARC REBORN   /   ACCOUNT"),NSRect(x:30,y:30,width:340,height:18),size:10,weight:.medium,color:ChapterInk.accent)
        kicker.font = .monospacedSystemFont(ofSize:10,weight:.semibold)
        text(tr("Votre espace,\npartout.","Your space,\nanywhere."),NSRect(x:27,y:62,width:360,height:106),size:43,weight:.semibold)
        text(tr("Retrouvez vos onglets, vos épingles et vos réglages, même après une réinstallation.","Bring your tabs, pins and settings with you, even after reinstalling."),NSRect(x:30,y:175,width:313,height:69),size:15,color:.secondaryLabelColor)
        let art = PreferencesCanvas(frame:NSRect(x:12,y:239,width:365,height:128)); art.wantsLayer = true; art.layer?.masksToBounds = true
        let engraving = WelcomeEngraving(right:false); engraving.frame = NSRect(x:-100,y:-51,width:850,height:208); art.addSubview(engraving)
        art.addSubview(WelcomeRibbonMark(frame:NSRect(x:145,y:2,width:128,height:128))); pageContent.addSubview(art)
        sectionLabel(tr("Synchronisation chiffrée","Encrypted sync"),x:29,y:396,width:322)
        text(tr("Le compte est facultatif. Activez la synchronisation quand vous le souhaitez ; votre code de récupération vous permettra de récupérer vos données.","An account is optional. Turn on sync when you’re ready and keep your recovery code to restore your data."),NSRect(x:30,y:421,width:313,height:73),size:13,color:.secondaryLabelColor)
        let panel = card(NSRect(x:formX,y:19,width:bodyWidth-formX-26,height:476))
        let form = ArcAccountForm(frame:NSRect(x:22,y:18,width:panel.bounds.width-44,height:444),chapterLanguage:language); panel.addSubview(form)
        pageContent.frame.size.height = max(scroll.bounds.height,515)
    }
    private func drawGeneral() {
        heading(tr("Au quotidien.","Every day."),tr("Apparence, langue et mises à jour de votre navigateur.","Appearance, language and updates for your browser."))
        let x:CGFloat = 28, w:CGFloat = (bodyWidth-72)/2, r = x+w+16
        sectionLabel(tr("Apparence","Appearance"),x:x,y:97,width:w)
        let looks = card(NSRect(x:x,y:118,width:w,height:145))
        for (i,mode) in [ThemeAppearance.automatic,.light,.dark].enumerated() {
            let row = PreferenceRow([tr("Suivre le Mac","Match your Mac"),tr("Clair","Light"),tr("Sombre","Dark")][i],symbol:["circle.lefthalf.filled","sun.max","moon.stars"][i],trailing:appearance == mode ? "checkmark" : "") { [weak self] in
                guard let self else { return }; self.appearance = mode; self.onAppearance?(mode)
                self.window?.appearance = mode == .automatic ? nil : NSAppearance(named:mode == .dark ? .darkAqua : .aqua); self.rebuild()
            }
            row.frame = NSRect(x:4,y:4+CGFloat(i)*46,width:w-8,height:45); row.selected = appearance == mode; looks.addSubview(row)
        }
        sectionLabel(tr("Ce navigateur","This browser"),x:r,y:97,width:w)
        let quick = card(NSRect(x:r,y:118,width:w,height:145))
        link(tr("Profils et données","Profiles and data"),symbol:"person.crop.circle",frame:NSRect(x:2,y:3,width:w-4,height:45),parent:quick) { [weak self] in self?.select(2) }
        line(quick,y:49)
        link(tr("Raccourcis clavier","Keyboard shortcuts"),symbol:"keyboard",frame:NSRect(x:2,y:50,width:w-4,height:44),parent:quick) { [weak self] in self?.select(5) }
        line(quick,y:95)
        link(tr("Utiliser par défaut…","Make default…"),symbol:"globe",frame:NSRect(x:2,y:96,width:w-4,height:45),parent:quick) { [weak self] in self?.onDefaultBrowser?() }
        sectionLabel(tr("Langue et accueil","Language and welcome"),x:x,y:284,width:w)
        let setup = card(NSRect(x:x,y:305,width:w,height:163))
        text(tr("Langue","Language"),NSRect(x:18,y:15,width:90,height:23),weight:.medium,in:setup)
        let picker = PreferencePicker(["Français","English"],selected:language == "en" ? 1 : 0) { [weak self] i in
            guard let self else { return }; self.language = i == 1 ? "en" : "fr"; self.onLanguage?(self.language)
            self.window?.title = self.tr("Préférences","Preferences"); self.buildNavigation(); self.rebuild()
        }
        picker.frame = NSRect(x:w-162,y:9,width:145,height:28); picker.setAccessibilityLabel(tr("Langue","Language")); setup.addSubview(picker); line(setup,y:47)
        link(tr("Importer des données…","Import data…"),symbol:"square.and.arrow.down",frame:NSRect(x:2,y:49,width:w-4,height:51),parent:setup) { [weak self] in guard let self else { return }; self.onImport?(self.selectedProfileID) }.isEnabled = !privateWindow
        line(setup,y:102)
        link(tr("Revoir l’accueil","Replay the welcome"),symbol:"sparkles",frame:NSRect(x:2,y:105,width:w-4,height:52),parent:setup) { [weak self] in self?.onWelcome?() }.isEnabled = !privateWindow
        sectionLabel(tr("Mises à jour","Updates"),x:r,y:284,width:w)
        let updates = card(NSRect(x:r,y:305,width:w,height:211))
        link(tr("Rechercher une mise à jour","Check for updates"),detail:"Arc Reborn "+BrowserUpdates.version,symbol:"arrow.triangle.2.circlepath",frame:NSRect(x:2,y:2,width:w-4,height:52),parent:updates) { BrowserUpdates.shared.check() }.isEnabled = BrowserUpdates.shared.isAvailable
        let download = PreferenceSwitch(value:BrowserUpdates.shared.automaticallyDownloads) { BrowserUpdates.shared.automaticallyDownloads = $0 }
        download.isEnabled = BrowserUpdates.shared.allowsAutomaticDownloads
        let check = PreferenceSwitch(value:BrowserUpdates.shared.automaticallyChecks) { value in
            BrowserUpdates.shared.automaticallyChecks = value; download.isEnabled = BrowserUpdates.shared.allowsAutomaticDownloads; download.state = BrowserUpdates.shared.automaticallyDownloads ? .on : .off
        }
        check.isEnabled = BrowserUpdates.shared.isAvailable
        for (i,row) in [(tr("Recherche automatique","Automatic checks"),tr("Toutes les six heures.","Every six hours."),check),(tr("Installation automatique","Automatic installation"),tr("À la fermeture du navigateur.","When you quit the browser."),download)].enumerated() {
            let y = CGFloat(55+i*54); line(updates,y:y); text(row.0,NSRect(x:17,y:y+7,width:w-85,height:20),weight:.medium,in:updates)
            text(row.1,NSRect(x:17,y:y+27,width:w-85,height:18),size:11,color:.secondaryLabelColor,in:updates)
            row.2.frame = NSRect(x:w-56,y:y+15,width:40,height:24); row.2.setAccessibilityLabel(row.0); updates.addSubview(row.2)
        }
        line(updates,y:164)
        link(tr("Nouveautés de la version","Release notes"),symbol:"sparkles",frame:NSRect(x:2,y:165,width:w-4,height:43),parent:updates) { BrowserUpdates.shared.showNews() }
        text(tr("Après un changement de langue, rechargez vos pages. Certains menus changent au prochain lancement.","Reload pages after changing the language. Some menus update on the next launch."),NSRect(x:x+3,y:479,width:w-6,height:52),size:11,color:.secondaryLabelColor)
        if !BrowserUpdates.shared.isAvailable { text(tr("Mises à jour désactivées en développement.","Updates are disabled in development builds."),NSRect(x:r+3,y:522,width:w-6,height:20),size:10.5,color:.secondaryLabelColor) }
        pageContent.frame.size.height = max(scroll.bounds.height,550)
    }
    private func drawInterface() {
        heading(tr("Disposition du navigateur","Browser layout"),
                tr("Choisissez où retrouver l’adresse et les commandes de navigation.","Choose where the address and navigation controls appear."))
        let inset: CGFloat = 28, gap: CGFloat = 14
        let width = (bodyWidth-2*inset-gap)/2
        let theme = previewTheme?() ?? .solid("#5747D8")
        for (index,mode) in BrowserInterface.allCases.enumerated() {
            let card = InterfaceChoice(mode:mode,theme:theme,english:language == "en") { [weak self] in
                guard let self, mode != self.interfaceMode, self.onInterfaceChange?(mode) == true else { return }
                self.refreshInterface(mode)
            }
            card.frame = NSRect(x:inset+CGFloat(index)*(width+gap),y:111,width:width,height:239)
            card.identifier = .init("interface."+mode.rawValue)
            card.selected = mode == interfaceMode
            pageContent.addSubview(card)
        }
        let panel = card(NSRect(x:inset+2,y:366,width:bodyWidth-2*inset-4,height:72))
        text(tr("Barre latérale","Sidebar"),NSRect(x:17,y:12,width:300,height:22),
             size:14,weight:.semibold,in:panel)
        visibilityHint = text("",NSRect(x:17,y:39,width:panel.bounds.width-254,height:22),
                              size:12,color:.secondaryLabelColor,in:panel)
        let control = NSSegmentedControl(labels:[tr("Affichée","Shown"),tr("Masquée","Hidden")],
                                         trackingMode:.selectOne,target:self,action:#selector(changeSidebarVisibility(_:)))
        control.segmentStyle = .rounded
        control.setWidth(88,forSegment:0); control.setWidth(88,forSegment:1)
        control.frame = NSRect(x:panel.bounds.width-209,y:20,width:192,height:30)
        control.identifier = .init("interface.sidebarVisibility")
        control.setAccessibilityLabel(tr("Visibilité de la barre latérale","Sidebar visibility"))
        control.isEnabled = onSidebarVisibilityChange != nil
        panel.addSubview(control); visibilityControl = control; refreshSidebarVisibility(sidebarHidden)
        text(tr("Les couleurs, le dégradé et le grain suivent le thème de l’espace actif.",
                "Colors, gradient and grain follow the active Space’s theme."),
             NSRect(x:inset+4,y:452,width:bodyWidth-2*inset-8,height:35),size:12,color:.secondaryLabelColor)
        pageContent.frame.size.height = max(scroll.bounds.height,495)
    }

    private func drawProfiles() {
        heading(tr("Vos profils, vos espaces.","Your profiles, your spaces."),tr("Séparez vos connexions, vos cookies et vos extensions. Un même profil peut être utilisé dans plusieurs espaces.","Keep sign-ins, cookies and extensions separate. One profile can be used across several spaces."))
        let left:CGFloat = 200, gap:CGFloat = 16, rightX = 32+left+gap, width = bodyWidth-rightX-32
        let selected = profiles.first(where: { $0.id == selectedProfileID }) ?? profiles.first
        guard let selected else { return }; selectedProfileID = selected.id
        sectionLabel(tr("Vos profils","Your profiles"),x:32,y:98,width:left)
        let list = card(NSRect(x:32,y:120,width:left,height:374))
        let profileScroll = NSScrollView(frame:NSRect(x:4,y:8,width:left-8,height:312)); profileScroll.drawsBackground = false; profileScroll.hasVerticalScroller = true; profileScroll.autohidesScrollers = true
        let profileDocument = PreferencesCanvas(frame:NSRect(x:0,y:0,width:left-14,height:max(312,CGFloat(profiles.count)*46)))
        for (index,profile) in profiles.enumerated() {
            let count = profile.spaces == 1 ? tr("1 espace","1 space") : "\(profile.spaces) "+tr("espaces","spaces")
            let row = PreferenceRow(profile.name,detail:count,symbol:"person.fill",trailing:"") { [weak self] in self?.showProfiles(profile.id) }
            row.frame = NSRect(x:0,y:CGFloat(index)*46,width:left-14,height:45); row.selected = profile.id == selectedProfileID; row.identifier = .init("profile."+profile.id)
            profileDocument.addSubview(row)
        }
        profileScroll.documentView = profileDocument; list.addSubview(profileScroll); line(list,y:322)
        let add = ActionButton("",symbol:"plus") { [weak self] in self?.close(); self?.onNewProfile?() }
        add.frame = NSRect(x:10,y:330,width:34,height:30); add.isEnabled = !privateWindow; add.toolTip = tr("Créer un profil","Create a profile"); add.setAccessibilityLabel(add.toolTip); list.addSubview(add)
        let rename = ActionButton(tr("Renommer…","Rename…"),symbol:"pencil") { [weak self] in self?.renameProfile() }
        rename.frame = NSRect(x:54,y:330,width:left-68,height:30); rename.isEnabled = !privateWindow; list.addSubview(rename)
        sectionLabel(tr("Navigation du profil","Profile browsing"),x:rightX,y:98,width:width)
        let navCard = card(NSRect(x:rightX,y:120,width:width,height:ProfileNavigationView.panelHeight))
        if let profile = navigationProfile?(selected.id) {
            let controls = ProfileNavigationView(frame:navCard.bounds,profile:profile,english:language == "en",readOnly:privateWindow) { [weak self] edit in
                self?.onNavigationEdit?(profile.id,edit) == true
            }
            navCard.addSubview(controls)
        }
        sectionLabel(tr("Données et confidentialité","Data and privacy"),x:rightX,y:navCard.frame.maxY+19,width:width)
        let links = card(NSRect(x:rightX,y:navCard.frame.maxY+41,width:width,height:218))
        for (index,item) in ProfileSettingsLink.all.enumerated() {
            let row = link(tr(item.fr,item.en),symbol:item.symbol,color:item.color,frame:NSRect(x:1,y:3+CGFloat(index)*42,width:width-2,height:42),parent:links) { [weak self] in self?.openProfilePage(item.address) }
            row.identifier = .init("profile-link."+item.id); row.isEnabled = !privateWindow
            row.toolTip = privateWindow ? tr("Disponible dans une fenêtre normale","Available in a regular window") : tr("Ouvrir dans un nouvel onglet du profil ","Open in a new tab for ")+selected.name
            if index < ProfileSettingsLink.all.count-1 { line(links,y:45+CGFloat(index)*42) }
        }
        text(privateWindow ? tr("Les données de cette fenêtre privée restent temporaires.","This private window uses temporary data.") : tr("Ces pages s’ouvrent dans le profil « \(selected.name) ».","These pages open in the “\(selected.name)” profile."),NSRect(x:rightX+3,y:links.frame.maxY+6,width:width-6,height:26),size:11,color:.secondaryLabelColor)
        let extras = card(NSRect(x:rightX,y:links.frame.maxY+44,width:width,height:50))
        link(tr("Importer dans ce profil…","Import into this profile…"),symbol:"square.and.arrow.down",frame:NSRect(x:1,y:3,width:width-2,height:44),parent:extras) { [weak self] in guard let self else { return }; self.onImport?(self.selectedProfileID) }.isEnabled = !privateWindow
        pageContent.frame.size.height = max(scroll.bounds.height,extras.frame.maxY+20)
    }
    func refreshNavigationPreferences() { if section == 2 { rebuild() } }
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
        let width = bodyWidth-302
        sectionLabel(tr("Identifiants et formulaires","Credentials and forms"),x:28,y:99,width:width)
        let panel = card(NSRect(x:28,y:121,width:width,height:219))
        let rows = [(tr("Proposer d’enregistrer les mots de passe","Offer to save passwords"),tr("Active aussi la génération de nouveaux mots de passe.","Also enables generation of new passwords."),savePasswords),
                    (tr("Connexion automatique","Automatic sign-in"),tr("Utiliser vos identifiants enregistrés pour vous connecter.","Use saved credentials to sign in."),automaticSignIn),
                    (tr("Suggestions dans les formulaires","Form suggestions"),tr("Proposer vos adresses et vos saisies précédentes.","Suggest saved addresses and previous entries."),formSuggestions)]
        for (index,row) in rows.enumerated() {
            let y = CGFloat(index)*73
            text(row.0,NSRect(x:22,y:y+13,width:width-115,height:24),size:14,weight:.medium,in:panel)
            text(row.1,NSRect(x:22,y:y+36,width:width-115,height:32),size:12,color:.secondaryLabelColor,in:panel)
            let control = PreferenceSwitch(value:row.2) { [weak self] value in self?.setCredential(index,value) }
            control.frame = NSRect(x:width-67,y:y+23,width:42,height:26); control.setAccessibilityLabel(row.0); panel.addSubview(control)
            if index < 2 { line(panel,y:y+73) }
        }
        let note = card(NSRect(x:44+width,y:121,width:230,height:219))
        text(tr("Vos mots de passe restent conservés.","Your saved passwords are kept."),NSRect(x:16,y:22,width:198,height:54),weight:.medium,in:note)
        text(tr("Ces options ne désactivent pas le remplissage des identifiants existants ni les suggestions de vos extensions.","These options do not disable filling existing credentials or suggestions from your extensions."),NSRect(x:16,y:79,width:198,height:122),size:12,color:.secondaryLabelColor,in:note)
        pageContent.frame.size.height = max(scroll.bounds.height,372)
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
