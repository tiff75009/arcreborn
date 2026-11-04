import AppKit
import QuartzCore
import UniformTypeIdentifiers

class CaptureSurface: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

final class CaptureButton: NSButton {
    var invoke: (() -> Void)?
    var selected = false { didSet { needsDisplay = true } }
    var primary = false
    private var hovered = false
    private let symbol: String?
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        self.symbol = symbol; invoke = action
        super.init(frame:.zero); self.title = title; isBordered = false; wantsLayer = true
        target = self; self.action = #selector(activate); toolTip = title
        setAccessibilityLabel(title); font = .systemFont(ofSize:13,weight:.medium)
    }
    required init?(coder:NSCoder) { fatalError() }
    @objc private func activate() { invoke?() }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let fill = primary || selected ? NSColor(srgbRed:0.35,green:0.31,blue:0.94,alpha:1) : NSColor.white.withAlphaComponent(isHighlighted ? 0.18 : hovered ? 0.10 : 0)
        fill.setFill(); NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:2),xRadius:10,yRadius:10).fill()
        let ink = NSColor.white.withAlphaComponent(isEnabled ? 0.95 : 0.25)
        if let symbol, let image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:19,weight:.regular).applying(.init(paletteColors:[ink]))) {
            let rect = NSRect(x:bounds.midX-11,y:bounds.midY-11,width:22,height:22)
            image.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        } else {
            let attributes:[NSAttributedString.Key:Any] = [.font:font!,.foregroundColor:ink]
            let size = (title as NSString).size(withAttributes:attributes)
            (title as NSString).draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2),withAttributes:attributes)
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))
    }
    override func mouseEntered(with event:NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event:NSEvent) { hovered = false; needsDisplay = true }
    override func mouseDown(with event:NSEvent) {
        guard isEnabled else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer else { super.mouseDown(with:event); return }
        let pressed = CATransform3DScale(CATransform3DMakeTranslation(bounds.width*0.02,bounds.height*0.02,0),0.96,0.96,1)
        CATransaction.begin(); CATransaction.setDisableActions(true); layer.transform = pressed; CATransaction.commit()
        super.mouseDown(with:event)
        CATransaction.begin(); CATransaction.setDisableActions(true); layer.transform = CATransform3DIdentity; CATransaction.commit()
        let spring = CASpringAnimation(keyPath:"transform"); spring.fromValue = NSValue(caTransform3D:pressed); spring.toValue = NSValue(caTransform3D:CATransform3DIdentity); spring.stiffness = 400; spring.damping = 25; spring.duration = 0.28; layer.add(spring,forKey:"capture.press")
    }
}

