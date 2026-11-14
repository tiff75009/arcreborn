import AppKit
import Quartz
import QuickLookThumbnailing
import QuartzCore

// Reveal the two surfaces in sequence so file and tab titles never crossfade over each other.
private let shelfFadeTime: TimeInterval = 0.12

/// Fades the tab artwork itself so the space's actual background shows through.
final class SidebarPeekContent: NSView {
    override var isFlipped: Bool { true }
    var blocksInputAt: ((NSPoint) -> Bool)?
    override func hitTest(_ point:NSPoint) -> NSView? {
        let local = convert(point,from:superview)
        guard blocksInputAt?(convert(local,to:nil)) != true else { return nil }
        return super.hitTest(point)
    }
    private let maskLayer = CAGradientLayer()
    private var edge: CGFloat = 0
    private var presented = false
    private var revision = 0
    private let solid = Array(repeating: NSColor.black.cgColor, count: 5)
    private let faded = [1, 1, 0.62, 0, 0].map { NSColor(white:0, alpha:$0).cgColor }

    override init(frame: NSRect) {
        super.init(frame:frame)
        wantsLayer = true
        maskLayer.startPoint = CGPoint(x:0.5,y:0)
        maskLayer.endPoint = CGPoint(x:0.5,y:1)
    }
    required init?(coder:NSCoder) { fatalError() }

    func setDownloadsEdge(_ y: CGFloat) {
        guard edge != y || maskLayer.frame != bounds else { return }
        edge = y
        let height = max(1, bounds.height)
        let end = min(1, max(0, y / height))
        let start = max(0, end - 72 / height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = bounds
        maskLayer.locations = [0, start, start + (end-start)*0.45, end, 1].map { NSNumber(value:Double($0)) }
        CATransaction.commit()
    }

    func setDownloadsPresented(_ visible: Bool, animated: Bool = true) {
        revision += 1
        let current = revision
        let from = maskLayer.presentation()?.colors ?? (presented ? faded : solid)
        presented = visible
        let destination = visible ? faded : solid
        let duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? shelfFadeTime : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.removeAnimation(forKey:"downloads")
        maskLayer.colors = destination
        layer?.mask = visible || duration > 0 ? maskLayer : nil
        CATransaction.commit()
        guard duration > 0 else { return }
        let fade = CABasicAnimation(keyPath:"colors")
        fade.fromValue = from; fade.toValue = destination
        fade.beginTime = CACurrentMediaTime() + (visible ? 0 : 0.20)
        fade.fillMode = .backwards
        fade.duration = duration; fade.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
        maskLayer.add(fade,forKey:"downloads")
        if !visible {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.20+duration) { [weak self] in
                guard let self, self.revision == current else { return }
                self.layer?.mask = nil
            }
        }
    }
}


private struct ShelfFile {
    let file: RecentLibraryFile
    let download: LibraryDownload?
    var key: String {
        if let download, download.isBlocked { return "blocked:" + download.id }
        return file.url.standardizedFileURL.path
    }
    var isActive: Bool { download?.isActive == true }
}

