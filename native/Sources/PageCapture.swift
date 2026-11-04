import AppKit
import CoreImage
import UniformTypeIdentifiers

private final class CaptureMenuRow: NSButton {
    let symbol:String
    var invoke:(()->Void)?
    var active = false { didSet { needsDisplay = true } }
    init(_ title:String,symbol:String,action:@escaping ()->Void) {
        self.symbol = symbol; super.init(frame:.zero); self.title = title; invoke = action
        isBordered = false; target = self; self.action = #selector(run); setAccessibilityLabel(title)
    }
    required init?(coder:NSCoder) { fatalError() }
    override var isFlipped:Bool { true }
    @objc private func run() { invoke?() }
    override func draw(_ dirtyRect:NSRect) {
        if active || isHighlighted { NSColor.white.withAlphaComponent(0.10).setFill(); NSBezierPath(roundedRect:bounds,xRadius:9,yRadius:9).fill() }
        let image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:16,weight:.regular).applying(.init(paletteColors:[.white.withAlphaComponent(0.7)])))
        image?.draw(in:NSRect(x:12,y:13,width:19,height:19),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        (title as NSString).draw(at:NSPoint(x:44,y:13),withAttributes:[.font:NSFont.systemFont(ofSize:14,weight:.medium),.foregroundColor:NSColor.white.withAlphaComponent(0.95)])
    }
    override func updateTrackingAreas() { super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea); addTrackingArea(NSTrackingArea(rect:bounds,options:[.activeInKeyWindow,.mouseEnteredAndExited,.inVisibleRect],owner:self)) }
    override func mouseEntered(with event:NSEvent) { active = true }
    override func mouseExited(with event:NSEvent) { active = false }
}

private final class CaptureActionPanel: NSVisualEffectView, NSTextFieldDelegate {
    private let search = NSTextField()
    private var rows:[CaptureMenuRow] = []
    private var index = 0
    var sizeChanged:(()->Void)?
    var preferredHeight:CGFloat { CGFloat(rows.filter { !$0.isHidden }.count)*46+132 }
    override var isFlipped:Bool { true }
    init(image:NSImage,fr:Bool,action:@escaping (String)->Void) {
        super.init(frame:.zero); material = .popover; blendingMode = .withinWindow; state = .active; appearance = NSAppearance(named:.darkAqua)
        wantsLayer = true; layer?.cornerRadius = 19; layer?.masksToBounds = true
        layer?.borderWidth = 0.7; layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
        let wash = CaptureSurface(frame:bounds); wash.autoresizingMask = [.width,.height]; wash.wantsLayer = true
        wash.layer?.backgroundColor = NSColor(srgbRed:0.075,green:0.06,blue:0.14,alpha:0.92).cgColor; addSubview(wash)
        let preview = NSImageView(frame:CGRect(x:16,y:16,width:64,height:44)); preview.image = image; preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true; preview.layer?.cornerRadius = 6; preview.layer?.masksToBounds = true; addSubview(preview)
        let title = NSTextField(labelWithString:fr ? "Votre capture est prête" : "Your capture is ready")
        title.font = .systemFont(ofSize:13,weight:.semibold); title.textColor = .white; title.frame = CGRect(x:92,y:18,width:224,height:20); addSubview(title)
        let detail = NSTextField(labelWithString:"\(Int(image.size.width)) × \(Int(image.size.height)) px")
        detail.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular); detail.textColor = .secondaryLabelColor; detail.frame = CGRect(x:92,y:40,width:200,height:18); addSubview(detail)
        search.placeholderString = fr ? "Rechercher une action…" : "Find an action…"; search.font = .systemFont(ofSize:14)
        search.isBordered = false; search.drawsBackground = false; search.focusRingType = .none; search.delegate = self; search.textColor = .white
        let field = CaptureSurface(frame:CGRect(x:12,y:74,width:312,height:36)); field.wantsLayer = true; field.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor; field.layer?.cornerRadius = 9
        search.frame = CGRect(x:12,y:8,width:288,height:22); field.addSubview(search); addSubview(field)
        let actions:[(String,String,String)] = [
            ("library",fr ? "Enregistrer dans la bibliothèque" : "Save to Library","photo.on.rectangle"),
            ("copy",fr ? "Copier" : "Copy","doc.on.doc"),
            ("save",fr ? "Enregistrer sous…" : "Save As…","square.and.arrow.down"),
            ("message",fr ? "Envoyer via Messages…" : "Send via Messages…","message"),
            ("share",fr ? "Partager…" : "Share…","square.and.arrow.up"),
            ("edit",fr ? "Modifier la capture" : "Edit capture","pencil.tip.crop.circle"),
            ("retake",fr ? "Reprendre la capture" : "Retake","arrow.counterclockwise")
        ]
        for (id,title,symbol) in actions {
            if id == "message" && NSSharingService(named:.composeMessage) == nil { continue }
            let row = CaptureMenuRow(title,symbol:symbol) { action(id) }; rows.append(row); addSubview(row)
        }
    }
    required init?(coder:NSCoder) { fatalError() }
    func focus() { window?.makeFirstResponder(search) }
    func controlTextDidChange(_ obj:Notification) {
        let query = search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        for row in rows { row.isHidden = !query.isEmpty && !row.title.localizedStandardContains(query); row.active = false }
        index = 0; needsLayout = true; sizeChanged?()
    }
    func control(_ control:NSControl,textView:NSTextView,doCommandBy selector:Selector) -> Bool {
        let visible = rows.filter { !$0.isHidden }; guard !visible.isEmpty else { return false }
        if selector == #selector(NSResponder.moveDown(_:)) || selector == #selector(NSResponder.moveUp(_:)) {
            index = (index+(selector == #selector(NSResponder.moveDown(_:)) ? 1 : visible.count-1))%visible.count
            for (i,row) in visible.enumerated() { row.active = i == index }; return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) { visible[min(index,visible.count-1)].invoke?(); return true }
        return false
    }
    override func layout() { super.layout(); var y:CGFloat = 120; for row in rows where !row.isHidden { row.frame = CGRect(x:10,y:y,width:bounds.width-20,height:44); y += 46 } }
}