final class CaptureCanvas: CaptureSurface, NSTextFieldDelegate {
    let document: CaptureDocument
    var tool: CaptureTool = .select { didSet { commitText(); window?.invalidateCursorRects(for:self); needsDisplay = true } }
    var color: NSColor = .systemRed
    var stroke: CGFloat = 4
    var filled = false
    var fontSize: CGFloat = 36
    var bold = true
    var changed: (() -> Void)?
    var chooseImage: (() -> Void)?
    var toolChanged: ((CaptureTool) -> Void)?
    var selected: UUID? { didSet { needsDisplay = true } }
    private var start: CGPoint?
    private var initial: CaptureMark?
    private var resizeCorner: Int?
    private var didCheckpoint = false
    private var textEditor: NSTextField?
    private var editingID: UUID?
    private var editingMark: CaptureMark?
    var selection: CaptureMark? { selectedIndex.map { document.marks[$0] } }
    private var scale: CGFloat { max(0.01,min((bounds.width-40)/document.size.width,(bounds.height-40)/document.size.height)) }
    var imageRect: CGRect { CGRect(x:(bounds.width-document.size.width*scale)/2,y:(bounds.height-document.size.height*scale)/2,width:document.size.width*scale,height:document.size.height*scale) }
    private func point(_ event: NSEvent) -> CGPoint { let p = convert(event.locationInWindow,from:nil); return CGPoint(x:(p.x-imageRect.minX)/scale,y:(p.y-imageRect.minY)/scale) }
    private func screen(_ rect: CGRect) -> CGRect { CGRect(x:imageRect.minX+rect.minX*scale,y:imageRect.minY+rect.minY*scale,width:rect.width*scale,height:rect.height*scale) }
    private var selectedIndex: Int? { document.marks.firstIndex { $0.id == selected } }
    override var acceptsFirstResponder: Bool { true }
    init(document: CaptureDocument) {
        self.document = document; super.init(frame:.zero)
        wantsLayer = true; registerForDraggedTypes([.fileURL,.tiff,.png])
        setAccessibilityRole(.group); setAccessibilityLabel("Éditeur de capture")
    }
    required init?(coder:NSCoder) { fatalError() }
    override func resetCursorRects() { addCursorRect(imageRect,cursor:tool == .select ? .arrow : tool == .text ? .iBeam : .crosshair) }
    override func draw(_ dirtyRect:NSRect) {
        let image = imageRect
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.45); shadow.shadowBlurRadius = 22; shadow.shadowOffset = NSSize(width:0,height:8)
        NSGraphicsContext.saveGraphicsState(); shadow.set(); NSColor(white:0.15,alpha:1).setFill(); NSBezierPath(roundedRect:image,xRadius:5,yRadius:5).fill(); NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:image).addClip()
        let transform = AffineTransform(translationByX:image.minX,byY:image.minY); (transform as NSAffineTransform).concat()
        let scaling = AffineTransform(scale:scale); (scaling as NSAffineTransform).concat()
        document.draw(excluding:editingID)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.18).setStroke(); let border = NSBezierPath(rect:image); border.lineWidth = 0.5; border.stroke()
        if let i = selectedIndex, editingID == nil {
            let rect = screen(document.marks[i].bounds).insetBy(dx:-3,dy:-3)
            NSColor(srgbRed:0.6,green:0.6,blue:1,alpha:1).setStroke(); let path = NSBezierPath(rect:rect); path.lineWidth = 1.2; path.stroke()
            for p in corners(rect) { NSColor.white.setFill(); NSBezierPath(roundedRect:CGRect(x:p.x-4,y:p.y-4,width:8,height:8),xRadius:2,yRadius:2).fill() }
        }
    }
    private func corners(_ rect: CGRect) -> [CGPoint] { [CGPoint(x:rect.minX,y:rect.minY),CGPoint(x:rect.maxX,y:rect.minY),CGPoint(x:rect.maxX,y:rect.maxY),CGPoint(x:rect.minX,y:rect.maxY)] }
    override func mouseDown(with event:NSEvent) {
        commitText(); window?.makeFirstResponder(self)
        let p = point(event); guard CGRect(origin:.zero,size:document.size).contains(p) else { selected = nil; changed?(); return }
        start = p; initial = nil; resizeCorner = nil; didCheckpoint = false
        if tool == .image { chooseImage?(); return }
        if tool == .select {
            if let i = selectedIndex {
                let mark = document.marks[i]
                resizeCorner = corners(mark.bounds).firstIndex { hypot($0.x-p.x,$0.y-p.y) < 12/scale }
                if resizeCorner != nil { initial = mark; return }
            }
            selected = document.marks.reversed().first(where: { $0.contains(p,tolerance:5/scale) })?.id
            if let i = selectedIndex {
                initial = document.marks[i]
                if event.clickCount == 2 && initial?.kind == .text { beginText(document.marks[i]); start = nil }
            }
            changed?(); return
        }
        if tool == .text {
            let mark = CaptureMark(kind:.text,rect:CGRect(x:p.x,y:p.y,width:min(360/scale,document.size.width-p.x),height:100/scale),color:color,fontSize:fontSize,bold:bold)
            beginText(mark); start = nil; return
        }
        document.checkpoint(); didCheckpoint = true
        var mark = CaptureMark(kind:tool,rect:CGRect(origin:p,size:.zero),color:color,width:stroke,filled:filled)
        if tool == .pen || tool == .arrow { mark.points = [p] }
        document.marks.append(mark); selected = mark.id; changed?(); needsDisplay = true
    }
    override func mouseDragged(with event:NSEvent) {
        guard let origin = start, let i = selectedIndex else { return }
        var p = point(event); p.x = min(document.size.width,max(0,p.x)); p.y = min(document.size.height,max(0,p.y))
        if let initial {
            if !didCheckpoint { document.checkpoint(); didCheckpoint = true }
            var rect = initial.bounds
            if let corner = resizeCorner {
                let opposite = corners(rect)[(corner+2)%4]
                rect = CGRect(x:min(opposite.x,p.x),y:min(opposite.y,p.y),width:max(8,abs(opposite.x-p.x)),height:max(8,abs(opposite.y-p.y)))
                if initial.kind == .image || event.modifierFlags.contains(.shift) {
                    let aspect = initial.bounds.width/max(1,initial.bounds.height)
                    if rect.width/rect.height > aspect { rect.size.height = rect.width/aspect } else { rect.size.width = rect.height*aspect }
                    rect.origin = CGPoint(x:p.x<opposite.x ? opposite.x-rect.width : opposite.x,y:p.y<opposite.y ? opposite.y-rect.height : opposite.y)
                }
            } else { rect.origin.x += p.x-origin.x; rect.origin.y += p.y-origin.y }
            var mark = initial; mark.transform(to:rect); document.marks[i] = mark
        } else {
            if tool == .pen { document.marks[i].points.append(p) }
            else if tool == .arrow { document.marks[i].points = [origin,p] }
            else {
                if event.modifierFlags.contains(.shift) { let side = min(abs(p.x-origin.x),abs(p.y-origin.y)); p = CGPoint(x:origin.x+(p.x<origin.x ? -side:side),y:origin.y+(p.y<origin.y ? -side:side)) }
                document.marks[i].rect = CGRect(x:min(origin.x,p.x),y:min(origin.y,p.y),width:abs(p.x-origin.x),height:abs(p.y-origin.y))
            }
        }
        needsDisplay = true; changed?()
    }
    override func mouseUp(with event:NSEvent) {
        if initial == nil, let i = selectedIndex, tool != .pen, tool != .text, document.marks[i].bounds.width < 3, document.marks[i].bounds.height < 3 { document.marks.remove(at:i); selected = nil }
        start = nil; initial = nil; resizeCorner = nil; changed?()
    }
    func insertImage(_ image:NSImage) {
        commitText(); guard image.size.width > 0, image.size.height > 0 else { return }
        let factor = min(document.size.width*0.5/image.size.width,document.size.height*0.5/image.size.height,1)
        let size = CGSize(width:image.size.width*factor,height:image.size.height*factor)
        document.checkpoint()
        let mark = CaptureMark(kind:.image,rect:CGRect(x:(document.size.width-size.width)/2,y:(document.size.height-size.height)/2,width:size.width,height:size.height),image:image)
        document.marks.append(mark); selected = mark.id; toolChanged?(.select); changed?(); needsDisplay = true
    }
    private func beginText(_ mark:CaptureMark) {
        editingID = mark.id; editingMark = mark; selected = mark.id
        let field = NSTextField(string:mark.text); textEditor = field
        field.isBordered = false; field.drawsBackground = true; field.backgroundColor = NSColor(white:0.12,alpha:0.85)
        field.textColor = mark.color; field.font = .systemFont(ofSize:max(9,mark.fontSize*scale),weight:mark.bold ? .semibold : .regular)
        field.focusRingType = .none; field.delegate = self; field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true; field.cell?.isScrollable = false
        field.placeholderString = "Texte"; field.frame = screen(mark.rect); addSubview(field); window?.makeFirstResponder(field); needsDisplay = true
    }
    func commitText() {
        guard let editor = textEditor, var mark = editingMark, editingID != nil else { return }
        let value = editor.stringValue
        textEditor = nil; editingID = nil; editingMark = nil; editor.delegate = nil; editor.removeFromSuperview()
        if !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            mark.text = value
            let height = (value as NSString).boundingRect(with:NSSize(width:mark.rect.width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:NSFont.systemFont(ofSize:mark.fontSize,weight:mark.bold ? .semibold : .regular)]).height
            mark.rect.size.height = max(mark.fontSize*1.3,ceil(height)+6)
            document.checkpoint()
            if let i = document.marks.firstIndex(where: { $0.id == mark.id }) { document.marks[i] = mark } else { document.marks.append(mark) }
        }
        needsDisplay = true; changed?()
    }
    func control(_ control:NSControl,textView:NSTextView,doCommandBy selector:Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) && NSApp.currentEvent?.modifierFlags.contains(.shift) != true { commitText(); window?.makeFirstResponder(self); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { textEditor?.delegate = nil; textEditor?.removeFromSuperview(); textEditor = nil; editingID = nil; editingMark = nil; needsDisplay = true; window?.makeFirstResponder(self); return true }
        return false
    }
    func controlTextDidEndEditing(_ obj:Notification) { commitText() }
    func styleSelection(_ change:(inout CaptureMark)->Void) {
        commitText(); if let i = selectedIndex {
            document.checkpoint(); change(&document.marks[i])
            if document.marks[i].kind == .text {
                let mark = document.marks[i]
                let height = (mark.text as NSString).boundingRect(with:NSSize(width:mark.rect.width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:NSFont.systemFont(ofSize:mark.fontSize,weight:mark.bold ? .semibold : .regular)]).height
                document.marks[i].rect.size.height = max(mark.fontSize*1.3,ceil(height)+6)
            }
        }; needsDisplay = true; changed?()
    }
    @objc func undo(_ sender:Any?) { commitText(); document.undo(); selected = nil; needsDisplay = true; changed?() }
    @objc func redo(_ sender:Any?) { commitText(); document.redo(); selected = nil; needsDisplay = true; changed?() }
    @objc func delete(_ sender:Any?) { guard let i = selectedIndex else { return }; document.checkpoint(); document.marks.remove(at:i); selected = nil; needsDisplay = true; changed?() }
    @objc func paste(_ sender:Any?) { if let image = NSImage(pasteboard:.general) { insertImage(image) } }
    override func keyDown(with event:NSEvent) {
        if [51,117].contains(event.keyCode) { delete(nil); return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" { event.modifierFlags.contains(.shift) ? redo(nil) : undo(nil); return }
        if [123,124,125,126].contains(event.keyCode), let i = selectedIndex {
            document.checkpoint(); var rect = document.marks[i].bounds; let amount:CGFloat = event.modifierFlags.contains(.shift) ? 10:1
            rect.origin.x += event.keyCode == 123 ? -amount : event.keyCode == 124 ? amount : 0
            rect.origin.y += event.keyCode == 126 ? -amount : event.keyCode == 125 ? amount : 0
            document.marks[i].transform(to:rect); needsDisplay = true; changed?(); return
        }
        let shortcuts:[String:CaptureTool] = ["v":.select,"i":.image,"t":.text,"o":.ellipse,"r":.rectangle,"a":.arrow,"p":.pen]
        if !event.modifierFlags.contains(.command), let tool = shortcuts[event.charactersIgnoringModifiers?.lowercased() ?? ""] { toolChanged?(tool); return }
        super.keyDown(with:event)
    }
    override func draggingEntered(_ sender:NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender:NSDraggingInfo) -> Bool {
        if let image = NSImage(pasteboard:sender.draggingPasteboard) { insertImage(image); return true }
        if let urls = sender.draggingPasteboard.readObjects(forClasses:[NSURL.self]) as? [URL], let url = urls.first, let image = NSImage(contentsOf:url) { insertImage(image); return true }
        return false
    }
    override func layout() { super.layout(); if let mark = editingMark, textEditor != nil { textEditor?.frame = screen(mark.rect) } }
}

