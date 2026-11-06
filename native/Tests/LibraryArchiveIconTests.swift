// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

@main enum LibraryArchiveIconTests {
    static func main() {
        _ = NSApplication.shared
        let icon = LibraryArchiveIcon()
        let parts = icon.sublayers! as! [CAShapeLayer]
        let paths = parts.map { $0.path! }
        precondition(parts.count == 3)
        icon.setSelected(true,accent:.systemBlue)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let groups = parts.map { $0.animation(forKey:"archive-bounce") as! CAAnimationGroup }
            precondition(Set(groups.map(\.beginTime)).count == 3 && Set(groups.map(\.duration)).count == 3,"three independent timelines")
            for group in groups {
                let y = (group.animations![0] as! CAKeyframeAnimation).values!.map { ($0 as! NSNumber).doubleValue }
                precondition(y[1] > 0 && y[2] < 0 && y.last == 0,"anticipation, jump and rest")
            }
            let tilt = groups[2].animations!.last as! CAKeyframeAnimation
            precondition(tilt.keyPath == "transform.rotation.z" && (tilt.values![2] as! NSNumber).doubleValue > 0.1,"lid tilts in flight")
            precondition(icon.animationKeys() == nil,"no whole-icon bounce")
            icon.setSelected(true,accent:.systemPink)
            precondition(parts[0].animation(forKey:"archive-bounce")?.beginTime == groups[0].beginTime,"active click or theme update does not restart")
            for _ in 0..<100 { icon.setSelected(false,accent:.systemBlue); icon.setSelected(true,accent:.systemBlue) }
            precondition(parts.allSatisfy { $0.animationKeys() == ["archive-bounce"] })
        }
        icon.setSelected(false,accent:.systemBlue)
        precondition(parts.allSatisfy { $0.animationKeys() == nil && $0.fillColor?.alpha == 0 })
        icon.setSelected(true,accent:.systemPink,animated:false)
        precondition(parts.allSatisfy { $0.animationKeys() == nil && CATransform3DIsIdentity($0.transform) })
        precondition(zip(parts,paths).allSatisfy { $0.path == $1 },"stable resting geometry")
        precondition(parts[0].fillColor == LibraryMediaIcon.vividColor(.systemPink).cgColor && parts[0].fillColor == parts[2].fillColor)
        print("PASS: independent archive parts, anticipation, lid tilt, stable rest, active-click guard, rapid switching and reduced motion")
    }
}
