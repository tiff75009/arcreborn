import AppKit
import QuartzCore

/// The engine retains the secret and the pending form. The native surface only
/// receives the origin, username and an opaque consent token.
final class PasswordSavePrompt {
    let tabID:String
    let request:UInt64
    private let panel:NSPanel
    private var events:Any?
    private var resizeObserver:NSObjectProtocol?
    private var finished = false
    private let respond:(Int)->Void

    init(tabID:String,request:UInt64,origin:String,username:String,profile:String,language:String,
         update:Bool,appearance:NSAppearance?,respond:@escaping (Int)->Void) {
        self.tabID = tabID; self.request = request; self.respond = respond
        let fr = language == "fr"
        panel = PasswordPromptPanel(contentRect:NSRect(x:0,y:0,width:480,height:174),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.appearance = appearance; panel.hidesOnDeactivate = true
        panel.setAccessibilityLabel(fr ? "Enregistrer un mot de passe" : "Save a password")
        let content = PasswordPromptSurface(frame:NSRect(x:0,y:0,width:480,height:174))
        panel.contentView = content
        func label(_ value:String,_ frame:NSRect,_ size:CGFloat,_ weight:NSFont.Weight = .regular,_ secondary:Bool = false) {
            let text = NSTextField(labelWithString:value); text.frame = frame; text.font = .systemFont(ofSize:size,weight:weight)
            text.autoresizingMask = [.width]; text.textColor = secondary ? .secondaryLabelColor : .labelColor
            text.lineBreakMode = .byTruncatingTail; content.addSubview(text)
        }
        let icon = NSImageView(frame:NSRect(x:23,y:25,width:28,height:28))
        icon.image = NSImage(systemSymbolName:"key.fill",accessibilityDescription:nil)
        icon.contentTintColor = PasswordPromptInk.accent; content.addSubview(icon)
        label(update ? (fr ? "Mettre à jour le mot de passe ?" : "Update your password?") : (fr ? "Enregistrer le mot de passe ?" : "Save your password?"),NSRect(x:72,y:19,width:365,height:22),15,.semibold)
        label(URL(string:origin)?.host ?? origin,NSRect(x:72,y:44,width:365,height:18),12,.regular,true)
        label(username.isEmpty ? (fr ? "Sans identifiant" : "No username") : username,NSRect(x:72,y:70,width:365,height:20),13,.medium)
        let lock = NSImageView(frame:NSRect(x:23,y:104,width:11,height:12))
        lock.image = NSImage(systemSymbolName:"lock.fill",accessibilityDescription:nil); lock.contentTintColor = .secondaryLabelColor; content.addSubview(lock)
        label(profile + (fr ? " · Trousseau du Mac" : " · Mac keychain"),NSRect(x:41,y:101,width:395,height:18),10.5,.regular,true)
        let never = PasswordPromptButton(fr ? "Jamais pour ce site" : "Never for this site",kind:.quiet) { [weak self] in self?.finish(2) }
        never.frame = NSRect(x:16,y:132,width:148,height:28); never.isHidden = update; content.addSubview(never)
        let later = PasswordPromptButton(fr ? "Pas maintenant" : "Not now",kind:.secondary) { [weak self] in self?.finish(0) }
        later.frame = NSRect(x:216,y:130,width:124,height:30); later.autoresizingMask = [.minXMargin]; content.addSubview(later)
        let save = PasswordPromptButton(update ? (fr ? "Mettre à jour" : "Update") : (fr ? "Enregistrer" : "Save"),kind:.primary) { [weak self] in self?.finish(1) }
        save.identifier = NSUserInterfaceItemIdentifier("password-prompt.save")
        save.frame = NSRect(x:348,y:130,width:112,height:30); save.autoresizingMask = [.minXMargin]; content.addSubview(save)
        let close = NavigationButton(fr ? "Fermer" : "Close",symbol:"xmark") { [weak self] in self?.finish(0) }
        close.frame = NSRect(x:448,y:12,width:20,height:20); close.autoresizingMask = [.minXMargin]; content.addSubview(close)
    }
    func show(in window:NSWindow) {
        position(in:window)
        resizeObserver = NotificationCenter.default.addObserver(forName:NSWindow.didResizeNotification,object:window,queue:.main) { [weak self,weak window] _ in
            guard let self, let window else { return }; self.position(in:window)
        }
        window.addChildWindow(panel,ordered:.above); panel.orderFront(nil)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18; context.timingFunction = CAMediaTimingFunction(name:.easeOut)
                panel.animator().alphaValue = 1
            }
        }
        events = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.finish(0); return nil }; return event
        }
    }
    private func position(in window:NSWindow) {
        let width = min(480,window.frame.width-32)
        panel.setContentSize(NSSize(width:width,height:174))
        panel.setFrameTopLeftPoint(NSPoint(x:window.frame.midX-width/2,y:window.frame.maxY-68))
    }
    func close() { finish(0) }
    private func finish(_ action:Int) {
        guard !finished else { return }; finished = true
        panel.parent?.removeChildWindow(panel); panel.orderOut(nil)
        if let events { NSEvent.removeMonitor(events); self.events = nil }
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver); self.resizeObserver = nil }
        respond(action)
    }
    deinit {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        if let events { NSEvent.removeMonitor(events) }
        panel.parent?.removeChildWindow(panel); panel.orderOut(nil)
    }
}

private enum PasswordPromptInk {
    static let accent = NSColor(name:nil) { $0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        ? NSColor(srgbRed:0.70,green:0.64,blue:1,alpha:1) : NSColor(srgbRed:0.37,green:0.28,blue:0.79,alpha:1) }
    static let surface = NSColor(name:nil) { $0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        ? NSColor(srgbRed:0.145,green:0.145,blue:0.17,alpha:1) : NSColor(srgbRed:0.99,green:0.99,blue:1,alpha:1) }
}
private final class PasswordPromptSurface:NSView {
    override var isFlipped:Bool { true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ rect:NSRect) {
        let path = NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:18,yRadius:18)
        PasswordPromptInk.surface.setFill(); path.fill()
        NSColor.labelColor.withAlphaComponent(0.10).setStroke(); path.lineWidth = 0.5; path.stroke()
        PasswordPromptInk.accent.withAlphaComponent(0.11).setFill()
        NSBezierPath(roundedRect:NSRect(x:16,y:18,width:42,height:42),xRadius:13,yRadius:13).fill()
    }
}
private final class PasswordPromptButton:ActionButton {
    enum Kind { case primary, secondary, quiet }
    private let kind:Kind
    init(_ title:String,kind:Kind,action:@escaping()->Void) { self.kind = kind; super.init(title,action:action); focusRingType = .exterior }
    required init?(coder:NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ rect:NSRect) {
        let path = NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:8,yRadius:8)
        if kind == .primary {
            NSColor(srgbRed:0.40,green:0.31,blue:0.87,alpha:isHighlighted ? 0.78 : 1).setFill(); path.fill()
        } else if kind == .secondary {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.12 : 0.06).setFill(); path.fill()
        }
        let ink:NSColor = kind == .primary ? .white : kind == .quiet ? .secondaryLabelColor : .labelColor
        let attrs:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:kind == .quiet ? 11 : 12,weight:kind == .quiet ? .regular : .semibold),.foregroundColor:ink]
        let text = title as NSString, size = text.size(withAttributes:attrs)
        text.draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2),withAttributes:attrs)
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:8,yRadius:8).fill() }
}
private final class PasswordPromptPanel:NSPanel { override var canBecomeKey:Bool { true } }
