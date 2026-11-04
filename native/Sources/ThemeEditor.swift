import AppKit
import QuartzCore

private final class ThemePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
private final class ThemeButton: NSButton {
    var invoke: (() -> Void)?
    init(_ symbol: String, label: String, frame: NSRect, action: @escaping () -> Void) {
        super.init(frame: frame)
        isBordered = false; image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        image = image?.withSymbolConfiguration(.init(pointSize: 18, weight: .medium))
        imagePosition = .imageOnly; title = ""; target = self; self.action = #selector(performAction)
        invoke = action; toolTip = label; setAccessibilityLabel(label); wantsLayer = true; layer?.cornerRadius = 10
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func performAction() { invoke?() }
}
private struct ThemePreset {
    let colors: [String]
}
private final class ThemeSwatch: NSButton {
    var colors = ["#FFFFFF"]
    var selected = false
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx:3,dy:3))
        NSGraphicsContext.saveGraphicsState(); circle.addClip()
        let palette = colors.compactMap { NSColor(browserHex:$0) }
        if palette.count > 1 { NSGradient(colors:palette)?.draw(in:bounds,angle:45) }
        else { (palette.first ?? .white).setFill(); circle.fill() }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.12).setStroke(); circle.lineWidth = 2; circle.stroke()
        if selected { NSColor.white.setStroke(); circle.lineWidth = 2.5; circle.stroke() }
    }
}
private final class ThemeCanvas: NSView {
    var points: [ThemePoint] = [] { didSet { needsDisplay = true; window?.invalidateCursorRects(for:self) } }
    var selected = 0 { didSet { needsDisplay = true } }
    var began: (() -> Void)?
    var changed: ((Int, NSPoint) -> Void)?
    private var dragging = false
    private var grabOffset = NSPoint.zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private var field: NSRect { NSRect(x:24,y:76,width:bounds.width-48,height:216) }
    override func resetCursorRects() {
        for point in points { let p = location(point); addCursorRect(NSRect(x:p.x-24,y:p.y-24,width:48,height:48),cursor:dragging ? .closedHand : .openHand) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.035).setFill()
        NSBezierPath(roundedRect:bounds,xRadius:12,yRadius:12).fill()
        NSColor.labelColor.withAlphaComponent(0.14).setFill()
        for y in stride(from:5.0,to:bounds.height,by:4.5) {
            for x in stride(from:5.0,to:bounds.width,by:4.5) { NSBezierPath(ovalIn:NSRect(x:x,y:y,width:0.8,height:0.8)).fill() }
        }
        // Draw the active circle last, so it stays draggable when colors meet.
        for i in points.indices.sorted(by: { ($0 == selected ? 1 : 0) < ($1 == selected ? 1 : 0) }) {
            let center = location(points[i]), radius: CGFloat = i == selected ? 20 : 12
            let circle = NSBezierPath(ovalIn:NSRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2))
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowBlurRadius = 8; shadow.shadowOffset = NSSize(width:0,height:-2); shadow.shadowColor = NSColor.black.withAlphaComponent(0.15); shadow.set()
            (NSColor(browserHex:points[i].color) ?? .white).setFill(); circle.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.setStroke(); circle.lineWidth = i == selected ? 4 : 3; circle.stroke()
        }
    }
    private func location(_ p: ThemePoint) -> NSPoint { NSPoint(x:field.minX+p.x*field.width,y:field.minY+p.y*field.height) }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        guard let index = points.indices.min(by: { hypot(location(points[$0]).x-point.x,location(points[$0]).y-point.y) < hypot(location(points[$1]).x-point.x,location(points[$1]).y-point.y) }),
              hypot(location(points[index]).x-point.x,location(points[index]).y-point.y) < 26 else { return }
        selected = index; window?.makeFirstResponder(self)
        let center = location(points[index]); grabOffset = NSPoint(x:point.x-center.x,y:point.y-center.y)
        dragging = true; NSCursor.closedHand.push(); began?()
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }; NSCursor.closedHand.set()
        let point = convert(event.locationInWindow,from:nil)
        changed?(selected,NSPoint(x:(point.x-grabOffset.x-field.minX)/field.width,y:(point.y-grabOffset.y-field.minY)/field.height))
    }
    override func mouseUp(with event: NSEvent) { endDrag() }
    func endDrag() { if dragging { dragging = false; NSCursor.pop(); window?.invalidateCursorRects(for:self) } }
    override func keyDown(with event: NSEvent) {
        guard points.indices.contains(selected) else { return }
        if event.keyCode == 48 { selected = (selected+1)%points.count; return }
        let delta: NSPoint
        switch event.keyCode {
        case 123: delta = NSPoint(x:-0.015,y:0)
        case 124: delta = NSPoint(x:0.015,y:0)
        case 125: delta = NSPoint(x:0,y:0.015)
        case 126: delta = NSPoint(x:0,y:-0.015)
        default: super.keyDown(with:event); return
        }
        began?(); changed?(selected,NSPoint(x:points[selected].x+delta.x,y:points[selected].y+delta.y))
    }
}
private class GrabSlider: NSSlider {
    private var grabbing = false
    override func resetCursorRects() {
        addCursorRect(bounds,cursor:grabbing ? .closedHand : .openHand)
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        grabbing = true
        NSCursor.closedHand.push()
        defer {
            grabbing = false
            NSCursor.pop()
            window?.invalidateCursorRects(for:self)
        }
        // AppKit owns the complete mouse tracking loop, including release outside.
        super.mouseDown(with:event)
    }
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        if grabbing { NSCursor.closedHand.set() }
        return super.sendAction(action,to:target)
    }
}
private final class WaveSlider: GrabSlider {
    private(set) var intensity: Double = 0
    private var targetIntensity: Double = 0
    private var timer: Timer?
    func showIntensity(_ value: Double, animated: Bool) {
        doubleValue = value; needsDisplay = true
        guard animated else { timer?.invalidate(); timer = nil; intensity = value; targetIntensity = value; needsDisplay = true; return }
        guard targetIntensity != value else { return }
        targetIntensity = value
        // Retarget the running animation instead of restarting its clock on every
        // mouse event (which can otherwise starve all frames during a fast drag).
        guard timer == nil else { return }
        var previousTime = CACurrentMediaTime()
        let tick = Timer(timeInterval:1.0/120,repeats:true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let now = CACurrentMediaTime(), elapsed = now-previousTime
            previousTime = now
            self.intensity += (self.targetIntensity-self.intensity)*(1-exp(-elapsed/0.035))
            if abs(self.targetIntensity-self.intensity) < 0.0005 {
                self.intensity = self.targetIntensity; timer.invalidate(); self.timer = nil
            }
            self.needsDisplay = true
        }
        timer = tick; RunLoop.main.add(tick,forMode:.common)
    }
    func stopAnimation() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
}
private final class WaveCell: NSSliderCell {
    override var knobThickness: CGFloat { 16 }
    override func knobRect(flipped: Bool) -> NSRect {
        let native = super.knobRect(flipped:flipped)
        let height = min(44,controlView?.bounds.height ?? 44)
        return NSRect(x:native.midX-8,y:native.midY-height/2,width:16,height:height)
    }
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let path = NSBezierPath(); path.lineWidth = 5; path.lineCapStyle = .round
        for step in 0...160 {
            let x = rect.minX+CGFloat(step)/160*rect.width
            let intensity = (controlView as? WaveSlider)?.intensity ?? doubleValue
            let y = rect.midY+sin(CGFloat(step)/160 * .pi*10)*CGFloat(intensity)*16
            if step == 0 { path.move(to:NSPoint(x:x,y:y)) } else { path.line(to:NSPoint(x:x,y:y)) }
        }
        NSColor.labelColor.withAlphaComponent(0.24).setStroke(); path.stroke()
    }
    override func drawKnob(_ knobRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.9).setFill()
        // Match AppKit's invalidation and hit-test rectangle exactly. Painting
        // outside the native knob rect leaves stale end caps during tracking.
        NSBezierPath(roundedRect:knobRect,xRadius:8,yRadius:8).fill()
    }
}
private final class GrainSlider: GrabSlider {
    static let detents = 22
    private var trackedDetent: Int?

