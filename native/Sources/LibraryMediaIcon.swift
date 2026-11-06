// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

/// Two vector cards, so the rear and front can anticipate and jump independently.
final class LibraryMediaIcon: CALayer {
    private let rear = CALayer(), front = CALayer()
    private let rearFace = CAShapeLayer(), frontFace = CAShapeLayer()
    private(set) var selected = false

    override init() {
        super.init()
        bounds = CGRect(x:0,y:0,width:26,height:26)
        isHidden = true
        for moving in [rear,front] { moving.frame = bounds; addSublayer(moving) }
        makeCard(in:rear,face:rearFace,origin:CGPoint(x:1.8,y:4.0),angle:-0.14,photo:false)
        makeCard(in:front,face:frontFace,origin:CGPoint(x:6.1,y:8.5),angle:0,photo:true)
    }
    override init(layer:Any) { super.init(layer:layer) }
    required init?(coder:NSCoder) { fatalError() }

    private func makeCard(in moving:CALayer,face:CAShapeLayer,origin:CGPoint,angle:CGFloat,photo:Bool) {
        let card = CALayer(); card.frame = CGRect(origin:origin,size:CGSize(width:19.5,height:16))
        card.transform = CATransform3DMakeRotation(angle,0,0,1); moving.addSublayer(card)
        let outline = CGPath(roundedRect:CGRect(x:0.9,y:0.9,width:17.7,height:14.2),cornerWidth:1.6,cornerHeight:1.6,transform:nil)
        face.path = outline; face.frame = card.bounds; card.addSublayer(face)
        if photo {
            let artwork = CALayer(); artwork.frame = card.bounds
            let mask = CAShapeLayer(); mask.path = outline; artwork.mask = mask; card.addSublayer(artwork)
            let mountain = CAShapeLayer(); let path = CGMutablePath()
            path.move(to:CGPoint(x:0,y:12.8)); path.addLine(to:CGPoint(x:5.0,y:8.7))
            path.addQuadCurve(to:CGPoint(x:6.2,y:8.7),control:CGPoint(x:5.6,y:8.1))
            path.addLine(to:CGPoint(x:9.0,y:11.1)); path.addLine(to:CGPoint(x:12.8,y:7.4))
            path.addQuadCurve(to:CGPoint(x:14.1,y:7.4),control:CGPoint(x:13.45,y:6.8))
            path.addLine(to:CGPoint(x:20,y:12.9)); path.addLine(to:CGPoint(x:20,y:17))
            path.addLine(to:CGPoint(x:0,y:17)); path.closeSubpath()
            mountain.path = path; mountain.fillColor = NSColor.white.withAlphaComponent(0.96).cgColor
            let sun = CAShapeLayer(); sun.path = CGPath(ellipseIn:CGRect(x:4.3,y:4.1,width:3.3,height:3.3),transform:nil)
            sun.fillColor = mountain.fillColor; artwork.addSublayer(mountain); artwork.addSublayer(sun)
        }
        let rim = CAShapeLayer(); rim.path = outline; rim.fillColor = nil
        rim.strokeColor = NSColor.white.withAlphaComponent(0.96).cgColor; rim.lineWidth = 1.65
        card.addSublayer(rim)
    }

    /// Preserve the space hue while giving the small colored faces a clear, vivid accent.
    static func vividColor(_ source:NSColor) -> NSColor {
        let color = source.usingColorSpace(.sRGB) ?? .systemBlue
        var h:CGFloat = 0, s:CGFloat = 0
        color.getHue(&h,saturation:&s,brightness:nil,alpha:nil)
        // Gray has no meaningful hue; don't accidentally turn neutral spaces red.
        guard s > 0.06 else { return NSColor(srgbRed:0.6,green:0.6,blue:0.6,alpha:1) }
        // Convert in sRGB directly: calibrated HSB can shift the source hue on wide-gamut displays.
        let chroma = max(0.86,min(0.98,s*1.4)), sector = h*6
        let second = chroma*(1-abs(sector.truncatingRemainder(dividingBy:2)-1)), floor = 1-chroma
        let rgb:(CGFloat,CGFloat,CGFloat)
        switch Int(sector)%6 {
        case 0: rgb = (chroma,second,0)
        case 1: rgb = (second,chroma,0)
        case 2: rgb = (0,chroma,second)
        case 3: rgb = (0,second,chroma)
        case 4: rgb = (second,0,chroma)
        default: rgb = (chroma,0,second)
        }
        return NSColor(srgbRed:rgb.0+floor,green:rgb.1+floor,blue:rgb.2+floor,alpha:1)
    }

    func setSelected(_ value:Bool, accent:NSColor, animated:Bool = true) {
        let changed = selected != value
        selected = value
        let color = Self.vividColor(accent).cgColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        rearFace.fillColor = color; frontFace.fillColor = color; isHidden = !value
        CATransaction.commit()
        // Repainting the theme, refreshing the library, or clicking the active section
        // must not restart the movement. There are no delayed callbacks to leak on exit.
        guard changed else { return }
        if value && animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            jump(rear,delay:0,height:2.6,lean:-0.18)
            jump(front,delay:0.065,height:3.2,lean:0.14)
        } else {
            for card in [rear,front] { card.removeAnimation(forKey:"media-jump") }
        }
    }

    private func jump(_ card:CALayer,delay:Double,height:CGFloat,lean:CGFloat) {
        let current = card.presentation() ?? card
        let lift = CAKeyframeAnimation(keyPath:"transform.translation.y")
        lift.values = [current.transform.m42,0.95,-height*0.78,-height,-height*0.36,0.32,0]
        lift.keyTimes = [0,0.15,0.30,0.43,0.60,0.78,1]
        // Rotation leads the rise and lingers at the apex: the cards tip and float,
        // instead of travelling upright along the same rigid bounce curve.
        let tilt = CAKeyframeAnimation(keyPath:"transform.rotation.z")
        tilt.values = [atan2(current.transform.m12,current.transform.m11),-lean*0.32,lean*0.90,lean,-lean*0.25,lean*0.07,0]
        tilt.keyTimes = [0,0.12,0.28,0.50,0.73,0.86,1]
        for motion in [lift,tilt] {
            motion.calculationMode = .cubic
            motion.tensionValues = [0.8,0.25,0.15,0.3,0.25,0.5,1]
            motion.duration = 0.62
        }
        let movement = CAAnimationGroup(); movement.animations = [lift,tilt]
        movement.beginTime = card.convertTime(CACurrentMediaTime(),from:nil)+delay
        movement.duration = 0.62; movement.fillMode = .backwards
        card.add(movement,forKey:"media-jump")
    }
}
