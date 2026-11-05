import AppKit
import QuartzCore

final class AddMenuButton: NSButton {
    var invoke: (() -> Void)?
    var ink = NSColor.labelColor { didSet { refresh() } }
    private let mark = CAShapeLayer()
    private var hovered = false
    private var expanded = false
    private var tracking: NSTrackingArea?
    override init(frame: NSRect) {
        super.init(frame:frame)
        title = ""; isBordered = false; wantsLayer = true
        layer?.cornerRadius = 8
        mark.fillColor = nil; mark.lineWidth = 2; mark.lineCap = .round
        layer?.addSublayer(mark)
        target = self; action = #selector(activate)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func activate() { invoke?() }
    override func draw(_ dirtyRect: NSRect) {}
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        mark.bounds = CGRect(x:0,y:0,width:18,height:18)
        mark.position = CGPoint(x:bounds.midX,y:bounds.midY)
        let path = CGMutablePath()
        path.move(to:CGPoint(x:3,y:9)); path.addLine(to:CGPoint(x:15,y:9))
        path.move(to:CGPoint(x:9,y:3)); path.addLine(to:CGPoint(x:9,y:15))
        mark.path = path
        CATransaction.commit()
    }
    func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        expanded = value
        if !value, let window {
            hovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream,from:nil))
        }
        let angle = value ? Double.pi/4 : 0
        let previous = (mark.presentation()?.value(forKeyPath:"transform.rotation.z") as? NSNumber)?.doubleValue ?? (value ? 0 : Double.pi/4)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        mark.setValue(angle,forKeyPath:"transform.rotation.z")
        CATransaction.commit()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath:"transform.rotation.z")
            animation.fromValue = previous; animation.toValue = angle; animation.duration = 0.22
            animation.timingFunction = CAMediaTimingFunction(controlPoints:0.22,0.75,0.25,1)
            mark.add(animation,forKey:"menu-turn")
        }
        refresh()
    }
    private func refresh() {
        let color = ink.withAlphaComponent(hovered || expanded ? 0.09 : 0).cgColor
        let previous = layer?.presentation()?.backgroundColor ?? layer?.backgroundColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        mark.strokeColor = ink.withAlphaComponent(hovered || expanded ? 0.9 : 0.65).cgColor; layer?.backgroundColor = color
        CATransaction.commit()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath:"backgroundColor")
            animation.fromValue = previous; animation.toValue = color; animation.duration = 0.12
            layer?.add(animation,forKey:"menu-hover")
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { trackPointer(event) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    func trackPointer(_ event: NSEvent) {
        setHovered(event.window === window && event.type != .mouseExited && !isHiddenOrHasHiddenAncestor && bounds.contains(convert(event.locationInWindow,from:nil)))
    }
    private func setHovered(_ value: Bool) { guard hovered != value else { return }; hovered = value; refresh() }
}

struct AddMenuEntry {
    let title: String
    let symbol: String
    let shortcut: String
    let separatorBefore: Bool
    let action: (() -> Void)?
}

private final class AddMenuRow: NSButton {
    var choose: (() -> Void)?
    var hover: (() -> Void)?
    var selectedRow = false { didSet { needsDisplay = true } }
    let entry: AddMenuEntry
    let tint: NSColor
    private var tracking: NSTrackingArea?
    init(_ entry: AddMenuEntry, tint: NSColor) {
        self.entry = entry; self.tint = tint
        super.init(frame:.zero)
        title = ""; isBordered = false; focusRingType = .none
        isEnabled = entry.action != nil
        target = self; action = #selector(activate)
        setAccessibilityLabel(entry.title)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func activate() { if isEnabled { choose?() } }
    override func draw(_ dirtyRect: NSRect) {
        if selectedRow && isEnabled {
            tint.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect:bounds,xRadius:9,yRadius:9).fill()
        }
        let foreground = NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.38)
        let rect = NSRect(x:11,y:(bounds.height-20)/2,width:20,height:20)
        let icon = NSImage(size:rect.size,flipped:false) { target in
            NSImage(systemSymbolName:self.entry.symbol,accessibilityDescription:nil)?.draw(in:target)
            foreground.setFill(); target.fill(using:.sourceAtop); return true
        }
        icon.draw(in:rect)
        let text = NSAttributedString(string:entry.title,attributes:[.font:NSFont.systemFont(ofSize:14,weight:.semibold),.foregroundColor:foreground])
        text.draw(at:NSPoint(x:42,y:(bounds.height-text.size().height)/2))
        let shortcut = NSAttributedString(string:entry.shortcut,attributes:[.font:NSFont.systemFont(ofSize:12,weight:.medium),.foregroundColor:NSColor.white.withAlphaComponent(isEnabled ? 0.45 : 0.24)])
        shortcut.draw(at:NSPoint(x:bounds.width-shortcut.size().width-12,y:(bounds.height-shortcut.size().height)/2))
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hover?() }
}

