// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

private func ink(_ rgb: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 255)/255, green: CGFloat((rgb >> 8) & 255)/255,
            blue: CGFloat(rgb & 255)/255, alpha: alpha)
}

private enum ArrivalMotion {
    static let scene: CFTimeInterval = 2.28
    static let mark: CFTimeInterval = 1.83
    static let type: CFTimeInterval = 0.88
    static let settle = CAMediaTimingFunction(controlPoints: 0.22, 0.82, 0.35, 1)
    static let glide = CAMediaTimingFunction(controlPoints: 0.32, 0.02, 0.12, 1)
}

private class WelcomeDrawing: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    var dark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua,.aqua]) == .darkAqua }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// Intaglio-like bands. Each line is a section through the same folded ribbon.
/// Drawn once per appearance/size; only the backing layer moves during the intro.
private final class WelcomeEngraving: WelcomeDrawing {
    let right: Bool
    init(right: Bool) { self.right = right; super.init(frame:.zero); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.scaleBy(x: bounds.width/840, y: bounds.height/360)
        let lines = CGMutablePath()
        for n in 0...65 {
            let t = CGFloat(n)/65, bow = sin(t * .pi)
            if !right {
                lines.move(to: CGPoint(x:-84,y:122+150*t))
                lines.addCurve(to: CGPoint(x:156+48*t,y:164+115*t),
                               control1: CGPoint(x:35-18*t,y:-40+98*t),
                               control2: CGPoint(x:79+38*t,y:82+166*t))
                lines.addCurve(to: CGPoint(x:390+12*t,y:229-8*t),
                               control1: CGPoint(x:232+52*t,y:244+157*t-28*bow),
                               control2: CGPoint(x:303+28*t,y:308-35*t))
            } else {
                lines.move(to: CGPoint(x:463+7*t,y:208-14*t))
                lines.addCurve(to: CGPoint(x:630+86*t,y:108+34*t),
                               control1: CGPoint(x:549+62*t,y:224-75*t),
                               control2: CGPoint(x:555+38*t,y:130-142*t))
                lines.addCurve(to: CGPoint(x:923,y:14+201*t),
                               control1: CGPoint(x:694+64*t,y:89+152*t+25*bow),
                               control2: CGPoint(x:780+70*t,y:127+11*t))
            }
        }
        ctx.addPath(lines); ctx.setLineWidth(0.92); ctx.setLineCap(.round); ctx.replacePathWithStrokedPath(); ctx.clip()
        let colors: [NSColor]
        if right {
            colors = dark ? [ink(0x645DFF,0.26),ink(0xB096FF,0.96),ink(0x697AEF,0.44)] : [ink(0x6454BB,0.25),ink(0x603DA6,0.85),ink(0x5168C2,0.52)]
        } else {
            colors = dark ? [ink(0x5398EC,0.65),ink(0x82E5EC,0.95),ink(0x506AB8,0.26)] : [ink(0x3C84BE,0.68),ink(0x137891,0.85),ink(0x5378B7,0.24)]
        }
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map(\.cgColor) as CFArray, locations:[0,0.52,1]) {
            ctx.drawLinearGradient(gradient, start:CGPoint(x:right ? 463 : 0,y:0), end:CGPoint(x:right ? 840 : 400,y:0), options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
        }
    }
}

private final class WelcomePaper: WelcomeDrawing {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width, h = bounds.height
        let base = dark ? ink(0x10101D) : ink(0xF7F5F2)
        base.setFill(); bounds.fill()
        func pool(_ point: CGPoint, _ radius: CGFloat, _ rgb: UInt32, _ alpha: CGFloat) {
            guard let g = CGGradient(colorsSpace: CGColorSpace(name:CGColorSpace.sRGB),
                                     colors:[ink(rgb,alpha).cgColor,ink(rgb,0).cgColor] as CFArray, locations:[0,1]) else { return }
            ctx.drawRadialGradient(g,startCenter:point,startRadius:0,endCenter:point,endRadius:radius,options:[])
        }
        pool(CGPoint(x:0,y:h*0.29),w*0.74,dark ? 0x173D64 : 0xB0DDE4,dark ? 0.62 : 0.58)
        pool(CGPoint(x:w*0.85,y:h*0.24),w*0.62,dark ? 0x4F317B : 0xD0BFF0,dark ? 0.52 : 0.56)
        pool(CGPoint(x:w*0.48,y:h*0.33),w*0.29,dark ? 0x536496 : 0xFFFFFF,dark ? 0.18 : 0.74)
    }
}

