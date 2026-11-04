import Foundation
import CoreGraphics

/// Hovering only changes transient presentation, never the saved sidebar preference.
enum SidebarRevealIntent: Equatable { case reveal, hide, keep }
struct SidebarRevealState {
    static func intent(hidden: Bool, revealed: Bool, active: Bool, pointer: CGPoint?,
                       height: CGFloat, sidebarWidth: CGFloat, protected: Bool) -> SidebarRevealIntent {
        guard hidden else { return .keep }
        if revealed && protected { return .keep }
        guard active, let p = pointer else { return revealed ? .hide : .keep }
        if revealed {
            // Small hysteresis prevents flicker along the rounded panel edge.
            return CGRect(x: 0, y: 0, width: sidebarWidth + 14, height: height).contains(p) ? .keep : .hide
        }
        return CGRect(x: 0, y: 0, width: 8, height: height).contains(p) ? .reveal : .keep
    }
}
