import AppKit
import UniformTypeIdentifiers

enum PortraitRenderer {
    static func image(_ screenshot:NSImage,color:NSColor,maxWidth:CGFloat = 2400) -> NSImage? {
        guard screenshot.size.width > 0, screenshot.size.height > 0 else { return nil }
        let width = min(maxWidth,screenshot.size.width), height = width*screenshot.size.height/screenshot.size.width
        let padding = max(24,width*0.09), canvas = NSSize(width:ceil(width+2*padding),height:ceil(height+2*padding))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(canvas.width),pixelsHigh:Int(canvas.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
              let context = NSGraphicsContext(bitmapImageRep:bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let bounds = NSRect(origin:.zero,size:canvas)
        NSGradient(starting:color.blended(withFraction:0.32,of:.white) ?? color,ending:color.blended(withFraction:0.15,of:.black) ?? color)?.draw(in:bounds,angle:-35)
        let frame = NSRect(x:padding,y:padding,width:width,height:height)
        let radius = max(5,width*0.012), border = max(2,width*0.004)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.shadowBlurRadius = width*0.035; shadow.shadowOffset = NSSize(width:0,height:-width*0.012); shadow.set()
        NSColor.white.withAlphaComponent(0.58).setFill()
        NSBezierPath(roundedRect:frame.insetBy(dx:-border,dy:-border),xRadius:radius+border,yRadius:radius+border).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect:frame,xRadius:radius,yRadius:radius).addClip()
        screenshot.draw(in:frame,from:.zero,operation:.sourceOver,fraction:1)
        NSGraphicsContext.restoreGraphicsState(); NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size:canvas); result.addRepresentation(bitmap); return result
    }
    static func png(_ image:NSImage) -> Data? {
        image.representations.compactMap { $0 as? NSBitmapImageRep }.first?.representation(using:.png,properties:[:])
    }
}

private final class PortraitHueSlider: NSControl {
    var hue:CGFloat = 0.88 { didSet { needsDisplay = true; setAccessibilityValue(Double(hue)) } }
    var changed:((CGFloat)->Void)?
    override var acceptsFirstResponder:Bool { true }
    override init(frame:NSRect) { super.init(frame:frame); setAccessibilityRole(.slider); setAccessibilityMinValue(0); setAccessibilityMaxValue(1) }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ dirtyRect:NSRect) {
        let track = NSRect(x:10,y:bounds.midY-6,width:bounds.width-20,height:12)
        let path = NSBezierPath(roundedRect:track,xRadius:6,yRadius:6)
        let colors = (0...12).map { NSColor(calibratedHue:CGFloat($0)/12,saturation:0.75,brightness:1,alpha:1) }
        NSGradient(colors:colors)?.draw(in:path,angle:0)
        NSColor.white.setFill()
        NSBezierPath(ovalIn:NSRect(x:10+hue*(bounds.width-20)-10,y:bounds.midY-10,width:20,height:20)).fill()
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self)
        func update(_ event:NSEvent) {
            hue = min(1,max(0,(convert(event.locationInWindow,from:nil).x-10)/max(1,bounds.width-20))); changed?(hue)
        }
        update(event)
        while let next = window?.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]) {
            update(next); if next.type == .leftMouseUp { break }
        }
    }
    override func keyDown(with event:NSEvent) {
        if [123,124].contains(event.keyCode) { hue = min(1,max(0,hue+(event.keyCode == 124 ? 0.015 : -0.015))); changed?(hue) }
        else { super.keyDown(with:event) }
    }
}

final class PortraitCapture: NSObject, NSPopoverDelegate {
    let tabID:String
    private let screenshot:NSImage
    private let popover = NSPopover()
    private let preview = NSImageView()
    private var color:NSColor
    private let language:String
    private weak var parent:NSWindow?
    var closed:((String)->Void)?
    var copied:(()->Void)?
    var failed:((String)->Void)?
    private var notified = false