/// Keep one source of truth for the mark: the same three vectors as Icon Composer.
private final class WelcomeRibbonMark: WelcomeDrawing {
    private static let pieces = ["01-ribbon-right","02-ribbon-arch","03-ribbon-sweep"].compactMap {
        Bundle.main.url(forResource:$0, withExtension:"png", subdirectory:"Welcome").flatMap(NSImage.init(contentsOf:))
    }
    override func draw(_ dirtyRect: NSRect) {
        guard Self.pieces.count == 3 else {
            NSApp.applicationIconImage?.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            return
        }
        for sheet in Self.pieces {
            sheet.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
        }
    }
}

/// Later chapters use the same paper, original mark and etched strands as the opening.
final class WelcomeChapterArt: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    init(frame:NSRect, account:Bool) {
        super.init(frame:frame)
        let paper = WelcomePaper(frame:bounds); paper.autoresizingMask = [.width,.height]; addSubview(paper)
        let band = WelcomeEngraving(right:!account)
        band.frame = account ? NSRect(x:-260,y:231,width:1170,height:257) : NSRect(x:185,y:12,width:775,height:172)
        addSubview(band)
        let mark = WelcomeRibbonMark(frame:account ? NSRect(x:169,y:299,width:179,height:179) : NSRect(x:556,y:53,width:131,height:131))
        addSubview(mark); setAccessibilityElement(false)
    }
    required init?(coder:NSCoder) { fatalError() }
}

/// A native button keeps Return, VoiceOver, the focus ring and pressed tracking.
final class ArrivalButton: NSButton {
    var invoke: (() -> Void)?
    private var hover = false
    private var area: NSTrackingArea?
    init(action: @escaping () -> Void) {
        invoke = action; super.init(frame:.zero)
        isBordered = false; bezelStyle = .regularSquare; setButtonType(.momentaryPushIn)
        keyEquivalent = "\r"; target = self; self.action = #selector(pressed)
        setAccessibilityIdentifier("welcome.start")
    }
    required init?(coder:NSCoder) { fatalError() }
    @objc private func pressed() { invoke?() }
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let area { removeTrackingArea(area) }
        area = NSTrackingArea(rect:.zero,options:[.activeInKeyWindow,.inVisibleRect,.mouseEnteredAndExited],owner:self)
        addTrackingArea(area!)
    }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func draw(_ dirtyRect:NSRect) {
        let dark = effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        let shape = NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:bounds.height/2,yRadius:bounds.height/2)
        (dark ? ink(isHighlighted ? 0xD3CFE8 : hover ? 0xFFFFFF : 0xF0EDF9) : ink(isHighlighted ? 0x433F56 : hover ? 0x302A47 : 0x211E33)).setFill(); shape.fill()
        let fg = dark ? ink(0x211E33) : ink(0xF8F6FF)
        let attrs:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:15,weight:.semibold),.foregroundColor:fg]
        let size = (title as NSString).size(withAttributes:attrs)
        (title as NSString).draw(at:.init(x:(bounds.width-size.width-27)/2,y:(bounds.height-size.height)/2),withAttributes:attrs)
        let x = (bounds.width+size.width)/2+7, y = bounds.midY
        let arrow = NSBezierPath(); arrow.move(to:.init(x:x-3,y:y)); arrow.line(to:.init(x:x+8,y:y))
        arrow.move(to:.init(x:x+3,y:y-5)); arrow.line(to:.init(x:x+8,y:y)); arrow.line(to:.init(x:x+3,y:y+5))
        fg.setStroke(); arrow.lineWidth = 1.55; arrow.lineJoinStyle = .round; arrow.lineCapStyle = .round; arrow.stroke()
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:bounds.height/2,yRadius:bounds.height/2).fill() }
}

