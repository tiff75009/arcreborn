import AppKit
import QuartzCore

private class FlippedView: NSView { override var isFlipped: Bool { true } }
private final class SidebarSurface: ThemeBackdropView {
    var contextMenu: (() -> NSMenu?)?
    var dragFinished: (() -> Void)?
    override func menu(for event: NSEvent) -> NSMenu? { contextMenu?() }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with:event)
        dragFinished?()
    }
}
private final class SidebarClipView: NSClipView {
    var dragFinished: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with:event)
        dragFinished?()
    }
}
private struct ProfileReload {
    var profileID: String
    var waiting: Set<String>
    var cancelled = false
}
private final class BrowserWindow: NSWindow {
    var undoDeletion: (() -> Bool)?
    var canUndoDeletion: (() -> Bool)?
    @objc func undo(_ sender: Any?) { _ = undoDeletion?() }
    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(undo(_:)) ? canUndoDeletion?() == true : super.validateMenuItem(item)
    }
    var pointerEvent: ((NSEvent) -> Void)?
    var pointerTrackingEnded: (() -> Void)?
    override func sendEvent(_ event: NSEvent) {
        // Buttons, favorite tiles, folder rows and window drags can consume the
        // mouse-up in a nested tracking loop, without calling sendEvent again.
        defer {
            if event.type == .leftMouseDown { pointerTrackingEnded?() }
        }
        switch event.type {
        case .mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp: pointerEvent?(event)
        default: break
        }
        super.sendEvent(event)
    }
}
private final class PointerRootView: FlippedView {
    override var acceptsFirstResponder: Bool { true }
    var appearanceChanged: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); appearanceChanged?() }
    var pointerChanged: ((NSEvent) -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { pointerChanged?(event) }
    override func mouseExited(with event: NSEvent) { pointerChanged?(event) }
    override func mouseMoved(with event: NSEvent) { pointerChanged?(event) }
}
final class FooterSpaceButton: ActionButton {
    var hoverChanged: (() -> Void)?
    private let progressRing = CAShapeLayer(), progressTrack = CAShapeLayer()
    private var transfersActive = false
    private var unreadTransfers = 0
    func updateTransfers(_ records: [LibraryDownload], unread: Int) {
        let active = records.filter(\.isActive); transfersActive = !active.isEmpty; unreadTransfers = unread
        progressRing.isHidden = !transfersActive; progressTrack.isHidden = !transfersActive
        let known = active.filter { $0.total > 0 }
        let total = known.reduce(0.0) { $0+Double($1.total) }
        let received = known.reduce(0.0) { $0+Double($1.received) }
        let fraction = total > 0 ? min(1,received/total) : 0.22
        let old = progressRing.presentation()?.strokeEnd ?? progressRing.strokeEnd
        CATransaction.begin(); CATransaction.setDisableActions(true); progressRing.strokeEnd = max(0.025,fraction); CATransaction.commit()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath:"strokeEnd"); animation.fromValue = old; animation.toValue = progressRing.strokeEnd; animation.duration = 0.24; progressRing.add(animation,forKey:"transfer-progress")
        }
        if transfersActive && known.count != active.count && active.contains(where: { $0.state == "progress" }) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if progressRing.animation(forKey:"indeterminate") == nil {
                let spin = CABasicAnimation(keyPath:"transform.rotation.z"); spin.fromValue = 0; spin.toValue = CGFloat.pi*2; spin.duration = 1.4; spin.repeatCount = .infinity; progressRing.add(spin,forKey:"indeterminate")
            }
        } else { progressRing.removeAnimation(forKey:"indeterminate") }
        needsDisplay = true; needsLayout = true
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let path = CGMutablePath(); path.addArc(center:CGPoint(x:bounds.midX,y:bounds.midY),radius:10,startAngle:-CGFloat.pi/2,endAngle:CGFloat.pi*1.5,clockwise:false)
        for ring in [progressTrack,progressRing] { ring.frame = bounds; ring.path = path; ring.fillColor = NSColor.clear.cgColor; ring.lineWidth = 2.5; ring.lineCap = .round }
        progressRing.strokeColor = ink.cgColor; progressTrack.strokeColor = ink.withAlphaComponent(0.18).cgColor
        CATransaction.commit()
    }
    var dotDiameter: CGFloat = 8 { didSet { needsDisplay = true } }
    var dot = false { didSet { needsDisplay = true } }
    var ink = NSColor.labelColor { didSet { needsDisplay = true; refreshHover() } }
    private var hovered = false
    private var tracking: NSTrackingArea?
    override init(_ title: String = "", symbol: String? = nil, action: @escaping () -> Void) {
        super.init(title,symbol:symbol,action:action)
        wantsLayer = true; layer?.cornerRadius = 8
        layer?.addSublayer(progressTrack); layer?.addSublayer(progressRing); progressTrack.isHidden = true; progressRing.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        if transfersActive {
            ink.setStroke(); let arrow = NSBezierPath(); arrow.lineWidth = 1.5; arrow.lineCapStyle = .round
            let direction: CGFloat = isFlipped ? 1 : -1
            arrow.move(to:NSPoint(x:bounds.midX,y:bounds.midY-5*direction)); arrow.line(to:NSPoint(x:bounds.midX,y:bounds.midY+5*direction)); arrow.move(to:NSPoint(x:bounds.midX-3,y:bounds.midY+2*direction)); arrow.line(to:NSPoint(x:bounds.midX,y:bounds.midY+5*direction)); arrow.line(to:NSPoint(x:bounds.midX+3,y:bounds.midY+2*direction)); arrow.stroke()
        } else if dot {
            ink.withAlphaComponent(0.55).setFill()
            NSBezierPath(ovalIn:NSRect(x:bounds.midX-dotDiameter/2,y:bounds.midY-dotDiameter/2,width:dotDiameter,height:dotDiameter)).fill()
        } else if SpaceIcon.symbol(title) != nil { SpaceIcon.draw(title,in:NSRect(x:bounds.midX-9,y:bounds.midY-9,width:18,height:18),color:ink) } else { super.draw(dirtyRect) }
        if !transfersActive && unreadTransfers > 0 {
            let badge = NSRect(x:bounds.maxX-15,y:isFlipped ? bounds.minY : bounds.maxY-15,width:15,height:15)
            NSColor.systemRed.setFill(); NSBezierPath(ovalIn:badge).fill()
            let text = unreadTransfers > 99 ? "99" : String(unreadTransfers)
            let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:9,weight:.bold),.foregroundColor:NSColor.white]
            let size = (text as NSString).size(withAttributes:attributes)
            (text as NSString).draw(at:NSPoint(x:badge.midX-size.width/2,y:badge.midY-size.height/2),withAttributes:attributes)
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self)
        addTrackingArea(tracking!)
        if let window { setHovered(!isHiddenOrHasHiddenAncestor && bounds.contains(convert(window.mouseLocationOutsideOfEventStream,from:nil))) }
    }
    override func mouseEntered(with event: NSEvent) { trackPointer(event) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    func trackPointer(_ event: NSEvent) {
        setHovered(event.window === window && event.type != .mouseExited && !isHiddenOrHasHiddenAncestor && bounds.contains(convert(event.locationInWindow,from:nil)))
    }
    private func setHovered(_ value: Bool) { guard value != hovered else { return }; hovered = value; refreshHover(); hoverChanged?() }
    func animateLibraryPeek(_ open: Bool) {
        guard let layer else { return }
        layer.shadowColor = ink.cgColor; layer.shadowRadius = open ? 5 : 0; layer.shadowOpacity = open ? 0.65 : 0; layer.shadowOffset = .zero
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let bounce = CAKeyframeAnimation(keyPath:"transform.translation.y")
        bounce.values = open ? [0,-4,1,-1,0] : [0,2,0]; bounce.keyTimes = open ? [0,0.35,0.65,0.82,1] : [0,0.45,1]; bounce.duration = open ? 0.42 : 0.2
        layer.add(bounce,forKey:"library-peek-bounce")
        let glow = CABasicAnimation(keyPath:"shadowOpacity"); glow.fromValue = open ? 0 : 0.65; glow.toValue = open ? 0.65 : 0; glow.duration = 0.25; layer.add(glow,forKey:"library-peek-glow")
    }
    private func refreshHover() {
        let color = ink.withAlphaComponent(hovered ? 0.09 : 0).cgColor
        let previous = layer?.presentation()?.backgroundColor ?? layer?.backgroundColor
        CATransaction.begin(); CATransaction.setDisableActions(true); layer?.backgroundColor = color; CATransaction.commit()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath:"backgroundColor"); animation.fromValue = previous; animation.toValue = color; animation.duration = 0.12
            layer?.add(animation,forKey:"footer-hover")
        }
    }
}
private final class SpaceHeaderButton: ActionButton {
    var suppressHover = false {
        didSet { if suppressHover { hovered = false; refreshTitle() } }
    }
    var spaceName = "", spaceIcon = "◈"
    var collapsed = false
    var ink = NSColor.labelColor
    var accent = NSColor.systemPink
    var moreLabel = ""
    private var hovered = false
    private var tracking: NSTrackingArea?
    private let moreButton = ActionButton("",symbol:"ellipsis",action:{})
    override var isFlipped: Bool { true }
    override init(_ title: String = "", symbol: String? = nil, action: @escaping () -> Void) {
        super.init("",action:action)
        addSubview(moreButton)
        moreButton.invoke = { [weak self] in
            guard let self, let menu = self.menu else { return }
            menu.popUp(positioning:nil,at:NSPoint(x:self.bounds.maxX-24,y:self.bounds.maxY+3),in:self)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    func refreshTitle() {
        // Fixed columns, shared with TabCell, independent of glyph/font metrics.
        title = ""; image = nil
        moreButton.isHidden = !hovered
        moreButton.contentTintColor = ink.withAlphaComponent(0.7)
        moreButton.setAccessibilityLabel(moreLabel); moreButton.toolTip = moreLabel
        needsDisplay = true; needsLayout = true
    }
    override func layout() {
        super.layout()
        moreButton.frame = NSRect(x:bounds.width-34,y:(bounds.height-28)/2,width:28,height:28)
    }
    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            ink.withAlphaComponent(0.065).setFill()
            NSBezierPath(roundedRect:bounds,xRadius:12,yRadius:12).fill()
        }
        let center = NSPoint(x:20,y:bounds.midY)
        if collapsed || hovered {
            let path = NSBezierPath(); path.lineWidth = 1.8; path.lineCapStyle = .round; path.lineJoinStyle = .round
            if collapsed {
                path.move(to:NSPoint(x:center.x-2,y:center.y-4.5)); path.line(to:NSPoint(x:center.x+2.5,y:center.y)); path.line(to:NSPoint(x:center.x-2,y:center.y+4.5))
            } else {
                path.move(to:NSPoint(x:center.x-4.5,y:center.y-2)); path.line(to:NSPoint(x:center.x,y:center.y+2.5)); path.line(to:NSPoint(x:center.x+4.5,y:center.y-2))
            }
            ink.withAlphaComponent(0.65).setStroke(); path.stroke()
        } else {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            SpaceIcon.draw(spaceIcon,in:NSRect(x:11,y:bounds.midY-9,width:18,height:18),color:accent)
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        NSAttributedString(string:spaceName,attributes:[.font:NSFont.systemFont(ofSize:14,weight:.semibold),.foregroundColor:ink.withAlphaComponent(0.65),.paragraphStyle:paragraph]).draw(in:NSRect(x:37,y:bounds.midY-9.5,width:max(0,bounds.width-78),height:20))
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { trackPointer(event) }
    override func mouseExited(with event: NSEvent) { hovered = false; refreshTitle() }
    func trackPointer(_ event: NSEvent) {
        let inside = !suppressHover && event.type != .mouseExited && event.window === window && !isHiddenOrHasHiddenAncestor && bounds.contains(convert(event.locationInWindow,from:nil))
        guard inside != hovered else { return }
        hovered = inside; refreshTitle()
    }
}
private final class ActionPopUp: NSPopUpButton {
    var invoke: (() -> Void)?
    init(items: [String], action: @escaping () -> Void) {
        super.init(frame: .zero, pullsDown: false); addItems(withTitles: items); invoke = action; target = self; self.action = #selector(invokeAction)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invokeAction() { invoke?() }
}
private final class SidebarTable: NSTableView {
    var context: ((Int) -> NSMenu?)?
    var clicked: ((Int) -> Void)?
    var dragExited: (() -> Void)?
    var mouseTrackingEnded: (() -> Void)?
    var didDrag = false
    var handlingMouseDown = false
    private(set) var clickedTitle = false
    var insertion: (row: Int, depth: Int, inside: Bool)? { didSet { needsDisplay = true } }
    var insertionColor = NSColor.controlAccentColor
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        // NSTableView normally delays text editing and may reclaim the click for
        // row selection/dragging. Once editing starts, the text system owns it.
        if responder is SplitTabChip { return true }
        if let field = responder as? TabTitleField { return field.isEditable }
        if let editor = responder as? NSTextView, editor.isFieldEditor, editor.isDescendant(of: self) { return true }
        return super.validateProposedFirstResponder(responder, for: event)
    }
    override func mouseDown(with event: NSEvent) {
        didDrag = false; handlingMouseDown = true
        defer {
            handlingMouseDown = false
            // NSTableView can consume mouseUp inside its own tracking loop.
            mouseTrackingEnded?()
        }
        let point = convert(event.locationInWindow, from: nil)
        let hitRow = row(at: point)
        if hitRow < 0 {
            window?.performDrag(with:event)
            return
        }
        let cell = hitRow >= 0 ? view(atColumn: 0, row: hitRow, makeIfNecessary: false) as? TabCell : nil
        clickedTitle = cell.map { $0.titleLabel.frame.contains($0.convert(event.locationInWindow, from: nil)) } ?? false
        if clickedTitle, let cell, cell.isEditingTitle {
            cell.titleLabel.mouseDown(with: event)
            return
        }
        let pressesTab = cell?.rename != nil && cell?.isEditingTitle == false
        if pressesTab { cell?.setPressed(true); CATransaction.flush() }
        super.mouseDown(with:event)
        if pressesTab {
            // Selection may rebuild the row. Transfer the release to its current
            // view, keeping the press held throughout AppKit's mouse tracking.
            let current = hitRow >= 0 && hitRow < numberOfRows ? view(atColumn:0,row:hitRow,makeIfNecessary:false) as? TabCell : nil
            if current !== cell { cell?.resetPress() }
            if !didDrag { current?.setPressed(false, fromHeld: current !== cell) }
            else { cell?.resetPress(); current?.resetPress() }
        }
    }
    @objc func handleClick(_ sender: Any?) {
        guard !didDrag else { return }
        clicked?(clickedRow)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { super.draggingExited(sender); insertion = nil; dragExited?() }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let marker = insertion else { return }
        let rowRect = marker.row < numberOfRows ? rect(ofRow:marker.row) : NSRect(x:0,y:numberOfRows > 0 ? rect(ofRow:numberOfRows-1).maxY+1 : 0,width:bounds.width,height:0)
        let x = min(bounds.width-30,10+CGFloat(marker.depth)*16)
        if marker.inside {
            let box = NSBezierPath(roundedRect:NSRect(x:x-4,y:rowRect.minY+1,width:bounds.width-x,height:rowRect.height-2),xRadius:8,yRadius:8)
            insertionColor.withAlphaComponent(0.18).setFill(); box.fill()
            insertionColor.withAlphaComponent(0.85).setStroke(); box.lineWidth = 1.5; box.stroke()
        } else {
            insertionColor.setStroke(); insertionColor.setFill()
            let y = max(2,rowRect.minY-1)
            let path = NSBezierPath(); path.lineWidth = 2; path.move(to:NSPoint(x:x,y:y)); path.line(to:NSPoint(x:bounds.width-6,y:y)); path.stroke()
            NSBezierPath(ovalIn:NSRect(x:x-3,y:y-3,width:6,height:6)).fill()
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? { context?(row(at: convert(event.locationInWindow, from: nil))) }
}
private final class ResizeStrip: NSView {
    var width: (() -> Double)?
    var begin: (() -> Void)?
    var change: ((Double) -> Void)?
    var end: (() -> Void)?
    private var gesture: SidebarResizeGesture?
    private let alignmentLine = CALayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        alignmentLine.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        alignmentLine.cornerRadius = 1
        alignmentLine.shadowColor = NSColor.white.cgColor
        alignmentLine.shadowOpacity = 0.5
        alignmentLine.shadowRadius = 3
        alignmentLine.shadowOffset = .zero
        alignmentLine.opacity = 0
        layer?.addSublayer(alignmentLine)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        alignmentLine.frame = CGRect(x: 7, y: 8, width: 2, height: max(0, bounds.height-16))
        CATransaction.commit()
    }
    private func showAlignment(_ visible: Bool) {
        let opacity: Float = visible ? 1 : 0
        guard alignmentLine.opacity != opacity else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = alignmentLine.presentation()?.opacity ?? alignmentLine.opacity
        animation.toValue = opacity
        animation.duration = visible ? 0.10 : 0.18
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        alignmentLine.opacity = opacity
        CATransaction.commit()
        alignmentLine.add(animation, forKey: "alignment")
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func mouseDown(with event: NSEvent) {
        begin?()
        gesture = SidebarResizeGesture(width: width?() ?? SidebarSizing.standard,
                                       pointerX: Double(event.locationInWindow.x))
        showAlignment(SidebarSizing.clamp(width?() ?? SidebarSizing.standard) == SidebarSizing.standard)
        NSCursor.resizeLeftRight.set()
    }
    override func mouseDragged(with event: NSEvent) {
        guard var gesture else { return }
        let result = gesture.update(pointerX: Double(event.locationInWindow.x))
        self.gesture = gesture
        NSCursor.resizeLeftRight.set()
        change?(result.width)
        showAlignment(result.width == SidebarSizing.standard)
        if result.alignment {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard gesture != nil else { return }
        gesture = nil
        showAlignment(false)
        end?()
        window?.invalidateCursorRects(for: self)
    }
}
private final class FavoritesHint: FlippedView {
    var acceptTab: ((String) -> Bool)?
    var ink = NSColor.black
    var accent = NSColor.systemPink
    let star = NSImageView(), heading = NSTextField(labelWithString: ""), detail = NSTextField(wrappingLabelWithString: "")
    let dismiss = ActionButton("", symbol: "xmark", action: {})
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([NSPasteboard.PasteboardType("local.browser.tab")])
        star.image = NSImage(systemSymbolName: "star.circle.fill", accessibilityDescription: nil)
        heading.font = .systemFont(ofSize: 13, weight: .semibold); heading.alignment = .center
        detail.font = .systemFont(ofSize: 12); detail.alignment = .center
        for v in [star, heading, detail, dismiss] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        star.frame = NSRect(x: bounds.midX-9, y: 12, width: 18, height: 18)
        heading.frame = NSRect(x: 10, y: 36, width: bounds.width-20, height: 20)
        detail.frame = NSRect(x: 20, y: 56, width: bounds.width-40, height: 35)
        dismiss.frame = NSRect(x: bounds.width-25, y: 7, width: 19, height: 19)
        star.contentTintColor = accent; heading.textColor = ink; detail.textColor = ink.withAlphaComponent(0.68); dismiss.contentTintColor = ink.withAlphaComponent(0.7)
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.7, dy: 0.7), xRadius: 12, yRadius: 12)
        NSColor.white.withAlphaComponent(0.16).setFill(); path.fill()
        NSColor.white.withAlphaComponent(0.32).setStroke(); path.lineWidth = 1; path.stroke()
        accent.withAlphaComponent(0.30).setStroke(); path.setLineDash([5,5], count: 2, phase: 0); path.stroke()
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("local.browser.tab")) == nil ? [] : .move }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { guard let id = sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("local.browser.tab")) else { return false }; return acceptTab?(id) ?? false }
}
private final class TabCloseButton: ActionButton {
    private var hovered = false
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let ink = contentTintColor ?? .labelColor
        if hovered {
            ink.withAlphaComponent(isHighlighted ? 0.20 : 0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        ink.withAlphaComponent(hovered ? 1 : 0.7).setStroke()
        let path = NSBezierPath(); path.lineWidth = 1.8; path.lineCapStyle = .round
        let x = bounds.midX, y = bounds.midY, r: CGFloat = 4.5
        path.move(to: NSPoint(x:x-r,y:y-r)); path.line(to:NSPoint(x:x+r,y:y+r))
        path.move(to: NSPoint(x:x-r,y:y+r)); path.line(to:NSPoint(x:x+r,y:y-r)); path.stroke()
    }
}
private final class TabTitleField: NSTextField {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: isEditable ? .iBeam : .arrow)
    }
}
private final class TabCell: NSTableCellView, NSTextFieldDelegate {
    private let developerOutline = DeveloperTabOutline()
    var developerMode = false { didSet { needsLayout = true } }
    private let pressedScale: CGFloat = 0.975
    func resetPress() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.transform = CATransform3DIdentity; layer?.removeAnimation(forKey:"tab-press")
        CATransaction.commit()
    }
    func setPressed(_ pressed: Bool, fromHeld: Bool = false) {
        guard let layer else { return }
        let start = fromHeld ? pressTransform(pressedScale) : (layer.presentation()?.transform ?? layer.transform)
        let target = pressed ? pressTransform(pressedScale) : CATransform3DIdentity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = target
        layer.removeAnimation(forKey:"tab-press")
        CATransaction.commit()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let motion: CABasicAnimation
        if pressed {
            motion = CABasicAnimation(keyPath:"transform")
            motion.duration = 0.11
            motion.timingFunction = CAMediaTimingFunction(name:.easeOut)
        } else {
            let spring = CASpringAnimation(keyPath:"transform")
            spring.mass = 1; spring.stiffness = 460; spring.damping = 25
            spring.duration = min(0.42,spring.settlingDuration)
            motion = spring
        }
        motion.fromValue = NSValue(caTransform3D:start)
        motion.toValue = NSValue(caTransform3D:target)
        layer.add(motion,forKey:"tab-press")
    }
    private func pressTransform(_ scale: CGFloat) -> CATransform3D {
        // AppKit owns the backing layer's anchor; compensate around its center.
        let anchor = layer?.anchorPoint ?? .zero
        let dx = bounds.width * (0.5-anchor.x), dy = bounds.height * (0.5-anchor.y)
        return CATransform3DScale(CATransform3DMakeTranslation(dx*(1-scale),dy*(1-scale),0),scale,scale,1)
    }
    private let titleEditingBackground = CALayer()
    let icon = NSImageView(); let titleLabel = TabTitleField(frame: .zero); let closeButton: ActionButton
    var rename: ((String) -> Void)?
    var titleEditingEnded: (() -> Void)?
    private(set) var isEditingTitle = false
    private var originalTitle = ""
    var depth = 0 { didSet { needsLayout = true } }
    var isFolder = false { didSet { needsLayout = true } }
    var active = false { didSet { updateLayer() } }
    var ink = NSColor.black { didSet { titleLabel.textColor = ink; icon.contentTintColor = ink.withAlphaComponent(0.6); closeButton.contentTintColor = ink } }
    var canClose = false { didSet { closeButton.isHidden = isEditingTitle || !canClose || !hovered } }
    private var hovered = false
    private var tracking: NSTrackingArea?
    override init(frame frameRect: NSRect) {
        closeButton = TabCloseButton("", symbol: "xmark", action: {})
        super.init(frame: frameRect)
        wantsLayer = true; layer?.cornerRadius = 12
        titleEditingBackground.cornerRadius = 7
        titleEditingBackground.borderWidth = 1
        titleEditingBackground.isHidden = true
        titleEditingBackground.actions = ["bounds": NSNull(), "position": NSNull(), "hidden": NSNull()]
        layer?.insertSublayer(titleEditingBackground, at: 0)
        titleLabel.font = .systemFont(ofSize: 14); titleLabel.lineBreakMode = .byTruncatingTail; titleLabel.maximumNumberOfLines = 1
        titleLabel.isEditable = false; titleLabel.isSelectable = false
        titleLabel.isBordered = false; titleLabel.isBezeled = false; titleLabel.drawsBackground = false
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.delegate = self; titleLabel.focusRingType = .none
        addSubview(icon); addSubview(titleLabel); addSubview(closeButton)
        layer?.addSublayer(developerOutline)
    }
    required init?(coder: NSCoder) { fatalError() }
    func beginTitleEditing() {
        guard rename != nil, !isEditingTitle else { return }
        originalTitle = titleLabel.stringValue; isEditingTitle = true
        titleLabel.isEditable = true; titleLabel.isSelectable = true
        window?.invalidateCursorRects(for: titleLabel)
        closeButton.isHidden = true
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateLayer()
        // makeFirstResponder already creates the field editor. Calling
        // NSTextField.selectText again ends that editing session first.
        window?.makeFirstResponder(titleLabel)
        if let editor = titleLabel.currentEditor() as? NSTextView {
            // The shared field editor can retain an opaque background from
            // another control. Keep our rounded editing surface visible.
            editor.drawsBackground = false
            editor.backgroundColor = .clear
            editor.focusRingType = .none
            editor.insertionPointColor = ink
            editor.setSelectedRange(NSRange(location:0,length:(editor.string as NSString).length))
        }
    }
    private func finishTitleEditing(cancelled: Bool) {
        guard isEditingTitle else { return }
        let name = titleLabel.currentEditor()?.string ?? titleLabel.stringValue
        isEditingTitle = false
        titleLabel.stringValue = cancelled ? originalTitle : name
        titleLabel.isEditable = false; titleLabel.isSelectable = false
        window?.invalidateCursorRects(for: titleLabel)
        closeButton.isHidden = !canClose || !hovered
        needsLayout = true
        updateLayer()
        let ended = titleEditingEnded; titleEditingEnded = nil; ended?()
        if cancelled { titleLabel.stringValue = originalTitle }
        else if name != originalTitle { rename?(name) }
    }
    func controlTextDidEndEditing(_ notification: Notification) { finishTitleEditing(cancelled: false) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            finishTitleEditing(cancelled: true); window?.makeFirstResponder(nil); return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            finishTitleEditing(cancelled: false); window?.makeFirstResponder(nil); return true
        }
        return false
    }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self); addTrackingArea(tracking!) }
    override func mouseEntered(with event: NSEvent) { hovered = true; closeButton.isHidden = isEditingTitle || !canClose; updateLayer() }
    override func mouseExited(with event: NSEvent) { hovered = false; closeButton.isHidden = true; updateLayer() }
    override func layout() {
        super.layout()
        developerOutline.update(in:bounds,enabled:developerMode)
        let indent = CGFloat(min(depth,8))*16, size: CGFloat = isFolder ? 20 : 16
        icon.frame = NSRect(x:20-size/2+indent,y:(bounds.height-size)/2,width:size,height:size)
        closeButton.frame = NSRect(x:bounds.width-28,y:(bounds.height-22)/2,width:22,height:22)
        // NSTextField adds a 2 pt text inset; align its glyphs with the header at x = 37.
        if isEditingTitle {
            // A separate layer adds padding without intercepting the native field editor.
            let fieldRect = NSRect(x:32+indent,y:(bounds.height-28)/2,width:max(0,bounds.width-40-indent),height:28)
            titleEditingBackground.frame = fieldRect
            titleLabel.frame = NSRect(x:fieldRect.minX+6,y:(bounds.height-19)/2,width:max(0,fieldRect.width-12),height:19)
        } else {
            titleLabel.frame = NSRect(x:35+indent,y:(bounds.height-19)/2,width:max(0,bounds.width-67-indent),height:19)
        }
    }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        let lightInk = (ink.usingColorSpace(.sRGB)?.redComponent ?? 0) > 0.8
        titleEditingBackground.isHidden = !isEditingTitle
        titleEditingBackground.backgroundColor = ink.withAlphaComponent(0.07).cgColor
        titleEditingBackground.borderColor = ink.withAlphaComponent(0.22).cgColor
        layer?.backgroundColor = active ? NSColor.white.withAlphaComponent(lightInk ? 0.18 : 0.84).cgColor : (hovered ? NSColor.white.withAlphaComponent(0.12).cgColor : NSColor.clear.cgColor)
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = active ? 0.12 : 0; layer?.shadowRadius = 1; layer?.shadowOffset = NSSize(width: 0, height: -1)
    }
}
private struct TabStatus { var progress: Double = 0; var hasLoaded = false; var loading = false; var back = false; var forward = false; var error: NavigationFailure? }
private enum SidebarRow { case tab(String), folder(String), heading(String), newTab }
private final class MenuAction: NSObject { let kind: String; let id: String; let value: String; init(_ kind: String, _ id: String, _ value: String = "") { self.kind = kind; self.id = id; self.value = value } }