/// One native file row, with the same geometry before, during and after a transfer.
final class RecentFileRow: NSView {
    static let height: CGFloat = 56
    private let thumbnail = NSImageView(), nameLabel = NSTextField(labelWithString:""), dateLabel = NSTextField(labelWithString:"")
    private let track = CALayer(), fill = CALayer()
    private let primary = TransferActionButton("",symbol:"folder",action:{})
    private let secondary = TransferActionButton("",symbol:"xmark",action:{})
    private var hovered = false
    private var ink = NSColor.white
    private var tracking: NSTrackingArea?
    private var request: QLThumbnailGenerator.Request?
    private var thumbnailKey = ""
    private var item: ShelfFile?
    private var seenTask: DispatchWorkItem?
    var open: ((URL) -> Void)?
    var action: ((String,String) -> Void)?
    var remove: ((URL) -> Void)?
    var seen: ((String) -> Void)?
    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer = true; layer?.cornerRadius = 8; focusRingType = .none
        setAccessibilityElement(true); setAccessibilityRole(.group)
        nameLabel.font = .systemFont(ofSize:14,weight:.medium); nameLabel.lineBreakMode = .byTruncatingTail
        dateLabel.font = .systemFont(ofSize:12.5); dateLabel.lineBreakMode = .byTruncatingTail
        for label in [nameLabel,dateLabel] { label.maximumNumberOfLines = 1; label.cell?.wraps = false; label.cell?.usesSingleLineMode = true }
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true; thumbnail.layer?.cornerRadius = 5; thumbnail.layer?.masksToBounds = true
        for button in [primary,secondary] { button.wantsLayer = true; button.layer?.cornerRadius = 5 }
        primary.invoke = { [weak self] in
            guard let self, let item = self.item, item.download?.isBlocked != true else { return }
            if let record = item.download, record.isActive {
                self.action?(record.id,record.state == "paused" ? "resume" : "pause")
            } else {
                if let record = item.download { self.seen?(record.id) }
                NSWorkspace.shared.activateFileViewerSelecting([item.file.url])
            }
        }
        secondary.invoke = { [weak self] in
            guard let self, let item = self.item else { return }
            if let record = item.download, record.isActive { self.action?(record.id,"cancel") }
            else if let record = item.download, record.isBlocked { self.action?(record.id,"remove") }
            else { self.remove?(item.file.url) }
        }
        for view in [thumbnail,nameLabel,dateLabel,primary,secondary] { addSubview(view) }
        track.cornerRadius = 1; fill.cornerRadius = 1; track.masksToBounds = true
        track.addSublayer(fill); layer?.addSublayer(track)
    }
    required init?(coder:NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    fileprivate func update(_ item:ShelfFile, language:String, ink:NSColor) {
        self.item = item; self.ink = ink
        let fr = language == "fr"
        nameLabel.stringValue = item.download?.name ?? item.file.url.lastPathComponent
        nameLabel.textColor = ink.withAlphaComponent(0.94); dateLabel.textColor = ink.withAlphaComponent(0.60)
        if let record = item.download, record.isActive {
            let bytes = ByteCountFormatStyle(style:.file,spellsOutZero:false,locale:Locale(identifier:fr ? "fr_FR" : "en_US"))
            let amount = record.total > 0 ? "\(Int(record.fraction*100)) %" : bytes.format(record.received)
            dateLabel.stringValue = record.state == "paused" ? (fr ? "En pause · " : "Paused · ")+amount : amount
            if record.state == "progress", let speed = record.speed, speed > 0 { dateLabel.stringValue += " · "+bytes.format(speed)+"/s" }
            primary.image = NSImage(systemSymbolName:record.state == "paused" ? "play.fill" : "pause.fill",accessibilityDescription:nil)
            primary.toolTip = record.state == "paused" ? (fr ? "Reprendre" : "Resume") : (fr ? "Mettre en pause" : "Pause")
            secondary.toolTip = fr ? "Annuler le téléchargement" : "Cancel download"
        } else if item.download?.isBlocked == true {
            dateLabel.stringValue = LibraryDownload.blockedLabel(language)
            secondary.toolTip = fr ? "Retirer de la liste" : "Remove from list"
        } else {
            let formatter = RelativeDateTimeFormatter(); formatter.locale = Locale(identifier:language); formatter.unitsStyle = .full
            dateLabel.stringValue = formatter.localizedString(for:item.file.date,relativeTo:Date())
            primary.image = NSImage(systemSymbolName:"folder",accessibilityDescription:nil)
            primary.toolTip = fr ? "Afficher dans le Finder" : "Show in Finder"
            secondary.toolTip = fr ? "Retirer de la liste" : "Remove from list"
        }
        for button in [primary,secondary] { button.contentTintColor = ink.withAlphaComponent(0.8); button.setAccessibilityLabel(button.toolTip) }
        track.isHidden = !item.isActive; track.backgroundColor = ink.withAlphaComponent(0.12).cgColor
        primary.isHidden = item.download?.isBlocked == true
        fill.backgroundColor = ink.withAlphaComponent(0.7).cgColor
        toolTip = nameLabel.stringValue
        setAccessibilityLabel(nameLabel.stringValue+", "+dateLabel.stringValue)
        updateThumbnail(item)
        updateControls(animated:false); needsLayout = true
        if !isHiddenOrHasHiddenAncestor { scheduleSeen() }
    }
    private func updateThumbnail(_ item:ShelfFile) {
        let key = item.key+(item.isActive ? "|pending" : "|\(item.file.date.timeIntervalSince1970)")
        guard thumbnailKey != key else { return }; thumbnailKey = key
        if let request { QLThumbnailGenerator.shared.cancel(request) }; request = nil
        if item.download?.isBlocked == true {
            thumbnail.image = NSImage(systemSymbolName:"exclamationmark.shield.fill",accessibilityDescription:nil)
            thumbnail.contentTintColor = .systemOrange
            return
        }
        thumbnail.contentTintColor = nil
        thumbnail.image = NSWorkspace.shared.icon(forFile:item.file.url.path)
        guard !item.isActive else { return }
        let request = QLThumbnailGenerator.Request(fileAt:item.file.url,size:NSSize(width:40,height:40),scale:window?.backingScaleFactor ?? 2,representationTypes:.all)
        self.request = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for:request) { [weak self] result,_ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.thumbnailKey == key else { return }
                self.request = nil
                if let result { self.thumbnail.image = result.nsImage }
            }
        }
    }
    override func layout() {
        super.layout()
        thumbnail.frame = NSRect(x:2,y:8,width:40,height:40)
        let controls = hovered || item?.isActive == true
        let textWidth = max(0,bounds.width-54-(controls ? 51 : 4))
        nameLabel.frame = NSRect(x:54,y:9,width:textWidth,height:19)
        dateLabel.frame = NSRect(x:54,y:28,width:textWidth,height:17)
        primary.frame = NSRect(x:bounds.width-48,y:16,width:22,height:24)
        secondary.frame = NSRect(x:bounds.width-24,y:16,width:22,height:24)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.frame = NSRect(x:56,y:49,width:max(0,textWidth-2),height:2)
        fill.frame = NSRect(x:0,y:0,width:track.bounds.width*(item?.download?.fraction ?? 0),height:2)
        CATransaction.commit()
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event:NSEvent) {}
    override func mouseUp(with event:NSEvent) {
        if bounds.contains(convert(event.locationInWindow,from:nil)) { activate() }
    }
    private func activate() {
        guard let item, !item.isActive, item.download?.isBlocked != true else { return }
        if let record = item.download { seen?(record.id) }
        open?(item.file.url)
    }
    override func accessibilityPerformPress() -> Bool { activate(); return item?.isActive == false && item?.download?.isBlocked != true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.activeAlways,.inVisibleRect,.mouseEnteredAndExited],owner:self); addTrackingArea(tracking!)
        refreshHover()
    }
    func refreshHover() {
        hover(containsCurrentPointer)
    }
    private func hover(_ value:Bool) {
        guard hovered != value else { return }; hovered = value
        updateControls(animated:true); needsLayout = true
    }
    private func updateControls(animated:Bool) {
        let visible = hovered || item?.isActive == true
        layer?.backgroundColor = ink.withAlphaComponent(hovered ? 0.07 : 0).cgColor
        for button in [primary,secondary] { button.isEnabled = visible }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.14 : 0
            primary.animator().alphaValue = visible ? 1 : 0; secondary.animator().alphaValue = visible ? 1 : 0
        }
    }
    func scheduleSeen() {
        guard item?.download?.unread == true, seenTask == nil else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }; self.seenTask = nil
            if let record = self.item?.download, record.state == "complete", record.unread == true,
               self.window?.isVisible == true, !self.isHiddenOrHasHiddenAncestor,
               self.visibleRect.height >= self.bounds.height*0.75 { self.seen?(record.id) }
        }
        seenTask = task; DispatchQueue.main.asyncAfter(deadline:.now()+0.85,execute:task)
    }
    override func mouseEntered(with event:NSEvent) { refreshHover() }
    override func mouseExited(with event:NSEvent) { hover(false) }
    deinit { seenTask?.cancel(); if let request { QLThumbnailGenerator.shared.cancel(request) } }
}

