// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

private final class UpdateCardSurface: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event:NSEvent) {} // Never forward to tabs underneath.
}

/// A bottom-anchored native surface. Only the painted portion owns hit testing;
/// the empty area above the collapsed pill remains available to the tab list.
final class SidebarUpdateCard: NSView {
    static let expandedHeight: CGFloat = 94
    static let collapsedHeight: CGFloat = 25
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    private let surface = UpdateCardSurface()
    private let heading = NSTextField(labelWithString:"")
    private let automatic = UpdateAutomaticButton()
    private let install = UpdateInstallButton()
    private let separator = CALayer()
    private var expanded = false
    private var available = false
    private var suppressed = false
    private var ink = NSColor.white
    private var closeTask: DispatchWorkItem?
    private var revision = 0
    var activate: (() -> Void)?
    var toggleAutomatic: ((Bool) -> Void)?
    var expansionChanged: ((Bool) -> Void)?
    var occupiedHeight: CGFloat { expanded ? Self.expandedHeight : Self.collapsedHeight }
    var isExpanded: Bool { expanded && !isHidden }

    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer = true; isHidden = true
        surface.wantsLayer = true; surface.layer?.masksToBounds = true
        surface.layer?.borderWidth = 1
        addSubview(surface)
        heading.alignment = .center; heading.font = .systemFont(ofSize:12.5,weight:.medium)
        heading.lineBreakMode = .byTruncatingTail
        surface.addSubview(heading)
        surface.layer?.addSublayer(separator)
        automatic.target = self; automatic.action = #selector(automaticPressed)
        automatic.font = .systemFont(ofSize:12.5,weight:.medium)
        automatic.appearance = NSAppearance(named:.darkAqua)
        surface.addSubview(automatic); surface.addSubview(install)
        automatic.isHidden = true; install.isHidden = true
        install.invoke = { [weak self] in self?.activate?() }
        setAccessibilityElement(true); setAccessibilityRole(.group)
    }
    required init?(coder:NSCoder) { fatalError() }
    deinit { closeTask?.cancel() }

    func update(phase:SidebarUpdateSession.Phase, progress:Double?, actionable:Bool,
                automatic:Bool, allowsAutomatic:Bool, accent:NSColor, ink:NSColor, language:String) {
        let french = language.lowercased().hasPrefix("fr")
        available = phase != .hidden
        isHidden = !available || suppressed
        self.ink = ink
        heading.stringValue = french ? "Nouvelle version disponible" : "New Arc Reborn Version Available"
        self.automatic.title = french ? "Mises à jour automatiques" : "Automatic Updates"
        self.automatic.state = automatic ? .on : .off
        self.automatic.isEnabled = allowsAutomatic
        install.isEnabled = actionable
        switch phase {
        case .downloading:
            install.title = (french ? "Téléchargement" : "Downloading") + (progress.map { " · \(Int($0 * 100)) %" } ?? "…")
        case .preparing: install.title = french ? "Préparation…" : "Preparing…"
        case .awaitingRestart: install.title = french ? "Réessayer le redémarrage" : "Retry Restart"
        case .installing: install.title = french ? "Redémarrage…" : "Restarting…"
        default: install.title = french ? "Redémarrer et mettre à jour" : "Restart and Update"
        }
        install.setAccessibilityLabel(install.title)
        install.setColor(accent); install.setProgress(progress)
        setAccessibilityLabel(heading.stringValue)
        if !available { setExpanded(false,animated:false) }
        refreshColors(); needsLayout = true
    }

    func setSuppressed(_ value:Bool) {
        suppressed = value; isHidden = !available || value
        if value { setExpanded(false,animated:false) }
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let height = occupiedHeight
        surface.frame = NSRect(x:0,y:bounds.height-height,width:bounds.width,height:height)
        heading.frame = NSRect(x:6,y:4,width:max(0,bounds.width-12),height:18)
        heading.font = .systemFont(ofSize:bounds.width < 220 ? 11.5 : 12.5,weight:.medium)
        separator.frame = NSRect(x:0,y:26,width:bounds.width,height:0.5)
        automatic.sizeToFit()
        automatic.frame = NSRect(x:max(6,(bounds.width-automatic.frame.width)/2),y:33,width:min(bounds.width-12,automatic.frame.width),height:20)
        install.frame = NSRect(x:8,y:62,width:max(0,bounds.width-16),height:25)
        CATransaction.commit()
    }
    private func refreshColors() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.layer?.backgroundColor = (expanded ? NSColor(srgbRed:0.025,green:0.025,blue:0.032,alpha:1) : ink.withAlphaComponent(0.085)).cgColor
        surface.layer?.borderColor = (expanded ? NSColor.white.withAlphaComponent(0.20) : ink.withAlphaComponent(0.18)).cgColor
        surface.layer?.cornerRadius = expanded ? 13 : Self.collapsedHeight/2
        heading.textColor = expanded ? .white : ink
        separator.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        CATransaction.commit()
    }
    func setExpanded(_ value:Bool, animated:Bool = true) {
        let value = value && available && !suppressed
        closeTask?.cancel(); closeTask = nil
        guard value != expanded else { return }
        revision += 1; let generation = revision
        layoutSubtreeIfNeeded()
        let from = surface.layer?.presentation() ?? surface.layer!
        let oldBounds = from.bounds, oldPosition = from.position, oldColor = from.backgroundColor
        expanded = value
        if value { automatic.isHidden = false; install.isHidden = false }
        layout(); refreshColors()
        expansionChanged?(value)
        guard animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            surface.layer?.removeAllAnimations()
            automatic.isHidden = !value; install.isHidden = !value
            return
        }
        let duration = value ? 0.42 : 0.30
        for (key,start,end) in [("bounds",NSValue(rect:oldBounds),NSValue(rect:surface.layer!.bounds)),
                                ("position",NSValue(point:oldPosition),NSValue(point:surface.layer!.position))] {
            let motion = CASpringAnimation(keyPath:key)
            motion.fromValue = start; motion.toValue = end
            motion.mass = 1; motion.stiffness = 330; motion.damping = 31
            motion.duration = duration; surface.layer?.add(motion,forKey:key)
        }
        let color = CABasicAnimation(keyPath:"backgroundColor")
        color.fromValue = oldColor; color.toValue = surface.layer?.backgroundColor
        color.duration = 0.20; surface.layer?.add(color,forKey:"backgroundColor")
        for (index,view) in [automatic,install].enumerated() {
            view.wantsLayer = true
            let opacity = CABasicAnimation(keyPath:"opacity")
            opacity.fromValue = view.layer?.presentation()?.opacity ?? (value ? 0 : 1)
            opacity.toValue = value ? 1 : 0
            opacity.duration = value ? 0.20 : 0.10
            opacity.beginTime = CACurrentMediaTime() + (value ? 0.065 + Double(index)*0.04 : 0)
            opacity.fillMode = .backwards
            view.layer?.add(opacity,forKey:"reveal")
        }
        if !value {
            install.setHovered(false)
            DispatchQueue.main.asyncAfter(deadline:.now()+duration) { [weak self] in
                guard let self, self.revision == generation, !self.expanded else { return }
                self.automatic.isHidden = true; self.install.isHidden = true
            }
        }
    }
    /// Called by the browser's existing pointer monitor, including when the
    /// sidebar is temporarily revealed over the web page.
    func trackPointer(_ point:NSPoint?) {
        guard !isHidden else { return }
        let local = point.map { convert($0,from:nil) }
        let inside = local.map { paintedRect.insetBy(dx:0,dy:expanded ? -4 : 0).contains($0) } ?? false
        install.setHovered(local.map { expanded && install.bounds.contains(install.convert($0,from:self)) } ?? false)
        if inside { closeTask?.cancel(); closeTask = nil; setExpanded(true) }
        else if expanded && closeTask == nil {
            let task = DispatchWorkItem { [weak self] in self?.setExpanded(false) }
            closeTask = task; DispatchQueue.main.asyncAfter(deadline:.now()+0.16,execute:task)
        }
    }
    private var paintedRect: NSRect {
        let current = surface.layer?.presentation()?.frame ?? surface.frame
        // Keep swallowing clicks on the disappearing card until it has closed.
        return current.union(surface.frame)
    }
    func contains(_ windowPoint:NSPoint) -> Bool { !isHidden && paintedRect.contains(convert(windowPoint,from:nil)) }
    override func hitTest(_ point:NSPoint) -> NSView? {
        guard !isHidden, paintedRect.contains(convert(point,from:superview)) else { return nil }
        return super.hitTest(point) ?? self
    }
    override func mouseDown(with event:NSEvent) { setExpanded(true) }
    override func scrollWheel(with event:NSEvent) {} // The covered tabs must not receive wheel events.
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { setExpanded(true); return true }
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 53 { setExpanded(false); window?.makeFirstResponder(nil) }
        else if event.keyCode == 36 || event.keyCode == 49 { setExpanded(true) }
        else { super.keyDown(with:event) }
    }
    override func accessibilityPerformPress() -> Bool { setExpanded(true); return true }
    @objc private func automaticPressed() { toggleAutomatic?(automatic.state == .on) }
}

