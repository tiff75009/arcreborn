// SPDX-License-Identifier: MPL-2.0
import AppKit

/// The committed side and the visible position can differ while the fingers are
/// down, or when a new gesture catches the drawer before it has settled.
final class LibraryDrawerMotion {
    private(set) var progress: CGFloat = 0
    private(set) var targetOpen = false
    private var origin: CGFloat?
    private var timer: Timer?
    var isTracking: Bool { origin != nil }
    var isSettling: Bool { timer != nil }

    func track(offset: CGFloat, width: CGFloat) {
        if origin == nil {
            timer?.invalidate(); timer = nil
            origin = progress
        }
        progress = min(1, max(0, (origin ?? progress) + offset / max(1,width)))
    }

    func releaseTarget(velocity: CGFloat, width: CGFloat) -> Bool {
        if abs(progress - (targetOpen ? 1 : 0)) * width < 8 { return targetOpen }
        let projection = progress + max(-0.30, min(0.30, velocity * 0.12 / max(1,width)))
        return targetOpen ? projection > 0.72 : projection >= 0.28
    }

    func settle(open: Bool, velocity: CGFloat, width: CGFloat, screen: NSScreen?,
                draw: @escaping () -> Void, completion: @escaping () -> Void) {
        origin = nil; targetOpen = open
        timer?.invalidate(); timer = nil
        let start = progress, end: CGFloat = open ? 1 : 0, distance = end-start
        guard abs(distance) > 0.001, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            progress = end; draw(); completion(); return
        }
        let duration = 0.12 + 0.18 * abs(distance)
        // Cubic Hermite with the finger's release velocity and zero end velocity.
        // Limit the tangent to keep this final stretch monotonic at either edge.
        let tangent = min(3, max(0, velocity / max(1,width) * duration / distance))
        let began = CACurrentMediaTime()
        let tick = Timer(timeInterval:1/Double(max(60,screen?.maximumFramesPerSecond ?? 60)),repeats:true) { [weak self] tick in
            guard let self else { tick.invalidate(); return }
            let t = min(1,(CACurrentMediaTime()-began)/duration), rest = 1-t
            self.progress = start + distance * (t*t*(3-2*t) + tangent*t*rest*rest)
            draw()
            if t == 1 {
                tick.invalidate(); self.timer = nil; completion()
            }
        }
        timer = tick
        RunLoop.main.add(tick,forMode:.common)
    }

    deinit { timer?.invalidate() }
}
