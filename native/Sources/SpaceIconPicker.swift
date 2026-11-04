import AppKit
import QuartzCore

/// Stored as a string so older emoji spaces remain compatible with the session format.
enum SpaceIcon {
    static func symbol(_ value: String) -> String? {
        if value == "none" { return "circle.fill" }
        return value.hasPrefix("sf:") ? String(value.dropFirst(3)) : nil
    }
    static func caption(_ value: String) -> String { symbol(value) == nil ? value : "" }
    static func image(_ value: String) -> NSImage? {
        guard let symbol = symbol(value) else { return nil }
        return NSImage(systemSymbolName:symbol,accessibilityDescription:nil)
    }
    static func draw(_ value: String, in rect: NSRect, color: NSColor, size: CGFloat = 17) {
        if let image = image(value)?.withSymbolConfiguration(.init(pointSize:size,weight:.medium))?.withSymbolConfiguration(.init(paletteColors:[color])) {
            let scale = min(rect.width / max(1,image.size.width),rect.height / max(1,image.size.height))
            let target = value == "none" ? NSRect(x:rect.midX-4,y:rect.midY-4,width:8,height:8) : NSRect(x:rect.midX-image.size.width*scale/2,y:rect.midY-image.size.height*scale/2,width:image.size.width*scale,height:image.size.height*scale)
            image.draw(in:target,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        } else {
            let text = NSAttributedString(string:value,attributes:[.font:NSFont.systemFont(ofSize:size),.foregroundColor:color])
            text.draw(at:NSPoint(x:rect.midX-text.size().width/2,y:rect.midY-text.size().height/2))
        }
    }
    static func title(_ space: NativeSpace) -> String {
        let prefix = caption(space.icon)
        return prefix.isEmpty ? space.name : "\(prefix)  \(space.name)"
    }
}

private final class IconTile: NSButton {
    let value: String
    private let choose: () -> Void
    private var tracking: NSTrackingArea?
    private var hovered = false
    var selected = false
    init(value: String, selected: Bool, choose: @escaping () -> Void) {
        self.value = value; self.selected = selected; self.choose = choose
        super.init(frame:.zero)
        title = ""; isBordered = false; focusRingType = .exterior
        target = self; action = #selector(activate)
        setAccessibilityLabel(value == "none" ? "Retirer l’icône" : (SpaceIcon.symbol(value) ?? value))
        setAccessibilityValue(selected ? "selected" : "")
        wantsLayer = true; layer?.cornerRadius = 6; refresh()
    }
    required init?(coder:NSCoder) { fatalError() }
    @objc private func activate() { choose() }
    override func draw(_ dirtyRect:NSRect) {
        SpaceIcon.draw(value,in:bounds.insetBy(dx:8,dy:8),color:.white,size:19)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self); addTrackingArea(tracking!)
    }
    override func mouseEntered(with event:NSEvent) { hovered = true; refresh() }
    override func mouseExited(with event:NSEvent) { hovered = false; refresh() }
    private func refresh() {
        let color = NSColor.white.withAlphaComponent(selected ? 0.23 : hovered ? 0.12 : 0).cgColor
        let old = layer?.presentation()?.backgroundColor ?? layer?.backgroundColor
        CATransaction.begin(); CATransaction.setDisableActions(true); layer?.backgroundColor = color; CATransaction.commit()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath:"backgroundColor"); animation.fromValue = old; animation.toValue = color; animation.duration = 0.12; layer?.add(animation,forKey:"hover")
        }
    }
}