final class BrowserController: NSObject, NSWindowDelegate, BrowserEngineDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let window: NSWindow
    private var session: BrowserSession
    private let store: SessionStore
    let windowID: String
    let windowKind: BrowserWindowKind
    let isPrivateWindow: Bool
    private let engine: WindowBrowserEngine
    var becameKey: ((BrowserController)->Void)?
    var windowClosed: ((BrowserController)->Void)?
    var newWindowRequested: ((BrowserWindowKind)->Void)?
    var privateAddressRequested: ((String)->Void)?
    var windowAddressRequested: ((String)->Void)?
    var promoteWindowRequested: (()->Void)?
    private var windowChrome: WindowChromeBar?
    private var closingWindow = false
    private var closeParticipants = Set<String>()
    private var closeWaiting = Set<String>()
    private var windowCloseCancelled = false
    private lazy var pictureInPicture = PictureInPictureController(engine:engine)
    private var preferencesWindow: BrowserPreferencesWindow?
    private var welcomeWindow: WelcomeWindow?
    private var extensionTabReservations: [String: ExtensionTabReservation] = [:]
    private let root = PointerRootView()
    private let sidebarHost = SidebarSurface()
    private var profileReloads: [String: ProfileReload] = [:]
    private var sharingPicker: NSSharingServicePicker?
    private var sidebarRevealed = false
    private var sidebarTransition = 0
    private var sidebarAnimating = false
    private var sidebarHoverTask: DispatchWorkItem?
    private var backgroundSidebarTimer: Timer?
    private var sidebarPendingIntent: SidebarRevealIntent?
    private var sidebarObservers: [NSObjectProtocol] = []
    private var trackingMenus = 0
    private var sidebarPointer: NSPoint?
    private var sidebarMousePressed = false
    private let sidebar = NSVisualEffectView()
    private let sidebarTint = ThemeBackdropView()
    private let toolbar = FlippedView()
    // Transparent so the space gradient and grain continue seamlessly across the window.
    private let classicHeader = FlippedView()
    private let addressMark = NSImageView()
    private let privateBadge = NSTextField(labelWithString:"")
    private var classicPresentation = false
    private var usesClassicInterface: Bool { windowKind != .compact && session.currentInterface == .classic }

    private let content = NSView()
    private let splitHost = SplitHostView()
    private var developerBars: [String:DeveloperToolbar] = [:]
    private var portraitCapture: PortraitCapture?
    private var pageCapture: PageCapture?
    private var pendingCaptures = Set<String>()
    private var splitDropTarget: String?
    private var splitLimitTarget: String?
    private var splitActionsMenu: NSMenu?
    private let pageShadow = NSView()
    private let home = BrowserLandingView(frame:.zero)
    private let rowsScroll = NSScrollView()
    private let table = SidebarTable()
    private weak var sidebarTitleEditor: TabCell?
    private let favorites = FavoritesGrid(frame:.zero)
    private let favoritesHint = FavoritesHint(frame: .zero)
    private let addressBackground = FlippedView()
    private let pageLoad = PageLoadIndicator(frame: .zero)
    private var copyLinkButton: CopyLinkButton!
    private var siteMenuButton: NavigationButton!
    private var siteMenu: SiteMenu?
    private lazy var extensionCatalog = ExtensionCatalog(directory:store.directory,liveSettings:{ [weak self] profile in self?.engine.extensionSettings(profile:profile) })
    private var extensionInstallNotice:ExtensionInstallNotice?
    private var extensionButtons:[ExtensionActionButton] = []
    private var overflowExtensions:[BrowserExtension] = []
    private lazy var extensionOverflowButton:NavigationButton = {
        let button = NavigationButton("",symbol:"ellipsis") { [weak self] in self?.showExtensionOverflow() }
        button.isHidden = true
        return button
    }()
    private var extensionSignature = ""
    private let faviconCache: FaviconCache
    private var hintDismissed = UserDefaults.standard.bool(forKey: "BrowserFavoritesHintDismissed")
    private let spacesFooter = FlippedView()
    private let spaceIndicators = HorizontalSpaceScrollView()
    private var spaceScrollMonitor: Any?
    private let spaceIndicatorContent = FlippedView()
    private var spaceSwipe = SpaceSwipeState()
    private var swipeTarget: String?
    private var swipeProgress: CGFloat = 0
    private var swipeSettling = false
    private var swipeReleaseTask: DispatchWorkItem?
    private var swipeNeedsRender = false
    private var completingSpaceSwipe = false
    private var copyingSpaceRows = false
    private let addButton = AddMenuButton(frame:.zero)
    private var addMenu: AddMenuPopover?
    private let resizeStrip = ResizeStrip()
    private let sidebarItems = SidebarPeekContent(frame:.zero)
    private let recentPeek = RecentMediaPeek(frame:.zero)
    private var recentPeekVisible = false
    private var recentPeekTask: DispatchWorkItem?
    private var recentPeekPending: Bool?
    private var library: LibraryView?
    private var libraryTransition = 0
    private var libraryClosing = false
    private static let downloadRunID = UUID().uuidString
    private var downloadRun:String { Self.downloadRunID }
    private lazy var libraryStore = LibraryStore(directory:store.directory,downloadsDirectory:ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DOWNLOADS"].map { URL(fileURLWithPath:$0) },persistent:!isPrivateWindow)
    private var rows: [SidebarRow] = []
    private var sidebarCollapse = SidebarCollapseState()
    private var treeRows: [SidebarTreeRow] = []
    private var sidebarDragActive = false
    private var favoriteDragBaseline: CGFloat = 0
    private var dropDestination: SidebarDestination?
    private var dropItem: SidebarItem?
    private var lastDropFeedback: SidebarDestination?
    private let folderDragType = NSPasteboard.PasteboardType("local.browser.folder")
    private var containers: [String: NSView] = [:]
    private var status: [String: TabStatus] = [:]
    private var backButton: NavigationButton!
    private var forwardButton: NavigationButton!
    private var reloadButton: ReloadButton!
    private var sidebarButton: ActionButton!
    private var addressButton: ActionButton!
    private var spaceButton: SpaceHeaderButton!
    private var folderButton: ActionButton!
    private var downloadButton: ActionButton!
    private var findField: NSSearchField!
    private var findClose: ActionButton!
    private var isFinding = false
    private var saveTask: DispatchWorkItem?
    private var lastSaveError: String?
    private var sheet: NSPanel?
    private var commandPalette: CommandPalette?
    private var iconPicker: SpaceIconPicker?
    private var themeEditor: ThemeEditor?
    private var spaceCreation: SpaceCreationView?
    private var spaceCreationClosing = false
    private var spaceSwitch: SpaceSwitchTransition?
    private var renderingSpaceSwitch = false
    private var themeRenderTask: DispatchWorkItem?
    private var appliedAppearance: ThemeAppearance?
    private var isRendering = false
    private var isQuitting = false
    private var quitCancellationObserver: NSObjectProtocol?
    private var pendingSpaceClosures: [String: Set<String>] = [:]
    private var deletionUndo: [DeletionUndo] = []
    private var destructiveClosing = Set<String>()
    private let undoToast = UndoToast()
    private let dragType = NSPasteboard.PasteboardType("local.browser.tab")
    private let palette = ["#B367A5", "#A5C4DD", "#A6C9BB", "#E2C1A5", "#B5B3E6", "#B6BFD2"]

    init(session: BrowserSession, store: SessionStore, windowID:String = UUID().uuidString, kind:BrowserWindowKind = .normal, privateWindow:Bool = false) {
        self.windowID = windowID; windowKind = kind; isPrivateWindow = privateWindow
        engine = WindowBrowserEngine(windowID:windowID)
        self.session = session; self.store = store
        faviconCache = FaviconCache(directory:store.directory,persistent:!privateWindow)
        window = BrowserWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        engine.delegate = self; window.delegate = self
        for profile in session.profiles { _ = configureEngine(profile.engine,profileID:profile.id) }
        (window as? BrowserWindow)?.undoDeletion = { [weak self] in self?.undoLastDeletion() ?? false }
        (window as? BrowserWindow)?.canUndoDeletion = { [weak self] in self?.deletionUndo.isEmpty == false }
        undoToast.undo = { [weak self] in _ = self?.undoLastDeletion() }
        quitCancellationObserver = NotificationCenter.default.addObserver(forName: Notification.Name("BrowserEngineQuitCancelled"), object: nil, queue: .main) { [weak self] _ in
            // Return from CEF's beforeunload callback before restoring any lazy view.
            DispatchQueue.main.async {
                guard let self else { return }
                self.isQuitting = false
                self.closingWindow = false; self.closeParticipants.removeAll(); self.closeWaiting.removeAll()
                self.pictureInPicture.resume()
                self.pendingClose.removeAll()
                self.pendingSpaceClosures.removeAll()
                self.showSelectedTab()
            }
        }
        window.title = "Arc Reborn"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true; window.minSize = NSSize(width: 760, height: 540)
        window.isReleasedWhenClosed = false; window.contentView = root; window.center()
        for tab in session.tabs {
            if let profile = session.profile(forSpace:tab.spaceID)?.id {
                faviconCache.restore(id:tab.id,url:tab.url,profile:profile)
            }
        }
        buildInterface()
        libraryStore.control = { [weak self] id,action in
            guard let self, id.hasPrefix(self.downloadRun+"-"), let number = UInt(id.dropFirst(self.downloadRun.count+1)) else { return }
            self.engine.controlDownload(number,action:action)
        }
        libraryStore.downloadsChanged = { [weak self] in self?.updateDownloadIndicator() }
        recentPeek.transferAction = { [weak self] in self?.libraryStore.request($0,action:$1) }
        recentPeek.transferRemove = { [weak self] in self?.libraryStore.removeDownload($0) }
        recentPeek.removeRecent = { [weak self] in self?.libraryStore.dismissRecentFile($0) }
        recentPeek.transferSeen = { [weak self] in self?.libraryStore.acknowledge([$0]) }
        recentPeek.showDownloads = { [weak self] in self?.showLibrary(); self?.library?.switchSection(.downloads) }
        if kind == .compact || privateWindow {
            let bar = WindowChromeBar(compact:kind == .compact,privateWindow:privateWindow,language:session.language,
                back:{ [weak self] in self?.backAction(nil) },forward:{ [weak self] in self?.forwardAction(nil) },reload:{ [weak self] in self?.reloadAction(nil) },expand:{ [weak self] in self?.promoteWindowRequested?() })
            bar.navigate = { [weak self] value in self?.navigate(value,newTab:false) }
            windowChrome = bar; root.addSubview(bar)
        }
        if kind == .compact {
            window.minSize = NSSize(width:540,height:380); window.setContentSize(NSSize(width:760,height:560)); window.center()
        }
        updateDownloadIndicator(); render(); layout()
    }
    deinit {
        if let spaceScrollMonitor { NSEvent.removeMonitor(spaceScrollMonitor) }
        if let observer = quitCancellationObserver { NotificationCenter.default.removeObserver(observer) }
        sidebarHoverTask?.cancel(); recentPeekTask?.cancel()
        backgroundSidebarTimer?.invalidate()
        sidebarObservers.forEach(NotificationCenter.default.removeObserver)
    }
    private func t(_ key: String) -> String { L10n.text(key, language: session.language) }
    private var activeSpace: NativeSpace? { session.spaces.first { $0.id == session.activeSpaceID } }
    private var currentEngine: SearchEngine { session.profile(forSpace:session.activeSpaceID)?.engine ?? .google }
    @discardableResult private func configureEngine(_ value:SearchEngine,profileID:String) -> Bool {
        let spec = value.spec
        return engine.setSearchProvider(spec.chromiumID,name:spec.name,keyword:spec.keyword,templateURL:value.chromiumTemplate,profile:profileID)
    }
    private var activeTab: NativeTab? { session.tabs.first { $0.id == activeSpace?.selectedTabID } }
    private var sidebarInk: NSColor {
        if darkTheme { return NSColor(white:0.95,alpha:1) }
        let c = tint().usingColorSpace(.sRGB) ?? .systemPurple
        let lightness = 0.2126*c.redComponent+0.7152*c.greenComponent+0.0722*c.blueComponent
        return lightness < 0.13 ? NSColor(white: 0.96, alpha: 1) : NSColor(srgbRed: c.redComponent*0.24, green: c.greenComponent*0.14, blue: c.blueComponent*0.25, alpha: 1)
    }
    private var showFavoritesHint: Bool { !hintDismissed && !sidebarDragActive && !session.tabs.contains { $0.favorite } }
    private func style(_ button: NSButton, opacity: CGFloat = 1) {
        let color = sidebarInk.withAlphaComponent(opacity)
        button.contentTintColor = color
        if button.title.isEmpty { button.imagePosition = .imageOnly; if let image = button.image { button.image = image.withSymbolConfiguration(.init(pointSize: 17, weight: .regular)) ?? image } }
        button.attributedTitle = NSAttributedString(string: button.title, attributes: [.font: button.font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: color])
    }
    private var darkTheme: Bool { window.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua }
    private func tint() -> NSColor { (NSColor(browserHex: activeSpace?.color ?? palette[0]) ?? .systemPurple).themeTone(dark:darkTheme) }
    private func applyTheme() {
        let mode = session.themeAppearance ?? .automatic
        if appliedAppearance != mode {
            appliedAppearance = mode
            window.appearance = mode == .automatic ? nil : NSAppearance(named:mode == .dark ? .darkAqua : .aqua)
            NSApp.appearance = window.appearance
            engine.setAppearanceMode(mode == .dark ? 2 : mode == .light ? 1 : 0)
        }
        let theme = activeSpace?.theme ?? .solid(activeSpace?.color ?? palette[0])
        if renderingSpaceSwitch && !completingSpaceSwipe {
            sidebarTint.transition(to:theme,dark:darkTheme)
            sidebarHost.transition(to:theme,dark:darkTheme)
        } else {
            sidebarTint.theme = theme; sidebarTint.dark = darkTheme
            sidebarHost.theme = theme; sidebarHost.dark = darkTheme
        }
    }
    func show() {
        guard !isQuitting else { return }
        if ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"] != nil,
           ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_BACKGROUND"] == "1" { showSelectedTab(); return }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if !session.onboardingComplete { DispatchQueue.main.async { [weak self] in self?.showOnboarding() } }
        else { showSelectedTab() }
    }
    func showPreferencesPreview(profiles:Bool,interface:Bool = false) {
        guard ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"] != nil, session.onboardingComplete else { return }
        settingsAction(nil)
        if interface { preferencesWindow?.showInterface() }
        else if profiles { preferencesWindow?.showProfiles() } else { preferencesWindow?.showAccount() }
    }
    func prepareToQuit() -> Bool {
        pageCapture?.close()
        finishSpaceSwitch()
        preferencesWindow?.close()
        dismissRecentPeek(animated:false); undoToast.dismiss(animated:false); library?.dispose(); libraryStore.flush()
        cancelSidebarHover()
        commandPalette?.close(); siteMenu?.close()
        themeEditor?.close(animated:false); themeRenderTask?.cancel()
        saveTask?.cancel()
        do { try store.save(session); faviconCache.flush(); pictureInPicture.stop(); engine.closeExtensionPopup(); extensionInstallNotice?.close(); isQuitting = true; return true }
        catch { showError(t("saveError"), detail: error.localizedDescription); return false }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { requestWindowClose(); return false }
    func windowDidResize(_ notification: Notification) {
        finishSpaceSwitch()
        sidebarTransition += 1; sidebarAnimating = false
        sidebarHost.layer?.removeAllAnimations()
        layout()
    }
    func windowDidResignKey(_ notification: Notification) { updateRecentPeekHover(); updateSidebarHover() }
    func windowDidBecomeKey(_ notification: Notification) { becameKey?(self); updateSidebarHover() }
    private func persist() {
        session.repairTabSelections()
        session.normalizeSplits()
        guard !isQuitting else { return }
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.isQuitting else { return }
            do { try self.store.save(self.session); self.lastSaveError = nil }
            catch { if self.lastSaveError != error.localizedDescription { self.lastSaveError = error.localizedDescription; self.showError(self.t("saveError"), detail: error.localizedDescription) } }
        }
        saveTask = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
    }
    private func buildInterface() {
        root.appearanceChanged = { [weak self] in
            DispatchQueue.main.async { [weak self] in guard let self, !self.isQuitting else { return }; self.render() }
        }
        root.wantsLayer = true; content.wantsLayer = true; content.layer?.cornerRadius = 6; content.layer?.masksToBounds = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        sidebar.material = .sidebar; sidebar.blendingMode = .behindWindow; sidebar.state = .active; sidebar.isHidden = true
        sidebarTint.wantsLayer = true
        pageShadow.wantsLayer = true; pageShadow.layer?.cornerRadius = 6; pageShadow.layer?.backgroundColor = NSColor.black.cgColor; pageShadow.layer?.shadowColor = NSColor.black.cgColor; pageShadow.layer?.shadowOpacity = 0.24; pageShadow.layer?.shadowRadius = 3; pageShadow.layer?.shadowOffset = NSSize(width: 0, height: -1)
        root.addSubview(sidebar); root.addSubview(sidebarTint); root.addSubview(pageShadow); root.addSubview(content)
        sidebarHost.wantsLayer = true
        sidebarHost.contextMenu = { [weak self] in guard let self, let space = self.activeSpace else { return nil }; return self.spaceMenu(space) }
        root.addSubview(classicHeader)
        classicHeader.isHidden = true
        privateBadge.font = .systemFont(ofSize:11,weight:.semibold)
        classicHeader.addSubview(privateBadge)
        root.addSubview(sidebarHost)
        sidebarHost.addSubview(sidebarItems)
        for view in [toolbar, addressBackground, favoritesHint, favorites, rowsScroll] { sidebarItems.addSubview(view) }
        sidebarHost.addSubview(spacesFooter)
        // Root-level hit surface spans both sides of the seam, above Chromium.
        root.addSubview(resizeStrip)
        home.search = { [weak self] in
            guard let self else { return }
            self.showCommand(newTab:self.activeTab == nil)
        }
        home.retry = { [weak self] in self?.reloadAction(nil) }
        content.addSubview(home)
        sidebarButton = ActionButton(t("sidebar"), symbol: "sidebar.left") { [weak self] in self?.toggleSidebarAction(nil) }; sidebarButton.title = ""
        backButton = NavigationButton(t("back"), symbol: "arrow.left") { [weak self] in self?.backAction(nil) }; backButton.title = ""
        forwardButton = NavigationButton(t("forward"), symbol: "arrow.right") { [weak self] in self?.forwardAction(nil) }; forwardButton.title = ""
        reloadButton = ReloadButton(t("reload")) { [weak self] in self?.reloadAction(nil) }
        addButton.invoke = { [weak self] in self?.showAddMenu() }
        addressButton = FadingAddressButton(t("address")) { [weak self] in self?.openLocationAction(nil) }; addressButton.font = .systemFont(ofSize: 14); addressButton.alignment = .left; addressButton.lineBreakMode = .byClipping
        sidebarHost.addSubview(recentPeek)
        downloadButton = FooterSpaceButton(t("library"), symbol: "archivebox.fill") { [weak self] in self?.showLibrary() }; downloadButton.title = ""
        (downloadButton as? FooterSpaceButton)?.hoverChanged = { [weak self] in
            guard let self else { return }
            self.sidebarPointer = self.root.convert(self.window.mouseLocationOutsideOfEventStream,from:nil)
            self.updateRecentPeekHover()
        }
        copyLinkButton = CopyLinkButton(t("copyURL"),symbol:"link") { [weak self] in self?.copyActiveURL() }
        siteMenuButton = NavigationButton(t("siteControls"),symbol:"slider.horizontal.3") { [weak self] in self?.showSiteMenu() }
        siteMenuButton.image = Self.siteControlsImage()
        addressBackground.wantsLayer = true; addressBackground.layer?.cornerRadius = 12
        favoritesHint.dismiss.invoke = { [weak self] in self?.hintDismissed = true; UserDefaults.standard.set(true, forKey: "BrowserFavoritesHintDismissed"); self?.render() }
        favoritesHint.acceptTab = { [weak self] id in
            guard let self else { return false }
            return self.acceptFavorite(id,at:self.session.favoriteTabs(spaceID:self.session.activeSpaceID).count)
        }
        favorites.activate = { [weak self] id in self?.selectTab(id) }
        favorites.accept = { [weak self] id, index in self?.acceptFavorite(id,at:index) ?? false }
        favorites.acceptedID = { [weak self] info in
            guard let self, case .tab(let id) = self.draggedItem(info),
                  self.session.tabs.contains(where: { $0.id == id && ($0.spaceID == self.session.activeSpaceID || $0.favorite) }) else { return nil }
            return id
        }
        favorites.draggingChanged = { [weak self] active in
            guard let self else { return }
            if active { self.favoriteDragBaseline = self.favorites.frame.height }
            else { self.favoriteDragBaseline = 0 }
            self.sidebarDragActive = active
            if active { self.cancelSidebarHover() } else { self.sidebarMousePressed = false; self.clearDropProposal(); self.updateSidebarHover() }
            self.layoutFavorites(animated:true)
        }
        favorites.heightChanged = { [weak self] in self?.layoutFavorites(animated:true) }
        for view in [sidebarButton, backButton, forwardButton, reloadButton] { toolbar.addSubview(view!) }
        for view in [addressButton, copyLinkButton, siteMenuButton] { addressBackground.addSubview(view!) }
        addressMark.image = NSImage(systemSymbolName:"magnifyingglass",accessibilityDescription:nil)
        addressMark.imageScaling = .scaleProportionallyDown
        addressMark.setAccessibilityElement(false)
        addressBackground.addSubview(addressMark,positioned:.below,relativeTo:addressButton)
        addressMark.isHidden = true
        sidebarHost.addSubview(downloadButton)
        findField = NSSearchField(); findField.placeholderString = t("find"); findField.delegate = self; findField.target = self; findField.action = #selector(findNextAction(_:)); findField.isHidden = true
        findClose = ActionButton(t("close"), symbol: "xmark") { [weak self] in self?.endFind() }; findClose.title = ""; findClose.isHidden = true
        root.addSubview(findField); root.addSubview(findClose)
        spaceButton = SpaceHeaderButton() { [weak self] in self?.toggleSpaceFolders() }; spaceButton.font = .systemFont(ofSize: 14, weight: .semibold); spaceButton.alignment = .left
        folderButton = ActionButton(t("newFolder"), symbol: "folder.badge.plus") { [weak self] in self?.newFolder() }; folderButton.title = ""
        sidebarItems.addSubview(spaceButton); sidebarItems.addSubview(folderButton)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar")); column.resizingMask = .autoresizingMask; table.addTableColumn(column)
        table.style = .plain; table.headerView = nil; table.rowHeight = 36; table.intercellSpacing = NSSize(width: 0, height: 2); table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.backgroundColor = .clear; table.selectionHighlightStyle = .none; table.focusRingType = .none
        table.dataSource = self; table.delegate = self; table.allowsEmptySelection = true
        table.verticalMotionCanBeginDrag = true
        table.context = { [weak self] row in self?.menuForRow(row) }
        table.clicked = { [weak self] row in self?.clickSidebarRow(row) }
        table.target = table; table.action = #selector(SidebarTable.handleClick(_:))
        table.dragExited = { [weak self] in self?.clearDropProposal() }
        table.draggingDestinationFeedbackStyle = .none
        table.registerForDraggedTypes([dragType,folderDragType]); table.setDraggingSourceOperationMask(.move, forLocal: true)
        let finishSidebarTracking: () -> Void = { [weak self] in
            guard let self else { return }
            self.sidebarMousePressed = NSEvent.pressedMouseButtons & 1 != 0
            self.refreshSidebarPointer()
        }
        sidebarHost.dragFinished = finishSidebarTracking
        table.mouseTrackingEnded = finishSidebarTracking
        let sidebarClip = SidebarClipView()
        sidebarClip.drawsBackground = false
        sidebarClip.dragFinished = finishSidebarTracking
        rowsScroll.contentView = sidebarClip
        rowsScroll.scrollerStyle = .overlay; rowsScroll.automaticallyAdjustsContentInsets = false; rowsScroll.contentInsets = .init(); rowsScroll.documentView = table; rowsScroll.drawsBackground = false; rowsScroll.hasVerticalScroller = true; rowsScroll.autohidesScrollers = true; rowsScroll.borderType = .noBorder
        resizeStrip.width = { [weak self] in self?.session.sidebarWidth ?? SidebarSizing.standard }
        resizeStrip.begin = { [weak self] in self?.finishSpaceSwitch() }
        resizeStrip.change = { [weak self] width in guard let self else { return }; self.session.sidebarWidth = width; self.layout(); self.persist() }
        resizeStrip.end = { [weak self] in self?.persist() }
        resizeStrip.setAccessibilityLabel("Sidebar width")
        window.acceptsMouseMovedEvents = true
        root.pointerChanged = { [weak self] event in self?.trackSidebarPointer(event); self?.trackSplitFocus(event) }
        (window as? BrowserWindow)?.pointerEvent = { [weak self] event in self?.trackSidebarPointer(event); self?.trackSplitFocus(event) }
        (window as? BrowserWindow)?.pointerTrackingEnded = finishSidebarTracking
        spaceScrollMonitor = NSEvent.addLocalMonitorForEvents(matching:.scrollWheel) { [weak self] event in
            guard let self, event.window === self.window || (event.window == nil && NSApp.keyWindow === self.window) else { return event }
            return self.handleSpaceScroll(event) ? nil : event
        }
        spaceIndicators.drawsBackground = false; spaceIndicators.borderType = .noBorder
        spaceIndicators.hasHorizontalScroller = false; spaceIndicators.documentView = spaceIndicatorContent
        spacesFooter.addSubview(spaceIndicators)
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            sidebarObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.trackingMenus = max(0, self.trackingMenus + (name == NSMenu.didBeginTrackingNotification ? 1 : -1))
                self.updateSidebarHover()
            })
        }
        sidebarObservers.append(NotificationCenter.default.addObserver(forName: Notification.Name("BrowserExtensionPreferencesChanged"), object:nil, queue:.main) { [weak self] note in
            guard let self, !self.isQuitting, let profile = note.object as? String else { return }
            self.extensionCatalog.invalidate(profile:profile)
            let items = self.extensionCatalog.entries(profile:profile,force:true)
            guard self.activeSpace?.profileID == profile else { return }
            let ids = Set(items.map(\.id))
            if self.extensionButtons.contains(where:{ !ids.contains($0.identifier?.rawValue ?? "") }) {
                self.engine.closeExtensionPopup()
                self.extensionInstallNotice?.close()
                self.siteMenu?.close()
            }
            self.refreshExtensionToolbar()
        })
        sidebarObservers.append(NotificationCenter.default.addObserver(forName:Notification.Name("BrowserDeveloperToolsChanged"),object:nil,queue:.main) { [weak self] _ in self?.updateDeveloperBars() })
        sidebarObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.engine.closeExtensionPopup()
            self?.finishSpaceSwitch()
            self?.addMenu?.close()
            self?.sidebarMousePressed = false
            self?.refreshSidebarPointer()
        })
    }
    private func layoutFavorites(animated: Bool) {
        let views: [NSView] = [favorites,spaceButton,rowsScroll]
        let previous = views.map(\.frame)
        layout()
        guard animated, !renderingSpaceSwitch, window.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let target = views.map(\.frame)
        guard zip(previous,target).contains(where: { $0 != $1 }) else { return }
        for (i,view) in views.enumerated() { view.frame = previous[i] }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.23; context.timingFunction = CAMediaTimingFunction(controlPoints:0.22,0.78,0.24,1)
            for (i,view) in views.enumerated() { view.animator().frame = target[i] }
        }
    }
    private func browsingFrame(side:CGFloat, floating:Bool) -> NSRect {
        let x:CGFloat = floating ? 8 : side+2
        let y:CGFloat = usesClassicInterface ? 48 : floating ? 9 : 7
        return NSRect(x:x,y:y,width:max(52,root.bounds.width-x-8),
                      height:max(100,root.bounds.height-y-(floating ? 9 : 10)))
    }

    private func host(_ view:NSView, in parent:NSView) {
        if view.superview !== parent { parent.addSubview(view) }
    }

    /// Only native controls change parents. The web view and its first responder
    /// stay in place, including when a floating sidebar appears over a live page.
    private func layoutNavigation(side:CGFloat) {
        let classic = usesClassicInterface
        let sidebarShown = !session.sidebarHidden || sidebarRevealed
        let navigationInSidebar = !classic || !session.sidebarHidden
        let barHost = navigationInSidebar ? toolbar : classicHeader
        for button in [backButton!,forwardButton!,reloadButton!] as [NSView] { host(button,in:barHost) }
        host(addressBackground,in:classic ? classicHeader : sidebarItems)
        host(sidebarButton,in:classic && !sidebarShown ? classicHeader : toolbar)
        toolbar.frame = NSRect(x:0,y:0,width:max(230,side),height:42)
        // Permanent sidebars use the very same controls and coordinates in both layouts.
        if navigationInSidebar {
            sidebarButton.frame = NSRect(x:74,y:5,width:32,height:32)
            let start = max(111,side-104)
            backButton.frame = NSRect(x:start-2.5,y:6,width:32,height:32)
            forwardButton.frame = NSRect(x:start+31.5,y:6,width:32,height:32)
            reloadButton.frame = NSRect(x:start+64,y:6,width:35,height:32)
        }
        classicHeader.isHidden = !classic || library != nil || spaceCreation != nil
        privateBadge.isHidden = !classic || !isPrivateWindow
        addressMark.isHidden = !classic
        let ink = sidebarInk
        if classic {
            let left = sidebarShown ? (session.sidebarHidden ? sidebarFrame.maxX+5 : side+2) : 5
            classicHeader.frame = NSRect(x:left,y:0,width:max(100,root.bounds.width-left-7),height:47)
            var x:CGFloat = 5
            if !navigationInSidebar {
                if sidebarShown {
                    sidebarButton.frame = NSRect(x:74,y:5,width:32,height:32)
                } else {
                    sidebarButton.frame = NSRect(x:x,y:7,width:32,height:32)
                    x += 38
                }
                for button in [backButton!,forwardButton!,reloadButton!] as [NSView] {
                    button.frame = NSRect(x:x,y:7,width:29,height:32); x += 30
                }
            }
            if isPrivateWindow {
                privateBadge.stringValue = splitText("Privé","Private")
                privateBadge.textColor = ink
                privateBadge.frame = NSRect(x:x+5,y:15,width:50,height:18); x += 48
            }
            x += 8
            addressBackground.frame = NSRect(x:x,y:7,width:max(80,classicHeader.bounds.width-x-5),height:32)
        } else {
            addressBackground.frame = NSRect(x:5,y:43,width:max(170,side-11),height:36)
        }

        let w = addressBackground.bounds.width
        let slots = extensionButtons.count + (overflowExtensions.isEmpty ? 0 : 1)
        let actionsWidth = CGFloat(61+slots*28)
        let buttonY:CGFloat = classic ? 3 : 6
        for (index,button) in extensionButtons.enumerated() {
            button.frame = NSRect(x:w-61-CGFloat((slots-index)*28),y:buttonY,width:26,height:25)
            button.ink = ink
        }
        extensionOverflowButton.frame = NSRect(x:w-89,y:buttonY,width:26,height:25)
        extensionOverflowButton.ink = ink
        copyLinkButton.frame = NSRect(x:w-59,y:buttonY,width:26,height:25)
        siteMenuButton.frame = NSRect(x:w-31,y:buttonY,width:25,height:25)
        if let address = addressButton as? FadingAddressButton {
            address.textInset = classic ? 32 : 0
            address.frame = classic ? NSRect(x:0,y:0,width:max(50,w-actionsWidth-12),height:32)
                                    : NSRect(x:13,y:4,width:max(30,side-100-CGFloat(slots*28)),height:28)
            address.wantsLayer = true
            address.layer?.cornerRadius = 9
            address.layer?.borderWidth = classic ? 0.7 : 0
            address.layer?.borderColor = ink.withAlphaComponent(0.16).cgColor
            address.layer?.backgroundColor = classic ? ink.withAlphaComponent(0.065).cgColor : nil
        }
        addressBackground.layer?.backgroundColor = classic ? nil : ink.withAlphaComponent(0.055).cgColor
        addressMark.contentTintColor = ink.withAlphaComponent(0.7)
        addressMark.frame = NSRect(x:10,y:9,width:14,height:14)
    }

    private func layout() {
        guard root.bounds.width > 0 else { return }
        let width = root.bounds.width
        let side = CGFloat(SidebarSizing.clamp(session.sidebarWidth))
        let floating = session.sidebarHidden
        if classicPresentation != usesClassicInterface {
            classicPresentation = usesClassicInterface
            cancelSidebarHover(); sidebarTransition += 1; sidebarAnimating = false
            sidebarHost.layer?.removeAllAnimations()
            updateBackgroundSidebarTracking()
        }
        let height = root.bounds.height - (floating ? 10 : 0)
        layoutSidebarPresentation()
        sidebarItems.frame = sidebarHost.bounds
        sidebarTint.frame = root.bounds
        layoutNavigation(side:side)
        content.frame = browsingFrame(side:side,floating:floating)
        if let library {
            library.frame = NSRect(x:0,y:0,width:library.expanded ? max(400,width-64) : min(414,width-180),height:root.bounds.height)
            content.frame = NSRect(x:library.frame.maxX+2,y:7,width:max(52,width-library.frame.maxX-10),height:root.bounds.height-17)
            sidebarHost.isHidden = true
        }
        if let windowChrome, !usesClassicInterface, library == nil, spaceCreation == nil {
            let compact = windowKind == .compact
            windowChrome.isHidden = false
            windowChrome.frame = NSRect(x:compact ? 6 : side+2,y:compact ? 4 : 7,width:compact ? width-12 : width-side-10,height:40)
            content.frame = NSRect(x:compact ? 8 : side+2,y:49,width:compact ? width-16 : width-side-10,height:max(100,root.bounds.height-59))
            if compact { sidebarHost.isHidden = true; resizeStrip.isHidden = true }
        } else { windowChrome?.isHidden = true }
        pageShadow.frame = content.frame
        home.frame = content.bounds
        let favoriteCount = session.tabs.filter { $0.favorite }.count
        let favoriteHeight: CGFloat = showFavoritesHint ? 94 : max(favorites.preferredHeight, sidebarDragActive ? max(favoriteDragBaseline,favoriteCount == 0 ? 46 : 0) : 0)
        let favoritesTop:CGFloat = usesClassicInterface ? 47 : 87
        favoritesHint.frame = NSRect(x: 5, y: favoritesTop, width: max(170,side-11), height: 94)
        favorites.frame = NSRect(x: 5, y: favoritesTop, width: max(170,side-11), height: favoriteHeight)
        let spaceY = favoritesTop+favoriteHeight+15
        spaceButton.frame = NSRect(x: 5, y: spaceY, width: max(170,side-11), height: 36)
        folderButton.frame = NSRect(x: side-37, y: spaceY+3, width: 25, height: 24)
        let rowsY = spaceY+42
        rowsScroll.frame = NSRect(x: 5, y: rowsY, width: max(170,side-11), height: max(40,height-rowsY-46))
        table.frame.size.width = rowsScroll.contentSize.width; table.tableColumns.first?.width = rowsScroll.contentSize.width
        downloadButton.frame = NSRect(x: 5, y: height-41, width: 34, height: 32)
        spacesFooter.frame = NSRect(x: 42, y: height-41, width: max(100,side-51), height: 32)
        layoutSpacesFooter()
        layoutRecentPeek()
        resizeStrip.frame = NSRect(x: side-6, y: 42, width: 14, height: max(0,height-52))
        resizeStrip.isHidden = floating || library != nil || spaceCreation != nil
        favoritesHint.isHidden = !showFavoritesHint
        favorites.isHidden = showFavoritesHint
        folderButton.isHidden = true // Folder creation remains in the space context menu and + menu.
        findField.frame = NSRect(x: max(side+18,width-340), y: usesClassicInterface ? content.frame.minY+8 : 17, width: 270, height: 28)
        findClose.frame = NSRect(x: width-48, y: usesClassicInterface ? content.frame.minY+9 : 18, width: 25, height: 25)
        layoutWindowButtons()
        if windowKind == .compact {
            sidebarHost.isHidden = true; resizeStrip.isHidden = true
        }
        undoToast.layout(in:window)
        spaceCreation?.frame = root.bounds
        spaceCreation?.sidebarWidth = side
        if spaceCreation != nil { sidebarHost.isHidden = true; content.isHidden = true; pageShadow.isHidden = true }
        layoutSplitContent()
        updateLoadIndicator()
    }
    private var sidebarFrame: NSRect {
        let side = CGFloat(SidebarSizing.clamp(session.sidebarWidth))
        if !session.sidebarHidden { return NSRect(x: 0, y: 0, width: side, height: root.bounds.height) }
        return NSRect(x: sidebarRevealed ? 4 : -side-16, y: 5, width: side+4, height: root.bounds.height-10)
    }
    private func layoutSidebarPresentation() {
        if windowKind == .compact { sidebarHost.isHidden = true; return }
        let floating = session.sidebarHidden
        sidebarHost.layer?.cornerRadius = floating ? 12 : 0
        // A translucent hairline catches the rounded edge without washing out the space color.
        sidebarHost.layer?.borderWidth = floating ? 1 : 0
        sidebarHost.layer?.borderColor = NSColor.white.withAlphaComponent(0.40).cgColor
        sidebarHost.layer?.backgroundColor = NSColor.clear.cgColor
        sidebarHost.paintsTheme = floating; sidebarHost.rounded = floating ? 12 : 0
        sidebarHost.layer?.shadowColor = NSColor.black.cgColor
        sidebarHost.layer?.shadowOpacity = floating ? 0.25 : 0
        sidebarHost.layer?.shadowRadius = 12
        sidebarHost.layer?.shadowOffset = NSSize(width: 4, height: -2)
        if !sidebarAnimating {
            sidebarHost.frame = sidebarFrame
            sidebarHost.isHidden = floating && !sidebarRevealed
        }
    }
    private func layoutWindowButtons() {
        let floating = windowKind != .compact && spaceCreation == nil && library == nil && session.sidebarHidden
        let hidden = floating && (sidebarAnimating || !sidebarRevealed)
        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = kinds.map { window.standardWindowButton($0) }
        // AppKit owns these controls in the title bar, outside the sliding view.
        // Change visibility as a group, then position them after title-bar layout.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            let changingVisibility = buttons.contains { $0.map { $0.isHidden != hidden } ?? false }
            if changingVisibility {
                for case let button? in buttons { button.isHidden = hidden }
            }
            guard !hidden else { return }
            if changingVisibility { window.contentView?.superview?.layoutSubtreeIfNeeded() }
            let anchor = floating ? sidebarFrame.origin : .zero
            for (index, candidate) in buttons.enumerated() {
                guard let button = candidate, let parent = button.superview else { continue }
                let center = parent.convert(NSPoint(x: anchor.x+17+CGFloat(index)*23, y: anchor.y+21), from: root)
                let origin = NSPoint(x: center.x-button.frame.width/2, y: center.y-button.frame.height/2)
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
        }
    }
    private func setSidebarRevealed(_ revealed: Bool) {
        guard session.sidebarHidden, sidebarRevealed != revealed else { return }
        cancelSidebarHover()
        sidebarRevealed = revealed
        updateBackgroundSidebarTracking()
        sidebarTransition += 1
        let transition = sidebarTransition
        sidebarAnimating = true
        if usesClassicInterface { layoutNavigation(side:CGFloat(SidebarSizing.clamp(session.sidebarWidth))) }
        layoutWindowButtons()
        sidebarHost.isHidden = false
        updateLoadIndicator()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : (revealed ? 0.24 : 0.20)
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.75, 0.25, 1)
            sidebarHost.animator().setFrameOrigin(sidebarFrame.origin)
        } completionHandler: { [weak self] in
            guard let self, self.sidebarTransition == transition else { return }
            self.sidebarAnimating = false
            self.layoutSidebarPresentation(); self.layoutWindowButtons()
        }
    }
    private func cancelSidebarHover() {
        sidebarHoverTask?.cancel(); sidebarHoverTask = nil; sidebarPendingIntent = nil
    }
    private func refreshSidebarPointer() {
        sidebarPointer = SidebarRevealState.pointer(at: NSEvent.mouseLocation, in: root)
        if NSEvent.pressedMouseButtons & 1 == 0 { sidebarMousePressed = false }
        updateRecentPeekHover()
        updateSidebarHover()
    }
    private func updateBackgroundSidebarTracking() {
        // Local tracking events can stop when the pointer moves to another app.
        // Sample only while a background window has a transient sidebar open.
        guard session.sidebarHidden, sidebarRevealed, !window.isKeyWindow,
              window.isVisible, !window.isMiniaturized, !isQuitting else {
            backgroundSidebarTimer?.invalidate()
            backgroundSidebarTimer = nil
            return
        }
        guard backgroundSidebarTimer == nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.refreshSidebarPointer()
        }
        timer.tolerance = 0.015
        backgroundSidebarTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func sidebarHoverIntent() -> SidebarRevealIntent {
        if NSEvent.pressedMouseButtons & 1 == 0 { sidebarMousePressed = false }
        let interacting = library != nil || trackingMenus > 0 || addMenu != nil || spaceCreation != nil || sheet != nil || window.attachedSheet != nil || commandPalette != nil || siteMenu?.isShown == true || iconPicker?.isShown == true || themeEditor != nil || sidebarMousePressed || sidebarDragActive || sidebarTitleEditor?.isEditingTitle == true
        return SidebarRevealState.intent(hidden: session.sidebarHidden, revealed: sidebarRevealed,
                                         active: window.isVisible && !window.isMiniaturized,
                                         pointer: sidebarPointer, height: root.bounds.height,
                                         sidebarWidth: CGFloat(SidebarSizing.clamp(session.sidebarWidth)), protected: interacting)
    }
    private func clearSidebarPointerFeedback() {
        guard let outside = NSEvent.mouseEvent(with:.mouseMoved,location:NSPoint(x:-10000,y:-10000),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:0,context:nil,eventNumber:0,clickCount:0,pressure:0) else { return }
        updateSidebarPointerFeedback(outside)
    }
    private func updateSidebarPointerFeedback(_ event: NSEvent) {
        spaceButton?.trackPointer(event)
        favorites.trackPointer(event)
        backButton?.trackPointer(event); forwardButton?.trackPointer(event)
        copyLinkButton?.trackPointer(event); siteMenuButton?.trackPointer(event)
        reloadButton?.trackPointer(event)
        addButton.trackPointer(event)
        (downloadButton as? FooterSpaceButton)?.trackPointer(event)
        spaceIndicatorContent.subviews.compactMap { $0 as? FooterSpaceButton }.forEach { $0.trackPointer(event) }
    }
    private func trackSidebarPointer(_ event: NSEvent) {
        guard siteMenu?.isShown != true else { clearSidebarPointerFeedback(); return }
        updateSidebarPointerFeedback(event)
        if event.type == .leftMouseDown || event.type == .leftMouseDragged {
            sidebarMousePressed = true
            let point = sidebarHost.convert(event.locationInWindow,from:nil)
            if !recentPeekVisible || !recentPeek.frame.contains(point) { dismissRecentPeek() }
        }
        if event.type == .leftMouseUp { sidebarMousePressed = false }
        let location = root.convert(event.locationInWindow, from:nil)
        sidebarPointer = event.type != .mouseExited && event.window === window && root.bounds.contains(location) ? location : nil
        updateRecentPeekHover()
        updateSidebarHover()
    }
    private func updateSidebarHover() {
        updateBackgroundSidebarTracking()
        guard windowKind != .compact else { return }
        guard !isQuitting, library == nil else { return }
        let intent = sidebarHoverIntent()
        guard intent != .keep else { cancelSidebarHover(); return }
        guard sidebarPendingIntent != intent else { return }
        cancelSidebarHover(); sidebarPendingIntent = intent
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.sidebarPendingIntent = nil; self.sidebarHoverTask = nil
            self.sidebarPointer = SidebarRevealState.pointer(at: NSEvent.mouseLocation, in: self.root)
            guard self.sidebarHoverIntent() == intent else { self.updateSidebarHover(); return }
            self.setSidebarRevealed(intent == .reveal)
        }
        sidebarHoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + (intent == .reveal ? 0.08 : 0.18), execute: task)
    }
    private func render() {
        session.repairTabSelections()
        session.normalizeSplits()
        if swipeTarget != nil { swipeNeedsRender = true; return }
        if !renderingSpaceSwitch { finishSpaceSwitch() }
        isRendering = true; defer { isRendering = false }
        applyTheme()
        sidebarButton.wantsLayer = true; sidebarButton.layer?.cornerRadius = 8; sidebarButton.layer?.backgroundColor = sidebarInk.withAlphaComponent(0.07).cgColor
        favoritesHint.ink = sidebarInk; favoritesHint.accent = NSColor(srgbRed: 0.70, green: 0, blue: 0.53, alpha: 1)
        favoritesHint.heading.stringValue = t("favoritesHintTitle"); favoritesHint.detail.stringValue = t("favoritesHintDetail"); favoritesHint.dismiss.setAccessibilityLabel(t("dismissHint")); favoritesHint.needsDisplay = true; favoritesHint.needsLayout = true
        for (button, key) in [(sidebarButton!, "sidebar"), (backButton!, "back"), (forwardButton!, "forward"), (reloadButton!, "reload"), (folderButton!, "newFolder"), (downloadButton!, "library"), (findClose!, "close")] { button.toolTip = t(key); button.setAccessibilityLabel(t(key)) }
        findField.placeholderString = t("find")
        favorites.update(session.favoriteTabs(spaceID:session.activeSpaceID).map {
            FavoriteVisual(id:$0.id,title:displayTitle($0),image:favoriteImage($0.id),menu:tabMenu($0),isLoaded:favoriteIsLoaded($0.id),developerMode:($0.id == (activeTab?.favoriteSourceID ?? activeTab?.id)) && activeTab?.developerMode == true)
        },activeID:activeTab?.favoriteSourceID ?? activeTab?.id,ink:sidebarInk)
        renderSpaceContent()
        table.insertionColor = sidebarInk
        table.reloadData(); renderSpacesFooter(); updateToolbar(); buildHome(); layoutFavorites(animated:true); style(spaceButton, opacity: 0.7); style(downloadButton, opacity: 0.8)
        library?.update(session:session)
    }
    /// Updates only the movable part of the sidebar; previewing never opens a Chromium tab.
    private func renderSpaceContent() {
        spaceButton.spaceName = activeSpace?.name ?? "Arc Reborn"; spaceButton.spaceIcon = activeSpace?.icon ?? "◈"
        spaceButton.collapsed = activeSpace?.foldersCollapsed == true; spaceButton.ink = sidebarInk; spaceButton.accent = favoritesHint.accent; spaceButton.moreLabel = t("more"); spaceButton.refreshTitle()
        spaceButton.setAccessibilityLabel((spaceButton.collapsed ? t("expandSpace") : t("collapseSpace")) + " — " + spaceButton.spaceName)
        spaceButton.menu = activeSpace.map(spaceMenu)
        spaceButton.toolTip = t(spaceButton.collapsed ? "expandSpace" : "collapseSpace"); folderButton.toolTip = t("newFolder")
        treeRows = session.sidebarTree(spaceID:session.activeSpaceID,retainedTabs:sidebarCollapse.retainedTabs)
        var visibleGroups = Set<String>()
        func includeTab(_ id:String) -> Bool {
            guard let group = session.splitGroup(containing:id) else { return true }
            return visibleGroups.insert(group.id).inserted
        }
        treeRows = treeRows.filter { entry in if case .tab(let id) = entry.item { return includeTab(id) }; return true }
        rows = treeRows.map { switch $0.item { case .tab(let id): return .tab(id); case .folder(let id): return .folder(id) } }
        rows.append(.heading("")); rows.append(.newTab)
        rows += session.sidebarChildren(spaceID:session.activeSpaceID,parentID:nil,temporary:true).compactMap {
            if case .tab(let id) = $0, includeTab(id) { return .tab(id) }; return nil
        }
        table.insertionColor = sidebarInk
        table.reloadData(); style(spaceButton,opacity:0.7)
    }
    private func renderSpacesFooter() {
        spaceIndicatorContent.subviews.forEach { $0.removeFromSuperview() }
        if addButton.superview == nil { spacesFooter.addSubview(addButton) }
        for space in session.spaces {
            let button = FooterSpaceButton(space.id == session.activeSpaceID ? space.icon : "") { [weak self] in self?.selectSpace(space.id) }
            button.toolTip = space.name; button.setAccessibilityLabel(space.name)
            button.dot = space.id != session.activeSpaceID; button.ink = sidebarInk
            button.font = .systemFont(ofSize:14); style(button,opacity:0.85); button.menu = spaceMenu(space)
            spaceIndicatorContent.addSubview(button)
        }
        (downloadButton as? FooterSpaceButton)?.ink = sidebarInk
        addButton.ink = sidebarInk; addButton.toolTip = t("add"); addButton.setAccessibilityLabel(t("add"))
    }
    private func layoutSpacesFooter() {
        let width = max(1,spacesFooter.bounds.width-37)
        spaceIndicators.frame = NSRect(x:0,y:0,width:width,height:32)
        let active = session.spaces.firstIndex(where: { $0.id == session.activeSpaceID }) ?? 0
        let metrics = SpaceIndicatorLayout(count:session.spaces.count,available:width,activeIndex:active)
        spaceIndicatorContent.frame = NSRect(x:0,y:0,width:max(width,metrics.width),height:32)
        for (i,view) in spaceIndicatorContent.subviews.enumerated() {
            let item = metrics.frame(i); view.frame = NSRect(x:item.x,y:0,width:item.width,height:32)
            (view as? FooterSpaceButton)?.dotDiameter = metrics.dotDiameter
        }
        if spaceIndicatorContent.subviews.indices.contains(active) { spaceIndicatorContent.scrollToVisible(spaceIndicatorContent.subviews[active].frame) }
        addButton.frame = NSRect(x:spacesFooter.bounds.width-31,y:0,width:33,height:32)
    }
    private func handleSpaceScroll(_ event: NSEvent) -> Bool {
        let blocked = library != nil || spaceCreation != nil || spaceCreationClosing || sheet != nil || window.attachedSheet != nil || commandPalette != nil || siteMenu?.isShown == true || iconPicker?.isShown == true || themeEditor != nil || addMenu != nil || trackingMenus > 0 || sidebarDragActive
        let location = event.window == nil ? window.convertPoint(fromScreen:NSEvent.mouseLocation) : event.locationInWindow
        let inside = !sidebarHost.isHidden && sidebarHost.bounds.contains(sidebarHost.convert(location,from:nil))
        let inFooter = inside && spacesFooter.frame.contains(sidebarHost.convert(location,from:nil))
        let phase: SpaceSwipeState.Phase = event.phase.contains(.began) || event.phase.contains(.mayBegin) ? .began : event.phase.contains(.cancelled) ? .cancelled : event.phase.contains(.ended) ? .ended : event.phase.isEmpty ? .unphased : .changed
        let overDownloads = !recentPeek.isHidden && recentPeek.frame.contains(sidebarHost.convert(location,from:nil))
        if inFooter || overDownloads || blocked || !inside || isQuitting {
            if swipeTarget != nil { finishSpaceSwitch() }
            _ = spaceSwipe.update(dx:0,dy:0,phase:phase,momentum:!event.momentumPhase.isEmpty,eligible:false,time:event.timestamp)
            return false
        }
        let momentum = !event.momentumPhase.isEmpty
        if swipeSettling {
            if phase == .began && !momentum { finishSpaceSwitch() }
            else { return true }
        }
        let scale = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
        let result = spaceSwipe.update(dx:Double(event.scrollingDeltaX)*scale,dy:Double(event.scrollingDeltaY)*scale,phase:phase,momentum:momentum,eligible:true,time:event.timestamp)
        guard !momentum else { return result.consume }
        if result.cancelled { settleSpaceSwipe(commit:false); return result.consume }
        if result.consume, let direction = result.direction,
           let index = session.spaces.firstIndex(where: { $0.id == session.activeSpaceID }) {
            let next = index + direction
            if session.spaces.indices.contains(next) {
                let target = session.spaces[next].id
                if swipeTarget != target { prepareSpaceSwipe(to:target,direction:direction) }
                swipeProgress = min(1,CGFloat(abs(result.offset))/max(1,sidebarHost.bounds.width))
                spaceSwitch?.setProgress(swipeProgress)
                sidebarTint.setPreviewProgress(swipeProgress); sidebarHost.setPreviewProgress(swipeProgress)
            } else { discardSpaceSwipePreview() }
        } else if result.consume {
            swipeProgress = 0; spaceSwitch?.setProgress(0)
            sidebarTint.setPreviewProgress(0); sidebarHost.setPreviewProgress(0)
        }
        if ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_SCROLL_LOG"] == "1" {
            NSLog("SpaceScroll dx=%g offset=%g progress=%g phase=%lu consumed=%d",event.scrollingDeltaX,result.offset,Double(swipeProgress),event.phase.rawValue,result.consume ? 1 : 0)
        }
        swipeReleaseTask?.cancel(); swipeReleaseTask = nil
        let commit = result.shouldCommit(width:Double(sidebarHost.bounds.width))
        if result.ended { settleSpaceSwipe(commit:commit) }
        else if result.consume && (phase == .unphased || phase == .changed || phase == .began) {
            // A real trackpad ends explicitly. The timeout is only for wheel/synthetic streams
            // without phases; a paused physical gesture remains exactly under the fingers.
            if phase == .unphased {
                let task = DispatchWorkItem { [weak self] in self?.settleSpaceSwipe(commit:commit) }
                swipeReleaseTask = task; DispatchQueue.main.asyncAfter(deadline:.now()+0.14,execute:task)
            }
        }
        return result.consume
    }

    private func discardSpaceSwipePreview() {
        spaceSwitch?.finish(); spaceSwitch = nil; swipeTarget = nil; swipeProgress = 0
        sidebarTint.endPreview(); sidebarHost.endPreview()
    }

    private func prepareSpaceSwipe(to id: String, direction: Int) {
        discardSpaceSwipePreview()
        let top = spaceButton.frame.minY
        let region = NSRect(x:0,y:top,width:sidebarHost.bounds.width,height:max(1,spacesFooter.frame.minY-top))
        let transition = SpaceSwitchTransition(host:sidebarItems,views:spaceSwitchViews,region:region,contentCopy:{ [weak self] in self?.copySpaceRows($0) })
        let original = session.activeSpaceID, scrollOrigin = rowsScroll.contentView.bounds.origin
        isRendering = true
        session.activeSpaceID = id
        renderSpaceContent()
        rowsScroll.contentView.scroll(to:.zero); rowsScroll.reflectScrolledClipView(rowsScroll.contentView)
        transition.captureIncoming(views:spaceSwitchViews,towardsRight:direction > 0)
        let theme = activeSpace?.theme ?? .solid(activeSpace?.color ?? palette[0])
        session.activeSpaceID = original
        renderSpaceContent()
        rowsScroll.contentView.scroll(to:scrollOrigin); rowsScroll.reflectScrolledClipView(rowsScroll.contentView)
        isRendering = false
        transition.conceal(spaceSwitchViews)
        spaceSwitch = transition; swipeTarget = id
        sidebarTint.beginPreview(theme:theme,dark:darkTheme); sidebarHost.beginPreview(theme:theme,dark:darkTheme)
    }

    private func settleSpaceSwipe(commit: Bool) {
        swipeReleaseTask?.cancel(); swipeReleaseTask = nil
        guard !swipeSettling, let target = swipeTarget, let transition = spaceSwitch else { return }
        swipeSettling = true
        let remaining = commit ? 1-swipeProgress : swipeProgress
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12+0.14*Double(remaining)
        sidebarTint.setPreviewProgress(commit ? 1 : 0,duration:duration)
        sidebarHost.setPreviewProgress(commit ? 1 : 0,duration:duration)
        transition.settle(commit:commit,duration:duration) { [weak self, weak transition] in
            guard let self, self.spaceSwitch === transition else { return }
            self.swipeTarget = nil; self.swipeSettling = false; self.spaceSwitch = nil
            self.sidebarTint.endPreview(); self.sidebarHost.endPreview()
            if commit { self.endFind(); self.session.activeSpaceID = target }
            self.renderingSpaceSwitch = true; self.completingSpaceSwipe = true
            self.render(); self.renderingSpaceSwitch = false; self.completingSpaceSwipe = false
            // The preview already blended the theme: no second fade or slide on release.
            self.sidebarTint.endPreview(); self.sidebarHost.endPreview()
            self.swipeNeedsRender = false
            if commit { self.showSelectedTab(); self.persist() }
        }
    }
    private static func siteControlsImage() -> NSImage {
        let image = NSImage(size: NSSize(width:18,height:18), flipped:false) { _ in
            NSColor.black.setStroke()
            let border = NSBezierPath(roundedRect:NSRect(x:1.5,y:1.5,width:15,height:15),xRadius:3,yRadius:3); border.lineWidth = 1.3; border.stroke()
            for (y,knob) in [(6.0,7.0),(12.0,11.0)] {
                let line = NSBezierPath(); line.move(to:NSPoint(x:4,y:y)); line.line(to:NSPoint(x:knob-1.7,y:y)); line.move(to:NSPoint(x:knob+1.7,y:y)); line.line(to:NSPoint(x:14,y:y)); line.lineWidth = 1.2; line.stroke()
                let circle = NSBezierPath(ovalIn:NSRect(x:knob-1.5,y:y-1.5,width:3,height:3)); circle.lineWidth = 1.2; circle.stroke()
            }
            return true
        }; image.isTemplate = true; return image
    }
    private func layoutRecentPeek() {
        recentPeek.frame = NSRect(x:0,y:downloadButton.frame.minY-recentPeek.desiredHeight+3,width:sidebarHost.bounds.width,height:recentPeek.desiredHeight)
        sidebarItems.setDownloadsEdge(recentPeek.frame.minY)
        recentPeek.layoutSubtreeIfNeeded(); recentPeek.layout()
    }
    private func updateDownloadIndicator() {
        (downloadButton as? FooterSpaceButton)?.updateTransfers(libraryStore.downloads,unread:libraryStore.unreadCount)
    }
    private var peekShowsDownloads = false
    private func updateRecentPeekContents() {
        if !libraryStore.activeDownloads.isEmpty || libraryStore.unreadCount > 0 { peekShowsDownloads = true }
        recentPeek.update(files:RecentLibraryFile.collect(media:libraryStore.media,downloads:libraryStore.downloads,excluding:libraryStore.hiddenRecents),downloads:peekShowsDownloads ? libraryStore.peekDownloads : [],ink:sidebarInk,language:session.language,loading:libraryStore.loading)
        layoutRecentPeek()
    }
    private func updateRecentPeekHover() {
        guard !isQuitting, window.isVisible, !window.isMiniaturized, library == nil, spaceCreation == nil, commandPalette == nil, siteMenu?.isShown != true, iconPicker?.isShown != true, themeEditor == nil, addMenu == nil, trackingMenus == 0, !sidebarDragActive, !sidebarHost.isHidden, let point = sidebarPointer else { dismissRecentPeek(); return }
        let local = sidebarHost.convert(point,from:root)
        let inside = downloadButton.frame.insetBy(dx:-3,dy:-4).contains(local) || (recentPeekVisible && recentPeek.frame.insetBy(dx:0,dy:-8).contains(local))
        guard inside != recentPeekVisible else { recentPeekTask?.cancel(); recentPeekTask = nil; recentPeekPending = nil; return }
        guard recentPeekPending != inside else { return }
        recentPeekTask?.cancel(); recentPeekPending = inside
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }; self.recentPeekTask = nil; self.recentPeekPending = nil
            if inside {
                guard NSEvent.pressedMouseButtons == 0 else { return }
                self.peekShowsDownloads = false
                self.recentPeekVisible = true
                self.libraryStore.changed = { [weak self] in if self?.recentPeekVisible == true { self?.updateRecentPeekContents() } }
                self.updateRecentPeekContents(); self.libraryStore.startObserving()
                self.sidebarItems.setDownloadsPresented(true)
                self.recentPeek.setPresented(true)
                (self.downloadButton as? FooterSpaceButton)?.animateLibraryPeek(true)
            } else { self.dismissRecentPeek() }
        }
        recentPeekTask = task; DispatchQueue.main.asyncAfter(deadline:.now()+(inside ? 0.32 : 0.18),execute:task)
    }
    private func dismissRecentPeek(animated: Bool = true) {
        recentPeekTask?.cancel(); recentPeekTask = nil; recentPeekPending = nil
        guard recentPeekVisible else { return }; recentPeekVisible = false
        libraryStore.changed = nil; libraryStore.stopObserving()
        sidebarItems.setDownloadsPresented(false, animated:animated)
        recentPeek.setPresented(false,animated:animated)
        (downloadButton as? FooterSpaceButton)?.animateLibraryPeek(false)
    }
    private func showLibrary() {
        dismissRecentPeek(animated:false)
        guard !isQuitting, spaceCreation == nil else { return }
        if library != nil { closeLibrary(); return }
        finishSpaceSwitch(); commandPalette?.close(); themeEditor?.close(animated:false); addMenu?.close(); endFind(); cancelSidebarHover()
        sidebarTransition += 1; sidebarAnimating = false; sidebarHost.isHidden = true
        let view = LibraryView(store:libraryStore,session:session); library = view
        view.close = { [weak self] in self?.closeLibrary() }
        view.expandedChanged = { [weak self] in self?.animateLibraryLayout() }
        view.selectSpace = { [weak self] id in self?.closeLibrary { [weak self] in self?.selectSpace(id) } }
        view.selectTab = { [weak self] id in self?.closeLibrary { [weak self] in
            guard let self, let tab = self.session.tabs.first(where: { $0.id == id }) else { return }
            self.session.activeSpaceID = tab.spaceID; self.selectTab(id)
        } }
        view.editTheme = { [weak self] id in self?.editSpaceAppearance(id,icon:false) }
        view.editIcon = { [weak self] id, anchor in self?.editSpaceAppearance(id,icon:true,anchor:anchor) }
        view.renameSpace = { [weak self] id,name in
            guard let self, let index = self.session.spaces.firstIndex(where: { $0.id == id }) else { return }
            let value = String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80))
            guard !value.isEmpty, value.rangeOfCharacter(from:.controlCharacters) == nil else { return }
            self.session.spaces[index].name = value; self.render(); self.persist()
        }
        view.moveSpace = { [weak self] id,index in
            guard let self, self.session.reorderSpace(id:id,to:index) else { return }; self.render(); self.persist()
        }
        view.spaceMenu = { [weak self] id in guard let self, let space = self.session.spaces.first(where: { $0.id == id }) else { return nil }; return self.spaceMenu(space) }
        view.reorderSpace = { [weak self] id,delta in
            guard let self, let from = self.session.spaces.firstIndex(where: { $0.id == id }), self.session.spaces.indices.contains(from+delta) else { return }
            guard self.session.reorderSpace(id:id,to:from+delta) else { return }; self.render(); self.persist()
        }
        view.folderToggle = { [weak self] id in guard let self else { return }; self.sidebarCollapse.toggle(.folder(id),in:&self.session); self.render(); self.persist() }
        view.restoreTab = { [weak self] id in self?.closeLibrary { [weak self] in
            guard let self, let index = self.session.closedTabs.firstIndex(where: { $0.id == id }) else { return }
            let tab = self.session.closedTabs.remove(at:index); self.session.closedTabs.append(tab)
            self.restoreTabAction(nil)
        } }
        root.addSubview(view,positioned:.below,relativeTo:pageShadow)
        animateLibraryLayout(entering:true)
        window.makeFirstResponder(view)
    }
    private func animateLibraryLayout(entering: Bool = false) {
        guard let library, !libraryClosing else { return }
        let previous = content.frame; layout(); library.layoutSubtreeIfNeeded(); let target = content.frame
        content.frame = previous; pageShadow.frame = previous
        if entering { library.frame.origin.x = -65; library.alphaValue = 0 }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.27
            context.timingFunction = CAMediaTimingFunction(controlPoints:0.2,0.8,0.25,1)
            library.animator().setFrameOrigin(.zero); library.animator().alphaValue = 1
            content.animator().frame = target; pageShadow.animator().frame = target
        } completionHandler: { [weak self] in self?.layout() }
    }
    private func closeLibrary(completion: (() -> Void)? = nil) {
        guard let view = library, !libraryClosing else { completion?(); return }
        libraryClosing = true; libraryTransition += 1; let token = libraryTransition
        view.dispose()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.20
            context.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
            view.animator().alphaValue = 0; view.animator().setFrameOrigin(NSPoint(x:-40,y:0))
            let side = CGFloat(SidebarSizing.clamp(session.sidebarWidth))
            let target = browsingFrame(side:side,floating:session.sidebarHidden)
            content.animator().frame = target; pageShadow.animator().frame = target
        },completionHandler:{ [weak self] in
            guard let self, self.libraryTransition == token else { return }
            view.removeFromSuperview(); self.library = nil; self.libraryClosing = false
            self.render(); self.showSelectedTab(); completion?()
        })
    }
    func browserDownloadUpdated(_ tabID: String, values: [String:Any]) {
        guard let id = values["id"] as? NSNumber else { return }
        let profile = session.tabs.first(where: { $0.id == tabID }).flatMap { tab in session.spaces.first(where: { $0.id == tab.spaceID })?.profileID } ?? ""
        libraryStore.updateDownload(id:downloadRun+"-"+id.stringValue,name:values["name"] as? String ?? "",path:values["path"] as? String ?? "",source:values["url"] as? String ?? "",profileID:profile,received:(values["received"] as? NSNumber)?.int64Value ?? 0,total:(values["total"] as? NSNumber)?.int64Value ?? 0,state:values["state"] as? String ?? "progress",speed:(values["speed"] as? NSNumber)?.int64Value ?? 0)
    }
    private func showAddMenu() {
        if let addMenu { addMenu.close(); return }
        let shortcuts = BrowserCommands.displayedBindings(commandOverrides)
        func shortcut(_ id:String) -> String { let value = shortcuts[id]; return value?.key.isEmpty == false ? value!.caption : "" }
        let menu = AddMenuPopover(entries:[
            AddMenuEntry(title:t("newSpace"),symbol:"rectangle.stack.badge.plus",shortcut:shortcut("newSpace"),separatorBefore:false,action:{ [weak self] in self?.showSpaceForm(nil) }),
            AddMenuEntry(title:t("newFolder"),symbol:"folder",shortcut:shortcut("newFolder"),separatorBefore:false,action:{ [weak self] in self?.newFolder() }),
            AddMenuEntry(title:t("newEasel"),symbol:"scribble",shortcut:"",separatorBefore:true,action:nil),
            AddMenuEntry(title:t("newNote"),symbol:"doc.text",shortcut:"",separatorBefore:false,action:nil),
            AddMenuEntry(title:t("newSplit"),symbol:"rectangle.split.2x1",shortcut:shortcut("split.add"),separatorBefore:true,action:{ [weak self] in self?.addSplitPane() }),
            AddMenuEntry(title:t("newTab"),symbol:"plus.app",shortcut:shortcut("newTab"),separatorBefore:false,action:{ [weak self] in self?.newTabAction(nil) })
        ],tint:tint())
        menu.onClosing = { [weak self] in self?.addButton.setExpanded(false) }
        menu.onClose = { [weak self] in
            self?.addMenu = nil
            self?.sidebarMousePressed = false; self?.updateSidebarHover()
        }
        addMenu = menu; cancelSidebarHover(); addButton.setExpanded(true)
        menu.show(from:addButton)
    }
    private func clearTemporaryTabs() {
        guard !isQuitting else { return }
        var next = session
        for tab in session.tabs where tab.spaceID == session.activeSpaceID && !tab.pinned && !tab.favorite {
            next.closeTab(id:tab.id)
        }
        performDeletion(next,kind:.tabs)
    }
    private func updateLoadIndicator() {
        let tab = activeTab
        let state = tab.flatMap { status[$0.id] }
        let showingPage = library == nil && spaceCreation == nil && !closingWindow
        if showingPage, state?.loading == true || !pageLoad.isHidden {
            if let chrome = windowChrome, !chrome.isHidden {
                if pageLoad.superview !== chrome { chrome.addSubview(pageLoad, positioned:.below, relativeTo:nil) }
                chrome.layoutSubtreeIfNeeded()
                pageLoad.follow(chrome.addressSurface, radius:7, style:.field)
            } else if usesClassicInterface || !session.sidebarHidden || sidebarRevealed {
                if pageLoad.superview !== addressBackground { addressBackground.addSubview(pageLoad, positioned:.below, relativeTo:nil) }
                let field = usesClassicInterface ? (addressButton?.frame ?? addressBackground.bounds) : addressBackground.bounds
                let radius = usesClassicInterface ? addressButton?.layer?.cornerRadius : addressBackground.layer?.cornerRadius
                pageLoad.follow(field, radius:radius ?? 0, style:.field)
            } else {
                if pageLoad.superview !== root { root.addSubview(pageLoad, positioned:.above, relativeTo:content) }
                pageLoad.follow(content.frame, radius:content.layer?.cornerRadius ?? 0, style:.rail)
            }
        }
        pageLoad.display(tab:showingPage ? tab?.id : nil, loading:showingPage && state?.loading == true,
                         progress:state?.progress ?? 0, base:tint(), accent:NSColor(browserHex:activeSpace?.color ?? palette[0]) ?? .systemPurple,
                         ink:sidebarInk, label:splitText("Chargement de la page","Page loading"))
    }

    private func updateToolbar() {
        updateLoadIndicator()
        updateSplitHeaders()
        updateDeveloperBars()
        refreshExtensionToolbar()
        let state = activeTab.flatMap { status[$0.id] }
        windowChrome?.update(url:activeTab?.url ?? "",back:state?.back ?? false,forward:state?.forward ?? false,loading:state?.loading ?? false)
        let pageTitle = activeTab.map { displayTitle($0) }.flatMap { $0.isEmpty ? nil : $0 } ?? "Arc Reborn"
        window.title = pageTitle + (isPrivateWindow ? splitText(" — Navigation privée"," — Private Browsing") : windowKind == .compact ? splitText(" — Petite fenêtre"," — Little Window") : "")
        backButton.ink = sidebarInk; forwardButton.ink = sidebarInk
        backButton.isEnabled = state?.back ?? false; forwardButton.isEnabled = state?.forward ?? false
        reloadButton.isEnabled = activeTab != nil && !(activeTab?.url.isEmpty ?? true)
        reloadButton.configure(loading:state?.loading == true,ink:sidebarInk,label:t(state?.loading == true ? "stop" : "reload"))
        addressButton.title = activeTab.map { tab in
            if settingsPageURL(tab.url) != nil { return browserDisplayAddress(tab.url) }
            let host = URL(string:tab.url)?.host
            return host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? t("address")
        } ?? t("address")
        addressButton.toolTip = activeTab.map { browserDisplayAddress($0.url) }; addressButton.isHidden = false
        findField.isHidden = !isFinding; findClose.isHidden = !isFinding
        copyLinkButton.isEnabled = copyableURL != nil
        siteMenuButton.isEnabled = copyableURL != nil
        copyLinkButton.ink = sidebarInk; siteMenuButton.ink = sidebarInk
        copyLinkButton.toolTip = t("copyURL"); copyLinkButton.setAccessibilityLabel(t("copyURL"))
        siteMenuButton.toolTip = t("siteControls"); siteMenuButton.setAccessibilityLabel(t("siteControls"))
        for button in [sidebarButton!, backButton!, forwardButton!, reloadButton!, addressButton!, copyLinkButton!, siteMenuButton!] { style(button, opacity: button.isEnabled ? 0.8 : 0.35) }
    }
    private func landingPage(for tab: NativeTab?) -> BrowserLandingView.Page? {
        let failure = tab.flatMap { status[$0.id]?.error }
        if let tab, failure == nil, !tab.url.isEmpty, tab.url != "about:blank" { return nil }
        let command = BrowserCommands.displayedBindings(commandOverrides)[tab == nil ? "newTab" : "commandBar"]
        let shortcut = command.flatMap { $0.key.isEmpty ? nil : $0.caption } ?? ""
        return .init(language:session.language, space:activeSpace?.name ?? "", isPrivate:isPrivateWindow,
                     shortcut:shortcut, failure:failure)
    }
    private func buildHome() {
        guard activeSplit == nil, let page = landingPage(for:activeTab) else { home.isHidden = true; return }
        home.show(page); home.isHidden = false
    }
    private func showSelectedTab() {
        // Commit the old/new Chromium surfaces together, without AppKit's
        // implicit opacity or geometry transitions during a tab switch.
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit(); NSAnimationContext.endGrouping() }
        guard !isQuitting, !closingWindow, spaceCreation == nil else { return }
        guard profileReloads[session.activeSpaceID] == nil, pendingSpaceClosures[session.activeSpaceID] == nil else { return }
        session.normalizeSplits()
        let ids = activeSplit?.tabIDs ?? activeTab.map { [$0.id] } ?? []
        let visible = Set(ids)
        if visible != archiveVisible {
            let changed = visible.symmetricDifference(archiveVisible), now = Date()
            archiveVisible = visible
            var recorded = false
            for i in session.tabs.indices where changed.contains(session.tabs[i].id) && session.profile(forSpace:session.tabs[i].spaceID)?.autoArchiveEnabled == true {
                session.tabs[i].lastViewedAt = now; recorded = true
            }
            if recorded { persist() }
        }
        pictureInPicture.update(visible:ids,eligible:Set(session.tabs.filter { session.automaticPictureInPictureEnabled(for:$0) }.map(\.id)))
        if let capture = pageCapture, activeTab?.id != capture.tabID { capture.close() }
        if let capture = portraitCapture, !ids.contains(capture.tabID) { capture.close() }
        for (id,bar) in developerBars where !ids.contains(id) { bar.isHidden = true }
        for (id,view) in containers where !ids.contains(id) { view.isHidden = true; engine.setTab(id,visible:false) }
        if let group = activeSplit {
            if splitHost.superview == nil { content.addSubview(splitHost) }
            splitHost.isHidden = false; splitHost.frame = content.bounds
            splitHost.resized = { [weak self] in self?.resizeSplitPages() }
            splitHost.weightsChanged = { [weak self] weights in
                guard let self, let index = self.session.splitGroups?.firstIndex(where: { $0.id == group.id }) else { return }
                self.session.splitGroups?[index].weights = weights; self.persist()
            }
            splitHost.configure(ids:group.tabIDs,vertical:group.vertical,weights:group.weights)
            home.isHidden = true
            for pane in splitHost.panes {
                pane.command = { [weak self] id,kind in self?.splitPaneCommand(id,kind) }
                ensurePage(pane.tabID,in:pane.body)
            }
            resizeSplitPages(); updateSplitHeaders()
        } else {
            splitHost.isHidden = true
            guard session.onboardingComplete, let tab = activeTab else { buildHome(); return }
            ensurePage(tab.id,in:content)
            buildHome()
            layoutSplitContent()
        }
    }
    private func selectTab(_ id: String) { guard !isQuitting else { return }; session.selectTab(id: id); render(); showSelectedTab(); persist() }
    /// NSTableView draws layer-backed cells lazily after reloadData. Copy the visible
    /// rows as independent native views so both pages are complete before fingers move.
    private func copySpaceRows(_ view: NSView) -> NSView? {
        guard view === rowsScroll else { return nil }
        let copy = FlippedView(frame:rowsScroll.bounds)
        copy.wantsLayer = true; copy.layer?.masksToBounds = true
        copyingSpaceRows = true; defer { copyingSpaceRows = false }
        var y = -rowsScroll.contentView.bounds.minY
        for row in rows.indices {
            let height = tableView(table,heightOfRow:row)
            defer { y += height + table.intercellSpacing.height }
            guard y+height >= 0 && y < rowsScroll.bounds.height,
                  let cell = tableView(table,viewFor:table.tableColumns.first,row:row) else { continue }
            cell.frame = NSRect(x:0,y:y,width:table.bounds.width,height:height)
            copy.addSubview(cell); cell.needsLayout = true; cell.layoutSubtreeIfNeeded()
        }
        return copy
    }
    private var spaceSwitchViews: [NSView] { [spaceButton,rowsScroll] }
    private func finishSpaceSwitch() {
        swipeReleaseTask?.cancel(); swipeReleaseTask = nil
        discardSpaceSwipePreview(); swipeSettling = false; spaceSwipe.reset()
        if swipeNeedsRender {
            swipeNeedsRender = false
            render()
        }
    }
    private func selectSpace(_ id: String) {
        guard !isQuitting, spaceCreation == nil, !spaceCreationClosing,
              id != session.activeSpaceID,
              let next = session.spaces.firstIndex(where: { $0.id == id }) else { return }
        let previous = session.spaces.firstIndex(where: { $0.id == session.activeSpaceID }) ?? next
        finishSpaceSwitch()
        let animate = window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animate && !sidebarHost.isHidden {
            let top = spaceButton.frame.minY
            let region = NSRect(x:0,y:top,width:sidebarHost.bounds.width,height:max(1,spacesFooter.frame.minY-top))
            spaceSwitch = SpaceSwitchTransition(host:sidebarItems,views:spaceSwitchViews,region:region,contentCopy:{ [weak self] in self?.copySpaceRows($0) })
        }
        endFind(); session.activeSpaceID = id
        renderingSpaceSwitch = animate
        render(); showSelectedTab(); persist()
        renderingSpaceSwitch = false
        if let transition = spaceSwitch {
            transition.run(views:spaceSwitchViews,towardsRight:next > previous) { [weak self, weak transition] in
                if self?.spaceSwitch === transition { self?.spaceSwitch = nil }
            }
        }
    }
    private func navigate(_ input: String, newTab: Bool) {
        guard !isQuitting else { return }
        if isExtensionsAddress(input) { manageExtensionsAction(nil); return }
        guard let url = browserURL(input,engine:currentEngine) else { showError(t("invalidURL"), detail: input); return }
        if url.scheme?.lowercased() == "https", url.host?.lowercased() == "chromewebstore.google.com", url.user == nil, url.password == nil {
            openExtensions(store:true, address:url.absoluteString); return
        }
        var id = activeTab?.id
        if newTab || id == nil { id = session.createTab(url: url.absoluteString, spaceID: session.activeSpaceID) }
        guard let tabID = id, let index = session.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        session.tabs[index].url = url.absoluteString; status[tabID]?.error = nil
        if containers[tabID] != nil { engine.navigateTab(tabID, url: url.absoluteString) }
        render(); showSelectedTab(); persist()
    }
    private func displayTitle(_ tab: NativeTab) -> String { !tab.displayTitle.isEmpty ? tab.displayTitle : (URL(string: tab.url)?.host ?? t("newTab")) }

    // NSTableView owns scrolling, accessibility and row recycling; page views never enter the UI process.
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .heading = rows[row] { return 24 }
        if case .tab(let id) = rows[row], let group = session.splitGroup(containing:id), group.name != nil || group.icon != nil { return 60 }
        return 36
    }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard rows.indices.contains(row) else { return false }
        switch rows[row] {
        case .tab: return true
        case .folder: return true
        case .newTab: newTabAction(nil); return false
        case .heading: return false
        }
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard sidebarTitleEditor?.isEditingTitle != true else { return }
        guard !isRendering, !table.handlingMouseDown, rows.indices.contains(table.selectedRow), case .tab(let id) = rows[table.selectedRow] else { return }
        // Focusing an inline field selects its row as well. Reloading that same
        // active tab here destroys the field editor just as it receives focus.
        guard id != activeTab?.id else { return }
        selectTab(id)
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        if case .heading = rows[row] {
            let holder = FlippedView(frame: NSRect(x:0,y:0,width:tableView.bounds.width,height:24))
            let line = NSView(frame:NSRect(x:10,y:12,width:max(25,tableView.bounds.width-72),height:0.5)); line.wantsLayer = true; line.layer?.backgroundColor = sidebarInk.withAlphaComponent(0.13).cgColor; line.autoresizingMask = [.width]; holder.addSubview(line)
            let clear = ActionButton("↓ " + t("clear")) { [weak self] in self?.clearTemporaryTabs() }; clear.font = .systemFont(ofSize:10,weight:.semibold); clear.frame = NSRect(x:tableView.bounds.width-61,y:1,width:55,height:22); clear.autoresizingMask = [.minXMargin]; style(clear,opacity:0.42); holder.addSubview(clear); return holder
        }
        if case .tab(let id) = rows[row], let group = session.splitGroup(containing:id) { return makeSplitCell(group) }
        let cell = (copyingSpaceRows ? nil : tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("tabCell"), owner: self) as? TabCell) ?? TabCell(frame: .zero)
        cell.identifier = NSUserInterfaceItemIdentifier("tabCell"); cell.active = false; cell.canClose = false; cell.isFolder = false
        cell.developerMode = false
        cell.rename = nil
        cell.ink = sidebarInk; cell.depth = treeRows.indices.contains(row) ? treeRows[row].depth : 0
        cell.titleLabel.font = .systemFont(ofSize:14)
        switch rows[row] {
        case .tab(let id):
            guard let tab = session.tabs.first(where: { $0.id == id }) else { return cell }
            cell.titleLabel.stringValue = displayTitle(tab); cell.toolTip = tab.url; cell.active = id == activeTab?.id && commandPalette?.isNewTab != true
            cell.icon.image = splitTabIcon(tab)
            cell.developerMode = tab.developerMode == true && id == activeTab?.id
            cell.canClose = true; cell.closeButton.toolTip = t("closeTab"); cell.closeButton.setAccessibilityLabel(t("closeTab"))
            cell.closeButton.invoke = { [weak self] in self?.requestCloseTab(id) }
            cell.rename = { [weak self] name in
                guard let self else { return }
                _ = self.session.renameTab(id: id, name: name)
                self.refreshTabVisual(id); self.persist()
            }
        case .folder(let id):
            guard let folder = session.folders.first(where: { $0.id == id }) else { return cell }
            cell.isFolder = true
            cell.titleLabel.font = .systemFont(ofSize:14,weight:.semibold)
            cell.titleLabel.stringValue = folder.name; cell.toolTip = folder.name
            cell.icon.image = folder.liveHost == nil ? Self.folderImage(open:!folder.collapsed) : NSImage(systemSymbolName:"folder.badge.gearshape",accessibilityDescription:t("folder"))
        case .heading:
            cell.titleLabel.stringValue = ""; cell.icon.image = nil; cell.toolTip = nil
        case .newTab:
            cell.active = commandPalette?.isNewTab == true
            cell.titleLabel.stringValue = t("newTab"); cell.titleLabel.textColor = sidebarInk.withAlphaComponent(0.48); cell.toolTip = t("newTab")
            cell.icon.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        }
        return cell
    }
    private static func folderImage(open: Bool) -> NSImage {
        let image = NSImage(size:NSSize(width:20,height:20),flipped:false) { _ in
            NSColor.labelColor.setStroke()
            let back = NSBezierPath(); back.lineWidth = 1.5; back.lineJoinStyle = .round
            back.move(to:NSPoint(x:2,y:4)); back.line(to:NSPoint(x:2,y:16)); back.line(to:NSPoint(x:7,y:16))
            back.line(to:NSPoint(x:9,y:14)); back.line(to:NSPoint(x:17,y:14)); back.line(to:NSPoint(x:17,y:4)); back.close()
            back.stroke()
            let front = NSBezierPath(); front.lineWidth = 1.5; front.lineJoinStyle = .round
            front.move(to:NSPoint(x:2,y:4)); front.line(to:NSPoint(x:open ? 6 : 2,y:12))
            front.line(to:NSPoint(x:19,y:12)); front.line(to:NSPoint(x:open ? 16 : 19,y:4)); front.close()
            NSColor.labelColor.withAlphaComponent(0.15).setFill(); front.fill(); front.stroke(); return true
        }
        image.isTemplate = true; return image
    }
    private func toggleSpaceFolders() {
        sidebarCollapse.toggle(.space(session.activeSpaceID),in:&session)
        render(); persist()
    }
    private func clickSidebarRow(_ row: Int) {
        guard rows.indices.contains(row) else { return }
        switch rows[row] {
        case .folder(let id):
            sidebarCollapse.toggle(.folder(id),in:&session); render(); persist()
        case .tab(let id):
            // Capture the active tab before selection: the click that opens an
            // inactive tab must never also enter its title editor.
            let editTitle = table.clickedTitle && activeTab?.id == id
            selectTab(id)
            if editTitle {
                // Wait for NSTableView's selection tracking and CEF focus to finish.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.activeTab?.id == id,
                          let index = self.rows.firstIndex(where: { if case .tab(let value) = $0 { return value == id }; return false }),
                          let cell = self.table.view(atColumn:0,row:index,makeIfNecessary:true) as? TabCell else { return }
                    self.beginSidebarTitleEditing(cell)
                }
            }
        default: break
        }
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard rows.indices.contains(row) else { return nil }
        let item = NSPasteboardItem()
        switch rows[row] {
        case .tab(let id): item.setString(id,forType:dragType)
        case .folder(let id): item.setString(id,forType:folderDragType)
        default: return nil
        }
        return item
    }
    func tableView(_ tableView: NSTableView, draggingSession: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        table.didDrag = true; favoriteDragBaseline = favorites.frame.height; sidebarDragActive = true; cancelSidebarHover(); clearDropProposal(); layoutFavorites(animated:true)
    }
    func tableView(_ tableView: NSTableView, draggingSession: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        sidebarDragActive = false; favoriteDragBaseline = 0; sidebarMousePressed = false; favorites.clearPreview(); clearDropProposal(); layoutFavorites(animated:true); updateSidebarHover()
    }
    private func acceptFavorite(_ id: String, at position: Int) -> Bool {
        guard session.moveToFavorites(id,spaceID:session.activeSpaceID,at:position) else { return false }
        session.detachSplitTab(id)
        render(); showSelectedTab(); persist(); return true
    }
    private func clearDropProposal() { splitDropTarget = nil; splitLimitTarget = nil; dropDestination = nil; dropItem = nil; lastDropFeedback = nil; table.insertion = nil }
    private func draggedItem(_ info: NSDraggingInfo) -> SidebarItem? {
        guard (info.draggingSource as? NSTableView) === table || favorites.ownsDrag(info.draggingSource) || (info.draggingSource as? SplitTabChip)?.window === window else { return nil }
        if let id = info.draggingPasteboard.string(forType:folderDragType) { return .folder(id) }
        if let id = info.draggingPasteboard.string(forType:dragType) { return .tab(id) }
        return nil
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard let item = draggedItem(info) else { clearDropProposal(); return [] }
        let point = table.convert(info.draggingLocation,from:nil)
        let hit = table.row(at:point)
        if case .tab(let source) = item, rows.indices.contains(hit), case .tab(let target) = rows[hit] {
            let rect = table.rect(ofRow:hit), fraction = (point.y-rect.minY)/rect.height
            if fraction > 0.22 && fraction < 0.78, let ids = session.splitMergeIDs(source,onto:target) {
                if ids.count > 4 {
                    if splitLimitTarget != target { splitLimitTarget = target; splitLimitNotice() }
                    splitDropTarget = nil; table.insertion = nil; return []
                }
                if splitDropTarget != target { NSHapticFeedbackManager.defaultPerformer.perform(.alignment,performanceTime:.now) }
                splitDropTarget = target; dropItem = item; dropDestination = nil
                table.setDropRow(hit,dropOperation:.on); table.insertion = (hit,0,true)
                return .move
            }
        }
        splitDropTarget = nil; splitLimitTarget = nil
        var destination = SidebarDestination(parentID:nil,before:nil)
        var markerRow = treeRows.count, depth = 0, inside = false
        if treeRows.indices.contains(hit) {
            let entry = treeRows[hit], rect = table.rect(ofRow:hit)
            let fraction = (point.y-rect.minY)/rect.height
            if case .folder(let id) = entry.item, fraction > 0.25 && fraction < 0.75 {
                destination.parentID = id; markerRow = hit; depth = entry.depth; inside = true
            } else {
                // Top/bottom edges insert beside a row, the center nests in a folder.
                let below = fraction >= 0.5
                var anchor = entry
                let requestedDepth = max(0,Int((point.x-10)/16))
                if below && requestedDepth < entry.depth {
                    var i = hit
                    while i > 0 && treeRows[i].depth > requestedDepth { i -= 1 }
                    anchor = treeRows[i]
                    markerRow = i+1
                } else { markerRow = hit+(below ? 1 : 0) }
                destination.parentID = anchor.parentID; depth = anchor.depth
                let siblings = session.sidebarChildren(spaceID:session.activeSpaceID,parentID:anchor.parentID)
                if below, let index = siblings.firstIndex(of:anchor.item) {
                    destination.before = index+1 < siblings.count ? siblings[index+1] : nil
                    while markerRow < treeRows.count && treeRows[markerRow].depth > depth { markerRow += 1 }
                } else { destination.before = anchor.item }
            }
        } else if case .tab = item, hit > treeRows.count || hit == -1 && point.y > table.rect(ofRow:max(0,rows.count-1)).maxY {
            destination.temporary = true
            markerRow = max(treeRows.count+2,min(row,rows.count))
            if rows.indices.contains(hit), case .tab(let id) = rows[hit] {
                let below = point.y > table.rect(ofRow:hit).midY
                let peers = session.sidebarChildren(spaceID:session.activeSpaceID,parentID:nil,temporary:true)
                if below, let index = peers.firstIndex(of:.tab(id)) { destination.before = index+1 < peers.count ? peers[index+1] : nil; markerRow = hit+1 }
                else { destination.before = .tab(id); markerRow = hit }
            }
        }
        guard session.canMoveSidebarItem(item,spaceID:session.activeSpaceID,to:destination) else { clearDropProposal(); return [] }
        dropDestination = destination; dropItem = item
        table.setDropRow(markerRow,dropOperation:inside ? .on : .above)
        table.insertion = (markerRow,min(depth,8),inside)
        if lastDropFeedback != destination {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment,performanceTime:.now)
            lastDropFeedback = destination
        }
        return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        if let target = splitDropTarget, case .tab(let source)? = draggedItem(info) {
            let accepted = session.mergeSplit(source,onto:target)
            clearDropProposal(); if accepted { render(); showSelectedTab(); persist() }; return accepted
        }
        guard let item = draggedItem(info), item == dropItem, let destination = dropDestination,
              session.canMoveSidebarItem(item,spaceID:session.activeSpaceID,to:destination) else { clearDropProposal(); return false }
        if case .tab(let id) = item { session.detachSplitTab(id) }
        guard session.moveSidebarItem(item,spaceID:session.activeSpaceID,to:destination) else { clearDropProposal(); return false }
        clearDropProposal(); render(); showSelectedTab(); persist(); return true
    }
    private func addMenu(_ menu: NSMenu, _ title: String, _ kind: String, _ id: String, _ value: String = "") {
        let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: ""); item.target = self; item.representedObject = MenuAction(kind, id, value); menu.addItem(item)
    }
    private func tabMenu(_ tab: NativeTab) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        addMenu(menu, splitText("Copier le lien","Copy Link"), "tabCopy", tab.id)
        let sharing = NSMenu(); addMenu(sharing,splitText("Partager…","Share…"),"tabShare",tab.id); addSubmenu(menu,splitText("Partager","Share"),sharing)
        menu.addItem(.separator())
        addMenu(menu,splitText("Changer l’icône…","Change Icon…"),"tabIcon",tab.id)
        addMenu(menu,splitText("Renommer","Rename"),"tabRename",tab.id)
        addMenu(menu,splitText("Activer / couper le son","Toggle Mute"),"tabMute",tab.id)
        addMenu(menu,splitText("Personnaliser la page…","Customize Page…"),"unavailable",tab.id); menu.items.last?.isEnabled = false
        menu.addItem(.separator())
        addMenu(menu,splitText("Ajouter une vue partagée","Add Split View"),"splitAdd",tab.id)
        if session.splitGroup(containing:tab.id) != nil { addMenu(menu,splitText("Séparer cet onglet","Separate This Tab"),"splitDetach",tab.id) }
        addMenu(menu, t("duplicate"), "duplicate", tab.id)
        let move = NSMenuItem(title: t("move"), action: nil, keyEquivalent: ""); let spaces = NSMenu(); spaces.autoenablesItems = false
        for s in session.spaces where s.id != tab.spaceID { addMenu(spaces, SpaceIcon.title(s), "move", tab.id, s.id) }
        move.submenu = spaces; if !spaces.items.isEmpty { menu.addItem(move) }
        let folderItem = NSMenuItem(title: t("moveFolder"), action: nil, keyEquivalent: ""); let folders = NSMenu(); folders.autoenablesItems = false
        for f in session.folders where f.spaceID == (tab.favorite ? session.activeSpaceID : tab.spaceID) && f.id != tab.folderID && f.liveHost == nil { addMenu(folders, f.name, "folder", tab.id, f.id) }
        if tab.folderID != nil { addMenu(folders, t("noFolder"), "unfolder", tab.id) }; folderItem.submenu = folders; if !folders.items.isEmpty { menu.addItem(folderItem) }
        let placement = NSMenu(); placement.autoenablesItems = false
        addMenu(placement,t(tab.pinned ? "unpin" : "pin"),"pin",tab.id)
        addMenu(placement,t(tab.favorite ? "unfavorite" : "favorite"),"favorite",tab.id)
        addSubmenu(menu,splitText("Épinglage","Pinning"),placement)
        menu.addItem(.separator()); addMenu(menu,splitText("Archiver l’onglet","Archive Tab"),"close",tab.id)
        addMenu(menu,splitText("Archiver les onglets suivants","Archive Tabs Below"),"tabsBelow",tab.id)
        menu.items.last?.isEnabled = !tabsBelow(tab.id).isEmpty
        return menu
    }
    private func spaceMenu(_ space: NativeSpace) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        addMenu(menu,t("changeSpaceIcon"),"spaceIcon",space.id)
        addMenu(menu,t("renameSpace"),"spaceName",space.id)
        addMenu(menu,t("editTheme"),"spaceColor",space.id)
        let profiles = NSMenu(); profiles.autoenablesItems = false
        for profile in session.profiles {
            addMenu(profiles,profile.name,"spaceProfile",space.id,profile.id)
            profiles.items.last?.state = profile.id == space.profileID ? .on : .off
            profiles.items.last?.isEnabled = profileReloads[space.id] == nil
        }
        profiles.addItem(.separator()); addMenu(profiles,t("newProfile") + "…","spaceNewProfile",space.id)
        profiles.items.last?.isEnabled = !isPrivateWindow
        addSubmenu(menu,t("setProfile"),profiles)
        menu.addItem(.separator())
        addMenu(menu,t("newFolder"),"newFolder",space.id)
        let live = NSMenu(); live.autoenablesItems = false
        addMenu(live,t("liveBySite"),"liveFolder",space.id)
        if let host = activeTab.flatMap({ URL(string: $0.url)?.host }), activeTab?.spaceID == space.id {
            addMenu(live,t("liveCurrentSite") + " — " + host,"liveFolderHost",space.id,host)
        }
        addSubmenu(menu,t("liveFolders"),live)
        menu.addItem(.separator())
        addMenu(menu,t("shareSpace"),"shareSpace",space.id)
        let export = NSMenu(); export.autoenablesItems = false
        for target in session.spaces where target.id != space.id { addMenu(export,SpaceIcon.title(target),"exportSpaceFolder",space.id,target.id) }
        addMenu(export,t("newSpace") + "…","exportNewSpace",space.id)
        export.addItem(.separator()); addMenu(export,t("exportHTML"),"exportHTML",space.id)
        addSubmenu(menu,String(format:t("exportSpace"),space.name),export)
        menu.addItem(.separator()); addMenu(menu,t("manageSpaces"),"manageSpaces",space.id)
        menu.addItem(.separator()); addMenu(menu,t("deleteSpaceMenu"),"deleteSpace",space.id)
        menu.items.last?.isEnabled = session.spaces.count > 1 && profileReloads[space.id] == nil
        if session.spaces.count == 1 { menu.items.last?.toolTip = t("lastSpace") }
        return menu
    }
    private func addSubmenu(_ menu: NSMenu, _ title: String, _ submenu: NSMenu) {
        let item = NSMenuItem(title:title,action:nil,keyEquivalent:""); item.submenu = submenu; menu.addItem(item)
    }
    private func menuForRow(_ row: Int) -> NSMenu? {
        guard rows.indices.contains(row) else { return activeSpace.map(spaceMenu) }
        switch rows[row] {
        case .tab(let id): if let group = session.splitGroup(containing:id) { return splitGroupMenu(group) }; return session.tabs.first(where: { $0.id == id }).map(tabMenu)
        case .folder(let id): let menu = NSMenu(); menu.autoenablesItems = false; addMenu(menu, t("rename"), "renameFolder", id); if session.folders.first(where: { $0.id == id })?.liveHost == nil { addMenu(menu,t("newFolder"),"newSubfolder",id) }; if let folder = session.folders.first(where: { $0.id == id }), folder.liveHost != nil { addMenu(menu,t("editLiveFolder"),"editLiveFolder",id) }; addMenu(menu, t("delete"), "deleteFolder", id); return menu
        default: return activeSpace.map(spaceMenu)
        }
    }
    @objc private func menuAction(_ sender: NSMenuItem) {
        guard !isQuitting else { return }
        guard let command = sender.representedObject as? MenuAction else { return }
        if handleSplitMenu(command) { return }
        let index = session.tabs.firstIndex { $0.id == command.id }
        if ["pin","favorite","folder","unfolder"].contains(command.kind) { session.detachSplitTab(command.id) }
        switch command.kind {
        case "downloads": if let url = FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask).first { NSWorkspace.shared.open(url) }; return
        case "settings": settingsAction(nil); return
        case "restore": restoreTabAction(nil); return
        case "newWindow": newWindowRequested?(.normal)
        case "blankWindow": newWindowRequested?(.blank)
        case "incognito": newWindowRequested?(.privateWindow)
        case "littleWindow": newWindowRequested?(.compact)
        case "newTab": newTabAction(nil); return
        case "newSpace": newSpaceAction(nil); return
        case "newFolder": newFolder(spaceID: command.id.isEmpty ? nil : command.id); return
        case "spaceName": renameSpace(command.id); return
        case "spaceIcon": editSpaceAppearance(command.id, icon: true); return
        case "spaceColor": editSpaceAppearance(command.id, icon: false); return
        case "spaceProfile": changeProfile(command.id, to:command.value); return
        case "spaceNewProfile": guard !isPrivateWindow else { return }; promptName(t("newProfile")) { [weak self] name in
            guard let self, self.session.profiles.count < 50 else { return }
            let profile = NativeProfile(id:UUID().uuidString,name:name); self.session.profiles.append(profile); self.configureEngine(profile.engine,profileID:profile.id); self.persist(); self.changeProfile(command.id,to:profile.id)
        }; return
        case "liveFolder": editLiveFolder(spaceID:command.id); return
        case "liveFolderHost": editLiveFolder(spaceID:command.id,initial:command.value); return
        case "editLiveFolder": if let f = session.folders.first(where: { $0.id == command.id }) { editLiveFolder(spaceID:f.spaceID,initial:f.liveHost ?? "",folderID:f.id) }; return
        case "shareSpace": shareSpace(command.id); return
        case "exportHTML": exportSpaceHTML(command.id); return
        case "exportSpaceFolder": exportSpace(command.id,to:command.value); return
        case "exportNewSpace": promptName(t("newSpace")) { [weak self] name in
            guard let self, let source = self.session.spaces.first(where: { $0.id == command.id }) else { return }
            let original = self.session
            let target = self.session.createSpace(name:name,color:source.color,icon:source.icon,profileID:source.profileID)
            guard !target.isEmpty, self.session.exportSpaceIntoFolder(source.id,targetID:target) else { self.session = original; self.showError(self.t("exportError"),detail:self.t("limitReached")); return }
            self.render(); self.showSelectedTab(); self.persist()
        }; return
        case "manageSpaces": manageSpaces(); return
        case "pin": if let i = index { session.tabs[i].pinned.toggle(); if !session.tabs[i].pinned { session.tabs[i].lastViewedAt = Date(); if session.tabs[i].favorite { session.detachFavoriteReferences(to:command.id) }; session.tabs[i].favorite = false; session.tabs[i].folderID = nil } }
        case "favorite": if let i = index {
            let spaceID = session.activeSpaceID
            if session.tabs[i].favorite { _ = session.moveSidebarItem(.tab(command.id),spaceID:spaceID,to:SidebarDestination(parentID:nil,before:nil,temporary:true)) }
            else { _ = session.moveToFavorites(command.id,spaceID:spaceID,at:session.favoriteTabs(spaceID:spaceID).count) }
        }
        case "duplicate": if let i = index { _ = session.createTab(url: session.tabs[i].url, spaceID: session.tabs[i].spaceID) }
        case "close": requestCloseTab(command.id); return
        case "move":
            if let i = index, let target = session.spaces.first(where: { $0.id == command.value }) {
                let oldSpace = session.tabs[i].spaceID
                // Cookies belong to a profile. Moving between profiles recreates the view with the target partition.
                if let old = session.spaces.first(where: { $0.id == oldSpace }), old.profileID != target.profileID, containers[command.id] != nil {
                    showError(t("move"), detail: session.language == "fr" ? "Ouvrez une copie de cet onglet dans un espace du nouveau profil pour conserver les connexions séparées." : "Open a copy in a space using the other profile to keep sign-ins separate."); return
                }
                session.detachSplitTab(command.id)
                session.tabs[i].spaceID = target.id; session.tabs[i].folderID = nil
                if let oldIndex = session.spaces.firstIndex(where: { $0.id == oldSpace }), session.spaces[oldIndex].selectedTabID == command.id { session.spaces[oldIndex].selectedTabID = session.tabs.first { $0.spaceID == oldSpace }?.id }
                session.selectTab(id: command.id)
            }
        case "folder": if let i = index { _ = session.moveSidebarItem(.tab(command.id),spaceID:session.tabs[i].favorite ? session.activeSpaceID : session.tabs[i].spaceID,to:SidebarDestination(parentID:command.value,before:nil)) }
        case "unfolder": if let i = index { _ = session.moveSidebarItem(.tab(command.id),spaceID:session.tabs[i].spaceID,to:SidebarDestination(parentID:nil,before:nil)) }
        case "editSpace": if let s = session.spaces.first(where: { $0.id == command.id }) { showSpaceForm(s) }; return
        case "selectSpace": selectSpace(command.id); return
        case "deleteSpace": deleteSpace(command.id); return
        case "newSubfolder": newFolder(parentID:command.id); return
        case "renameFolder": renameFolder(command.id); return
        case "deleteFolder": session.removeFolder(command.id)
        default: return
        }
        render(); showSelectedTab(); persist()
    }
    private var pendingClose = Set<String>()
    private var archiveVisible = Set<String>()
    private var archiveProbing = Set<String>()
    private var automaticClose = [String: () -> Bool]()

    var archiveProtectedIDs: Set<String> {
        var ids = Set(activeSplit?.tabIDs ?? activeTab.map { [$0.id] } ?? [])
        ids.formUnion(pendingClose.subtracting(automaticClose.keys)); ids.formUnion(destructiveClosing); ids.formUnion(pendingCaptures)
        for operation in profileReloads.values { ids.formUnion(operation.waiting) }
        for closing in pendingSpaceClosures.values { ids.formUnion(closing) }
        if let id = pageCapture?.tabID { ids.insert(id) }
        if let id = portraitCapture?.tabID { ids.insert(id) }
        return ids
    }
    func seedArchiveDates(at now:Date) {
        if session.seedArchiveClock(at:now) { persist() }
    }
    func hasArchiveRenderer(_ id:String) -> Bool { containers[id] != nil }

    func archiveDormantTabs(_ ids:[String],at now:Date) {
        guard !ids.isEmpty, !isQuitting, !closingWindow else { return }
        var candidate = session
        for id in ids { candidate.closeTab(id:id,automaticallyAt:now) }
        do { try store.save(candidate) }
        catch { NSLog("Auto archive: %@",error.localizedDescription); return }
        session = candidate; render(); library?.update(session:session)
    }

    func probeForAutoArchive(_ id:String,stillEligible:@escaping ()->Bool) {
        guard !isQuitting, !closingWindow, !pendingClose.contains(id), !archiveProbing.contains(id),
              !engine.hasPictureInPicture(id), !engine.hasDeveloperTools(id) else { return }
        archiveProbing.insert(id)
        engine.checkArchiveIdle(id) { [weak self] idle in
            guard let self else { return }
            self.archiveProbing.remove(id)
            guard !self.isQuitting, !self.closingWindow, stillEligible() else { return }
            guard idle else { self.resetArchiveClock(id); return }
            self.automaticClose[id] = stillEligible; self.pendingClose.insert(id)
            self.engine.tryAutoArchiveTab(id)
        }
    }
    private func resetArchiveClock(_ id:String) {
        if let i = session.tabs.firstIndex(where:{ $0.id == id }) {
            session.tabs[i].lastViewedAt = Date(); persist()
        }
    }

    private func requestCloseTab(_ id: String) {
        guard !isQuitting else { return }
        if containers[id] != nil { pendingClose.insert(id); engine.closeTab(id) }
        else { session.closeTab(id: id); render(); showSelectedTab(); persist() }
    }
    @objc func newTabAction(_ sender: Any?) {
        guard !isQuitting, spaceCreation == nil else { return }
        if let home = session.profile(forSpace:session.activeSpaceID)?.homepage {
            commandPalette?.close()
            if windowKind == .compact { navigate(home,newTab:false) }
            else if !session.createTab(url:home).isEmpty { render(); showSelectedTab(); persist() }
        } else { showCommand(newTab:windowKind != .compact) }
    }
    @objc func openLocationAction(_ sender: Any?) { guard spaceCreation == nil else { return }; showCommand(newTab: false) }
    @objc func closeTabAction(_ sender: Any?) { if windowKind == .compact { requestWindowClose() } else if let tab = activeTab { requestCloseTab(tab.id) } }
    @objc func restoreTabAction(_ sender: Any?) { guard !isQuitting else { return }; session.restoreTab(); render(); showSelectedTab(); persist() }
    @objc func toggleSidebarAction(_ sender: Any?) {
        setSidebarHidden(!session.sidebarHidden)
    }
    private func setSidebarHidden(_ hidden:Bool) {
        guard windowKind != .compact, session.sidebarHidden != hidden else { return }
        cancelSidebarHover()
        sidebarTransition += 1; sidebarAnimating = false
        session.sidebarHidden = hidden
        preferencesWindow?.refreshSidebarVisibility(hidden)
        sidebarRevealed = hidden
        updateBackgroundSidebarTracking()
        layout()
        if session.sidebarHidden { setSidebarRevealed(false) }
        persist()
    }
    @objc func newSpaceAction(_ sender: Any?) { showSpaceForm(nil) }
    @objc func nextSpaceAction(_ sender: Any?) { cycleSpace(direction: 1) }
    @objc func previousSpaceAction(_ sender: Any?) { cycleSpace(direction: -1) }
    private func cycleSpace(direction: Int) {
        guard !isQuitting, !session.spaces.isEmpty, let current = session.spaces.firstIndex(where: { $0.id == session.activeSpaceID }) else { return }
        let next = (current + direction + session.spaces.count) % session.spaces.count
        selectSpace(session.spaces[next].id)
    }
    private var copyableURL: URL? {
        guard let text = activeTab?.url, let url = URL(string:text),
              ["http","https","file"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
    private func showNotice(_ key:String) {
        undoToast.show(in:window,message:"✓  "+t(key),suffix:"",undoLabel:"",color:tint(),offersUndo:false)
    }
    private func copyActiveURL() {
        guard let url = copyableURL else { return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([url as NSURL]) else { return }
        NSPasteboard.general.setString(url.absoluteString,forType:.string)
        copyLinkButton.copied(); showNotice("urlCopied")
    }
    private func showSiteMenu(anchor:NSView? = nil) {
        engine.closeExtensionPopup(); extensionInstallNotice?.close()
        if siteMenu?.isShown == true { siteMenu?.close(); return }
        guard let tab = activeTab, let url = copyableURL else { return }
        commandPalette?.close(); themeEditor?.close(animated:false); iconPicker?.close(); addMenu?.close()
        let loaded = containers[tab.id] != nil
        let web = ["http","https"].contains(url.scheme?.lowercased() ?? "")
        let certificate = engine.certificateInfo(forTab:tab.id).flatMap { SiteCertificate(info:$0) }
        let menuAnchor:NSView = anchor ?? siteMenuButton
        let menu = SiteMenu(language:session.language,color:tint(),secureConnection:certificate?.isSecure == true,developerOpen:tab.developerMode == true,automaticPiP:session.automaticPictureInPictureEnabled(for:tab),pipOpen:engine.hasPictureInPicture(tab.id),extensions:extensionCatalog.entries(profile:activeSpace?.profileID ?? "",force:true),
                            pinned:Set(extensionCatalog.pins(profile:activeSpace?.profileID ?? "")),
                            activateExtension:{ [weak self, weak menuAnchor] item in
                                guard let menuAnchor else { return }
                                self?.activateExtension(item, from:menuAnchor)
                            },
                            pinExtension:{ [weak self] in self?.toggleExtensionPin($0) },actions:.init(
            share:{ [weak self] in
                guard let self else { return }
                let picker = NSSharingServicePicker(items:[url]); self.sharingPicker = picker
                picker.show(relativeTo:self.siteMenuButton.bounds,of:self.siteMenuButton,preferredEdge:.maxY)
            },
            capture:loaded ? { [weak self] in self?.startPageCapture(for:tab.id) } : nil,
            find:loaded ? { [weak self] in self?.findAction(nil) } : nil,
            developer:loaded ? { [weak self] in self?.toggleDeveloperMode(for:tab.id) } : nil,
            pictureInPicture:loaded && web ? { [weak self] in self?.togglePictureInPicture(for:tab.id) } : nil,
            automaticPictureInPicture:web ? { [weak self] in
                guard let self else { return }
                self.session.setAutomaticPictureInPicture(!self.session.automaticPictureInPictureEnabled(for:tab),for:tab)
                self.persist(); self.showSelectedTab()
            } : nil,
            clearCache:loaded ? { [weak self] in
                self?.engine.clearCache(forTab:tab.id) { [weak self] ok in
                    guard let self, !self.isQuitting else { return }
                    if ok { self.showNotice("cacheCleared") } else { self.showError(self.t("siteActionFailed"),detail:"") }
                }
            } : nil,
            clearCookies:loaded && web ? { [weak self] in
                self?.engine.clearCookies(forTab:tab.id) { [weak self] ok in
                    guard let self, !self.isQuitting else { return }
                    if ok { self.showNotice("cookiesCleared") } else { self.showError(self.t("siteActionFailed"),detail:"") }
                }
            } : nil,
            manageExtensions:isPrivateWindow ? nil : { [weak self] in self?.manageExtensionsAction(nil) },
            addExtension:isPrivateWindow ? nil : { [weak self] in self?.addExtensionAction(nil) },
            certificate:certificate.map { certificate in { [weak self] in
                guard let self, !self.isQuitting else { return }
                certificate.show(in:self.window)
            } },
            allSiteSettings:web ? { [weak self] in self?.openSiteSettings(for:tab.id) } : nil
        ),dismissed:{ [weak self] in
            self?.engine.setPageInputSuppressed(false,forTab:tab.id)
            self?.siteMenu = nil; self?.spaceButton?.suppressHover = false; self?.siteMenuButton.menuOpen = false; self?.updateSidebarHover()
        })
        engine.setPageInputSuppressed(true,forTab:tab.id)
        menu.pointerChanged = { [weak self] in self?.clearSidebarPointerFeedback() }
        spaceButton?.suppressHover = true
        siteMenu = menu; siteMenuButton.menuOpen = true; menu.show(of:menuAnchor)
        if !menu.isShown {
            engine.setPageInputSuppressed(false,forTab:tab.id)
            siteMenu = nil; spaceButton?.suppressHover = false; siteMenuButton.menuOpen = false
        }
    }
    @objc func backAction(_ sender: Any?) { if let id = activeTab?.id { engine.goBack(id) } }
    @objc func pictureInPictureAction(_ sender: Any?) {
        guard let id = activeTab?.id else { return }
        togglePictureInPicture(for:id)
    }
    private func togglePictureInPicture(for id:String) {
        pictureInPicture.toggle(id) { [weak self] result in
            guard let self, !self.isQuitting else { return }
            if result == "no-video" { self.showNotice("pipNoVideo") }
            else if result == "unavailable" { self.showNotice("pipUnavailable") }
        }
    }
    func browserPictureInPictureReturn(_ tabID:String) {
        guard !isQuitting, session.tabs.contains(where: { $0.id == tabID }) else { return }
        selectTab(tabID)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        engine.focusTab(tabID)
    }
    private func refreshExtensionToolbar() {
        guard let profile = activeSpace?.profileID else { return }
        let items = extensionCatalog.entries(profile:profile)
        let pins = extensionCatalog.pins(profile:profile)
        let pinned = pins.compactMap { id in items.first { $0.id == id } }
        // Two direct actions, then an explicit overflow. Resizing the sidebar
        // must never silently hide or remove a pin.
        let visible = Array(pinned.prefix(2))
        overflowExtensions = Array(pinned.dropFirst(2))
        let signature = profile+":"+pinned.map { $0.id+":"+$0.name }.joined(separator:",")
        guard signature != extensionSignature else { return }; extensionSignature = signature
        extensionButtons.forEach { $0.removeFromSuperview() }
        extensionButtons = visible.map { item in
            let button = ExtensionActionButton(item) { [weak self] in self?.activateExtension(item) }
            button.ink = sidebarInk; addressBackground.addSubview(button); return button
        }
        extensionOverflowButton.ink = sidebarInk
        extensionOverflowButton.isHidden = overflowExtensions.isEmpty
        let label = session.language == "fr" ? "Autres extensions épinglées" : "More pinned extensions"
        extensionOverflowButton.toolTip = label
        extensionOverflowButton.setAccessibilityLabel(label)
        if extensionOverflowButton.superview == nil { addressBackground.addSubview(extensionOverflowButton) }
        layout()
    }
    private func showExtensionOverflow() {
        guard !overflowExtensions.isEmpty else { return }
        engine.closeExtensionPopup()
        let menu = NSMenu(); menu.autoenablesItems = false
        for entry in overflowExtensions {
            let item = NSMenuItem(title:entry.name,action:#selector(activateOverflowExtension(_:)),keyEquivalent:"")
            item.target = self; item.representedObject = entry.id
            item.image = entry.image?.copy() as? NSImage; item.image?.size = NSSize(width:18,height:18)
            menu.addItem(item)
        }
        menu.popUp(positioning:nil,at:NSPoint(x:0,y:extensionOverflowButton.bounds.maxY),in:extensionOverflowButton)
    }
    @objc private func activateOverflowExtension(_ sender:NSMenuItem) {
        guard let id = sender.representedObject as? String, let item = overflowExtensions.first(where:{ $0.id == id }) else { return }
        // Finish menu tracking before handing keyboard focus to Chromium.
        DispatchQueue.main.async { [weak self] in self?.activateExtension(item) }
    }
    private func toggleExtensionPin(_ item:BrowserExtension) {
        guard let profile = activeSpace?.profileID else { return }
        let pinned = !extensionCatalog.pins(profile:profile).contains(item.id)
        guard engine.setExtensionPinned(item.id,profile:profile,pinned:pinned) else {
            showError(t("siteActionFailed"),detail:item.name); return
        }
        extensionCatalog.togglePin(item.id,profile:profile)
        extensionSignature = ""; refreshExtensionToolbar(); layout()
    }
    private func activateExtension(_ item:BrowserExtension, from source:NSView? = nil) {
        guard let tab = activeTab else { return }
        let requested = ProcessInfo.processInfo.systemUptime
        let anchor: NSView = source ?? (extensionButtons.first(where: { $0.identifier?.rawValue == item.id }) as NSView?) ?? (overflowExtensions.contains(where:{ $0.id == item.id }) ? extensionOverflowButton : siteMenuButton)
        guard let anchorWindow = anchor.window else { return }
        let screenRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        extensionInstallNotice?.close()
        let open:()->Void = { [weak self] in
            guard let self, self.activeTab?.id == tab.id else { return }
            NSLog("Extension %@: handoff after %.1f ms",item.id,(ProcessInfo.processInfo.systemUptime-requested)*1000)
            let result = self.engine.activateExtension(item.id,tab:tab.id,anchor:screenRect)
            if result != 0 {
                NSLog("Native extension action failed (%ld) for %@",result,item.id)
                self.showError(self.t("siteActionFailed"),detail:item.name)
            }
        }
        // Wait for the AppKit popover to finish resigning focus before Chrome
        // gives focus to the extension. A queued next-runloop open races it.
        if let menu = siteMenu, menu.isShown { menu.close(animated:false,completion:open) }
        else { open() }
    }
    func browserExtensionInstalled(_ identifier:String, name:String, profile:String) {
        guard !isQuitting else { return }
        let item = extensionCatalog.entries(profile:profile,force:true).first { $0.id == identifier }
            ?? BrowserExtension(id:identifier,name:name,image:nil)
        extensionCatalog.installed(item,profile:profile)
        extensionSignature = ""; refreshExtensionToolbar()
        guard activeSpace?.profileID == profile else { return }
        engine.closeExtensionPopup(); extensionInstallNotice?.close()
        let show:()->Void = { [weak self] in
            guard let self, !self.isQuitting, self.activeSpace?.profileID == profile else { return }
            let notice = ExtensionInstallNotice(item:item,language:self.session.language,color:self.tint(),
                pinned:self.extensionCatalog.pins(profile:profile).contains(identifier),
                pin:{ [weak self] in
                    guard let self, self.activeSpace?.profileID == profile else { return }
                    if !self.extensionCatalog.pins(profile:profile).contains(identifier) { self.toggleExtensionPin(item) }
                },dismissed:{ [weak self] in self?.extensionInstallNotice = nil })
            self.extensionInstallNotice = notice; notice.show(of:self.siteMenuButton)
        }
        if let menu = siteMenu, menu.isShown { menu.close(completion:show) } else { show() }
        DispatchQueue.main.asyncAfter(deadline:.now()+3) { [weak self] in
            guard let self, !self.isQuitting else { return }
            _ = self.extensionCatalog.entries(profile:profile,force:true)
            self.extensionSignature = ""; self.refreshExtensionToolbar()
        }
    }
    @objc func manageExtensionsAction(_ sender: Any?) { openExtensions(store:false) }
    @objc func addExtensionAction(_ sender: Any?) { openExtensions(store:true) }
    private func openSiteSettings(for id:String) {
        guard !isQuitting, let tab = session.tabs.first(where: { $0.id == id }),
              let url = siteSettingsURL(for:tab.url) else { return }
        commandPalette?.close(); addMenu?.close()
        // The source space owns the request context and its actual permissions.
        let created = session.createTab(url:url.absoluteString,spaceID:tab.spaceID)
        guard !created.isEmpty else { return }
        if let index = session.tabs.firstIndex(where: { $0.id == created }) { session.tabs[index].title = t("settings") }
        render(); showSelectedTab(); persist()
    }
    private func openExtensions(store:Bool, address:String? = nil) {
        guard !isPrivateWindow, !isQuitting, let space = activeSpace else { return }
        commandPalette?.close(); siteMenu?.close(); addMenu?.close()
        let url = store ? (address ?? "https://chromewebstore.google.com/category/extensions") : "chrome://extensions/"
        if let existing = session.tabs.first(where:{ $0.spaceID == space.id && $0.url == url }) {
            selectTab(existing.id); return
        }
        _ = session.createTab(url:url,spaceID:space.id)
        render(); showSelectedTab(); persist()
    }

    @objc func forwardAction(_ sender: Any?) { if let id = activeTab?.id { engine.goForward(id) } }
    @objc func reloadAction(_ sender: Any?) {
        guard spaceCreation == nil, let tab = activeTab else { return }
        if status[tab.id]?.loading == true { engine.stop(tab.id) }
        else { reloadButton.animateReload(); status[tab.id]?.error = nil; if containers[tab.id] != nil { engine.reload(tab.id) }; buildHome(); showSelectedTab() }
    }
    @objc func findAction(_ sender: Any?) { guard activeTab != nil else { return }; isFinding = true; updateToolbar(); window.makeFirstResponder(findField) }
    @objc private func findNextAction(_ sender: Any?) { if let id = activeTab?.id { engine.find(inTab: id, text: findField.stringValue, forward: true, next: true) } }
    private func endFind() { isFinding = false; if let id = activeTab?.id { engine.stopFinding(id) }; updateToolbar() }
    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === findField { if let id = activeTab?.id { engine.find(inTab: id, text: findField.stringValue, forward: true, next: false) } }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { if sheet != nil { dismissSheet() }; endFind(); return true }; return false
    }
    private func makeSheet(size: NSSize, title: String) -> (NSPanel, FlippedView) {
        commandPalette?.close()
        dismissSheet()
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = title; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true; panel.isReleasedWhenClosed = false
        let view = FlippedView(frame: NSRect(origin: .zero, size: size)); view.wantsLayer = true; view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; panel.contentView = view
        sheet = panel; return (panel, view)
    }
    private func presentSheet(_ panel: NSPanel) { window.beginSheet(panel) }
    private func dismissSheet() {
        guard let panel = sheet else { return }; window.endSheet(panel); panel.orderOut(nil); sheet = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isQuitting, self.window.attachedSheet == nil, self.commandPalette == nil else { return }
            self.showSelectedTab(); self.updateSidebarHover()
        }
    }
    private func label(_ text: String, font: NSFont = .systemFont(ofSize: 12), color: NSColor = .labelColor) -> NSTextField { let l = NSTextField(labelWithString: text); l.font = font; l.textColor = color; return l }
    private func showCommand(newTab: Bool) {
        guard !isQuitting, session.onboardingComplete else { return }
        commandPalette?.close(); dismissSheet()
        let initial = newTab || activeTab?.url == "about:blank" ? "" : activeTab.map { browserDisplayAddress($0.url) } ?? ""
        // An empty split pane uses the new-tab presentation while navigation
        // still fills that existing pane (including choosing an open tab).
        let emptySplitPane = !newTab && (activeTab?.url == "about:blank" || activeTab?.url.isEmpty == true)
        let palette = CommandPalette(parent: window, newTab: newTab, centered: emptySplitPane, addressAnchor:usesClassicInterface ? addressButton : nil, initial: initial, icon: activeTab.flatMap(tabFavicon), tint: tint(), language: session.language, suggestions: { [weak self] query in
            self?.commandSuggestions(query, initial: initial, newTab: newTab) ?? []
        }, onDismiss: { [weak self] in self?.commandPalette = nil; self?.render(); self?.updateSidebarHover() })
        commandPalette = palette; render(); palette.show()
    }
    private func commandSuggestions(_ input: String, initial: String, newTab: Bool) -> [CommandSuggestion] {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isExtensionsAddress(query) {
            return [CommandSuggestion(title:t("manageExtensions"),detail:"arc://extensions/",image:nil,symbol:"puzzlepiece.extension",perform:{ [weak self] in self?.navigate(query,newTab:newTab) })]
        }
        let initialAddress = !newTab && query == initial
        var result: [CommandSuggestion] = []
        if !query.isEmpty && !initialAddress, let input = parseBrowserInput(query), input.url(using:currentEngine) != nil {
            let searching: Bool
            if case .search = input { searching = true } else { searching = false }
            let detail = searching ? splitText("Rechercher avec ","Search with ") + currentEngine.spec.name : t("open")
            result.append(CommandSuggestion(title: query, detail: detail, image: nil, symbol: searching ? "magnifyingglass" : "globe", perform: { [weak self] in self?.navigate(query,newTab:newTab) }))
        }
        let ordered = session.tabs.sorted { a,b in
            if a.id == activeTab?.id { return b.id != a.id }; if b.id == activeTab?.id { return false }
            if a.favorite != b.favorite { return a.favorite }; return false
        }
        for tab in ordered where query.isEmpty || initialAddress || (tab.displayTitle+" "+tab.url).localizedCaseInsensitiveContains(query) {
            result.append(CommandSuggestion(title:displayTitle(tab),detail:t("switchTab"),image:tabFavicon(tab),symbol:"globe",perform:{ [weak self] in self?.selectCommandTab(tab.id,newTab:newTab) }))
        }
        let openURLs = Set(session.tabs.map(\.url))
        var seen = openURLs
        for tab in session.closedTabs.reversed() where !seen.contains(tab.url) && (query.isEmpty || initialAddress || (tab.displayTitle+" "+tab.url).localizedCaseInsensitiveContains(query)) {
            seen.insert(tab.url)
            result.append(CommandSuggestion(title:displayTitle(tab),detail:t("restore"),image:nil,symbol:"clock",perform:{ [weak self] in self?.navigate(tab.url,newTab:newTab || self?.activeSplit == nil) }))
        }
        return Array(result.prefix(5))
    }
    private func showOnboarding(start:WelcomeWindow.Step = .welcome, standalone:Bool = false, profileID:String? = nil) {
        guard !isPrivateWindow, !isQuitting else { return }
        if let welcomeWindow { welcomeWindow.window?.makeKeyAndOrderFront(nil); return }
        guard window.attachedSheet == nil else { return }
        let welcome = WelcomeWindow(language:session.language,start:start,standalone:standalone)
        let targetProfile = profileID ?? activeSpace?.profileID ?? session.profiles[0].id
        welcome.importLinks = { [weak self] links,source in
            guard let self else { throw BrowserImportError.invalid("La fenêtre a été fermée.") }
            var candidate = self.session
            let count = try candidate.importLinks(links,from:source,profileID:targetProfile)
            if count > 0 { try self.store.save(candidate); self.session = candidate; self.render() }
            return count
        }
        welcome.finish = { [weak self] language,address in
            guard let self else { return }
            self.session.language = language; UserDefaults.standard.set(language,forKey:"BrowserLanguage")
            self.engine.updateLanguages(); self.session.onboardingComplete = true
            self.dismissSheet(); self.welcomeWindow = nil; self.render(); self.showSelectedTab(); self.persist()
            NotificationCenter.default.post(name:Notification.Name("BrowserLanguageChanged"),object:language)
            if let address {
                var candidate = self.session
                if candidate.openSettingsPage(address,profileID:targetProfile) != nil {
                    do { try self.store.save(candidate); self.session = candidate; self.render(); self.showSelectedTab(); self.persist() }
                    catch { self.showError(self.t("saveError"),detail:error.localizedDescription) }
                }
            }
        }
        welcomeWindow = welcome
        sheet = welcome.window as? NSPanel
        presentSheet(welcome.window as! NSPanel)
    }
    @objc func settingsAction(_ sender: Any?) {
        guard !isQuitting, session.onboardingComplete else { return }
        if let preferencesWindow, preferencesWindow.window?.isVisible == true {
            preferencesWindow.window?.makeKeyAndOrderFront(nil); return
        }
        let preferences = BrowserPreferencesWindow(language: session.language,
            profiles: session.profiles.map { profile in PreferenceProfile(id:profile.id,name:profile.name,spaces:session.spaces.filter { $0.profileID == profile.id }.count) },
            selectedProfileID:activeSpace?.profileID ?? session.profiles[0].id,interfaceMode:session.currentInterface,sidebarHidden:session.sidebarHidden,appearance:session.themeAppearance ?? .automatic,save: session.savePasswords ?? true,
            signIn: session.automaticSignIn ?? true, suggestions: session.formSuggestions ?? true,privateWindow:isPrivateWindow)
        if windowKind != .compact {
            preferences.onSidebarVisibilityChange = { [weak self] hidden in self?.setSidebarHidden(hidden) }
        }
        preferences.previewTheme = { [weak self] in self?.activeSpace?.theme ?? .solid(self?.activeSpace?.color ?? "#5747D8") }
        preferences.onInterfaceChange = { [weak self] mode in
            guard let self else { return false }
            var changed = self.session; changed.interfaceStyle = mode
            do { try self.store.save(changed) }
            catch { self.showError(self.t("saveError"),detail:error.localizedDescription); return false }
            self.receiveInterfaceStyle(mode)
            return true
        }
        preferences.navigationProfile = { [weak self] id in self?.session.profiles.first { $0.id == id } }
        preferences.onNavigationEdit = { [weak self] id,edit in
            guard let self, !self.isPrivateWindow, let i = self.session.profiles.firstIndex(where: { $0.id == id }) else { return false }
            let previous = self.session.profiles[i]
            var changed = self.session
            switch edit {
            case .engine(let engine):
                guard self.configureEngine(engine,profileID:id) else { return false }
                changed.profiles[i].searchEngineID = engine.rawValue
            case .homepage(let raw):
                if let raw, normalizedNewTabAddress(raw) != raw { return false }
                changed.profiles[i].newTabAddress = raw
            case .autoArchive(let enabled):
                if enabled != previous.autoArchiveEnabled { changed.profiles[i].autoArchiveEnabledSince = enabled ? Date() : nil }
            case .archive(let delay):
                guard previous.autoArchiveEnabled else { return false }
                changed.profiles[i].archiveAfterHours = delay.rawValue
            }
            do { try self.store.save(changed) }
            catch { if case .engine = edit { self.configureEngine(previous.engine,profileID:id) }; return false }
            self.session = changed; self.buildHome(); self.updateSplitHeaders()
            return true
        }
        preferences.onAppearance = { [weak self] mode in
            guard let self else { return }; self.session.themeAppearance = mode; self.applyTheme(); self.persist()
        }
        preferences.onWelcome = { [weak self] in self?.preferencesWindow?.close(); self?.showOnboarding() }
        preferences.onImport = { [weak self] id in self?.preferencesWindow?.close(); self?.showOnboarding(start:.browserImport,standalone:true,profileID:id) }
        preferences.onDefaultBrowser = { [weak self] in self?.setDefaultBrowser() }
        preferences.onRenameProfile = { [weak self] id,name in
            guard let self, !self.isPrivateWindow, self.session.renameProfile(id:id,name:name) else { return false }
            self.persist(); self.render(); return true
        }
        preferences.onOpenProfilePage = { [weak self] id,address in self?.openProfileSettings(address,profileID:id) ?? false }
        preferences.onLanguage = { [weak self] language in
            guard let self else { return }
            self.session.language = language
            UserDefaults.standard.set(language, forKey: "BrowserLanguage")
            self.engine.updateLanguages(); self.persist(); self.render()
            NotificationCenter.default.post(name: Notification.Name("BrowserLanguageChanged"), object: language)
        }
        preferences.onCredentials = { [weak self] save, signIn, suggestions in
            guard let self else { return false }
            let defaults = UserDefaults.standard
            let keys = ["BrowserSavePasswords", "BrowserAutomaticSignIn", "BrowserFormSuggestions"]
            let old = [self.session.savePasswords ?? true, self.session.automaticSignIn ?? true, self.session.formSuggestions ?? true]
            for (key, value) in zip(keys, [save, signIn, suggestions]) { defaults.set(value, forKey: key) }
            guard self.engine.updateCredentialPreferences() else {
                for (key, value) in zip(keys, old) { defaults.set(value, forKey: key) }
                _ = self.engine.updateCredentialPreferences()
                return false
            }
            self.session.savePasswords = save; self.session.automaticSignIn = signIn; self.session.formSuggestions = suggestions
            self.persist(); return true
        }
        preferences.commandBindings = commandOverrides
        preferences.onCommandBindings = { [weak self] bindings in
            guard let self else { return }
            self.session.commandShortcuts = bindings.filter { !$0.key.hasPrefix("split.") }
            self.session.splitShortcuts = Dictionary(uniqueKeysWithValues:bindings.filter { $0.key.hasPrefix("split.") }.map { (String($0.key.dropFirst(6)),$0.value) })
            self.persist()
            NotificationCenter.default.post(name:BrowserCommands.changed,object:nil)
        }
        preferences.onNewProfile = { [weak self] in self?.createProfile() }
        preferencesWindow = preferences
        preferences.showWindow(nil); preferences.window?.makeKeyAndOrderFront(nil)
    }
    @discardableResult func openProfileSettings(_ address:String,profileID:String) -> Bool {
        guard !isQuitting, !isPrivateWindow, ProfileSettingsLink.all.contains(where: { $0.address == address }) else { return false }
        var candidate = session
        guard candidate.openSettingsPage(address,profileID:profileID) != nil else { return false }
        do { try store.save(candidate) } catch { showError(t("saveError"),detail:error.localizedDescription); return false }
        finishSpaceSwitch(); commandPalette?.close(); siteMenu?.close(); session = candidate
        if library != nil { closeLibrary() }
        render(); showSelectedTab(); window.makeKeyAndOrderFront(nil); persist(); return true
    }
    private func promptName(_ title: String, initial: String = "", completion: @escaping (String) -> Void) {
        let alert = NSAlert(); alert.messageText = title; alert.addButton(withTitle: t("save")); alert.addButton(withTitle: t("cancel"))
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 26)); input.stringValue = initial; input.placeholderString = t("name"); alert.accessoryView = input
        alert.beginSheetModal(for: window) { result in if result == .alertFirstButtonReturn { let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { completion(String(value.prefix(80))) } } }; alert.window.makeFirstResponder(input)
    }
    private func createProfile() {
        guard !isPrivateWindow else { return }
        promptName(t("newProfile")) { [weak self] name in guard let self else { return }; let profile = NativeProfile(id:UUID().uuidString,name:name); self.session.profiles.append(profile); self.configureEngine(profile.engine,profileID:profile.id); self.persist(); self.settingsAction(nil); self.preferencesWindow?.showProfiles(profile.id) }
    }
    private func newFolder(spaceID: String? = nil, parentID: String? = nil) {
        let target = parentID.flatMap { id in session.folders.first(where: { $0.id == id })?.spaceID } ?? spaceID ?? session.activeSpaceID
        promptName(t("newFolder")) { [weak self] name in
            guard let self, self.session.spaces.contains(where: { $0.id == target }), self.session.folders.count < 1000 else { return }
            if let parentID { guard self.session.folders.contains(where: { $0.id == parentID && $0.spaceID == target && $0.liveHost == nil }) else { return } }
            let id = UUID().uuidString
            self.session.folders.append(NativeFolder(id:id,spaceID:target,name:name,collapsed:false,parentID:parentID))
            _ = self.session.moveSidebarItem(.folder(id),spaceID:target,to:SidebarDestination(parentID:parentID,before:nil))
            self.render(); self.persist()
        }
    }
    private func renameFolder(_ id: String) { guard let folder = session.folders.first(where: { $0.id == id }) else { return }; promptName(t("rename"), initial: folder.name) { [weak self] name in guard let self, let index = self.session.folders.firstIndex(where: { $0.id == id }) else { return }; self.session.folders[index].name = name; self.render(); self.persist() } }
    private func renameSpace(_ id: String) {
        guard let space = session.spaces.first(where: { $0.id == id }) else { return }
        promptName(t("renameSpace"),initial:space.name) { [weak self] value in
            guard let self, let i = self.session.spaces.firstIndex(where: { $0.id == id }) else { return }
            self.session.spaces[i].name = value; self.render(); self.persist()
        }
    }
    private func editSpaceAppearance(_ id: String, icon editingIcon: Bool, anchor: NSView? = nil) {
        guard let space = session.spaces.first(where: { $0.id == id }) else { return }
        if !editingIcon {
            commandPalette?.close(); themeEditor?.close(animated:false)
            let editor = ThemeEditor(parent:window,anchor:NSEvent.mouseLocation,theme:space.theme ?? .solid(space.color),appearance:session.themeAppearance ?? .automatic,language:session.language,change: { [weak self] theme, mode in
                guard let self, let i = self.session.spaces.firstIndex(where: { $0.id == id }), theme.validated() else { return }
                self.session.spaces[i].theme = theme; self.session.spaces[i].color = theme.points[0].color
                self.session.themeAppearance = mode; self.applyTheme(); self.persist()
                // Backdrops update immediately; expensive table/layout work is coalesced while dragging.
                self.themeRenderTask?.cancel()
                let task = DispatchWorkItem { [weak self] in self?.render() }
                self.themeRenderTask = task; DispatchQueue.main.asyncAfter(deadline:.now()+0.08,execute:task)
            },dismissed: { [weak self] in
                guard let self else { return }; self.themeEditor = nil; self.themeRenderTask?.cancel(); self.render(); self.updateSidebarHover()
            })
            themeEditor = editor; editor.show(); return
        }
        iconPicker?.close(); themeEditor?.close(animated:false)
        let picker = SpaceIconPicker(value:space.icon,language:session.language,change:{ [weak self] value in
            guard let self, let i = self.session.spaces.firstIndex(where: { $0.id == id }) else { return }
            self.session.spaces[i].icon = value; self.render(); self.persist()
        },dismissed:{ [weak self] in self?.iconPicker = nil; self?.updateSidebarHover() })
        iconPicker = picker
        let point = root.convert(window.convertPoint(fromScreen:NSEvent.mouseLocation),from:nil)
        if let anchor { picker.show(relativeTo:anchor.bounds,of:anchor) }
        else { picker.show(relativeTo:NSRect(x:point.x,y:point.y,width:1,height:1),of:root) }
    }

    private func editLiveFolder(spaceID: String, initial: String = "", folderID: String? = nil) {
        let alert = NSAlert(); alert.messageText = t("liveFolders"); alert.informativeText = t("liveInfo")
        alert.addButton(withTitle:t(folderID == nil ? "create" : "save")); alert.addButton(withTitle:t("cancel"))
        let field = NSTextField(frame:NSRect(x:0,y:0,width:340,height:28)); field.placeholderString = t("domain"); field.stringValue = initial; alert.accessoryView = field
        alert.beginSheetModal(for:window) { [weak self] result in
            guard let self, result == .alertFirstButtonReturn, self.session.spaces.contains(where: { $0.id == spaceID }) else { return }
            guard let host = normalizedLiveHost(field.stringValue) else { self.showError(self.t("liveFolders"),detail:self.t("invalidDomain")); return }
            if let folderID, let i = self.session.folders.firstIndex(where: { $0.id == folderID }) { self.session.folders[i].liveHost = host }
            else {
                guard self.session.folders.count < 1000 else { self.showError(self.t("liveFolders"),detail:self.t("limitReached")); return }
                self.session.folders.append(NativeFolder(id:UUID().uuidString,spaceID:spaceID,name:host,collapsed:false,liveHost:host))
            }
            self.render(); self.persist(); self.updateSidebarHover()
        }; alert.window.makeFirstResponder(field)
    }
    private func shareSpace(_ id: String) {
        let picker = NSSharingServicePicker(items:[session.shareText(for:id)])
        sharingPicker = picker
        picker.show(relativeTo:NSRect(x:20,y:180,width:1,height:1),of:sidebarHost,preferredEdge:.maxX)
    }
    private func exportSpaceHTML(_ id: String) {
        guard let space = session.spaces.first(where: { $0.id == id }) else { return }
        let html = session.bookmarksHTML(for:id)
        let save = NSSavePanel(); save.title = t("exportHTML"); save.nameFieldStringValue = space.name.replacingOccurrences(of:"/",with:"-") + ".html"
        save.beginSheetModal(for:window) { [weak self] result in
            guard let self, result == .OK, let url = save.url else { return }
            do { try html.write(to:url,atomically:true,encoding:.utf8) }
            catch { self.showError(self.t("exportError"),detail:error.localizedDescription) }
        }
    }
    private func exportSpace(_ id: String, to target: String) {
        guard session.exportSpaceIntoFolder(id,targetID:target) else { showError(t("exportError"),detail:t("limitReached")); return }
        selectSpace(target); persist()
    }
    private func manageSpaces() {
        if library == nil { showLibrary() }
        library?.switchSection(.spaces)
    }
    private func changeProfile(_ spaceID: String, to profileID: String) {
        guard let space = session.spaces.first(where: { $0.id == spaceID }), space.profileID != profileID,
              session.profiles.contains(where: { $0.id == profileID }), profileReloads[spaceID] == nil else { return }
        let alert = NSAlert(); alert.messageText = t("changeProfile"); alert.informativeText = t("changeProfileInfo")
        alert.addButton(withTitle:t("changeProfile")); alert.addButton(withTitle:t("cancel"))
        alert.beginSheetModal(for:window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let ids = Set(self.session.tabs.filter { $0.spaceID == spaceID && self.containers[$0.id] != nil }.map(\.id))
            self.profileReloads[spaceID] = ProfileReload(profileID:profileID,waiting:ids)
            if ids.isEmpty { self.finishProfileReload(spaceID) }
            else { for id in ids { self.engine.closeTab(id) } }
        }
    }
    private func finishProfileReload(_ id: String) {
        guard let reload = profileReloads[id], reload.waiting.isEmpty else { return }
        profileReloads.removeValue(forKey:id)
        if !reload.cancelled, let i = session.spaces.firstIndex(where: { $0.id == id }) {
            session.spaces[i].profileID = reload.profileID
            let aliases = session.normalizeFavoriteTabs()
            discardDeletedBrowsers(Set(aliases.keys))
        }
        persist()
        DispatchQueue.main.async { [weak self] in self?.render(); self?.showSelectedTab() }
    }
    private func showSpaceCreation() {
        if library != nil { closeLibrary { [weak self] in self?.showSpaceCreation() }; return }
        guard spaceCreation == nil, !spaceCreationClosing else { return }
        guard session.spaces.count < BrowserSession.maximumSpaces else {
            showError(t("newSpace"),detail:session.language == "fr" ? "La limite de 100 espaces est atteinte." : "The limit of 100 spaces has been reached."); return
        }
        guard let profileID = activeSpace?.profileID ?? session.profiles.first?.id else { return }
        finishSpaceSwitch()
        commandPalette?.close(); themeEditor?.close(animated:false); addMenu?.close()
        cancelSidebarHover(); sidebarTransition += 1; sidebarAnimating = false
        let view = SpaceCreationView(draft:SpaceCreationDraft(profileID:profileID,appearance:session.themeAppearance ?? .automatic),profiles:session.profiles,spaces:session.spaces,activeSpaceID:session.activeSpaceID,language:session.language)
        spaceCreation = view; view.frame = root.bounds; view.sidebarWidth = CGFloat(SidebarSizing.clamp(session.sidebarWidth))
        view.didEnter = { [weak self, weak view] in
            guard let self, let view, self.spaceCreation === view else { return }
            self.sidebarHost.isHidden = true; self.content.isHidden = true; self.pageShadow.isHidden = true
            for (id,container) in self.containers { self.engine.setTab(id,visible:false); container.isHidden = true }
        }
        view.cancel = { [weak self] in self?.finishSpaceCreation(created:false) }
        view.selectExistingSpace = { [weak self] id in
            self?.finishSpaceCreation(created:false) { [weak self] in self?.selectSpace(id) }
        }
        view.chooseTheme = { [weak self, weak view] in
            guard let self, let view else { return }
            self.themeEditor?.close(animated:false)
            let editor = ThemeEditor(parent:self.window,anchor:NSEvent.mouseLocation,theme:view.draft.theme,appearance:view.draft.appearance,language:self.session.language,change:{ [weak view] theme, mode in
                view?.updateTheme(theme,appearance:mode)
            },dismissed:{ [weak self] in self?.themeEditor = nil })
            self.themeEditor = editor; editor.show()
        }
        view.commit = { [weak self] draft in
            guard let self, !self.isQuitting else { return L10n.text("saveError",language:"fr") }
            var candidate = self.session
            guard !candidate.createSpace(from:draft).isEmpty else { return self.t("emptyName") }
            do {
                try self.store.save(candidate)
                self.saveTask?.cancel(); self.session = candidate
                return nil
            } catch { return self.t("saveError") + " : " + error.localizedDescription }
        }
        view.completed = { [weak self] in self?.finishSpaceCreation(created:true) }
        root.addSubview(view,positioned:.above,relativeTo:nil)
        layoutWindowButtons(); view.show()
    }
    private func finishSpaceCreation(created: Bool, completion: (() -> Void)? = nil) {
        guard let view = spaceCreation, !spaceCreationClosing else { return }
        spaceCreationClosing = true
        themeEditor?.close(animated:false)
        spaceCreation = nil
        content.isHidden = false; pageShadow.isHidden = false
        render(); showSelectedTab()
        view.dismiss(created:created) { [weak self, weak view] in
            view?.removeFromSuperview()
            guard let self else { return }
            self.spaceCreationClosing = false; self.layoutWindowButtons(); self.updateSidebarHover(); completion?()
        }
    }
    private func showSpaceForm(_ existing: NativeSpace?) {
        guard !isQuitting, session.onboardingComplete else { return }
        if existing == nil { showSpaceCreation(); return }
        let alert = NSAlert(); alert.messageText = t(existing == nil ? "newSpace" : "editSpace"); alert.addButton(withTitle: t(existing == nil ? "create" : "save")); alert.addButton(withTitle: t("cancel"))
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: 350, height: 230))
        let name = NSTextField(frame: NSRect(x: 0, y: 23, width: 350, height: 28)); name.placeholderString = t("name"); name.stringValue = existing?.name ?? ""
        let nameLabel = label(t("name")); nameLabel.frame = NSRect(x: 0, y: 0, width: 350, height: 20); view.addSubview(nameLabel); view.addSubview(name)
        let colorLabel = label(t("color")); colorLabel.frame = NSRect(x: 0, y: 70, width: 140, height: 20); view.addSubview(colorLabel)
        let colors = palette + ((existing != nil && !palette.contains(existing!.color)) ? [existing!.color] : [])
        let color = NSPopUpButton(frame: NSRect(x: -3, y: 95, width: 160, height: 28)); color.addItems(withTitles: session.language == "fr" ? ["Orchidée", "Azur", "Sauge", "Pêche", "Lavande", "Ardoise"] : ["Orchid", "Azure", "Sage", "Peach", "Lavender", "Slate"]); if colors.count > palette.count { color.addItem(withTitle:colors.last!) }; color.selectItem(at: colors.firstIndex(of: existing?.color ?? "") ?? session.spaces.count % palette.count); view.addSubview(color)
        let iconLabel = label(t("icon")); iconLabel.frame = NSRect(x: 180, y: 70, width: 160, height: 20); view.addSubview(iconLabel)
        var chosenIcon = existing?.icon ?? "◈"
        let icon = ActionButton(SpaceIcon.caption(chosenIcon),symbol:SpaceIcon.symbol(chosenIcon),action:{})
        icon.frame = NSRect(x:176,y:92,width:44,height:34); icon.setAccessibilityLabel(t("changeSpaceIcon")); view.addSubview(icon)
        icon.invoke = { [weak self, weak icon] in
            guard let self, let icon else { return }
            self.iconPicker?.close()
            let picker = SpaceIconPicker(value:chosenIcon,language:self.session.language,change:{ value in
                chosenIcon = value; icon.title = SpaceIcon.caption(value); icon.image = SpaceIcon.image(value); icon.imagePosition = icon.image == nil ? .noImage : .imageOnly; icon.needsDisplay = true
            },dismissed:{ [weak self] in self?.iconPicker = nil })
            self.iconPicker = picker; picker.show(relativeTo:icon.bounds,of:icon)
        }

        let profileLabel = label(t("profile")); profileLabel.frame = NSRect(x: 0, y: 148, width: 350, height: 20); view.addSubview(profileLabel)
        let profile = NSPopUpButton(frame: NSRect(x: -3, y: 173, width: 353, height: 28)); profile.addItems(withTitles: session.profiles.map(\.name)); profile.selectItem(at: session.profiles.firstIndex(where: { $0.id == (existing?.profileID ?? activeSpace?.profileID) }) ?? 0); profile.isEnabled = existing == nil; view.addSubview(profile)
        alert.accessoryView = view
        alert.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .alertFirstButtonReturn else { return }
            let value = String(name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)); guard !value.isEmpty else { return }
            if let existing, let i = self.session.spaces.firstIndex(where: { $0.id == existing.id }) { self.session.spaces[i].name = value; if self.session.spaces[i].color != colors[color.indexOfSelectedItem] { self.session.spaces[i].theme = nil }; self.session.spaces[i].color = colors[color.indexOfSelectedItem]; self.session.spaces[i].icon = chosenIcon }
            else { _ = self.session.createSpace(name: value, color: colors[color.indexOfSelectedItem], icon: chosenIcon, profileID: self.session.profiles[profile.indexOfSelectedItem].id) }
            self.render(); self.showSelectedTab(); self.persist()
        }; alert.window.makeFirstResponder(name)
    }
    private func deleteSpace(_ id: String) {
        guard !isQuitting, session.spaces.count > 1 else { return }
        var next = session; next.removeSpace(id:id)
        performDeletion(next,kind:.space)
    }
    private func performDeletion(_ next: BrowserSession, kind: DeletionUndo.Kind) {
        let change = DeletionUndo(kind:kind,before:session,after:next)
        guard !change.isEmpty else { return }
        do { try store.save(next) }
        catch { showError(t("saveError"),detail:error.localizedDescription); return }
        finishSpaceSwitch(); endFind(); session = next
        deletionUndo.append(change)
        if deletionUndo.count > 20 { deletionUndo.removeFirst() }
        discardDeletedBrowsers(change.removedTabIDs.union(change.reloadTabIDs))
        render(); showSelectedTab()
        window.makeFirstResponder(root)
        undoToast.show(in:window,message:t(kind == .space ? "spaceDeletedNotice" : "tabsClearedNotice"),suffix:t("undoNoticeSuffix"),undoLabel:t("undoDeletion"),color:tint())
    }
    private func discardDeletedBrowsers(_ ids: Set<String>) {
        for id in ids where containers[id] != nil && !destructiveClosing.contains(id) {
            containers[id]?.isHidden = true; engine.setTab(id,visible:false)
            destructiveClosing.insert(id); engine.discardTab(id)
        }
    }
    @discardableResult private func undoLastDeletion() -> Bool {
        guard !isQuitting, window.attachedSheet == nil, commandPalette == nil, spaceCreation == nil,
              let change = deletionUndo.last else { return false }
        guard let restored = change.restoring(session) else {
            showError(t("undoDeletion"),detail:t("limitReached")); return true
        }
        do { try store.save(restored) }
        catch { showError(t("saveError"),detail:error.localizedDescription); return true }
        finishSpaceSwitch(); deletionUndo.removeLast(); undoToast.dismiss()
        session = restored
        discardDeletedBrowsers(change.reloadTabIDs)
        render(); showSelectedTab()
        window.makeFirstResponder(root)
        return true
    }
    func browserUndoRequested() -> Bool { undoLastDeletion() }
    private func showError(_ title: String, detail: String) {
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = title; alert.informativeText = detail; alert.addButton(withTitle: t("close")); alert.beginSheetModal(for: window)
    }

    // CEF delegate callbacks arrive on the AppKit/UI thread.
    func browserFaviconChanged(_ tabID: String, document: String, image: NSImage) {
        guard !isQuitting, !destructiveClosing.contains(tabID),
              let tab = session.tabs.first(where:{ $0.id == tabID }), let profile = session.profile(forSpace:tab.spaceID)?.id,
              FaviconCache.canUse(document,for:tab.url) else { return }
        let result = faviconCache.save(image,id:tabID,url:tab.url,profile:profile)
        if result.changed || result.firstSite { refreshTabVisual(tabID,siteAvailable:result.firstSite) }
    }
    private func tabFavicon(_ tab:NativeTab) -> NSImage? {
        guard let profile = session.profile(forSpace:tab.spaceID)?.id else { return nil }
        return faviconCache.image(id:tab.id,url:tab.url,profile:profile)
    }
    private func favoriteIsLoaded(_ id: String) -> Bool {
        guard let shared = session.favoriteTabID(id,spaceID:session.activeSpaceID) else { return false }
        return containers[shared] != nil && status[shared]?.hasLoaded == true && status[shared]?.error == nil
    }
    private func favoriteImage(_ id: String) -> NSImage? {
        guard let source = session.tabs.first(where:{ $0.id == id }) else { return nil }
        let local = session.favoriteTabID(id,spaceID:session.activeSpaceID).flatMap { localID in
            session.tabs.first(where:{ $0.id == localID })
        }
        if let local, let icon = tabFavicon(local) { return icon }
        // A shared bookmark may show its saved artwork in another profile, but
        // never store that artwork in the other profile's site cache.
        let document = FaviconCache.document(source.url)
        if let local, !FaviconCache.canUse(document,for:local.url) { return nil }
        if let icon = tabFavicon(source) { return icon }
        return session.tabs.lazy.filter {
            $0.favoriteSourceID == id && FaviconCache.document($0.url) == document
        }.compactMap { self.tabFavicon($0) }.first
    }
    private func refreshTabVisual(_ tabID: String, siteAvailable:Bool = false) {
        guard let tab = session.tabs.first(where: { $0.id == tabID }) else { return }
        updateSplitHeaders()
        // A newly learned site icon can also fill visible dormant rows. Offscreen
        // cells resolve their image when AppKit asks for them; never load the page.
        let visible = table.rows(in:table.visibleRect)
        for row in visible.location..<(visible.location + visible.length) {
            guard rows.indices.contains(row), case .tab(let id) = rows[row] else { continue }
            if let group = session.splitGroup(containing:id) {
                guard siteAvailable || group.tabIDs.contains(tabID) else { continue }
                if let view = table.view(atColumn:0,row:row,makeIfNecessary:false),
                   !(sidebarTitleEditor?.isEditingTitle == true && sidebarTitleEditor?.isDescendant(of:view) == true) {
                    table.reloadData(forRowIndexes:IndexSet(integer:row),columnIndexes:IndexSet(integer:0))
                }
            } else if (siteAvailable || id == tabID),
                      let cell = table.view(atColumn:0,row:row,makeIfNecessary:false) as? TabCell,
                      let item = id == tabID ? tab : session.tabs.first(where:{ $0.id == id }) {
                cell.icon.image = splitTabIcon(item)
                if id == tabID {
                    if !cell.isEditingTitle { cell.titleLabel.stringValue = displayTitle(tab) }
                    cell.toolTip = tab.url
                }
            }
        }
        if siteAvailable || tab.favorite || tab.favoriteSourceID != nil {
            favorites.update(session.favoriteTabs(spaceID:session.activeSpaceID).map {
                FavoriteVisual(id:$0.id,title:displayTitle($0),image:favoriteImage($0.id),menu:tabMenu($0),isLoaded:favoriteIsLoaded($0.id),developerMode:($0.id == (activeTab?.favoriteSourceID ?? activeTab?.id)) && activeTab?.developerMode == true)
            },activeID:activeTab?.favoriteSourceID ?? activeTab?.id,ink:sidebarInk)
        }
    }
    func browserTitleChanged(_ tabID: String, title: String) {
        guard !isQuitting else { return }
        guard let i = session.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let title = String(decoding:title.utf8.prefix(8000),as:UTF8.self).replacingOccurrences(of:"\0",with:"")
        guard !title.isEmpty, session.tabs[i].title != title else { return }
        session.tabs[i].title = title; refreshTabVisual(tabID); persist()
    }
    func browserURLChanged(_ tabID: String, url: String) {
        guard !isQuitting else { return }
        guard let i = session.tabs.firstIndex(where: { $0.id == tabID }), isAllowedBrowserURL(url) else { return }
        if pageCapture?.tabID == tabID, session.tabs[i].url != url { pageCapture?.close() }
        let hostChanged = URL(string:session.tabs[i].url)?.host != URL(string:url)?.host
        let previousIcon = tabFavicon(session.tabs[i])
        session.tabs[i].url = url
        if tabFavicon(session.tabs[i]) !== previousIcon { refreshTabVisual(tabID) }
        if hostChanged && session.folders.contains(where: { $0.spaceID == session.tabs[i].spaceID && $0.liveHost != nil }) { render() }
        else { updateToolbar() }
        persist()
    }
    func browserLoadProgress(_ tabID: String, fraction: Double) {
        guard !isQuitting, fraction.isFinite, var state = status[tabID], state.loading else { return }
        let next = min(1, max(0, fraction))
        guard next != state.progress else { return }
        state.progress = next; status[tabID] = state
        if tabID == activeTab?.id { updateLoadIndicator() }
    }
    func browserLoadingChanged(_ tabID: String, loading: Bool, back: Bool, forward: Bool) {
        guard !isQuitting, session.tabs.contains(where: { $0.id == tabID }) else { return }
        var state = status[tabID] ?? TabStatus(); let wasLoading = state.loading; state.loading = loading; state.back = back; state.forward = forward
        let previouslyLoaded = state.hasLoaded
        if loading { state.error = nil; if !wasLoading { state.progress = 0 } }
        else if wasLoading && state.error == nil { state.hasLoaded = true }
        status[tabID] = state; updateToolbar()
        if state.hasLoaded != previouslyLoaded { refreshTabVisual(tabID) }
        guard spaceCreation == nil, !closingWindow else { return }
        let visible = activeSplit.map { $0.tabIDs.contains(tabID) } ?? (tabID == activeTab?.id)
        guard visible, let tab = session.tabs.first(where:{ $0.id == tabID }) else { return }
        if tabID == activeTab?.id { buildHome() }
        if state.error != nil || tab.url.isEmpty || tab.url == "about:blank" {
            hideDocument(tabID)
        } else if let container = containers[tabID], container.isHidden {
            container.isHidden = false
            if window.attachedSheet == nil { engine.setTab(tabID, visible:true) }
            if let parent = container.superview { layoutDeveloperPage(tabID,in:parent) }
        }
    }
    private func hideDocument(_ id:String) {
        developerBars[id]?.isHidden = true
        guard let container = containers[id], !container.isHidden else { return }
        container.isHidden = true; engine.setTab(id,visible:false)
    }
    func browserFailed(_ tabID:String, code:String, host:String?) {
        guard !isQuitting, let tab = session.tabs.first(where:{ $0.id == tabID }) else { return }
        var state = status[tabID] ?? TabStatus()
        state.error = NavigationFailure(code:code,host:host ?? URL(string:tab.url)?.host)
        state.loading = false; state.hasLoaded = false; status[tabID] = state
        hideDocument(tabID); refreshTabVisual(tabID)
        updateSplitHeaders()
        if tabID == activeTab?.id { updateToolbar(); buildHome() }
    }
    func browserRequestedNewTab(_ url: String, sourceTab: String) {
        guard !isQuitting else { return }
        guard let source = session.tabs.first(where: { $0.id == sourceTab }), let normalized = browserURL(url,engine:session.profile(forSpace:source.spaceID)?.engine ?? .google) else { return }
        _ = session.createTab(url: normalized.absoluteString, spaceID: session.browsingSpaceID(for:source)); render(); showSelectedTab(); persist()
    }
    func browserPrepareExtensionTab(_ sourceTab: String, active: Bool, pinned: Bool, index: Int) -> [String: Any]? {
        guard !isQuitting, let source = session.tabs.first(where: { $0.id == sourceTab }),
              profileReloads[source.spaceID] == nil,
              let reservation = session.reserveExtensionTab(sourceTabID: sourceTab, active: active,
                                                             pinned: pinned, index: index) else { return nil }
        extensionTabReservations[reservation.id] = reservation
        let container = NSView(frame: content.bounds)
        container.isHidden = true
        content.addSubview(container)
        containers[reservation.id] = container
        return ["id": reservation.id, "view": container]
    }
    func browserExtensionTabCreated(_ tabID: String, success: Bool) {
        guard let reservation = extensionTabReservations.removeValue(forKey: tabID) else { return }
        if !success {
            session.cancelExtensionTab(reservation)
            containers.removeValue(forKey: tabID)?.removeFromSuperview()
            status.removeValue(forKey: tabID)
        }
        // Let Chromium finish tabs.create and navigation before displaying the
        // resulting tab. Background creation keeps the previous selection.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isQuitting else { return }
            self.render(); self.showSelectedTab(); self.persist()
        }
    }
    func browserPreparePopup(_ url: String, sourceTab: String) -> [String: Any]? {
        browserPreparePopup(url, sourceTab:sourceTab, active:true)
    }
    func browserPreparePopup(_ url: String, sourceTab: String, active: Bool) -> [String: Any]? {
        guard !isQuitting else { return nil }
        guard let source = session.tabs.first(where: { $0.id == sourceTab }) else { return nil }
        guard profileReloads[source.spaceID] == nil else { return nil }
        let value = url.isEmpty ? "about:blank" : url
        guard isAllowedBrowserURL(value) else { return nil }
        let previousSpace = session.activeSpaceID
        let spaceID = session.browsingSpaceID(for:source)
        let selected = session.spaces.first(where: { $0.id == spaceID })?.selectedTabID
        let id = session.createTab(url: value, spaceID: spaceID)
        guard !id.isEmpty else { return nil }
        if !active {
            if let index = session.spaces.firstIndex(where: { $0.id == spaceID }) { session.spaces[index].selectedTabID = selected }
            session.activeSpaceID = previousSpace
        }
        let container = NSView(frame: content.bounds); content.addSubview(container); containers[id] = container
        container.isHidden = !active
        DispatchQueue.main.async { [weak self] in guard let self, !self.isQuitting else { return }; self.render(); self.showSelectedTab(); self.persist() }
        return ["id": id, "view": container]
    }
    func browserRequestedPrivateWindow(_ url: String, sourceTab: String) {
        guard !isQuitting, session.tabs.contains(where: { $0.id == sourceTab }), isAllowedBrowserURL(url) else { return }
        privateAddressRequested?(url)
    }
    func browserRequestedNewWindow(_ url: String, sourceTab: String) {
        guard !isQuitting, session.tabs.contains(where: { $0.id == sourceTab }), isAllowedBrowserURL(url) else { return }
        windowAddressRequested?(url)
    }
    func browserCloseCancelled(_ tabID: String) {
        if automaticClose.removeValue(forKey:tabID) != nil { pendingClose.remove(tabID); resetArchiveClock(tabID) }
        if closeParticipants.contains(tabID), !isQuitting { windowCloseCancelled = true; closeWaiting.remove(tabID); finishWindowCloseAttempt(); return }
        if let id = profileReloads.first(where: { $0.value.waiting.contains(tabID) })?.key {
            profileReloads[id]?.cancelled = true; profileReloads[id]?.waiting.remove(tabID); finishProfileReload(id)
        }
        pendingClose.remove(tabID)
        for key in Array(pendingSpaceClosures.keys) where pendingSpaceClosures[key]?.contains(tabID) == true { pendingSpaceClosures.removeValue(forKey: key) }
    }
    func browserClosed(_ tabID: String) {
        let archiveDecision = automaticClose[tabID]?()
        automaticClose.removeValue(forKey:tabID)
        let archivedAutomatically = archiveDecision == true
        developerBars.removeValue(forKey:tabID)?.removeFromSuperview()
        pendingCaptures.remove(tabID)
        if pageCapture?.tabID == tabID { pageCapture?.close() }
        if portraitCapture?.tabID == tabID { portraitCapture?.close() }
        containers.removeValue(forKey: tabID)?.removeFromSuperview(); status.removeValue(forKey: tabID)
        pendingClose.remove(tabID)
        if closeParticipants.contains(tabID), !isQuitting { closeWaiting.remove(tabID); finishWindowCloseAttempt(); return }
        if destructiveClosing.remove(tabID) != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isQuitting else { return }
                self.showSelectedTab()
            }
            return
        }
        // Orderly application shutdown releases views but retains the saved session.
        // Other closures include window.close(), not only explicit sidebar actions.
        guard !isQuitting, session.tabs.contains(where: { $0.id == tabID }) else { return }
        if let id = profileReloads.first(where: { $0.value.waiting.contains(tabID) })?.key {
            profileReloads[id]?.waiting.remove(tabID); finishProfileReload(id); return
        }
        if archiveDecision == false {
            // The user may have selected or pinned this tab while CEF was closing.
            DispatchQueue.main.async { [weak self] in self?.showSelectedTab() }; return
        }
        let preservingSharedFavorite = session.tabs.contains { $0.id == tabID && $0.favorite } && pendingSpaceClosures.values.contains { $0.contains(tabID) }
        if !preservingSharedFavorite { session.closeTab(id:tabID,automaticallyAt:archivedAutomatically ? Date() : nil) }
        for key in Array(pendingSpaceClosures.keys) { pendingSpaceClosures[key]?.remove(tabID); if pendingSpaceClosures[key]?.isEmpty == true { session.removeSpace(id: key); pendingSpaceClosures.removeValue(forKey: key) } }
        persist()
        // Avoid creating a lazy replacement browser inside CEF OnBeforeClose.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isQuitting else { return }
            self.render(); self.showSelectedTab()
        }
    }
}

