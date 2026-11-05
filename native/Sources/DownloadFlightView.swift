// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

/// Drawn above the page and sidebar in the originating window. Pointer and
/// keyboard events keep going to the views underneath for the entire flight.
final class DownloadFlightView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point:NSPoint) -> NSView? { nil }

    func play(from start:CGPoint, into end:CGPoint, ink:NSColor, paper:NSColor, landed:@escaping () -> Void) {
        wantsLayer = true
        setAccessibilityElement(false)
        guard let host = layer else { removeFromSuperview(); landed(); return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reduce ? 0 : 0.64
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in self?.removeFromSuperview(); landed() }

        if !reduce {
            let badge = CALayer()
            badge.bounds = CGRect(x:0,y:0,width:30,height:30)
            badge.backgroundColor = ink.cgColor
            badge.cornerRadius = 15
            badge.shadowColor = NSColor.black.cgColor
            badge.shadowRadius = 4; badge.shadowOffset = CGSize(width:0,height:1); badge.shadowOpacity = 0.22
            badge.position = end; badge.opacity = 0
            let arrow = CAShapeLayer()
            arrow.frame = badge.bounds; arrow.fillColor = nil; arrow.strokeColor = paper.cgColor
            arrow.lineWidth = 2; arrow.lineCap = .round; arrow.lineJoin = .round
            let mark = CGMutablePath()
            mark.move(to:CGPoint(x:15,y:8)); mark.addLine(to:CGPoint(x:15,y:18))
            mark.move(to:CGPoint(x:10.5,y:14)); mark.addLine(to:CGPoint(x:15,y:18.5)); mark.addLine(to:CGPoint(x:19.5,y:14))
            mark.move(to:CGPoint(x:9,y:22)); mark.addLine(to:CGPoint(x:21,y:22))
            arrow.path = mark; badge.addSublayer(arrow); host.addSublayer(badge)

            let dx = start.x-end.x, dy = end.y-start.y
            let path = CGMutablePath(); path.move(to:start)
            path.addCurve(to:end,control1:CGPoint(x:start.x-0.20*dx,y:max(18,start.y-64)),
                          control2:CGPoint(x:end.x+0.12*dx,y:end.y-max(18,0.3*dy)))
            let travel = CAKeyframeAnimation(keyPath:"position")
            travel.path = path; travel.calculationMode = .paced
            travel.timingFunction = CAMediaTimingFunction(controlPoints:0.35,0.04,0.43,1)
            let shrink = CAKeyframeAnimation(keyPath:"transform.scale")
            shrink.values = [0.72,1,0.86,0.34]; shrink.keyTimes = [0,0.15,0.68,1]
            let fade = CAKeyframeAnimation(keyPath:"opacity")
            fade.values = [0,1,1,0]; fade.keyTimes = [0,0.09,0.84,1]
            for animation in [travel,shrink,fade] { animation.duration = duration }
            let flight = CAAnimationGroup()
            flight.animations = [travel,shrink,fade]; flight.duration = duration
            badge.add(flight,forKey:"download-flight")
        }

        let ring = CAShapeLayer()
        ring.bounds = CGRect(x:0,y:0,width:26,height:26); ring.position = end
        ring.path = CGPath(ellipseIn:ring.bounds.insetBy(dx:1,dy:1),transform:nil)
        ring.fillColor = nil; ring.strokeColor = ink.cgColor; ring.lineWidth = 1.5; ring.opacity = 0
        host.addSublayer(ring)
        let arrival = CAKeyframeAnimation(keyPath:"opacity")
        arrival.values = [0,0.48,0]; arrival.keyTimes = [0,0.23,1]; arrival.duration = 0.30
        let pulse = CAAnimationGroup()
        pulse.animations = [arrival]
        if !reduce {
            let bloom = CABasicAnimation(keyPath:"transform.scale")
            bloom.fromValue = 0.70; bloom.toValue = 1.18; bloom.duration = 0.30
            pulse.animations?.append(bloom)
        }
        pulse.beginTime = ring.convertTime(CACurrentMediaTime(),from:nil)+max(0,duration-0.06)
        pulse.duration = 0.30
        ring.add(pulse,forKey:"download-arrival")
        CATransaction.commit()
    }
}
