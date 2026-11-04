import AppKit

final class WindowChromeBar: NSView, NSTextFieldDelegate {
    override var isFlipped: Bool { true }
    private let address = NSTextField()
    var addressSurface: NSRect { address.frame.insetBy(dx:-5,dy:-3) }
    private let badge = NSTextField(labelWithString:"")
    private let back = ActionButton("",symbol:"chevron.left") {}
    private let forward = ActionButton("",symbol:"chevron.right") {}
    private let reload = ActionButton("",symbol:"arrow.clockwise") {}
    private let expand = ActionButton("",symbol:"arrow.up.left.and.arrow.down.right") {}
    var navigate: ((String)->Void)?
    init(compact:Bool, privateWindow:Bool, language:String, back actionBack:@escaping ()->Void, forward actionForward:@escaping ()->Void, reload actionReload:@escaping ()->Void, expand actionExpand:@escaping ()->Void) {
        self.compact = compact; self.privateWindow = privateWindow
        super.init(frame:.zero)
        wantsLayer = true; layer?.cornerRadius = 9
        back.invoke = actionBack; forward.invoke = actionForward; reload.invoke = actionReload; expand.invoke = actionExpand
        address.isBordered = false; address.drawsBackground = false; address.focusRingType = .none
        address.font = .systemFont(ofSize:13,weight:.medium); address.delegate = self; address.target = self; address.action = #selector(openAddress)
        address.placeholderString = language == "fr" ? "Rechercher ou saisir une URL…" : "Search or enter a URL…"
        address.setAccessibilityLabel(language == "fr" ? "Adresse de la page" : "Page address")
        badge.stringValue = privateWindow ? (language == "fr" ? "🔒 Privé" : "🔒 Private") : ""
        badge.font = .systemFont(ofSize:11,weight:.semibold); badge.textColor = .secondaryLabelColor
        for view in [back,forward,reload,address,badge,expand] { addSubview(view) }
        back.toolTip = language == "fr" ? "Page précédente" : "Back"; forward.toolTip = language == "fr" ? "Page suivante" : "Forward"
        reload.toolTip = language == "fr" ? "Recharger / arrêter" : "Reload / stop"
        expand.toolTip = language == "fr" ? "Ouvrir dans une fenêtre complète" : "Open in a full window"
        expand.isHidden = !compact
    }
    private let compact:Bool
    private let privateWindow:Bool
    required init?(coder:NSCoder) { fatalError() }
    @objc private func openAddress() { navigate?(address.stringValue) }
    override func layout() {
        super.layout()
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.18).cgColor
        var x:CGFloat = compact ? 78 : 5
        for button in [back,forward,reload] { button.frame = NSRect(x:x,y:6,width:28,height:28); x += 29; button.contentTintColor = .labelColor }
        if privateWindow { badge.frame = NSRect(x:x+5,y:13,width:65,height:18); x += 72 }
        let trailing:CGFloat = compact ? 40 : 10
        address.frame = NSRect(x:x+6,y:11,width:max(70,bounds.width-x-trailing-12),height:22)
        expand.frame = NSRect(x:bounds.width-35,y:6,width:28,height:28); expand.contentTintColor = .labelColor
    }
    func update(url:String,back canBack:Bool,forward canForward:Bool,loading:Bool) {
        if address.currentEditor() == nil { address.stringValue = url == "about:blank" ? "" : browserDisplayAddress(url) }
        back.isEnabled = canBack; forward.isEnabled = canForward
        reload.image = NSImage(systemSymbolName:loading ? "xmark" : "arrow.clockwise",accessibilityDescription:nil)
    }
}
