// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

/// Mounted above Chromium only during a compatible local tab drag. The real
/// page is clipped and translated at compositor speed, keeping its DOM viewport
/// intact until the user actually drops the tab.
final class PageSplitDropView: NSView {
    enum Side { case left, right }

    struct Drag {
        let source: String
        let target: String
        let incomingCount: Int
        let totalCount: Int
    }

    var accepts: ((Drag, NSDraggingInfo) -> Bool)?
    var commit: ((Drag, Side) -> Bool)?
    private(set) var drag: Drag?
    private(set) var side: Side?
    private weak var page: NSView?
    private weak var pageShadow: NSView?
    private let clip = CALayer()
    private let slot = CALayer()
    private var card: NSImage?
    private var lastEdge: Side = .left
    private var retirement: DispatchWorkItem?
    var coveredLeadingWidth: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        isHidden = true
        setAccessibilityElement(false)
        registerForDraggedTypes([.init("local.browser.tab")])
        clip.anchorPoint = .zero
        clip.backgroundColor = NSColor.black.cgColor
        clip.cornerRadius = 6
        slot.anchorPoint = .zero
        slot.cornerRadius = 6
        slot.borderWidth = 1.5
        slot.opacity = 0
        layer?.addSublayer(slot)
    }
    required init?(coder: NSCoder) { fatalError() }

    func begin(_ drag: Drag, page: NSView, shadow: NSView, title: String, icon: NSImage?, dark: Bool) {
        finish(animated: false)
        self.page = page
        self.pageShadow = shadow
        self.drag = drag
        frame = page.frame
        let ink: NSColor = dark ? .white : .black
        slot.borderColor = ink.withAlphaComponent(dark ? 0.30 : 0.22).cgColor
        slot.backgroundColor = ink.withAlphaComponent(0.025).cgColor
        card = Self.makeCard(title: title, icon: icon, dark: dark)
        isHidden = false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        drag == nil ? nil : super.hitTest(point)
    }

    // Leaving a small band around the center empty lets the user back out
    // without having to return all the way to the sidebar.
    static func edge(at x: CGFloat, width: CGFloat, retaining side: Side?) -> Side? {
        guard width > 0, x >= 0, x <= width else { return nil }
        let center = width / 2
        let band = min(34, width * 0.045)
        if x < center - band * (side == .left ? 0.65 : 1) { return .left }
        if x > center + band * (side == .right ? 0.65 : 1) { return .right }
        return nil
    }

    private func update(_ info: NSDraggingInfo) -> NSDragOperation {
        guard let drag, accepts?(drag, info) == true else {
            preview(nil)
            return []
        }
        let point = convert(info.draggingLocation, from: nil)
        let edge = bounds.contains(point) ? Self.edge(at: point.x - coveredLeadingWidth,
            width: bounds.width - coveredLeadingWidth, retaining: side) : nil
        preview(edge)
        return edge == nil ? [] : .move
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = update(sender)
        updateDraggingItemsForDrag(sender)
        return operation
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { preview(nil) }
    override func updateDraggingItemsForDrag(_ sender: NSDraggingInfo?) {
        guard let sender, let drag, accepts?(drag, sender) == true, let card else { return }
        let point = convert(sender.draggingLocation, from: nil)
        let frame = NSRect(x: point.x - card.size.width / 2, y: point.y - card.size.height / 2,
                           width: card.size.width, height: card.size.height)
        sender.enumerateDraggingItems(options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
            item.setDraggingFrame(frame, contents: card)
        }
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        sender.animatesToDestination = false
        return update(sender) == .move
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard update(sender) == .move, let drag, let side else { return false }
        // Reparent the live Chromium containers in the same display transaction
        // that removes the rehearsal, so a full-width page never flashes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        finish(animated: false)
        return commit?(drag, side) == true
    }

    func resize(to frame: NSRect) {
        guard self.frame != frame else { return }
        self.frame = frame
        if page?.layer?.mask === clip { preview(side, animated: false, force: true) }
    }

    private func preview(_ next: Side?, animated: Bool = true, force: Bool = false) {
        guard next != side || force, let drag, let surface = page?.layer else { return }
        let entering = side == nil && next != nil
        side = next
        if let next { lastEdge = next }
        let w = bounds.width
        let gap: CGFloat = 8 // Same divider spacing as the committed SplitHostView.
        let incoming = (w + gap) * CGFloat(drag.incomingCount) / CGFloat(drag.totalCount) - gap
        let slotWidth = next == nil ? 0 : max(0, incoming)
        let pageWidth = next == nil ? w : max(0, w - incoming - gap)
        let translation = next == .left ? w - pageWidth : 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if surface.mask !== clip {
            clip.frame = CGRect(origin: .zero, size: bounds.size)
            surface.mask = clip
        }
        clip.bounds.size.height = bounds.height
        slot.bounds.size.height = bounds.height
        if entering && (slot.presentation()?.opacity ?? slot.opacity) < 0.01 {
            slot.position.x = lastEdge == .left ? 0 : w
            slot.bounds.size.width = 0
        }
        let duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.24 : 0
        move(clip, "bounds.size.width", to: pageWidth, duration: duration)
        move(surface, "transform.translation.x", to: translation, duration: duration)
        if let shadow = pageShadow?.layer { move(shadow, "opacity", to: next == nil ? 1 : 0, duration: duration) }
        move(slot, "position.x", to: lastEdge == .left ? 0 : w - slotWidth, duration: duration)
        move(slot, "bounds.size.width", to: slotWidth, duration: duration)
        move(slot, "opacity", to: next == nil ? 0 : 1, duration: duration)
    }

    private func move(_ layer: CALayer, _ path: String, to value: CGFloat, duration: Double) {
        let from = layer.presentation()?.value(forKeyPath: path) ?? layer.value(forKeyPath: path)
        let key = "page-split-" + path
        layer.removeAnimation(forKey: key)
        layer.setValue(value, forKeyPath: path)
        guard duration > 0 else { return }
        let animation = CABasicAnimation(keyPath: path)
        animation.fromValue = from
        animation.toValue = value
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.82, 0.26, 1)
        layer.add(animation, forKey: key)
    }

    func finish(animated: Bool) {
        retirement?.cancel()
        retirement = nil
        let restoring = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && page?.layer?.mask === clip
        preview(nil, animated: restoring)
        drag = nil
        card = nil
        if restoring {
            let work = DispatchWorkItem { [weak self] in self?.clearPresentation() }
            retirement = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        } else { clearPresentation() }
    }
    private func clearPresentation() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let surface = page?.layer, surface.mask === clip {
            surface.removeAnimation(forKey: "page-split-transform.translation.x")
            surface.setValue(0, forKeyPath: "transform.translation.x")
            surface.mask = nil
        }
        if let shadow = pageShadow?.layer {
            shadow.removeAnimation(forKey: "page-split-opacity")
            shadow.opacity = 1
        }
        clip.removeAllAnimations()
        slot.removeAllAnimations()
        slot.opacity = 0
        isHidden = true
        page = nil
        pageShadow = nil
        CATransaction.commit()
    }

    private static func makeCard(title: String, icon: NSImage?, dark: Bool) -> NSImage {
        // Include the shadow in the drag image; AppKit moves it with the pointer.
        NSImage(size: NSSize(width: 184, height: 270), flipped: true) { rect in
            let box = rect.insetBy(dx: 10, dy: 10)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
            shadow.shadowBlurRadius = 8
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.set()
            NSColor(white: dark ? 0.045 : 0.985, alpha: 0.98).setFill()
            NSBezierPath(roundedRect: box, xRadius: 20, yRadius: 20).fill()
            NSGraphicsContext.restoreGraphicsState()
            icon?.draw(in: NSRect(x: rect.midX - 8, y: rect.midY - 43, width: 16, height: 16),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            let label = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: dark ? NSColor.white : NSColor.black,
                .paragraphStyle: paragraph
            ])
            label.draw(with: NSRect(x: box.minX + 10, y: rect.midY - 4, width: box.width - 20, height: 49),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            return true
        }
    }
}
