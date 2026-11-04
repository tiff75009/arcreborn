import Foundation

struct SpaceIndicatorLayout {
    let count: Int
    let available: Double
    let activeIndex: Int
    var activeWidth: Double { min(34,max(24,available / Double(max(1,count)))) }
    var inactiveWidth: Double { count <= 1 ? 34 : min(34,max(12,(available-activeWidth)/Double(count-1))) }
    var width: Double { count == 0 ? 0 : activeWidth+Double(count-1)*inactiveWidth }
    var start: Double { max(0,(available-width)/2) }
    var dotDiameter: Double { max(4,min(8,inactiveWidth*8/34)) }
    func frame(_ index: Int) -> (x: Double, width: Double) {
        (start+Double(index)*inactiveWidth+(index > activeIndex ? activeWidth-inactiveWidth : 0),index == activeIndex ? activeWidth : inactiveWidth)
    }
}

/// Own the gesture from its first horizontal delta, including its release and momentum.
struct SpaceSwipeState {
    enum Phase { case began, changed, ended, cancelled, unphased }
    struct Update {
        let consume: Bool
        let offset: Double
        let velocity: Double
        let ended: Bool
        let cancelled: Bool
        var direction: Int? { abs(offset) > 0.01 ? (offset < 0 ? 1 : -1) : nil }
        func shouldCommit(width: Double) -> Bool {
            let projected = offset + velocity * 0.12
            return abs(offset) >= width * 0.28 ||
                (abs(offset) >= 12 && projected * offset > 0 && abs(projected) >= width * 0.28)
        }
    }
    private enum Axis { case pending, horizontal, vertical, rejected }
    private var axis: Axis = .pending
    private var x = 0.0, y = 0.0, lastTime = -Double.infinity, velocity = 0.0
    private var active = false
    mutating func reset() { self = SpaceSwipeState() }
    mutating func update(dx: Double, dy: Double, phase: Phase, momentum: Bool, eligible: Bool, time: Double) -> Update {
        if momentum { return Update(consume:axis == .horizontal && eligible,offset:x,velocity:0,ended:false,cancelled:false) }
        if phase == .began || !active || (phase == .unphased && time-lastTime > 0.20) {
            axis = eligible ? .pending : .rejected; x = 0; y = 0; velocity = 0; active = true
            lastTime = time
        }
        let dt = time-lastTime
        if dt > 0.001 && dt < 0.12 && dx != 0 { velocity = velocity*0.35 + dx/dt*0.65 }
        else if dt >= 0.12 { velocity = 0 }
        lastTime = time
        let wasHorizontal = axis == .horizontal
        if !eligible || phase == .cancelled {
            axis = .rejected; active = phase != .cancelled && phase != .ended
            return Update(consume:wasHorizontal,offset:x,velocity:0,ended:true,cancelled:true)
        }
        x += dx; y += dy
        if axis == .pending && max(abs(x),abs(y)) > 0 {
            if abs(y) > abs(x)*1.15 { axis = .vertical }
            else if abs(x) > abs(y)*1.35 { axis = .horizontal }
        }
        let consumed = axis == .horizontal || (axis == .pending && phase == .began)
        if phase == .ended { active = false }
        return Update(consume:consumed,offset:axis == .horizontal ? x : 0,velocity:velocity,
                      ended:phase == .ended,cancelled:false)
    }
}

#if canImport(AppKit)
import AppKit

/// The footer is a horizontal strip, never a vertically scrolling list.
final class HorizontalSpaceScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), let documentView else { return }
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        let x = min(max(0,contentView.bounds.minX-event.scrollingDeltaX*scale),max(0,documentView.bounds.width-contentView.bounds.width))
        contentView.scroll(to:NSPoint(x:x,y:0)); reflectScrolledClipView(contentView)
    }
}
#endif

/// Destination is the final index, after removal of the moving space.
extension BrowserSession {
    @discardableResult mutating func reorderSpace(id:String,to destination:Int) -> Bool {
        guard spaces.indices.contains(destination), let source = spaces.firstIndex(where: { $0.id == id }), source != destination else { return false }
        let space = spaces.remove(at:source); spaces.insert(space,at:destination)
        return true
    }
}
