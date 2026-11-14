import AppKit
import QuartzCore
import UniformTypeIdentifiers

/// The same transfer card is used by the compact shelf and the virtualized library.
final class DownloadCard: NSView {
    private let nameLabel = NSTextField(labelWithString:"")
    private let sizeLabel = NSTextField(labelWithString:"")
    private let statusLabel = NSTextField(labelWithString:"")
    private let glyph = NSImageView()
    private let track = CALayer(), fill = CALayer()
    private var pause: ActionButton!, cancel: ActionButton!
    private var recovery: TransferActionButton!
    private var reveal: ActionButton!, remove: ActionButton!
    private var hovered = false
    private let compact: Bool
    private var ink = NSColor.white
    private var fileType: UTType?
    var removeRecord: ((String) -> Void)?
    private var record: LibraryDownload?
    private var tracking: NSTrackingArea?
    private var seenTask: DispatchWorkItem?
    var action: ((String,String) -> Void)?
    var seen: ((String) -> Void)?
    var open: ((URL) -> Void)?
    override var isFlipped: Bool { true }
    var shelfHeight: CGFloat { record?.isActive == true || record?.isBlocked == true ? 48 : 33 }
    init(frame:NSRect, compact:Bool = false) {
        self.compact = compact
        super.init(frame:frame); wantsLayer = true; layer?.cornerRadius = compact ? 7 : 12
        nameLabel.font = .systemFont(ofSize:12.5,weight:compact ? .medium : .semibold); nameLabel.lineBreakMode = .byTruncatingMiddle
        for label in [sizeLabel,statusLabel] { label.font = .systemFont(ofSize:10.5); label.lineBreakMode = .byTruncatingTail }
        pause = TransferActionButton("",symbol:"pause.fill") { [weak self] in guard let self, let record = self.record else { return }; self.action?(record.id,record.state == "paused" ? "resume" : "pause") }
        cancel = TransferActionButton("",symbol:"xmark") { [weak self] in guard let self, let record = self.record else { return }; self.action?(record.id,"cancel") }
        recovery = TransferActionButton("") { [weak self] in
            guard let self, let record = self.record, let command = record.isActive ? "details" : record.recoveryAction else { return }
            self.action?(record.id,command)
        }
        recovery.font = .systemFont(ofSize:11,weight:.semibold)
        reveal = TransferActionButton("",symbol:"folder") { [weak self] in
            guard let self, let record = self.record, !record.path.isEmpty else { return }; self.seen?(record.id)
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:record.path)])
        }
        remove = TransferActionButton("",symbol:"xmark") { [weak self] in guard let self, let record = self.record else { return }; self.removeRecord?(record.id) }
        for button in [pause!,cancel!,reveal!,remove!,recovery!] { button.wantsLayer = true; button.layer?.cornerRadius = 7; button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor }
        if compact {
            sizeLabel.alignment = .right
            glyph.imageScaling = .scaleProportionallyUpOrDown
        }
        for child in [glyph,nameLabel,sizeLabel,statusLabel,pause!,cancel!,reveal!,remove!,recovery!] { addSubview(child) }
        fill.anchorPoint = CGPoint(x:0,y:0); track.cornerRadius = 2; fill.cornerRadius = 2; track.masksToBounds = true; track.addSublayer(fill); layer?.addSublayer(track)
        setAccessibilityElement(true); setAccessibilityRole(.group)
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(_ value:LibraryDownload, language:String, ink:NSColor = .white) {
        self.ink = ink
        if record?.id != value.id { seenTask?.cancel(); seenTask = nil }
        record = value; let fr = language == "fr"
        nameLabel.stringValue = value.name.isEmpty ? (fr ? "Téléchargement" : "Download") : value.name
        nameLabel.textColor = ink.withAlphaComponent(0.94); sizeLabel.textColor = ink.withAlphaComponent(0.63); statusLabel.textColor = ink.withAlphaComponent(0.74)
        let byteFormat = ByteCountFormatStyle(style:.file,spellsOutZero:false,locale:Locale(identifier:fr ? "fr_FR" : "en_US"))
        let bytes = { (n:Int64) in byteFormat.format(max(0,n)) }
        sizeLabel.stringValue = value.total > 0 ? "\(bytes(value.received)) / \(bytes(value.total))" : bytes(value.received)
        switch value.state {
        case "progress": statusLabel.stringValue = "\(bytes(value.speed ?? 0))/s" + (value.total > 0 ? "  ·  \(Int(value.fraction*100)) %" : "  ·  " + (fr ? "En cours" : "Downloading"))
        case "recovering": statusLabel.stringValue = fr ? "Relance en cours…" : "Restarting…"
        case "paused": statusLabel.stringValue = fr ? "En pause" : "Paused"
        case "complete": statusLabel.stringValue = fr ? "Terminé · Ouvrir" : "Complete · Open"
        case "cancelled": statusLabel.stringValue = fr ? "Annulé" : "Cancelled"
        case "blocked": statusLabel.stringValue = LibraryDownload.blockedLabel(language)
        default: statusLabel.stringValue = fr ? "Interrompu" : "Interrupted"
        }
        if compact && value.state == "complete" {
            let type = UTType(filenameExtension:(nameLabel.stringValue as NSString).pathExtension) ?? .data
            if fileType != type { glyph.image = NSWorkspace.shared.icon(for:type); fileType = type }
            glyph.contentTintColor = nil
            sizeLabel.stringValue = bytes(value.received)
        } else {
            fileType = nil
            glyph.image = NSImage(systemSymbolName:value.state == "complete" ? "checkmark.circle.fill" : value.state == "paused" ? "pause.circle" : value.isActive ? "arrow.down.circle" : "doc",accessibilityDescription:nil)
            glyph.contentTintColor = ink.withAlphaComponent(0.75)
            if value.isBlocked {
                glyph.image = NSImage(systemSymbolName:"exclamationmark.shield.fill",accessibilityDescription:nil)
                glyph.contentTintColor = .systemOrange
                sizeLabel.stringValue = ""
            }
        }
        if compact && value.state == "progress" {
            let amount = value.total > 0 ? "\(Int(value.fraction*100)) %" : bytes(value.received)
            statusLabel.stringValue = (value.speed ?? 0) > 0 ? amount+" · "+bytes(value.speed ?? 0)+"/s" : amount
        } else if compact && value.state == "paused" && value.total > 0 {
            statusLabel.stringValue += " · \(Int(value.fraction*100)) %"
        }
        let command = value.isActive && !compact ? "details" : value.recoveryAction
        recovery.isHidden = command == nil
        switch command {
        case "details": recovery.title = fr ? "Détails" : "Details"
        case "resume": recovery.title = fr ? "Reprendre" : "Resume"
        case "page": recovery.title = fr ? "Ouvrir la page" : "Open page"
        default: recovery.title = fr ? "Recommencer" : "Restart"
        }
        recovery.toolTip = recovery.title
        recovery.attributedTitle = NSAttributedString(string:recovery.title,attributes:[.foregroundColor:ink,.font:recovery.font!])
        if value.state == "interrupted" && command == nil {
            statusLabel.stringValue = fr ? "Interrompu · À retélécharger depuis la page d’origine" : "Interrupted · Download again from the original page"
        }
        pause.isHidden = !value.isActive; cancel.isHidden = !value.isActive
        pause.image = NSImage(systemSymbolName:value.state == "paused" ? "play.fill" : "pause.fill",accessibilityDescription:nil)
        pause.toolTip = value.state == "paused" ? (fr ? "Reprendre" : "Resume") : (fr ? "Mettre en pause" : "Pause")
        cancel.toolTip = fr ? "Annuler le téléchargement" : "Cancel download"
        reveal.toolTip = fr ? "Afficher dans le Finder" : "Show in Finder"
        remove.toolTip = fr ? "Retirer de la liste" : "Remove from list"
        reveal.isHidden = value.state != "complete"; remove.isHidden = value.isActive || value.isRecovering
        reveal.alphaValue = hovered ? 1 : 0; remove.alphaValue = hovered ? 1 : 0
        for button in [pause!,cancel!,reveal!,remove!,recovery!] { button.contentTintColor = ink; button.setAccessibilityLabel(button.toolTip) }
        track.backgroundColor = ink.withAlphaComponent(0.12).cgColor; fill.backgroundColor = ink.withAlphaComponent(value.state == "paused" ? 0.4 : 0.85).cgColor
        let description = [nameLabel.stringValue,sizeLabel.stringValue,statusLabel.stringValue].joined(separator:", ")
        track.isHidden = !value.isActive; toolTip = compact ? description : value.name
        layer?.backgroundColor = rowColor.cgColor
        setAccessibilityLabel(description)
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
        let progressFrame: NSRect
        if compact {
            let active = record?.isActive == true
            let complete = record?.state == "complete"
            let textX:CGFloat = 33
            let actionsY = floor((bounds.height-24)/2)
            pause.frame = NSRect(x:w-53,y:actionsY,width:23,height:24)
            cancel.frame = NSRect(x:w-27,y:actionsY,width:23,height:24)
            let sizeWidth = min(ceil(sizeLabel.attributedStringValue.size().width)+8,w*0.33)
            let trailing = active || hovered ? pause.frame.minX-4 : w-7-(complete ? sizeWidth+5 : 0)
            glyph.frame = NSRect(x:6,y:floor((bounds.height-20)/2),width:20,height:20)
            let twoLines = active || record?.isBlocked == true
            nameLabel.frame = NSRect(x:textX,y:twoLines ? 4 : floor((bounds.height-17)/2),width:max(0,trailing-textX),height:17)
            sizeLabel.frame = NSRect(x:w-7-sizeWidth,y:floor((bounds.height-15)/2),width:sizeWidth,height:15)
            sizeLabel.isHidden = !complete || hovered
            statusLabel.isHidden = !twoLines
            statusLabel.frame = NSRect(x:textX,y:22,width:max(0,trailing-textX),height:15)
            progressFrame = NSRect(x:textX+2,y:40,width:max(0,trailing-textX-2),height:2)
        } else {
            glyph.frame = NSRect(x:10,y:12,width:21,height:21)
            nameLabel.frame = NSRect(x:39,y:11,width:max(20,w-49-53),height:19)
            pause.frame = NSRect(x:w-57,y:9,width:24,height:25); cancel.frame = NSRect(x:w-29,y:9,width:24,height:25)
            sizeLabel.frame = NSRect(x:12,y:39,width:max(0,w-24),height:16)
            statusLabel.frame = NSRect(x:12,y:60,width:max(0,w-24),height:17)
            progressFrame = NSRect(x:12,y:84,width:max(0,w-24),height:3)
        }
        let recoveryWidth = ceil(recovery.attributedTitle.size().width) + 16
        recovery.frame = NSRect(x:w-recoveryWidth-(compact ? 28 : 12),y:compact ? pause.frame.minY : 56,width:recoveryWidth,height:24)
        if !recovery.isHidden {
            if compact { nameLabel.frame.size.width = max(0,recovery.frame.minX-nameLabel.frame.minX-5) }
            else { statusLabel.frame.size.width = max(0,recovery.frame.minX-statusLabel.frame.minX-5) }
        }
        reveal.frame = pause.frame; remove.frame = cancel.frame
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.frame = progressFrame
        let old = fill.presentation()?.bounds.width ?? fill.bounds.width
        fill.frame = CGRect(x:0,y:0,width:track.bounds.width * (record?.fraction ?? 0),height:track.bounds.height)
        CATransaction.commit()
        if abs(old-fill.bounds.width) > 0.5, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath:"bounds.size.width"); animation.fromValue = old; animation.toValue = fill.bounds.width; animation.duration = 0.22; fill.add(animation,forKey:"progress")
        }
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event:NSEvent) {}
    override func mouseUp(with event:NSEvent) {
        guard bounds.contains(convert(event.locationInWindow,from:nil)), let record, record.state == "complete", !record.path.isEmpty else { return }
        seen?(record.id); open?(URL(fileURLWithPath:record.path))
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.activeAlways,.inVisibleRect,.mouseEnteredAndExited],owner:self); addTrackingArea(tracking!)
        setHovered(containsCurrentPointer)
    }
    func refreshHover() { setHovered(containsCurrentPointer) }
    private var rowColor:NSColor {
        compact ? ink.withAlphaComponent(hovered ? 0.08 : 0) : NSColor.white.withAlphaComponent(hovered ? 0.09 : 0.035)
    }
    private func setHovered(_ value:Bool) {
        guard hovered != value else { return }; hovered = value
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
            reveal.animator().alphaValue = value ? 1 : 0; remove.animator().alphaValue = value ? 1 : 0
        }
        layer?.backgroundColor = rowColor.cgColor
        if compact { needsLayout = true }
    }
    override func mouseEntered(with event:NSEvent) { refreshHover(); scheduleSeen() }
    override func mouseExited(with event:NSEvent) { refreshHover() }
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