final class SpaceIconPicker: NSObject, NSPopoverDelegate {
    static let symbols = [
        "star.fill","bookmark.fill","heart.fill","flag.fill","bolt.fill","triangle.fill","asterisk","bell.fill",
        "lightbulb.fill","sailboat.fill","square.grid.2x2.fill","circle.grid.3x3.fill","square.3.layers.3d","externaldrive.fill","tray.fill","square.on.square.fill",
        "folder.fill","archivebox.fill","calendar","envelope.fill","checkmark.square.fill","doc.fill","book.fill","message.fill",
        "person.2.fill","terminal.fill","wrench.and.screwdriver.fill","square.fill","oval.fill","circle.fill","moon.fill","sun.max.fill",
        "sparkles","leaf.fill","cloud.fill","pawprint.fill","basket.fill","gift.fill","bed.double.fill","fork.knife",
        "dumbbell.fill","airplane","music.note","paintpalette.fill","video.fill","bandage.fill","chevron.left","globe.americas.fill",
        "cloud","map.fill","flame.fill","carrot.fill","face.smiling.fill","newspaper.fill","hand.thumbsup.fill","tram.fill"
    ]
    private static let emojis = [
        "😀","🥰","😎","🤩","🥳","🤖","👻","👽","🪐","🌍","🌙","⭐️","☀️","🌈","⚡️","🔥",
        "🏠","💼","💻","📱","🎨","🎵","🎮","🎬","📚","✏️","📷","💡","🔬","🔭","🛠️","⚙️",
        "🌿","🌸","🌲","🍀","🐶","🐱","🦊","🐼","🍎","☕️","🍕","🍰","⚽️","🏀","🏋️","🚴",
        "✈️","🚀","🚗","⛵️","🏖️","🏔️","🎁","❤️"
    ]
    private let popover = NSPopover()
    private let surface = NSVisualEffectView(frame:NSRect(x:0,y:0,width:280,height:278))
    private let segment = NSSegmentedControl(labels:["Emoji","Icônes"],trackingMode:.selectOne,target:nil,action:nil)
    private var tiles: [IconTile] = []
    private let selected: String
    private let change: (String) -> Void
    private let dismissed: () -> Void
    var isShown: Bool { popover.isShown }
    init(value:String, language:String, change:@escaping (String)->Void, dismissed:@escaping ()->Void = {}) {
        self.selected = value; self.change = change; self.dismissed = dismissed
        super.init()
        surface.material = .popover; surface.blendingMode = .behindWindow; surface.state = .active
        segment.setLabel(language == "fr" ? "Icônes" : "Icon",forSegment:1)
        segment.frame = NSRect(x:64,y:238,width:120,height:27); segment.segmentStyle = .rounded
        segment.selectedSegment = SpaceIcon.symbol(value) == nil ? 0 : 1
        segment.target = self; segment.action = #selector(switchTab)
        segment.setAccessibilityLabel(language == "fr" ? "Type d’icône" : "Icon type")
        surface.addSubview(segment)
        let trash = IconTile(value:"sf:trash",selected:false) { [weak self] in self?.pick("none") }
        trash.frame = NSRect(x:193,y:235,width:32,height:32)
        trash.setAccessibilityLabel(language == "fr" ? "Retirer l’icône" : "Remove icon"); surface.addSubview(trash)
        let controller = NSViewController(); controller.view = surface
        popover.contentViewController = controller; popover.contentSize = surface.frame.size
        popover.behavior = .transient; popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.appearance = NSAppearance(named:.darkAqua); popover.delegate = self
        rebuild()
    }
    func show(relativeTo rect:NSRect, of view:NSView) { popover.show(relativeTo:rect,of:view,preferredEdge:.maxY) }
    func close() { popover.close() }
    func popoverDidClose(_ notification:Notification) { dismissed() }
    @objc private func switchTab() {
        rebuild()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let fade = CATransition(); fade.type = .fade; fade.duration = 0.14; surface.layer?.add(fade,forKey:"icon-category")
    }
    private func rebuild() {
        tiles.forEach { $0.removeFromSuperview() }; tiles.removeAll()
        let values = segment.selectedSegment == 0 ? Self.emojis : Self.symbols.map { "sf:"+$0 }
        for (index,value) in values.enumerated() {
            let tile = IconTile(value:value,selected:selected == value) { [weak self] in self?.pick(value) }
            tile.frame = NSRect(x:12+(index%8)*32,y:200-(index/8)*32,width:30,height:30)
            surface.addSubview(tile); tiles.append(tile)
        }
    }
    private func pick(_ value:String) { change(value); close() }
}
