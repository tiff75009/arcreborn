import AppKit
import Quartz
import QuickLookThumbnailing
import QuartzCore

private class LibraryCanvas: NSView { override var isFlipped: Bool { true } }
private class LibrarySearchField: NSTextField {
    var focusChanged: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged?(true) }
        return accepted
    }
    override func mouseDown(with event:NSEvent) {
        super.mouseDown(with:event)
        focusChanged?(currentEditor() != nil)
    }
}
private final class LibrarySearchBackground: LibraryCanvas {
    var focus: (() -> Void)?
    override func mouseDown(with event: NSEvent) { focus?() }
}
private class LibraryButton: NSButton {
    var invoke: (() -> Void)?
    var symbol: String?
    var vertical = false
    var spaceIconValue: String?
    var gradientFill = false
    var centered = false
    var selected = false { didSet { updateFill() } }
    var filled = false { didSet { updateFill() } }
    private let iconLayer = CALayer()
    private var mediaArtwork: LibraryMediaIcon?
    private var downloadArtwork: LibraryDownloadIcon?
    private var spacesArtwork: LibrarySpacesIcon?
    private var archiveArtwork: LibraryArchiveIcon?
    var iconAccent = NSColor.systemBlue { didSet { updateIconArtwork() } }
    private var hovered = false
    private var tracking: NSTrackingArea?
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        super.init(frame:.zero); self.title = title; self.symbol = symbol; invoke = action
        isBordered = false; target = self; self.action = #selector(activate); focusRingType = .none
        wantsLayer = true; layer?.cornerRadius = 12; font = .systemFont(ofSize:14,weight:.semibold)
        iconLayer.contentsGravity = .resizeAspect; layer?.addSublayer(iconLayer)
        if symbol == "photo.on.rectangle.angled" {
            let artwork = LibraryMediaIcon(); mediaArtwork = artwork; iconLayer.addSublayer(artwork)
        } else if symbol == "arrow.down.circle" {
            let artwork = LibraryDownloadIcon(); downloadArtwork = artwork; iconLayer.addSublayer(artwork)
        } else if symbol == "rectangle.on.rectangle" {
            let artwork = LibrarySpacesIcon(); spacesArtwork = artwork; iconLayer.addSublayer(artwork)
        } else if symbol == "archivebox" {
            let artwork = LibraryArchiveIcon(); archiveArtwork = artwork; iconLayer.addSublayer(artwork)
        }
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func activate() { animateIcon(); invoke?() }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        iconLayer.bounds = CGRect(x:0,y:0,width:26,height:26)
        iconLayer.position = CGPoint(x:bounds.midX,y:31)
        iconLayer.contentsScale = window?.backingScaleFactor ?? 2
        mediaArtwork?.frame = iconLayer.bounds; downloadArtwork?.frame = iconLayer.bounds
        spacesArtwork?.frame = iconLayer.bounds; archiveArtwork?.frame = iconLayer.bounds
        CATransaction.commit()
    }
    private func animateIcon() {
        guard vertical, isEnabled, mediaArtwork == nil, downloadArtwork == nil, spacesArtwork == nil, archiveArtwork == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let motion = CAKeyframeAnimation(keyPath:"transform.translation.y")
        motion.values = [0,-3,2,-0.5,0]
        motion.keyTimes = [0,0.28,0.60,0.82,1]
        motion.timingFunctions = Array(repeating:CAMediaTimingFunction(name:.easeInEaseOut),count:4)
        let scale = CAKeyframeAnimation(keyPath:"transform.scale"); scale.values = [1,1.13,0.98,1]; scale.keyTimes = [0,0.3,0.7,1]
        let group = CAAnimationGroup(); group.animations = [motion,scale]; group.duration = 0.38
        iconLayer.add(group,forKey:"sectionActivation")
    }
    private func updateIconArtwork() {
        mediaArtwork?.setSelected(selected,accent:iconAccent)
        let ink = NSColor.white.withAlphaComponent(isEnabled ? (selected || hovered ? 0.98 : 0.72) : 0.3)
        downloadArtwork?.setSelected(selected,accent:iconAccent,ink:ink)
        spacesArtwork?.setSelected(selected,accent:iconAccent,ink:ink)
        archiveArtwork?.setSelected(selected,accent:iconAccent,ink:ink)
        needsDisplay = true
    }
    private func updateFill() {
        updateIconArtwork()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
            context.allowsImplicitAnimation = true
            layer?.backgroundColor = NSColor.white.withAlphaComponent(selected ? 0.12 : hovered && isEnabled ? 0.09 : filled ? 0.055 : 0).cgColor
        }; needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        if gradientFill {
            NSGradient(starting:NSColor(srgbRed:0.86,green:0.53,blue:0.69,alpha:1),ending:NSColor(srgbRed:0.26,green:0.36,blue:0.97,alpha:1))?.draw(in:NSBezierPath(roundedRect:bounds,xRadius:7,yRadius:7),angle:0)
        }
        let ink = NSColor.white.withAlphaComponent(gradientFill ? 1 : isEnabled ? (selected || hovered ? 0.98 : 0.72) : 0.3)
        if let spaceIconValue { SpaceIcon.draw(spaceIconValue,in:NSRect(x:bounds.midX-9,y:bounds.midY-9,width:18,height:18),color:ink,size:18); return }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = vertical || centered ? .center : .left; paragraph.lineBreakMode = .byTruncatingTail
        if vertical, (mediaArtwork != nil && selected) || downloadArtwork != nil || spacesArtwork != nil || archiveArtwork != nil {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            iconLayer.contents = nil
            CATransaction.commit()
        } else if let symbol, let image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:vertical ? 23 : 17,weight:.regular))?.withSymbolConfiguration(.init(paletteColors:[ink])) {
            let size: CGFloat = vertical ? 26 : 19
            let scale = min(size/max(1,image.size.width),size/max(1,image.size.height))
            let fitted = NSSize(width:image.size.width*scale,height:image.size.height*scale)
            let box = NSRect(x:vertical || title.isEmpty ? (bounds.width-size)/2 : 10,y:vertical ? 18 : (bounds.height-size)/2,width:size,height:size)
            if vertical {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                let pixels = size*(window?.backingScaleFactor ?? 2)
                let raster = NSImage(size:NSSize(width:pixels,height:pixels),flipped:false) { rect in
                    let ratio = min(rect.width/image.size.width,rect.height/image.size.height)
                    let fit = NSSize(width:image.size.width*ratio,height:image.size.height*ratio)
                    image.draw(in:NSRect(x:rect.midX-fit.width/2,y:rect.midY-fit.height/2,width:fit.width,height:fit.height))
                    return true
                }
                iconLayer.contents = raster.cgImage(forProposedRect:nil,context:nil,hints:nil)
                CATransaction.commit()
            } else {
                image.draw(in:NSRect(x:box.midX-fitted.width/2,y:box.midY-fitted.height/2,width:fitted.width,height:fitted.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            }
        }
        if title.isEmpty { return }
        if centered && symbol == nil {
            let attributes:[NSAttributedString.Key:Any] = [.font:font ?? NSFont.systemFont(ofSize:14),.foregroundColor:ink]
            let size = (title as NSString).size(withAttributes:attributes)
            (title as NSString).draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2),withAttributes:attributes)
            return
        }
        let available = bounds.width-(vertical ? 8 : symbol == nil ? 24 : 44)
        let original = font ?? .systemFont(ofSize:14)
        let measured = (title as NSString).size(withAttributes:[.font:original]).width
        let fitted = NSFont(descriptor:original.fontDescriptor,size:max(9,original.pointSize*min(1,available/max(1,measured)))) ?? original
        let attributes: [NSAttributedString.Key:Any] = [.font:fitted,.foregroundColor:ink,.paragraphStyle:paragraph]
        let text = title as NSString
        text.draw(in:NSRect(x:vertical ? 2 : symbol == nil ? 12 : 37,y:vertical ? 49 : (bounds.height-18)/2,width:bounds.width-(vertical ? 4 : symbol == nil ? 24 : 44),height:vertical ? 30 : 20),withAttributes:attributes)
    }
    override var isFlipped: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self); addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; updateFill() }
    override func mouseExited(with event: NSEvent) { hovered = false; updateFill() }
}

