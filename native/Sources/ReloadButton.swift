import AppKit
import QuartzCore

final class ReloadButton: NSButton {
    private let glyph = CALayer()
    private var hovered = false
    private var loading = false
    private var wasEnabled = true
    private var pulsing = false
    private var ink = NSColor.labelColor
    private var tracking: NSTrackingArea?
    private var pulseCompletion: DispatchWorkItem?
    private var invoke: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        invoke = action
        super.init(frame: .zero)
        self.title = ""; isBordered = false; wantsLayer = true
        layer?.cornerRadius = 8
        glyph.contentsGravity = .resizeAspect
        layer?.addSublayer(glyph)
        target = self; self.action = #selector(activate)
        setAccessibilityLabel(title)
        updateGlyph()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func activate() { invoke() }
    override func draw(_ dirtyRect: NSRect) {} // Only the glyph rotates, never the hover surface.
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glyph.bounds = CGRect(x:0,y:0,width:18,height:18)
        glyph.position = CGPoint(x:bounds.midX,y:bounds.midY)
        CATransaction.commit()
    }
    func configure(loading: Bool, ink: NSColor, label: String) {
        let changed = self.loading != loading || self.ink != ink || wasEnabled != isEnabled
        wasEnabled = isEnabled
        self.loading = loading; self.ink = ink
        toolTip = label; setAccessibilityLabel(label)
        if changed { updateGlyph(); updateHover() }
    }
    private func updateGlyph() {
        let symbol = NSImage(systemSymbolName: loading && !pulsing ? "xmark" : "arrow.clockwise", accessibilityDescription:nil)
        let color = ink.withAlphaComponent(isEnabled ? 0.8 : 0.35)
        let image = NSImage(size:NSSize(width:36,height:36),flipped:false) { rect in
            symbol?.draw(in:rect)
            color.setFill(); rect.fill(using:.sourceAtop)
            return true
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glyph.contents = image.cgImage(forProposedRect:nil,context:nil,hints:nil)
        CATransaction.commit()
    }
    func animateReload() {
        pulseCompletion?.cancel()
        pulsing = true; updateGlyph()
        // Keep the reload glyph briefly at rest after its return. Fast loads
        // finish without flashing a stop icon, including with Reduce Motion.
        let completion = DispatchWorkItem { [weak self] in
            self?.pulsing = false; self?.updateGlyph(); self?.pulseCompletion = nil
        }
        pulseCompletion = completion
        DispatchQueue.main.asyncAfter(deadline:.now()+0.85,execute:completion)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            glyph.removeAnimation(forKey:"reload-turn"); return
        }
        let angle = (glyph.presentation()?.value(forKeyPath:"transform.rotation.z") as? NSNumber)?.doubleValue ?? 0
        let animation = CAKeyframeAnimation(keyPath:"transform.rotation.z")
        animation.values = [angle, Double.pi/2, 0]
        animation.keyTimes = [0, 0.4, 1]
        animation.timingFunctions = [CAMediaTimingFunction(controlPoints:0.2,0.7,0.3,1), CAMediaTimingFunction(controlPoints:0.25,0,0.2,1)]
        animation.duration = 0.36
        glyph.add(animation,forKey:"reload-turn")
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { trackPointer(event) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    func trackPointer(_ event: NSEvent) {
        setHovered(event.window === window && event.type != .mouseExited && containsExposedPointer(at:event.locationInWindow))
    }
    private func setHovered(_ value: Bool) {
        guard hovered != value else { return }; hovered = value; updateHover()
    }
    private func updateHover() {
        let color = ink.withAlphaComponent(hovered && isEnabled ? 0.09 : 0).cgColor
        let previous = layer?.presentation()?.backgroundColor ?? layer?.backgroundColor
        CATransaction.begin(); CATransaction.setDisableActions(true); layer?.backgroundColor = color; CATransaction.commit()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath:"backgroundColor")
            animation.fromValue = previous; animation.toValue = color; animation.duration = 0.12
            layer?.add(animation,forKey:"reload-hover")
        }
    }
}
