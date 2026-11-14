import AppKit
import QuartzCore

/// History controls share the reload button's hover surface, without activating
/// that surface when Chromium has no previous/next page.
class NavigationButton: ActionButton {
    var restingFillOpacity: CGFloat = 0 { didSet { updateHover(animated:false) } }
    var menuOpen = false { didSet { updateHover() } }
    var ink = NSColor.labelColor { didSet { if oldValue != ink { updateHover() } } }
    override var isEnabled: Bool { didSet { updateHover(animated:isEnabled) } }
    private var hovered = false
    private var tracking: NSTrackingArea?

    override init(_ title: String = "", symbol: String? = nil, action: @escaping () -> Void) {
        super.init(title,symbol:symbol,action:action)
        self.title = ""; imagePosition = .imageOnly
        wantsLayer = true; layer?.cornerRadius = 8
    }
    required init?(coder:NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self)
        addTrackingArea(tracking!)
        setHovered(containsCurrentPointer)
    }
    override func mouseEntered(with event:NSEvent) { trackPointer(event) }
    override func mouseExited(with event:NSEvent) { setHovered(false) }
    func trackPointer(_ event:NSEvent) {
        setHovered(event.window === window && event.type != .mouseExited && containsExposedPointer(at:event.locationInWindow))
    }
    private func setHovered(_ value:Bool) {
        guard hovered != value else { return }
        hovered = value; updateHover()
    }
    private func updateHover(animated:Bool = true) {
        let color = ink.withAlphaComponent((hovered || menuOpen) && isEnabled ? max(0.09, restingFillOpacity+0.07) : restingFillOpacity).cgColor
        let previous = layer?.presentation()?.backgroundColor ?? layer?.backgroundColor
        layer?.removeAnimation(forKey:"navigation-hover")
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.backgroundColor = color
        CATransaction.commit()
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let animation = CABasicAnimation(keyPath:"backgroundColor")
        animation.fromValue = previous; animation.toValue = color; animation.duration = 0.12
        layer?.add(animation,forKey:"navigation-hover")
    }
}
