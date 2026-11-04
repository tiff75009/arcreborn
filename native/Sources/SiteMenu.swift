import AppKit
import QuartzCore

private final class SiteMenuSurface: NSVisualEffectView {
    override var isFlipped:Bool { true }
    func trackPointer(at screenPoint:NSPoint) {
        subviews.compactMap { $0 as? SiteMenuSection }.forEach { $0.trackPointer(at:screenPoint) }
        let actions = subviews.compactMap { $0 as? SiteMenuAction } + subviews.flatMap { $0.subviews.compactMap { $0 as? SiteMenuAction } }
        actions.forEach { $0.trackPointer(at:screenPoint) }
        subviews.compactMap { $0 as? SiteConnectionButton }.forEach { $0.trackPointer(at:screenPoint) }
    }
    // Empty areas belong to the panel too; never forward their pointer events.
    override func mouseDown(with event:NSEvent) {}
    override func rightMouseDown(with event:NSEvent) {}
    override func mouseMoved(with event:NSEvent) {}
    override func scrollWheel(with event:NSEvent) {}
}

private final class SiteMenuHeaderButton: ActionButton {
    private var hovered = false
    private var tracking: NSTrackingArea?
    override func draw(_ dirtyRect:NSRect) {
        if hovered && isEnabled {
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect:bounds,xRadius:5,yRadius:5).fill()
        }
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (title as NSString).draw(in:NSRect(x:4,y:(bounds.height-16)/2,width:bounds.width-8,height:16),withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.semibold),.foregroundColor:NSColor.white.withAlphaComponent(isEnabled ? 0.72 : 0.4),.paragraphStyle:style])
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self); addTrackingArea(tracking!)
    }
    override func mouseEntered(with event:NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event:NSEvent) { hovered = false; needsDisplay = true }
}