/// Owned by the onboarding window so a replay or a round trip through Account
/// does not restart the score. Never created by the ordinary browsing window.
final class WelcomeSoundtrack {
    private var sound:NSSound?, started = false
    private(set) var muted = UserDefaults.standard.bool(forKey:"ArcRebornWelcomeMuted")
    var playing:Bool { sound?.isPlaying == true }
    func begin() {
        guard !started else { return }; started = true
        guard let url = Bundle.main.url(forResource:"arrival",withExtension:"mp3",subdirectory:"Welcome") else { return }
        sound = NSSound(contentsOf:url,byReference:true)
        sound?.loops = false; sound?.volume = muted ? 0 : 0.60; sound?.play()
    }
    func toggle() {
        muted.toggle(); UserDefaults.standard.set(muted,forKey:"ArcRebornWelcomeMuted")
        sound?.volume = muted ? 0 : 0.60
    }
    func stop() { sound?.stop(); sound = nil }
    deinit { stop() }
}

final class WelcomeIntro: NSView {
    override var isFlipped: Bool { true }
    private let paper = WelcomePaper(), left = WelcomeEngraving(right:false), right = WelcomeEngraving(right:true)
    private let mark = WelcomeRibbonMark()
    private let section = NSTextField(labelWithString:""), greeting = NSTextField(labelWithString:"")
    private let name = NSTextField(labelWithString:""), caption = NSTextField(labelWithString:""), foot = NSTextField(labelWithString:"")
    private let line = NSBox(), languagePicker = NSPopUpButton(frame:.zero,pullsDown:false)
    private let replay = NSButton(), speaker = NSButton()
    private let soundtrack:WelcomeSoundtrack
    private let start: ArrivalButton
    private let changeLanguage: (String) -> Void
    private var language: String, didArrive = false
    private var shownObserver: NSObjectProtocol?, accessibilityObserver: NSObjectProtocol?

