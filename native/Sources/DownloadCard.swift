import AppKit
import QuartzCore

/// The same transfer card is used by the compact shelf and the virtualized library.
final class DownloadCard: NSView {
    private let nameLabel = NSTextField(labelWithString:"")
    private let sizeLabel = NSTextField(labelWithString:"")
    private let statusLabel = NSTextField(labelWithString:"")
    private let glyph = NSImageView()
    private let track = CALayer(), fill = CALayer()
    private var pause: ActionButton!, cancel: ActionButton!
    private var reveal: ActionButton!, remove: ActionButton!
    private var hovered = false
    var removeRecord: ((String) -> Void)?
    private var record: LibraryDownload?
    private var tracking: NSTrackingArea?
    private var seenTask: DispatchWorkItem?
    var action: ((String,String) -> Void)?
    var seen: ((String) -> Void)?
    var open: ((URL) -> Void)?
    override var isFlipped: Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame); wantsLayer = true; layer?.cornerRadius = 12; layer?.backgroundColor = NSColor.white.withAlphaComponent(0.035).cgColor
        nameLabel.font = .systemFont(ofSize:12.5,weight:.semibold); nameLabel.lineBreakMode = .byTruncatingMiddle
        for label in [sizeLabel,statusLabel] { label.font = .systemFont(ofSize:10.5); label.lineBreakMode = .byTruncatingTail }
        pause = TransferActionButton("",symbol:"pause.fill") { [weak self] in guard let self, let record = self.record else { return }; self.action?(record.id,record.state == "paused" ? "resume" : "pause") }
        cancel = TransferActionButton("",symbol:"xmark") { [weak self] in guard let self, let record = self.record else { return }; self.action?(record.id,"cancel") }
        reveal = TransferActionButton("",symbol:"folder") { [weak self] in
            guard let self, let record = self.record, !record.path.isEmpty else { return }; self.seen?(record.id)
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:record.path)])
        }
        remove = TransferActionButton("",symbol:"xmark") { [weak self] in guard let self, let record = self.record else { return }; self.removeRecord?(record.id) }
        for button in [pause!,cancel!,reveal!,remove!] { button.wantsLayer = true; button.layer?.cornerRadius = 7; button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor }
        for child in [glyph,nameLabel,sizeLabel,statusLabel,pause!,cancel!,reveal!,remove!] { addSubview(child) }
        fill.anchorPoint = CGPoint(x:0,y:0); track.cornerRadius = 2; fill.cornerRadius = 2; track.masksToBounds = true; track.addSublayer(fill); layer?.addSublayer(track)
        setAccessibilityElement(true); setAccessibilityRole(.group)
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(_ value:LibraryDownload, language:String, ink:NSColor = .white) {
        if record?.id != value.id { seenTask?.cancel(); seenTask = nil }
        record = value; let fr = language == "fr"
        nameLabel.stringValue = value.name.isEmpty ? (fr ? "Téléchargement" : "Download") : value.name
        nameLabel.textColor = ink.withAlphaComponent(0.94); sizeLabel.textColor = ink.withAlphaComponent(0.63); statusLabel.textColor = ink.withAlphaComponent(0.74)
        let bytes = { (n:Int64) in ByteCountFormatter.string(fromByteCount:max(0,n),countStyle:.file) }
        sizeLabel.stringValue = value.total > 0 ? "\(bytes(value.received)) / \(bytes(value.total))" : bytes(value.received)
        switch value.state {
        case "progress": statusLabel.stringValue = "\(bytes(value.speed ?? 0))/s" + (value.total > 0 ? "  ·  \(Int(value.fraction*100)) %" : "  ·  " + (fr ? "En cours" : "Downloading"))
        case "paused": statusLabel.stringValue = fr ? "En pause" : "Paused"
        case "complete": statusLabel.stringValue = fr ? "Terminé · Ouvrir" : "Complete · Open"
        case "cancelled": statusLabel.stringValue = fr ? "Annulé" : "Cancelled"
        default: statusLabel.stringValue = fr ? "Interrompu" : "Interrupted"
        }
        glyph.image = NSImage(systemSymbolName:value.state == "complete" ? "checkmark.circle.fill" : value.state == "paused" ? "pause.circle" : value.isActive ? "arrow.down.circle" : "doc",accessibilityDescription:nil); glyph.contentTintColor = ink.withAlphaComponent(0.75)
        pause.isHidden = !value.isActive; cancel.isHidden = !value.isActive
        pause.image = NSImage(systemSymbolName:value.state == "paused" ? "play.fill" : "pause.fill",accessibilityDescription:nil)
        pause.toolTip = value.state == "paused" ? (fr ? "Reprendre" : "Resume") : (fr ? "Mettre en pause" : "Pause")
        cancel.toolTip = fr ? "Annuler le téléchargement" : "Cancel download"
        reveal.toolTip = fr ? "Afficher dans le Finder" : "Show in Finder"
        remove.toolTip = fr ? "Retirer de la liste" : "Remove from list"
        reveal.isHidden = value.state != "complete"; remove.isHidden = value.isActive
        reveal.alphaValue = hovered ? 1 : 0; remove.alphaValue = hovered ? 1 : 0
        for button in [pause!,cancel!,reveal!,remove!] { button.contentTintColor = ink; button.setAccessibilityLabel(button.toolTip) }
        track.backgroundColor = ink.withAlphaComponent(0.12).cgColor; fill.backgroundColor = ink.withAlphaComponent(value.state == "paused" ? 0.4 : 0.85).cgColor
        track.isHidden = !value.isActive; toolTip = value.name
        setAccessibilityLabel(nameLabel.stringValue + ", " + sizeLabel.stringValue + ", " + statusLabel.stringValue)
        needsLayout = true; layout()
        scheduleSeen()
    }
    private func scheduleSeen() {
        guard record?.unread == true, seenTask == nil else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }; self.seenTask = nil
            if let record = self.record, record.unread == true, self.window?.isVisible == true, !self.isHiddenOrHasHiddenAncestor,
               self.visibleRect.height >= self.bounds.height*0.75, self.visibleRect.width > self.bounds.width*0.75 {
                self.seen?(record.id)
            }
        }; seenTask = task; DispatchQueue.main.asyncAfter(deadline:.now()+0.85,execute:task)
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleSeen() }
    override func layout() {
        super.layout(); let w = bounds.width
        glyph.frame = NSRect(x:10,y:12,width:21,height:21)
        nameLabel.frame = NSRect(x:39,y:11,width:max(20,w-49-53),height:19)
        pause.frame = NSRect(x:w-57,y:9,width:24,height:25); cancel.frame = NSRect(x:w-29,y:9,width:24,height:25)
        reveal.frame = pause.frame; remove.frame = cancel.frame
        sizeLabel.frame = NSRect(x:12,y:39,width:w-24,height:16)
        statusLabel.frame = NSRect(x:12,y:60,width:w-24,height:17)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.frame = CGRect(x:12,y:84,width:max(0,w-24),height:3)
        let old = fill.presentation()?.bounds.width ?? fill.bounds.width
        fill.frame = CGRect(x:0,y:0,width:track.bounds.width * (record?.fraction ?? 0),height:3)
        CATransaction.commit()
        if abs(old-fill.bounds.width) > 0.5, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath:"bounds.size.width"); animation.fromValue = old; animation.toValue = fill.bounds.width; animation.duration = 0.22; fill.add(animation,forKey:"progress")
        }
    }
    override func mouseUp(with event:NSEvent) {
        guard let record, record.state == "complete", !record.path.isEmpty else { return }
        seen?(record.id); open?(URL(fileURLWithPath:record.path))
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.activeAlways,.inVisibleRect,.mouseEnteredAndExited],owner:self); addTrackingArea(tracking!)
        if let window { setHovered(!isHiddenOrHasHiddenAncestor && visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream,from:nil))) }
    }
    func refreshHover() { if let window { setHovered(!isHiddenOrHasHiddenAncestor && visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream,from:nil))) } }
    private func setHovered(_ value:Bool) {
        guard hovered != value else { return }; hovered = value
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
            reveal.animator().alphaValue = value ? 1 : 0; remove.animator().alphaValue = value ? 1 : 0
        }
        layer?.backgroundColor = NSColor.white.withAlphaComponent(value ? 0.09 : 0.035).cgColor
    }
    override func mouseEntered(with event:NSEvent) { setHovered(true); scheduleSeen() }
    override func mouseExited(with event:NSEvent) { setHovered(window.map { visibleRect.contains(convert($0.mouseLocationOutsideOfEventStream,from:nil)) } ?? false) }
    deinit { seenTask?.cancel() }
}

/// Native arrow cursor with a small, animated hover surface.
final class TransferActionButton: ActionButton {
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.activeAlways,.inVisibleRect,.mouseEnteredAndExited],owner:self); addTrackingArea(tracking!)
    }
    override func mouseEntered(with event:NSEvent) { layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor }
    override func mouseExited(with event:NSEvent) { layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor }
}