private final class SiteMenuSection: NSView {
    override var isFlipped:Bool { true }
    let headerAction: SiteMenuHeaderButton
    private var tracking:NSTrackingArea?
    private var revealed = false
    private var revision = 0
    init(frame:NSRect, title:String, enabled:Bool, action:@escaping ()->Void) {
        headerAction = SiteMenuHeaderButton(title,action:action)
        super.init(frame:frame)
        headerAction.frame = NSRect(x:166,y:0,width:62,height:22)
        headerAction.isEnabled = enabled; headerAction.alphaValue = 0; headerAction.isHidden = true
        addSubview(headerAction)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self); addTrackingArea(tracking!)
    }
    override func mouseEntered(with event:NSEvent) { reveal(true) }
    override func mouseExited(with event:NSEvent) { reveal(false) }
    func trackPointer(at screenPoint:NSPoint) {
        guard let window else { return }
        reveal(bounds.contains(convert(window.convertPoint(fromScreen:screenPoint),from:nil)))
    }
    private func reveal(_ visible:Bool) {
        guard revealed != visible else { return }; revealed = visible; revision += 1
        let token = revision; headerAction.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
            context.timingFunction = CAMediaTimingFunction(name:.easeOut)
            headerAction.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            guard let self, self.revision == token else { return }
            self.headerAction.isHidden = !visible
        }
    }
}
private final class SiteMenuAction: NSButton {
    let symbol: String
    let heading: String
    private(set) var detail: String
    let compact: Bool
    var translucentTile = false
    private var toggleLabels: (on:String,off:String)?
    private var toggleOn = false
    private var activationPending = false
    private let invoke: (() -> Void)?
    private var hovered = false
    private var tracking: NSTrackingArea?
    init(symbol:String, title:String, detail:String = "", compact:Bool = false, action:(()->Void)?) {
        self.symbol = symbol; heading = title; self.detail = detail; self.compact = compact; invoke = action
        super.init(frame:.zero); self.title = ""; isBordered = false; wantsLayer = true; layer?.cornerRadius = compact ? 8 : 10
        isEnabled = action != nil; target = self; self.action = #selector(activate)
        setAccessibilityLabel(title+(detail.isEmpty ? "" : ", "+detail)); toolTip = title
    }
    required init?(coder:NSCoder) { fatalError() }
    func configureToggle(isOn:Bool,onDetail:String,offDetail:String) {
        toggleLabels = (onDetail,offDetail); toggleOn = isOn; updateToggle()
    }
    private func updateToggle() {
        guard let labels = toggleLabels else { return }
        detail = toggleOn ? labels.on : labels.off
        setAccessibilityValue(toggleOn ? 1 : 0)
        setAccessibilityLabel(heading+", "+detail); needsDisplay = true
    }
    @objc private func activate() {
        guard isEnabled, !activationPending else { return }
        guard toggleLabels != nil else { invoke?(); return }
        activationPending = true; toggleOn.toggle(); updateToggle()
        setPressed(false,fromHeld:true)
        // Keep the feedback visible before the existing action closes the menu.
        let delay = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.26
        DispatchQueue.main.asyncAfter(deadline:.now()+delay) { [self] in
            activationPending = false; invoke?()
        }
    }
    override func mouseDown(with event:NSEvent) {
        guard toggleLabels != nil, isEnabled else { super.mouseDown(with:event); return }
        guard !activationPending else { return }
        setPressed(true)
        super.mouseDown(with:event)
        if !activationPending { setPressed(false) }
    }
    private func setPressed(_ pressed:Bool,fromHeld:Bool = false) {
        guard let layer else { return }
        func transform(_ scale:CGFloat) -> CATransform3D {
            let dx = bounds.width*(0.5-layer.anchorPoint.x), dy = bounds.height*(0.5-layer.anchorPoint.y)
            return CATransform3DScale(CATransform3DMakeTranslation(dx*(1-scale),dy*(1-scale),0),scale,scale,1)
        }
        let start = fromHeld ? transform(0.975) : (layer.presentation()?.transform ?? layer.transform)
        let end = pressed ? transform(0.975) : CATransform3DIdentity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = end; layer.removeAnimation(forKey:"site-toggle-press")
        CATransaction.commit()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let animation:CABasicAnimation
        if pressed {
            animation = CABasicAnimation(keyPath:"transform"); animation.duration = 0.11
            animation.timingFunction = CAMediaTimingFunction(name:.easeOut)
        } else {
            let spring = CASpringAnimation(keyPath:"transform")
            spring.mass = 1; spring.stiffness = 460; spring.damping = 25
            spring.duration = min(0.42,spring.settlingDuration); animation = spring
        }
        animation.fromValue = NSValue(caTransform3D:start); animation.toValue = NSValue(caTransform3D:end)
        layer.add(animation,forKey:"site-toggle-press")
    }
    override var isFlipped:Bool { true }
    override func draw(_ rect:NSRect) {
        let ink = NSColor.white.withAlphaComponent(isEnabled ? 0.85 : 0.48)
        if compact {
            let path = NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:8,yRadius:8)
            if translucentTile {
                NSColor.white.withAlphaComponent(hovered && isEnabled ? 0.13 : 0.07).setFill(); path.fill()
            } else {
                NSGradient(starting:NSColor(white:hovered && isEnabled ? 0.23 : 0.15,alpha:0.96),ending:NSColor(white:0.055,alpha:0.96))?.draw(in:path,angle:90)
                NSColor.white.withAlphaComponent(0.14).setStroke(); path.lineWidth = 0.5; path.stroke()
            }
        }
        let box = compact ? NSRect(x:bounds.midX-10,y:bounds.midY-10,width:20,height:20) : NSRect(x:8,y:bounds.midY-10,width:20,height:20)
        let illuminated = toggleLabels != nil && toggleOn
        if !compact {
            (illuminated ? NSColor.white : ink.withAlphaComponent(isEnabled ? 0.16 : 0.07)).setFill()
            NSBezierPath(ovalIn:NSRect(x:2,y:bounds.midY-16,width:32,height:32)).fill()
        }
        SpaceIcon.draw("sf:"+symbol,in:box,color:illuminated ? .black : ink,size:18)
        if !compact {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            (heading as NSString).draw(in:NSRect(x:42,y:8,width:bounds.width-48,height:19),withAttributes:[.font:NSFont.systemFont(ofSize:14,weight:.semibold),.foregroundColor:ink,.paragraphStyle:paragraph])
            (detail as NSString).draw(in:NSRect(x:42,y:27,width:bounds.width-48,height:17),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:ink.withAlphaComponent(isEnabled ? 0.65 : 0.36)])
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self); addTrackingArea(tracking!)
    }
    override func mouseEntered(with event:NSEvent) { hovered = true; refresh() }
    override func mouseExited(with event:NSEvent) { hovered = false; refresh() }
    func trackPointer(at screenPoint:NSPoint) {
        guard let window else { return }
        let inside = bounds.contains(convert(window.convertPoint(fromScreen:screenPoint),from:nil))
        guard hovered != inside else { return }
        hovered = inside; refresh()
    }
    private func refresh() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12; context.allowsImplicitAnimation = true
            layer?.backgroundColor = NSColor.white.withAlphaComponent(hovered && isEnabled ? 0.09 : 0).cgColor
        }
        needsDisplay = true
    }
}

