import AppKit
import QuartzCore

private class CreationFlippedView: NSView { override var isFlipped: Bool { true } }
private final class CreationButton: NSButton {
    var invoke: (() -> Void)?
    var fill = NSColor.clear { didSet { needsDisplay = true } }
    var foreground = NSColor.white { didSet { needsDisplay = true } }
    var symbol: String?
    var leading = false
    private var hovered = false
    private var tracking: NSTrackingArea?
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        self.symbol = symbol; invoke = action
        super.init(frame:.zero)
        self.title = title; isBordered = false; font = .systemFont(ofSize:14,weight:.semibold)
        target = self; self.action = #selector(activate); focusRingType = .none
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func activate() { invoke?() }
    override func draw(_ dirtyRect: NSRect) {
        fill.withAlphaComponent(fill.alphaComponent * (isEnabled ? 1 : 0.45)).setFill(); NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill()
        if hovered && isEnabled { NSColor.white.withAlphaComponent(0.06).setFill(); NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill() }
        let color = foreground.withAlphaComponent(foreground.alphaComponent * (isEnabled ? 1 : 0.38))
        if let symbol, let icon = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[color])) {
            icon.draw(in:NSRect(x:leading ? 9 : (bounds.width-18)/2,y:(bounds.height-18)/2,width:18,height:18))
        }
        let text = NSAttributedString(string:title,attributes:[.font:font ?? .systemFont(ofSize:14),.foregroundColor:color])
        text.draw(at:NSPoint(x:leading ? 33 : (bounds.width-text.size().width)/2,y:(bounds.height-text.size().height)/2))
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self); addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
}

private final class SpaceCardsView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        for (x,angle,emoji) in [(17.0,14.0,"🌿"),(51.0,-14.0,"📚"),(34.0,0.0,"💻")] {
            NSGraphicsContext.saveGraphicsState()
            let transform = AffineTransform(translationByX:x,byY:bounds.midY)
            let t = NSAffineTransform(transform:transform); t.rotate(byDegrees:angle); t.concat()
            let card = NSBezierPath(roundedRect:NSRect(x:-16,y:-21,width:32,height:42),xRadius:3,yRadius:3)
            let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.2); shadow.shadowBlurRadius = 3; shadow.shadowOffset = NSSize(width:0,height:-1); shadow.set()
            NSColor.white.setFill(); card.fill()
            NSShadow().set()
            let label = NSAttributedString(string:emoji,attributes:[.font:NSFont.systemFont(ofSize:23)])
            label.draw(at:NSPoint(x:-label.size().width/2,y:-label.size().height/2))
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

