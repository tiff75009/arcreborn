// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

final class TabCloseButton: ActionButton {
    var acceptsPointerAt: ((NSPoint) -> Bool)?
    private var hovered = false
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        updateHover(at:window?.mouseLocationOutsideOfEventStream)
    }
    override func mouseEntered(with event: NSEvent) { updateHover(at:window?.mouseLocationOutsideOfEventStream) }
    override func mouseExited(with event: NSEvent) { updateHover(at:window?.mouseLocationOutsideOfEventStream) }
    func updateHover(at point:NSPoint?) {
        let inside = point.map {
            window != nil && !isHiddenOrHasHiddenAncestor && bounds.intersection(visibleRect).contains(convert($0,from:nil)) &&
            acceptsPointerAt?($0) != false
        } ?? false
        guard inside != hovered else { return }
        hovered = inside; needsDisplay = true
    }
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
final class TabTitleField: NSTextField {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: isEditable ? .iBeam : .arrow)
    }
}
final class TabCell: NSTableCellView, NSTextFieldDelegate {
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
    let icon = NSImageView(); let titleLabel = TabTitleField(frame: .zero); let closeButton: TabCloseButton
    var rename: ((String) -> Void)?
    var titleEditingEnded: (() -> Void)?
    var acceptsPointerAt: ((NSPoint) -> Bool)? { didSet { closeButton.acceptsPointerAt = acceptsPointerAt } }
    private(set) var isEditingTitle = false
    private var originalTitle = ""
    var depth = 0 { didSet { needsLayout = true } }
    private var folderIcon: FolderDisclosureIcon?
    let soundButton = TabSoundButton()
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
        titleLabel.isEditable = false; titleLabel.isSelectable = false; titleLabel.allowsExpansionToolTips = false
        titleLabel.isBordered = false; titleLabel.isBezeled = false; titleLabel.drawsBackground = false
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.delegate = self; titleLabel.focusRingType = .none
        addSubview(icon); addSubview(titleLabel); addSubview(closeButton); addSubview(soundButton)
        closeButton.isHidden = true
        layer?.addSublayer(developerOutline)
    }
    required init?(coder: NSCoder) { fatalError() }
    func showFolder(_ folder: NativeFolder, tint: NSColor, animated: Bool = false) {
        let glyph = folderIcon ?? FolderDisclosureIcon()
        if folderIcon == nil {
            folderIcon = glyph
            addSubview(glyph)
            needsLayout = true
        }
        icon.isHidden = true
        glyph.configure(folder, ink: ink, tint: tint, animated: animated)
        setAccessibilityExpanded(!folder.collapsed)
    }
    func setTabHint(_ text:String) {
        setAccessibilityHelp(text); titleLabel.setAccessibilityHelp(text)
        toolTip = nil; titleLabel.toolTip = nil
    }
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
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self)
        addTrackingArea(tracking!)
        updateHover(at:window?.mouseLocationOutsideOfEventStream)
    }
    // Scrolling can replace tracking areas before their queued enter/exit events
    // arrive. The live pointer and clipped row geometry are the source of truth.
    override func mouseEntered(with event: NSEvent) { updateHover(at:window?.mouseLocationOutsideOfEventStream) }
    override func mouseExited(with event: NSEvent) { updateHover(at:window?.mouseLocationOutsideOfEventStream) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateHover(at:window?.mouseLocationOutsideOfEventStream)
    }
    func updateHover(at point:NSPoint?) {
        let inside = point.map {
            window != nil && !isHiddenOrHasHiddenAncestor && bounds.intersection(visibleRect).contains(convert($0,from:nil)) &&
            acceptsPointerAt?($0) != false
        } ?? false
        if inside != hovered {
            hovered = inside
            closeButton.isHidden = isEditingTitle || !canClose || !inside
            updateLayer()
        }
        closeButton.updateHover(at:inside ? point : nil)
        if !inside { soundButton.setHovered(false) }
    }
    func clearHover() { updateHover(at:nil) }
    func setDepth(_ value:Int, animated:Bool) {
        guard depth != value else { return }
        layoutSubtreeIfNeeded()
        let views = [icon,titleLabel,soundButton] + (folderIcon.map { [$0 as NSView] } ?? [])
        let previous = views.map(\.frame)
        depth = value; layoutSubtreeIfNeeded()
        guard animated, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let target = views.map(\.frame)
        for (i,view) in views.enumerated() { view.frame = previous[i] }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(controlPoints:0.22,0.80,0.24,1)
            for (i,view) in views.enumerated() { view.animator().frame = target[i] }
        }
    }
    override func layout() {
        super.layout()
        developerOutline.update(in:bounds,enabled:developerMode)
        let indent = CGFloat(min(depth,8))*16
        icon.frame = NSRect(x:12+indent,y:(bounds.height-16)/2,width:16,height:16)
        let glyphSize = FolderDisclosureIcon.size
        folderIcon?.frame = NSRect(x:20-glyphSize/2+indent,y:(bounds.height-glyphSize)/2,width:glyphSize,height:glyphSize)
        let inset = soundButton.titleInset
        soundButton.frame = NSRect(x:34+indent,y:bounds.midY-12,width:23,height:24)
        closeButton.frame = NSRect(x:bounds.width-28,y:(bounds.height-22)/2,width:22,height:22)
        // NSTextField adds a 2 pt text inset; align its glyphs with the header at x = 37.
        if isEditingTitle {
            // A separate layer adds padding without intercepting the native field editor.
            let fieldRect = NSRect(x:32+indent+inset,y:(bounds.height-28)/2,width:max(0,bounds.width-40-indent-inset),height:28)
            titleEditingBackground.frame = fieldRect
            titleLabel.frame = NSRect(x:fieldRect.minX+6,y:(bounds.height-19)/2,width:max(0,fieldRect.width-12),height:19)
        } else {
            titleLabel.frame = NSRect(x:35+indent+inset,y:(bounds.height-19)/2,width:max(0,bounds.width-67-indent-inset),height:19)
        }
        updateHover(at:window?.mouseLocationOutsideOfEventStream)
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