private final class SiteConnectionButton: ActionButton {
    private let secure: Bool
    private var hovered = false
    private var tracking: NSTrackingArea?
    private let textFont = NSFont.systemFont(ofSize:12,weight:.semibold)
    var preferredWidth: CGFloat { ceil((title as NSString).size(withAttributes:[.font:textFont]).width)+45 }
    override var isFlipped: Bool { true }

    init(title:String, secure:Bool, action:(()->Void)?) {
        self.secure = secure
        super.init(title,action:{ action?() })
        isEnabled = action != nil; focusRingType = .exterior
    }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.white.withAlphaComponent(isEnabled && isHighlighted ? 0.19 : (hovered && isEnabled ? 0.13 : 0.07)).setFill()
        NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill()
        let ink = NSColor.white.withAlphaComponent(0.85)
        let attributes: [NSAttributedString.Key:Any] = [.font:textFont,.foregroundColor:ink]
        let size = (title as NSString).size(withAttributes:attributes)
        let x = (bounds.width-(14+7+size.width))/2
        SpaceIcon.draw("sf:"+(secure ? "lock.fill" : "exclamationmark.triangle"),in:NSRect(x:x,y:bounds.midY-7,width:14,height:14),color:ink,size:14)
        (title as NSString).draw(at:NSPoint(x:x+21,y:(bounds.height-size.height)/2),withAttributes:attributes)
    }
    override func resetCursorRects() { if isEnabled { addCursorRect(bounds,cursor:.pointingHand) } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self); addTrackingArea(tracking!)
    }
    override func mouseEntered(with event:NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event:NSEvent) { hovered = false; needsDisplay = true }
    func trackPointer(at point:NSPoint) {
        guard let window else { return }
        let inside = bounds.contains(convert(window.convertPoint(fromScreen:point),from:nil))
        if inside != hovered { hovered = inside; needsDisplay = true }
    }
}