/// Native checkbox semantics with Arc's small square outline rather than the
/// operating system's larger, filled switch artwork.
private final class UpdateAutomaticButton: NSButton {
    override init(frame:NSRect) {
        super.init(frame:frame); setButtonType(.switch); isBordered = false
    }
    convenience init() { self.init(frame:.zero) }
    required init?(coder:NSCoder) { fatalError() }
    override func sizeToFit() {
        frame.size = NSSize(width:ceil((title as NSString).size(withAttributes:[.font:font ?? NSFont.systemFont(ofSize:12.5)]).width)+19,height:20)
    }
    override func draw(_ dirtyRect:NSRect) {
        let color = NSColor.white.withAlphaComponent(isEnabled ? 0.72 : 0.4)
        let box = NSRect(x:1,y:bounds.midY-5.5,width:11,height:11)
        let outline = NSBezierPath(roundedRect:box,xRadius:1,yRadius:1)
        color.setStroke(); outline.lineWidth = 1.1; outline.stroke()
        if state == .on {
            let check = NSBezierPath()
            check.move(to:NSPoint(x:3.3,y:bounds.midY)); check.line(to:NSPoint(x:5.4,y:bounds.midY-2.3)); check.line(to:NSPoint(x:9.8,y:bounds.midY+2.8))
            check.lineWidth = 1.3; check.lineCapStyle = .round; check.lineJoinStyle = .round; check.stroke()
        }
        let attrs:[NSAttributedString.Key:Any] = [.font:font ?? NSFont.systemFont(ofSize:12.5),.foregroundColor:color]
        let height = (title as NSString).size(withAttributes:attrs).height
        (title as NSString).draw(at:NSPoint(x:19,y:(bounds.height-height)/2),withAttributes:attrs)
    }
}

