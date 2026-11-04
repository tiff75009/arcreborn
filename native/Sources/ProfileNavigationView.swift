// SPDX-License-Identifier: MPL-2.0
import AppKit

enum ProfileNavigationEdit {
    case engine(SearchEngine)
    case homepage(String?)
    case autoArchive(Bool)
    case archive(ArchiveDelay)
}

private extension SearchEngine {
    var badge: (String, NSColor) {
        switch self {
        case .google: return ("G", .systemBlue)
        case .bing: return ("b", .systemTeal)
        case .duckduckgo: return ("D", .systemOrange)
        case .brave: return ("B", .systemRed)
        case .yahoo: return ("y!", .systemPurple)
        case .ecosia: return ("E", .systemGreen)
        case .qwant: return ("Q", .systemPink)
        case .startpage: return ("S", .systemIndigo)
        }
    }
}

/// Draw the marks locally; browsing preferences should never contact a search engine.
private final class SearchEngineTile: ChapterButton {
    let provider: SearchEngine
    var chosen = false {
        didSet { setAccessibilityValue(chosen ? 1 : 0); needsDisplay = true }
    }
    private var hovering = false
    init(_ engine: SearchEngine, action: @escaping () -> Void) {
        provider = engine
        super.init(engine.spec.name, style: .soft, action: action)
        toolTip = engine.spec.keyword
        setAccessibilityRole(.radioButton); setAccessibilityLabel(engine.spec.name)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseEntered(with event: NSEvent) { hovering = true; super.mouseEntered(with:event) }
    override func mouseExited(with event: NSEvent) { hovering = false; super.mouseExited(with:event) }
    override func draw(_ dirty: NSRect) {
        let border = NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1), xRadius:9, yRadius:9)
        (chosen ? ChapterInk.selected : hovering || isHighlighted ? ChapterInk.line : NSColor.clear).setFill(); border.fill()
        (chosen ? ChapterInk.accent : ChapterInk.line).setStroke(); border.lineWidth = chosen ? 1.4 : 1; border.stroke()
        let (mark,color) = provider.badge
        let markRect = NSRect(x:9,y:bounds.midY-12,width:24,height:24)
        color.withAlphaComponent(0.16).setFill(); NSBezierPath(roundedRect:markRect,xRadius:7,yRadius:7).fill()
        let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:16,weight:.bold),.foregroundColor:color]
        let size = (mark as NSString).size(withAttributes:attrs)
        (mark as NSString).draw(at:NSPoint(x:markRect.midX-size.width/2,y:markRect.midY-size.height/2),withAttributes:attrs)
        let label: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:12,weight:chosen ? .semibold : .medium),.foregroundColor:NSColor.labelColor]
        let name = provider.spec.name as NSString
        name.draw(at:NSPoint(x:39,y:bounds.midY-name.size(withAttributes:label).height/2),withAttributes:label)
        if chosen {
            let dot = NSRect(x:bounds.maxX-12,y:bounds.maxY-11,width:5,height:5)
            ChapterInk.accent.setFill(); NSBezierPath(ovalIn:dot).fill()
        }
    }
}

/// An engine selection is immediate. An address is a draft until Return or Save;
/// switching profiles, or simply editing a field, never navigates an existing tab.
final class ProfileNavigationView: NSView, NSTextFieldDelegate {
    static let panelHeight: CGFloat = 383
    override var isFlipped: Bool { true }
    private let english: Bool
    private var engine: SearchEngine, savedHome: String?
    private let change: (ProfileNavigationEdit) -> Bool
    private var tiles: [SearchEngineTile] = []
    private let modes = NSSegmentedControl(), urlField = NSTextField(), status = NSTextField(labelWithString:"")
    private let archivePicker = NSPopUpButton(frame:.zero,pullsDown:false)
    private let archiveSwitch = NSSwitch(), archiveHint = NSTextField(labelWithString:"")
    private var archiveEnabled: Bool
    private var archiveDelay: ArchiveDelay
    private let homeMark = WelcomeRibbonMark(frame:NSRect(x:14,y:209,width:54,height:54))
    private let homeTitle = NSTextField(labelWithString:"Arc Reborn")
    private var saveButton: ChapterButton!
    private var editingHome: Bool { modes.selectedSegment == 1 }
    private func tr(_ fr: String, _ en: String) -> String { english ? en : fr }