// The instruction never participates in hit testing: selections can begin beneath it.
private final class CaptureHint: CaptureSurface {
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
}

private final class CaptureOverlay: CaptureSurface {
    private(set) var image:NSImage
    var pageRect:CGRect = .zero { didSet { needsLayout = true } }
    private(set) var selection:CGRect?
    private(set) var selecting = true
    private(set) var scrolling = false
    private var busy = false
    var hover:((CGPoint?)->Void)?
    var captured:((CGRect)->Void)?
    var scrolled:((CGPoint?,NSEvent)->Void)?
    var fullPage:(()->Void)?
    var cancel:(()->Void)?
    private let fr:Bool
    private var start:CGPoint?
    private var dragged = false
    private var targetRadius:CGFloat = 10
    private let hint = NSTextField(labelWithString:"")
    private let help = NSTextField(labelWithString:"")
    private let capsule = CaptureHint()
    private var hintHidden = false
    private var close:CaptureButton!
    private var wholePage:CaptureButton!
    private let snapshot = CALayer()
    private let highlight = CALayer()
    private let shape = CAShapeLayer()
    private let outline = CAShapeLayer()
    private static let context = CIContext()
    private static let cameraCursor:NSCursor = {
        let image = NSImage(size:NSSize(width:36,height:36),flipped:true) { _ in
            let shadow = NSShadow(); shadow.shadowColor = .black; shadow.shadowBlurRadius = 2; shadow.set()
            NSColor.white.setStroke(); let cross = NSBezierPath(); cross.lineWidth = 1.5
            cross.move(to:CGPoint(x:1,y:7)); cross.line(to:CGPoint(x:13,y:7)); cross.move(to:CGPoint(x:7,y:1)); cross.line(to:CGPoint(x:7,y:13)); cross.stroke()
            let camera = NSImage(systemSymbolName:"camera",accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[.white]))
            camera?.draw(in:CGRect(x:12,y:12,width:23,height:20),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil); return true
        }
        return NSCursor(image:image,hotSpot:NSPoint(x:7,y:7))
    }()
    init(image:NSImage,fr:Bool) {
        self.image = image; self.fr = fr
        super.init(frame:.zero); wantsLayer = true
        layer?.addSublayer(snapshot); layer?.addSublayer(highlight); layer?.addSublayer(outline)
        snapshot.name = "capture.snapshot"; highlight.name = "capture.highlight"; shape.name = "capture.mask"; outline.name = "capture.outline"
        snapshot.opacity = 0.65
        highlight.mask = shape; shape.fillColor = NSColor.white.cgColor
        outline.fillColor = nil; outline.strokeColor = NSColor(srgbRed:0.25,green:0.31,blue:0.48,alpha:0.95).cgColor
        outline.lineWidth = 1; outline.shadowColor = NSColor(srgbRed:0.08,green:0.12,blue:0.23,alpha:1).cgColor
        outline.shadowOpacity = 0.8; outline.shadowRadius = 3; outline.shadowOffset = .zero
        highlight.opacity = 0; outline.opacity = 0
        replaceImage(image)
        capsule.wantsLayer = true; capsule.layer?.cornerRadius = 14; capsule.layer?.backgroundColor = NSColor.white.cgColor
        capsule.layer?.shadowColor = NSColor.black.cgColor; capsule.layer?.shadowOpacity = 0.22; capsule.layer?.shadowRadius = 18
        hint.font = .systemFont(ofSize:12,weight:.semibold); hint.textColor = NSColor(srgbRed:0.36,green:0.24,blue:0.73,alpha:1); hint.alignment = .center
        hint.lineBreakMode = .byTruncatingTail
        help.stringValue = fr ? "Échap pour annuler" : "Escape to cancel"; help.font = .systemFont(ofSize:10); help.textColor = NSColor(white:0.45,alpha:1); help.alignment = .center
        capsule.addSubview(hint); capsule.addSubview(help); addSubview(capsule)
        close = CaptureButton(fr ? "Annuler la capture" : "Cancel capture",symbol:"xmark") { [weak self] in self?.cancel?() }; addSubview(close)
        wholePage = CaptureButton(fr ? "Toute la page" : "Entire page") { [weak self] in self?.fullPage?() }
        wholePage.wantsLayer = true; wholePage.layer?.backgroundColor = NSColor(srgbRed:0.10,green:0.09,blue:0.18,alpha:0.94).cgColor
        wholePage.layer?.cornerRadius = 11; wholePage.layer?.borderWidth = 0.5; wholePage.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        wholePage.toolTip = fr ? "Capturer la page entière, de haut en bas" : "Capture the entire page, from top to bottom"
        addSubview(wholePage); updateHint()
    }
    required init?(coder:NSCoder) { fatalError() }
    override var acceptsFirstResponder:Bool { true }
    func replaceImage(_ image:NSImage) {
        self.image = image
        guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return }
        image.size = NSSize(width:cg.width,height:cg.height)
        var gray = cg
        if let filter = CIFilter(name:"CIColorControls") {
            filter.setValue(CIImage(cgImage:cg),forKey:kCIInputImageKey); filter.setValue(0,forKey:kCIInputSaturationKey); filter.setValue(-0.10,forKey:kCIInputBrightnessKey)
            if let output = filter.outputImage, let result = Self.context.createCGImage(output,from:output.extent) { gray = result }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        snapshot.contents = gray; highlight.contents = cg
        snapshot.isHidden = false; CATransaction.commit()
        scrolling = false; wholePage?.isEnabled = !busy; updateHint(); needsDisplay = true
    }
    func beginScrolling() {
        scrolling = true; start = nil; setSelection(nil,animated:false)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        snapshot.removeAllAnimations(); snapshot.isHidden = true
        CATransaction.commit()
        wholePage.isEnabled = false; updateHint(); needsDisplay = true
    }
    func setBusy(_ value:Bool) { busy = value; wholePage.isEnabled = !value; updateHint() }
    func setSelecting(_ value:Bool) {
        selecting = value; capsule.isHidden = !value; close.isHidden = !value; wholePage.isHidden = !value
        window?.invalidateCursorRects(for:self); needsDisplay = true
    }
    private func updateHint() {
        let text:String
        if busy { text = fr ? "Capture de toute la page…" : "Capturing the entire page…" }
        else if selection != nil && !dragged && !scrolling { text = fr ? "Cliquez pour capturer cet élément" : "Click to capture this element" }
        else { text = fr ? "Faites glisser pour capturer une zone" : "Drag to capture an area" }
        guard hint.stringValue != text else { return }
        hint.stringValue = text
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CATransition(); fade.type = .fade; fade.duration = 0.14; hint.layer?.add(fade,forKey:"hint.text")
        }
    }
    private func updateHintVisibility(at point:CGPoint?) {
        let hidden = point.map { capsule.frame.insetBy(dx:-8,dy:-8).contains($0) } ?? false
        guard hidden != hintHidden else { return }; hintHidden = hidden
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : (hidden ? 0.16 : 0.24)
            context.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
            capsule.animator().alphaValue = hidden ? 0.04 : 1
        }
    }
    override func resetCursorRects() { if selecting { addCursorRect(pageRect,cursor:Self.cameraCursor) } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect:bounds,options:[.activeInKeyWindow,.mouseMoved,.mouseEnteredAndExited,.inVisibleRect,.enabledDuringMouseDrag],owner:self))
    }
    override func mouseExited(with event:NSEvent) { if start == nil { hover?(nil); showTarget(nil); updateHintVisibility(at:nil) } }
    override func mouseMoved(with event:NSEvent) {
        guard selecting, start == nil else { return }
        let p = convert(event.locationInWindow,from:nil); updateHintVisibility(at:p)
        // Stop locally on exit; do not wait for an asynchronous DOM hit test.
        if let selection, !selection.contains(p) { setSelection(nil,animated:false) }
        if pageRect.contains(p), !wholePage.frame.contains(p), !close.frame.contains(p) {
            hover?(CGPoint(x:(p.x-pageRect.minX)/pageRect.width,y:(p.y-pageRect.minY)/pageRect.height))
        } else { hover?(nil); showTarget(nil) }
    }
    override func scrollWheel(with event:NSEvent) {
        guard selecting, !busy, start == nil else { return }
        let p = convert(event.locationInWindow,from:nil)
        let inside = pageRect.contains(p); guard inside || scrolling else { return }
        // Zero-delta phase/momentum endings are essential to native scrolling.
        guard abs(event.scrollingDeltaX)+abs(event.scrollingDeltaY)>0 || event.phase != [] || event.momentumPhase != [] else { return }
        updateHintVisibility(at:p)
        let point = inside ? CGPoint(x:(p.x-pageRect.minX)/pageRect.width,y:(p.y-pageRect.minY)/pageRect.height) : nil
        scrolled?(point,event)
    }
    override func mouseDown(with event:NSEvent) {
        guard selecting, !scrolling, !busy else { return }; let p = convert(event.locationInWindow,from:nil)
        guard pageRect.contains(p) else { return }; start = p; dragged = false; window?.makeFirstResponder(self)
    }
    override func mouseDragged(with event:NSEvent) {
        guard selecting, let start else { return }; var p = convert(event.locationInWindow,from:nil)
        p.x = min(pageRect.maxX,max(pageRect.minX,p.x)); p.y = min(pageRect.maxY,max(pageRect.minY,p.y)); updateHintVisibility(at:p)
        guard dragged || hypot(p.x-start.x,p.y-start.y)>4 else { return }; dragged = true
        setSelection(CGRect(x:min(p.x,start.x),y:min(p.y,start.y),width:abs(p.x-start.x),height:abs(p.y-start.y)),animated:false)
    }
    override func mouseUp(with event:NSEvent) {
        defer { start = nil; dragged = false }
        guard selecting, !scrolling, !busy, start != nil, let rect = selection?.intersection(pageRect), !rect.isNull, rect.width >= 3, rect.height >= 3 else { return }
        captured?(CGRect(x:(rect.minX-pageRect.minX)/pageRect.width,y:(rect.minY-pageRect.minY)/pageRect.height,width:rect.width/pageRect.width,height:rect.height/pageRect.height))
    }
    func showTarget(_ normalized:CGRect?,radius:CGFloat = 0) {
        guard selecting, start == nil, !scrolling, !busy else { return }
        targetRadius = radius.isFinite ? max(0,radius*pageRect.width) : 0
        setSelection(normalized.map { CGRect(x:pageRect.minX+$0.minX*pageRect.width,y:pageRect.minY+$0.minY*pageRect.height,width:$0.width*pageRect.width,height:$0.height*pageRect.height) },animated:true)
    }
    private func setSelection(_ rect:CGRect?,animated:Bool) {
        if rect == nil {
            selection = nil
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for target in [highlight,shape,outline] { target.removeAllAnimations() }
            highlight.isHidden = true; outline.isHidden = true
            highlight.opacity = 0; outline.opacity = 0; shape.path = nil; outline.path = nil
            CATransaction.commit()
            updateHint(); needsDisplay = true; return
        }
        guard rect != selection else { return }
        let previous = selection; selection = rect; updateHint(); needsDisplay = true
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let oldPath = shape.presentation()?.path ?? shape.path
        let oldOpacity = highlight.presentation()?.opacity ?? highlight.opacity
        let oldOutlineOpacity = outline.presentation()?.opacity ?? outline.opacity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        highlight.isHidden = false; outline.isHidden = false
        highlight.opacity = 1; outline.opacity = 1
        if let rect {
            let local = rect.offsetBy(dx:-pageRect.minX,dy:-pageRect.minY)
            let radius = dragged ? 3 : min(targetRadius,min(local.width,local.height)/2)
            let path = CGPath(roundedRect:local,cornerWidth:radius,cornerHeight:radius,transform:nil)
            shape.path = path; outline.path = path
            shape.removeAllAnimations(); outline.removeAllAnimations(); highlight.removeAllAnimations()
            if animate {
                if previous != nil, let oldPath {
                    for target in [shape,outline] {
                        let move = CABasicAnimation(keyPath:"path"); move.fromValue = oldPath; move.toValue = path; move.duration = 0.14
                        move.timingFunction = CAMediaTimingFunction(controlPoints:0.2,0.8,0.2,1); target.add(move,forKey:"capture.retarget")
                    }
                }
                if previous == nil {
                    let seed = CGRect(x:local.minX,y:local.minY,width:1,height:local.height)
                    let fill = CABasicAnimation(keyPath:"path"); fill.fromValue = CGPath(roundedRect:seed,cornerWidth:radius,cornerHeight:radius,transform:nil); fill.toValue = path; fill.duration = 0.38
                    fill.timingFunction = CAMediaTimingFunction(controlPoints:0.2,0.65,0.25,1); shape.add(fill,forKey:"capture.fill")
                }
                let color = CABasicAnimation(keyPath:"opacity"); color.fromValue = previous == nil ? 0.15 : oldOpacity; color.toValue = 1; color.duration = 0.38
                color.timingFunction = CAMediaTimingFunction(controlPoints:0.2,0.65,0.25,1); highlight.add(color,forKey:"capture.color")
                let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = previous == nil ? 0 : oldOutlineOpacity; fade.toValue = 1; fade.duration = 0.16; outline.add(fade,forKey:"capture.border")
            }
        }
        CATransaction.commit()
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.black.withAlphaComponent(0.48).setFill(); bounds.fill()
        if dragged, let rect = selection {
            let text = "\(Int(rect.width/pageRect.width*image.size.width)) × \(Int(rect.height/pageRect.height*image.size.height))"
            let attrs:[NSAttributedString.Key:Any] = [.font:NSFont.monospacedDigitSystemFont(ofSize:10,weight:.medium),.foregroundColor:NSColor.white]
            let size = (text as NSString).size(withAttributes:attrs), label = CGRect(x:rect.minX+5,y:max(pageRect.minY+4,rect.minY-25),width:size.width+14,height:20)
            NSColor(white:0.08,alpha:0.9).setFill(); NSBezierPath(roundedRect:label,xRadius:5,yRadius:5).fill(); (text as NSString).draw(at:CGPoint(x:label.minX+7,y:label.minY+4),withAttributes:attrs)
        }
    }
    override func layout() {
        super.layout(); let width = min(350,max(180,pageRect.width-32))
        capsule.frame = CGRect(x:pageRect.midX-width/2,y:max(pageRect.minY+40,pageRect.maxY-76),width:width,height:50)
        hint.frame = CGRect(x:12,y:9,width:width-24,height:18); help.frame = CGRect(x:12,y:29,width:width-24,height:14)
        close.frame = CGRect(x:pageRect.maxX-50,y:pageRect.minY+12,width:38,height:38)
        wholePage.frame = CGRect(x:max(pageRect.minX+12,pageRect.maxX-180),y:pageRect.minY+14,width:124,height:34)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        snapshot.frame = pageRect; highlight.frame = pageRect; shape.frame = highlight.bounds
        outline.frame = pageRect
        CATransaction.commit()
    }
}