private final class AddMenuSurface: NSView {
    var key: ((NSEvent) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { key?(event) }
}

final class AddMenuPopover: NSObject, NSPopoverDelegate {
    var onClosing: (() -> Void)?
    var onClose: (() -> Void)?
    private let popover = NSPopover()
    private let surface = AddMenuSurface()
    private var rows: [AddMenuRow] = []
    private var selected = -1
    private var pendingAction: (() -> Void)?
    private var menuSize = NSSize.zero
    init(entries: [AddMenuEntry], tint: NSColor) {
        super.init()
        let width: CGFloat = 268
        surface.wantsLayer = true
        surface.layer?.backgroundColor = (NSColor.black.blended(withFraction:0.13,of:tint) ?? .black).cgColor
        var y: CGFloat = 8
        for entry in entries {
            if entry.separatorBefore {
                let line = NSView(frame:NSRect(x:12,y:y+7,width:width-24,height:0.5))
                line.wantsLayer = true; line.layer?.backgroundColor = tint.withAlphaComponent(0.45).cgColor
                surface.addSubview(line); y += 16
            }
            let row = AddMenuRow(entry,tint:tint)
            row.frame = NSRect(x:8,y:y,width:width-16,height:40)
            let index = rows.count
            row.hover = { [weak self] in self?.select(index) }
            row.choose = { [weak self] in self?.choose(index) }
            rows.append(row); surface.addSubview(row); y += 40
        }
        surface.frame = NSRect(x:0,y:0,width:width,height:y+8)
        menuSize = surface.frame.size
        surface.key = { [weak self] event in
            guard let self else { return }
            switch event.keyCode {
            case 53: self.close()
            case 125: self.step(1)
            case 126: self.step(-1)
            case 36, 76: self.choose(self.selected)
            default: break
            }
        }
        // Extend the opaque menu background into AppKit's chevron. Keep rows
        // inside the safe area so the arrow never steals their bottom padding.
        let background = NSView(frame:surface.frame)
        background.wantsLayer = true
        background.layer?.backgroundColor = surface.layer?.backgroundColor
        background.addSubview(surface)
        surface.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo:background.safeAreaLayoutGuide.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo:background.safeAreaLayoutGuide.trailingAnchor),
            surface.topAnchor.constraint(equalTo:background.safeAreaLayoutGuide.topAnchor),
            surface.bottomAnchor.constraint(equalTo:background.safeAreaLayoutGuide.bottomAnchor)
        ])
        let controller = NSViewController(); controller.view = background
        if #available(macOS 14.0, *) { popover.hasFullSizeContent = true }
        popover.contentViewController = controller; popover.contentSize = menuSize
        popover.appearance = NSAppearance(named:.vibrantDark)
        popover.behavior = .transient; popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
    }
    func show(from button: NSView) {
        popover.show(relativeTo:button.bounds,of:button,preferredEdge:.maxY)
        surface.window?.makeFirstResponder(surface)
    }
    func close() { popover.performClose(nil) }
    private func select(_ index: Int) {
        selected = rows.indices.contains(index) && rows[index].isEnabled ? index : -1
        for (i,row) in rows.enumerated() { row.selectedRow = i == selected }
    }
    private func step(_ direction: Int) {
        let enabled = rows.indices.filter { rows[$0].isEnabled }
        guard !enabled.isEmpty else { return }
        let index = enabled.firstIndex(of:selected) ?? (direction > 0 ? -1 : 0)
        select(enabled[(index+direction+enabled.count)%enabled.count])
    }
    private func choose(_ index: Int) {
        guard rows.indices.contains(index), let action = rows[index].entry.action else { return }
        pendingAction = action; close()
    }
    private func fitSafeContent() {
        guard let background = popover.contentViewController?.view else { return }
        background.layoutSubtreeIfNeeded()
        let delta = NSSize(width:menuSize.width-surface.bounds.width,height:menuSize.height-surface.bounds.height)
        guard abs(delta.width) > 0.5 || abs(delta.height) > 0.5 else { return }
        let animate = popover.animates; popover.animates = false
        popover.contentSize = NSSize(width:popover.contentSize.width+delta.width,height:popover.contentSize.height+delta.height)
        background.layoutSubtreeIfNeeded(); popover.animates = animate
    }
    func popoverWillShow(_ notification: Notification) { fitSafeContent() }
    func popoverDidShow(_ notification: Notification) { fitSafeContent() }
    func popoverWillClose(_ notification: Notification) { onClosing?() }
    func popoverDidClose(_ notification: Notification) {
        let action = pendingAction; pendingAction = nil
        onClose?(); action?()
    }
}