    init(tabID:String,image:NSImage,color:NSColor,language:String) {
        self.tabID = tabID; screenshot = image; self.color = color; self.language = language
        super.init()
        let surface = SplitFlippedView(frame:NSRect(x:0,y:0,width:360,height:310))
        surface.wantsLayer = true; surface.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let title = NSTextField(labelWithString:language == "fr" ? "Capture en mode portrait" : "Capture in Portrait Mode")
        title.font = .systemFont(ofSize:14,weight:.semibold); title.alignment = .center; title.frame = NSRect(x:14,y:15,width:332,height:22); surface.addSubview(title)
        preview.frame = NSRect(x:14,y:47,width:332,height:190); preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true; preview.layer?.cornerRadius = 9; preview.layer?.masksToBounds = true; surface.addSubview(preview)
        let hue = PortraitHueSlider(frame:NSRect(x:49,y:240,width:262,height:28))
        hue.hue = (color.usingColorSpace(.deviceRGB) ?? .systemPink).hueComponent
        hue.setAccessibilityLabel(language == "fr" ? "Couleur de l’arrière-plan" : "Background color")
        hue.changed = { [weak self] value in self?.setColor(NSColor(calibratedHue:value,saturation:0.62,brightness:0.95,alpha:1)) }
        surface.addSubview(hue)
        for (x,value,name) in [(CGFloat(15),NSColor(white:0.10,alpha:1),language == "fr" ? "Fond sombre" : "Dark background"),(CGFloat(321),NSColor(white:0.86,alpha:1),language == "fr" ? "Fond clair" : "Light background")] {
            let button = ActionButton(action:{ [weak self] in self?.setColor(value) })
            button.frame = NSRect(x:x,y:244,width:24,height:24); button.wantsLayer = true; button.layer?.cornerRadius = 12
            button.layer?.backgroundColor = value.cgColor; button.layer?.borderWidth = 1; button.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
            button.toolTip = name; button.setAccessibilityLabel(name); surface.addSubview(button)
        }
        let copy = ActionButton(language == "fr" ? "Copier" : "Copy",symbol:"doc.on.doc") { [weak self] in self?.copyImage() }
        let save = ActionButton(language == "fr" ? "Enregistrer…" : "Save…",symbol:"square.and.arrow.down") { [weak self] in self?.saveImage() }
        for (index,button) in [copy,save].enumerated() {
            button.isBordered = true; button.bezelStyle = .rounded; button.frame = NSRect(x:14+CGFloat(index)*170,y:274,width:162,height:26); surface.addSubview(button)
        }
        let controller = NSViewController(); controller.view = surface
        popover.contentViewController = controller; popover.contentSize = surface.bounds.size
        popover.behavior = .transient; popover.appearance = NSAppearance(named:.darkAqua); popover.delegate = self
        refreshPreview()
    }
    private func setColor(_ value:NSColor) { color = value; refreshPreview() }
    private func refreshPreview() { preview.image = PortraitRenderer.image(screenshot,color:color,maxWidth:640) }
    func show(of anchor:NSView,rect:NSRect? = nil) { parent = anchor.window; popover.show(relativeTo:rect ?? anchor.bounds,of:anchor,preferredEdge:rect == nil ? .maxY : .minY) }
    func close() { popover.close(); notifyClosed() }
    func popoverDidClose(_ notification:Notification) { notifyClosed() }
    private func notifyClosed() { guard !notified else { return }; notified = true; closed?(color.themeHex) }
    private func renderedPNG() -> Data? { PortraitRenderer.image(screenshot,color:color).flatMap(PortraitRenderer.png) }
    private func copyImage() {
        guard let data = renderedPNG() else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data,forType:.png)
        close(); copied?()
    }
    private func saveImage() {
        guard let data = renderedPNG(), let parent else { return }
        let report = failed
        close()
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "Browser-capture.png"
        panel.beginSheetModal(for:parent) { response in
            guard response == .OK, let url = panel.url else { return }
            do { try data.write(to:url,options:.atomic) } catch { report?(error.localizedDescription) }
        }
    }
}