final class RecentMediaPeek: NSView, QLPreviewPanelDataSource {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    private var presented = false
    private var rows: [RecentFileRow] = []
    private var keys: [String] = []
    var transferAction: ((String,String) -> Void)?
    var removeRecent: ((URL) -> Void)?
    var transferSeen: ((String) -> Void)?
    private var previewURL: URL?
    private var animationToken = 0
    private let emptyLabel = NSTextField(wrappingLabelWithString:"")
    var desiredHeight: CGFloat { CGFloat(max(1,rows.count))*RecentFileRow.height+8 }
    override var acceptsFirstResponder: Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame); wantsLayer = true; isHidden = true
        emptyLabel.font = .systemFont(ofSize:12); emptyLabel.alignment = .center
        emptyLabel.wantsLayer = true; addSubview(emptyLabel)
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(files:[RecentLibraryFile], downloads:[LibraryDownload] = [], ink:NSColor, language:String, loading:Bool) {
        // Reserve room for ongoing transfers; merge finished transfers with the actual files.
        // No mode switch on unread status, and no duplicate row when a transfer finishes.
        let byPath = Dictionary(downloads.filter { !$0.path.isEmpty }.map { (URL(fileURLWithPath:$0.path).standardizedFileURL.path,$0) },uniquingKeysWith:{ a,b in a.date > b.date ? a : b })
        var entries = downloads.filter { $0.isActive || $0.isBlocked }.map { ShelfFile(file:RecentLibraryFile(url:URL(fileURLWithPath:$0.path.isEmpty ? "/.transfer-"+$0.id : $0.path),date:$0.date),download:$0) }
        let activePaths = Set(entries.map(\.key))
        entries += files.filter { !activePaths.contains($0.url.standardizedFileURL.path) }.map { ShelfFile(file:$0,download:byPath[$0.url.standardizedFileURL.path]) }
        entries = Array(entries.sorted {
            if $0.isActive != $1.isActive { return $0.isActive }
            return $0.file.date == $1.file.date ? $0.key < $1.key : $0.file.date > $1.file.date
        }.prefix(4)).sorted { $0.file.date == $1.file.date ? $0.key < $1.key : $0.file.date < $1.file.date }
        let old = Dictionary(uniqueKeysWithValues:zip(keys,rows))
        let nextKeys = entries.map(\.key)
        for (key,row) in old where !nextKeys.contains(key) { row.removeFromSuperview() }
        rows = entries.map { item in
            let row = old[item.key] ?? RecentFileRow(frame:.zero)
            row.open = { [weak self] in self?.preview($0) }
            row.action = { [weak self] in self?.transferAction?($0,$1) }
            row.remove = { [weak self] in self?.removeRecent?($0) }
            row.seen = { [weak self] in self?.transferSeen?($0) }
            row.update(item,language:language,ink:ink)
            if row.superview == nil { addSubview(row) }
            return row
        }
        keys = nextKeys
        emptyLabel.stringValue = L10n.text(loading ? "loadingMedia" : "nothingHere",language:language)
        emptyLabel.textColor = ink.withAlphaComponent(0.65); emptyLabel.isHidden = !rows.isEmpty
        needsLayout = true
    }
    override func layout() {
        super.layout()
        for (i,row) in rows.enumerated() {
            row.frame = NSRect(x:8,y:4+CGFloat(i)*RecentFileRow.height,width:max(0,bounds.width-16),height:RecentFileRow.height)
            row.layout()
        }
        emptyLabel.frame = NSRect(x:12,y:18,width:max(0,bounds.width-24),height:40)
    }
    override func hitTest(_ point:NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        guard presented else { return self }
        var view:NSView? = hit
        while let candidate = view, candidate !== self {
            if let button = candidate as? NSButton, button.isEnabled, button.alphaValue > 0.1 { return button }
            if candidate is RecentFileRow { return candidate }
            view = candidate.superview
        }
        return self
    }
    // Invisible background is still a native input surface, including while exiting.
    override func mouseDown(with event:NSEvent) {}
    override func mouseDragged(with event:NSEvent) {}
    override func mouseUp(with event:NSEvent) {}
    override func rightMouseDown(with event:NSEvent) {}
    override func otherMouseDown(with event:NSEvent) {}
    override func scrollWheel(with event:NSEvent) {}
    override func menu(for event:NSEvent) -> NSMenu? { nil }
    func refreshHover() { rows.forEach { $0.refreshHover() } }
    func setPresented(_ visible:Bool, animated:Bool = true) {
        animationToken += 1; let token = animationToken
        let wasHidden = isHidden
        presented = visible
        let moving = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        isHidden = false
        let views:[NSView] = rows.isEmpty ? [emptyLabel] : rows
        for (index,view) in views.enumerated() {
            guard let layer = view.layer else { continue }
            let fromOpacity = wasHidden ? Float(0) : layer.presentation()?.opacity ?? layer.opacity
            let fromTransform = wasHidden ? CATransform3DMakeTranslation(0,18,0) : layer.presentation()?.transform ?? layer.transform
            let targetTransform = visible ? CATransform3DIdentity : CATransform3DMakeTranslation(0,12,0)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.removeAnimation(forKey:"shelf-reveal"); layer.removeAnimation(forKey:"shelf-fade")
            layer.opacity = visible ? 1 : 0; layer.transform = targetTransform
            CATransaction.commit()
            guard moving else { continue }
            // The newest (bottom) row leads. Reversals start at the presented frame.
            let delay = visible && wasHidden ? 0.07+Double(views.count-1-index)*0.025 : 0
            let motion = CABasicAnimation(keyPath:"transform")
            motion.fromValue = NSValue(caTransform3D:fromTransform); motion.toValue = NSValue(caTransform3D:targetTransform)
            motion.duration = visible ? 0.36 : 0.18
            motion.timingFunction = CAMediaTimingFunction(controlPoints:0.18,0.80,0.24,1)
            motion.beginTime = CACurrentMediaTime()+delay; motion.fillMode = .backwards
            layer.add(motion,forKey:"shelf-reveal")
            let fade = CABasicAnimation(keyPath:"opacity")
            fade.fromValue = fromOpacity; fade.toValue = visible ? 1 : 0
            fade.duration = visible ? 0.20 : 0.14; fade.beginTime = motion.beginTime; fade.fillMode = .backwards
            layer.add(fade,forKey:"shelf-fade")
        }
        if visible { rows.forEach { $0.scheduleSeen() } }
        if !moving { isHidden = !visible; return }
        if !visible {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.20) { [weak self] in
                guard let self, self.animationToken == token else { return }
                self.isHidden = true
            }
        }
    }
    private func preview(_ url: URL) {
        guard FileManager.default.fileExists(atPath:url.path) else { NSSound.beep(); return }
        previewURL = url; window?.makeFirstResponder(self)
        guard let panel = QLPreviewPanel.shared() else { return }; panel.dataSource = self; panel.reloadData(); panel.makeKeyAndOrderFront(nil)
    }
    override func acceptsPreviewPanelControl(_ panel:QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel:QLPreviewPanel!) { panel.dataSource = self }
    override func endPreviewPanelControl(_ panel:QLPreviewPanel!) { if panel.dataSource === self { panel.dataSource = nil } }
    func numberOfPreviewItems(in panel:QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }
    func previewPanel(_ panel:QLPreviewPanel!,previewItemAt index:Int) -> QLPreviewItem! { previewURL as NSURL? }
}
