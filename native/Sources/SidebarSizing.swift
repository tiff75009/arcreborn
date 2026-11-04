import Foundation

enum SidebarSizing {
    static let minimum = 224.0
    static let standard = 240.0
    static let maximum = 400.0

    static func clamp(_ width: Double) -> Double {
        guard width.isFinite else { return standard }
        return min(maximum, max(minimum, width))
    }
}

/// The pointer remains independent of the snapped width: no accumulating drift.
struct SidebarResizeGesture {
    private let initialWidth: Double
    private let initialX: Double
    private var snapped: Bool

    init(width: Double, pointerX: Double) {
        initialWidth = SidebarSizing.clamp(width)
        initialX = pointerX
        snapped = initialWidth == SidebarSizing.standard
    }

    mutating func update(pointerX: Double) -> (width: Double, alignment: Bool) {
        let width = SidebarSizing.clamp(initialWidth + pointerX - initialX)
        let distance = abs(width - SidebarSizing.standard)
        if snapped {
            if distance <= 10 { return (SidebarSizing.standard, false) }
            snapped = false
        } else if distance <= 6 {
            snapped = true
            return (SidebarSizing.standard, true)
        }
        return (width, false)
    }
}