final class SiteMenu: NSObject, NSPopoverDelegate {
    struct Actions {
        var share:(()->Void)?
        var capture:(()->Void)?
        var find:(()->Void)?
        var developer:(()->Void)?
        var pictureInPicture:(()->Void)?
        var automaticPictureInPicture:(()->Void)?
        var clearCache:(()->Void)?
        var clearCookies:(()->Void)?
        var manageExtensions:(()->Void)?
        var addExtension:(()->Void)?
        var certificate:(()->Void)?
        var allSiteSettings:(()->Void)?
    }
    private let popover = NSPopover()
    private let surface = SiteMenuSurface(frame:NSRect(x:0,y:0,width:236,height:294))
    private var pointerMonitor:Any?
    private var deactivateObserver:NSObjectProtocol?
    private var trackingMore = false
    private weak var ownerWindow:NSWindow?
    private let actions:Actions
    private let language:String
    private let dismissed:()->Void
    private var afterClose:(()->Void)?
    var isShown:Bool { popover.isShown }
    var pointerChanged:(()->Void)?
    init(language:String,color:NSColor,secureConnection:Bool,developerOpen:Bool,automaticPiP:Bool,pipOpen:Bool,extensions items:[BrowserExtension] = [],pinned:Set<String> = [],activateExtension:@escaping (BrowserExtension)->Void = { _ in },pinExtension:@escaping (BrowserExtension)->Void = { _ in },actions:Actions,dismissed:@escaping ()->Void) {
        self.language = language; self.actions = actions; self.dismissed = dismissed
        super.init()
        surface.material = .popover; surface.blendingMode = .behindWindow; surface.state = .active; surface.wantsLayer = true
        surface.layer?.cornerRadius = 19
        surface.layer?.borderWidth = 0.5
        surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        let wash = NSView(frame:surface.bounds); wash.wantsLayer = true; wash.layer?.backgroundColor = color.withAlphaComponent(0.22).cgColor; surface.addSubview(wash)
        let quick:[(String,String,(() -> Void)?)] = [
            ("square.and.arrow.up","sharePage",actions.share), (pipOpen ? "pip.exit" : "pip.enter",pipOpen ? "closePiP" : "openPiP",actions.pictureInPicture),
            ("camera","capturePage",actions.capture), ("viewfinder","find",actions.find)
        ]
        for (index,item) in quick.enumerated() {
            let button = SiteMenuAction(symbol:item.0,title:t(item.1),compact:true,action:item.2.map { action in { [weak self] in self?.close(completion:action) } })
            button.frame = NSRect(x:10+index*56,y:10,width:48,height:32); surface.addSubview(button)
        }
        let extensions = SiteMenuSection(frame:NSRect(x:0,y:53,width:236,height:66),title:t("manageSection"),enabled:actions.manageExtensions != nil) { [weak self] in
            self?.close(); actions.manageExtensions?()
        }
        extensions.headerAction.toolTip = t("manageExtensions")
        surface.addSubview(extensions)
        heading("extensions",in:extensions)
        let scroller = NSScrollView(frame:NSRect(x:8,y:24,width:220,height:40))
        scroller.drawsBackground = false; scroller.hasHorizontalScroller = false
        let strip = NSView(frame:NSRect(x:0,y:0,width:max(220,(items.count+1)*56),height:40))
        scroller.documentView = strip; extensions.addSubview(scroller)
        for (index,item) in items.enumerated() {
            let button = ExtensionActionButton(item) { activateExtension(item) }
            button.ink = .white; button.frame = NSRect(x:index*56,y:4,width:48,height:32)
            button.restingFillOpacity = 0.07
            strip.addSubview(button)
            let pin = ExtensionPinButton(language == "fr" ? "Épingler / détacher" : "Pin / unpin") { [weak self] in
                self?.close(); pinExtension(item)
            }
            pin.pinned = pinned.contains(item.id)
            pin.ink = .white; pin.contentTintColor = .white
            pin.frame = NSRect(x:index*56+34,y:0,width:18,height:18)
            pin.layer?.cornerRadius = 9
            strip.addSubview(pin)
        }
        let add = SiteMenuAction(symbol:"plus",title:t("addExtension"),compact:true,action:actions.addExtension.map { action in { [weak self] in self?.close(); action() } })
        add.translucentTile = true; add.frame = NSRect(x:items.count*56,y:4,width:48,height:32); strip.addSubview(add)
        let settings = SiteMenuSection(frame:NSRect(x:0,y:125,width:236,height:114),title:t("moreSection"),enabled:true) { [weak self] in
            self?.showMore(settingsOnly:true,at:NSPoint(x:222,y:145))
        }
        settings.headerAction.setAccessibilityLabel(t("moreSiteSettings"))
        surface.addSubview(settings)
        heading("settings",in:settings)
        let developer = SiteMenuAction(symbol:"hammer.fill",title:t("developerMode"),detail:t(developerOpen ? "enabledState" : "offState"),action:actions.developer.map { action in { [weak self] in
            if let self { self.close(completion:action) } else { action() }
        } })
        developer.configureToggle(isOn:developerOpen,onDetail:t("enabledState"),offDetail:t("offState"))
        developer.frame = NSRect(x:8,y:22,width:220,height:46); settings.addSubview(developer)
        let pip = SiteMenuAction(symbol:"pip",title:t("automaticPiP"),detail:t(automaticPiP ? "enabledState" : "offState"),action:actions.automaticPictureInPicture.map { action in { [weak self] in self?.close(completion:action) } })
        pip.configureToggle(isOn:automaticPiP,onDetail:t("enabledState"),offDetail:t("offState"))
        pip.toolTip = t("automaticPiPHelp")
        pip.frame = NSRect(x:8,y:68,width:220,height:46); settings.addSubview(pip)
        let separator = NSBox(); separator.boxType = .separator; separator.frame = NSRect(x:10,y:244,width:216,height:1); surface.addSubview(separator)
        let badge = SiteConnectionButton(title:t(secureConnection ? "httpsConnection" : "notSecureConnection"),secure:secureConnection,action:actions.certificate.map { action in
            { [weak self] in self?.close(completion:action) }
        })
        badge.frame = NSRect(x:10,y:255,width:badge.preferredWidth,height:28)
        badge.toolTip = actions.certificate == nil ? t("notSecureConnection") : (language == "fr" ? "Afficher le certificat" : "Show Certificate")
        surface.addSubview(badge)
        let more = NavigationButton(t("more"),symbol:"ellipsis") { [weak self] in self?.showMore() }; more.ink = .white; more.contentTintColor = .white.withAlphaComponent(0.8)
        more.frame = NSRect(x:194,y:253,width:32,height:32); more.wantsLayer = true; more.layer?.cornerRadius = 16; surface.addSubview(more)
        let controller = NSViewController(); controller.view = surface
        popover.contentViewController = controller; popover.contentSize = surface.frame.size; popover.behavior = .applicationDefined
        popover.appearance = NSAppearance(named:.darkAqua); popover.delegate = self
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    private func t(_ key:String)->String { L10n.text(key,language:language) }
    private func heading(_ key:String,in section:NSView) {
        let label = NSTextField(labelWithString:t(key)); label.font = .systemFont(ofSize:14,weight:.semibold); label.textColor = .white.withAlphaComponent(0.75); label.frame = NSRect(x:10,y:0,width:150,height:22); section.addSubview(label)
    }
    func show(of view:NSView) {
        ownerWindow = view.window
        popover.show(relativeTo:view.bounds,of:view,preferredEdge:.maxY)
        surface.window?.acceptsMouseMovedEvents = true
        pointerChanged?()
        // AppKit can still deliver tracking events to Chromium's parent window
        // while a child popover covers it. Drop only those occluded events,
        // leaving the popover and outside clicks (dismissal) untouched.
        deactivateObserver = NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) { [weak self] _ in self?.close() }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.mouseMoved,.mouseEntered,.mouseExited,.cursorUpdate,.scrollWheel,.leftMouseDown,.rightMouseDown,.otherMouseDown,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged,.leftMouseUp,.rightMouseUp,.otherMouseUp]) { [weak self] event in
            guard let self, self.isShown else { return event }
            guard !self.trackingMore else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.close(); return nil }
                return event
            }
            self.pointerChanged?()
            self.surface.trackPointer(at:NSEvent.mouseLocation)
            guard let panel = self.surface.window else { return event }
            let inside = panel.frame.contains(NSEvent.mouseLocation)
            if !inside && [.leftMouseDown,.rightMouseDown,.otherMouseDown].contains(event.type) {
                self.close(); return nil
            }
            if inside && event.window === self.ownerWindow && event.type != .mouseExited { return nil }
            return event
        }
    }
    private func removePointerMonitor() {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor); self.pointerMonitor = nil }
        if let deactivateObserver { NotificationCenter.default.removeObserver(deactivateObserver); self.deactivateObserver = nil }
    }
    deinit { removePointerMonitor() }
    func close(animated:Bool = true,completion:(()->Void)? = nil) {
        guard isShown else { completion?(); return }
        afterClose = completion
        // Extension actions hand focus to another native popup. Do not make
        // their loading wait for the system popover's closing animation.
        if !animated { popover.animates = false }
        popover.close(); removePointerMonitor()
    }
    func popoverDidClose(_ notification:Notification) {
        removePointerMonitor()
        let completion = afterClose; afterClose = nil
        dismissed()
        completion?()
    }
    private func showMore(settingsOnly:Bool = false,at anchor:NSPoint = NSPoint(x:210,y:268)) {
        trackingMore = true; defer { trackingMore = false }
        let menu = NSMenu(); menu.autoenablesItems = false
        for (key,action) in [("clearSiteCache",actions.clearCache),("clearSiteCookies",actions.clearCookies),("-",nil),("manageBoosts",nil),("newBoost",nil),("-",nil),("manageExtensions",actions.manageExtensions),("addExtension",actions.addExtension),("-",nil),("allSiteSettings",actions.allSiteSettings)] as [(String,(() -> Void)?)] {
            if settingsOnly && ["manageBoosts","newBoost","manageExtensions","addExtension"].contains(key) { continue }
            if key == "-" {
                if menu.items.last?.isSeparatorItem == false { menu.addItem(.separator()) }
                continue
            }
            let item = NSMenuItem(title:t(key),action:action == nil ? nil : #selector(performMore(_:)),keyEquivalent:"")
            item.target = self; item.isEnabled = action != nil; item.representedObject = key
            if key == "clearSiteCache" { item.toolTip = t("clearCacheScope") }
            if key == "clearSiteCookies" { item.toolTip = t("clearCookiesScope") }
            menu.addItem(item)
        }
        menu.popUp(positioning:nil,at:anchor,in:surface)
    }
    @objc private func performMore(_ item:NSMenuItem) {
        let action: (() -> Void)?
        switch item.representedObject as? String {
        case "clearSiteCache": action = actions.clearCache
        case "clearSiteCookies": action = actions.clearCookies
        case "manageExtensions": action = actions.manageExtensions
        case "addExtension": action = actions.addExtension
        case "allSiteSettings":
            // Finish the context menu and popover before focusing the new tab.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }; self.close(completion:self.actions.allSiteSettings)
            }
            return
        default: action = nil
        }
        close(); action?()
    }
}