// Split View keeps native Chromium containers in one real AppKit window.
extension BrowserController {
    private func toggleDeveloperMode(for id:String) {
        guard let index = session.tabs.firstIndex(where: { $0.id == id }) else { return }
        let enabled = session.tabs[index].developerMode != true
        session.tabs[index].developerMode = enabled
        if !enabled {
            engine.closeDeveloperTools(id)
            if portraitCapture?.tabID == id { portraitCapture?.close() }
        }
        render(); showSelectedTab(); persist()
    }
    private func pageBounds(for id:String,in parent:NSView) -> NSRect {
        let enabled = session.tabs.first(where: { $0.id == id })?.developerMode == true
        let height = enabled ? DeveloperToolbar.height(for:parent.bounds.width) : 0
        return NSRect(x:0,y:0,width:parent.bounds.width,height:max(1,parent.bounds.height-height))
    }
    private func layoutDeveloperPage(_ id:String,in parent:NSView) {
        guard let container = containers[id], let tab = session.tabs.first(where: { $0.id == id }) else { return }
        let frame = pageBounds(for:id,in:parent)
        container.frame = frame; engine.resizeTab(id,container:container)
        guard tab.developerMode == true else { developerBars[id]?.isHidden = true; return }
        let bar:DeveloperToolbar
        if let existing = developerBars[id] { bar = existing }
        else {
            bar = DeveloperToolbar(tabID:id,language:session.language); developerBars[id] = bar
            bar.navigate = { [weak self] input in
                guard let self, self.session.tabs.contains(where: { $0.id == id }) else { return }
                self.activateDeveloperTab(id); self.navigate(input,newTab:false)
            }
            bar.command = { [weak self] kind,anchor in self?.developerCommand(id,kind:kind,anchor:anchor) }
        }
        if bar.superview !== parent { bar.removeFromSuperview(); parent.addSubview(bar,positioned:.above,relativeTo:nil) }
        let height = DeveloperToolbar.height(for:parent.bounds.width)
        bar.frame = NSRect(x:0,y:parent.bounds.height-height,width:parent.bounds.width,height:height)
        bar.isHidden = container.isHidden; bar.needsLayout = true; bar.layoutSubtreeIfNeeded()
        bar.update(url:tab.url,tool:engine.developerTool(forTab:id),loadingCapture:pendingCaptures.contains(id))
    }
    private func updateDeveloperBars() {
        for (id,bar) in developerBars where !bar.isHidden {
            guard let tab = session.tabs.first(where: { $0.id == id }) else { continue }
            bar.update(url:tab.url,tool:engine.developerTool(forTab:id),loadingCapture:pendingCaptures.contains(id))
        }
    }
    private func activateDeveloperTab(_ id:String) {
        guard activeTab?.id != id else { return }
        if activeSplit?.tabIDs.contains(id) == true { focusSplitPane(id,keyboard:false) }
        else { selectTab(id) }
    }
    private func developerCommand(_ id:String,kind:String,anchor:NSView) {
        guard !isQuitting, let tab = session.tabs.first(where: { $0.id == id }), tab.developerMode == true else { return }
        activateDeveloperTab(id)
        switch kind {
        case "copy":
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(browserDisplayAddress(tab.url),forType:.string)
            developerBars[id]?.showCopied()
        case "portrait": showPortraitCapture(for:id,anchor:anchor)
        case "region": startPageCapture(for:id)
        case "console", "network", "inspect": engine.toggleDeveloperTool(kind,forTab:id); updateDeveloperBars()
        case "extensions": showSiteMenu(anchor:anchor)
        case "split":
            if let group = session.splitGroup(containing:id) { splitGroupMenu(group).popUp(positioning:nil,at:NSPoint(x:0,y:anchor.bounds.height),in:anchor) }
            else { addSplitPane(to:id) }
        default: break
        }
    }
    private func showPortraitCapture(for id:String,anchor:NSView) {
        guard !pendingCaptures.contains(id) else { return }
        if portraitCapture?.tabID == id { portraitCapture?.close(); return }
        portraitCapture?.close(); pendingCaptures.insert(id); updateDeveloperBars()
        engine.capturePage(id) { [weak self, weak anchor] data in
            guard let self else { return }
            self.pendingCaptures.remove(id); self.updateDeveloperBars()
            guard !self.isQuitting, let anchor, !anchor.isHiddenOrHasHiddenAncestor,
                  let tab = self.session.tabs.first(where: { $0.id == id }), self.activeTab?.id == id else { return }
            guard let data, let image = NSImage(data:data) else { self.showError(self.t("siteActionFailed"),detail:self.splitText("La capture de la page n’a pas abouti.","The page could not be captured.")); return }
            let capture = PortraitCapture(tabID:id,image:image,color:NSColor(browserHex:tab.developerCaptureColor ?? "#E971B8") ?? .systemPink,language:self.session.language)
            capture.closed = { [weak self, weak capture] color in
                guard let self else { return }
                if let index = self.session.tabs.firstIndex(where: { $0.id == id }) { self.session.tabs[index].developerCaptureColor = color; self.persist() }
                if self.portraitCapture === capture { self.portraitCapture = nil }
            }
            capture.copied = { [weak self] in
                guard let self else { return }
                self.undoToast.show(in:self.window,message:self.splitText("Capture copiée","Capture copied"),suffix:"",undoLabel:"",color:self.tint(),offersUndo:false)
            }
            capture.failed = { [weak self] message in guard let self else { return }; self.showError(self.t("siteActionFailed"),detail:message) }
            self.portraitCapture = capture; capture.show(of:anchor,rect:anchor === self.content ? NSRect(x:anchor.bounds.midX,y:anchor.bounds.maxY-4,width:1,height:1) : nil)
        }
    }