/// The native dragging session keeps the pointer attached to the card while the
/// board previews its new order. The session model is changed only on a valid drop.
private let librarySpaceType = NSPasteboard.PasteboardType("local.browser.library-space")
private final class LibrarySpaceDragHandle: LibraryButton, NSDraggingSource {
    var spaceID = ""
    weak var card: NSView?
    var began: ((String) -> Void)?
    var ended: (() -> Void)?
    private var press: NSEvent?
    private var dragging = false
    override func resetCursorRects() { addCursorRect(bounds,cursor:.openHand) }
    override func mouseDown(with event:NSEvent) { press = event; dragging = false; window?.makeFirstResponder(self) }
    override func mouseDragged(with event:NSEvent) {
        guard !dragging, let press, let card,
              hypot(event.locationInWindow.x-press.locationInWindow.x,event.locationInWindow.y-press.locationInWindow.y) > 4,
              let bitmap = card.bitmapImageRepForCachingDisplay(in:card.bounds) else { return }
        card.cacheDisplay(in:card.bounds,to:bitmap)
        let image = NSImage(size:card.bounds.size); image.addRepresentation(bitmap)
        let item = NSPasteboardItem(); item.setString(spaceID,forType:librarySpaceType)
        let dragged = NSDraggingItem(pasteboardWriter:item)
        dragged.setDraggingFrame(convert(card.bounds,from:card),contents:image)
        dragging = true; began?(spaceID)
        let session = beginDraggingSession(with:[dragged],event:event,source:self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
    override func mouseUp(with event:NSEvent) { if !dragging { performClick(nil) }; press = nil }
    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
    func draggingSession(_ session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation) { dragging = false; press = nil; ended?() }
}
private final class LibrarySpaceBoard: LibraryCanvas {
    var preview: ((String,NSPoint) -> Bool)?
    var drop: ((String) -> Bool)?
    var leave: (() -> Void)?
    override init(frame:NSRect) { super.init(frame:frame); registerForDraggedTypes([librarySpaceType]) }
    required init?(coder:NSCoder) { fatalError() }
    override func draggingEntered(_ sender:NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender:NSDraggingInfo) -> NSDragOperation {
        guard let id = sender.draggingPasteboard.string(forType:librarySpaceType) else { return [] }
        if let scroll = enclosingScrollView {
            let local = scroll.contentView.convert(sender.draggingLocation,from:nil)
            let visible = scroll.contentView.bounds
            let delta:CGFloat = local.x < visible.minX+35 ? -14 : local.x > visible.maxX-35 ? 14 : 0
            if delta != 0 {
                let x = min(max(0,visible.minX+delta),max(0,bounds.width-visible.width))
                scroll.contentView.scroll(to:NSPoint(x:x,y:0)); scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        return preview?(id,convert(sender.draggingLocation,from:nil)) == true ? .move : []
    }
    override func draggingExited(_ sender:NSDraggingInfo?) { leave?() }
    override func prepareForDragOperation(_ sender:NSDraggingInfo) -> Bool { sender.draggingPasteboard.string(forType:librarySpaceType) != nil }
    override func performDragOperation(_ sender:NSDraggingInfo) -> Bool {
        guard let id = sender.draggingPasteboard.string(forType:librarySpaceType) else { return false }
        return drop?(id) ?? false
    }
}
private final class LibrarySpaceName: LibrarySearchField, NSTextFieldDelegate {
    var savedName = ""
    var commit: ((String) -> Void)?
    private var cancelled = false
    private var tracking: NSTrackingArea?
    override init(frame:NSRect) {
        super.init(frame:frame); isBordered = false; isBezeled = false; drawsBackground = false
        focusRingType = .none; font = .systemFont(ofSize:14,weight:.bold); textColor = .white.withAlphaComponent(0.9)
        cell?.isScrollable = true; delegate = self; wantsLayer = true; layer?.cornerRadius = 6
        focusChanged = { [weak self] focused in self?.setSurface(focused:focused) }
    }
    required init?(coder:NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.inVisibleRect,.activeAlways,.mouseEnteredAndExited],owner:self); addTrackingArea(tracking!)
    }
    private func setSurface(focused:Bool,hovered:Bool = false) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
            context.allowsImplicitAnimation = true
            superview?.layer?.backgroundColor = NSColor.white.withAlphaComponent(focused ? 0.10 : hovered ? 0.055 : 0).cgColor
            superview?.layer?.borderWidth = focused ? 1 : 0
            superview?.layer?.borderColor = NSColor.white.withAlphaComponent(0.23).cgColor
        }
    }
    override func mouseEntered(with event:NSEvent) { if currentEditor() == nil { setSurface(focused:false,hovered:true) } }
    override func mouseExited(with event:NSEvent) { if currentEditor() == nil { setSurface(focused:false) } }
    func control(_ control:NSControl,textView:NSTextView,doCommandBy command:Selector) -> Bool {
        if command == #selector(NSResponder.cancelOperation(_:)) { cancelled = true; window?.makeFirstResponder(superview); return true }
        if command == #selector(NSResponder.insertNewline(_:)) { window?.makeFirstResponder(superview); return true }
        return false
    }
    func controlTextDidBeginEditing(_ obj:Notification) { cancelled = false; (currentEditor() as? NSTextView)?.insertionPointColor = .white }
    func controlTextDidEndEditing(_ obj:Notification) {
        let value = String(stringValue.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80))
        let valid = !cancelled && !value.isEmpty && value.rangeOfCharacter(from:.controlCharacters) == nil
        stringValue = valid ? value : savedName; setSurface(focused:false)
        if valid && value != savedName {
            savedName = value
            let action = commit; DispatchQueue.main.async { action?(value) }
        }
        cancelled = false
    }
}
private final class LibrarySpaceCard: ThemeBackdropView {
    let spaceID:String
    let icon:LibraryButton, name = LibrarySpaceName(frame:.zero), paint:LibraryButton
    let bodyScroll = NSScrollView(), nameSurface = LibrarySearchBackground()
    let handle:LibrarySpaceDragHandle, more:LibraryButton
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    init(id:String) {
        spaceID = id; icon = LibraryButton("") {}; paint = LibraryButton("",symbol:"paintbrush.pointed.fill") {}
        handle = LibrarySpaceDragHandle("",symbol:"arrow.up.and.down.and.arrow.left.and.right") {}; more = LibraryButton("",symbol:"ellipsis") {}
        super.init(frame:.zero); wantsLayer = true; layer?.cornerRadius = 14; layer?.masksToBounds = true
        icon.centered = true; icon.font = .systemFont(ofSize:18)
        nameSurface.wantsLayer = true; nameSurface.layer?.cornerRadius = 8
        nameSurface.addSubview(name); nameSurface.focus = { [weak self] in guard let self else { return }; self.window?.makeFirstResponder(self.name) }
        for child in [icon,nameSurface,paint,bodyScroll,handle,more] { addSubview(child) }
        layer?.borderWidth = 0.5; layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        for button in [icon,paint,handle,more] { button.layer?.cornerRadius = 8 }
        handle.spaceID = id; handle.card = self
        bodyScroll.drawsBackground = false; bodyScroll.hasVerticalScroller = true; bodyScroll.autohidesScrollers = true; bodyScroll.scrollerStyle = .overlay
    }
    required init?(coder:NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        icon.frame = NSRect(x:12,y:12,width:30,height:30)
        nameSurface.frame = NSRect(x:44,y:12,width:bounds.width-88,height:32)
        name.frame = NSRect(x:8,y:6,width:nameSurface.bounds.width-16,height:21)
        paint.frame = NSRect(x:bounds.width-42,y:12,width:30,height:30)
        bodyScroll.frame = NSRect(x:10,y:57,width:bounds.width-20,height:max(20,bounds.height-107))
        handle.frame = NSRect(x:12,y:bounds.height-42,width:30,height:30)
        more.frame = NSRect(x:bounds.width-42,y:bounds.height-42,width:30,height:30)
    }
}

