import Foundation

@main struct SidebarSizingTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message); count += 1
        }
        check(SidebarSizing.clamp(180) == 224, "legacy narrow width")
        check(SidebarSizing.clamp(440) == 400, "legacy wide width")
        check(SidebarSizing.clamp(.nan) == 240, "invalid width")
        var drag = SidebarResizeGesture(width: 300, pointerX: 306)
        check(drag.update(pointerX: 306).width == 300, "grab offset must not jump")
        check(drag.update(pointerX: 900).width == 400, "maximum")
        check(drag.update(pointerX: 0).width == 224, "minimum")
        let snap = drag.update(pointerX: 251)
        check(snap.width == 240 && snap.alignment, "snap and pulse on entry")
        let held = drag.update(pointerX: 255)
        check(held.width == 240 && !held.alignment, "hysteresis prevents repeated pulses")
        check(drag.update(pointerX: 258).width == 252, "release beyond magnet")
        check(drag.update(pointerX: 246).alignment, "return triggers a new pulse")
        var defaultDrag = SidebarResizeGesture(width: 240, pointerX: 246)
        check(!defaultDrag.update(pointerX: 246).alignment, "no pulse merely grabbing default")
        check(defaultDrag.update(pointerX: 260).width == 254, "can leave default")
        check(defaultDrag.update(pointerX: 246).alignment, "default reached again")
        print("PASS: \(count) sidebar resizing assertions")
    }
}