/// Color remains faithful to the space (muted themes stay muted). A moving
/// light inside the clipped button responds to hover; the label stays sharp.
private final class UpdateInstallButton: NSButton {
    var invoke: (() -> Void)?
    private let light = CAGradientLayer(), progressLayer = CALayer()
    private var hovered = false
    override init(frame:NSRect) {
        super.init(frame:frame)
        isBordered = false; wantsLayer = true; layer?.cornerRadius = 7
        layer?.masksToBounds = true; layer?.borderWidth = 0.8
        layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        font = .systemFont(ofSize:12.5,weight:.medium)
        light.colors = [0,0.04,0.22,0.04,0].map { NSColor.white.withAlphaComponent($0).cgColor }
        light.startPoint = CGPoint(x:0,y:0.3); light.endPoint = CGPoint(x:1,y:0.7)
        light.opacity = 0; layer?.addSublayer(light)
        progressLayer.backgroundColor = NSColor.white.withAlphaComponent(0.19).cgColor
        layer?.addSublayer(progressLayer)
        target = self; action = #selector(pressed)
    }
    convenience init() { self.init(frame:.zero) }
    required init?(coder:NSCoder) { fatalError() }
    override func layout() {
        super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true)
        light.frame = bounds.insetBy(dx:-bounds.width*0.3,dy:0)
        CATransaction.commit()
    }
    func setColor(_ color:NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .systemIndigo
        // Preserve chroma, cap luminance for the white label on pale spaces.
        let luminance = 0.2126*rgb.redComponent + 0.7152*rgb.greenComponent + 0.0722*rgb.blueComponent
        let scale = luminance > 0.53 ? 0.53/luminance : 1
        layer?.backgroundColor = NSColor(srgbRed:rgb.redComponent*scale,green:rgb.greenComponent*scale,blue:rgb.blueComponent*scale,alpha:1).cgColor
    }
    func setProgress(_ progress:Double?) {
        progressLayer.frame = NSRect(x:0,y:0,width:bounds.width*CGFloat(progress ?? 0),height:bounds.height)
    }
    func setHovered(_ value:Bool) {
        let value = value && isEnabled
        guard hovered != value else { return }; hovered = value
        let opacity = CABasicAnimation(keyPath:"opacity")
        opacity.fromValue = light.presentation()?.opacity ?? light.opacity
        opacity.toValue = value ? 1 : 0; opacity.duration = 0.18
        light.opacity = value ? 1 : 0; light.add(opacity,forKey:"hover")
        if value && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let sweep = CABasicAnimation(keyPath:"transform.translation.x")
            sweep.fromValue = -bounds.width*0.65; sweep.toValue = bounds.width*0.65
            sweep.duration = 1.4; sweep.autoreverses = true; sweep.repeatCount = .infinity
            sweep.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
            light.add(sweep,forKey:"light")
        } else { light.removeAnimation(forKey:"light") }
    }
    override func draw(_ dirtyRect:NSRect) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key:Any] = [.font:font ?? NSFont.systemFont(ofSize:12.5),.foregroundColor:NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.75),.paragraphStyle:paragraph]
        let size = (title as NSString).size(withAttributes:attrs)
        (title as NSString).draw(in:NSRect(x:4,y:(bounds.height-size.height)/2,width:bounds.width-8,height:size.height),withAttributes:attrs)
    }
    override func mouseDown(with event:NSEvent) {
        guard isEnabled else { return }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let press = CAKeyframeAnimation(keyPath:"transform.scale")
            press.values = [1,0.974,1.006,1]; press.keyTimes = [0,0.24,0.65,1]; press.duration = 0.34
            press.calculationMode = .cubic; layer?.add(press,forKey:"press")
        }
        super.mouseDown(with:event)
    }
    @objc private func pressed() { invoke?() }
}