private final class LibraryCollection: NSCollectionView {
    var activate: ((IndexPath) -> Void)?
    var reveal: ((IndexPath) -> Void)?
    var menuIndex: IndexPath?
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with:event)
        if event.clickCount == 2, let index = indexPathForItem(at:convert(event.locationInWindow,from:nil)) { activate?(index) }
    }
    override func keyDown(with event:NSEvent) {
        if (event.keyCode == 49 || event.keyCode == 36), let index = selectionIndexPaths.first { activate?(index); return }
        super.keyDown(with:event)
    }
    override func menu(for event:NSEvent) -> NSMenu? {
        guard let index = indexPathForItem(at:convert(event.locationInWindow,from:nil)) else { return nil }
        menuIndex = index; selectionIndexPaths = [index]
        let menu = NSMenu()
        for (title,selector) in [("open",#selector(openSelected)),("revealFinder",#selector(revealSelected))] {
            let item = NSMenuItem(title:L10n.text(title,language:LibraryView.currentLanguage),action:selector,keyEquivalent:""); item.target = self; menu.addItem(item)
        }; return menu
    }
    @objc private func openSelected() { if let menuIndex { activate?(menuIndex) } }
    @objc private func revealSelected() { if let menuIndex { reveal?(menuIndex) } }
}
private final class LibrarySkeleton: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.white.withAlphaComponent(0.04).setFill()
        for i in 0..<Int(bounds.height/60)+1 { NSBezierPath(roundedRect:NSRect(x:7,y:25+CGFloat(i)*60,width:bounds.width-14,height:48),xRadius:13,yRadius:13).fill() }
    }
}
private final class LibraryTileCanvas: LibraryCanvas {
    var hoverChanged: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event:NSEvent) { hoverChanged?(true) }
    override func mouseExited(with event:NSEvent) { hoverChanged?(false) }
    var activate: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { activate?(); return activate != nil }
}
private final class LibraryTile: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("LibraryTile")
    let picture = NSImageView(), name = NSTextField(labelWithString:""), detail = NSTextField(labelWithString:"")
    let bar = NSView()
    let transfer = DownloadCard(frame:.zero)
    var thumbnail: QLThumbnailGenerator.Request?
    var key = ""
    var mediaMode = true
    private var hovered = false
    func updateAppearance(animated:Bool = true) {
        guard isViewLoaded, let layer = view.layer else { return }
        let scale:CGFloat = mediaMode && hovered ? 1.035 : 1
        let center = CGPoint(x:layer.bounds.width*(0.5-layer.anchorPoint.x),y:layer.bounds.height*(0.5-layer.anchorPoint.y))
        var transform = CATransform3DMakeTranslation(center.x,center.y,0)
        transform = CATransform3DScale(transform,scale,scale,1)
        transform = CATransform3DTranslate(transform,-center.x,-center.y,0)
        let old = layer.presentation()?.transform ?? layer.transform
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = transform
        layer.backgroundColor = NSColor.white.withAlphaComponent(isSelected ? 0.15 : hovered && mediaMode ? 0.10 : 0.045).cgColor
        layer.borderWidth = isSelected ? 1 : 0
        layer.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        CATransaction.commit()
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath:"transform"); animation.fromValue = NSValue(caTransform3D:old); animation.toValue = NSValue(caTransform3D:transform)
            animation.duration = hovered ? 0.18 : 0.24; animation.timingFunction = CAMediaTimingFunction(controlPoints:0.2,0.8,0.2,1)
            layer.add(animation,forKey:"mediaHover")
        } else { layer.removeAnimation(forKey:"mediaHover") }
    }
    var open: (() -> Void)? { didSet { (view as? LibraryTileCanvas)?.activate = open } }
    var reveal: (() -> Void)?
    override func loadView() {
        view = LibraryTileCanvas(); view.setAccessibilityElement(true); view.setAccessibilityRole(.button); view.wantsLayer = true; view.layer?.cornerRadius = 13
        (view as? LibraryTileCanvas)?.hoverChanged = { [weak self] inside in
            guard let self, self.hovered != inside else { return }; self.hovered = inside; self.updateAppearance()
        }
        picture.imageScaling = .scaleProportionallyUpOrDown; picture.wantsLayer = true; picture.layer?.cornerRadius = 2
        name.font = .systemFont(ofSize:13,weight:.semibold); name.textColor = .white.withAlphaComponent(0.92); name.lineBreakMode = .byTruncatingMiddle
        detail.font = .systemFont(ofSize:11); detail.textColor = .white.withAlphaComponent(0.55); detail.lineBreakMode = .byTruncatingTail
        bar.wantsLayer = true; bar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.7).cgColor; bar.layer?.cornerRadius = 1
        transfer.isHidden = true; view.addSubview(transfer)
        for child in [picture,name,detail,bar] { view.addSubview(child) }
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        transfer.frame = view.bounds; transfer.layout()
        if mediaMode {
            let area = view.bounds.insetBy(dx:10,dy:10)
            let size = picture.image?.size ?? NSSize(width:1,height:1)
            let scale = min(area.width/max(1,size.width),area.height/max(1,size.height))
            picture.frame = NSRect(x:area.midX-size.width*scale/2,y:area.midY-size.height*scale/2,width:size.width*scale,height:size.height*scale)
        } else {
            picture.frame = NSRect(x:10,y:14,width:30,height:30)
            name.frame = NSRect(x:49,y:12,width:max(10,view.bounds.width-61),height:19)
            detail.frame = NSRect(x:49,y:34,width:max(10,view.bounds.width-61),height:16)
        }
    }
    override var isSelected: Bool { didSet { updateAppearance() } }
    override func prepareForReuse() {
        super.prepareForReuse(); if let thumbnail { QLThumbnailGenerator.shared.cancel(thumbnail) }; thumbnail = nil
        hovered = false; updateAppearance(animated:false)
        transfer.isHidden = true; picture.image = nil; key = ""; open = nil; reveal = nil
    }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let openItem = NSMenuItem(title:L10n.text("open",language:LibraryView.currentLanguage),action:#selector(openFile),keyEquivalent:""); openItem.target = self; menu.addItem(openItem)
        let revealItem = NSMenuItem(title:L10n.text("revealFinder",language:LibraryView.currentLanguage),action:#selector(revealFile),keyEquivalent:""); revealItem.target = self; menu.addItem(revealItem)
        NSMenu.popUpContextMenu(menu,with:event,for:view)
    }
    @objc private func openFile() { open?() }
    @objc private func revealFile() { reveal?() }
    deinit { if let thumbnail { QLThumbnailGenerator.shared.cancel(thumbnail) } }
}