    init(frame:NSRect, language:String,soundtrack:WelcomeSoundtrack, chooseLanguage:@escaping(String)->Void, proceed:@escaping()->Void) {
        self.soundtrack = soundtrack
        self.language = language; changeLanguage = chooseLanguage; start = ArrivalButton(action:proceed)
        super.init(frame:frame); wantsLayer = true; layer?.masksToBounds = true
        for view in [paper,left,right,mark,section,greeting,name,caption,line,foot,replay,speaker,languagePicker,start] as [NSView] { addSubview(view) }
        for artwork in [paper,left,right,mark] as [NSView] { artwork.setAccessibilityElement(false) }
        for item in [left,right,mark,greeting,name,caption] as [NSView] { item.wantsLayer = true }
        section.font = .monospacedSystemFont(ofSize:10.5,weight:.medium); section.textColor = .secondaryLabelColor
        greeting.font = .systemFont(ofSize:28,weight:.regular); greeting.textColor = .secondaryLabelColor
        name.attributedStringValue = NSAttributedString(string:"Arc Reborn.",attributes:[.font:NSFont.systemFont(ofSize:78,weight:.semibold),.kern:-1.5,.foregroundColor:NSColor.labelColor])
        caption.font = .systemFont(ofSize:16); caption.textColor = .secondaryLabelColor
        foot.font = .systemFont(ofSize:12); foot.textColor = .secondaryLabelColor
        line.boxType = .separator
        languagePicker.addItems(withTitles:["Français","English"]); languagePicker.isBordered = false; languagePicker.font = .systemFont(ofSize:12,weight:.medium)
        languagePicker.target = self; languagePicker.action = #selector(choose); languagePicker.setAccessibilityIdentifier("welcome.language")
        replay.isBordered = false; replay.image = NSImage(systemSymbolName:"arrow.counterclockwise",accessibilityDescription:nil)
        replay.target = self; replay.action = #selector(replayArrival); replay.contentTintColor = .secondaryLabelColor
        replay.isHidden = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        speaker.isBordered = false; speaker.target = self; speaker.action = #selector(toggleSound); speaker.contentTintColor = .secondaryLabelColor
        updateLanguage(); setAccessibilityChildren([section,greeting,name,caption,languagePicker,start,replay,speaker,foot])
    }
    required init?(coder:NSCoder) { fatalError() }
    private func updateLanguage() {
        let en = language == "en"
        section.stringValue = en ? "01 / 03   ·   GETTING STARTED" : "01 / 03   ·   PRISE EN MAIN"
        greeting.stringValue = en ? "Welcome to" : "Bienvenue dans"
        caption.stringValue = en ? "Your spaces, tabs and favorites, together again." : "Retrouvez vos espaces, vos onglets et vos favoris."
        foot.stringValue = en ? "An account and data import are optional." : "Le compte et l’import sont facultatifs."
        start.title = en ? "Get started" : "Commencer"; start.setAccessibilityLabel(start.title)
        languagePicker.selectItem(at:en ? 1 : 0); languagePicker.setAccessibilityLabel(en ? "Browser language" : "Langue du navigateur")
        replay.toolTip = en ? "Replay the animation" : "Revoir l’animation"; replay.setAccessibilityLabel(replay.toolTip)
        updateSpeaker()
    }
    private func updateSpeaker() {
        speaker.image = NSImage(systemSymbolName:soundtrack.muted ? "speaker.slash" : "speaker.wave.2",accessibilityDescription:nil)
        speaker.toolTip = soundtrack.muted ? (language == "en" ? "Unmute welcome music" : "Activer la musique d’accueil") : (language == "en" ? "Mute welcome music" : "Couper la musique d’accueil")
        speaker.setAccessibilityLabel(speaker.toolTip)
    }
    @objc private func toggleSound() { soundtrack.toggle(); updateSpeaker() }
    @objc private func replayArrival() { settle(); didArrive = false; arriveIfVisible() }
    @objc private func choose() { language = languagePicker.indexOfSelectedItem == 1 ? "en" : "fr"; updateLanguage(); changeLanguage(language) }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height, gutter = max(26,min(55,w*0.067))
        paper.frame = bounds; section.frame = NSRect(x:gutter,y:31,width:w-230,height:20)
        languagePicker.frame = NSRect(x:w-gutter-92,y:23,width:96,height:30)
        replay.frame = NSRect(x:w-gutter-130,y:23,width:29,height:29)
        speaker.frame = NSRect(x:w-gutter-166,y:23,width:29,height:29)
        let artTop:CGFloat = 57, artHeight = min(388,h*0.50,max(78,h-380))
        let art = NSRect(x:0,y:artTop,width:w,height:artHeight); left.frame = art; right.frame = art
        let size = min(310,artHeight*0.82)
        mark.frame = NSRect(x:(w-size)*0.50,y:art.midY-size*0.5+9,width:size,height:size)
        let titleY = art.maxY+2
        greeting.frame = NSRect(x:gutter,y:titleY,width:w-gutter*2,height:39)
        name.frame = NSRect(x:gutter-3,y:titleY+34,width:w-gutter*2+3,height:103)
        caption.frame = NSRect(x:gutter,y:titleY+144,width:w-gutter*2,height:28)
        line.frame = NSRect(x:gutter,y:h-98,width:w-gutter*2,height:1)
        foot.frame = NSRect(x:gutter,y:h-63,width:w-2*gutter-190,height:22)
        start.frame = NSRect(x:w-gutter-166,y:h-74,width:166,height:47)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let shownObserver { NotificationCenter.default.removeObserver(shownObserver); self.shownObserver = nil }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver); self.accessibilityObserver = nil }
        guard let window else { soundtrack.stop(); settle(); return }
        shownObserver = NotificationCenter.default.addObserver(forName:NSWindow.didChangeOcclusionStateNotification,object:window,queue:.main) { [weak self] _ in
            guard let self else { return }
            if self.window?.isVisible != true { self.soundtrack.stop() } else { self.arriveIfVisible() }
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil,queue:.main) { [weak self] _ in
            self?.replay.isHidden = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { self?.settle() }
        }
        DispatchQueue.main.async { [weak self] in self?.arriveIfVisible() }
    }
    deinit {
        if let shownObserver { NotificationCenter.default.removeObserver(shownObserver) }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }
    private var animatedViews: [NSView] { [left,right,mark,greeting,name,caption] }
    private func settle() {
        for item in animatedViews { item.layer?.removeAnimation(forKey:"arrival"); item.layer?.mask = nil }
    }
    private func arriveIfVisible() {
        guard window?.occlusionState.contains(.visible) == true, !didArrive else { return }
        didArrive = true; soundtrack.begin(); layoutSubtreeIfNeeded()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let now = CACurrentMediaTime()
        func enter(_ view:NSView, from start:CATransform3D, opacity:Float, delay:Double, duration:Double, ease:CAMediaTimingFunction) {
            guard let layer = view.layer else { return }
            let t = CABasicAnimation(keyPath:"transform"); t.fromValue = NSValue(caTransform3D:start); t.toValue = NSValue(caTransform3D:CATransform3DIdentity)
            let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = opacity; fade.toValue = 1
            t.duration = duration; fade.duration = duration
            let group = CAAnimationGroup(); group.animations = [t,fade]; group.timingFunction = ease
            group.beginTime = layer.convertTime(now,from:nil)+delay; group.duration = duration; group.fillMode = .backwards
            layer.add(group,forKey:"arrival")
        }
        // The engraved threads unspool outwards from the A. Its own shapes keep
        // their proportions throughout. A moving feathered mask avoids re-drawing
        // the 132 curves on every frame and leaves no running display link.
        for (i,wing) in [left,right].enumerated() {
            guard let layer = wing.layer else { continue }
            let mask = CAGradientLayer(), w = layer.bounds.width
            mask.anchorPoint = .zero; mask.bounds = CGRect(x:0,y:0,width:w*2,height:layer.bounds.height)
            mask.startPoint = CGPoint(x:0,y:0.5); mask.endPoint = CGPoint(x:1,y:0.5)
            let clear = NSColor.clear.cgColor, solid = NSColor.black.cgColor
            mask.colors = i == 0 ? [clear,solid,solid] : [solid,solid,clear]
            mask.locations = i == 0 ? [0,0.14,1] : [0,0.86,1]
            CATransaction.begin(); CATransaction.setDisableActions(true)
            mask.position = CGPoint(x:i == 0 ? -w*0.3 : 0,y:0); layer.mask = mask
            CATransaction.commit()
            let reveal = CABasicAnimation(keyPath:"position.x")
            reveal.fromValue = i == 0 ? w*0.50 : -w*1.50; reveal.toValue = mask.position.x
            reveal.beginTime = mask.convertTime(now,from:nil)+0.08; reveal.duration = ArrivalMotion.scene
            reveal.fillMode = .backwards; reveal.timingFunction = ArrivalMotion.glide
            mask.add(reveal,forKey:"unspool")
            enter(wing,from:CATransform3DMakeTranslation(i == 0 ? -24 : 24,4,0),opacity:0.5,delay:0,duration:ArrivalMotion.scene,ease:ArrivalMotion.glide)
        }
        var pull = CATransform3DMakeScale(3.15,3.15,1)
        pull = CATransform3DRotate(pull,-0.115,0,0,1)
        enter(mark,from:pull,opacity:0.08,delay:0,duration:ArrivalMotion.mark,ease:ArrivalMotion.settle)
        for (i,view) in [greeting,name,caption].enumerated() {
            enter(view,from:CATransform3DMakeTranslation(0,11,0),opacity:0,delay:0.40+Double(i)*0.14,duration:ArrivalMotion.type,ease:ArrivalMotion.settle)
        }
    }
}
