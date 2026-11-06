// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

/// Two portrait pages meet, recoil and settle separately. Neither the title nor
/// the complete icon scales or moves with them.
final class LibrarySpacesIcon: CALayer {
    private let rear = CAShapeLayer(), front = CAShapeLayer()
    private let rearCutout = CAShapeLayer()
    private let rearAngle: CGFloat = -0.30
    private(set) var selected = false

    override init() {
        super.init()
        bounds = CGRect(x:0,y:0,width:26,height:26)
        makePage(rear,frame:CGRect(x:4.5,y:2.6,width:14.5,height:19.5))
        makePage(front,frame:CGRect(x:9.5,y:5.3,width:15,height:19.5))
        rear.transform = CATransform3DMakeRotation(rearAngle,0,0,1)
        rearCutout.frame = rear.bounds
        let origin = rear.convert(CGPoint.zero,from:front)
        let x = rear.convert(CGPoint(x:1,y:0),from:front)
        let y = rear.convert(CGPoint(x:0,y:1),from:front)
        var transform = CGAffineTransform(a:x.x-origin.x,b:x.y-origin.y,c:y.x-origin.x,d:y.y-origin.y,tx:origin.x,ty:origin.y)
        let cutout = CGMutablePath()
        cutout.addRect(CGRect(x:-30,y:-30,width:90,height:90))
        cutout.addPath(front.path!.copy(using:&transform)!)
        rearCutout.path = cutout; rearCutout.fillRule = .evenOdd
        // Preserve the clean overlapping outlines when the faces are unfilled.
        rear.mask = rearCutout
    }
    override init(layer:Any) { super.init(layer:layer) }
    required init?(coder:NSCoder) { fatalError() }

    private func makePage(_ page:CAShapeLayer,frame:CGRect) {
        page.frame = frame
        page.path = CGPath(roundedRect:page.bounds.insetBy(dx:0.85,dy:0.85),cornerWidth:1.9,cornerHeight:1.9,transform:nil)
        page.lineWidth = 1.65; page.lineJoin = .round
        page.fillColor = NSColor.clear.cgColor
        page.strokeColor = NSColor.white.withAlphaComponent(0.72).cgColor
        addSublayer(page)
    }

    func setSelected(_ value:Bool,accent:NSColor,ink:NSColor = .white,animated:Bool = true) {
        let changed = selected != value; selected = value
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let face = value ? LibraryMediaIcon.vividColor(accent).cgColor : NSColor.clear.cgColor
        for page in [rear,front] { page.fillColor = face; page.strokeColor = ink.cgColor }
        rear.mask = value ? nil : rearCutout
        CATransaction.commit()
        guard changed else { return }
        guard value && animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            rear.removeAnimation(forKey:"spaces-meet"); front.removeAnimation(forKey:"spaces-meet")
            return
        }
        let start = CACurrentMediaTime()
        // The rear straightens into the front, then fans back out. The front
        // answers slightly later, tipping in the opposite direction on recoil.
        animate(rear,at:start,duration:0.66,
                x:[0,2.7,-1.15,0.28,-0.06,0], y:[0,0.80,-0.35,0.10,0,0],
                angles:[rearAngle,-0.045,-0.40,-0.27,-0.307,rearAngle],
                times:[0,0.25,0.48,0.70,0.86,1])
        animate(front,at:start+0.035,duration:0.70,
                x:[0,-1.1,1.15,-0.24,0.055,0], y:[0,-0.40,0.32,-0.09,0,0],
                angles:[0,-0.07,0.18,-0.035,0.008,0],
                times:[0,0.22,0.46,0.69,0.85,1])
    }

    private func animate(_ page:CALayer,at time:Double,duration:Double,x:[CGFloat],y:[CGFloat],angles:[CGFloat],times:[NSNumber]) {
        let tracks = [("transform.translation.x",x),("transform.translation.y",y),("transform.rotation.z",angles)]
        let group = CAAnimationGroup()
        group.animations = tracks.map { key,values in
            let track = CAKeyframeAnimation(keyPath:key)
            track.values = values; track.keyTimes = times
            track.calculationMode = .cubic
            track.tensionValues = [0.8,0.35,0.35,0.45,0.65,1]
            track.duration = duration
            return track
        }
        group.beginTime = page.convertTime(time,from:nil)
        group.duration = duration; group.fillMode = .backwards
        page.add(group,forKey:"spaces-meet")
    }
}
