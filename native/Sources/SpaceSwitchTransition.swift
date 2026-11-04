import AppKit
import QuartzCore

/// AppKit owns the flipped coordinate system of every snapshot and its viewport.
/// Only these two cached sidebar pages move; Chromium and favorites stay in place.
final class SpaceSwitchTransition {
    private final class Page: NSView { override var isFlipped: Bool { true } }
    private let overlay: NSView
    private let outgoing = Page()
    private let incoming = Page()
    private var concealed: [NSView] = []
    private var cleanup: DispatchWorkItem?
    private var finished = false
    private var distance: CGFloat = 0
    private var progress: CGFloat = 0
    private let contentCopy: ((NSView) -> NSView?)?

    init(host: NSView, views: [NSView], region: NSRect, contentCopy: ((NSView) -> NSView?)? = nil) {
        self.contentCopy = contentCopy
        overlay = Page(frame:region)
        overlay.wantsLayer = true; overlay.layer?.masksToBounds = true
        for page in [outgoing,incoming] {
            page.frame = overlay.bounds; page.wantsLayer = true
            overlay.addSubview(page)
        }
        capture(views,into:outgoing,region:region)
        host.addSubview(overlay)
    }

    private func capture(_ views: [NSView], into container: NSView, region: NSRect) {
        for view in views where !view.isHidden && view.bounds.width > 0 && view.bounds.height > 0 {
            if let copy = contentCopy?(view) {
                copy.frame = view.frame.offsetBy(dx:-region.minX,dy:-region.minY)
                container.addSubview(copy)
                copy.layoutSubtreeIfNeeded(); copy.displayIfNeeded()
                continue
            }
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { continue }
            view.cacheDisplay(in:view.bounds,to:bitmap)
            let image = NSImage(size:view.bounds.size); image.addRepresentation(bitmap)
            let snapshot = NSImageView(frame:view.frame.offsetBy(dx:-region.minX,dy:-region.minY))
            snapshot.image = image; snapshot.imageScaling = .scaleAxesIndependently
            container.addSubview(snapshot)
        }
    }

    func captureIncoming(views: [NSView], towardsRight: Bool) {
        capture(views,into:incoming,region:overlay.frame)
        distance = overlay.bounds.width * (towardsRight ? 1 : -1)
        setProgress(0)
    }

    func conceal(_ views: [NSView]) {
        concealed = views
        for view in views { view.alphaValue = 0 }
    }

    func setProgress(_ value: CGFloat) {
        progress = min(1,max(0,value))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        outgoing.setFrameOrigin(NSPoint(x:-distance*progress,y:0))
        incoming.setFrameOrigin(NSPoint(x:distance*(1-progress),y:0))
        CATransaction.commit()
    }

    func settle(commit: Bool, duration: Double, completion: @escaping () -> Void) {
        let target: CGFloat = commit ? 1 : 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints:0.22,0.75,0.24,1)
            outgoing.animator().setFrameOrigin(NSPoint(x:-distance*target,y:0))
            incoming.animator().setFrameOrigin(NSPoint(x:distance*(1-target),y:0))
        }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            completion(); self.finish()
        }
        cleanup = task; DispatchQueue.main.asyncAfter(deadline:.now()+duration,execute:task)
    }

    func run(views: [NSView], towardsRight: Bool, completion: @escaping () -> Void) {
        captureIncoming(views:views,towardsRight:towardsRight); conceal(views)
        settle(commit:true,duration:0.26,completion:completion)
    }

    func finish() {
        guard !finished else { return }; finished = true
        cleanup?.cancel(); cleanup = nil
        for view in concealed { view.alphaValue = 1 }
        concealed.removeAll(); overlay.removeFromSuperview()
    }
    deinit { cleanup?.cancel() }
}
