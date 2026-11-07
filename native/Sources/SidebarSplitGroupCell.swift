// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

final class SplitTabChip: NSView, NSDraggingSource {
    private let developerOutline = DeveloperTabOutline()
    var developerMode = false { didSet { needsLayout = true } }
    let id:String
    let icon = NSImageView()
    let label = NSTextField(labelWithString:"")
    let soundButton = TabSoundButton()
    let archive = TabCloseButton("", symbol:"xmark", action:{})
    var trailingInset: CGFloat = 0 { didSet { if trailingInset != oldValue { needsLayout = true } } }
    var focused = false
    var select:(() -> Void)?
    var rename:(() -> Void)?
    var context:(() -> NSMenu)?
    var dragChanged:((Bool) -> Void)?
    var dragWriter: (() -> NSPasteboardItem?)?
    override var mouseDownCanMoveWindow:Bool { false }
    init(id:String,title:String,image:NSImage?) {
        self.id = id; super.init(frame:.zero); wantsLayer = true; layer?.cornerRadius = 9
        icon.image = image; icon.imageScaling = .scaleProportionallyUpOrDown
        label.stringValue = title; label.font = .systemFont(ofSize:14,weight:.medium); label.lineBreakMode = .byTruncatingTail
        addSubview(icon); addSubview(label); label.allowsExpansionToolTips = false; setAccessibilityLabel(title); setAccessibilityRole(.button)
        addSubview(soundButton); addSubview(archive); archive.isHidden = true
        layer?.addSublayer(developerOutline)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        developerOutline.update(in:bounds,enabled:developerMode,radius:8)
        let right = bounds.width - trailingInset
        let compact = right < 49
        let hasSound = soundButton.titleInset > 0
        let iconSize = min(16,max(0,right-2))
        let x = compact ? max(0,(right-iconSize)/2) : 7
        icon.frame = NSRect(x:x,y:bounds.midY-iconSize/2,width:iconSize,height:iconSize)
        icon.isHidden = compact && hasSound
        soundButton.frame = NSRect(x:compact ? max(0,(right-22)/2) : 25,y:bounds.midY-12,width:min(22,max(0,right)),height:24)
        let labelX = 30 + soundButton.titleInset
        label.isHidden = compact || right-labelX < 8
        label.frame = NSRect(x:labelX,y:bounds.midY-9.5,width:max(0,right-labelX-3),height:19)
        archive.frame = NSRect(x:bounds.maxX-23,y:bounds.midY-11,width:22,height:22)
    }
    override func hitTest(_ point:NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === archive || hit === soundButton ? hit : self
    }
    override func menu(for event:NSEvent) -> NSMenu? { context?() }
    override func mouseDown(with event:NSEvent) {
        guard let window else { return }
        let start = event.locationInWindow
        layer?.opacity = 0.72
        while let next = window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]) {
            if next.type == .leftMouseUp {
                layer?.opacity = 1
                if focused, let rename, !label.isHidden && label.frame.contains(convert(start,from:nil)) { rename() }
                else { select?() }
                return
            }
            if hypot(next.locationInWindow.x-start.x,next.locationInWindow.y-start.y) > 4 {
                layer?.opacity = 1
                guard let pasteboard = dragWriter?() else { return }
                let item = NSDraggingItem(pasteboardWriter:pasteboard)
                guard let group = superview as? SplitGroupCell, let image = group.dragImage() else { return }
                item.setDraggingFrame(convert(group.bounds,from:group),contents:image)
                dragChanged?(true); beginDraggingSession(with:[item],event:next,source:self); return
            }
        }
        layer?.opacity = 1
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        SidebarTabDrag.operation(in: context, pasteboard: session.draggingPasteboard)
    }
    func draggingSession(_ session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation) { dragChanged?(false) }
}
final class SplitGroupCell: NSTableCellView {
    let chips:[SplitTabChip]
    let archive = TabCloseButton("", symbol:"xmark", action:{})
    private let dividers:[CALayer]
    private var focusedID:String?
    private var hovered = false
    private var tracking:NSTrackingArea?
    var acceptsPointerAt:((NSPoint) -> Bool)? {
        didSet {
            archive.acceptsPointerAt = acceptsPointerAt
            chips.forEach { $0.archive.acceptsPointerAt = acceptsPointerAt }
        }
    }
    private let groupTitle = NSTextField(labelWithString:"")
    private let groupIcon = NSImageView()
    private var titled = false
    init(chips:[SplitTabChip], ink:NSColor, title:String?, icon:String?, focusedID:String?) {
        self.chips = chips
        self.focusedID = focusedID
        dividers = chips.dropFirst().map { _ in CALayer() }
        super.init(frame:.zero)
        wantsLayer = true; layer?.cornerRadius = 12; layer?.cornerCurve = .continuous
        for chip in chips {
            chip.label.textColor = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? ink : ink.withAlphaComponent(0.88)
            chip.archive.contentTintColor = ink
            chip.layer?.cornerCurve = .continuous
            addSubview(chip)
        }
        for line in dividers {
            line.backgroundColor = ink.withAlphaComponent(0.18).cgColor
            line.actions = ["position":NSNull(),"bounds":NSNull(),"hidden":NSNull()]
            layer?.addSublayer(line)
        }
        archive.contentTintColor = ink
        addSubview(archive)
        titled = title != nil || icon != nil
        groupTitle.stringValue = title ?? ""; groupTitle.font = .systemFont(ofSize:11,weight:.semibold)
        groupTitle.textColor = ink; groupTitle.lineBreakMode = .byTruncatingTail
        groupTitle.isHidden = !titled; addSubview(groupTitle)
        if let icon {
            groupIcon.image = NSImage(size:NSSize(width:16,height:16),flipped:false) { rect in SpaceIcon.draw(icon,in:rect,color:ink,size:14); return true }
        }
        groupIcon.isHidden = icon == nil; addSubview(groupIcon)
        if let title {
            toolTip = title
            for chip in chips {
                chip.soundButton.hoverChanged = { [weak self] inside in self?.toolTip = inside ? nil : title }
            }
        }
        updateAppearance()
    }
    required init?(coder:NSCoder) { fatalError() }
    func dragImage() -> NSImage? {
        layoutSubtreeIfNeeded()
        guard !bounds.isEmpty, let bitmap = bitmapImageRepForCachingDisplay(in:bounds) else { return nil }
        cacheDisplay(in:bounds,to:bitmap)
        let image = NSImage(size:bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
    func setFocus(_ id:String?) {
        guard focusedID != id else { return }
        focusedID = id
        updateAppearance()
    }
    private func updateAppearance() {
        let active = chips.contains { $0.id == focusedID }
        layer?.backgroundColor = NSColor.white.withAlphaComponent(active ? 0.21 : hovered ? 0.11 : 0).cgColor
        archive.isHidden = active || !hovered
        for (index, chip) in chips.enumerated() {
            chip.focused = chip.id == focusedID
            chip.layer?.backgroundColor = NSColor.white.withAlphaComponent(active ? 0.08 : 0).cgColor
            chip.archive.isHidden = !active || !hovered
            let reserve = !chip.archive.isHidden || (!archive.isHidden && index == chips.count-1)
            chip.trailingInset = reserve ? 23 : 0
        }
        dividers.forEach { $0.isHidden = active }
        needsLayout = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self)
        addTrackingArea(tracking!)
        updateHover(at:window?.mouseLocationOutsideOfEventStream)
    }
    override func mouseEntered(with event:NSEvent) { updateHover(at:window?.mouseLocationOutsideOfEventStream) }
    override func mouseExited(with event:NSEvent) { updateHover(at:window?.mouseLocationOutsideOfEventStream) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateHover(at:window?.mouseLocationOutsideOfEventStream)
    }
    func updateHover(at point:NSPoint?) {
        let inside = point.map { window != nil && !isHiddenOrHasHiddenAncestor &&
            bounds.intersection(visibleRect).contains(convert($0,from:nil)) && acceptsPointerAt?($0) != false
        } ?? false
        if hovered != inside { hovered = inside; updateAppearance() }
        archive.updateHover(at:inside ? point : nil)
        for chip in chips {
            chip.archive.updateHover(at:inside ? point : nil)
            if !inside { chip.soundButton.setHovered(false) }
        }
    }
    override func layout() {
        super.layout()
        let width = max(1,(bounds.width-8-CGFloat(chips.count-1)*4)/CGFloat(max(1,chips.count)))
        let height = max(1,bounds.height-(titled ? 32 : 8))
        for (i,chip) in chips.enumerated() {
            chip.frame = NSRect(x:4+CGFloat(i)*(width+4),y:4,width:width,height:height)
            if i > 0 {
                let scale = window?.backingScaleFactor ?? 2
                dividers[i-1].frame = NSRect(x:round((chip.frame.minX-2)*scale)/scale,y:chip.frame.midY-7.5,width:1/scale,height:15)
            }
        }
        archive.frame = NSRect(x:bounds.width-27,y:4+(height-22)/2,width:22,height:22)
        groupIcon.frame = NSRect(x:8,y:bounds.height-23,width:16,height:16)
        groupTitle.frame = NSRect(x:groupIcon.isHidden ? 8 : 30,y:bounds.height-23,width:max(0,bounds.width-40),height:17)
    }
}
