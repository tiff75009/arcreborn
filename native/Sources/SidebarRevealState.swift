import AppKit

extension NSWindow {
    /// AppKit tracking areas can still report points covered by another window.
    func receivesPointer(atScreenPoint point: NSPoint) -> Bool {
        isVisible && !isMiniaturized && frame.contains(point) &&
            NSWindow.windowNumber(at:point, belowWindowWithWindowNumber:0) == windowNumber
    }
}

extension NSView {
    func containsExposedPointer(at point: NSPoint) -> Bool {
        guard let window, !isHiddenOrHasHiddenAncestor,
              bounds.intersection(visibleRect).contains(convert(point,from:nil)) else { return false }
        return window.receivesPointer(atScreenPoint:window.convertPoint(toScreen:point))
    }

    var containsCurrentPointer: Bool {
        guard let window else { return false }
        return containsExposedPointer(at:window.mouseLocationOutsideOfEventStream)
    }
}

/// Hovering only changes transient presentation, never the saved sidebar preference.
enum SidebarRevealIntent: Equatable { case reveal, hide, keep }
struct SidebarRevealState {
    /// A point inside the window frame may actually belong to an overlapping app.
    static func pointer(at screenPoint: NSPoint, in root: NSView) -> NSPoint? {
        guard let window = root.window else { return nil }
        let point = root.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        guard root.bounds.contains(point), window.receivesPointer(atScreenPoint:screenPoint) else { return nil }
        return point
    }
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