final class LibraryView: ThemeBackdropView, NSCollectionViewDataSource, NSCollectionViewDelegate, NSTextFieldDelegate, QLPreviewPanelDataSource {
    typealias Section = LibrarySection
    static var currentLanguage = "fr"
    var close: (() -> Void)?
    var expandedChanged: (() -> Void)?
    var selectSpace: ((String) -> Void)?
    var selectTab: ((String) -> Void)?
    var editTheme: ((String) -> Void)?
    var spaceMenu: ((String) -> NSMenu?)?
    var reorderSpace: ((String,Int) -> Void)?
    var moveSpace: ((String,Int) -> Void)?
    var renameSpace: ((String,String) -> Void)?
    var editIcon: ((String, NSView) -> Void)?
    var restoreTab: ((String) -> Void)?
    var folderToggle: ((String) -> Void)?
    private(set) var section: Section = .media
    var expanded: Bool { section == .spaces }
    func canScrollSpaceCards(at pointInWindow: NSPoint, delta: CGFloat) -> Bool {
        guard expanded, !filterVisible, cardsScroll.visibleRect.contains(cardsScroll.convert(pointInWindow,from:nil)) else { return false }
        let clip = cardsScroll.contentView.bounds
        return delta < 0 ? clip.maxX < cards.bounds.maxX-1 : delta > 0 && clip.minX > 1
    }
    private let store: LibraryStore
    private let archivedIcon: (NativeTab) -> NSImage?
    private var session: BrowserSession
    private let language: String
    private let rail = LibraryCanvas(), pane = LibraryCanvas(), searchBackground = LibrarySearchBackground()
    private let search = LibrarySearchField(), searchIcon = NSImageView(), scroll = NSScrollView(), collection = LibraryCollection()
    private var clearSearch: LibraryButton!
    private let skeleton = LibrarySkeleton()
    private let flow = NSCollectionViewFlowLayout()
    private let empty = LibraryCanvas(), emptyIcon = NSImageView(), emptyTitle = NSTextField(labelWithString:""), emptyDetail = NSTextField(wrappingLabelWithString:"")
    private let intro = LibraryCanvas(), introIcon = NSImageView(), introTitle = NSTextField(labelWithString:""), introText = NSTextField(wrappingLabelWithString:""), introPrivacy = NSTextField(wrappingLabelWithString:"")
    private let cardsScroll = NSScrollView(), cards = LibrarySpaceBoard(), filterPane = LibraryCanvas()
    private var nav: [LibraryButton] = [], back: LibraryButton!, settings: LibraryButton!, enable: LibraryButton!, dismissIntro: LibraryButton!, retry: LibraryButton!, filter: LibraryButton!
    private var items: [LibraryMedia] = [], records: [LibraryDownload] = [], archives: [NativeTab] = []
    private var profileFilter = Set<String>()
    private var spaceCards:[LibrarySpaceCard] = []
    private var draggingSpaceID:String?
    private var previewOrder:[String] = []
    private let spaceInsertion = CALayer()
    private var filterVisible = false
    private var introDismissed = false
    private var lastSignature = ""
    private var previewURLs: [URL] = []
    private var keyMonitor: Any?
    private let thumbnails = NSCache<NSString,NSImage>()
    private var searchTask: DispatchWorkItem?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private func t(_ key: String) -> String { L10n.text(key,language:language) }
    init(store: LibraryStore, session: BrowserSession, archivedIcon: @escaping (NativeTab) -> NSImage? = { _ in nil }) {
        self.store = store; self.session = session; language = session.language; Self.currentLanguage = session.language
        self.archivedIcon = archivedIcon
        section = store.lastSection
        super.init(frame:.zero); wantsLayer = true; layer?.masksToBounds = true
        thumbnails.countLimit = 120; thumbnails.totalCostLimit = 36*1024*1024
        for view in [rail,pane] { view.wantsLayer = true; addSubview(view) }
        rail.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.025).cgColor
        rail.layer?.borderWidth = 0.5; rail.layer?.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor
        let titles = ["media","downloads","easelsNotes","spaces","archivedTabs"]
        let symbols = ["photo.on.rectangle.angled","arrow.down.circle","scribble.variable","rectangle.on.rectangle","archivebox"]
        for (i,title) in titles.enumerated() {
            let button = LibraryButton(t(title),symbol:symbols[i]) { [weak self] in self?.switchSection(Section.allCases[i]) }
            button.vertical = true; button.font = .systemFont(ofSize:language == "fr" ? 11.5 : 12,weight:.bold); button.isEnabled = i != Section.notes.index
            if !button.isEnabled { button.toolTip = t("comingLater") }
            rail.addSubview(button); nav.append(button)
        }
        back = LibraryButton("",symbol:"arrow.left") { [weak self] in self?.close?() }; back.setAccessibilityLabel(t("back")); rail.addSubview(back)
        settings = LibraryButton("",symbol:"folder") { [weak self] in guard let self else { return }; NSWorkspace.shared.open(self.store.downloadsDirectory) }; settings.setAccessibilityLabel(t("openDownloads")); settings.toolTip = t("openDownloads"); rail.addSubview(settings)
        searchBackground.wantsLayer = true; searchBackground.layer?.cornerRadius = 13; searchBackground.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor; pane.addSubview(searchBackground)
        search.isBordered = false; search.drawsBackground = false; search.focusRingType = .none; search.font = .systemFont(ofSize:14,weight:.medium); search.textColor = .white; search.delegate = self; searchBackground.addSubview(search)
        search.focusChanged = { [weak self] in self?.updateSearchFocus($0) }
        search.isBezeled = false; search.cell?.isScrollable = true; search.cell?.wraps = false
        searchIcon.image = NSImage(systemSymbolName:"magnifyingglass",accessibilityDescription:nil)
        searchIcon.contentTintColor = .white.withAlphaComponent(0.50); searchIcon.imageScaling = .scaleProportionallyUpOrDown
        searchBackground.addSubview(searchIcon)
        searchBackground.focus = { [weak self] in guard let self else { return }; self.window?.makeFirstResponder(self.search) }
        clearSearch = LibraryButton("",symbol:"xmark.circle.fill") { [weak self] in
            guard let self else { return }; self.search.stringValue = ""; self.clearSearch.isHidden = true
            self.window?.makeFirstResponder(self.search); self.refresh()
        }
        clearSearch.setAccessibilityLabel(t("clear")); clearSearch.toolTip = t("clear"); clearSearch.isHidden = true
        searchBackground.addSubview(clearSearch)
        filter = LibraryButton(t("filter"),symbol:"line.3.horizontal.decrease.circle") { [weak self] in self?.showFilters() }; filter.filled = true; pane.addSubview(filter)
        flow.minimumInteritemSpacing = 10; flow.minimumLineSpacing = 9; flow.sectionInset = NSEdgeInsets(top:7,left:7,bottom:12,right:7)
        collection.collectionViewLayout = flow; collection.backgroundColors = [.clear]; collection.dataSource = self; collection.delegate = self; collection.isSelectable = true
        collection.register(LibraryTile.self,forItemWithIdentifier:LibraryTile.identifier)
        collection.setDraggingSourceOperationMask(.copy,forLocal:false)
        collection.activate = { [weak self] index in
            guard let self else { return }; self.collection.selectionIndexPaths = [index]
            if self.section == .archived, self.archives.indices.contains(index.item) { self.restoreTab?(self.archives[index.item].id) } else { self.previewSelection() }
        }
        collection.reveal = { [weak self] index in
            guard let self else { return }
            if self.section == .media, self.items.indices.contains(index.item) { NSWorkspace.shared.activateFileViewerSelecting([self.items[index.item].url]) }
            else if self.section == .downloads, self.records.indices.contains(index.item), !self.records[index.item].path.isEmpty { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:self.records[index.item].path)]) }
        }
        scroll.documentView = collection; scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay; pane.addSubview(scroll)
        for label in [emptyTitle,introTitle] { label.font = .systemFont(ofSize:16,weight:.bold); label.textColor = .white.withAlphaComponent(0.92); label.alignment = .center }
        for label in [emptyDetail,introText] { label.font = .systemFont(ofSize:13); label.textColor = .white.withAlphaComponent(0.68) }
        emptyDetail.alignment = .center
        pane.addSubview(skeleton)
        for child in [emptyIcon,emptyTitle,emptyDetail] { empty.addSubview(child) }; pane.addSubview(empty)
        retry = LibraryButton(t("retry"),symbol:"arrow.clockwise") { [weak self] in self?.store.refreshMedia() }; retry.filled = true; empty.addSubview(retry)
        intro.wantsLayer = true; intro.layer?.cornerRadius = 18; intro.layer?.backgroundColor = NSColor(srgbRed:0.075,green:0.07,blue:0.11,alpha:0.97).cgColor
        intro.layer?.borderWidth = 0.6; intro.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        intro.layer?.shadowColor = NSColor.systemPurple.cgColor; intro.layer?.shadowOpacity = 0.35; intro.layer?.shadowRadius = 20
        introIcon.image = NSImage(systemSymbolName:"photo.on.rectangle.angled",accessibilityDescription:nil); introIcon.contentTintColor = NSColor(srgbRed:0.6,green:0.48,blue:0.88,alpha:1)
        introTitle.stringValue = t("mediaIntroTitle"); introTitle.font = .systemFont(ofSize:14,weight:.bold)
        introText.stringValue = t("mediaIntroText")
        introPrivacy.stringValue = t("mediaPrivacy"); introPrivacy.font = .systemFont(ofSize:11); introPrivacy.textColor = .white.withAlphaComponent(0.42)
        enable = LibraryButton(t("showMedia")) { [weak self] in self?.store.enableMedia() }; enable.font = .systemFont(ofSize:14,weight:.semibold)
        enable.gradientFill = true; enable.centered = true
        introIcon.imageScaling = .scaleProportionallyUpOrDown; emptyIcon.imageScaling = .scaleProportionallyUpOrDown
        introTitle.maximumNumberOfLines = 0; introTitle.cell?.wraps = true; introTitle.cell?.isScrollable = false
        dismissIntro = LibraryButton("",symbol:"xmark") { [weak self] in self?.introDismissed = true; self?.refresh() }; dismissIntro.setAccessibilityLabel(t("close"))
        for child in [introIcon,introTitle,introText,introPrivacy,enable!,dismissIntro!] { intro.addSubview(child) }; pane.addSubview(intro)
        cards.wantsLayer = true; spaceInsertion.backgroundColor = NSColor.white.withAlphaComponent(0.8).cgColor; spaceInsertion.cornerRadius = 1.5; spaceInsertion.isHidden = true; cards.layer?.addSublayer(spaceInsertion)
        cards.preview = { [weak self] id,point in self?.previewSpaceMove(id,point:point) ?? false }
        cards.drop = { [weak self] id in self?.commitSpaceMove(id) ?? false }
        cards.leave = { [weak self] in self?.resetSpacePreview() }
        cardsScroll.documentView = cards; cardsScroll.drawsBackground = false; cardsScroll.hasHorizontalScroller = true; cardsScroll.hasVerticalScroller = false; cardsScroll.autohidesScrollers = true; cardsScroll.scrollerStyle = .overlay; pane.addSubview(cardsScroll)
        filterPane.wantsLayer = true; pane.addSubview(filterPane)
        updateTheme(); store.changed = { [weak self] in self?.refresh() }; refresh(); store.startObserving()
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(session: BrowserSession) { guard self.session != session else { return }; self.session = session; updateTheme(); if section == .spaces && draggingSpaceID == nil { rebuildCards() }; if section == .archived { refresh() } }
    private func updateTheme() {
        let space = session.spaces.first(where: { $0.id == session.activeSpaceID })
        theme = space?.theme ?? .solid(space?.color ?? "#777890")
        let accent = NSColor(browserHex:theme.points.first?.color ?? space?.color ?? "#777890") ?? .systemBlue
        nav.forEach { $0.iconAccent = accent }
        let mode = session.themeAppearance ?? .automatic
        dark = mode == .dark || (mode == .automatic && effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateTheme() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); updateTheme()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        guard window != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.keyCode == 53, let editor = self.window?.firstResponder as? NSTextView, self.spaceCards.contains(where: { $0.name.currentEditor() === editor }) { return event }
            if event.keyCode == 53 { if self.filterVisible { self.hideFilters() } else { self.close?() }; return nil }
            if event.keyCode == 49, self.window?.firstResponder === self.collection { self.previewSelection(); return nil }
            return event
        }
    }
    func switchSection(_ next: Section) {
        guard next != .notes, next != section else { return }
        searchTask?.cancel(); window?.makeFirstResponder(self); updateSearchFocus(false)
        let previous = section; section = next; search.stringValue = ""; filterVisible = false; lastSignature = ""
        store.rememberSection(next)
        if next == .spaces { rebuildCards() }; refresh(); expandedChanged?(); layoutSubtreeIfNeeded()
        let direction: CGFloat = next.index > previous.index ? 1 : -1
        pane.layer?.removeAnimation(forKey:"librarySection")
        let animation = CABasicAnimation(keyPath:"transform.translation.x"); animation.fromValue = direction*16; animation.toValue = 0; animation.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.20; animation.timingFunction = CAMediaTimingFunction(name:.easeOut); pane.layer?.add(animation,forKey:"librarySection")
        let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = 0.4; fade.toValue = 1; fade.duration = animation.duration; pane.layer?.add(fade,forKey:"libraryFade")
    }
    func controlTextDidBeginEditing(_ obj:Notification) { updateSearchFocus(true) }
    func controlTextDidEndEditing(_ obj:Notification) { updateSearchFocus(false) }
    private func updateSearchFocus(_ focused:Bool) {
        (search.currentEditor() as? NSTextView)?.insertionPointColor = .white
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
            context.allowsImplicitAnimation = true
            searchBackground.layer?.backgroundColor = NSColor.white.withAlphaComponent(focused ? 0.13 : 0.055).cgColor
            searchBackground.layer?.borderWidth = focused ? 1.5 : 0
            searchBackground.layer?.borderColor = NSColor.white.withAlphaComponent(0.48).cgColor
        }
        searchIcon.contentTintColor = .white.withAlphaComponent(focused ? 0.95 : 0.50)
    }
    func controlTextDidChange(_ obj: Notification) {
        clearSearch.isHidden = search.stringValue.isEmpty
        searchTask?.cancel(); let task = DispatchWorkItem { [weak self] in self?.refresh() }; searchTask = task
        DispatchQueue.main.asyncAfter(deadline:.now()+0.09,execute:task)
    }
    private func refresh() {
        for (i,button) in nav.enumerated() { button.selected = i == section.index }
        search.placeholderAttributedString = NSAttributedString(string:t(section == .media ? "searchMedia" : section == .downloads ? "searchDownloads" : "searchArchives"),attributes:[.foregroundColor:NSColor.white.withAlphaComponent(0.52),.font:NSFont.systemFont(ofSize:14,weight:.medium)])
        clearSearch.isHidden = search.stringValue.isEmpty
        search.setAccessibilityLabel(search.placeholderString)
        filter.isHidden = section != .downloads || filterVisible
        searchBackground.isHidden = section == .spaces || filterVisible
        cardsScroll.isHidden = section != .spaces; filterPane.isHidden = !filterVisible
        scroll.isHidden = section == .spaces || filterVisible
        intro.isHidden = section != .media || store.mediaEnabled || store.hasCaptures || introDismissed
        skeleton.isHidden = intro.isHidden
        let query = search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        items = LibraryMediaScanner.matching(store.media,query:query)
        records = store.matchingDownloads(query:query,profiles:profileFilter)
        archives = session.closedTabs.reversed().filter { query.isEmpty || $0.displayTitle.localizedStandardContains(query) || $0.url.localizedStandardContains(query) }
        let count = section == .media ? items.count : section == .downloads ? records.count : archives.count
        empty.isHidden = section == .spaces || filterVisible || count > 0 || !intro.isHidden
        let failed = section == .media && store.mediaError != nil
        emptyIcon.image = NSImage(systemSymbolName:section == .media ? "photo.on.rectangle.angled" : section == .downloads ? "arrow.down.circle" : "archivebox",accessibilityDescription:nil)
        emptyIcon.contentTintColor = .white.withAlphaComponent(0.3)
        emptyTitle.stringValue = t(failed ? "mediaAccess" : section == .media && store.loading ? "loadingMedia" : query.isEmpty ? "nothingHere" : "noResults")
        emptyDetail.stringValue = failed ? t("mediaAccessHelp") : section == .media ? t("mediaEmpty") : t("libraryEmpty")
        retry.isHidden = !failed && !(section == .media && !store.mediaEnabled)
        retry.title = t(failed ? "retry" : "showMedia"); retry.invoke = { [weak self] in guard let self else { return }; if self.store.mediaEnabled { self.store.refreshMedia() } else { self.store.enableMedia() } }
        let signature = "\(section)|\(query)|" + (section == .media ? items.map(\.cacheKey).joined(separator:";") : section == .downloads ? records.map(\.id).joined(separator:";") : archives.map(\.id).joined(separator:";"))
        if signature != lastSignature { lastSignature = signature; collection.reloadData() }
        else if section == .downloads {
            for item in collection.visibleItems() {
                if let tile = item as? LibraryTile, let index = collection.indexPath(for:item)?.item, records.indices.contains(index) { configureTransfer(tile,record:records[index]) }
            }
        }
        if section == .spaces && cards.subviews.isEmpty { rebuildCards() }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let railWidth: CGFloat = 110
        rail.frame = NSRect(x:0,y:0,width:railWidth,height:bounds.height); pane.frame = NSRect(x:railWidth,y:0,width:bounds.width-railWidth,height:bounds.height)
        let step = min(100,max(70,(bounds.height-160)/5)), start = max(65,(bounds.height-step*5)/2)
        for (i,button) in nav.enumerated() { button.frame = NSRect(x:6,y:start+CGFloat(i)*step,width:97,height:80) }
        back.frame = NSRect(x:5,y:bounds.height-43,width:36,height:32); settings.frame = NSRect(x:74,y:bounds.height-43,width:30,height:32)
        let w = pane.bounds.width
        searchBackground.frame = NSRect(x:8,y:7,width:w-16-(section == .downloads ? 90 : 0),height:36)
        searchIcon.frame = NSRect(x:13,y:9,width:18,height:18)
        search.frame = NSRect(x:41,y:8,width:max(20,searchBackground.bounds.width-73),height:21)
        clearSearch.frame = NSRect(x:searchBackground.bounds.width-31,y:4,width:28,height:28)
        filter.frame = NSRect(x:w-93,y:7,width:85,height:36)
        scroll.frame = NSRect(x:5,y:51,width:w-10,height:max(20,bounds.height-59))
        skeleton.frame = scroll.frame
        let cellWidth = section == .media ? floor((scroll.contentSize.width-24)/2) : scroll.contentSize.width-14
        let size = NSSize(width:max(40,cellWidth),height:section == .media ? max(40,cellWidth) : section == .downloads ? 98 : 66)
        if flow.itemSize != size { flow.itemSize = size; flow.invalidateLayout() }
        empty.frame = NSRect(x:12,y:max(90,(bounds.height-180)/2),width:w-24,height:200)
        emptyIcon.frame = NSRect(x:(empty.bounds.width-50)/2,y:0,width:50,height:50)
        emptyTitle.frame = NSRect(x:0,y:66,width:empty.bounds.width,height:24)
        emptyDetail.frame = NSRect(x:5,y:100,width:empty.bounds.width-10,height:65)
        retry.frame = NSRect(x:(empty.bounds.width-160)/2,y:167,width:160,height:32)
        let introWidth = min(270,w-20), textWidth = introWidth-28
        func labelHeight(_ label:NSTextField, width:CGFloat) -> CGFloat {
            ceil(label.cell?.cellSize(forBounds:NSRect(x:0,y:0,width:width,height:1000)).height ?? 20)
        }
        let titleHeight = labelHeight(introTitle,width:textWidth)
        let textHeight = labelHeight(introText,width:textWidth)
        let privacyHeight = labelHeight(introPrivacy,width:textWidth-2)
        let textY = 80+titleHeight+10, buttonY = textY+textHeight+14
        let introHeight = buttonY+41+12+privacyHeight+16
        intro.frame = NSRect(x:(w-introWidth)/2,y:max(66,(bounds.height-introHeight)/2),width:introWidth,height:introHeight)
        introIcon.frame = NSRect(x:(intro.bounds.width-42)/2,y:32,width:42,height:37)
        dismissIntro.frame = NSRect(x:intro.bounds.width-37,y:12,width:28,height:27)
        introTitle.frame = NSRect(x:14,y:80,width:textWidth,height:titleHeight)
        introText.frame = NSRect(x:14,y:textY,width:textWidth,height:textHeight)
        enable.frame = NSRect(x:14,y:buttonY,width:textWidth,height:41)
        introPrivacy.frame = NSRect(x:15,y:buttonY+53,width:textWidth-2,height:privacyHeight)
        cardsScroll.frame = NSRect(x:0,y:0,width:w,height:bounds.height)
        if section == .spaces { layoutCards() }
        filterPane.frame = pane.bounds
        for (i,v) in filterPane.subviews.enumerated() {
            if i == 0 { v.frame = NSRect(x:12,y:16,width:max(100,w-90),height:23) }
            else if i == 1 { v.frame = NSRect(x:w-76,y:7,width:66,height:36) }
            else if i == 2 { v.frame = NSRect(x:12,y:60,width:w-24,height:23) }
            else { v.frame = NSRect(x:12,y:87+CGFloat(i-3)*42,width:w-24,height:34) }
        }
    }
    func numberOfSections(in collectionView:NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView:NSCollectionView, numberOfItemsInSection section:Int) -> Int { self.section == .media ? items.count : self.section == .downloads ? records.count : self.section == .archived ? archives.count : 0 }
    func collectionView(_ collectionView:NSCollectionView,itemForRepresentedObjectAt indexPath:IndexPath) -> NSCollectionViewItem {
        let tile = collectionView.makeItem(withIdentifier:LibraryTile.identifier,for:indexPath) as! LibraryTile
        tile.open = nil; tile.reveal = nil; tile.view.toolTip = nil
        tile.picture.layer?.borderWidth = 0
        tile.transfer.isHidden = true; tile.picture.isHidden = false; tile.view.setAccessibilityElement(true)
        tile.mediaMode = section == .media; tile.name.isHidden = tile.mediaMode; tile.detail.isHidden = tile.mediaMode; tile.bar.isHidden = true
        tile.updateAppearance(animated:false)
        if section == .media {
            let item = items[indexPath.item]; tile.key = item.cacheKey; tile.view.toolTip = item.name; tile.view.setAccessibilityLabel(item.name)
            tile.open = { [weak self] in self?.preview([item.url]) }; tile.reveal = { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            if let image = thumbnails.object(forKey:item.cacheKey as NSString) { tile.picture.image = image; tile.picture.layer?.borderWidth = 3; tile.picture.layer?.borderColor = NSColor.white.cgColor }
            else {
                tile.picture.image = NSImage(systemSymbolName:item.kind == "audio" ? "waveform" : item.kind == "video" ? "play.rectangle" : "photo",accessibilityDescription:nil)
                let request = QLThumbnailGenerator.Request(fileAt:item.url,size:NSSize(width:220,height:220),scale:2,representationTypes:.thumbnail)
                tile.thumbnail = request
                QLThumbnailGenerator.shared.generateBestRepresentation(for:request) { [weak self,weak tile] representation,_ in
                    guard let representation else { return }
                    DispatchQueue.main.async {
                        let image = representation.nsImage; self?.thumbnails.setObject(image,forKey:item.cacheKey as NSString,cost:440*440*4)
                        guard let tile, tile.key == item.cacheKey else { return }
                        tile.picture.image = image; tile.thumbnail = nil; tile.picture.layer?.borderWidth = 3; tile.picture.layer?.borderColor = NSColor.white.cgColor; tile.view.needsLayout = true
                        let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = 0; fade.toValue = 1; fade.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16; tile.picture.layer?.add(fade,forKey:"thumbnail")
                    }
                }
            }
        } else if section == .downloads {
            configureTransfer(tile,record:records[indexPath.item])
        } else if section == .archived {
            let tab = archives[indexPath.item]; tile.name.stringValue = tab.displayTitle.isEmpty ? tab.url : tab.displayTitle; tile.detail.stringValue = URL(string:tab.url)?.host ?? tab.url
            tile.key = "archive:"+tab.id
            if tab.autoArchivedAt != nil {
                tile.detail.stringValue = (language == "en" ? "Auto-archived" : "Archivé automatiquement") + " · " + tile.detail.stringValue
            }
            tile.picture.image = archiveImage(tab)
            tile.open = { [weak self] in self?.restoreTab?(tab.id) }
        }
        if !tile.mediaMode { tile.view.setAccessibilityLabel(tile.name.stringValue + " — " + tile.detail.stringValue) }
        tile.view.needsLayout = true; return tile
    }
    private func archiveImage(_ tab:NativeTab) -> NSImage? {
        archivedIcon(tab) ?? NSImage(systemSymbolName:tab.autoArchivedAt != nil ? "clock.arrow.circlepath" : "globe",accessibilityDescription:nil)
    }
    func refreshArchiveIcons() {
        guard section == .archived else { return }
        for case let tile as LibraryTile in collection.visibleItems() {
            guard let index = collection.indexPath(for:tile)?.item, archives.indices.contains(index),
                  tile.key == "archive:"+archives[index].id else { continue }
            tile.picture.image = archiveImage(archives[index])
        }
    }
    private func configureTransfer(_ tile:LibraryTile, record:LibraryDownload) {
        store.checkLegacyDownload(record)
        tile.key = record.id
        for child in [tile.picture,tile.name,tile.detail,tile.bar] { child.isHidden = true }
        tile.transfer.isHidden = false; tile.view.setAccessibilityElement(false)
        tile.transfer.action = { [weak self] in self?.store.request($0,action:$1) }
        tile.transfer.removeRecord = { [weak self] in self?.store.removeDownload($0) }
        tile.transfer.seen = { [weak self] in self?.store.acknowledge([$0]) }
        tile.transfer.open = { [weak self] in self?.preview([$0]) }
        tile.transfer.update(record,language:session.language,ink:dark ? .white : NSColor(white:0.1,alpha:1))
        tile.open = { [weak self] in if record.state == "complete", !record.path.isEmpty { self?.store.acknowledge([record.id]); self?.preview([URL(fileURLWithPath:record.path)]) } }
        tile.reveal = { if !record.path.isEmpty { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:record.path)]) } }
    }
    func collectionView(_ collectionView:NSCollectionView,willDisplay item:NSCollectionViewItem,forRepresentedObjectAt indexPath:IndexPath) {
        if section == .downloads, let tile = item as? LibraryTile, records.indices.contains(indexPath.item) { configureTransfer(tile,record:records[indexPath.item]) }
    }
    func collectionView(_ collectionView:NSCollectionView,pasteboardWriterForItemAt indexPath:IndexPath) -> NSPasteboardWriting? {
        if section == .media { return items[indexPath.item].url as NSURL }
        if section == .downloads, records[indexPath.item].state == "complete", !records[indexPath.item].path.isEmpty { return URL(fileURLWithPath:records[indexPath.item].path) as NSURL }
        return nil
    }
    private func previewSelection() {
        guard let index = collection.selectionIndexPaths.first?.item else { return }
        if section == .media, items.indices.contains(index) { preview([items[index].url]) }
        else if section == .downloads, records.indices.contains(index), records[index].state == "complete" { preview([URL(fileURLWithPath:records[index].path)]) }
    }
    private func preview(_ urls:[URL]) {
        previewURLs = urls; window?.makeFirstResponder(self)
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self; panel.reloadData(); panel.makeKeyAndOrderFront(nil)
    }
    override func acceptsPreviewPanelControl(_ panel:QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel:QLPreviewPanel!) { panel.dataSource = self }
    override func endPreviewPanelControl(_ panel:QLPreviewPanel!) { panel.dataSource = nil }
    func numberOfPreviewItems(in panel:QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel:QLPreviewPanel!,previewItemAt index:Int) -> QLPreviewItem! { previewURLs[index] as NSURL }
    private func showFilters() {
        filterVisible = true; filterPane.subviews.forEach { $0.removeFromSuperview() }
        let title = NSTextField(labelWithString:t("filterDownloads")); title.font = .systemFont(ofSize:14,weight:.bold); title.textColor = .white.withAlphaComponent(0.8); filterPane.addSubview(title)
        let done = LibraryButton(t("done")) { [weak self] in self?.hideFilters() }; done.filled = true; filterPane.addSubview(done)
        let label = NSTextField(labelWithString:t("profiles")); label.font = .systemFont(ofSize:12,weight:.semibold); label.textColor = .white.withAlphaComponent(0.6); filterPane.addSubview(label)
        for profile in session.profiles {
            let button = LibraryButton(profile.name) { [weak self] in
                guard let self else { return }; if self.profileFilter.contains(profile.id) { self.profileFilter.remove(profile.id) } else { self.profileFilter.insert(profile.id) }; self.showFilters()
            }; button.selected = profileFilter.contains(profile.id); button.filled = true; filterPane.addSubview(button)
        }
        refresh(); animateFilter()
    }
    private func hideFilters() { filterVisible = false; refresh(); animateFilter() }
    private func animateFilter() { let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = 0.3; fade.toValue = 1; fade.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16; pane.layer?.add(fade,forKey:"filter") }
    private func rebuildCards() {
        // Preserve cards and their field editors while another tab updates in CEF.
        let ids = Set(session.spaces.map(\.id))
        for card in spaceCards where !ids.contains(card.spaceID) { card.removeFromSuperview() }
        spaceCards = session.spaces.map { space in
            let card = spaceCards.first(where: { $0.spaceID == space.id }) ?? LibrarySpaceCard(id:space.id)
            card.theme = space.theme ?? .solid(space.color); card.dark = dark
            card.icon.spaceIconValue = space.icon; card.icon.title = SpaceIcon.caption(space.icon); card.icon.symbol = SpaceIcon.symbol(space.icon); card.icon.needsDisplay = true
            card.icon.setAccessibilityLabel(t("changeSpaceIcon")+" — "+space.name); card.icon.toolTip = t("changeSpaceIcon")
            card.icon.invoke = { [weak self, weak card] in guard let card else { return }; self?.editIcon?(space.id,card.icon) }
            if card.name.currentEditor() == nil { card.name.stringValue = space.name; card.name.savedName = space.name }
            card.name.setAccessibilityLabel(t("renameSpace")+" — "+space.name); card.name.toolTip = t("renameSpace")
            card.name.commit = { [weak self] value in self?.renameSpace?(space.id,value) }
            card.paint.setAccessibilityLabel(t("editTheme")+" — "+space.name); card.paint.toolTip = t("editTheme")
            card.paint.invoke = { [weak self] in self?.editTheme?(space.id) }
            let body = LibraryCanvas()
            var rows = session.sidebarTree(spaceID:space.id)
            rows += session.sidebarChildren(spaceID:space.id,parentID:nil,temporary:true).map { SidebarTreeRow(item:$0,depth:0,parentID:nil) }
            for (i,row) in rows.enumerated() {
                let button:LibraryButton
                switch row.item {
                case .folder(let id):
                    guard let folder = session.folders.first(where: { $0.id == id }) else { continue }
                    button = LibraryButton(folder.name,symbol:folder.collapsed ? "folder" : "folder.fill") { [weak self] in self?.folderToggle?(id) }
                case .tab(let id):
                    guard let tab = session.tabs.first(where: { $0.id == id }) else { continue }
                    button = LibraryButton(tab.displayTitle.isEmpty ? URL(string:tab.url)?.host ?? t("newTab") : tab.displayTitle,symbol:"globe") { [weak self] in self?.selectTab?(id) }; button.font = .systemFont(ofSize:13)
                }
                button.frame = NSRect(x:CGFloat(min(row.depth,6))*14,y:CGFloat(i)*39,width:220-CGFloat(min(row.depth,6))*14,height:36); body.addSubview(button)
            }
            let scrollPoint = card.bodyScroll.contentView.bounds.origin
            body.frame = NSRect(x:0,y:0,width:220,height:CGFloat(rows.count)*39); card.bodyScroll.documentView = body
            card.bodyScroll.contentView.scroll(to:NSPoint(x:0,y:min(scrollPoint.y,max(0,body.bounds.height-card.bodyScroll.contentSize.height))))
            card.handle.setAccessibilityLabel(t("move")+" — "+space.name); card.handle.toolTip = t("move")
            card.handle.began = { [weak self] id in
                guard let self else { return }; self.draggingSpaceID = id; self.previewOrder = self.session.spaces.map(\.id)
                self.spaceCards.first(where: { $0.spaceID == id })?.alphaValue = 0.24
            }
            card.handle.ended = { [weak self] in self?.finishSpaceDrag() }
            card.handle.invoke = { [weak self,weak card] in
                guard let self, let card else { return }; let menu = NSMenu()
                for (key,delta) in [("moveLeft",-1),("moveRight",1)] {
                    let item = NSMenuItem(title:self.t(key),action:#selector(self.moveCard(_:)),keyEquivalent:"")
                    item.target = self; item.representedObject = [space.id,String(delta)]
                    item.isEnabled = self.session.spaces.firstIndex(where: { $0.id == space.id }).map { self.session.spaces.indices.contains($0+delta) } ?? false
                    menu.addItem(item)
                }
                menu.autoenablesItems = false; menu.popUp(positioning:nil,at:NSPoint(x:12,y:card.bounds.height-42),in:card)
            }
            card.more.setAccessibilityLabel(t("more")+" — "+space.name); card.more.toolTip = t("more")
            card.more.invoke = { [weak self,weak card] in guard let self, let card else { return }; self.spaceMenu?(space.id)?.popUp(positioning:nil,at:NSPoint(x:card.bounds.width-42,y:card.bounds.height-42),in:card) }
            if card.superview == nil { cards.addSubview(card) }
            return card
        }
        layoutCards()
    }
    @objc private func moveCard(_ sender:NSMenuItem) { guard let value = sender.representedObject as? [String],value.count == 2, let delta = Int(value[1]) else { return }; reorderSpace?(value[0],delta) }
    private func previewSpaceMove(_ id:String, point:NSPoint) -> Bool {
        guard draggingSpaceID == id, let from = previewOrder.firstIndex(of:id), !previewOrder.isEmpty else { return false }
        let target = max(0,min(previewOrder.count-1,Int(floor((point.x-24)/264))))
        if target != from {
            previewOrder.remove(at:from); previewOrder.insert(id,at:target)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment,performanceTime:.now)
            layoutCards(animated:true)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        spaceInsertion.frame = CGRect(x:12+CGFloat(target)*264,y:56,width:3,height:max(40,bounds.height-112)); spaceInsertion.isHidden = false
        CATransaction.commit()
        return true
    }
    private func resetSpacePreview() {
        previewOrder = session.spaces.map(\.id); spaceInsertion.isHidden = true; layoutCards(animated:true)
    }
    private func commitSpaceMove(_ id:String) -> Bool {
        guard draggingSpaceID == id, let index = previewOrder.firstIndex(of:id) else { return false }
        draggingSpaceID = nil; previewOrder = []; spaceInsertion.isHidden = true
        moveSpace?(id,index)
        for card in spaceCards { card.alphaValue = 1 }
        layoutCards(animated:true); return true
    }
    private func finishSpaceDrag() {
        draggingSpaceID = nil; previewOrder = []; spaceInsertion.isHidden = true
        for card in spaceCards { card.animator().alphaValue = 1 }
        rebuildCards()
    }
    private func layoutCards(animated:Bool = false) {
        let height = max(220,bounds.height-96)
        cards.frame = NSRect(x:0,y:0,width:max(pane.bounds.width,CGFloat(session.spaces.count)*264+24),height:bounds.height)
        let order = draggingSpaceID == nil ? session.spaces.map(\.id) : previewOrder
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.22 : 0
            context.timingFunction = CAMediaTimingFunction(controlPoints:0.2,0.8,0.2,1)
            for card in spaceCards {
                guard let index = order.firstIndex(of:card.spaceID) else { continue }
                let frame = NSRect(x:24+CGFloat(index)*264,y:48,width:240,height:height)
                if animated { card.animator().frame = frame } else { card.frame = frame }
            }
        }
    }
    func dispose() { store.changed = nil; store.stopObserving(); searchTask?.cancel(); if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }; if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared()?.dataSource === self { QLPreviewPanel.shared()?.orderOut(nil); QLPreviewPanel.shared()?.dataSource = nil } }
    deinit { dispose() }
}