final class CaptureEditor: CaptureSurface {
    let canvas: CaptureCanvas
    private let fr:Bool
    private var tools:[CaptureTool:CaptureButton] = [:]
    private let header = CaptureSurface(), bar = CaptureSurface(), options = CaptureSurface()
    private let colorWell = NSColorWell(), width = NSPopUpButton(), textSize = NSPopUpButton()
    private var undoButton:CaptureButton!, redoButton:CaptureButton!, fillButton:CaptureButton!, boldButton:CaptureButton!
    private let title = NSTextField(labelWithString:"")
    private var doneButton:CaptureButton!, cancelButton:CaptureButton!
    var done:(()->Void)?
    var cancel:(()->Void)?
    init(document:CaptureDocument,language:String) {
        canvas = CaptureCanvas(document:document); fr = language == "fr"; super.init(frame:.zero)
        wantsLayer = true; layer?.backgroundColor = NSColor(srgbRed:0.065,green:0.06,blue:0.12,alpha:0.98).cgColor; layer?.cornerRadius = 20
        layer?.borderWidth = 0.7; layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.4; layer?.shadowRadius = 30
        addSubview(canvas); addSubview(header); addSubview(bar); addSubview(options)
        title.stringValue = fr ? "Modifier la capture" : "Edit capture"; title.font = .systemFont(ofSize:14,weight:.semibold); title.textColor = .white; header.addSubview(title)
        cancelButton = CaptureButton(fr ? "Retour" : "Back") { [weak self] in self?.canvas.commitText(); self?.cancel?() }
        doneButton = CaptureButton(fr ? "Terminé" : "Done") { [weak self] in self?.canvas.commitText(); self?.done?() }; doneButton.primary = true
        header.addSubview(cancelButton); header.addSubview(doneButton)
        for (i,tool) in CaptureTool.allCases.enumerated() {
            let b = CaptureButton(tool.title(fr),symbol:tool.symbol) { [weak self] in self?.select(tool) }
            b.frame = CGRect(x:i*44,y:0,width:42,height:42); bar.addSubview(b); tools[tool] = b
        }
        undoButton = CaptureButton(fr ? "Annuler · ⌘Z" : "Undo · ⌘Z",symbol:"arrow.uturn.backward") { [weak self] in self?.canvas.undo(nil) }
        redoButton = CaptureButton(fr ? "Rétablir · ⇧⌘Z" : "Redo · ⇧⌘Z",symbol:"arrow.uturn.forward") { [weak self] in self?.canvas.redo(nil) }
        bar.addSubview(undoButton); bar.addSubview(redoButton)
        let remove = CaptureButton(fr ? "Supprimer l’annotation" : "Delete annotation",symbol:"trash") { [weak self] in self?.canvas.delete(nil) }; remove.frame = CGRect(x:410,y:0,width:42,height:42); bar.addSubview(remove)
        undoButton.frame = CGRect(x:316,y:0,width:42,height:42); redoButton.frame = CGRect(x:360,y:0,width:42,height:42)
        colorWell.color = canvas.color; colorWell.target = self; colorWell.action = #selector(colorChanged); colorWell.toolTip = fr ? "Couleur" : "Color"; options.addSubview(colorWell)
        width.addItems(withTitles:["2 px","4 px","7 px","12 px","20 px"]); width.selectItem(at:1); width.target = self; width.action = #selector(widthChanged); width.toolTip = fr ? "Épaisseur" : "Stroke width"; options.addSubview(width)
        fillButton = CaptureButton(fr ? "Remplissage" : "Fill",symbol:"circle.lefthalf.filled") { [weak self] in guard let self else { return }; self.canvas.filled.toggle(); self.fillButton.selected = self.canvas.filled; self.canvas.styleSelection { $0.filled = self.canvas.filled } }; options.addSubview(fillButton)
        textSize.addItems(withTitles:["16","24","36","48","64","96","128"]); textSize.selectItem(withTitle:"36"); textSize.target = self; textSize.action = #selector(sizeChanged); textSize.toolTip = fr ? "Taille du texte" : "Text size"; options.addSubview(textSize)
        boldButton = CaptureButton(fr ? "Gras" : "Bold",symbol:"bold") { [weak self] in guard let self else { return }; self.canvas.bold.toggle(); self.boldButton.selected = self.canvas.bold; self.canvas.styleSelection { $0.bold = self.canvas.bold } }; boldButton.selected = true; options.addSubview(boldButton)
        canvas.changed = { [weak self] in self?.refresh() }; canvas.toolChanged = { [weak self] in self?.select($0) }; canvas.chooseImage = { [weak self] in self?.importImage() }
        select(.select); refresh()
    }
    required init?(coder:NSCoder) { fatalError() }
    private func refresh() {
        undoButton.isEnabled = canvas.document.canUndo; redoButton.isEnabled = canvas.document.canRedo; undoButton.needsDisplay = true; redoButton.needsDisplay = true
        if let mark = canvas.selection {
            colorWell.color = mark.color; canvas.color = mark.color; canvas.filled = mark.filled; fillButton.selected = mark.filled
            canvas.bold = mark.bold; boldButton.selected = mark.bold
            width.selectItem(withTitle:"\(Int(mark.width)) px"); textSize.selectItem(withTitle:"\(Int(mark.fontSize))")
        }
    }
    private func select(_ tool:CaptureTool) {
        if tool == .image { importImage(); return }
        canvas.tool = tool; for (kind,b) in tools { b.selected = kind == tool }; window?.makeFirstResponder(canvas)
    }
    private func importImage() {
        canvas.commitText(); guard let window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for:window) { [weak self] result in if result == .OK, let url = panel.url, let image = NSImage(contentsOf:url) { self?.canvas.insertImage(image) } }
    }
    @objc private func colorChanged() { canvas.color = colorWell.color; canvas.styleSelection { $0.color = colorWell.color } }
    @objc private func widthChanged() { canvas.stroke = [2,4,7,12,20][width.indexOfSelectedItem]; canvas.styleSelection { $0.width = canvas.stroke } }
    @objc private func sizeChanged() { canvas.fontSize = CGFloat(Double(textSize.titleOfSelectedItem ?? "36") ?? 36); canvas.styleSelection { $0.fontSize = canvas.fontSize } }
    override func layout() {
        super.layout(); header.frame = CGRect(x:0,y:0,width:bounds.width,height:52)
        title.frame = CGRect(x:24,y:18,width:max(0,bounds.width-220),height:20)
        cancelButton.frame = CGRect(x:bounds.width-174,y:8,width:78,height:36); doneButton.frame = CGRect(x:bounds.width-92,y:8,width:78,height:36)
        canvas.frame = CGRect(x:8,y:52,width:bounds.width-16,height:max(80,bounds.height-156))
        bar.frame = CGRect(x:(bounds.width-452)/2,y:bounds.height-100,width:452,height:44)
        options.frame = CGRect(x:(bounds.width-280)/2,y:bounds.height-53,width:280,height:36)
        colorWell.frame = CGRect(x:0,y:3,width:38,height:30); width.frame = CGRect(x:48,y:5,width:76,height:28)
        fillButton.frame = CGRect(x:130,y:0,width:36,height:36); textSize.frame = CGRect(x:176,y:5,width:64,height:28); boldButton.frame = CGRect(x:244,y:0,width:36,height:36)
    }
}