final class PageCapture: NSObject {
    let tabID:String
    private let engine:BrowserEngine
    private weak var parent:NSWindow?
    private weak var page:NSView?
    private let fr:Bool
    private var overlay:CaptureOverlay?
    private var panel:CaptureActionPanel?
    private var editor:CaptureEditor?
    private var document:CaptureDocument?
    private var beforeEditing:CaptureDocument.Snapshot?
    private var monitor:Any?, resizeObserver:NSObjectProtocol?
    private var pageObserver:NSObjectProtocol?
    private var generation = 0
    private var queryPending = false
    private var pointer:CGPoint?
    private var lastQuery:CGPoint?
    private weak var scrollTarget:NSView?
    private var refreshWork:DispatchWorkItem?
    private var capturingFullPage = false
    private var sound:NSSound?
    private var sharing:NSSharingServicePicker?
    private var sharingService:NSSharingService?
    private weak var previousResponder:NSResponder?
    private var ended = false
    var saved:((Data)throws->Void)?
    var notice:((String)->Void)?
    var failed:((String)->Void)?
    var closed:(()->Void)?
    init(tabID:String,engine:BrowserEngine,window:NSWindow,language:String) { self.tabID = tabID; self.engine = engine; parent = window; fr = language == "fr"; super.init() }
    func start(fullPage:Bool = false) {
        guard !ended, let parent, let root = parent.contentView, let page = engine.captureView(forTab:tabID), page.window === parent, !page.isHiddenOrHasHiddenAncestor else { close(); return }
        self.page = page; if monitor == nil { previousResponder = parent.firstResponder }
        generation += 1; let token = generation
        engine.capturePage(tabID) { [weak self,weak root,weak page] data in
            guard let self, !self.ended, self.generation == token, let root, let page, !page.isHiddenOrHasHiddenAncestor else { return }
            guard let data, let image = NSImage(data:data) else { self.close(); self.failed?(self.fr ? "La capture de cette page a échoué." : "Could not capture this page."); return }
            let captured = CaptureDocument(image:image).original
            if let cg = captured.cgImage(forProposedRect:nil,context:nil,hints:nil) { captured.size = NSSize(width:cg.width,height:cg.height) }
            let overlay = CaptureOverlay(image:captured,fr:self.fr); self.overlay = overlay
            overlay.frame = root.bounds; overlay.autoresizingMask = [.width,.height]; root.addSubview(overlay,positioned:.above,relativeTo:nil)
            overlay.pageRect = overlay.convert(page.bounds,from:page); overlay.needsLayout = true
            overlay.hover = { [weak self] p in self?.pointer = p; if p == nil { self?.lastQuery = nil }; self?.queryTarget() }
            overlay.captured = { [weak self] rect in self?.take(rect) }; overlay.cancel = { [weak self] in self?.close() }
            overlay.scrolled = { [weak self] point,event in self?.scroll(at:point,event:event) }
            overlay.fullPage = { [weak self] in self?.takeFullPage() }
            self.engine.setPageInputSuppressed(true,forTab:self.tabID); parent.makeFirstResponder(overlay)
            page.postsFrameChangedNotifications = true
            self.pageObserver = NotificationCenter.default.addObserver(forName:NSView.frameDidChangeNotification,object:page,queue:.main) { [weak self] _ in
                guard let self, self.document == nil else { return }; self.close()
            }
            self.installEvents(); if fullPage { self.takeFullPage() } else { self.animateIn(overlay) }
        }
    }
    private func installEvents() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self, event.window === self.parent, self.parent?.attachedSheet == nil else { return event }
            if event.keyCode == 53 {
                if let editor = self.editor {
                    if self.parent?.firstResponder is NSTextView { return event }
                    editor.canvas.commitText(); if let snapshot = self.beforeEditing { self.document?.restore(snapshot) }; self.showActions()
                } else { self.close() }
                return nil
            }
            return event
        }
        if let parent {
            resizeObserver = NotificationCenter.default.addObserver(forName:NSWindow.didResizeNotification,object:parent,queue:.main) { [weak self] _ in
                guard let self else { return }
                if self.document == nil { self.close() } else { self.layoutPanels() }
            }
        }
    }
    private func queryTarget() {
        guard !queryPending, let p = pointer, overlay?.selecting == true, overlay?.scrolling == false, !capturingFullPage, !ended else { return }
        if let lastQuery, hypot(p.x-lastQuery.x,p.y-lastQuery.y)<0.002 { return }
        lastQuery = p; queryPending = true; let token = generation
        engine.captureElement(at:p,forTab:tabID) { [weak self] result in
            guard let self, !self.ended, self.generation == token else { return }; self.queryPending = false
            if self.pointer == p {
                let rect = result.flatMap { r -> CGRect? in
                    guard let x = r["x"] as? Double, let y = r["y"] as? Double, let w = r["width"] as? Double, let h = r["height"] as? Double else { return nil }
                    return CGRect(x:x,y:y,width:w,height:h)
                }
                self.overlay?.showTarget(rect,radius:CGFloat((result?["radius"] as? Double) ?? 0))
            } else { self.queryTarget() }
        }
    }
    private func take(_ rect:CGRect) {
        guard let overlay, let image = CaptureDocument.crop(overlay.image,normalized:rect) else { return }
        finishCapture(image)
    }
    private func takeFullPage() {
        guard let overlay, overlay.selecting, !overlay.scrolling, !capturingFullPage, !ended else { return }
        capturingFullPage = true; overlay.setBusy(true)
        generation += 1; let token = generation
        engine.captureFullPage(tabID) { [weak self,weak overlay] data in
            guard let self, let overlay, !self.ended, self.generation == token else { return }
            self.capturingFullPage = false; overlay.setBusy(false)
            guard let data, let image = NSImage(data:data) else {
                self.queryPending = false; self.lastQuery = nil; self.queryTarget()
                self.failed?(self.fr ? "Impossible de capturer toute cette page." : "Could not capture the entire page."); return
            }
            if let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) { image.size = NSSize(width:cg.width,height:cg.height) }
            self.finishCapture(image)
        }
    }
    private func finishCapture(_ image:NSImage) {
        guard let overlay else { return }
        document = CaptureDocument(image:image); overlay.setSelecting(false)
        sound = NSSound(contentsOfFile:"/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",byReference:true); sound?.play()
        let flash = CaptureSurface(frame:overlay.pageRect); flash.wantsLayer = true; flash.layer?.backgroundColor = NSColor.white.cgColor; flash.alphaValue = 0.22; overlay.addSubview(flash)
        NSAnimationContext.runAnimationGroup { context in context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18; flash.animator().alphaValue = 0 } completionHandler: { flash.removeFromSuperview() }
        showActions()
    }
    private func scroll(at point:CGPoint?,event:NSEvent) {
        guard let overlay, let page, let container = page.superview, overlay.selecting, !capturingFullPage, !ended else { return }
        if scrollTarget == nil {
            // Hit-test the page subtree directly, bypassing only the capture
            // overlay. The original NSEvent retains precise deltas and phases.
            let location = container.convert(event.locationInWindow,from:nil)
            scrollTarget = page.hitTest(location)
        }
        guard let target = scrollTarget, target.isDescendant(of:page) || target === page else { return }
        generation += 1; queryPending = false; lastQuery = nil; pointer = point
        refreshWork?.cancel(); refreshWork = nil
        overlay.beginScrolling()
        // The overlay still consumes all clicks and keyboard input.
        engine.setPageInputSuppressed(false,forTab:tabID)
        target.scrollWheel(with:event)
        let activePhases:NSEvent.Phase = [.mayBegin,.began,.changed,.stationary]
        guard event.phase.intersection(activePhases).isEmpty, event.momentumPhase.intersection(activePhases).isEmpty else { return }
        let token = generation
        let work = DispatchWorkItem { [weak self,weak overlay] in
            guard let self, let overlay, !self.ended, self.generation == token else { return }
            self.engine.capturePage(self.tabID) { [weak self,weak overlay] data in
                guard let self, let overlay, !self.ended, self.generation == token else { return }
                guard let data, let image = NSImage(data:data) else { self.close(); self.failed?(self.fr ? "Impossible d’actualiser la capture." : "Could not refresh the capture."); return }
                self.engine.setPageInputSuppressed(true,forTab:self.tabID)
                self.scrollTarget = nil
                overlay.replaceImage(image); self.lastQuery = nil; self.queryTarget()
            }
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline:.now()+0.12,execute:work)
    }
    private func showActions() {
        guard let overlay, let image = document?.rendered() else { return }
        editor?.removeFromSuperview(); editor = nil; panel?.removeFromSuperview()
        let panel = CaptureActionPanel(image:image,fr:fr) { [weak self] action in self?.perform(action) }; self.panel = panel
        panel.sizeChanged = { [weak self] in self?.layoutPanels() }
        overlay.addSubview(panel); layoutPanels(); animateIn(panel); panel.focus()
    }
    private func perform(_ action:String) {
        guard let document, let image = document.rendered(), let parent else { return }
        switch action {
        case "edit":
            beforeEditing = document.snapshot(); panel?.removeFromSuperview(); panel = nil
            let editor = CaptureEditor(document:document,language:fr ? "fr" : "en"); self.editor = editor; overlay?.addSubview(editor)
            editor.done = { [weak self] in self?.showActions() }
            editor.cancel = { [weak self] in guard let self else { return }; if let snapshot = self.beforeEditing { self.document?.restore(snapshot) }; self.showActions() }
            layoutPanels(); animateIn(editor); parent.makeFirstResponder(editor.canvas)
        case "retake":
            removeOverlay(); self.document = nil; pointer = nil; lastQuery = nil; queryPending = false; start()
        case "copy":
            guard let data = CaptureDocument.png(image) else { return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data,forType:.png)
            close(); notice?(fr ? "Capture copiée" : "Capture copied")
        case "library":
            do { guard let data = CaptureDocument.png(image), let saved else { return }; try saved(data); close(); notice?(fr ? "Capture enregistrée dans la bibliothèque" : "Capture saved to Library") }
            catch { failed?(error.localizedDescription) }
        case "save":
            let save = NSSavePanel(); save.allowedContentTypes = [.png]; save.nameFieldStringValue = "Browser-capture.png"
            save.beginSheetModal(for:parent) { [weak self] response in
                guard let self, !self.ended, response == .OK, let url = save.url else { return }
                do { guard let data = CaptureDocument.png(image) else { return }; try data.write(to:url,options:.atomic); self.close(); self.notice?(self.fr ? "Capture enregistrée" : "Capture saved") }
                catch { self.failed?(error.localizedDescription) }
            }
        case "message":
            if let service = NSSharingService(named:.composeMessage) { sharingService = service; service.perform(withItems:[image]); close() }
        case "share":
            guard let panel else { return }; let picker = NSSharingServicePicker(items:[image]); sharing = picker
            picker.show(relativeTo:panel.bounds,of:panel,preferredEdge:.maxX)
        default: break
        }
    }
    private func layoutPanels() {
        guard let overlay else { return }
        if let panel { panel.frame = CGRect(x:(overlay.bounds.width-336)/2,y:max(16,(overlay.bounds.height-panel.preferredHeight)/2),width:336,height:panel.preferredHeight) }
        if let editor { editor.frame = overlay.bounds.insetBy(dx:max(24,(overlay.bounds.width-1100)/2),dy:28); editor.needsLayout = true }
    }
    private func animateIn(_ view:NSView) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        view.wantsLayer = true
        let opacity = CABasicAnimation(keyPath:"opacity"); opacity.fromValue = 0; opacity.toValue = 1; opacity.duration = 0.16; view.layer?.add(opacity,forKey:"capture.appear")
        if view !== overlay {
            let slide = CASpringAnimation(keyPath:"transform.translation.y"); slide.fromValue = 10; slide.toValue = 0; slide.mass = 1; slide.stiffness = 340; slide.damping = 28; slide.duration = 0.32; view.layer?.add(slide,forKey:"capture.lift")
        }
    }
    private func removeOverlay() {
        refreshWork?.cancel(); refreshWork = nil; scrollTarget = nil; capturingFullPage = false
        if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) }; pageObserver = nil
        generation += 1; editor?.removeFromSuperview(); editor = nil; panel?.removeFromSuperview(); panel = nil; overlay?.removeFromSuperview(); overlay = nil
        engine.setPageInputSuppressed(false,forTab:tabID)
    }
    func close() {
        guard !ended else { return }; ended = true
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }; resizeObserver = nil
        removeOverlay(); if let responder = previousResponder { parent?.makeFirstResponder(responder) }; closed?()
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) }; if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }; if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) } }
}
