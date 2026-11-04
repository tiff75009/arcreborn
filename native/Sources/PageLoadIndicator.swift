// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

/// The address surface fills underneath its controls; the hidden chrome uses a slim rail instead.
final class PageLoadIndicator: NSView {
    enum Style { case field, rail }
    private let fill = CALayer()
    private let lip = CAGradientLayer()
    private let clip = CAShapeLayer()
    private var style: Style = .field
    private var radius: CGFloat = 0
    private var tab: String?
    private var loading = false
    private var fraction: CGFloat = 0
    private var epoch = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("PageLoadProgress")
        isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityMinValue(0)
        setAccessibilityMaxValue(100)
        wantsLayer = true
        layer?.mask = clip
        fill.anchorPoint = .zero
        layer?.addSublayer(fill)
        lip.anchorPoint = .zero
        lip.startPoint = CGPoint(x:0,y:0.5); lip.endPoint = CGPoint(x:1,y:0.5)
        layer?.addSublayer(lip)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    private var motion: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func follow(_ rect: CGRect, radius outerRadius: CGFloat, style nextStyle: Style) {
        let r = max(0, min(outerRadius, min(rect.width, rect.height) / 2))
        // Hosts have flipped coordinates. Only the top two points overlay page content.
        let next = nextStyle == .field ? rect : CGRect(x:rect.minX, y:rect.minY, width:rect.width, height:min(rect.height, 2))
        guard frame != next || radius != r || style != nextStyle else { return }
        style = nextStyle; radius = r; frame = next
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let maskHeight = max(bounds.height, r * 2)
        let shape = CGRect(x:0, y:bounds.maxY-maskHeight, width:bounds.width, height:maskHeight)
        clip.frame = bounds
        clip.path = CGPath(roundedRect:shape, cornerWidth:r, cornerHeight:r, transform:nil)
        // Only the leading few points soften. The whole travelled surface stays opaque.
        lip.bounds = CGRect(x:0, y:0, width:style == .field ? min(16, bounds.width*0.04) : 3, height:bounds.height)
        CATransaction.commit()
        setWidth(animated:false)
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 1
        clip.contentsScale = scale; fill.contentsScale = scale
    }

    func display(tab id: String?, loading busy: Bool, progress: Double, base: NSColor, accent: NSColor, ink: NSColor, label: String) {
        if accessibilityLabel() != label { setAccessibilityLabel(label) }
        let tint = base.usingColorSpace(.sRGB) ?? base
        let foreground = ink.usingColorSpace(.sRGB) ?? ink
        let lightText = foreground.brightnessComponent > 0.65
        let pale = tint.brightnessComponent > 0.82
        let space = accent.usingColorSpace(.sRGB) ?? tint
        let color: NSColor
        if style == .rail {
            color = space.blended(withFraction:0.33, of:foreground) ?? foreground
        } else {
            // A solid swatch drawn behind the glyphs; choose its value to keep the URL legible.
            if lightText {
                let vivid = tint.blended(withFraction:0.54, of:space) ?? tint
                // Neutral and very dark spaces still need a perceptible fill.
                let lifted = (vivid.blended(withFraction:vivid.brightnessComponent < 0.24 ? 0.20 : 0.05, of:.white) ?? vivid).usingColorSpace(.sRGB) ?? tint
                let lightness = 0.2126*lifted.redComponent + 0.7152*lifted.greenComponent + 0.0722*lifted.blueComponent
                let factor = min(1, 0.43 / max(0.01, lightness))
                color = NSColor(srgbRed:lifted.redComponent*factor, green:lifted.greenComponent*factor, blue:lifted.blueComponent*factor, alpha:1)
            } else {
                color = tint.blended(withFraction:pale ? 0.14 : 0.34, of:pale ? foreground : .white) ?? tint
            }
        }
        let fillColor = color.withAlphaComponent(1).cgColor
        if fill.backgroundColor != fillColor {
            CATransaction.begin(); CATransaction.setDisableActions(true); fill.backgroundColor = fillColor
            lip.colors = [fillColor, color.withAlphaComponent(0).cgColor]; CATransaction.commit()
        }
        if tab != id {
            epoch += 1; loading = false; fraction = 0; tab = id
            layer?.removeAnimation(forKey:"finish"); fill.removeAllAnimations(); isHidden = true
        }
        if busy, id != nil {
            let next = CGFloat(max(0.025, min(0.99, progress)))
            if !loading {
                epoch += 1; let current = epoch
                loading = true; fraction = next; isHidden = true
                layer?.removeAnimation(forKey:"finish")
                setAccessibilityValue(Int((next*100).rounded())); setWidth(animated:false)
                DispatchQueue.main.asyncAfter(deadline:.now()+0.12) { [weak self] in
                    guard let self, self.epoch == current, self.loading else { return }
                    self.isHidden = false
                }
            } else if next > fraction {
                fraction = next; setAccessibilityValue(Int((next*100).rounded())); setWidth(animated:!isHidden)
            }
        } else if loading {
            loading = false; epoch += 1; let current = epoch
            fraction = 1; setAccessibilityValue(100)
            guard !isHidden, motion else { isHidden = true; return }
            setWidth(animated:true)
            let fade = CABasicAnimation(keyPath:"opacity")
            fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.18
            fade.beginTime = CACurrentMediaTime()+0.14
            fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
            layer?.add(fade, forKey:"finish")
            DispatchQueue.main.asyncAfter(deadline:.now()+0.32) { [weak self] in
                guard let self, self.epoch == current else { return }
                self.isHidden = true; self.layer?.removeAnimation(forKey:"finish")
            }
        }
    }

    private func setWidth(animated: Bool) {
        let width = bounds.width*fraction
        let from = fill.presentation()?.bounds.width ?? fill.bounds.width
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fill.bounds = CGRect(x:0,y:0,width:width,height:bounds.height)
        lip.position = CGPoint(x:width,y:0)
        CATransaction.commit()
        if animated, motion, abs(width-from) > 0.5 {
            let grow = CABasicAnimation(keyPath:"bounds.size.width")
            grow.fromValue = from; grow.toValue = width; grow.duration = 0.16
            grow.timingFunction = CAMediaTimingFunction(name:.easeOut)
            fill.add(grow, forKey:"advance")
            let edge = grow.copy() as! CABasicAnimation
            edge.keyPath = "position.x"; lip.add(edge, forKey:"advance")
        } else { fill.removeAnimation(forKey:"advance"); lip.removeAnimation(forKey:"advance") }
    }
}
