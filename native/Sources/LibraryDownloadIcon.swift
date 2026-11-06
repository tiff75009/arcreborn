// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

/// The ring, arrow and shaft retain their own geometry throughout the small spring.
final class LibraryDownloadIcon: CALayer {
    private let ring = CAShapeLayer(), arrow = CALayer()
    private let shaft = CAShapeLayer(), point = CAShapeLayer()
    private(set) var selected = false

    override init() {
        super.init()
        bounds = CGRect(x:0,y:0,width:26,height:26)
        ring.frame = bounds
        ring.path = CGPath(ellipseIn:CGRect(x:3.8,y:3.8,width:18.4,height:18.4),transform:nil)
        ring.lineWidth = 1.65; ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = NSColor.white.withAlphaComponent(0.72).cgColor
        addSublayer(ring)
        arrow.frame = bounds; addSublayer(arrow)
        for part in [shaft,point] {
            part.frame = bounds; part.lineWidth = 1.55; part.lineCap = .round; part.lineJoin = .round
            part.fillColor = nil; part.strokeColor = ring.strokeColor; arrow.addSublayer(part)
        }
        let stem = CGMutablePath(); stem.move(to:CGPoint(x:13,y:7.8)); stem.addLine(to:CGPoint(x:13,y:18.2)); shaft.path = stem
        let tip = CGMutablePath(); tip.move(to:CGPoint(x:9.5,y:14.7)); tip.addLine(to:CGPoint(x:13,y:18.2)); tip.addLine(to:CGPoint(x:16.5,y:14.7)); point.path = tip
    }
    override init(layer:Any) { super.init(layer:layer) }
    required init?(coder:NSCoder) { fatalError() }

    func setSelected(_ value:Bool, accent:NSColor, ink:NSColor = .white, animated:Bool = true) {
        let changed = selected != value; selected = value
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ring.fillColor = value ? LibraryMediaIcon.vividColor(accent).cgColor : NSColor.clear.cgColor
        ring.strokeColor = ink.cgColor; shaft.strokeColor = ink.cgColor; point.strokeColor = ink.cgColor
        CATransaction.commit()
        // Hover, theme updates and clicks on the current section leave the animation alone.
        guard changed else { return }
        if value && animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animateSelection()
        } else {
            ring.removeAnimation(forKey:"download-ring")
            arrow.removeAnimation(forKey:"download-arrow")
            shaft.removeAnimation(forKey:"download-shaft")
        }
    }

    private func animateSelection() {
        let time = CACurrentMediaTime()
        func motion(_ key:String,values:[CGFloat],times:[NSNumber],duration:Double) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath:key)
            animation.values = values; animation.keyTimes = times
            animation.calculationMode = .cubic
            animation.tensionValues = [0.8,0.35,0.3,0.4,0.6,1]
            animation.duration = duration
            return animation
        }
        // The arrow crouches inside the circle, then springs upwards. Only the
        // stem shortens: the arrowhead and stroke weight remain unchanged.
        let press = motion("transform.translation.y",values:[0,1.15,-2.65,-0.48,0.22,0],times:[0,0.15,0.38,0.62,0.80,1],duration:0.60)
        press.beginTime = arrow.convertTime(time,from:nil); arrow.add(press,forKey:"download-arrow")
        let shorten = motion("strokeStart",values:[0,0.32,0.055,0,0.025,0],times:[0,0.15,0.34,0.57,0.80,1],duration:0.60)
        shorten.beginTime = shaft.convertTime(time,from:nil); shaft.add(shorten,forKey:"download-shaft")
        // A separate anticipation, jump and landing: not a subpixel echo of the
        // arrow. The circle reaches its apex later and settles more slowly.
        let response = motion("transform.translation.y",values:[0,0.70,-2.20,-0.45,0.26,0],times:[0,0.18,0.43,0.62,0.80,1],duration:0.70)
        response.beginTime = ring.convertTime(time+0.04,from:nil)
        response.fillMode = .backwards
        ring.add(response,forKey:"download-ring")
    }
}
