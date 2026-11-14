import AppKit
import QuartzCore

/// A decoration shared by ordinary tabs, split chips and favorite tiles.
final class DeveloperTabOutline: CAShapeLayer {
    override init() {
        super.init(); fillColor = nil; strokeColor = NSColor(srgbRed:1,green:0.86,blue:0.15,alpha:1).cgColor
        lineWidth = 2; lineDashPattern = [5,4]
        actions = ["path":NSNull(),"hidden":NSNull(),"bounds":NSNull(),"position":NSNull()]
        isHidden = true
    }
    override init(layer:Any) { super.init(layer:layer) }
    required init?(coder:NSCoder) { fatalError() }
    func update(in bounds:NSRect, enabled:Bool, radius:CGFloat = 10) {
        frame = bounds
        path = CGPath(roundedRect:bounds.insetBy(dx:1,dy:1),cornerWidth:radius,cornerHeight:radius,transform:nil)
        isHidden = !enabled
    }
}

struct FavoriteVisual {
    var id: String
    var title: String
    var image: NSImage?
    var menu: NSMenu
    var isLoaded: Bool = false
    var developerMode: Bool = false
    var unreadLabel: String?
    var configureSound: ((TabSoundButton) -> Void)?
}

/// Retained tiles: a title/favicon refresh never replaces a running drag source.
final class FavoritesGrid: NSView {
    var dragWriter: ((String) -> NSPasteboardItem?)?
    var activate: ((String) -> Void)?
    var accept: ((String,Int,NSDraggingInfo) -> Bool)?
    var acceptedID: ((NSDraggingInfo) -> String?)?
    var draggingChanged: ((Bool) -> Void)?
    var heightChanged: (() -> Void)?
    private var items: [FavoriteVisual] = []
    private var tiles: [String: FavoriteTile] = [:]
    private var activeID: String?
    private var ink = NSColor.labelColor
    private var localDrag: String?
    private var previewID: String?
    private var previewIndex: Int?
    private var lastSlot: Int?
    private var isUpdating = false
    private var layoutWidth: CGFloat = 0
    private let placeholder = NSView()
    private let dragType = SidebarTabDrag.tabType
    override var isFlipped: Bool { true }
    var preferredHeight: CGFloat {
        let count = previewID == nil ? items.count : items.filter { $0.id != previewID }.count+1
        return FavoriteGridLayout(count:count).height
    }
    override init(frame: NSRect) {
        super.init(frame:frame); wantsLayer = true
        registerForDraggedTypes([dragType])
        placeholder.wantsLayer = true; placeholder.layer?.cornerRadius = 12
        placeholder.layer?.borderWidth = 1.5; placeholder.layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        placeholder.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        placeholder.isHidden = true; addSubview(placeholder)
    }
    required init?(coder: NSCoder) { fatalError() }
    // A split is one sidebar item. Let the enclosing sidebar receive its drop
    // above the list instead of offering to turn one pane into a favorite.
    func allowFavoriteDrops(_ enabled:Bool) {
        if enabled { registerForDraggedTypes([dragType]) } else { unregisterDraggedTypes() }
    }
    func trackPointer(_ event: NSEvent) { for tile in tiles.values { tile.trackPointer(event) } }
    func ownsDrag(_ source: Any?) -> Bool { (source as? FavoriteTile)?.grid === self }
    func frameForItem(_ id:String) -> NSRect? { tiles[id]?.frame }
    func update(_ items: [FavoriteVisual], activeID: String?, ink: NSColor) {
        self.items = items; self.activeID = activeID; self.ink = ink
        isUpdating = true
        for item in items {
            let tile: FavoriteTile
            if let existing = tiles[item.id] { tile = existing }
            else {
                tile = FavoriteTile(id:item.id,grid:self); tiles[item.id] = tile; addSubview(tile)
                tile.alphaValue = 0
            }
            tile.configure(item,active:item.id == activeID,ink:ink)
        }
        for id in Array(tiles.keys) where !items.contains(where: { $0.id == id }) && id != localDrag {
            tiles.removeValue(forKey:id)?.removeFromSuperview()
        }
        isUpdating = false
        arrange(animated:window != nil)
    }
    override func layout() { super.layout(); if layoutWidth != bounds.width { layoutWidth = bounds.width; arrange(animated:false) } }
    private func arrange(animated: Bool) {
        guard !isUpdating, bounds.width > 0 else { return }
        let peers = items.filter { $0.id != previewID }
        let count = previewID == nil ? items.count : peers.count+1
        let layout = FavoriteGridLayout(count:count)
        let slot = min(previewIndex ?? 0,peers.count)
        placeholder.isHidden = previewID == nil
        if previewID != nil { placeholder.frame = layout.frame(at:slot,width:bounds.width) }
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? 0.23 : 0
            context.timingFunction = CAMediaTimingFunction(controlPoints:0.22,0.78,0.24,1)
            for (i,item) in peers.enumerated() {
                guard let tile = tiles[item.id] else { continue }
                let index = previewID != nil && i >= slot ? i+1 : i
                let frame = layout.frame(at:index,width:bounds.width)
                if tile.frame == .zero { tile.frame = frame.insetBy(dx:3,dy:3) }
                if tile.frame != frame { if animate { tile.animator().frame = frame } else { tile.frame = frame } }
                let opacity: CGFloat = item.id == localDrag ? 0 : 1
                if animate { tile.animator().alphaValue = opacity } else { tile.alphaValue = opacity }
            }
            if let previewID { tiles[previewID]?.alphaValue = 0 }
        }
    }
    fileprivate func select(_ id: String) { activate?(id) }
    fileprivate func beginDrag(_ id: String) {
        localDrag = id; previewID = id; previewIndex = items.firstIndex(where: { $0.id == id }); lastSlot = previewIndex
        draggingChanged?(true); arrange(animated:true)
    }
    fileprivate func endDrag() {
        localDrag = nil; clearPreview()
        for id in Array(tiles.keys) where !items.contains(where: { $0.id == id }) { tiles.removeValue(forKey:id)?.removeFromSuperview() }
        draggingChanged?(false); arrange(animated:true)
    }
    func clearPreview() {
        let hadPreview = previewID != nil
        previewID = nil; previewIndex = nil; lastSlot = nil
        if hadPreview { heightChanged?(); arrange(animated:true) }
    }
    private func propose(_ info: NSDraggingInfo) -> NSDragOperation {
        guard let id = acceptedID?(info) else { clearPreview(); return [] }
        let point = convert(info.draggingLocation,from:nil)
        let layout = FavoriteGridLayout(count:items.filter { $0.id != id }.count+1)
        let slot = layout.insertionIndex(x:point.x,y:point.y,width:bounds.width)
        if previewID != id || previewIndex != slot {
            let previousHeight = preferredHeight
            previewID = id; previewIndex = slot
            if preferredHeight != previousHeight { heightChanged?() }
            arrange(animated:true)
            if lastSlot != slot { NSHapticFeedbackManager.defaultPerformer.perform(.alignment,performanceTime:.now); lastSlot = slot }
        }
        return .move
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { propose(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { propose(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { clearPreview() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard acceptedID?(sender) != nil else { return false }
        sender.animatesToDestination = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion; return true
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let id = acceptedID?(sender), previewID == id, let index = previewIndex else { return false }
        // Clear preview before publishing; the placeholder becomes the real tile.
        previewID = nil; previewIndex = nil; lastSlot = nil
        let result = accept?(id,index,sender) ?? false
        heightChanged?(); arrange(animated:true); return result
    }
}

private final class FavoriteTile: NSButton, NSDraggingSource {
    private let developerOutline = DeveloperTabOutline()
    private var developerMode = false
    let id: String
    weak var grid: FavoritesGrid?
    private var favicon: NSImage?
    private let iconView = NSImageView()
    private let soundButton = TabSoundButton()
    private var isLoaded = false
    private var hasUnread = false
    private var configured = false
    private var ink = NSColor.labelColor
    private var active = false, hovered = false
    private var tracking: NSTrackingArea?
    private let colorBorder = CAGradientLayer()
    private let borderMask = CAShapeLayer()
    private var fallback = ""
    private var tileTitle = ""
    init(id: String, grid: FavoritesGrid) {
        self.id = id; self.grid = grid
        super.init(frame:.zero)
        title = ""; isBordered = false; wantsLayer = true
        layer?.cornerRadius = 12
        iconView.imageScaling = .scaleProportionallyUpOrDown; iconView.wantsLayer = true
        addSubview(iconView)
        addSubview(soundButton)
        soundButton.hoverChanged = { [weak self] inside in self?.toolTip = inside ? nil : self?.tileTitle }
        colorBorder.startPoint = CGPoint(x:0,y:1); colorBorder.endPoint = CGPoint(x:1,y:0)
        borderMask.fillColor = NSColor.clear.cgColor; borderMask.strokeColor = NSColor.white.cgColor; borderMask.lineWidth = 2
        colorBorder.mask = borderMask; layer?.addSublayer(colorBorder)
        layer?.addSublayer(developerOutline)
        target = self; action = #selector(activate)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func activate() { grid?.select(id) }
    func configure(_ item: FavoriteVisual, active: Bool, ink: NSColor) {
        developerMode = item.developerMode && active; developerOutline.update(in:bounds,enabled:developerMode)
        let imageChanged = favicon !== item.image
        favicon = item.image; if imageChanged { iconView.image = item.image }; fallback = String(item.title.prefix(1)).uppercased()
        self.active = active; self.ink = ink; menu = item.menu; tileTitle = item.title
        toolTip = soundButton.hovered ? nil : tileTitle
        hasUnread = item.unreadLabel != nil
        item.configureSound?(soundButton)
        setAccessibilityLabel([item.title, item.unreadLabel].compactMap { $0 }.joined(separator:", "))
        if imageChanged || colorBorder.colors == nil { colorBorder.colors = faviconPalette(favicon,fallback:ink).map(\.cgColor) }
        let opacity: CGFloat = item.isLoaded ? 1 : 0.42
        if configured && isLoaded != item.isLoaded && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18; iconView.animator().alphaValue = opacity
            }
        } else { iconView.alphaValue = opacity }
        isLoaded = item.isLoaded; configured = true
        updateAppearance(); needsDisplay = true
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let iconCenterY = bounds.midY + (isFlipped ? 9 : -9) * soundButton.reveal
        let iconFrame = NSRect(x:bounds.midX-10,y:iconCenterY-10,width:20,height:20)
        if iconView.frame != iconFrame {
            iconView.frame = iconFrame
            if favicon == nil { needsDisplay = true }
        }
        soundButton.frame = NSRect(x:bounds.midX-12, y:isFlipped ? bounds.minY+2 : bounds.maxY-20,width:24,height:18)
        colorBorder.frame = bounds
        developerOutline.update(in:bounds,enabled:developerMode)
        borderMask.path = CGPath(roundedRect:bounds.insetBy(dx:1,dy:1),cornerWidth:11,cornerHeight:11,transform:nil)
        CATransaction.commit()
    }
    private func updateAppearance() {
        let brightInk = (ink.usingColorSpace(.sRGB)?.redComponent ?? 0) > 0.8
        let selected = active || hovered
        layer?.backgroundColor = selected ? NSColor.white.withAlphaComponent(brightInk ? 0.22 : 0.83).cgColor : ink.withAlphaComponent(0.075).cgColor
        let target: Float = selected ? 1 : 0
        if colorBorder.opacity != target {
            let animation = CABasicAnimation(keyPath:"opacity"); animation.fromValue = colorBorder.presentation()?.opacity ?? colorBorder.opacity; animation.toValue = target
            animation.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
            colorBorder.opacity = target; colorBorder.add(animation,forKey:"hover")
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        if hasUnread {
            let dot = NSRect(x:bounds.maxX-12, y:isFlipped ? bounds.maxY-12 : bounds.minY+7, width:5, height:5)
            NSColor(srgbRed:0.92, green:0.26, blue:0.21, alpha:1).setFill()
            NSBezierPath(ovalIn:dot).fill()
        }
        if favicon == nil {
            let style = NSMutableParagraphStyle(); style.alignment = .center
            NSAttributedString(string:fallback,attributes:[.font:NSFont.systemFont(ofSize:18,weight:.semibold),.foregroundColor:ink.withAlphaComponent(isLoaded ? 1 : 0.42),.paragraphStyle:style]).draw(in:NSRect(x:0,y:iconView.frame.midY-12,width:bounds.width,height:24))
        }
    }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.arrow) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self); addTrackingArea(tracking!)
    }
    func trackPointer(_ event: NSEvent) {
        let inside = event.window === window && event.type != .mouseExited && alphaValue > 0 && containsExposedPointer(at:event.locationInWindow)
        if inside != hovered { hovered = inside; updateAppearance() }
    }
    override func mouseEntered(with event: NSEvent) { trackPointer(event) }
    override func mouseExited(with event: NSEvent) { hovered = false; updateAppearance() }
    override func mouseDown(with event: NSEvent) {
        let start = convert(event.locationInWindow,from:nil)
        while let next = window?.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]) {
            let point = convert(next.locationInWindow,from:nil)
            if next.type == .leftMouseUp { if bounds.contains(point) { activate() }; return }
            guard hypot(point.x-start.x,point.y-start.y) > 4 else { continue }
            guard let pasteboard = grid?.dragWriter?(id) else { return }
            let item = NSDraggingItem(pasteboardWriter:pasteboard)
            let image = NSImage(size:bounds.size)
            if let bitmap = bitmapImageRepForCachingDisplay(in:bounds) { cacheDisplay(in:bounds,to:bitmap); image.addRepresentation(bitmap) }
            item.setDraggingFrame(bounds,contents:image)
            grid?.beginDrag(id)
            let session = beginDraggingSession(with:[item],event:next,source:self)
            session.animatesToStartingPositionsOnCancelOrFail = true
            return
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        SidebarTabDrag.operation(in: context, pasteboard: session.draggingPasteboard)
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { grid?.endDrag() }
}

/// Saturated pixels dominate; transparent padding and white backgrounds are ignored.
private func faviconPalette(_ image: NSImage?, fallback: NSColor) -> [NSColor] {
    guard let image, let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:24,pixelsHigh:24,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
          let context = NSGraphicsContext(bitmapImageRep:bitmap) else { return [fallback,fallback] }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    image.draw(in:NSRect(x:0,y:0,width:24,height:24)); NSGraphicsContext.restoreGraphicsState()
    var bins = [(weight:CGFloat,r:CGFloat,g:CGFloat,b:CGFloat)](repeating:(0,0,0,0),count:12)
    for y in 0..<24 { for x in 0..<24 {
        guard let color = bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.5, color.saturationComponent > 0.3, color.brightnessComponent > 0.25 else { continue }
        let bucket = min(11,Int(color.hueComponent*12)), weight = color.saturationComponent*color.alphaComponent
        bins[bucket].weight += weight; bins[bucket].r += color.redComponent*weight; bins[bucket].g += color.greenComponent*weight; bins[bucket].b += color.blueComponent*weight
    } }
    let strongest = bins.map(\.weight).max() ?? 0
    let colors = bins.filter { $0.weight > max(1,strongest*0.12) }.sorted { $0.weight > $1.weight }.prefix(4).map {
        NSColor(srgbRed:$0.r/$0.weight,green:$0.g/$0.weight,blue:$0.b/$0.weight,alpha:1)
    }
    if colors.count > 1 { return colors }
    let color = colors.first ?? fallback
    return [color,color]
}
