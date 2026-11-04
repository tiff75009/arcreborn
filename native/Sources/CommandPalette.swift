import AppKit

struct CommandSuggestion {
    let title: String
    let detail: String
    let image: NSImage?
    let symbol: String
    let perform: () -> Void
}
private final class CommandWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
private final class CommandSurface: NSView {
    var compact = false
    var tint = NSColor.systemPurple
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: 12, yRadius: 12)
        NSGraphicsContext.saveGraphicsState(); path.addClip()
        let end = NSColor(srgbRed: 0.085, green: 0.085, blue: 0.09, alpha: 0.99)
        let start = compact ? (end.blended(withFraction: 0.17, of: tint) ?? end) : end
        NSGradient(starting: start, ending: end)?.draw(in: bounds, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.26).setStroke(); path.lineWidth = 0.75; path.stroke()
    }
}
private final class CommandRow: NSButton {
    let badge = NSView(), icon = NSImageView(), name = NSTextField(labelWithString: ""), detail = NSTextField(labelWithString: ""), arrow = NSImageView()
    var choose: (() -> Void)?
    var hover: (() -> Void)?
    var selected = false { didSet { refresh() } }
    var compact = false
    private var tracking: NSTrackingArea?
    init(_ item: CommandSuggestion, compact: Bool) {
        super.init(frame: .zero)
        self.compact = compact; title = ""; isBordered = false; target = self; action = #selector(activate)
        focusRingType = .none; wantsLayer = true; layer?.cornerRadius = 6
        badge.wantsLayer = true; badge.layer?.cornerRadius = 5
        icon.image = item.image ?? NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyDown
        badge.layer?.backgroundColor = item.image == nil ? NSColor.white.withAlphaComponent(0.04).cgColor : NSColor.white.cgColor
        name.stringValue = item.title; name.font = .systemFont(ofSize: 14, weight: .semibold); name.lineBreakMode = .byTruncatingTail
        detail.stringValue = item.detail; detail.font = .systemFont(ofSize: 13, weight: .medium); detail.lineBreakMode = .byTruncatingTail
        arrow.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)
        arrow.wantsLayer = true; arrow.layer?.cornerRadius = 5
        arrow.imageScaling = .scaleProportionallyDown
        for v in [badge, name, detail, arrow] { addSubview(v) }; badge.addSubview(icon)
        detail.isHidden = compact; arrow.isHidden = compact
        setAccessibilityLabel(item.title + (item.detail.isEmpty ? "" : ", " + item.detail))
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func activate() { choose?() }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hover?() }
    override func layout() {
        super.layout()
        badge.frame = NSRect(x: 10, y: (bounds.height-24)/2, width: 24, height: 24); icon.frame = NSRect(x: 4, y: 4, width: 16, height: 16)
        let detailWidth: CGFloat = compact ? 0 : min(190, bounds.width*0.30)
        name.frame = NSRect(x: 42, y: (bounds.height-20)/2, width: max(50,bounds.width-58-detailWidth-(compact ? 0 : 32)), height: 20)
        detail.frame = NSRect(x: bounds.width-detailWidth-42, y: (bounds.height-20)/2, width: detailWidth, height: 20); detail.alignment = .right
        arrow.frame = NSRect(x: bounds.width-36, y: (bounds.height-24)/2, width: 24, height: 24)
    }
    private func refresh() {
        layer?.backgroundColor = selected ? NSColor(srgbRed: 0.61, green: 0.15, blue: 0.46, alpha: 1).cgColor : NSColor.clear.cgColor
        name.textColor = NSColor.white.withAlphaComponent(selected ? 1 : 0.78)
        detail.textColor = NSColor.white.withAlphaComponent(selected ? 0.95 : 0.36)
        icon.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        arrow.layer?.backgroundColor = NSColor.white.withAlphaComponent(selected ? 1 : 0.04).cgColor
        arrow.contentTintColor = selected ? NSColor(srgbRed: 0.78, green: 0.3, blue: 0.62, alpha: 1) : NSColor.white.withAlphaComponent(0.6)
    }
}

