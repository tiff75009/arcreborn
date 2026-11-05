// SPDX-License-Identifier: MPL-2.0
import AppKit

enum TabSoundState { case silent, playing, muted }

/// One clock drives the glyph and the title next to it, including mid-gesture reversals.
final class TabSoundButton: NSButton {
    private struct Motion {
        var from: CGFloat = 0
        var to: CGFloat = 0
        var start: TimeInterval = 0
        var duration: TimeInterval = 0
        func value(at time: TimeInterval) -> CGFloat {
            guard duration > 0 else { return to }
            let t = min(1, max(0, (time-start)/duration))
            return from + (to-from) * CGFloat(1-pow(1-t, 2.2))
        }
        mutating func move(to target: CGFloat, at time: TimeInterval, duration: TimeInterval) {
            if duration > 0 && to == target { return }
            from = duration > 0 ? value(at:time) : target
            to = target; start = time; self.duration = duration
        }
    }

    private var presence = Motion(), fold = Motion(), hover = Motion()
    private var timer: Timer?
    private(set) var representedID: String?
    private(set) var hovered = false
    var hoverChanged: ((Bool) -> Void)?
    private(set) var playback: TabSoundState = .silent
    private(set) var reveal: CGFloat = 0
    private var mute: CGFloat = 0
    private var ink = NSColor.labelColor
    var toggle: (() -> Void)?
    var titleInset: CGFloat { reveal * (25 - 4*mute) }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { playback == .silent ? nil : super.hitTest(point) }

    init() {
        super.init(frame:.zero)
        title = ""; isBordered = false; focusRingType = .default
        target = self; action = #selector(pressed); isHidden = true
        setAccessibilityRole(.button); setAccessibilityElement(false)
    }
    required init?(coder:NSCoder) { fatalError() }
    deinit { timer?.invalidate() }
    @objc private func pressed() { if playback != .silent { toggle?() } }

    func setHovered(_ inside:Bool) {
        let active = inside && playback != .silent
        guard active != hovered else { return }
        hovered = active; hoverChanged?(active)
        let animate = window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        hover.move(to:active ? 1 : 0, at:ProcessInfo.processInfo.systemUptime, duration:animate ? 0.12 : 0)
        updateMotion()
    }

    func configure(id:String?, sound next:TabSoundState, ink:NSColor, language:String) {
        self.ink = ink
        let label = next == .muted
            ? (language == "fr" ? "Réactiver le son de cet onglet" : "Unmute this tab")
            : (language == "fr" ? "Couper le son de cet onglet" : "Mute this tab")
        setAccessibilityLabel(label)
        needsDisplay = true
        guard representedID != id || playback != next else { return }
        let animate = representedID != nil && representedID == id && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let now = ProcessInfo.processInfo.systemUptime
        // A newly appearing muted tab starts in its muted pose. A disappearing
        // button keeps its last pose while the title comes back.
        let firstPose = playback == .silent || !animate
        let folded: CGFloat = next == .silent ? fold.to : (next == .muted ? 1 : 0)
        if representedID != id || next == .silent { setHovered(false) }
        representedID = id; playback = next
        setAccessibilityElement(next != .silent)
        presence.move(to: next == .silent ? 0 : 1, at:now, duration:animate ? 0.24 : 0)
        fold.move(to:folded, at:now, duration:animate && !firstPose ? 0.34 : 0)
        updateMotion()
    }
    private var motionEnd: TimeInterval { max(presence.start+presence.duration, fold.start+fold.duration, hover.start+hover.duration) }
    private func updateMotion() {
        tick()
        if timer == nil && ProcessInfo.processInfo.systemUptime < motionEnd {
            let t = Timer(timeInterval:1/Double(max(60, window?.screen?.maximumFramesPerSecond ?? 60)),repeats:true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode:.common); timer = t
        }
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let previousInset = titleInset
        reveal = presence.value(at:now); mute = fold.value(at:now)
        isHidden = reveal <= 0 && playback == .silent
        if previousInset != titleInset { superview?.needsLayout = true }
        needsDisplay = true
        if now >= motionEnd {
            timer?.invalidate(); timer = nil
        }
    }

    private func ramp(_ value: CGFloat) -> CGFloat { min(1,max(0,value)) }
    override func draw(_ dirtyRect:NSRect) {
        guard reveal > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState(); defer { ctx.restoreGState() }
        let highlight = hover.value(at:ProcessInfo.processInfo.systemUptime)
        if highlight > 0 {
            ink.withAlphaComponent(reveal * highlight * (isHighlighted ? 0.16 : 0.095)).setFill()
            NSBezierPath(roundedRect:bounds,xRadius:5.5,yRadius:5.5).fill()
        }
        let side = min(19, min(bounds.width,bounds.height))
        let scale = side / 24 * (0.74+0.26*reveal) * (1-0.07*mute)
        ctx.translateBy(x:bounds.midX, y:bounds.midY)
        ctx.scaleBy(x:scale, y:scale)
        ctx.translateBy(x:-12+1.6*mute, y:-12)
        ctx.setAlpha(reveal * (isHighlighted ? 0.60 : 0.75))
        ctx.beginTransparencyLayer(auxiliaryInfo:nil)
        ctx.setStrokeColor(ink.cgColor); ctx.setLineWidth(1.65)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.move(to:CGPoint(x:2.0,y:9.2)); ctx.addLine(to:CGPoint(x:5.2,y:9.2))
        ctx.addLine(to:CGPoint(x:9.9,y:5)); ctx.addQuadCurve(to:CGPoint(x:10.6,y:5.4), control:CGPoint(x:10.6,y:4.6))
        ctx.addLine(to:CGPoint(x:10.6,y:18.6)); ctx.addQuadCurve(to:CGPoint(x:9.9,y:19), control:CGPoint(x:10.6,y:19.4))
        ctx.addLine(to:CGPoint(x:5.2,y:14.8)); ctx.addLine(to:CGPoint(x:2.0,y:14.8)); ctx.closePath(); ctx.strokePath()
        for i in 0..<4 {
            let visible = 1-ramp((mute-CGFloat(3-i)*0.13)/0.40)
            guard visible > 0 else { continue }
            let index = CGFloat(i)
            let x = 12.4+2.30*index
            let h = (1.45+1.86*index)*visible
            ctx.saveGState(); ctx.setAlpha(visible); ctx.setLineWidth(1.4)
            ctx.move(to:CGPoint(x:x, y:12-h))
            ctx.addQuadCurve(to:CGPoint(x:x, y:12+h),control:CGPoint(x:x+h*0.91,y:12))
            ctx.strokePath(); ctx.restoreGState()
        }
        let slash = ramp((mute-0.44)/0.56)
        if slash > 0 {
            let end = CGPoint(x:2.2+16.2*slash,y:3.9+16.2*slash)
            ctx.setBlendMode(.clear); ctx.setLineWidth(4.4)
            ctx.move(to:CGPoint(x:2.2,y:3.9)); ctx.addLine(to:end); ctx.strokePath()
            ctx.setBlendMode(.normal); ctx.setLineWidth(1.75)
            ctx.move(to:CGPoint(x:2.2,y:3.9)); ctx.addLine(to:end); ctx.strokePath()
        }
        ctx.endTransparencyLayer()
    }
}
