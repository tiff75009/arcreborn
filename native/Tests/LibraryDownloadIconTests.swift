// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

@main enum LibraryDownloadIconTests {
    static func main() {
        _ = NSApplication.shared
        let icon = LibraryDownloadIcon()
        let ring = icon.sublayers![0] as! CAShapeLayer, arrow = icon.sublayers![1]
        let shaft = arrow.sublayers![0] as! CAShapeLayer, point = arrow.sublayers![1] as! CAShapeLayer
        let circlePath = ring.path!, shaftPath = shaft.path!, pointPath = point.path!
        let strokeWidth = shaft.lineWidth
        let accent = NSColor(srgbRed:0.33,green:0.33,blue:0.6,alpha:1)
        icon.setSelected(true,accent:accent,animated:false)
        precondition(ring.fillColor == LibraryMediaIcon.vividColor(accent).cgColor)
        precondition(shaft.strokeStart == 0 && arrow.animationKeys() == nil)
        icon.setSelected(false,accent:accent)
        precondition(ring.fillColor?.alpha == 0 && !icon.isHidden,"inactive outline retains the same size")
        icon.setSelected(true,accent:accent)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let press = arrow.animation(forKey:"download-arrow") as! CAKeyframeAnimation
            let response = ring.animation(forKey:"download-ring") as! CAKeyframeAnimation
            let compress = shaft.animation(forKey:"download-shaft") as! CAKeyframeAnimation
            let lengths = compress.values!.map { ($0 as! NSNumber).doubleValue }
            let circleTravel = response.values!.map { ($0 as! NSNumber).doubleValue }
            precondition(lengths.min() == 0 && lengths.max()! > 0.25 && lengths.last == 0,"shaft shortens and returns to full length")
            precondition(response.keyTimes != press.keyTimes && response.duration != press.duration,"ring and arrow have independent timing")
            precondition(circleTravel.min()! < -1.5 && circleTravel.max()! > 0.4,"the circle visibly crouches and jumps, rather than barely moving a fraction of a point")
            precondition(response.beginTime > press.beginTime && response.fillMode == .backwards,"the circle follows on its own delayed timeline without a starting jump")
            precondition(ring.path == circlePath && shaft.path == shaftPath && point.path == pointPath && shaft.lineWidth == strokeWidth,"animation preserves the circle, point and stroke thickness")
            precondition(point.animationKeys() == nil && icon.animationKeys() == nil,"no scaling of the complete icon or arrowhead")
            icon.setSelected(true,accent:.systemPink)
            precondition(arrow.animation(forKey:"download-arrow")?.beginTime == press.beginTime,"active click or recoloring does not restart")
            for _ in 0..<100 { icon.setSelected(false,accent:accent); icon.setSelected(true,accent:accent) }
            precondition(arrow.animationKeys() == ["download-arrow"] && shaft.animationKeys() == ["download-shaft"] && ring.animationKeys() == ["download-ring"])
        }
        icon.setSelected(false,accent:accent)
        precondition(arrow.animationKeys() == nil && shaft.animationKeys() == nil && ring.animationKeys() == nil)
        icon.setSelected(true,accent:accent,animated:false)
        precondition(shaft.strokeStart == 0 && CATransform3DIsIdentity(arrow.transform) && CATransform3DIsIdentity(ring.transform))
        print("PASS: independent download ring, shaft compression, unchanged arrowhead, stable geometry, active-click guard, rapid switches and reduced motion")
    }
}