    override func mouseDown(with event: NSEvent) {
        trackedDetent = Int((doubleValue * Double(Self.detents)).rounded())
        defer { trackedDetent = nil }
        // NSSlider tracks the complete drag inside this call.
        super.mouseDown(with:event)
    }

    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        if let previous = trackedDetent {
            let position = doubleValue * Double(Self.detents)
            // Small hysteresis avoids buzzing when a finger rests on a boundary.
            if abs(position - Double(previous)) >= 0.6 {
                trackedDetent = Int(position.rounded())
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment,performanceTime:.now)
            }
        }
        // No timer or queued pulses: feedback stops as soon as the gesture stops.
        return super.sendAction(action,to:target)
    }
}
private final class GrainCell: NSSliderCell {
    override func draw(withFrame frame: NSRect, in controlView: NSView) {
        let center = NSPoint(x:frame.midX,y:frame.midY), radius = min(frame.width,frame.height)/2-8
        for i in 0..<GrainSlider.detents {
            let angle = CGFloat(i)/CGFloat(GrainSlider.detents) * .pi*2 - .pi/2
            NSColor.labelColor.withAlphaComponent(0.25).setFill()
            NSBezierPath(ovalIn:NSRect(x:center.x+cos(angle)*radius-2,y:center.y+sin(angle)*radius-2,width:4,height:4)).fill()
        }
        let disc = NSBezierPath(ovalIn:NSRect(x:center.x-19,y:center.y-19,width:38,height:38))
        NSColor.gray.withAlphaComponent(0.45).setFill(); disc.fill()
        NSGraphicsContext.saveGraphicsState(); disc.addClip()
        NSGraphicsContext.current?.cgContext.setAlpha(0.35)
        NSColor(patternImage:ThemePainter.noise).setFill(); disc.bounds.fill()
        NSGraphicsContext.restoreGraphicsState()
        let angle = CGFloat(doubleValue)*2 * .pi - .pi/2
        let tick = NSBezierPath(); tick.lineWidth = 5; tick.lineCapStyle = .round
        tick.move(to:NSPoint(x:center.x+cos(angle)*(radius-4),y:center.y+sin(angle)*(radius-4)))
        tick.line(to:NSPoint(x:center.x+cos(angle)*(radius+2),y:center.y+sin(angle)*(radius+2)))
        NSColor.labelColor.withAlphaComponent(0.9).setStroke(); tick.stroke()
    }
}