final class SpaceCreationView: NSView, NSTextFieldDelegate {
    var cancel: (() -> Void)?
    var commit: ((SpaceCreationDraft) -> String?)?
    var completed: (() -> Void)?
    var chooseTheme: (() -> Void)?
    var didEnter: (() -> Void)?
    var selectExistingSpace: ((String) -> Void)?
    private(set) var draft: SpaceCreationDraft
    private var iconPicker: SpaceIconPicker?
    private let profiles: [NativeProfile]
    private let language: String
    var sidebarWidth: CGFloat = 240 { didSet { needsLayout = true } }
    private let preview = ThemeBackdropView()
    private let form = CreationFlippedView()
    private let cards = SpaceCardsView()
    private let heading = NSTextField(labelWithString:"")
    private let subtitle = NSTextField(wrappingLabelWithString:"")
    private let nameRow = CreationFlippedView(), profileRow = CreationFlippedView()
    private let name = NSTextField()
    private var iconButton: CreationButton!, themeButton: CreationButton!, createButton: CreationButton!, cancelButton: CreationButton!, infoButton: CreationButton!
    private let profileLabel = NSTextField(labelWithString:"")
    private let profilePicker = NSPopUpButton()
    private let profileIcon = NSImageView()
    private let errorLabel = NSTextField(wrappingLabelWithString:"")
    private let emblem = SpaceCardsView()
    private let dots = HorizontalSpaceScrollView()
    private let spaceDots = SpaceDockView()
    private var help: NSPopover?
    private var customTheme = false
    private var committing = false
    private var ending = false
    private var completionTask: DispatchWorkItem?
    private var keyMonitor: Any?
    private var animatedFields: [NSView] { [cards,heading,subtitle,nameRow,profileRow,themeButton,createButton,cancelButton,dots] }
    override var isFlipped: Bool { true }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private func t(_ key: String) -> String { L10n.text(key,language:language) }
    init(draft: SpaceCreationDraft, profiles: [NativeProfile], spaces: [NativeSpace], activeSpaceID: String, language: String) {
        self.draft = draft; self.profiles = profiles; self.language = language
        super.init(frame:.zero)
        wantsLayer = true; layer?.masksToBounds = true
        appearance = NSAppearance(named:.darkAqua)
        preview.wantsLayer = true; preview.layer?.cornerRadius = 6; preview.layer?.masksToBounds = true
        preview.theme = SpaceTheme(points:[ThemePoint(color:"#2C2B3A",x:0.15,y:0.3),ThemePoint(color:"#332A3A",x:0.85,y:0.8)],gradient:0.07,grain:0.14)
        preview.dark = false
        addSubview(preview); addSubview(form)
        for item in [cards,heading,subtitle,nameRow,profileRow,errorLabel,dots,emblem] { item.wantsLayer = true; form.addSubview(item) }
        heading.stringValue = t("createSpaceTitle"); heading.font = .systemFont(ofSize:18,weight:.bold); heading.textColor = .white; heading.alignment = .center
        subtitle.stringValue = t("createSpaceSubtitle"); subtitle.font = .systemFont(ofSize:14,weight:.medium); subtitle.textColor = NSColor.white.withAlphaComponent(0.88); subtitle.alignment = .center
        for row in [nameRow,profileRow] { row.layer?.cornerRadius = 8; row.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor }
        name.isBezeled = false; name.drawsBackground = false; name.focusRingType = .none; name.font = .systemFont(ofSize:14,weight:.semibold); name.textColor = .white; name.delegate = self
        name.placeholderAttributedString = NSAttributedString(string:t("spaceNamePlaceholder"),attributes:[.foregroundColor:NSColor.white.withAlphaComponent(0.48),.font:NSFont.systemFont(ofSize:14,weight:.semibold)])
        name.setAccessibilityLabel(t("name")); nameRow.addSubview(name)
        iconButton = CreationButton("",symbol:"plus.square.dashed") { [weak self] in self?.showIcons() }; iconButton.setAccessibilityLabel(t("changeSpaceIcon")); iconButton.foreground = NSColor.white.withAlphaComponent(0.55); nameRow.addSubview(iconButton)
        profileIcon.image = NSImage(systemSymbolName:"face.smiling",accessibilityDescription:nil); profileIcon.contentTintColor = NSColor.white.withAlphaComponent(0.55); profileRow.addSubview(profileIcon)
        profileLabel.stringValue = t("profile"); profileLabel.font = .systemFont(ofSize:14,weight:.semibold); profileLabel.textColor = .white; profileRow.addSubview(profileLabel)
        profilePicker.addItems(withTitles:profiles.map(\.name)); profilePicker.selectItem(at:profiles.firstIndex(where: { $0.id == draft.profileID }) ?? 0)
        profilePicker.font = .systemFont(ofSize:12,weight:.semibold); profilePicker.bezelStyle = .rounded; profilePicker.target = self; profilePicker.action = #selector(profileChanged)
        profilePicker.setAccessibilityLabel(t("profile")); profileRow.addSubview(profilePicker)
        infoButton = CreationButton("",symbol:"questionmark.circle") { [weak self] in self?.showHelp() }; infoButton.setAccessibilityLabel(t("profileHelp")); infoButton.toolTip = t("profileHelp"); profileRow.addSubview(infoButton)
        themeButton = CreationButton(t("chooseSpaceTheme"),symbol:"paintbrush.fill") { [weak self] in self?.help?.close(); self?.chooseTheme?() }; themeButton.leading = true; themeButton.fill = NSColor.white.withAlphaComponent(0.09)
        createButton = CreationButton(t("createSpaceButton")) { [weak self] in self?.submit() }; createButton.fill = NSColor(srgbRed:0.24,green:0.20,blue:0.97,alpha:1); createButton.isEnabled = false
        cancelButton = CreationButton(t("cancel")) { [weak self] in if self?.committing == false { self?.cancel?() } }; cancelButton.foreground = NSColor.white.withAlphaComponent(0.58); cancelButton.font = .systemFont(ofSize:13,weight:.semibold)
        for item in [themeButton!,createButton!,cancelButton!] { item.wantsLayer = true; form.addSubview(item) }
        errorLabel.font = .systemFont(ofSize:11); errorLabel.textColor = .systemRed
        dots.drawsBackground = false; dots.borderType = .noBorder; dots.hasHorizontalScroller = true
        dots.autohidesScrollers = true; dots.scrollerStyle = .overlay; dots.documentView = spaceDots
        let items = spaces.map { SpaceDockView.Item(id:$0.id,name:$0.name,icon:$0.icon) }
        spaceDots.update(items+[.init(id:"creation-draft",name:t("createSpaceTitle"),icon:"none",enabled:false)],
                         selectedID:activeSpaceID,ink:.white,select:{ [weak self] id in
            guard let self, !self.committing, !self.ending else { return }; self.selectExistingSpace?(id)
        })
        dots.pointerAfterScroll = { [weak self] in self?.spaceDots.trackPointer($0) }
        emblem.alphaValue = 0
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; completionTask?.cancel() }
    override func draw(_ dirtyRect: NSRect) {
        if customTheme { ThemePainter.draw(draft.theme,in:bounds,dark:true) }
        else { NSColor(srgbRed:0.035,green:0.035,blue:0.09,alpha:1).setFill(); bounds.fill() }
        // Passive navigation chrome preserves the reference's quiet top row.
        for (symbol,x) in [("sidebar.left",CGFloat(86)),("arrow.left",sidebarWidth-94),("arrow.right",sidebarWidth-60),("arrow.clockwise",sidebarWidth-26)] {
            NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[NSColor.white.withAlphaComponent(0.35)]))?.draw(in:NSRect(x:x-9,y:14,width:18,height:18))
        }
    }
    override func layout() {
        super.layout()
        preview.frame = NSRect(x:sidebarWidth+2,y:7,width:max(100,bounds.width-sidebarWidth-10),height:max(100,bounds.height-17))
        form.frame = NSRect(x:8,y:0,width:sidebarWidth-16,height:bounds.height)
        let width = form.bounds.width
        cards.frame = NSRect(x:(width-68)/2,y:82,width:68,height:48)
        heading.frame = NSRect(x:0,y:142,width:width,height:30)
        subtitle.frame = NSRect(x:8,y:175,width:width-16,height:48)
        nameRow.frame = NSRect(x:0,y:241,width:width,height:36)
        iconButton.frame = NSRect(x:5,y:5,width:26,height:26); name.frame = NSRect(x:34,y:8,width:width-43,height:24)
        profileRow.frame = NSRect(x:0,y:283,width:width,height:36)
        profileIcon.frame = NSRect(x:10,y:10,width:16,height:16); profileLabel.frame = NSRect(x:32,y:9,width:53,height:22)
        profilePicker.frame = NSRect(x:80,y:6,width:max(60,width-112),height:25); infoButton.frame = NSRect(x:width-28,y:5,width:24,height:26)
        themeButton.frame = NSRect(x:0,y:327,width:width,height:36)
        errorLabel.frame = NSRect(x:4,y:370,width:width-8,height:48)
        createButton.frame = NSRect(x:0,y:max(425,bounds.height-132),width:width,height:36)
        cancelButton.frame = NSRect(x:0,y:max(469,bounds.height-88),width:width,height:30)
        dots.frame = NSRect(x:0,y:bounds.height-39,width:width,height:34)
        spaceDots.fit(width:width)
        emblem.frame = NSRect(x:(width-68)/2,y:(bounds.height-60)/2,width:68,height:60)
    }
    func show() {
        layoutSubtreeIfNeeded()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self, event.window === self.window, !self.ending else { return event }
            if event.keyCode == 53 && self.help?.isShown != true { if !self.committing { self.cancel?() }; return nil }
            return event
        }
        if !reduceMotion, let layer {
            let offset = -bounds.width
            CATransaction.begin(); CATransaction.setDisableActions(true); layer.transform = CATransform3DMakeTranslation(offset,0,0); CATransaction.commit()
            window?.displayIfNeeded()
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.ending, let layer = self.layer else { return }
                CATransaction.begin(); CATransaction.setDisableActions(true); layer.transform = CATransform3DIdentity; CATransaction.commit()
                let slide = CABasicAnimation(keyPath:"transform.translation.x"); slide.fromValue = offset; slide.toValue = 0; slide.duration = 0.32
                slide.timingFunction = CAMediaTimingFunction(controlPoints:0.2,0.75,0.25,1); layer.add(slide,forKey:"creation-enter")
                DispatchQueue.main.asyncAfter(deadline:.now()+0.33) { [weak self] in guard let self, !self.ending else { return }; self.didEnter?() }
            }
        } else { didEnter?() }
        window?.makeFirstResponder(name)
    }
    func updateTheme(_ theme: SpaceTheme, appearance: ThemeAppearance) {
        guard !committing, theme.validated() else { return }
        draft.theme = theme; draft.appearance = appearance; customTheme = true
        preview.theme = theme; preview.dark = appearance == .dark
        needsDisplay = true
    }
    func controlTextDidChange(_ notification: Notification) {
        draft.name = name.stringValue; errorLabel.stringValue = ""
        createButton.isEnabled = draft.isValid; createButton.needsDisplay = true
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { submit(); return true }
        return false
    }
    @objc private func profileChanged() { if profiles.indices.contains(profilePicker.indexOfSelectedItem) { draft.profileID = profiles[profilePicker.indexOfSelectedItem].id } }
    private func showIcons() {
        guard !committing else { return }
        iconPicker?.close()
        let picker = SpaceIconPicker(value:draft.icon,language:language,change:{ [weak self] value in
            guard let self else { return }
            self.draft.icon = value; self.iconButton.symbol = SpaceIcon.symbol(value)
            self.iconButton.title = SpaceIcon.caption(value); self.iconButton.needsDisplay = true
        },dismissed:{ [weak self] in self?.iconPicker = nil })
        iconPicker = picker; picker.show(relativeTo:iconButton.bounds,of:iconButton)
    }
    private func showHelp() {
        if let help, help.isShown { help.close(); self.help = nil; return }
        let popover = NSPopover(); popover.behavior = .transient; popover.appearance = NSAppearance(named:.darkAqua)
        let view = NSView(frame:NSRect(x:0,y:0,width:205,height:98)); view.wantsLayer = true; view.layer?.backgroundColor = NSColor(srgbRed:0.045,green:0.045,blue:0.27,alpha:1).cgColor
        let text = NSTextField(wrappingLabelWithString:t("creationProfileInfo")); text.font = .systemFont(ofSize:12,weight:.medium); text.textColor = NSColor(srgbRed:0.76,green:0.76,blue:0.93,alpha:1); text.frame = NSRect(x:16,y:12,width:173,height:74); view.addSubview(text)
        let controller = NSViewController(); controller.view = view; popover.contentViewController = controller; popover.contentSize = view.frame.size
        help = popover; popover.show(relativeTo:infoButton.bounds,of:infoButton,preferredEdge:.maxX)
    }
    private func submit() {
        guard !committing, !ending, draft.isValid else { return }
        help?.close(); help = nil
        if let error = commit?(draft) { errorLabel.stringValue = error; return }
        committing = true; window?.makeFirstResponder(self)
        for field in [name as NSControl,profilePicker,iconButton!,themeButton!,createButton!,cancelButton!,infoButton!] { field.isEnabled = false }
        if reduceMotion { completed?(); return }
        for (index,view) in animatedFields.enumerated() {
            guard let layer = view.layer else { continue }
            let move = CABasicAnimation(keyPath:"transform.translation.y"); move.fromValue = 0; move.toValue = -70
            let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = 1; fade.toValue = 0
            let group = CAAnimationGroup(); group.animations = [move,fade]; group.duration = 0.30; group.beginTime = CACurrentMediaTime()+Double(index)*0.022
            group.timingFunction = CAMediaTimingFunction(controlPoints:0.3,0,0.3,1); group.fillMode = .forwards; group.isRemovedOnCompletion = false
            layer.add(group,forKey:"creation-submit")
        }
        emblem.alphaValue = 1
        let scale = CAKeyframeAnimation(keyPath:"transform.scale"); scale.values = [0.35,1.12,1]; scale.keyTimes = [0,0.7,1]
        let rotate = CABasicAnimation(keyPath:"transform.rotation.z"); rotate.fromValue = -0.3; rotate.toValue = 0
        let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = 0; fade.toValue = 1
        let group = CAAnimationGroup(); group.animations = [scale,rotate,fade]; group.beginTime = CACurrentMediaTime()+0.34; group.duration = 0.36; group.fillMode = .backwards
        group.timingFunction = CAMediaTimingFunction(controlPoints:0.22,0.75,0.25,1); emblem.layer?.add(group,forKey:"space-emblem")
        let task = DispatchWorkItem { [weak self] in guard let self, !self.ending else { return }; self.completed?() }
        completionTask = task; DispatchQueue.main.asyncAfter(deadline:.now()+2.70,execute:task)
    }
    func dismiss(created: Bool, completion: @escaping () -> Void) {
        guard !ending else { return }; ending = true
        help?.close(); help = nil; completionTask?.cancel()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        guard !reduceMotion else { completion(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = created ? 0.18 : 0.24; context.timingFunction = CAMediaTimingFunction(controlPoints:0.3,0,0.2,1)
            self.animator().alphaValue = 0
        } completionHandler: { completion() }
        if !created, let layer {
            let slide = CABasicAnimation(keyPath:"transform.translation.x"); slide.fromValue = 0; slide.toValue = -bounds.width; slide.duration = 0.24
            slide.timingFunction = CAMediaTimingFunction(controlPoints:0.3,0,0.2,1); slide.fillMode = .forwards; slide.isRemovedOnCompletion = false; layer.add(slide,forKey:"creation-cancel")
        }
    }
}