    @objc func capturePageAction(_ sender:Any?) { if let id = activeTab?.id { startPageCapture(for:id) } }
    private func startPageCapture(for id:String, fullPage:Bool = false) {
        guard !isQuitting, engine.captureView(forTab:id) != nil else { return }
        pageCapture?.close(); portraitCapture?.close(); siteMenu?.close(); commandPalette?.close()
        engine.closeExtensionPopup(); extensionInstallNotice?.close()
        let capture = PageCapture(tabID:id,engine:engine,window:window,language:session.language)
        capture.saved = { [weak self] data in guard let self else { return }; try self.libraryStore.saveCapture(data) }
        capture.notice = { [weak self] message in guard let self else { return }; self.undoToast.show(in:self.window,message:message,suffix:"",undoLabel:"",color:self.tint(),offersUndo:false) }
        capture.failed = { [weak self] message in guard let self else { return }; self.showError(self.t("siteActionFailed"),detail:message) }
        capture.closed = { [weak self,weak capture] in if self?.pageCapture === capture { self?.pageCapture = nil } }
        pageCapture = capture; capture.start(fullPage:fullPage)
    }
    private var activeSplit: NativeSplitGroup? { activeTab.flatMap { session.splitGroup(containing:$0.id) } }
    private func splitText(_ fr:String,_ en:String) -> String { session.language == "en" ? en : fr }
    private func isSplitRepresentative(_ id:String) -> Bool {
        guard let group = session.splitGroup(containing:id) else { return true }
        return group.tabIDs.first == id
    }
    private func splitTabIcon(_ tab:NativeTab) -> NSImage? {
        if let value = tab.customIcon, value != "none" {
            let ink = sidebarInk
            return NSImage(size:NSSize(width:24,height:24),flipped:false) { rect in SpaceIcon.draw(value,in:rect,color:ink,size:20); return true }
        }
        return tabFavicon(tab) ?? NSImage(systemSymbolName:"globe",accessibilityDescription:nil)
    }
    private func ensurePage(_ id:String,in parent:NSView) {
        guard let tab = session.tabs.first(where: { $0.id == id }), !destructiveClosing.contains(id) else { return }
        if tab.url.isEmpty || tab.url == "about:blank" || status[id]?.error != nil {
            hideDocument(id)
            return
        }
        if let container = containers[id] {
            if container.superview !== parent { container.removeFromSuperview(); parent.addSubview(container) }
            container.frame = pageBounds(for:id,in:parent); container.isHidden = false
            engine.resizeTab(id,container:container); engine.setTab(id,visible:true)
        } else {
            let container = NSView(frame:pageBounds(for:id,in:parent)); parent.addSubview(container); containers[id] = container
            guard let space = session.spaces.first(where: { $0.id == tab.spaceID }), engine.createTab(id,profile:space.profileID,url:tab.url,container:container) else {
                container.removeFromSuperview(); containers[id] = nil; status[id] = TabStatus(error:NavigationFailure(code:"TAB_UNAVAILABLE",host:URL(string:tab.url)?.host)); return
            }
            engine.setTab(id,visible:true)
        }
        layoutDeveloperPage(id,in:parent)
    }
    private func layoutSplitContent() {
        if activeSplit != nil, !splitHost.isHidden {
            splitHost.frame = content.bounds; splitHost.needsLayout = true; splitHost.layoutSubtreeIfNeeded()
        } else if let id = activeTab?.id, let container = containers[id], container.superview === content {
            layoutDeveloperPage(id,in:content)
        }
    }
    private func resizeSplitPages() {
        for pane in splitHost.panes {
            guard let container = containers[pane.tabID], container.superview === pane.body else { continue }
            layoutDeveloperPage(pane.tabID,in:pane.body)
        }
    }
    private func updateSplitHeaders() {
        guard !splitHost.isHidden else { return }
        for pane in splitHost.panes {
            guard let tab = session.tabs.first(where: { $0.id == pane.tabID }) else { continue }
            pane.update(title:displayTitle(tab),url:tab.url,focused:tab.id == activeTab?.id,canBack:status[tab.id]?.back == true,canForward:status[tab.id]?.forward == true,language:session.language,landingPage:landingPage(for:tab))
        }
    }
    private func trackSplitFocus(_ event:NSEvent) {
        guard event.type == .leftMouseDown, activeSplit != nil, !splitHost.isHiddenOrHasHiddenAncestor,
              siteMenu?.isShown != true, commandPalette == nil else { return }
        for pane in splitHost.panes where pane.bounds.contains(pane.convert(event.locationInWindow,from:nil)) {
            if pane.tabID != activeTab?.id { focusSplitPane(pane.tabID, keyboard:false) }
            break
        }
    }
    private func focusSplitPane(_ id:String,keyboard:Bool = true) {
        guard activeSplit?.tabIDs.contains(id) == true else { selectTab(id); return }
        session.selectTab(id:id); updateToolbar(); renderSpaceContent(); persist()
        if keyboard { engine.focusTab(id) }
    }
    private func splitPaneCommand(_ id:String,_ command:String) {
        focusSplitPane(id,keyboard:false)
        switch command {
        case "back": engine.goBack(id)
        case "forward": engine.goForward(id)
        case "reload": reloadAction(nil)
        case "address": showCommand(newTab:false)
        case "close": removeSplitPane(id)
        case "site": showSiteMenu(anchor:splitHost.panes.first(where: { $0.tabID == id })?.site)
        case "options": if let group = activeSplit { splitHost.panes.first(where: { $0.tabID == id })?.optionsMenu(splitGroupMenu(group)) }
        default: break
        }
    }
    private func makeSplitCell(_ group:NativeSplitGroup) -> NSView {
        let chips = group.tabIDs.compactMap { id -> SplitTabChip? in
            guard let tab = session.tabs.first(where: { $0.id == id }) else { return nil }
            let chip = SplitTabChip(id:id,title:displayTitle(tab),image:splitTabIcon(tab),active:id == activeTab?.id)
            chip.developerMode = tab.developerMode == true && id == activeTab?.id
            chip.select = { [weak self] in
                guard let self else { return }; if self.activeSplit?.id == group.id { self.focusSplitPane(id) } else { self.selectTab(id) }
            }
            chip.context = { [weak self] in self?.splitGroupMenu(group) ?? NSMenu() }
            chip.dragChanged = { [weak self] active in self?.sidebarDragActive = active; if !active { self?.clearDropProposal(); self?.updateSidebarHover() } }
            return chip
        }
        return SplitGroupCell(chips:chips,ink:sidebarInk,title:group.name,icon:group.icon)
    }
    private func selectCommandTab(_ id:String,newTab:Bool) {
        guard !newTab, let blank = activeTab, blank.url == "about:blank", let group = activeSplit,
              let destination = session.tabs.first(where: { $0.id == id }), !destination.favorite,
              destination.spaceID == blank.spaceID, !group.tabIDs.contains(id) else { selectTab(id); return }
        let extra = session.splitGroup(containing:id)?.tabIDs ?? [id]
        guard group.tabIDs.count - 1 + extra.count <= 4 else { splitLimitNotice(); return }
        // Replace the empty pane with an existing tab without creating another page.
        let anchor = group.tabIDs.first { $0 != blank.id }!
        session.closeTab(id:blank.id)
        if session.mergeSplit(id,onto:anchor) { session.selectTab(id:id) }
        render(); showSelectedTab(); persist()
    }
    private func splitLimitNotice() {
        undoToast.show(in:window,message:splitText("Une vue partagée contient au maximum 4 onglets.","A Split View can contain up to 4 tabs."),suffix:"",undoLabel:"",color:tint(),offersUndo:false)
    }
    private func addSplitPane(to id:String? = nil) {
        guard let id = id ?? activeTab?.id, let source = session.tabs.first(where: { $0.id == id }), !source.favorite else { return }
        if (session.splitGroup(containing:id)?.tabIDs.count ?? 1) >= 4 { splitLimitNotice(); return }
        let new = session.createTab(spaceID:source.spaceID)
        guard !new.isEmpty else { return }
        if session.mergeSplit(new,onto:id) {
            session.selectTab(id:new); render(); showSelectedTab(); persist()
            if activeTab?.url == "about:blank" { showCommand(newTab:false) }
        }
    }
    private func removeSplitPane(_ id:String) {
        guard let group = session.splitGroup(containing:id) else { return }
        let next = group.tabIDs.first { $0 != id }
        session.detachSplitTab(id)
        if let next { session.selectTab(id:next) }
        render(); showSelectedTab(); persist()
    }
    private func tabsBelow(_ id:String) -> [String] {
        guard let index = rows.firstIndex(where: { if case .tab(let value) = $0 { return value == id || session.splitGroup(containing:id)?.tabIDs.first == value }; return false }) else { return [] }
        return rows.dropFirst(index+1).flatMap { row -> [String] in
            if case .tab(let value) = row { return session.splitGroup(containing:value)?.tabIDs ?? [value] }; return []
        }
    }
    private func splitGroupMenu(_ group:NativeSplitGroup) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        addMenu(menu,splitText("Partager la vue partagée…","Share Split View…"),"splitShare",group.id)
        menu.addItem(.separator())
        addMenu(menu,splitText("Séparer tous les onglets","Separate All Tabs"),"splitSeparate",group.id)
        addMenu(menu,splitText("Ajouter un onglet…","Add Tab…"),"splitAdd",group.tabIDs.first ?? "")
        menu.items.last?.isEnabled = group.tabIDs.count < 4
        addMenu(menu,group.vertical ? splitText("Convertir en vue horizontale","Convert to Horizontal Split View") : splitText("Convertir en vue verticale","Convert to Vertical Split View"),"splitOrientation",group.id)
        menu.addItem(.separator())
        let heading = NSMenuItem(title:splitText("Options des onglets","Tab Options"),action:nil,keyEquivalent:""); heading.isEnabled = false; menu.addItem(heading)
        for id in group.tabIDs {
            guard let tab = session.tabs.first(where: { $0.id == id }) else { continue }
            addSubmenu(menu,String(displayTitle(tab).prefix(48)),tabMenu(tab))
            let image = splitTabIcon(tab)?.copy() as? NSImage; image?.size = NSSize(width:16,height:16); menu.items.last?.image = image
        }
        menu.addItem(.separator())
        addMenu(menu,splitText("Changer l’icône…","Change Icon…"),"splitIcon",group.id)
        addMenu(menu,splitText("Renommer","Rename"),"splitRename",group.id)
        menu.addItem(.separator())
        addMenu(menu,t("duplicate"),"splitDuplicate",group.id)
        let destinations = NSMenu(); destinations.autoenablesItems = false
        let source = session.tabs.first { $0.id == group.tabIDs.first }
        for space in session.spaces where space.id != source?.spaceID {
            addMenu(destinations,space.name,"splitMove",group.id,space.id)
            destinations.items.last?.isEnabled = space.profileID == session.spaces.first(where: { $0.id == source?.spaceID })?.profileID
        }
        addSubmenu(menu,t("move"),destinations)
        menu.addItem(.separator())
        addMenu(menu,splitText("Archiver le groupe","Archive Item"),"splitArchive",group.id)
        addMenu(menu,splitText("Archiver les onglets suivants","Archive Tabs Below"),"tabsBelow",group.tabIDs.first ?? "")
        menu.items.last?.isEnabled = !tabsBelow(group.tabIDs.first ?? "").isEmpty
        return menu
    }
    private func shareSplitItems(_ ids:[String]) {
        let urls = ids.compactMap { id in session.tabs.first(where: { $0.id == id }).flatMap { URL(string:$0.url) } }
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items:urls); sharingPicker = picker
        picker.show(relativeTo:addressBackground.bounds,of:addressBackground,preferredEdge:.maxY)
    }
    private func editTabOrGroupIcon(_ id:String,group:Bool) {
        let current = group ? session.splitGroups?.first(where: { $0.id == id })?.icon : session.tabs.first(where: { $0.id == id })?.customIcon
        iconPicker?.close()
        let picker = SpaceIconPicker(value:current ?? "none",language:session.language,change:{ [weak self] value in
            guard let self else { return }
            if group, let i = self.session.splitGroups?.firstIndex(where: { $0.id == id }) { self.session.splitGroups?[i].icon = value == "none" ? nil : value }
            else if let i = self.session.tabs.firstIndex(where: { $0.id == id }) { self.session.tabs[i].customIcon = value == "none" ? nil : value }
            self.render(); self.persist()
        },dismissed:{ [weak self] in self?.iconPicker = nil })
        iconPicker = picker
        let point = root.convert(window.convertPoint(fromScreen:NSEvent.mouseLocation),from:nil)
        picker.show(relativeTo:NSRect(x:point.x,y:point.y,width:1,height:1),of:root)
    }
    private func sidebarView(containing id:String) -> NSView? {
        let ids = session.splitGroup(containing:id)?.tabIDs ?? [id]
        guard let row = rows.firstIndex(where: { if case .tab(let value) = $0 { return ids.contains(value) }; return false }) else { return nil }
        table.scrollRowToVisible(row); table.layoutSubtreeIfNeeded()
        return table.view(atColumn:0,row:row,makeIfNecessary:true)
    }
    private func beginTabRename(_ id:String) {
        guard !isQuitting, let tab = session.tabs.first(where: { $0.id == id }) else { return }
        window.makeFirstResponder(nil)
        if let view = sidebarView(containing:id) {
            if let cell = view as? TabCell { beginSidebarTitleEditing(cell); return }
            // Split chips share a row: reuse the existing full-width tab editor
            // so even a compact chip has enough room to edit its complete title.
            editSidebarTitle(in:view,title:displayTitle(tab),icon:splitTabIcon(tab)) { [weak self] name in
                guard let self else { return }
                _ = self.session.renameTab(id:id,name:name); self.refreshTabVisual(id); self.persist()
            }
        } else if tab.favorite, let frame = favorites.frameForItem(id) {
            editSidebarTitle(in:favorites,frame:NSRect(x:0,y:frame.minY,width:favorites.bounds.width,height:frame.height),title:displayTitle(tab),icon:splitTabIcon(tab)) { [weak self] name in
                guard let self else { return }
                _ = self.session.renameTab(id:id,name:name); self.refreshTabVisual(id); self.persist()
            }
        }
    }
    private func beginSplitRename(_ id:String) {
        guard !isQuitting, let group = session.splitGroups?.first(where: { $0.id == id }), let first = group.tabIDs.first else { return }
        window.makeFirstResponder(nil)
        guard let view = sidebarView(containing:first) else { return }
        editSidebarTitle(in:view,title:group.name ?? "",icon:NSImage(systemSymbolName:"rectangle.split.2x1",accessibilityDescription:nil)) { [weak self] name in
            guard let self, let index = self.session.splitGroups?.firstIndex(where: { $0.id == id }) else { return }
            let name = String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80))
            self.session.splitGroups?[index].name = name.isEmpty ? nil : name
            self.render(); self.persist()
        }
    }
    private func beginSidebarTitleEditing(_ cell:TabCell, cleanup:(() -> Void)? = nil) {
        sidebarTitleEditor = cell
        cell.titleEditingEnded = { [weak self] in
            cleanup?(); self?.sidebarTitleEditor = nil; self?.updateSidebarHover()
        }
        cell.beginTitleEditing(); updateSidebarHover()
    }
    private func editSidebarTitle(in view:NSView, frame:NSRect? = nil, title:String, icon:NSImage?, rename:@escaping (String) -> Void) {
        let frame = frame ?? view.bounds
        let hidden = view.subviews.filter { !$0.isHidden && $0.frame.intersects(frame) }
        hidden.forEach { $0.isHidden = true }
        let editor = TabCell(frame:frame)
        editor.autoresizingMask = frame == view.bounds ? [.width,.height] : [.width]
        editor.ink = sidebarInk; editor.titleLabel.stringValue = title; editor.icon.image = icon; editor.rename = rename
        view.addSubview(editor)
        beginSidebarTitleEditing(editor) { [weak self, weak editor] in
            self?.window.makeFirstResponder(nil)
            editor?.removeFromSuperview(); hidden.forEach { $0.isHidden = false }
        }
    }
    private func handleSplitMenu(_ command:MenuAction) -> Bool {
        switch command.kind {
        case "tabCopy":
            if let tab = session.tabs.first(where: { $0.id == command.id }) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(tab.url,forType:.string); showNotice("urlCopied") }
        case "tabShare": shareSplitItems([command.id])
        case "tabIcon": editTabOrGroupIcon(command.id,group:false)
        case "tabRename":
            // Let menu tracking release focus before starting the field editor.
            DispatchQueue.main.async { [weak self] in self?.beginTabRename(command.id) }
        case "tabMute": engine.toggleMute(command.id)
        case "tabsBelow": tabsBelow(command.id).forEach { requestCloseTab($0) }
        case "splitAdd": addSplitPane(to:command.id)
        case "splitDetach": session.detachSplitTab(command.id); session.selectTab(id:command.id); render(); showSelectedTab(); persist()
        case "splitIcon": editTabOrGroupIcon(command.id,group:true)
        case "splitRename":
            DispatchQueue.main.async { [weak self] in self?.beginSplitRename(command.id) }
        case "splitShare", "splitSeparate", "splitOrientation", "splitDuplicate", "splitMove", "splitArchive":
            guard let group = session.splitGroups?.first(where: { $0.id == command.id }) else { return true }
            switch command.kind {
            case "splitShare": shareSplitItems(group.tabIDs); return true
            case "splitArchive": group.tabIDs.forEach { requestCloseTab($0) }; return true
            case "splitSeparate": session.splitGroups?.removeAll { $0.id == group.id }
            case "splitOrientation": if let i = session.splitGroups?.firstIndex(where: { $0.id == group.id }) { session.splitGroups?[i].vertical.toggle() }
            case "splitDuplicate":
                let originals = group.tabIDs.compactMap { id in session.tabs.first { $0.id == id } }
                var copies:[String] = []
                for tab in originals {
                    let id = session.createTab(url:tab.url,spaceID:tab.spaceID)
                    if !id.isEmpty { copies.append(id) }
                }
                if copies.count > 1 { var copy = group; copy.id = UUID().uuidString; copy.tabIDs = copies; session.splitGroups = (session.splitGroups ?? [])+[copy] }
            case "splitMove":
                guard let target = session.spaces.first(where: { $0.id == command.value }),
                      let sourceTab = session.tabs.first(where: { $0.id == group.tabIDs.first }),
                      let old = session.spaces.firstIndex(where: { $0.id == sourceTab.spaceID }), session.spaces[old].profileID == target.profileID else { return true }
                for i in session.tabs.indices where group.tabIDs.contains(session.tabs[i].id) { session.tabs[i].spaceID = target.id; session.tabs[i].folderID = nil }
                if group.tabIDs.contains(session.spaces[old].selectedTabID ?? "") { session.spaces[old].selectedTabID = session.tabs.first(where: { $0.spaceID == sourceTab.spaceID })?.id }
                if let first = group.tabIDs.first { session.selectTab(id:first) }
            default: break
            }
            render(); showSelectedTab(); persist()
        default: return false
        }
        return true
    }
    func populateSplitMenu(_ menu:NSMenu) {
        splitActionsMenu = menu; menu.removeAllItems(); menu.autoenablesItems = false
        for action in SplitShortcutAction.allCases {
            let key = BrowserCommands.resolved(commandOverrides)["split."+action.rawValue] ?? SplitKeyBinding(key:"",modifiers:0)
            let item = NSMenuItem(title:action.title(session.language),action:#selector(splitShortcut(_:)),keyEquivalent:key.key)
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue:key.modifiers)
            item.target = self; item.representedObject = action.rawValue; item.isEnabled = action != .note
            menu.addItem(item)
        }
    }
    @objc private func splitShortcut(_ sender:NSMenuItem) {
        guard window.isKeyWindow, let value = sender.representedObject as? String, let action = SplitShortcutAction(rawValue:value) else { return }
        if action == .add { addSplitPane(); return }
        guard let group = activeSplit, let id = activeTab?.id, let index = group.tabIDs.firstIndex(of:id) else { return }
        switch action {
        case .close: removeSplitPane(id)
        case .separate: session.detachSplitTab(id); render(); showSelectedTab(); persist()
        case .next: focusSplitPane(group.tabIDs[(index+1)%group.tabIDs.count])
        case .previous: focusSplitPane(group.tabIDs[(index+group.tabIDs.count-1)%group.tabIDs.count])
        case .pane1,.pane2,.pane3,.pane4:
            let position = [SplitShortcutAction.pane1,.pane2,.pane3,.pane4].firstIndex(of:action) ?? 0
            if group.tabIDs.indices.contains(position) { focusSplitPane(group.tabIDs[position]) }
        default: break
        }
    }
}

