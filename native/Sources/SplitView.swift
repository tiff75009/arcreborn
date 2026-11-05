import AppKit
import QuartzCore

class SplitFlippedView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}
final class SplitPaneView: SplitFlippedView {
    let tabID: String
    let body = NSView()
    let header = SplitFlippedView()
    private let address = ActionButton(action:{})
    private let back = NavigationButton("",symbol:"arrow.left",action:{})
    private let forward = NavigationButton("",symbol:"arrow.right",action:{})
    private let reload = NavigationButton("",symbol:"arrow.clockwise",action:{})
    private let options = NavigationButton("",symbol:"rectangle.split.2x1",action:{})
    let site = NavigationButton("",symbol:"slider.horizontal.3",action:{})
    private let close = NavigationButton("",symbol:"xmark",action:{})
    private let landing = BrowserLandingView(frame:.zero)
    var command: ((String,String) -> Void)?
    init(id: String) {
        tabID = id; super.init(frame:.zero)
        wantsLayer = true; layer?.cornerRadius = 8; layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        header.wantsLayer = true; header.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        addSubview(body); addSubview(header); body.addSubview(landing)
        for button in [back,forward,reload,address,site,options,close] { header.addSubview(button) }
        for (button,kind) in [(back,"back"),(forward,"forward"),(reload,"reload"),(address,"address"),(options,"options"),(site,"site"),(close,"close")] {
            button.invoke = { [weak self] in guard let self else { return }; self.command?(self.tabID,kind) }
        }
        address.font = .systemFont(ofSize:12,weight:.medium); address.cell?.lineBreakMode = .byTruncatingTail
        address.imagePosition = .imageLeading
        address.image = NSImage(systemSymbolName:"link",accessibilityDescription:nil)
        landing.search = { [weak self] in guard let self else { return }; self.command?(self.tabID,"address") }
        landing.retry = { [weak self] in guard let self else { return }; self.command?(self.tabID,"reload") }
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(title:String, url:String, focused:Bool, canBack:Bool, canForward:Bool, language:String, landingPage:BrowserLandingView.Page?) {
        address.title = settingsPageURL(url) != nil ? browserDisplayAddress(url) : (URL(string:url)?.host ?? title)
        address.toolTip = browserDisplayAddress(url)
        back.isEnabled = canBack; forward.isEnabled = canForward
        back.toolTip = language == "fr" ? "Précédent" : "Back"
        forward.toolTip = language == "fr" ? "Suivant" : "Forward"
        reload.toolTip = language == "fr" ? "Recharger" : "Reload"
        close.toolTip = language == "fr" ? "Retirer de la vue partagée" : "Remove from Split View"
        site.toolTip = language == "fr" ? "Réglages du site et extensions" : "Site settings and extensions"
        options.toolTip = language == "fr" ? "Options de la vue partagée" : "Split View options"
        landing.isHidden = landingPage == nil
        if let landingPage { landing.show(landingPage) }
        layer?.borderWidth = focused ? 2 : 0.5
        layer?.borderColor = (focused ? NSColor.systemIndigo : NSColor.white.withAlphaComponent(0.10)).cgColor
        header.alphaValue = focused ? 1 : 0.72
        for button in [back,forward,reload,site,options,close] { button.ink = .labelColor }
    }
    override func layout() {
        super.layout()
        header.frame = NSRect(x:2,y:2,width:max(0,bounds.width-4),height:32)
        body.frame = NSRect(x:2,y:34,width:max(0,bounds.width-4),height:max(0,bounds.height-36))
        back.frame = NSRect(x:4,y:2,width:26,height:27); forward.frame = NSRect(x:32,y:2,width:26,height:27)
        reload.frame = NSRect(x:60,y:2,width:26,height:27)
        close.frame = NSRect(x:header.bounds.width-30,y:2,width:26,height:27)
        options.frame = NSRect(x:header.bounds.width-60,y:2,width:26,height:27)
        site.frame = NSRect(x:header.bounds.width-90,y:2,width:26,height:27)
        let compact = header.bounds.width < 290
        back.isHidden = compact; forward.isHidden = compact; reload.isHidden = compact
        let leading:CGFloat = compact ? 6 : 92
        address.frame = NSRect(x:leading,y:2,width:max(0,header.bounds.width-leading-94),height:27)
        landing.frame = body.bounds
    }
    func optionsMenu(_ menu:NSMenu) { menu.popUp(positioning:nil,at:NSPoint(x:0,y:options.bounds.height),in:options) }
}
private final class SplitDividerView: SplitFlippedView {
    var vertical = false
    var resize: ((CGFloat,Bool) -> Void)?
    override func resetCursorRects() { addCursorRect(bounds,cursor:vertical ? .resizeUpDown : .resizeLeftRight) }
    override func mouseDown(with event:NSEvent) {
        guard let window else { return }
        let initial = event.locationInWindow
        let resize = self.resize
        while let next = window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]) {
            let delta = vertical ? initial.y-next.locationInWindow.y : next.locationInWindow.x-initial.x
            resize?(delta,next.type == .leftMouseUp)
            if next.type == .leftMouseUp { break }
        }
    }
}
final class SplitHostView: SplitFlippedView {
    var panes:[SplitPaneView] = []
    private var dividers:[SplitDividerView] = []
    var vertical = false
    var weights:[Double] = []
    var resized: (() -> Void)?
    var weightsChanged: (([Double]) -> Void)?
    func configure(ids:[String], vertical:Bool, weights:[Double]) {
        let changed = self.vertical != vertical || panes.map(\.tabID) != ids
        let oldFrames = Dictionary(uniqueKeysWithValues:panes.map { ($0.tabID,$0.frame) })
        self.vertical = vertical; self.weights = weights
        if panes.map(\.tabID) != ids {
            let previous = Dictionary(uniqueKeysWithValues:panes.map { ($0.tabID,$0) })
            panes.filter { !ids.contains($0.tabID) }.forEach { $0.removeFromSuperview() }
            panes = ids.map { previous[$0] ?? SplitPaneView(id:$0) }
            for pane in panes where pane.superview == nil {
                addSubview(pane)
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.20
                    pane.layer?.add(fade,forKey:"split-appear")
                }
            }
            dividers.forEach { $0.removeFromSuperview() }
            dividers = (0..<max(0,ids.count-1)).map { _ in let d = SplitDividerView(); addSubview(d); return d }
        }
        needsLayout = true; layoutSubtreeIfNeeded()
        if changed, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            for pane in panes {
                guard let old = oldFrames[pane.tabID], old.width > 0, let layer = pane.layer else { continue }
                let position = CABasicAnimation(keyPath:"position")
                position.fromValue = NSValue(point:NSPoint(x:old.minX+old.width*layer.anchorPoint.x,y:old.minY+old.height*layer.anchorPoint.y)); position.toValue = NSValue(point:layer.position)
                let size = CABasicAnimation(keyPath:"bounds.size")
                size.fromValue = NSValue(size:old.size); size.toValue = NSValue(size:layer.bounds.size)
                let group = CAAnimationGroup(); group.animations = [position,size]; group.duration = 0.22
                group.timingFunction = CAMediaTimingFunction(controlPoints:0.2,0.8,0.2,1)
                layer.add(group,forKey:"split-layout")
            }
        }
    }
    override func layout() {
        super.layout()
        guard !panes.isEmpty else { return }
        let gap:CGFloat = 8
        let length = max(1,(vertical ? bounds.height : bounds.width)-gap*CGFloat(panes.count-1))
        if weights.count != panes.count { weights = Array(repeating:1/Double(panes.count),count:panes.count) }
        var offset:CGFloat = 0
        for (i,pane) in panes.enumerated() {
            let size = length * weights[i]
            pane.frame = vertical ? NSRect(x:0,y:offset,width:bounds.width,height:size) : NSRect(x:offset,y:0,width:size,height:bounds.height)
            pane.needsLayout = true; pane.layoutSubtreeIfNeeded()
            offset += size
            if i < dividers.count {
                let divider = dividers[i]; divider.vertical = vertical
                divider.frame = vertical ? NSRect(x:0,y:offset,width:bounds.width,height:gap) : NSRect(x:offset,y:0,width:gap,height:bounds.height)
                let initial = weights
                divider.resize = { [weak self] delta,ended in
                    guard let self else { return }
                    // Both adjacent panes share a fixed total. No page is recreated during resize.
                    let total = initial[i]+initial[i+1]
                    let minimum = min(0.45*total, (self.vertical ? 100.0 : 150.0)/length)
                    let left = min(total-minimum,max(minimum,initial[i]+delta/length))
                    self.weights[i] = left; self.weights[i+1] = total-left
                    self.needsLayout = true; self.layoutSubtreeIfNeeded()
                    if ended { self.weightsChanged?(self.weights) }
                }
                offset += gap
            }
        }
        resized?()
    }
}

