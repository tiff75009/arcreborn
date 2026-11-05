// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

/// Real buttons retain their keyboard actions, menus and accessibility. Only the
/// artwork moves; the next click uses the same slot that accepted the hover.
private final class SpaceDockSlot: ActionButton {
    let id: String
    var glyph: NSImage?
    var icon: String?
    var x = SpaceDockSpring(0), emphasis = SpaceDockSpring(0), lift = SpaceDockSpring(0)
    init(id: String, select: @escaping () -> Void) {
        self.id = id; super.init("",action:select); focusRingType = .exterior
    }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ dirtyRect:NSRect) {}
}

final class SpaceDockView: NSView {
    struct Item {
        let id: String, name: String, icon: String
        var enabled = true
    }
    private var slots: [SpaceDockSlot] = []
    private var selected = 0, hovered: Int?
    private var ink = NSColor.white
    private var viewportWidth: CGFloat = 0
    private var metrics: SpaceIndicatorLayout { .init(count:slots.count,available:viewportWidth,activeIndex:hovered ?? selected) }
    private var tracking: NSTrackingArea?
    var receivesWindowEvents = false
    private var stopDisplayLink: (() -> Void)?
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    override var isFlipped: Bool { true }

    func update(_ items: [Item], selectedID: String, ink: NSColor, select: @escaping (String)->Void,
                menu: ((Int)->NSMenu?)? = nil) {
        let rebuild = slots.map(\.id) != items.map(\.id)
        let oldSelection = selected, recolor = self.ink != ink
        if rebuild {
            let hoveredID = hovered.map { slots[$0].id }
            slots.forEach { $0.removeFromSuperview() }
            slots = items.map { item in
                let button = SpaceDockSlot(id:item.id) { select(item.id) }
                addSubview(button); return button
            }
            hovered = items.firstIndex { $0.id == hoveredID && $0.enabled }
        }
        selected = items.firstIndex { $0.id == selectedID } ?? 0
        self.ink = ink
        for (i,item) in items.enumerated() {
            let slot = slots[i]
            slot.isEnabled = item.enabled; slot.setAccessibilityLabel(item.name)
            slot.setAccessibilitySelected(i == selected); slot.toolTip = receivesWindowEvents ? nil : item.name; slot.menu = menu?(i)
            if slot.icon != item.icon || recolor {
                slot.icon = item.icon
                if item.icon.isEmpty || item.icon == "none" { slot.glyph = nil }
                else {
                    slot.glyph = NSImage(size:NSSize(width:20,height:20),flipped:false) { rect in
                        SpaceIcon.draw(item.icon,in:rect.insetBy(dx:3,dy:3),color:ink,size:13); return true
                    }
                }
            }
        }
        if rebuild || oldSelection != selected {
            arrange(animate:!rebuild)
            revealSelection()
        }
        needsDisplay = true
    }

    func fit(width: CGFloat) {
        guard width != viewportWidth else { return }
        viewportWidth = width; arrange(animate:false); revealSelection()
    }
    private func revealSelection() {
        if slots.indices.contains(selected) { scrollToVisible(slots[selected].frame) }
    }
    private func arrange(animate: Bool) {
        let layout = metrics
        setFrameSize(NSSize(width:max(viewportWidth,layout.width),height:32))
        for (i,slot) in slots.enumerated() {
            let r = layout.frame(i); slot.frame = NSRect(x:r.x,y:0,width:r.width,height:32)
        }
        if animate && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { startClock() }
        else { step(dt:nil); stopClock() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        guard !receivesWindowEvents else { tracking = nil; return }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.mouseMoved,.activeInKeyWindow,.inVisibleRect],owner:self)
        addTrackingArea(tracking!)
    }
    func slot(at location:NSPoint) -> (id:String,view:NSView)? {
        let point = convert(location,from:nil)
        guard visibleRect.contains(point), let i = metrics.index(at:point.x), slots[i].isEnabled else { return nil }
        return (slots[i].id,slots[i])
    }
    func trackPointer(_ event: NSEvent) {
        guard let window, event.window === window, window.isKeyWindow, event.type != .mouseExited,
              !isHiddenOrHasHiddenAncestor else { clearHover(); return }
        let p = convert(event.locationInWindow,from:nil)
        let index = visibleRect.contains(p) ? metrics.index(at:p.x) : nil
        setHover(index.flatMap { slots[$0].isEnabled ? $0 : nil })
    }
    override func mouseMoved(with event: NSEvent) { trackPointer(event) }
    override func mouseEntered(with event: NSEvent) { trackPointer(event) }
    override func mouseExited(with event: NSEvent) { clearHover() }
    func clearHover() { setHover(nil) }
    private func setHover(_ index: Int?) {
        guard index != hovered else { return }
        // Integrate up to the event, including visits shorter than one display frame.
        if lastTick != 0 { tick() }
        hovered = index; arrange(animate:true)
    }
    private func startClock() {
        guard lastTick == 0 else { return }
        lastTick = CACurrentMediaTime()
        if #available(macOS 14.0, *) {
            let link = displayLink(target:self,selector:#selector(displayFrame(_:)))
            link.add(to:.main,forMode:.common); stopDisplayLink = { link.invalidate() }
        } else {
            let t = Timer(timeInterval:1/60.0,repeats:true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t,forMode:.common); timer = t
        }
    }
    private func stopClock() {
        stopDisplayLink?(); stopDisplayLink = nil; timer?.invalidate(); timer = nil; lastTick = 0
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { hovered = nil; arrange(animate:false) }
    }
    @objc private func displayFrame(_ link: Any) { tick() }
    private func tick() {
        let now = CACurrentMediaTime(), dt = max(0,now-lastTick)
        lastTick = now
        if !step(dt:NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : dt) { stopClock() }
    }
    @discardableResult private func step(dt: Double?) -> Bool {
        let focus = hovered ?? selected
        var moving = false
        for (i,slot) in slots.enumerated() {
            let x = slot.frame.midX, e = Double(i == focus ? 1 : 0), h = Double(i == hovered ? 1 : 0)
            if let dt {
                slot.x.advance(to:x,dt:dt); slot.emphasis.advance(to:e,dt:dt); slot.lift.advance(to:h,dt:dt)
                if !slot.x.isAt(x) || !slot.emphasis.isAt(e) || !slot.lift.isAt(h) { moving = true }
            } else { slot.x = .init(x); slot.emphasis = .init(e); slot.lift = .init(h) }
        }
        setNeedsDisplay(visibleRect)
        return moving
    }

    override func draw(_ dirtyRect: NSRect) {
        for slot in slots where slot.x.value >= dirtyRect.minX-12 && slot.x.value <= dirtyRect.maxX+12 {
            let x = slot.x.value, y = bounds.midY, e = max(0,min(1,slot.emphasis.value))
            let glyphAlpha = slot.glyph == nil ? 0 : e*e*(3-2*e)
            let diameter = 4+4*e
            ink.withAlphaComponent((0.18+0.36*e)*(1-glyphAlpha)).setFill()
            NSBezierPath(ovalIn:NSRect(x:x-diameter/2,y:y-diameter/2,width:diameter,height:diameter)).fill()
            if let glyph = slot.glyph, glyphAlpha > 0.001 {
                let side = 20*(0.58+0.42*e+0.08*slot.lift.value)
                glyph.draw(in:NSRect(x:x-side/2,y:y-side/2,width:side,height:side),from:.zero,operation:.sourceOver,
                           fraction:0.94*glyphAlpha,respectFlipped:true,hints:nil)
            }
        }
    }
}
