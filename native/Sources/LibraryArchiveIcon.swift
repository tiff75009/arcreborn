// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

/// The box, label and lid each have their own anticipation and settling motion.
/// Resting geometry stays fixed, so interrupted selections cannot leave it askew.
final class LibraryArchiveIcon: CALayer {
    private let box = CAShapeLayer(), label = CAShapeLayer(), lid = CAShapeLayer()
    private(set) var selected = false

    override init() {
        super.init()
        bounds = CGRect(x:0,y:0,width:26,height:26)
        let body = CGMutablePath()
        body.move(to:CGPoint(x:5.2,y:9.5)); body.addLine(to:CGPoint(x:5.2,y:20.9))
        body.addQuadCurve(to:CGPoint(x:6.7,y:22.4),control:CGPoint(x:5.2,y:22.4))
        body.addLine(to:CGPoint(x:19.3,y:22.4))
        body.addQuadCurve(to:CGPoint(x:20.8,y:20.9),control:CGPoint(x:20.8,y:22.4))
        body.addLine(to:CGPoint(x:20.8,y:9.5)); box.path = body
        lid.path = CGPath(roundedRect:CGRect(x:3.2,y:5.8,width:19.6,height:4.2),cornerWidth:0.9,cornerHeight:0.9,transform:nil)
        let line = CGMutablePath(); line.move(to:CGPoint(x:10,y:13.5)); line.addLine(to:CGPoint(x:16,y:13.5))
        label.path = line
        for part in [box,label,lid] {
            part.frame = bounds; part.lineWidth = 1.65; part.lineJoin = .round; part.lineCap = .round
            part.strokeColor = NSColor.white.withAlphaComponent(0.72).cgColor
            part.fillColor = NSColor.clear.cgColor; addSublayer(part)
        }
        // Rotate the lid around its own centre rather than the whole icon.
        lid.anchorPoint = CGPoint(x:0.5,y:7.9/26); lid.position = CGPoint(x:13,y:7.9)
    }
    override init(layer:Any) { super.init(layer:layer) }
    required init?(coder:NSCoder) { fatalError() }

    func setSelected(_ value:Bool,accent:NSColor,ink:NSColor = .white,animated:Bool = true) {
        let changed = selected != value; selected = value
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let face = value ? LibraryMediaIcon.vividColor(accent).cgColor : NSColor.clear.cgColor
        box.fillColor = face; lid.fillColor = face
        for part in [box,label,lid] { part.strokeColor = ink.cgColor }
        CATransaction.commit()
        guard changed else { return }
        guard value && animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            for part in [box,label,lid] { part.removeAnimation(forKey:"archive-bounce") }
            return
        }
        let start = CACurrentMediaTime()
        animate(box,at:start,duration:0.68,
                y:[0,0.8,-2.2,-0.25,0.20,0],times:[0,0.15,0.40,0.64,0.82,1])
        animate(label,at:start+0.015,duration:0.65,
                y:[0,7.7,-4.6,-0.2,0.4,0],times:[0,0.17,0.43,0.66,0.82,1])
        animate(lid,at:start+0.025,duration:0.74,
                y:[0,0.9,-3.5,-0.6,0.4,0],times:[0,0.15,0.40,0.64,0.82,1],
                angles:[0,-0.055,0.17,-0.065,0.015,0])
    }

    private func animate(_ part:CALayer,at time:Double,duration:Double,y:[CGFloat],times:[NSNumber],angles:[CGFloat]? = nil) {
        var tracks:[(String,[CGFloat])] = [("transform.translation.y",y)]
        if let angles { tracks.append(("transform.rotation.z",angles)) }
        let group = CAAnimationGroup()
        group.animations = tracks.map { key,values in
            let track = CAKeyframeAnimation(keyPath:key)
            track.values = values; track.keyTimes = times; track.calculationMode = .cubic
            track.tensionValues = [0.8,0.45,0.45,0.5,0.7,1]; track.duration = duration
            return track
        }
        group.beginTime = part.convertTime(time,from:nil)
        group.duration = duration; group.fillMode = .backwards
        part.add(group,forKey:"archive-bounce")
    }
}