// Native menu commands share the existing controller paths (profiles, undo, splits, captures).
extension BrowserController {
    var menuLanguage: String { session.language }
    var menuSpaces: [NativeSpace] { session.spaces }
    var menuProfiles: [NativeProfile] { session.profiles }
    var menuExtensions: [BrowserExtension] { extensionCatalog.entries(profile:activeSpace?.profileID ?? "") }
    var commandOverrides: [String:SplitKeyBinding] {
        var result = session.commandShortcuts ?? [:]
        for (action,binding) in session.splitShortcuts ?? [:] where result["split."+action] == nil { result["split."+action] = binding }
        return result
    }
    private var orderedMenuTabs: [String] {
        var expanded = session
        for i in expanded.spaces.indices { expanded.spaces[i].foldersCollapsed = false }
        for i in expanded.folders.indices { expanded.folders[i].collapsed = false }
        var ids = session.favoriteTabs(spaceID:session.activeSpaceID).map(\.id)
        for row in expanded.sidebarTree(spaceID:session.activeSpaceID) {
            if case .tab(let id) = row.item {
                for member in session.splitGroup(containing:id)?.tabIDs ?? [id] where !ids.contains(member) { ids.append(member) }
            }
        }
        for item in session.sidebarChildren(spaceID:session.activeSpaceID,parentID:nil,temporary:true) {
            if case .tab(let id) = item {
                for member in session.splitGroup(containing:id)?.tabIDs ?? [id] where !ids.contains(member) { ids.append(member) }
            }
        }
        return ids
    }
    func browserCommandState(_ id: String) -> BrowserMenuState {
        if let command = BrowserCommands.command(id), !command.available { return .init(enabled:false) }
        guard !isQuitting, !closingWindow else { return .init(enabled:false) }
        if ["newWindow","blankWindow","incognito","littleWindow"].contains(id) { return .init(enabled:session.onboardingComplete) }
        if isPrivateWindow && ["history","manageExtensions","addExtension","newProfile","importBrowser"].contains(id) { return .init(enabled:false) }
        if windowKind == .compact && ["sidebar","collapsePinned","newSpace","spaceTheme","spaceRename","newFolder","manageSpaces","split.add"].contains(id) { return .init(enabled:false) }
        if id == "updates" { return .init(enabled:session.onboardingComplete && BrowserUpdates.shared.canCheck) }
        if ["preferences","shortcuts","logs","defaultBrowser","whatsNew"].contains(id) { return .init(enabled:session.onboardingComplete) }
        guard window.isKeyWindow, window.attachedSheet == nil, session.onboardingComplete else { return .init(enabled:false) }
        let page = activeTab.map { containers[$0.id] != nil && !$0.url.isEmpty && $0.url != "about:blank" } ?? false
        let web = activeTab.flatMap { URL(string:$0.url)?.scheme }.map { ["http","https"].contains($0) } ?? false
        let browsing = library == nil && spaceCreation == nil && pageCapture == nil
        if id.hasPrefix("spaceID.") { return .init(checked:session.activeSpaceID == String(id.dropFirst(8))) }
        if id.hasPrefix("space."), let n = Int(id.dropFirst(6)) {
            return .init(enabled:session.spaces.indices.contains(n-1),checked:session.spaces.indices.contains(n-1) && session.spaces[n-1].id == session.activeSpaceID)
        }
        if id.hasPrefix("profile.") { return .init(checked:activeSpace?.profileID == String(id.dropFirst(8))) }
        if id.hasPrefix("extension.") { return .init(enabled:activeTab != nil && browsing) }
        if id.hasPrefix("appearance.") { return .init(checked:(session.themeAppearance ?? .automatic).rawValue == String(id.dropFirst(11))) }
        if id.hasPrefix("split.") {
            guard browsing else { return .init(enabled:false) }
            if id == "split.add" { return .init(enabled:activeTab != nil && (activeSplit?.tabIDs.count ?? 1) < 4) }
            guard let group = activeSplit else { return .init(enabled:false) }
            if id.hasPrefix("split.pane"), let n = Int(id.dropFirst(10)) { return .init(enabled:group.tabIDs.indices.contains(n-1),checked:group.tabIDs.indices.contains(n-1) && group.tabIDs[n-1] == activeTab?.id) }
            return .init()
        }
        switch id {
        case "newTab","commandBar","newFolder": return .init(enabled:spaceCreation == nil)
        case "newProfile": return .init(enabled:session.profiles.count < 50)
        case "newSpace": return .init(enabled:session.spaces.count < BrowserSession.maximumSpaces)
        case "restoreTab","clearArchive": return .init(enabled:!session.closedTabs.isEmpty)
        case "closeTab","duplicateTab","renameTab","revealTab": return .init(enabled:activeTab != nil && browsing)
        case "pinTab": return .init(enabled:activeTab != nil && browsing,title:splitText(activeTab?.pinned == true ? "Désépingler l’onglet" : "Épingler l’onglet",activeTab?.pinned == true ? "Unpin Tab" : "Pin Tab"))
        case "sharePage": return .init(enabled:copyableURL != nil && browsing)
        case "savePage": return .init(enabled:page && browsing && (activeTab.map { engine.canSavePage($0.id) } ?? false))
        case "capture","captureFull","capturePortrait","print","find","reload","forceReload","clearCache","devtools","console","network","inspect":
            let checked = activeTab.map { tab in id == "devtools" ? engine.hasDeveloperTools(tab.id) : ["console","network","inspect"].contains(id) && engine.developerTool(forTab:tab.id) == id } ?? false
            return .init(enabled:page && browsing,checked:checked)
        case "developer": return .init(enabled:page && browsing,checked:activeTab?.developerMode == true,title:splitText(activeTab?.developerMode == true ? "Désactiver le mode développeur" : "Activer le mode développeur",activeTab?.developerMode == true ? "Disable Developer Mode" : "Enable Developer Mode"))
        case "clearCookies": return .init(enabled:page && web && browsing)
        case "pip":
            let open = activeTab.map { engine.hasPictureInPicture($0.id) } ?? false
            return .init(enabled:page && web && browsing,checked:open,title:splitText(open ? "Quitter l’image dans l’image" : "Activer l’image dans l’image",open ? "Exit Picture-in-Picture" : "Enter Picture-in-Picture"))
        case "stop": return .init(enabled:browsing && activeTab.flatMap { status[$0.id]?.loading } == true)
        case "back": return .init(enabled:browsing && activeTab.flatMap { status[$0.id]?.back } == true)
        case "forward": return .init(enabled:browsing && activeTab.flatMap { status[$0.id]?.forward } == true)
        case "zoomIn","zoomOut","zoomReset":
            let zoom = activeTab.map { engine.zoomLevel($0.id) } ?? 0
            return .init(enabled:page && browsing && (id == "zoomReset" ? abs(zoom) > 0.01 : (id == "zoomIn" ? zoom < 9 : zoom > -6)))
        case "sidebar": return .init(title:splitText(session.sidebarHidden ? "Afficher la barre latérale" : "Masquer la barre latérale",session.sidebarHidden ? "Show Sidebar" : "Hide Sidebar"))
        case "collapsePinned": return .init(enabled:activeSpace != nil,title:splitText(activeSpace?.foldersCollapsed == true ? "Déplier les onglets épinglés" : "Replier les onglets épinglés",activeSpace?.foldersCollapsed == true ? "Expand Pinned Tabs" : "Collapse Pinned Tabs"))
        case "spaceNext","spacePrevious": return .init(enabled:session.spaces.count > 1)
        case "tabNext","tabPrevious": return .init(enabled:orderedMenuTabs.count > 1 && browsing)
        case "clearToday": return .init(enabled:session.tabs.contains { $0.spaceID == session.activeSpaceID && !$0.pinned && !$0.favorite })
        case "alwaysOnTop": return .init(enabled:!window.styleMask.contains(.fullScreen),checked:window.level == .floating)
        case "fullscreen": return .init(title:splitText(window.styleMask.contains(.fullScreen) ? "Quitter le mode plein écran" : "Activer le mode plein écran",window.styleMask.contains(.fullScreen) ? "Exit Full Screen" : "Enter Full Screen"))
        case "windowLeft","windowRight","windowTop","windowBottom","windowFill","windowCenter": return .init(enabled:!window.styleMask.contains(.fullScreen))
        default: return .init(enabled:BrowserCommands.command(id)?.available == true)
        }
    }
    func openExternalAddress(_ address: String) {
        guard !isQuitting, isAllowedBrowserURL(address) else { return }
        commandPalette?.close(); siteMenu?.close()
        _ = session.createTab(url:address,spaceID:session.activeSpaceID)
        if library != nil { closeLibrary() }
        render(); showSelectedTab(); persist()
    }
    func performBrowserCommand(_ id: String) {
        guard browserCommandState(id).enabled else { return }
        if id.hasPrefix("spaceID.") { selectSpace(String(id.dropFirst(8))); return }
        if id.hasPrefix("space."), let n = Int(id.dropFirst(6)), session.spaces.indices.contains(n-1) { selectSpace(session.spaces[n-1].id); return }
        if id.hasPrefix("profile.") { changeProfile(session.activeSpaceID,to:String(id.dropFirst(8))); return }
        if id.hasPrefix("extension."), let entry = menuExtensions.first(where: { $0.id == String(id.dropFirst(10)) }) { activateExtension(entry); return }
        if id.hasPrefix("appearance."), let appearance = ThemeAppearance(rawValue:String(id.dropFirst(11))) { session.themeAppearance = appearance; applyTheme(); persist(); return }
        if id.hasPrefix("split.") {
            let item = NSMenuItem(); item.representedObject = String(id.dropFirst(6)); splitShortcut(item); return
        }
        switch id {
        case "updates": BrowserUpdates.shared.check()
        case "whatsNew": BrowserUpdates.shared.showNews()
        case "preferences": settingsAction(nil)
        case "importBrowser": showOnboarding(start:.browserImport,standalone:true)
        case "shortcuts": settingsAction(nil); preferencesWindow?.showShortcuts()
        case "defaultBrowser": setDefaultBrowser()
        case "newWindow": newWindowRequested?(.normal)
        case "blankWindow": newWindowRequested?(.blank)
        case "incognito": newWindowRequested?(.privateWindow)
        case "littleWindow": newWindowRequested?(.compact)
        case "newTab": newTabAction(nil)
        case "commandBar": openLocationAction(nil)
        case "restoreTab": restoreTabAction(nil)
        case "closeTab": closeTabAction(nil)
        case "newProfile": createProfile()
        case "sharePage":
            if let url = copyableURL {
                let picker = NSSharingServicePicker(items:[url]); sharingPicker = picker
                picker.show(relativeTo:NSRect(x:content.bounds.midX,y:content.bounds.maxY-1,width:1,height:1),of:content,preferredEdge:.minY)
            }
        case "capture": capturePageAction(nil)
        case "captureFull": if let tab = activeTab { startPageCapture(for:tab.id,fullPage:true) }
        case "capturePortrait": if let tab = activeTab { showPortraitCapture(for:tab.id,anchor:content) }
        case "savePage": if let tab = activeTab { engine.savePage(tab.id) }
        case "print": if let tab = activeTab { engine.printPage(tab.id) }
        case "sidebar": toggleSidebarAction(nil)
        case "collapsePinned": sidebarCollapse.toggle(.space(session.activeSpaceID),in:&session); render(); persist()
        case "reload": if let tab = activeTab { engine.reload(tab.id) }
        case "forceReload": if let tab = activeTab { engine.reloadIgnoringCache(tab.id) }
        case "stop": if let tab = activeTab { engine.stop(tab.id) }
        case "clearCache","clearCookies":
            if let tab = activeTab {
                let completion: (Bool)->Void = { [weak self] ok in
                    guard let self, !self.isQuitting else { return }
                    if ok { self.engine.reload(tab.id) }
                    else { self.showError(self.t("siteActionFailed"),detail:"") }
                }
                if id == "clearCache" { engine.clearCache(forTab:tab.id,completion:completion) }
                else { engine.clearCookies(forTab:tab.id,completion:completion) }
            }
        case "zoomReset","zoomIn","zoomOut": if let tab = activeTab { engine.setZoomLevel(tab.id,level:id == "zoomReset" ? 0 : engine.zoomLevel(tab.id)+(id == "zoomIn" ? 1 : -1)) }
        case "find": findAction(nil)
        case "pip": pictureInPictureAction(nil)
        case "developer": if let tab = activeTab { toggleDeveloperMode(for:tab.id) }
        case "devtools": if let tab = activeTab { engine.toggleDeveloperTools(tab.id); updateDeveloperBars() }
        case "console","network","inspect": if let tab = activeTab { engine.toggleDeveloperTool(id,forTab:tab.id); updateDeveloperBars() }
        case "fullscreen": window.toggleFullScreen(nil)
        case "newSpace": newSpaceAction(nil)
        case "spaceTheme": editSpaceAppearance(session.activeSpaceID,icon:false)
        case "spaceRename": renameSpace(session.activeSpaceID)
        case "spaceNext": nextSpaceAction(nil)
        case "spacePrevious": previousSpaceAction(nil)
        case "manageSpaces": manageSpaces()
        case "newFolder": newFolder()
        case "pinTab","duplicateTab": if let tab = activeTab { let item = NSMenuItem(); item.representedObject = MenuAction(id == "pinTab" ? "pin" : "duplicate",tab.id); menuAction(item) }
        case "renameTab": if let tab = activeTab { revealActiveTab(); beginTabRename(tab.id) }
        case "tabNext","tabPrevious":
            let ids = orderedMenuTabs
            if !ids.isEmpty { let index = activeTab.flatMap { ids.firstIndex(of:$0.id) } ?? 0; selectTab(ids[(index+ids.count+(id == "tabNext" ? 1 : -1))%ids.count]) }
        case "revealTab": revealActiveTab()
        case "clearToday": clearTemporaryTabs()
        case "back": backAction(nil)
        case "forward": forwardAction(nil)
        case "history": openExternalAddress("chrome://history/")
        case "archive","library","downloads","media":
            if library == nil { showLibrary() }
            if id == "archive" { library?.switchSection(.archived) }
            if id == "downloads" { library?.switchSection(.downloads) }
            if id == "media" { library?.switchSection(.media) }
        case "clearArchive":
            let alert = NSAlert(); alert.messageText = splitText("Vider les archives ?","Clear the archive?")
            alert.informativeText = splitText("Les onglets archivés ne pourront plus être restaurés. Vos onglets ouverts et votre historique seront conservés.","Archived tabs will no longer be restorable. Open tabs and browsing history will be kept.")
            alert.addButton(withTitle:splitText("Vider les archives","Clear Archive")); alert.addButton(withTitle:t("cancel"))
            alert.beginSheetModal(for:window) { [weak self] response in
                guard let self, response == .alertFirstButtonReturn else { return }
                self.session.closedTabs.removeAll(); self.persist(); self.library?.update(session:self.session)
            }
        case "alwaysOnTop": window.level = window.level == .floating ? .normal : .floating
        case "windowFill","windowCenter","windowLeft","windowRight","windowTop","windowBottom": arrangeBrowserWindow(id)
        case "logs":
            let folder = store.directory.appendingPathComponent("Chromium/Diagnostics",isDirectory:true)
            NSWorkspace.shared.open(FileManager.default.fileExists(atPath:folder.path) ? folder : store.directory)
        default: break
        }
    }
    private func revealActiveTab() {
        guard let tab = activeTab else { return }
        if session.sidebarHidden { toggleSidebarAction(nil) }
        if activeSpace?.foldersCollapsed == true { sidebarCollapse.toggle(.space(session.activeSpaceID),in:&session) }
        var folder = tab.folderID
        var visited = Set<String>()
        while let id = folder, visited.insert(id).inserted, let item = session.folders.first(where: { $0.id == id }) {
            if item.collapsed { sidebarCollapse.toggle(.folder(id),in:&session) }; folder = item.parentID
        }
        render(); persist(); _ = sidebarView(containing:tab.id)
    }
    private func arrangeBrowserWindow(_ command: String) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        if command == "windowCenter" {
            frame.size.width = min(frame.width,visible.width); frame.size.height = min(frame.height,visible.height)
            frame.origin = NSPoint(x:visible.midX-frame.width/2,y:visible.midY-frame.height/2)
        } else {
            frame = visible
            if ["windowLeft","windowRight"].contains(command) {
                frame.size.width = min(visible.width,max(window.minSize.width,visible.width/2))
                if command == "windowRight" { frame.origin.x = visible.maxX-frame.width }
            }
            if ["windowTop","windowBottom"].contains(command) {
                frame.size.height = min(visible.height,max(window.minSize.height,visible.height/2))
                if command == "windowTop" { frame.origin.y = visible.maxY-frame.height }
            }
        }
        window.setFrame(frame,display:true,animate:!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    private func setDefaultBrowser() {
        let applicationURL = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at:applicationURL,toOpenURLsWithScheme:"http") { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error { self.showError(self.splitText("Navigateur par défaut","Default Browser"),detail:error.localizedDescription); return }
                NSWorkspace.shared.setDefaultApplication(at:applicationURL,toOpenURLsWithScheme:"https") { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self, let error else { return }
                        self.showError(self.splitText("Navigateur par défaut","Default Browser"),detail:error.localizedDescription)
                    }
                }
            }
        }
    }
}

