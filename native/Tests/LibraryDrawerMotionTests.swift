// SPDX-License-Identifier: MPL-2.0
import AppKit

@main enum LibraryDrawerMotionTests {
    static func main() {
        _ = NSApplication.shared
        let motion = LibraryDrawerMotion(), width: CGFloat = 400
        func follow(_ delta: CGFloat) { motion.track(offset:delta,width:width) }
        func settle(_ open: Bool) {
            var completed = false
            motion.settle(open:open,velocity:0,width:width,screen:nil,draw:{},completion:{ completed = true })
            let deadline = Date(timeIntervalSinceNow:1)
            while !completed && Date() < deadline { RunLoop.main.run(until:Date(timeIntervalSinceNow:0.01)) }
            precondition(completed && !motion.isTracking && motion.progress == (open ? 1 : 0))
        }
        follow(80); precondition(motion.progress == 0.2)
        RunLoop.main.run(until:Date(timeIntervalSinceNow:0.25))
        precondition(motion.progress == 0.2 && !motion.releaseTarget(velocity:0,width:width))
        follow(52); precondition(motion.progress == 0.13 && motion.releaseTarget(velocity:800,width:width))
        follow(1); precondition(!motion.releaseTarget(velocity:4000,width:width))
        follow(-30); precondition(motion.progress == 0)
        follow(500); precondition(motion.progress == 1 && motion.releaseTarget(velocity:0,width:width))
        settle(true)
        follow(-40); precondition(motion.progress == 0.9 && motion.releaseTarget(velocity:0,width:width))
        follow(-160); precondition(motion.progress == 0.6 && !motion.releaseTarget(velocity:0,width:width))
        follow(-32); precondition(motion.progress == 0.92 && motion.releaseTarget(velocity:0,width:width))
        settle(true)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            motion.settle(open:false,velocity:0,width:width,screen:nil,draw:{},completion:{ preconditionFailure("interrupted close completed") })
            RunLoop.main.run(until:Date(timeIntervalSinceNow:0.08))
            let partial = motion.progress
            precondition(partial > 0 && partial < 1)
            follow(8); precondition(abs(motion.progress-min(1,partial+0.02)) < 1e-6)
            RunLoop.main.run(until:Date(timeIntervalSinceNow:0.35))
            precondition(abs(motion.progress-min(1,partial+0.02)) < 1e-6)
        }
        settle(false)
        print("PASS: interactive drawer distance, holds, reversals, release, endpoints and re-grab")
    }
}