final class SplitTabChip: NSView, NSDraggingSource {
    private let developerOutline = DeveloperTabOutline()
    var developerMode = false { didSet { needsLayout = true } }
    let id:String
    let icon = NSImageView()
    let label = NSTextField(labelWithString:"")
    let soundButton = TabSoundButton()
    var select:(() -> Void)?
    var rename:(() -> Void)?
    var context:(() -> NSMenu)?
    var dragChanged:((Bool) -> Void)?
    override var mouseDownCanMoveWindow:Bool { false }
    init(id:String,title:String,image:NSImage?,active:Bool) {
        self.id = id; super.init(frame:.zero); wantsLayer = true; layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor.white.withAlphaComponent(active ? 0.20 : 0.08).cgColor
        icon.image = image; icon.imageScaling = .scaleProportionallyUpOrDown
        label.stringValue = title; label.font = .systemFont(ofSize:12,weight:.medium); label.lineBreakMode = .byTruncatingTail
        addSubview(icon); addSubview(label); label.allowsExpansionToolTips = false; setAccessibilityLabel(title); setAccessibilityRole(.button)
        addSubview(soundButton)
        layer?.addSublayer(developerOutline)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func layout() {
        super.layout(); let compact = bounds.width < 76
        developerOutline.update(in:bounds,enabled:developerMode,radius:8)
        icon.frame = NSRect(x:compact ? bounds.midX-9 : 7,y:bounds.midY-9,width:18,height:18)
        let inset = soundButton.titleInset
        icon.isHidden = compact && inset > 0
        soundButton.frame = NSRect(x:compact ? bounds.midX-11 : 28,y:bounds.midY-12,width:22,height:24)
        label.isHidden = compact; label.frame = NSRect(x:30+inset,y:bounds.midY-8,width:max(0,bounds.width-36-inset),height:17)
    }
    override func menu(for event:NSEvent) -> NSMenu? { context?() }
    override func mouseDown(with event:NSEvent) {
        guard let window else { return }
        let start = event.locationInWindow
        layer?.opacity = 0.72
        while let next = window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]) {
            if next.type == .leftMouseUp {
                layer?.opacity = 1
                if let rename, label.isHidden || label.frame.contains(convert(start,from:nil)) { rename() }
                else { select?() }
                return
            }
            if hypot(next.locationInWindow.x-start.x,next.locationInWindow.y-start.y) > 4 {
                layer?.opacity = 1
                let pasteboard = NSPasteboardItem(); pasteboard.setString(id,forType:NSPasteboard.PasteboardType("local.browser.tab"))
                let item = NSDraggingItem(pasteboardWriter:pasteboard)
                item.setDraggingFrame(bounds,contents:icon.image ?? NSImage(size:bounds.size))
                dragChanged?(true); beginDraggingSession(with:[item],event:next,source:self); return
            }
        }
        layer?.opacity = 1
    }
    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext) -> NSDragOperation { .move }
    func draggingSession(_ session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation) { dragChanged?(false) }
}
final class SplitGroupCell: NSTableCellView {
    var chips:[SplitTabChip] = []
    private let groupTitle = NSTextField(labelWithString:"")
    private let groupIcon = NSImageView()
    private var titled = false
    init(chips:[SplitTabChip], ink:NSColor, title:String?, icon:String?) {
        super.init(frame:.zero); self.chips = chips
        wantsLayer = true; layer?.cornerRadius = 11; layer?.backgroundColor = ink.withAlphaComponent(0.09).cgColor
        for chip in chips { chip.label.textColor = ink; addSubview(chip) }
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
    }
    required init?(coder:NSCoder) { fatalError() }
    override func layout() {
        super.layout(); let width = max(1,(bounds.width-8-CGFloat(chips.count-1)*4)/CGFloat(max(1,chips.count)))
        for (i,chip) in chips.enumerated() { chip.frame = NSRect(x:4+CGFloat(i)*(width+4),y:4,width:width,height:max(1,bounds.height-(titled ? 32 : 8))) }
        groupIcon.frame = NSRect(x:8,y:bounds.height-23,width:16,height:16)
        groupTitle.frame = NSRect(x:groupIcon.isHidden ? 8 : 30,y:bounds.height-23,width:max(0,bounds.width-40),height:17)
    }
}
