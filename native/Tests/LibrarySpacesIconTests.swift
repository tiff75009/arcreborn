// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

@main enum LibrarySpacesIconTests {
    static func main() {
        _ = NSApplication.shared
        let icon = LibrarySpacesIcon()
        let rear = icon.sublayers![0] as! CAShapeLayer, front = icon.sublayers![1] as! CAShapeLayer
        let restingRear = rear.transform, restingFront = front.transform
        precondition(rear.bounds.height > rear.bounds.width && front.bounds.height > front.bounds.width,"two portrait pages")
        precondition(rear.mask != nil && front.mask == nil,"inactive front page occludes the rear outline")
        icon.setSelected(true,accent:.systemBlue)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let a = rear.animation(forKey:"spaces-meet") as! CAAnimationGroup
            let b = front.animation(forKey:"spaces-meet") as! CAAnimationGroup
            precondition(b.beginTime > a.beginTime && a.duration != b.duration,"independent page timelines")
            let rearX = (a.animations![0] as! CAKeyframeAnimation).values!.map { ($0 as! NSNumber).doubleValue }
            let frontX = (b.animations![0] as! CAKeyframeAnimation).values!.map { ($0 as! NSNumber).doubleValue }
            precondition(rearX[1] > 0 && frontX[1] < 0,"pages move towards one another")
            precondition(rearX[2] < 0 && frontX[2] > 0,"each page recoils in the opposite direction")
            precondition(icon.animationKeys() == nil,"no whole-icon bounce or zoom")
            icon.setSelected(true,accent:.systemPink)
            precondition(rear.animation(forKey:"spaces-meet")?.beginTime == a.beginTime,"active click or theme refresh cannot restart the motion")
            for _ in 0..<100 { icon.setSelected(false,accent:.systemBlue); icon.setSelected(true,accent:.systemBlue) }
            precondition(rear.animationKeys() == ["spaces-meet"] && front.animationKeys() == ["spaces-meet"])
        }
        precondition(rear.mask == nil && rear.fillColor == front.fillColor)
        icon.setSelected(false,accent:.systemBlue)
        precondition(rear.animationKeys() == nil && front.animationKeys() == nil && rear.mask != nil)
        precondition(rear.fillColor?.alpha == 0 && front.fillColor?.alpha == 0)
        icon.setSelected(true,accent:.systemPink,animated:false)
        precondition(CATransform3DEqualToTransform(rear.transform,restingRear) && CATransform3DEqualToTransform(front.transform,restingFront))
        precondition(rear.fillColor == LibraryMediaIcon.vividColor(.systemPink).cgColor)
        print("PASS: portrait pages, independent convergence and recoil, stable rest, active-click guard, rapid switching, inactive occlusion and reduced motion")
    }
}
