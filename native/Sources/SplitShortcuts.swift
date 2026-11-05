import AppKit

enum SplitShortcutAction: String, CaseIterable {
    case add, close, note, separate, pane1, pane2, pane3, pane4, next, previous
    func title(_ language:String) -> String {
        let titles:[String:(String,String)] = [
            "add":("Ajouter une vue partagée","Add Split View"), "close":("Retirer le panneau actif","Close this Split Pane"),
            "note":("Nouvelle note (dans la vue)","New Note (in Split)"), "separate":("Séparer la page de la vue","Separate Page from Split View"),
            "pane1":("Activer le panneau 1","Switch to Split View 1"), "pane2":("Activer le panneau 2","Switch to Split View 2"),
            "pane3":("Activer le panneau 3","Switch to Split View 3"), "pane4":("Activer le panneau 4","Switch to Split View 4"),
            "next":("Panneau suivant","Switch to next Split View"), "previous":("Panneau précédent","Switch to previous Split View")]
        let pair = titles[rawValue]!; return language == "en" ? pair.1 : pair.0
    }
    var defaultBinding:SplitKeyBinding {
        let keys:[String:String] = ["add":"=","close":"-","note":"n","separate":"","pane1":"1","pane2":"2","pane3":"3","pane4":"4","next":"]","previous":"["]
        return SplitKeyBinding(key:keys[rawValue] ?? "",modifiers:(self == .note ? NSEvent.ModifierFlags([.control,.option]) : [.control,.shift]).rawValue)
    }
}
extension SplitKeyBinding {
    var caption:String {
        key.isEmpty ? "—" : keycaps.joined()
    }
    var keycaps:[String] {
        guard !key.isEmpty else { return [] }
        let flags = NSEvent.ModifierFlags(rawValue:modifiers)
        let mods:[(NSEvent.ModifierFlags,String)] = [(.control,"⌃"),(.option,"⌥"),(.shift,"⇧"),(.command,"⌘")]
        let keys = ["\u{F700}":"↑","\u{F701}":"↓","\u{F702}":"←","\u{F703}":"→","\t":"⇥"," ":"Espace"]
        return mods.compactMap { flags.contains($0.0) ? $0.1 : nil } + [keys[key] ?? key.uppercased()]
    }
}
private final class SplitShortcutRecorder: NSButton {
    var binding = SplitKeyBinding(key:"",modifiers:0) { didSet { title = binding.caption } }
    var record:((SplitKeyBinding) -> Bool)?
    private var recording = false
    override var acceptsFirstResponder:Bool { true }
    override func mouseDown(with event:NSEvent) {
        guard isEnabled else { return }
        recording = true; window?.makeFirstResponder(self); title = "…"; contentTintColor = .systemPurple
    }
    override func resignFirstResponder() -> Bool { recording = false; title = binding.caption; contentTintColor = .labelColor; return true }
    override func performKeyEquivalent(with event:NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with:event) }; keyDown(with:event); return true
    }
    override func keyDown(with event:NSEvent) {
        guard recording else { super.keyDown(with:event); return }
        if event.keyCode == 53 { window?.makeFirstResponder(nil); return }
        let flags = event.modifierFlags.intersection([.command,.control,.option,.shift])
        var candidate = SplitKeyBinding(key:(event.charactersIgnoringModifiers ?? "").lowercased(),modifiers:flags.rawValue)
        if event.keyCode == 51 || event.keyCode == 117 { candidate = SplitKeyBinding(key:"",modifiers:0) }
        else if flags.intersection([.command,.control,.option]).isEmpty || candidate.key.count != 1 { NSSound.beep(); return }
        if record?(candidate) == true { binding = candidate; window?.makeFirstResponder(nil) } else { NSSound.beep() }
    }
}
final class CommandShortcutsPreferencesView: SplitFlippedView, NSSearchFieldDelegate {
    private let search = NSSearchField(), scroll = NSScrollView(), document = SplitFlippedView()
    private let feedback = NSTextField(wrappingLabelWithString:"")
    private let hint = NSTextField(wrappingLabelWithString:"")
    private var reset:ActionButton!
    private var lastWidth:CGFloat = 0
    var bindings:[String:SplitKeyBinding]
    let language:String
    var changed:(([String:SplitKeyBinding])->Void)?
    init(language:String,bindings:[String:SplitKeyBinding]) {
        self.language = language; self.bindings = bindings; super.init(frame:NSRect(x:0,y:0,width:916,height:520))
        search.placeholderString = language == "fr" ? "Rechercher une commande ou une catégorie…" : "Search commands or categories…"
        search.delegate = self; search.setAccessibilityLabel(language == "fr" ? "Rechercher un raccourci" : "Search shortcuts"); addSubview(search)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.wantsLayer = true; scroll.layer?.cornerRadius = 14; scroll.layer?.borderWidth = 0.5
        scroll.documentView = document; addSubview(scroll)
        reset = ChapterButton(language == "fr" ? "Réinitialiser" : "Reset",style:.soft) { [weak self] in
            guard let self else { return }; self.bindings = [:]; self.feedback.stringValue = ""; self.changed?([:]); self.rebuild()
        }
        reset.isBordered = false; addSubview(reset)
        hint.stringValue = language == "fr" ? "Échap pour annuler · Effacer pour retirer une combinaison. Les commandes à venir restent grisées." : "Escape to cancel · Delete to clear a combination. Unavailable commands remain dimmed."
        hint.font = .systemFont(ofSize:11); hint.textColor = .secondaryLabelColor; addSubview(hint)
        feedback.font = .systemFont(ofSize:11); feedback.textColor = .systemOrange; addSubview(feedback)
        needsLayout = true
    }
    required init?(coder:NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        search.frame = NSRect(x:0,y:0,width:max(220,bounds.width-146),height:30)
        reset.frame = NSRect(x:bounds.width-130,y:0,width:130,height:30)
        scroll.frame = NSRect(x:0,y:45,width:bounds.width,height:max(220,bounds.height-106))
        hint.frame = NSRect(x:2,y:bounds.height-49,width:bounds.width-4,height:27)
        feedback.frame = NSRect(x:2,y:bounds.height-24,width:bounds.width-4,height:26)
        scroll.layer?.borderColor = ChapterInk.line.cgColor
        scroll.layer?.backgroundColor = ChapterInk.surface.cgColor
        let width = scroll.contentSize.width
        if abs(lastWidth-width)>0.5 { lastWidth = width; rebuild() }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsLayout = true }
    func controlTextDidChange(_ obj:Notification) { scroll.contentView.scroll(to:.zero); rebuild() }
    private func rebuild() {
        document.subviews.forEach { $0.removeFromSuperview() }
        let query = search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        let commands = BrowserCommands.all.filter { query.isEmpty || $0.title(language).localizedCaseInsensitiveContains(query) || BrowserCommands.categoryTitle($0.category,language).localizedCaseInsensitiveContains(query) }
        let effective = BrowserCommands.displayedBindings(bindings), width = max(380,lastWidth)
        reset.isEnabled = !bindings.isEmpty
        var y:CGFloat = 0
        for category in BrowserCommands.categories {
            let rows = commands.filter { $0.category == category }; guard !rows.isEmpty else { continue }
            let heading = NSTextField(labelWithString:BrowserCommands.categoryTitle(category,language))
            heading.stringValue = heading.stringValue.uppercased(); heading.font = .monospacedSystemFont(ofSize:10,weight:.semibold); heading.textColor = ChapterInk.accent
            heading.frame = NSRect(x:16,y:y+12,width:width-36,height:20); document.addSubview(heading); y += 33
            for command in rows {
                let label = NSTextField(wrappingLabelWithString:command.title(language)); label.font = .systemFont(ofSize:13)
                label.textColor = command.available ? .labelColor : .tertiaryLabelColor
                label.frame = NSRect(x:16,y:y+9,width:width-170,height:32); document.addSubview(label)
                let recorder = SplitShortcutRecorder(frame:NSRect(x:width-136,y:y+4,width:116,height:28))
                recorder.bezelStyle = .rounded; recorder.isBordered = true; recorder.font = .monospacedSystemFont(ofSize:12,weight:.medium)
                recorder.binding = effective[command.id] ?? .init(key:"",modifiers:0); recorder.isEnabled = command.available
                recorder.setAccessibilityLabel(command.title(language))
                recorder.toolTip = command.available ? (language == "fr" ? "Cliquez pour modifier ; Effacer pour retirer." : "Click to edit; Delete to clear.") : (language == "fr" ? "Bientôt disponible" : "Not available yet")
                recorder.record = { [weak self] binding in
                    guard let self, BrowserCommands.valid(binding) else { return false }
                    let current = BrowserCommands.displayedBindings(self.bindings)
                    if !binding.key.isEmpty {
                        if let conflict = BrowserCommands.all.first(where: { $0.id != command.id && current[$0.id] == binding }) {
                            self.feedback.stringValue = self.language == "fr" ? "Déjà utilisé pour « \(conflict.title(self.language)) ». Retirez d’abord cet autre raccourci." : "Already used by “\(conflict.title(self.language))”. Clear that shortcut first."; return false
                        }
                        if BrowserCommands.reserved.contains(binding) {
                            self.feedback.stringValue = self.language == "fr" ? "Ce raccourci est réservé à l’édition de texte." : "This shortcut is reserved for text editing."; return false
                        }
                    }
                    self.feedback.stringValue = ""; self.bindings[command.id] = binding; self.reset.isEnabled = true; self.changed?(self.bindings); return true
                }
                document.addSubview(recorder)
                let line = NSBox(frame:NSRect(x:18,y:y+36,width:width-36,height:1)); line.boxType = .separator; document.addSubview(line)
                y += 37
            }
            y += 8
        }
        if commands.isEmpty {
            let empty = NSTextField(labelWithString:language == "fr" ? "Aucun raccourci trouvé" : "No shortcuts found")
            empty.textColor = .secondaryLabelColor; empty.frame = NSRect(x:20,y:24,width:width-40,height:24); document.addSubview(empty)
        }
        document.frame = NSRect(x:0,y:0,width:width,height:max(60,y))
    }
}
