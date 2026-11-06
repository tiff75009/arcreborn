// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

enum SidebarTabReturnEdge { case above, below }

enum SidebarTabReturnGeometry {
    static func edge(of row:NSRect,visible:NSRect) -> SidebarTabReturnEdge? {
        guard !row.isEmpty, visible.height > 0 else { return nil }
        if row.maxY <= visible.minY+0.5 { return .above }
        if row.minY >= visible.maxY-0.5 { return .below }
        return nil
    }
    static func destination(for row:NSRect,edge:SidebarTabReturnEdge,visible:NSRect,document:NSRect) -> CGFloat {
        let y = edge == .above ? row.minY : row.maxY-visible.height
        return min(max(document.minY,y),max(document.minY,document.maxY-visible.height))
    }
}

/// A floating, native button. The outgoing surface keeps owning its clicks until
/// the fade finishes, even though its action has already been disabled.
final class SidebarTabReturnButton: NSButton {
    static let diameter: CGFloat = 28
    let edge: SidebarTabReturnEdge
    private(set) var shown = false
    private var revision = 0
    var invoke: (() -> Void)?
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    init(edge:SidebarTabReturnEdge) {
        self.edge = edge
        super.init(frame:NSRect(x:0,y:0,width:Self.diameter,height:Self.diameter))
        title = ""; isBordered = false; focusRingType = .exterior
        target = self; action = #selector(activate)
        wantsLayer = true; isHidden = true
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.10
        layer?.shadowRadius = 3; layer?.shadowOffset = NSSize(width:0,height:1)
    }
    required init?(coder:NSCoder) { fatalError() }
    @objc private func activate() { if shown { invoke?() } }
    func contains(_ point:NSPoint) -> Bool {
        guard !isHiddenOrHasHiddenAncestor else { return false }
        let p = convert(point,from:nil), radius = min(bounds.width,bounds.height)/2
        return hypot(p.x-bounds.midX,p.y-bounds.midY) <= radius
    }
    override func hitTest(_ point:NSPoint) -> NSView? {
        let p = superview?.convert(point,to:nil) ?? point
        return contains(p) ? super.hitTest(point) : nil
    }
    func setShown(_ value:Bool,animated:Bool = true) {
        guard shown != value else { return }
        shown = value; revision += 1; let token = revision
        let animate = animated && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let wasHidden = isHidden
        let oldOpacity = wasHidden ? 0 : (layer?.presentation()?.opacity ?? layer?.opacity ?? 0)
        let oldTransform = layer?.presentation()?.transform ?? layer?.transform ?? CATransform3DIdentity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.removeAllAnimations(); layer?.transform = CATransform3DIdentity
        layer?.opacity = value ? 1 : 0
        isHidden = !value && !animate
        CATransaction.commit()
        guard animate else { return }
        let direction:CGFloat = edge == .above ? -1 : 1
        let transform = CAKeyframeAnimation(keyPath:"transform")
        let values:[(CGFloat,CGFloat)] = value
            ? [(direction*10,0.64),(-direction*1.2,1.075),(direction*0.3,0.985),(0,1)]
            : [(0,1),(direction*4,0.9)]
        var poses = values.map { y,scale -> NSValue in
            let anchor = layer?.anchorPoint ?? .zero
            let dx = bounds.width*(0.5-anchor.x)*(1-scale)
            let dy = bounds.height*(0.5-anchor.y)*(1-scale)+y
            return NSValue(caTransform3D:CATransform3DScale(CATransform3DMakeTranslation(dx,dy,0),scale,scale,1))
        }
        if !wasHidden { poses[0] = NSValue(caTransform3D:oldTransform) }
        transform.values = poses
        transform.keyTimes = value ? [0,0.55,0.78,1] : [0,1]
        transform.timingFunctions = Array(repeating:CAMediaTimingFunction(name:.easeInEaseOut),count:values.count-1)
        transform.duration = value ? 0.42 : 0.14
        layer?.add(transform,forKey:"return-motion")
        let opacity = CABasicAnimation(keyPath:"opacity")
        opacity.fromValue = oldOpacity
        opacity.toValue = value ? 1 : 0; opacity.duration = 0.14
        layer?.add(opacity,forKey:"return-opacity")
        if !value {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.14) { [weak self] in
                guard let self, self.revision == token, !self.shown else { return }
                self.isHidden = true
            }
        }
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor(white:isHighlighted ? 0.88 : 0.97,alpha:1).setFill()
        NSBezierPath(ovalIn:bounds).fill()
        NSColor(white:0.08,alpha:1).setStroke()
        let path = NSBezierPath(); path.lineWidth = 1.65; path.lineCapStyle = .round; path.lineJoinStyle = .round
        let x = bounds.midX, y = bounds.midY, sign:CGFloat = edge == .above ? -1 : 1
        path.move(to:NSPoint(x:x,y:y-sign*5)); path.line(to:NSPoint(x:x,y:y+sign*5))
        path.move(to:NSPoint(x:x-4.3,y:y+sign*0.7)); path.line(to:NSPoint(x:x,y:y+sign*5)); path.line(to:NSPoint(x:x+4.3,y:y+sign*0.7))
        path.stroke()
    }
}

/// Scroll only; never select a row or open a page. A wheel or drag can cancel the
/// motion immediately instead of fighting a queued AppKit property animation.
final class SidebarTabReturnMotion {
    private var timer: Timer?
    private var completion: (() -> Void)?
    var isRunning: Bool { timer != nil }
    func cancel() {
        timer?.invalidate(); timer = nil
        let done = completion; completion = nil; done?()
    }
    func scroll(_ scroll:NSScrollView,to y:CGFloat,animated:Bool = true,completion:@escaping () -> Void) {
        cancel()
        let clip = scroll.contentView, origin = clip.bounds.origin
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, abs(y-origin.y) > 0.5 else {
            clip.scroll(to:NSPoint(x:origin.x,y:y)); scroll.reflectScrolledClipView(clip); completion(); return
        }
        self.completion = completion
        let start = ProcessInfo.processInfo.systemUptime
        let duration = 0.26+min(0.12,Double(abs(y-origin.y))/4000)
        let timer = Timer(timeInterval:1/Double(max(60,scroll.window?.screen?.maximumFramesPerSecond ?? 60)),repeats:true) { [weak self,weak scroll] _ in
            guard let self, let scroll else { self?.cancel(); return }
            let t = min(1,(ProcessInfo.processInfo.systemUptime-start)/duration)
            let progress = CGFloat(1-pow(1-t,3))
            let clip = scroll.contentView
            clip.scroll(to:NSPoint(x:origin.x,y:origin.y+(y-origin.y)*progress))
            scroll.reflectScrolledClipView(clip)
            if t >= 1 { self.cancel() }
        }
        self.timer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    deinit { timer?.invalidate() }
}
