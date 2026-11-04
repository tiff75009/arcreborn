import AppKit
import Quartz
import QuickLookThumbnailing
import QuartzCore

// Reveal the two surfaces in sequence so file and tab titles never crossfade over each other.
private let shelfFadeTime: TimeInterval = 0.12

/// Fades the tab artwork itself so the space's actual background shows through.
final class SidebarPeekContent: NSView {
    override var isFlipped: Bool { true }
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
        fade.beginTime = CACurrentMediaTime() + (visible ? 0 : duration)
        fade.fillMode = .backwards
        fade.duration = duration; fade.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
        maskLayer.add(fade,forKey:"downloads")
        if !visible {
            DispatchQueue.main.asyncAfter(deadline:.now()+2*duration) { [weak self] in
                guard let self, self.revision == current else { return }
                self.layer?.mask = nil
            }
        }
    }
}

private final class RecentFileRow: NSView {
    var open: (() -> Void)?
    let thumbnail = NSImageView(), nameLabel = NSTextField(labelWithString:""), dateLabel = NSTextField(labelWithString:"")
    private var hovered = false
    private let revealButton = TransferActionButton("",symbol:"folder",action:{})
    private let removeButton = TransferActionButton("",symbol:"xmark",action:{})
    private var tracking: NSTrackingArea?
    var request: QLThumbnailGenerator.Request?
    init(file: RecentLibraryFile, remove: @escaping () -> Void, language: String, ink: NSColor, open: @escaping () -> Void) {
        super.init(frame:.zero); self.open = open; setAccessibilityElement(true); setAccessibilityRole(.group)
        wantsLayer = true; layer?.cornerRadius = 10; focusRingType = .none
        nameLabel.stringValue = file.url.lastPathComponent; nameLabel.font = .systemFont(ofSize:13,weight:.medium); nameLabel.textColor = ink; nameLabel.lineBreakMode = .byTruncatingTail
        let formatter = RelativeDateTimeFormatter(); formatter.locale = Locale(identifier:language); formatter.unitsStyle = .full
        dateLabel.stringValue = formatter.localizedString(for:file.date,relativeTo:Date()); dateLabel.font = .systemFont(ofSize:12); dateLabel.textColor = ink.withAlphaComponent(0.55)
        thumbnail.imageScaling = .scaleProportionallyUpOrDown; thumbnail.wantsLayer = true; thumbnail.layer?.cornerRadius = 7; thumbnail.layer?.masksToBounds = true
        thumbnail.image = NSWorkspace.shared.icon(forFile:file.url.path)
        revealButton.invoke = { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }; removeButton.invoke = remove
        revealButton.toolTip = language == "fr" ? "Afficher dans le Finder" : "Show in Finder"; removeButton.toolTip = language == "fr" ? "Retirer de la liste" : "Remove from list"
        for button in [revealButton,removeButton] { button.wantsLayer = true; button.layer?.cornerRadius = 6; button.contentTintColor = ink; button.alphaValue = 0; button.setAccessibilityLabel(button.toolTip) }
        for v in [thumbnail,nameLabel,dateLabel,revealButton,removeButton] { addSubview(v) }
        setAccessibilityLabel(nameLabel.stringValue+", "+dateLabel.stringValue); toolTip = nameLabel.stringValue
        let request = QLThumbnailGenerator.Request(fileAt:file.url,size:NSSize(width:48,height:48),scale:2,representationTypes:.thumbnail); self.request = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for:request) { [weak self] result,_ in
            guard let result else { return }; DispatchQueue.main.async { [weak self] in self?.thumbnail.image = result.nsImage; self?.request = nil }
        }
    }
    required init?(coder:NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect:NSRect) {}
    override func layout() {
        super.layout(); thumbnail.frame = NSRect(x:3,y:7,width:40,height:40)
        nameLabel.frame = NSRect(x:54,y:11,width:max(20,bounds.width-62),height:19)
        dateLabel.frame = NSRect(x:54,y:30,width:max(20,bounds.width-112),height:18)
        revealButton.frame = NSRect(x:bounds.width-51,y:29,width:23,height:23); removeButton.frame = NSRect(x:bounds.width-26,y:29,width:23,height:23)
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event:NSEvent) {}
    override func mouseUp(with event:NSEvent) { if bounds.contains(convert(event.locationInWindow,from:nil)) { open?() } }
    override func accessibilityPerformPress() -> Bool { open?(); return true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.activeAlways,.inVisibleRect,.mouseEnteredAndExited],owner:self); addTrackingArea(tracking!)
        if let window { hover(!isHiddenOrHasHiddenAncestor && visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream,from:nil))) }
    }
    func refreshHover() { if let window { hover(!isHiddenOrHasHiddenAncestor && visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream,from:nil))) } }
    private func hover(_ value:Bool) {
        guard hovered != value else { return }; hovered = value
        layer?.backgroundColor = NSColor.white.withAlphaComponent(value ? 0.08 : 0).cgColor
        NSAnimationContext.runAnimationGroup { context in context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14; revealButton.animator().alphaValue = value ? 1 : 0; removeButton.animator().alphaValue = value ? 1 : 0 }
    }
    override func mouseEntered(with event:NSEvent) { hover(true) }
    override func mouseExited(with event:NSEvent) { hover(false) }
    deinit { if let request { QLThumbnailGenerator.shared.cancel(request) } }
}