/// Two non-modal child panels. Dismissing never creates a tab or navigates.
final class CommandPalette: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    let isNewTab: Bool
    private let isCentered: Bool
    private weak var addressAnchor: NSView?
    private let parent: NSWindow
    private let panel: CommandWindow
    private let surface = CommandSurface()
    private let input = NSTextField()
    private let inputViewport = FadingTextViewport(frame: .zero)
    private let leading = NSImageView()
    private let info = NSButton()
    private let separator = NSView()
    private let help = NSTextField(wrappingLabelWithString: "")
    private let suggestions: (String) -> [CommandSuggestion]
    private let onDismiss: () -> Void
    private var items: [CommandSuggestion] = []
    private var rows: [CommandRow] = []
    private var selectedIndex = 0
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var closed = false
    private var helpVisible = false

    init(parent: NSWindow, newTab: Bool, centered: Bool = false, addressAnchor: NSView? = nil, initial: String, icon: NSImage?, tint: NSColor, language: String, suggestions: @escaping (String) -> [CommandSuggestion], onDismiss: @escaping () -> Void) {
        self.addressAnchor = addressAnchor
        self.parent = parent; isNewTab = newTab; self.suggestions = suggestions; self.onDismiss = onDismiss
        isCentered = newTab || centered
        panel = CommandWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.isMovable = false; panel.isFloatingPanel = false; panel.hidesOnDeactivate = false; panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua); panel.title = L10n.text(isCentered ? "newTab" : "address", language: language)
        surface.compact = !isCentered; surface.tint = tint; panel.contentView = surface
        input.isBordered = false; input.drawsBackground = false; input.focusRingType = .none
        input.maximumNumberOfLines = 1
        input.cell?.wraps = false; input.cell?.isScrollable = true
        input.cell?.usesSingleLineMode = true; input.lineBreakMode = .byClipping
        input.textColor = .white; input.font = .systemFont(ofSize: isCentered ? 18 : 14, weight: .semibold)
        input.placeholderAttributedString = NSAttributedString(string: L10n.text("commandPlaceholder", language: language), attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.48), .font: input.font!])
        input.stringValue = initial; input.delegate = self; input.target = self; input.action = #selector(submit)
        input.setAccessibilityLabel(L10n.text("address", language: language))
        leading.image = !isCentered ? (icon ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)) : NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        leading.contentTintColor = .white; leading.imageScaling = .scaleProportionallyDown
        info.isBordered = false; info.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil); info.imagePosition = .imageOnly
        info.contentTintColor = NSColor.white.withAlphaComponent(0.55); info.wantsLayer = true; info.layer?.cornerRadius = 12; info.layer?.backgroundColor = NSColor(srgbRed: 0.09, green: 0, blue: 0.055, alpha: 1).cgColor
        info.target = self; info.action = #selector(toggleHelp); info.setAccessibilityLabel(L10n.text("commandHelp", language: language)); info.toolTip = L10n.text("commandKeys", language: language)
        help.stringValue = L10n.text("commandKeys", language: language); help.font = .systemFont(ofSize: 12); help.textColor = NSColor.white.withAlphaComponent(0.6); help.isHidden = true
        separator.wantsLayer = true; separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor; separator.isHidden = !isCentered
        inputViewport.addSubview(input)
        for v in [leading,inputViewport,info,separator,help] { surface.addSubview(v) }
        rebuild()
    }
    func show() {
        parent.addChildWindow(panel, ordered: .above); position(); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(input)
        if !isCentered { input.selectText(nil) }
        if let editor = input.currentEditor() as? NSTextView { editor.insertionPointColor = .systemPink }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, !self.closed else { return event }
            if event.window !== self.panel {
                self.close()
                // Consume the dismissal click so an underlying web action cannot fire.
                return nil
            }
            return event
        }
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in self?.position() })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.close() })
    }
    func close() {
        guard !closed else { return }; closed = true
        let restoreParentFocus = panel.isKeyWindow && NSApp.isActive
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        panel.delegate = nil; parent.removeChildWindow(panel); panel.orderOut(nil)
        if restoreParentFocus { parent.makeKey() }
        onDismiss()
    }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        observers.forEach(NotificationCenter.default.removeObserver)
    }
    func windowDidResignKey(_ notification: Notification) { close() }
    func controlTextDidChange(_ obj: Notification) { selectedIndex = 0; rebuild() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { close(); return true }
        if commandSelector == #selector(NSResponder.moveDown(_:)) { select(selectedIndex+1); return true }
        if commandSelector == #selector(NSResponder.moveUp(_:)) { select(selectedIndex-1); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { submit(); return true }
        return false
    }
    @objc private func toggleHelp() { helpVisible.toggle(); help.isHidden = !helpVisible; position() }
    @objc private func submit() {
        guard items.indices.contains(selectedIndex) else { return }
        let action = items[selectedIndex].perform; close(); action()
    }
    private func select(_ index: Int) {
        guard !items.isEmpty else { return }; selectedIndex = max(0,min(items.count-1,index))
        for (i,row) in rows.enumerated() { row.selected = i == selectedIndex }
    }
    private func rebuild() {
        rows.forEach { $0.removeFromSuperview() }; rows.removeAll()
        items = Array(suggestions(input.stringValue).prefix(5)); selectedIndex = min(selectedIndex,max(0,items.count-1))
        for (index,item) in items.enumerated() {
            let row = CommandRow(item, compact: !isCentered); row.selected = index == selectedIndex
            row.choose = { [weak self] in self?.selectedIndex = index; self?.submit() }
            row.hover = { [weak self] in self?.select(index) }
            surface.addSubview(row); rows.append(row)
        }
        position()
    }
    private func position() {
        guard !closed, let parentView = parent.contentView else { return }
        let anchor = isCentered ? nil : addressAnchor.flatMap { $0.isHiddenOrHasHiddenAncestor ? nil : parentView.convert($0.bounds,from:$0) }
        let preferredWidth = anchor.map { min(700,max(340,$0.width)) } ?? (isCentered ? 765 : 420)
        let width = min(preferredWidth,max(260,parentView.bounds.width-24))
        let header: CGFloat = isCentered ? 70 : 51
        let height = header+CGFloat(max(1,rows.count))*50+10+(helpVisible ? 42 : 0)
        let localX: CGFloat = isCentered ? (parentView.bounds.width-width)/2 : min(anchor?.minX ?? 12,parentView.bounds.width-width-8)
        let top: CGFloat = isCentered ? max(12,(parentView.bounds.height-height)/2) : anchor?.minY ?? 9
        let point = parentView.convert(NSPoint(x:localX,y:top),to:nil)
        let screen = parent.convertPoint(toScreen:point)
        panel.setFrame(NSRect(x:screen.x,y:screen.y-height,width:width,height:height),display:true)
        let inputY: CGFloat = isCentered ? 19 : 13
        leading.frame = NSRect(x:24,y:inputY+5,width:16,height:16)
        inputViewport.frame = NSRect(x:51,y:inputY,width:width-104,height:isCentered ? 32 : 24)
        input.frame = inputViewport.bounds
        inputViewport.overflows = (input.stringValue as NSString).size(withAttributes: [.font: input.font!]).width > input.bounds.width-4
        inputViewport.layoutSubtreeIfNeeded()
        info.frame = NSRect(x:width-46,y:inputY+1,width:24,height:24)
        separator.frame = NSRect(x:11,y:63,width:width-22,height:0.5)
        for (i,row) in rows.enumerated() { row.frame = NSRect(x:10,y:header+CGFloat(i)*50,width:width-20,height:46) }
        help.frame = NSRect(x:22,y:height-43,width:width-44,height:34)
        surface.needsDisplay = true
    }
}
