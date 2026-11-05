// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

/// The same non-interactive child window can sit above both AppKit and Chromium.
final class SidebarHoverTip {
    enum Target: Equatable { case tab(String), sound(String), space(String) }
    enum Content: Equatable {
        case tab(title:String, hint:String?)
        case space(name:String, keys:[String])
    }
    struct Presentation { let content:Content; let anchor:NSRect } // screen coordinates
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    private weak var parent: NSWindow?
    private var panel: NSPanel?
    private(set) var target: Target?
    private var resolve: (() -> Presentation?)?
    private var pending: DispatchWorkItem?
    private var lastContent: Content?
    init(parent:NSWindow) { self.parent = parent }

    func track(_ next:Target?, resolve:@escaping () -> Presentation?) {
        guard next != target else { return }
        dismiss()
        guard let next else { return }
        target = next; self.resolve = resolve
        let task = DispatchWorkItem { [weak self] in
            guard self?.target == next else { return }; self?.present()
        }
        pending = task
        let delay:Double
        switch next { case .space: delay = 0.95; case .tab, .sound: delay = 0.65 }
        DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:task)
    }
    func refreshIfVisible() { if panel?.isVisible == true { present() } }
    private func present() {
        guard let parent, parent.isKeyWindow, parent.isVisible, let p = resolve?() else { dismiss(); return }
        let screen = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        let same = p.content == lastContent
        let w = panel ?? Panel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        if panel == nil {
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = true; w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false; w.hidesOnDeactivate = true; w.isExcludedFromWindowsMenu = true
            w.isMovable = false; panel = w
        }
        let view = same ? w.contentView! : SidebarTipBubble(p.content,maxSize:screen.insetBy(dx:12,dy:12).size)
        let size = view.frame.size
        var x:CGFloat, y:CGFloat
        switch p.content {
        case .space: x = p.anchor.midX-size.width/2; y = p.anchor.maxY+3
        case .tab:
            x = p.anchor.midX+9; y = p.anchor.midY-10-size.height
            if y < screen.minY+4 { y = p.anchor.midY+12 }
        }
        x = min(max(screen.minX+4,x),screen.maxX-size.width-4)
        y = min(max(screen.minY+4,y),screen.maxY-size.height-4)
        let frame = NSRect(origin:.init(x:round(x),y:round(y)),size:size)
        if !same { w.contentView = view; lastContent = p.content }
        let entering = !w.isVisible
        w.setFrame(frame,display:false)
        if entering {
            let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            w.alphaValue = animated ? 0 : 1; parent.addChildWindow(w,ordered:.above); w.orderFront(nil)
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.14; ctx.timingFunction = CAMediaTimingFunction(name:.easeOut)
                    w.animator().alphaValue = 1
                }
            }
        }
    }
    func dismiss() {
        pending?.cancel(); pending = nil; target = nil; resolve = nil; lastContent = nil
        if let panel { parent?.removeChildWindow(panel); panel.orderOut(nil); self.panel = nil }
    }
    deinit { dismiss() }
}

