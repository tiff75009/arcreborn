// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

@main enum LibraryMediaIconTests {
    static func main() {
        _ = NSApplication.shared
        let icon = LibraryMediaIcon()
        let rear = icon.sublayers![0], front = icon.sublayers![1]
        precondition(icon.isHidden && !icon.selected)
        icon.setSelected(true,accent:.blue,animated:false)
        precondition(!icon.isHidden && icon.selected && rear.animationKeys() == nil)
        icon.setSelected(false,accent:.blue)
        icon.setSelected(true,accent:.blue)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let a = rear.animation(forKey:"media-jump") as! CAAnimationGroup
            let b = front.animation(forKey:"media-jump") as! CAAnimationGroup
            precondition((0.06...0.075).contains(b.beginTime-a.beginTime),"the front follows the rear")
            let lift = a.animations![0] as! CAKeyframeAnimation
            let tilt = a.animations![1] as! CAKeyframeAnimation
            let heights = lift.values!.map { ($0 as! NSNumber).doubleValue }, angles = tilt.values!.map { ($0 as! NSNumber).doubleValue }
            precondition(heights[1] > 0 && heights[3] < 0 && heights.min()! >= -3.5,"a small anticipation and low jump")
            precondition(abs(angles[3]) >= 0.14 && lift.keyTimes != tilt.keyTimes,"rotation and lift are not locked together")
            precondition(heights.last == 0 && angles.last == 0,"settle at the original position")
            icon.setSelected(true,accent:.systemPink)
            precondition(rear.animation(forKey:"media-jump")?.beginTime == a.beginTime,"active clicks and theme refreshes never replay the animation")
            for _ in 0..<100 { icon.setSelected(false,accent:.blue); icon.setSelected(true,accent:.blue) }
            precondition(rear.animationKeys() == ["media-jump"] && front.animationKeys() == ["media-jump"],"rapid switches replace rather than accumulate motion")
        }
        icon.setSelected(false,accent:.blue)
        precondition(icon.isHidden && rear.animationKeys() == nil && front.animationKeys() == nil)
        icon.setSelected(true,accent:.blue,animated:false)
        precondition(CATransform3DIsIdentity(rear.transform) && CATransform3DIsIdentity(front.transform))
        for source in [NSColor(srgbRed:0.3,green:0.3,blue:0.6,alpha:1), .systemPink, .systemGreen, .systemOrange] {
            var sourceHue:CGFloat = 0, h:CGFloat = 0,s:CGFloat = 0,b:CGFloat = 0,a:CGFloat = 0
            source.usingColorSpace(.sRGB)!.getHue(&sourceHue,saturation:nil,brightness:nil,alpha:nil)
            LibraryMediaIcon.vividColor(source).getHue(&h,saturation:&s,brightness:&b,alpha:&a)
            precondition(abs(h-sourceHue)<0.025 && s>=0.82 && b>0.98 && a==1,"vivid faces retain the space hue")
        }
        var saturation:CGFloat = 1
        LibraryMediaIcon.vividColor(.gray).getHue(nil,saturation:&saturation,brightness:nil,alpha:nil)
        precondition(saturation == 0,"neutral spaces stay neutral")
        print("PASS: independent media cards, anticipation, stagger, active-click guard, rapid switches, reduced motion and space colors")
    }
}
