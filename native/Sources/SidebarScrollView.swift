// SPDX-License-Identifier: MPL-2.0
import AppKit

/// Native scrolling, fading and thumb dragging, with a slender edge-aligned
/// thumb. Its six-point rail is kept outside the tab rows and close buttons.
final class SidebarScroller: NSScroller {
    static let railWidth: CGFloat = 6
    static let thumbWidth: CGFloat = 3
    // AppKit clips overlay artwork to its inset knob surface. Offset the native
    // frame, rather than the tab viewport, to expose the full thumb to the right.
    static let outerOffset: CGFloat = 1.5
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func rect(for part:NSScroller.Part) -> NSRect {
        var rect = super.rect(for:part)
        if !rect.isEmpty {
            rect.origin.x = bounds.maxX-Self.railWidth-Self.outerOffset
            rect.size.width = Self.railWidth
        }
        return rect
    }
    override func drawKnob() {
        let rect = rect(for:.knob)
        guard !rect.isEmpty else { return }
        let thumb = NSRect(x:bounds.maxX-Self.railWidth,
                           y:rect.minY,width:Self.thumbWidth,height:rect.height)
        let dark = knobStyle == .dark || (knobStyle == .default && effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .aqua)
        (dark ? NSColor.black : .white).withAlphaComponent(dark ? 0.42 : 0.5).setFill()
        NSBezierPath(roundedRect:thumb,xRadius:Self.thumbWidth/2,yRadius:Self.thumbWidth/2).fill()
    }
    override func drawKnobSlot(in slotRect:NSRect,highlight flag:Bool) {}
    override func hitTest(_ point:NSPoint) -> NSView? {
        let local = convert(point,from:superview)
        guard local.x >= bounds.maxX-Self.railWidth-Self.outerOffset,
              local.x <= bounds.maxX-Self.outerOffset else { return nil }
        return super.hitTest(point)
    }
}

final class SidebarScrollView: NSScrollView {
    override init(frame:NSRect) {
        super.init(frame:frame)
        verticalScroller = SidebarScroller()
        scrollerStyle = .overlay
    }
    required init?(coder:NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        let local = convert(point, from: superview)
        let clip = contentView
        guard clip.frame.contains(local), contentInsets.bottom > 0, let document = documentView else { return hit }
        let position = clip.convert(local, from: self)
        let distanceFromBottom = clip.isFlipped ? clip.bounds.maxY - position.y : position.y - clip.bounds.minY
        guard distanceFromBottom < contentInsets.bottom else { return hit }
        // AppKit draws an inset backdrop over the document. Route this strip
        // to the table (including its row controls) or the empty clip below it.
        return document.hitTest(position) ?? clip
    }

    override func tile() {
        let bottom = min(144, (bounds.height * 0.25).rounded())
        if contentInsets.bottom != bottom { contentInsets.bottom = bottom }
        super.tile()
        guard hasVerticalScroller, let scroller = verticalScroller else { return }
        var clip = contentView.frame
        clip.size.width = max(0,bounds.width-clip.minX-SidebarScroller.railWidth)
        contentView.frame = clip
        var rail = scroller.frame
        rail.origin.x = bounds.maxX-rail.width+SidebarScroller.outerOffset
        scroller.frame = rail
    }
}