final class SidebarTipBubble: NSView {
    override var isFlipped:Bool { true }
    private var pointerCorner = false
    override func draw(_ dirtyRect:NSRect) {
        guard pointerCorner, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = bounds.insetBy(dx:0.35,dy:0.35), radius:CGFloat = 13
        // A smaller corner points back towards the cursor, like the reference card.
        let path = CGMutablePath(); path.move(to:.init(x:r.midX,y:r.minY))
        for (corner,next,bend) in [(CGPoint(x:r.maxX,y:r.minY),CGPoint(x:r.maxX,y:r.maxY),radius),
                                   (CGPoint(x:r.maxX,y:r.maxY),CGPoint(x:r.minX,y:r.maxY),radius),
                                   (CGPoint(x:r.minX,y:r.maxY),CGPoint(x:r.minX,y:r.minY),radius),
                                   (CGPoint(x:r.minX,y:r.minY),CGPoint(x:r.midX,y:r.minY),3.0)] {
            path.addArc(tangent1End:corner,tangent2End:next,radius:bend)
        }
        path.closeSubpath(); ctx.addPath(path); ctx.setFillColor(Self.background.cgColor)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor); ctx.setLineWidth(0.7); ctx.drawPath(using:.fillStroke)
    }
    private static let background = NSColor(srgbRed:0.10,green:0.10,blue:0.13,alpha:1)
    init(_ content:SidebarHoverTip.Content,maxSize:NSSize) {
        super.init(frame:.zero)
        wantsLayer = true; layer?.backgroundColor = Self.background.cgColor
        layer?.borderWidth = 0.6; layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.cornerCurve = .continuous; layer?.masksToBounds = true
        let title = NSTextField(wrappingLabelWithString:"")
        title.font = .systemFont(ofSize:12,weight:.semibold); title.textColor = NSColor(white:0.95,alpha:1)
        title.isSelectable = false; title.allowsExpansionToolTips = false
        addSubview(title)
        switch content {
        case .tab(let caption,let hint):
            title.stringValue = caption
            let detail = hint.map { hint -> NSTextField in
                let field = NSTextField(labelWithString:hint)
                field.textColor = NSColor(white:0.66,alpha:1)
                field.font = .systemFont(ofSize:11,weight:.regular); field.sizeToFit(); addSubview(field)
                return field
            }
            let limit = max(64,min(350,maxSize.width-20))
            let width = min(limit,max(ceil(title.attributedStringValue.size().width)+4,detail?.frame.width ?? 0))
            let height = max(15,min(maxSize.height-34,ceil(title.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:width,height:10000)).height)))
            title.frame = NSRect(x:9,y:6,width:width,height:height)
            detail?.frame = NSRect(x:9,y:title.frame.maxY,width:width,height:14)
            setFrameSize(NSSize(width:width+18,height:(detail?.frame.maxY ?? title.frame.maxY)+6))
            pointerCorner = true; layer?.backgroundColor = nil; layer?.borderWidth = 0
        case .space(let name,let keys):
            title.stringValue = name; title.maximumNumberOfLines = 1; title.lineBreakMode = .byTruncatingTail
            var badges:[NSView] = []
            for key in keys {
                let cap = NSView(); cap.wantsLayer = true; cap.layer?.cornerRadius = 3.4; cap.layer?.backgroundColor = NSColor(srgbRed:0.60,green:0.60,blue:0.67,alpha:1).cgColor
                let face = NSTextField(labelWithString:key)
                face.font = .systemFont(ofSize:11,weight:.bold); face.alignment = .center
                face.textColor = NSColor(srgbRed:0.31,green:0.31,blue:0.41,alpha:1)
                face.sizeToFit()
                let w:CGFloat = key.count == 1 ? 18 : max(18,ceil(face.attributedStringValue.size().width)+6)
                cap.frame.size = NSSize(width:w,height:19)
                let top = NSView(frame:NSRect(x:0,y:2,width:w,height:17)); top.wantsLayer = true; top.layer?.cornerRadius = 3
                top.layer?.backgroundColor = NSColor(srgbRed:0.88,green:0.88,blue:0.90,alpha:1).cgColor
                cap.addSubview(top); face.frame = NSRect(x:0,y:2,width:w,height:14); top.addSubview(face)
                addSubview(cap); badges.append(cap)
            }
            let keyWidth = badges.reduce(CGFloat(0)) { $0+$1.frame.width+3 }
            let width = max(24,min(220,maxSize.width-keyWidth-28,ceil(title.attributedStringValue.size().width)+4))
            title.frame = NSRect(x:9,y:6,width:width,height:16)
            var x = title.frame.maxX + (badges.isEmpty ? 0 : 4)
            for badge in badges { badge.frame.origin = .init(x:x,y:4.5); x += badge.frame.width+3 }
            setFrameSize(.init(width:x+(badges.isEmpty ? 9 : 7),height:28)); layer?.cornerRadius = 14
        }
    }
    required init?(coder:NSCoder) { fatalError() }
}
