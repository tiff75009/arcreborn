import AppKit

/// Success-only UI: Chromium owns the preceding integrity and permission checks.
final class ExtensionInstallNotice: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let surface = NSVisualEffectView(frame:NSRect(x:0,y:0,width:306,height:170))
    private var events:Any?
    private var deactivation:NSObjectProtocol?
    private let dismissed:()->Void
    private var didDismiss = false
    init(item:BrowserExtension,language:String,color:NSColor,pinned:Bool,pin:@escaping ()->Void,dismissed:@escaping ()->Void) {
        self.dismissed = dismissed
        super.init()
        let fr = language == "fr"
        surface.material = .popover; surface.blendingMode = .behindWindow; surface.state = .active
        surface.wantsLayer = true; surface.layer?.cornerRadius = 18
        surface.layer?.borderWidth = 0.5; surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        let wash = NSView(frame:surface.bounds); wash.wantsLayer = true
        wash.layer?.backgroundColor = color.withAlphaComponent(0.22).cgColor; surface.addSubview(wash)
        let icon = NSImageView(frame:NSRect(x:20,y:110,width:36,height:36))
        icon.image = item.image ?? NSImage(systemSymbolName:"puzzlepiece.extension.fill",accessibilityDescription:nil)
        icon.contentTintColor = .white; icon.imageScaling = .scaleProportionallyDown; surface.addSubview(icon)
        let heading = NSTextField(labelWithString:fr ? "Extension installée" : "Extension installed")
        heading.font = .systemFont(ofSize:15,weight:.semibold); heading.textColor = .white
        heading.frame = NSRect(x:68,y:132,width:210,height:20); surface.addSubview(heading)
        let name = NSTextField(labelWithString:item.name)
        name.font = .systemFont(ofSize:12); name.textColor = .white.withAlphaComponent(0.72)
        name.lineBreakMode = .byTruncatingTail; name.frame = NSRect(x:68,y:111,width:210,height:18); surface.addSubview(name)
        let explanation = NSTextField(wrappingLabelWithString:fr ? "Épinglez-la pour la retrouver dans votre barre latérale." : "Pin it for quick access from your sidebar.")
        explanation.font = .systemFont(ofSize:12); explanation.textColor = .white.withAlphaComponent(0.8)
        explanation.frame = NSRect(x:20,y:63,width:266,height:36); surface.addSubview(explanation)
        let close = NavigationButton(fr ? "Fermer" : "Close",symbol:"xmark") { [weak self] in self?.close() }
        close.ink = .white; close.frame = NSRect(x:276,y:143,width:20,height:20); surface.addSubview(close)
        let later = ActionButton(fr ? "Plus tard" : "Not now") { [weak self] in self?.close() }
        later.frame = NSRect(x:20,y:17,width:116,height:32); later.isBordered = false
        later.contentTintColor = .white.withAlphaComponent(0.8); surface.addSubview(later)
        let button = ActionButton(pinned ? (fr ? "Épinglée" : "Pinned") : (fr ? "Épingler" : "Pin extension")) { [weak self] in
            self?.close(); pin()
        }
        button.bezelStyle = .rounded; button.bezelColor = color.blended(withFraction:0.35,of:.white)
        button.contentTintColor = .white; button.font = .systemFont(ofSize:13,weight:.semibold)
        button.frame = NSRect(x:150,y:17,width:136,height:32); button.isEnabled = !pinned
        surface.addSubview(button)
        let controller = NSViewController(); controller.view = surface
        popover.contentViewController = controller; popover.contentSize = surface.frame.size
        popover.behavior = .applicationDefined; popover.delegate = self
        popover.appearance = NSAppearance(named:.darkAqua)
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    func show(of anchor:NSView) {
        popover.show(relativeTo:anchor.bounds,of:anchor,preferredEdge:.maxY)
        events = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.otherMouseDown,.keyDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.close(); return nil }
            } else if let window = self.surface.window, !window.frame.contains(NSEvent.mouseLocation) {
                self.close()
            }
            return event
        }
        deactivation = NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) { [weak self] _ in self?.close() }
    }
    func close() { popover.close() }
    func popoverDidClose(_ notification:Notification) {
        cleanup()
        guard !didDismiss else { return }; didDismiss = true; dismissed()
    }
    private func cleanup() {
        if let events { NSEvent.removeMonitor(events); self.events = nil }
        if let deactivation { NotificationCenter.default.removeObserver(deactivation); self.deactivation = nil }
    }
    deinit { cleanup() }
}