final class RecentMediaPeek: NSView, QLPreviewPanelDataSource {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    private var presented = false
    private var rows: [RecentFileRow] = []
    private var files: [RecentLibraryFile] = []
    private var cards: [DownloadCard] = []
    private var downloadIDs: [String] = []
    private let allButton = ActionButton("",action:{})
    var transferAction: ((String,String) -> Void)?
    var transferRemove: ((String) -> Void)?
    var removeRecent: ((URL) -> Void)?
    var transferSeen: ((String) -> Void)?
    var showDownloads: (() -> Void)?
    private var previewURL: URL?
    private var animationToken = 0
    private let emptyLabel = NSTextField(wrappingLabelWithString:"")
    var desiredHeight: CGFloat { cards.isEmpty ? CGFloat(max(1,rows.count))*56+4 : CGFloat(cards.count)*102+34 }
    override var acceptsFirstResponder: Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame); wantsLayer = true; isHidden = true
        allButton.isHidden = true; allButton.invoke = { [weak self] in self?.showDownloads?() }; addSubview(allButton)
        emptyLabel.font = .systemFont(ofSize:12); emptyLabel.alignment = .center; addSubview(emptyLabel)
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(files: [RecentLibraryFile], downloads: [LibraryDownload] = [], ink: NSColor, language: String, loading: Bool) {
        let ids = downloads.map(\.id)
        if ids != downloadIDs {
            cards.forEach { $0.removeFromSuperview() }; downloadIDs = ids
            cards = downloads.map { _ in
                let card = DownloadCard(frame:.zero)
                card.action = { [weak self] in self?.transferAction?($0,$1) }
                card.removeRecord = { [weak self] in self?.transferRemove?($0) }
                card.seen = { [weak self] in self?.transferSeen?($0) }
                card.open = { [weak self] in self?.preview($0) }
                addSubview(card); return card
            }
        }
        for (card,record) in zip(cards,downloads) { card.update(record,language:language,ink:ink) }
        allButton.isHidden = cards.isEmpty; allButton.title = language == "fr" ? "Tous les téléchargements" : "All Downloads"; allButton.contentTintColor = ink
        rows.forEach { $0.isHidden = !cards.isEmpty }
        if !cards.isEmpty { emptyLabel.isHidden = true; needsLayout = true; return }
        emptyLabel.stringValue = L10n.text(loading ? "loadingMedia" : "nothingHere",language:language); emptyLabel.textColor = ink.withAlphaComponent(0.65); emptyLabel.isHidden = !files.isEmpty
        guard self.files != files else { return }; self.files = files
        rows.forEach { $0.removeFromSuperview() }
        rows = files.map { file in RecentFileRow(file:file,remove:{ [weak self] in self?.removeRecent?(file.url) },language:language,ink:ink) { [weak self] in self?.preview(file.url) } }
        rows.forEach(addSubview); needsLayout = true
    }
    override func layout() {
        super.layout()
        for (i,row) in rows.enumerated() { row.frame = NSRect(x:5,y:CGFloat(i)*56,width:bounds.width-10,height:54); row.layout() }
        for (i,card) in cards.enumerated() { card.frame = NSRect(x:5,y:CGFloat(i)*102,width:bounds.width-10,height:98); card.layout() }
        allButton.frame = NSRect(x:12,y:bounds.height-29,width:bounds.width-24,height:25)
        emptyLabel.frame = NSRect(x:12,y:10,width:bounds.width-24,height:40)
    }
    override func hitTest(_ point:NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        // Static labels and thumbnails belong to their row. Keep real buttons as targets.
        guard presented else { return self }
        var view: NSView? = hit
        while let candidate = view, candidate !== self {
            if candidate is NSButton || candidate is RecentFileRow || candidate is DownloadCard { return candidate }
            view = candidate.superview
        }
        return self
    }
    // Empty shelf areas end the responder chain here, including while fading out.
    override func mouseDown(with event:NSEvent) {}
    override func mouseDragged(with event:NSEvent) {}
    override func mouseUp(with event:NSEvent) {}
    override func rightMouseDown(with event:NSEvent) {}
    override func otherMouseDown(with event:NSEvent) {}
    override func scrollWheel(with event:NSEvent) {}
    override func menu(for event:NSEvent) -> NSMenu? { nil }

    func refreshHover() { rows.forEach { $0.refreshHover() }; cards.forEach { $0.refreshHover() } }
    func setPresented(_ visible: Bool, animated: Bool = true) {
        animationToken += 1
        let token = animationToken
        let previous = isHidden ? Float(0) : layer?.presentation()?.opacity ?? 1
        presented = visible
        layer?.removeAnimation(forKey:"peekOpacity")
        let duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? shelfFadeTime : 0
        guard duration > 0 else { isHidden = !visible; return }
        // Keep AppKit's input surface stationary and active until the last visible frame.
        isHidden = false
        let fade = CABasicAnimation(keyPath:"opacity")
        fade.fromValue = previous; fade.toValue = visible ? 1 : 0
        fade.duration = duration; fade.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
        let delay = visible ? duration : 0
        fade.beginTime = CACurrentMediaTime()+delay
        fade.fillMode = .both; fade.isRemovedOnCompletion = false
        layer?.add(fade,forKey:"peekOpacity")
        DispatchQueue.main.asyncAfter(deadline:.now()+delay+duration) { [weak self] in
            guard let self, self.animationToken == token else { return }
            self.isHidden = !visible
            self.layer?.removeAnimation(forKey:"peekOpacity")
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