/// A native, non-modal theme editor. Every change previews and persists; dismissal commits nothing extra.
final class ThemeEditor: NSObject {
    private let parent: NSWindow
    private let panel: ThemePanel
    private let animationHost = NSView()
    private let surface = ThemeBackdropView()
    private let canvas = ThemeCanvas()
    private let wave = WaveSlider(), grain = GrainSlider()
    private let anchorOffset: NSPoint
    private var appearanceButtons: [ThemeButton] = []
    private var swatches: [ThemeSwatch] = []
    private let presetViewport = NSView()
    private var presetStrip = NSView()
    private var switchingPresets = false
    private var pendingPresetDirection: Int?
    private var dragTheme: SpaceTheme?
    private var appearing = false
    private var removeButton: ThemeButton!, addButton: ThemeButton!
    private var theme: SpaceTheme
    private var mode: ThemeAppearance
    private let language: String
    private let change: (SpaceTheme, ThemeAppearance) -> Void
    private let dismissed: () -> Void
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var closed = false
    private var presetPage = 0
    private let presetPages: [[ThemePreset]] = [
        ["#EFE7DE","#EB96BA","#B367A5","#EF5770","#FF8856","#F4D85B","#2AD99B","#65BBD9","#706B96"].map { ThemePreset(colors:[$0]) },
        [["#EFE7DE","#CFD9CD"],["#F2B49A","#E598C6"],["#927795","#BD8899"],
         ["#FFB15C","#E785B5"],["#F4DB50","#F39A70"],["#D5E85F","#8EC873"],
         ["#3FD7B3","#70C9DD"],["#8487E5","#69CBD2"],["#75678F","#AC839D"]].map { ThemePreset(colors:$0) }
    ]
    init(parent: NSWindow, anchor: NSPoint, theme: SpaceTheme, appearance: ThemeAppearance, language: String,
         change: @escaping (SpaceTheme, ThemeAppearance) -> Void, dismissed: @escaping () -> Void) {
        self.parent = parent; self.theme = theme.preparedForColorWheel(); mode = appearance; self.language = language; self.change = change; self.dismissed = dismissed
        anchorOffset = NSPoint(x:anchor.x-parent.frame.minX,y:anchor.y-parent.frame.minY)
        panel = ThemePanel(contentRect:NSRect(x:0,y:0,width:360,height:520),styleMask:[.borderless],backing:.buffered,defer:false)
        super.init()
        panel.title = t("themeEditor"); panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.isFloatingPanel = false; panel.hidesOnDeactivate = false
        surface.paintsTheme = false; surface.wantsLayer = true; surface.layer?.cornerRadius = 24; surface.layer?.masksToBounds = true
        surface.layer?.borderWidth = 1; surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        animationHost.frame = NSRect(x:0,y:0,width:360,height:520); animationHost.wantsLayer = true
        panel.contentView = animationHost
        surface.frame = animationHost.bounds; surface.autoresizingMask = [.width,.height]; animationHost.addSubview(surface)
        let glass = NSVisualEffectView(frame:surface.bounds); glass.autoresizingMask = [.width,.height]; glass.material = .popover; glass.blendingMode = .behindWindow; glass.state = .active; surface.addSubview(glass)
        canvas.frame = NSRect(x:9,y:9,width:342,height:338); surface.addSubview(canvas)
        canvas.setAccessibilityLabel(t("colorWheel")); canvas.toolTip = t("colorWheelHelp")
        canvas.began = { [weak self] in self?.dragTheme = self?.theme }
        canvas.changed = { [weak self] index, point in
            guard let self else { return }
            self.theme = (self.dragTheme ?? self.theme).movingColor(index,toX:point.x,y:point.y); self.publish()
        }
        for (i,item) in [("sparkles","appearanceAutomatic"),("sun.max.fill","appearanceLight"),("moon.stars.fill","appearanceDark")].enumerated() {
            let modes: [ThemeAppearance] = [.automatic,.light,.dark]
            let button = ThemeButton(item.0,label:t(item.1),frame:NSRect(x:122+CGFloat(i-1)*42,y:26,width:34,height:34)) { [weak self] in self?.mode = modes[i]; self?.publish() }
            surface.addSubview(button); appearanceButtons.append(button)
        }
        // Keep the three appearance buttons centered over the dotted field.
        for (i,button) in appearanceButtons.enumerated() { button.frame.origin.x = 121+CGFloat(i)*42 }
        removeButton = ThemeButton("minus",label:t("removeThemeColor"),frame:NSRect(x:139,y:305,width:30,height:30)) { [weak self] in
            guard let self, self.theme.points.count > 1 else { return }
            self.theme.points.remove(at:self.canvas.selected); self.canvas.selected = min(self.canvas.selected,self.theme.points.count-1); self.publish()
        }
        addButton = ThemeButton("plus",label:t("addThemeColor"),frame:NSRect(x:182,y:305,width:30,height:30)) { [weak self] in
            guard let self, self.theme.points.count < 3 else { return }
            self.theme.addHarmonyColor()
            self.canvas.selected = self.theme.points.count-1; self.theme.gradient = max(0.6,self.theme.gradient); self.publish()
        }
        surface.addSubview(removeButton); surface.addSubview(addButton)
        presetViewport.frame = NSRect(x:43,y:364,width:274,height:30)
        presetViewport.wantsLayer = true; presetViewport.layer?.masksToBounds = true; surface.addSubview(presetViewport)
        presetStrip = makePresetStrip(); presetViewport.addSubview(presetStrip)
        for (i,symbol) in ["chevron.left","chevron.right"].enumerated() {
            let b = ThemeButton(symbol,label:t(i == 0 ? "previousPresets" : "nextPresets"),frame:NSRect(x:i == 0 ? 13 : 324,y:364,width:24,height:30)) { [weak self] in
                self?.switchPresets(direction:i == 0 ? -1 : 1)
            }; surface.addSubview(b)
        }
        wave.cell = WaveCell(); wave.minValue = 0; wave.maxValue = 1; wave.isContinuous = true; wave.frame = NSRect(x:25,y:427,width:220,height:48); wave.target = self; wave.action = #selector(adjustGradient)
        wave.setAccessibilityLabel(t("gradient")); wave.toolTip = t("gradientHelp"); surface.addSubview(wave)
        grain.cell = GrainCell(); grain.sliderType = .circular; grain.minValue = 0; grain.maxValue = 1; grain.isContinuous = true; grain.frame = NSRect(x:262,y:416,width:76,height:76); grain.target = self; grain.action = #selector(adjustGrain)
        grain.setAccessibilityLabel(t("grain")); grain.toolTip = t("grainHelp"); surface.addSubview(grain)
        refresh()
    }
    private func t(_ key: String) -> String { L10n.text(key,language:language) }
    func show() {
        position()
        panel.alphaValue = 1; panel.hasShadow = reduceMotion
        if !reduceMotion, let layer = surface.layer {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.transform = genieTransform(x:0.08,y:0.12,shear:0.06); layer.opacity = 0
            CATransaction.commit()
        }
        parent.addChildWindow(panel,ordered:.above); panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(canvas); panel.displayIfNeeded()
        if !reduceMotion {
            appearing = true
            // Start after the menu has finished tracking and the child window has
            // committed its first frame. Animating NSWindow.alphaValue alone can
            // finish before the compositor ever displays the window.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.closed else { return }
                self.animateGenie(opening:true) { [weak self] in
                    guard let self, !self.closed else { return }
                    self.appearing = false; self.panel.hasShadow = true; self.position()
                }
            }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown]) { [weak self] event in
            guard let self, !self.closed else { return event }
            if event.type == .keyDown { if event.keyCode == 53 { self.close(); return nil }; return event }
            if event.window !== self.panel { self.close(); return nil }
            return event
        }
        for name in [NSWindow.didResizeNotification,NSWindow.didMoveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:parent,queue:.main) { [weak self] _ in self?.position() })
        }
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) { [weak self] _ in self?.close() })
    }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    func close(animated: Bool = true) {
        guard !closed else { return }; closed = true; canvas.endDrag()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        panel.ignoresMouseEvents = true
        // Notify synchronously: replacing an editor must never let an old animation
        // clear the controller's new editor reference or steal its focus.
        dismissed()
        let finish = { [self] in
            let wasKey = panel.isKeyWindow
            parent.removeChildWindow(panel); panel.orderOut(nil)
            if wasKey && NSApp.isActive { parent.makeKey() }
        }
        wave.stopAnimation()
        if animated && !reduceMotion && panel.isVisible {
            panel.hasShadow = false
            animateGenie(opening:false,completion:finish)
        } else {
            surface.layer?.removeAllAnimations(); finish()
        }
    }
    private func genieTransform(x: CGFloat, y: CGFloat, shear: CGFloat) -> CATransform3D {
        guard let layer = surface.layer else { return CATransform3DIdentity }
        // Pivot at the clicked side of the panel, a little below its upper edge.
        let anchor = NSPoint(x:parent.frame.minX+anchorOffset.x,y:parent.frame.minY+anchorOffset.y)
        let pivotX: CGFloat = anchor.x < panel.frame.midX ? 0 : surface.bounds.width
        let top = min(surface.bounds.height-18,max(18,panel.frame.maxY-anchor.y))
        let pivotY = layer.isGeometryFlipped ? top : surface.bounds.height-top
        let px = pivotX-layer.anchorPoint.x*surface.bounds.width
        let py = pivotY-layer.anchorPoint.y*surface.bounds.height
        var transform = CATransform3DIdentity
        transform.m11 = x; transform.m22 = y; transform.m21 = shear
        transform.m41 = px*(1-x)-py*shear; transform.m42 = py*(1-y)
        return transform
    }
    private func animateGenie(opening: Bool, completion: @escaping () -> Void) {
        guard let layer = surface.layer else { completion(); return }
        let current = layer.presentation()?.transform ?? layer.transform
        let opacity = layer.presentation()?.opacity ?? layer.opacity
        layer.removeAnimation(forKey:"themeGenie")
        let small = genieTransform(x:0.08,y:0.12,shear:0.06)
        let spread = genieTransform(x:0.77,y:0.62,shear:0.035)
        let final = opening ? CATransform3DIdentity : small
        let shape = CAKeyframeAnimation(keyPath:"transform")
        shape.values = (opening ? [current,spread,CATransform3DIdentity] : [current,spread,small]).map { NSValue(caTransform3D:$0) }
        shape.keyTimes = [0,0.48,1]
        shape.timingFunctions = [CAMediaTimingFunction(controlPoints:0.2,0.75,0.25,1),CAMediaTimingFunction(name:opening ? .easeOut : .easeIn)]
        let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = opacity; fade.toValue = opening ? 1 : 0
        let group = CAAnimationGroup(); group.animations = [shape,fade]; group.duration = opening ? 0.28 : 0.18
        shape.duration = group.duration; fade.duration = group.duration
        CATransaction.begin(); CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion)
        layer.transform = final; layer.opacity = opening ? 1 : 0
        layer.add(group,forKey:"themeGenie")
        CATransaction.commit()
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) }; observers.forEach(NotificationCenter.default.removeObserver) }
    private func position() {
        guard !closed, !appearing, parent.contentView != nil else { return }
        let anchor = NSPoint(x:parent.frame.minX+anchorOffset.x,y:parent.frame.minY+anchorOffset.y)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) }?.visibleFrame ?? parent.screen?.visibleFrame ?? parent.frame
        let right = anchor.x+12
        let proposedX = right+360 <= screen.maxX-8 ? right : anchor.x-372
        let x = max(screen.minX+8,min(screen.maxX-368,proposedX))
        let y = max(screen.minY+8,min(screen.maxY-528,anchor.y-520+18))
        panel.setFrame(NSRect(x:x,y:y,width:360,height:520),display:true)
    }

    private func publish() { change(theme,mode); refresh() }
    private func refresh() {
        panel.appearance = mode == .automatic ? nil : NSAppearance(named:mode == .dark ? .darkAqua : .aqua)
        canvas.points = theme.points
        removeButton.isEnabled = theme.points.count > 1; addButton.isEnabled = theme.points.count < 3
        for (i,button) in appearanceButtons.enumerated() {
            let active = [ThemeAppearance.automatic,.light,.dark][i] == mode
            button.state = active ? .on : .off; button.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(active ? 0.09 : 0).cgColor
        }
        for (i,button) in swatches.enumerated() {
            button.selected = presetPages[presetPage][i].colors == theme.points.map(\.color)
            button.needsDisplay = true
        }
        wave.showIntensity(theme.gradient,animated:panel.isVisible && !reduceMotion); grain.doubleValue = theme.grain; grain.needsDisplay = true
    }
    private func makePresetStrip() -> NSView {
        let strip = NSView(frame:NSRect(x:0,y:0,width:274,height:30)); strip.wantsLayer = true
        swatches = []
        for (i,preset) in presetPages[presetPage].enumerated() {
            let button = ThemeSwatch(frame:NSRect(x:CGFloat(i)*30,y:1,width:28,height:28))
            button.colors = preset.colors; button.isBordered = false; button.title = ""
            button.tag = i; button.target = self; button.action = #selector(selectPreset(_:))
            let name = t(preset.colors.count > 1 ? "gradientPreset" : "solidPreset") + " \(i+1)"
            button.setAccessibilityLabel(name); button.toolTip = name
            strip.addSubview(button); swatches.append(button)
        }
        return strip
    }
    private func switchPresets(direction: Int) {
        guard !closed else { return }
        if switchingPresets { pendingPresetDirection = direction; return }
        presetPage = (presetPage+direction+presetPages.count)%presetPages.count
        let old = presetStrip
        presetStrip = makePresetStrip(); let incoming = presetStrip
        presetViewport.addSubview(incoming); refresh()
        guard !reduceMotion else { old.removeFromSuperview(); return }
        switchingPresets = true
        old.subviews.compactMap { $0 as? NSButton }.forEach { $0.isEnabled = false }
        swatches.forEach { $0.isEnabled = false }
        incoming.frame.origin.x = CGFloat(direction)*274; incoming.alphaValue = 0.3
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.27; context.timingFunction = CAMediaTimingFunction(controlPoints:0.22,0.75,0.25,1)
            old.animator().setFrameOrigin(NSPoint(x:-CGFloat(direction)*274,y:0)); old.animator().alphaValue = 0.2
            incoming.animator().setFrameOrigin(.zero); incoming.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            old.removeFromSuperview()
            guard let self else { return }; self.switchingPresets = false; self.swatches.forEach { $0.isEnabled = true }
            if let next = self.pendingPresetDirection { self.pendingPresetDirection = nil; self.switchPresets(direction:next) }
        }
    }
    @objc private func selectPreset(_ sender: NSButton) {
        let preset = presetPages[presetPage][sender.tag]
        theme.points = preset.colors.map { SpaceTheme.wheelPoint(color:$0) }
        theme.pickerVersion = 1; theme.gradient = preset.colors.count > 1 ? 0.72 : 0
        canvas.selected = 0; publish()
    }
    @objc private func adjustGradient() { theme.gradient = wave.doubleValue; publish() }
    @objc private func adjustGrain() { theme.grain = grain.doubleValue; publish() }
}
