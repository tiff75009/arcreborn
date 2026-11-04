import Foundation
import CoreGraphics

@main struct SidebarRevealTests {
    static func main() {
        var passed = 0
        func check(_ expected: SidebarRevealIntent, _ message: String, hidden: Bool = true, revealed: Bool = false,
                   active: Bool = true, x: CGFloat? = 3, y: CGFloat = 300, width: CGFloat = 240, protected: Bool = false) {
            let point = x.map { CGPoint(x: $0, y: y) }
            let actual = SidebarRevealState.intent(hidden: hidden, revealed: revealed, active: active,
                                                   pointer: point, height: 820, sidebarWidth: width, protected: protected)
            guard actual == expected else { fatalError(message) }; passed += 1
        }
        check(.reveal, "left border reveals the sidebar")
        check(.keep, "web content never triggers reveal", x: 9)
        check(.keep, "outside the window does not reveal", x: -1)
        check(.keep, "above the window does not reveal", y: -1)
        check(.keep, "below the window does not reveal", y: 821)
        check(.keep, "unavailable window does not reveal", active: false)
        check(.keep, "pinned sidebar ignores pointer", hidden: false, x: 500)
        check(.keep, "inside revealed sidebar", revealed: true, x: 180)
        check(.keep, "hysteresis at rounded edge", revealed: true, x: 250)
        check(.hide, "leaving panel hides it", revealed: true, x: 270)
        check(.hide, "leaving window hides it", revealed: true, x: nil)
        check(.hide, "unavailable window hides it", revealed: true, active: false)
        check(.keep, "menu, palette or drag holds sidebar open", revealed: true, x: 700, protected: true)
        check(.hide, "ending interaction outside dismisses", revealed: true, x: 700, protected: false)
        check(.keep, "resized sidebar preserves interior", revealed: true, x: 380, width: 400)
        check(.hide, "resized sidebar dismisses beyond its edge", revealed: true, x: 420, width: 400)
        print("PASS: \(passed) sidebar hover assertions")
    }
}