extension BrowserController {
    func resumeAfterCancelledQuit() {
        isQuitting = false; pictureInPicture.resume(); showSelectedTab()
    }
    var windowSession: BrowserSession { session }
    var selectedWindowURL: String? { activeTab?.url }
    var selectedWindowTabID: String? { activeTab?.id }
    func rendererID(for tab:String) -> String { engine.rendererID(tab) }
    var isClosingWindow: Bool { closingWindow }
    var isManagingSpaces: Bool { library?.section == .spaces }
    func requestWindowClose() {
        guard !isQuitting, !closingWindow, window.attachedSheet == nil else { return }
        saveTask?.cancel()
        do { try store.save(session) } catch { showError(t("saveError"),detail:error.localizedDescription); return }
        closingWindow = true; windowCloseCancelled = false
        closeParticipants = Set(containers.keys); closeWaiting = closeParticipants
        pageCapture?.close(); portraitCapture?.close(); commandPalette?.close(); siteMenu?.close()
        closeNextWindowTab()
    }
    private func closeNextWindowTab() {
        guard closingWindow, !isQuitting else { return }
        guard let id = closeWaiting.sorted().first else { finishWindowCloseAttempt(); return }
        engine.closeTab(id)
    }
    private func finishWindowCloseAttempt() {
        guard closingWindow else { return }
        if windowCloseCancelled {
            closingWindow = false; closeParticipants.removeAll(); closeWaiting.removeAll(); showSelectedTab(); return
        }
        if !closeWaiting.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.closeNextWindowTab() }; return
        }
        // Release the controller outside Chromium's OnBeforeClose callback.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.closingWindow, !self.isQuitting else { return }
            guard self.prepareToQuit() else { self.closingWindow = false; self.showSelectedTab(); return }
            self.window.delegate = nil; self.window.close(); self.windowClosed?(self)
        }
    }
    // Blank and compact windows keep their own tabs, but use the same profile preferences.
    func receiveNavigationPreferences(_ source:NativeProfile,as localID:String) {
        guard let i = session.profiles.firstIndex(where:{ $0.id == localID }) else { return }
        let previous = session.profiles[i]
        guard previous.searchEngineID != source.searchEngineID || previous.newTabAddress != source.newTabAddress || previous.archiveAfterHours != source.archiveAfterHours || previous.autoArchiveEnabledSince != source.autoArchiveEnabledSince else { return }
        session.profiles[i].searchEngineID = source.searchEngineID; session.profiles[i].newTabAddress = source.newTabAddress
        session.profiles[i].archiveAfterHours = source.archiveAfterHours
        session.profiles[i].autoArchiveEnabledSince = source.autoArchiveEnabledSince
        if previous.engine != source.engine { configureEngine(source.engine,profileID:localID) }
        preferencesWindow?.refreshNavigationPreferences(); buildHome(); updateSplitHeaders()
    }
    func receiveInterfaceStyle(_ style:BrowserInterface?) {
        guard session.interfaceStyle != style else { return }
        session.interfaceStyle = style
        preferencesWindow?.refreshInterface(session.currentInterface)
        commandPalette?.close(); siteMenu?.close()
        render()
    }
    func receiveSharedSession(_ shared:BrowserSession) {
        guard !isQuitting, !closingWindow else { return }
        let previous = session
        var next = shared
        next.sidebarWidth = previous.sidebarWidth; next.sidebarHidden = previous.sidebarHidden
        if next.spaces.contains(where: { $0.id == previous.activeSpaceID }) { next.activeSpaceID = previous.activeSpaceID }
        for i in next.spaces.indices {
            if let local = previous.spaces.first(where: { $0.id == next.spaces[i].id }),
               let selected = local.selectedTabID, next.canSelectTab(selected,in:local.id) { next.spaces[i].selectedTabID = selected }
        }
        guard next != previous else { return }
        session = next
        for profile in next.profiles where previous.profiles.first(where: { $0.id == profile.id })?.engine != profile.engine {
            configureEngine(profile.engine,profileID:profile.id)
        }
        if previous.currentInterface != next.currentInterface {
            preferencesWindow?.refreshInterface(next.currentInterface)
            commandPalette?.close(); siteMenu?.close()
        }
        if previous.profiles != next.profiles { preferencesWindow?.refreshNavigationPreferences() }
        let changedProfiles = Set(next.spaces.filter { space in previous.spaces.first(where: { $0.id == space.id })?.profileID != space.profileID }.map(\.id))
        discardDeletedBrowsers(Set(next.tabs.filter { changedProfiles.contains($0.spaceID) }.map(\.id)))
        let removed = Set(previous.tabs.map(\.id)).subtracting(next.tabs.map(\.id))
        discardDeletedBrowsers(removed)
        for tab in next.tabs where containers[tab.id] != nil {
            if let old = previous.tabs.first(where: { $0.id == tab.id }), old.url != tab.url { engine.navigateTab(tab.id,url:tab.url) }
        }
        library?.update(session:session); render(); showSelectedTab()
    }
}