    init(frame:NSRect, profile:NativeProfile, english:Bool, readOnly:Bool, change:@escaping (ProfileNavigationEdit) -> Bool) {
        self.english = english; engine = profile.engine; savedHome = profile.homepage; archiveDelay = profile.archiveDelay; self.change = change
        archiveEnabled = profile.autoArchiveEnabled
        super.init(frame:frame)
        let w = bounds.width
        func label(_ text:String,_ y:CGFloat,_ font:NSFont,_ ink:NSColor) {
            let l = NSTextField(labelWithString:text); l.font = font; l.textColor = ink
            l.frame = NSRect(x:16,y:y,width:w-32,height:20); addSubview(l)
        }
        label(tr("Moteur de recherche","Search engine"), 14, .systemFont(ofSize:15,weight:.semibold), .labelColor)
        label(tr("Utilisé dans la barre d’adresse et pour rechercher du texte sélectionné.","Used in the address bar and when searching for selected text."), 36, .systemFont(ofSize:11.5), .secondaryLabelColor)
        let tileWidth = (w-32-18)/4
        for (i,provider) in SearchEngine.allCases.enumerated() {
            let tile = SearchEngineTile(provider) { [weak self] in self?.pick(provider) }
            tile.chosen = provider == engine
            tile.frame = NSRect(x:16+CGFloat(i%4)*(tileWidth+6),y:62+CGFloat(i/4)*43,width:tileWidth,height:38)
            tiles.append(tile); addSubview(tile)
        }
        let rule = NSBox(frame:NSRect(x:16,y:157,width:w-32,height:1)); rule.boxType = .separator; addSubview(rule)
        label(tr("Page du nouvel onglet","New tab page"), 172, .systemFont(ofSize:15,weight:.semibold), .labelColor)
        modes.segmentCount = 2; modes.trackingMode = .selectOne; modes.segmentStyle = .rounded
        modes.setLabel("Arc Reborn",forSegment:0); modes.setLabel(tr("Personnalisée","Custom URL"),forSegment:1)
        modes.frame = NSRect(x:w-222,y:166,width:207,height:32); modes.selectedSegment = savedHome == nil ? 0 : 1
        modes.setAccessibilityLabel(tr("Page du nouvel onglet","New tab page")); modes.target = self; modes.action = #selector(switchMode); addSubview(modes)
        homeMark.setAccessibilityElement(false); addSubview(homeMark)
        homeTitle.font = .systemFont(ofSize:14,weight:.semibold); homeTitle.textColor = .labelColor
        homeTitle.frame = NSRect(x:80,y:215,width:w-96,height:20); addSubview(homeTitle)

        urlField.font = .systemFont(ofSize:13); urlField.placeholderString = "https://exemple.fr"
        if english { urlField.placeholderString = "https://example.com" }
        urlField.cell?.wraps = false; urlField.cell?.isScrollable = true
        urlField.frame = NSRect(x:16,y:210,width:w-139,height:27); urlField.bezelStyle = .roundedBezel
        urlField.setAccessibilityLabel(tr("Adresse de la page d’accueil","Home page address"))
        urlField.target = self; urlField.action = #selector(saveHome); urlField.delegate = self; addSubview(urlField)
        saveButton = ChapterButton(tr("Enregistrer","Save"),style:.soft) { [weak self] in self?.saveHome() }
        saveButton.frame = NSRect(x:w-116,y:207,width:101,height:32); addSubview(saveButton)
        status.frame = NSRect(x:17,y:251,width:w-34,height:34); status.font = .systemFont(ofSize:11.5)
        status.maximumNumberOfLines = 2; status.lineBreakMode = .byWordWrapping; addSubview(status)
        let lowerRule = NSBox(frame:NSRect(x:16,y:277,width:w-32,height:1)); lowerRule.boxType = .separator; addSubview(lowerRule)
        label(tr("Archivage automatique","Auto archive"), 290, .systemFont(ofSize:15,weight:.semibold), .labelColor)
        archiveSwitch.frame = NSRect(x:w-58,y:285,width:42,height:28); archiveSwitch.isEnabled = !readOnly
        archiveSwitch.target = self; archiveSwitch.action = #selector(toggleArchive)
        archiveSwitch.setAccessibilityLabel(tr("Archivage automatique des onglets","Automatically archive idle tabs")); addSubview(archiveSwitch)
        archiveHint.frame = NSRect(x:16,y:314,width:w-32,height:21); archiveHint.font = .systemFont(ofSize:11.5)
        archiveHint.textColor = .secondaryLabelColor; addSubview(archiveHint)
        label(tr("Délai d’inactivité","Idle time"), 348, .systemFont(ofSize:13,weight:.medium), .labelColor)
        archivePicker.addItems(withTitles: ArchiveDelay.allCases.map { $0.label(english:english) })
        archivePicker.selectItem(at:ArchiveDelay.allCases.firstIndex(of:archiveDelay) ?? 0)
        archivePicker.frame = NSRect(x:w-196,y:340,width:182,height:30)
        archivePicker.setAccessibilityLabel(tr("Délai d’archivage automatique","Auto archive interval"))
        archivePicker.target = self; archivePicker.action = #selector(setArchiveDelay); addSubview(archivePicker)
        refreshArchive(); refreshHome()
        if readOnly {
            tiles.forEach { $0.isEnabled = false }; modes.isEnabled = false; urlField.isEditable = false; saveButton.isEnabled = false
            feedback(tr("Ces choix sont hérités du profil. Modifiez-les dans une fenêtre normale.","These settings follow your profile. Change them in a regular window."))
        }
    }
    required init?(coder:NSCoder) { fatalError() }
    private func refreshArchive() {
        archiveSwitch.state = archiveEnabled ? .on : .off
        archivePicker.isEnabled = archiveEnabled && archiveSwitch.isEnabled
        archiveHint.stringValue = archiveEnabled
            ? tr("Les favoris et les onglets épinglés restent en place.","Favorites and pinned tabs stay where they are.")
            : tr("Désactivé. Vos onglets restent ouverts jusqu’à ce que vous les fermiez.","Off. Your tabs stay open until you close them.")
    }
    @objc private func toggleArchive() {
        let enabled = archiveSwitch.state == .on
        guard change(.autoArchive(enabled)) else {
            refreshArchive()
            archiveHint.stringValue = tr("Le réglage n’a pas pu être enregistré.","Could not save this setting."); return
        }
        archiveEnabled = enabled; refreshArchive()
    }
    @objc private func setArchiveDelay() {
        guard archiveEnabled else { return }
        guard ArchiveDelay.allCases.indices.contains(archivePicker.indexOfSelectedItem) else { return }
        let picked = ArchiveDelay.allCases[archivePicker.indexOfSelectedItem]
        guard change(.archive(picked)) else {
            archivePicker.selectItem(at:ArchiveDelay.allCases.firstIndex(of:archiveDelay) ?? 0)
            feedback(tr("Impossible d’enregistrer le délai.","Could not save the interval."),error:true); return
        }
        archiveDelay = picked
    }
    private func pick(_ value:SearchEngine) {
        guard value != engine else { return }
        guard change(.engine(value)) else { feedback(tr("Ce moteur n’a pas pu être appliqué à ce profil.","This search engine could not be applied to this profile."),error:true); return }
        engine = value; tiles.forEach { $0.chosen = $0.provider == value }
    }
    private func feedback(_ value:String,error:Bool = false) {
        status.stringValue = value; status.textColor = error ? .systemRed : .secondaryLabelColor
    }
    private func refreshHome() {
        urlField.stringValue = savedHome ?? ""; urlField.isHidden = !editingHome; saveButton.isHidden = !editingHome
        homeMark.isHidden = editingHome; homeTitle.isHidden = editingHome
        status.frame = editingHome ? NSRect(x:17,y:251,width:bounds.width-34,height:34) :
            NSRect(x:80,y:238,width:bounds.width-96,height:34)
        if editingHome { updateDraft() }
        else { feedback(tr("Les nouveaux onglets s’ouvrent sur l’accueil d’Arc Reborn.","New tabs open on the Arc Reborn start page.")) }
    }
    @objc private func switchMode() {
        if !editingHome, savedHome != nil {
            guard change(.homepage(nil)) else { modes.selectedSegment = 1; feedback(tr("Impossible de rétablir l’accueil.","Could not restore the start page."),error:true); return }
            savedHome = nil
        }
        refreshHome()
        if editingHome { window?.makeFirstResponder(urlField) }
    }
    private func updateDraft() {
        let input = urlField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        let address = normalizedNewTabAddress(input)
        saveButton.isEnabled = address != nil && address != savedHome
        if input.isEmpty { feedback(tr("Saisissez l’adresse à ouvrir, par exemple wikipedia.org.","Enter the address to open, for example wikipedia.org.")) }
        else if address == nil { feedback(tr("Saisissez une adresse web valide (HTTP ou HTTPS), sans identifiants.","Enter a valid HTTP or HTTPS address without credentials."),error:true) }
        else if address == savedHome { feedback(tr("Cette adresse s’ouvrira dans vos prochains onglets.","This address will open in your next new tabs.")) }
        else { feedback(tr("Appuyez sur Entrée pour enregistrer cette adresse.","Press Return to save this address.")) }
    }
    func controlTextDidChange(_ notification: Notification) { updateDraft() }
    @objc private func saveHome() {
        guard editingHome, let address = normalizedNewTabAddress(urlField.stringValue) else { updateDraft(); return }
        if address != savedHome, !change(.homepage(address)) { feedback(tr("Impossible d’enregistrer cette adresse.","Could not save this address."),error:true); return }
        savedHome = address; refreshHome()
    }
}
