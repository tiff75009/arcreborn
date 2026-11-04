import AppKit
import Quartz
import QuickLookThumbnailing
import QuartzCore

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
    override func mouseUp(with event:NSEvent) { open?() }
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

final class RecentMediaPeek: ThemeBackdropView, QLPreviewPanelDataSource {
    private let fadeMask = CAGradientLayer()
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
    var desiredHeight: CGFloat { cards.isEmpty ? CGFloat(max(1,rows.count))*56+30 : CGFloat(cards.count)*102+58 }
    override var acceptsFirstResponder: Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame); wantsLayer = true; isHidden = true
        fadeMask.colors = [NSColor.clear.cgColor,NSColor.black.cgColor,NSColor.black.cgColor]; fadeMask.locations = [0,0.14,1]; fadeMask.startPoint = CGPoint(x:0.5,y:0); fadeMask.endPoint = CGPoint(x:0.5,y:1); layer?.mask = fadeMask
        allButton.isHidden = true; allButton.invoke = { [weak self] in self?.showDownloads?() }; addSubview(allButton)
        emptyLabel.font = .systemFont(ofSize:12); emptyLabel.alignment = .center; addSubview(emptyLabel)
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(files: [RecentLibraryFile], downloads: [LibraryDownload] = [], theme: SpaceTheme, dark: Bool, ink: NSColor, language: String, loading: Bool) {
        self.theme = theme; self.dark = dark
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
        super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); fadeMask.frame = bounds; CATransaction.commit()
        for (i,row) in rows.enumerated() { row.frame = NSRect(x:5,y:26+CGFloat(i)*56,width:bounds.width-10,height:54); row.layout() }
        for (i,card) in cards.enumerated() { card.frame = NSRect(x:5,y:24+CGFloat(i)*102,width:bounds.width-10,height:98); card.layout() }
        allButton.frame = NSRect(x:12,y:bounds.height-29,width:bounds.width-24,height:25)
        emptyLabel.frame = NSRect(x:12,y:36,width:bounds.width-24,height:40)
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.saveGraphicsState(); bounds.clip()
        ThemePainter.draw(theme,in:NSRect(x:0,y:-frame.minY,width:bounds.width,height:superview?.bounds.height ?? bounds.height),dark:dark)
        NSGraphicsContext.restoreGraphicsState()
    }
    func refreshHover() { rows.forEach { $0.refreshHover() }; cards.forEach { $0.refreshHover() } }
    func setPresented(_ presented: Bool, animated: Bool = true) {
        animationToken += 1; let token = animationToken
        let duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? (presented ? 0.32 : 0.20) : 0
        let previous = layer?.presentation()?.opacity ?? (isHidden ? 0 : 1)
        isHidden = false; alphaValue = presented ? 1 : 0
        let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = previous; fade.toValue = presented ? 1 : 0; fade.duration = duration; layer?.add(fade,forKey:"peekOpacity")
        let slide = CABasicAnimation(keyPath:"transform.translation.y"); slide.fromValue = layer?.presentation()?.value(forKeyPath:"transform.translation.y") ?? (presented ? 18 : 0); slide.toValue = presented ? 0 : 12; slide.duration = duration; slide.timingFunction = CAMediaTimingFunction(controlPoints:0.2,0.8,0.2,1); layer?.add(slide,forKey:"peekSlide")
        if presented {
            for (i,row) in (cards.isEmpty ? rows.map { $0 as NSView } : cards.map { $0 as NSView }).enumerated() {
                let animation = CABasicAnimation(keyPath:"transform.translation.x"); animation.fromValue = -18; animation.toValue = 0; animation.duration = duration; animation.beginTime = CACurrentMediaTime()+Double(i)*0.025; animation.fillMode = .backwards; animation.timingFunction = CAMediaTimingFunction(name:.easeOut); row.layer?.add(animation,forKey:"peekRow")
            }
        } else { DispatchQueue.main.asyncAfter(deadline:.now()+duration) { [weak self] in if self?.animationToken == token { self?.isHidden = true } } }
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
