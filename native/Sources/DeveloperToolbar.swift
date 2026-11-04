import AppKit
import QuartzCore

final class DeveloperToolbar: NSView, NSTextFieldDelegate {
    let tabID: String
    private let address = NSTextField()
    private let lock = NSImageView()
    private let actionScroll = NSScrollView()
    private let actionStrip = SplitFlippedView()
    private var buttons: [String:NavigationButton] = [:]
    private var separators: [NSView] = []
    private var lastAddress = ""
    var navigate: ((String)->Void)?
    var command: ((String,NSView)->Void)?
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    static func height(for width:CGFloat) -> CGFloat { width < 560 ? 76 : 40 }

    init(tabID:String,language:String) {
        self.tabID = tabID; super.init(frame:.zero)
        wantsLayer = true; layer?.masksToBounds = true
        address.isBordered = false; address.drawsBackground = false; address.focusRingType = .none
        address.textColor = .white; address.font = .monospacedSystemFont(ofSize:12,weight:.medium)
        address.cell?.isScrollable = true; address.cell?.wraps = false; address.cell?.usesSingleLineMode = true
        address.delegate = self; address.setAccessibilityLabel(language == "fr" ? "Adresse de l’onglet — mode développeur" : "Tab address — Developer Mode")
        addSubview(address)
        lock.contentTintColor = .white.withAlphaComponent(0.8); lock.imageScaling = .scaleProportionallyDown; addSubview(lock)
        actionScroll.drawsBackground = false; actionScroll.borderType = .noBorder
        // This strip sits below our own toolbar, not beneath AppKit's title bar.
        // Automatic title-bar insets otherwise push the icons out of the strip.
        actionScroll.automaticallyAdjustsContentInsets = false; actionScroll.contentInsets = .init()
        actionScroll.hasVerticalScroller = false
        actionScroll.hasHorizontalScroller = true; actionScroll.autohidesScrollers = true; actionScroll.scrollerStyle = .overlay
        actionScroll.documentView = actionStrip; addSubview(actionScroll)
        let specs:[(String,String,String,String)] = [
            ("copy","link","Copier l’URL","Copy URL"),
            ("portrait","rectangle.inset.filled","Capture en mode portrait","Capture in Portrait Mode"),
            ("region","camera","Capturer un élément ou une portion de la page","Capture an element or area"),
            ("console","terminal","Afficher / masquer la console","Toggle Console"),
            ("network","network","Afficher / masquer le réseau","Toggle Network Panel"),
            ("inspect","scope","Inspecter un élément","Inspect Element"),
            ("extensions","puzzlepiece.extension","Extensions","Extensions"),
            ("split","rectangle.split.2x1","Vue partagée","Split View")
        ]
        var x:CGFloat = 0
        for (kind,symbol,fr,en) in specs {
            if ["portrait","console","extensions"].contains(kind) {
                let line = NSView(frame:NSRect(x:x+3,y:8,width:1,height:20)); line.wantsLayer = true
                line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor; actionStrip.addSubview(line); separators.append(line); x += 12
            }
            let button = NavigationButton(language == "fr" ? fr : en,symbol:symbol,action:{})
            button.image = button.image?.withSymbolConfiguration(.init(pointSize:16,weight:.regular))
            button.ink = .white; button.contentTintColor = .white.withAlphaComponent(0.9)
            button.toolTip = language == "fr" ? fr : en
            button.frame = NSRect(x:x,y:3,width:30,height:30)
            button.invoke = { [weak self, weak button] in guard let button else { return }; self?.command?(kind,button) }
            actionStrip.addSubview(button); buttons[kind] = button; x += 34
        }
        actionStrip.frame = NSRect(x:0,y:0,width:x,height:36)
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(url:String,tool:String,loadingCapture:Bool) {
        lastAddress = browserDisplayAddress(url)
        if address.currentEditor() == nil { address.stringValue = lastAddress }
        lock.image = NSImage(systemSymbolName:URL(string:url)?.scheme == "https" ? "lock.fill" : "globe",accessibilityDescription:nil)
        for kind in ["console","network","inspect"] { buttons[kind]?.restingFillOpacity = tool == kind ? 0.22 : 0 }
        buttons["portrait"]?.isEnabled = !loadingCapture
        buttons["portrait"]?.alphaValue = loadingCapture ? 0.4 : 1
    }
    func showCopied() {
        buttons["copy"]?.image = NSImage(systemSymbolName:"checkmark",accessibilityDescription:nil)
        DispatchQueue.main.asyncAfter(deadline:.now()+1.2) { [weak self] in self?.buttons["copy"]?.image = NSImage(systemSymbolName:"link",accessibilityDescription:nil) }
    }
    func control(_ control:NSControl,textView:NSTextView,doCommandBy selector:Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            let value = textView.string; window?.makeFirstResponder(nil); navigate?(value); return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            address.stringValue = lastAddress; window?.makeFirstResponder(nil); return true
        }
        return false
    }
    override func layout() {
        super.layout()
        let compact = bounds.width < 560
        let controlsWidth = compact ? max(0,bounds.width-16) : actionStrip.frame.width
        actionScroll.frame = NSRect(x:compact ? 8 : bounds.width-controlsWidth-9,y:compact ? 36 : 2,width:controlsWidth,height:36)
        actionScroll.tile()
        let horizontalOffset = min(max(0,actionScroll.contentView.bounds.minX),max(0,actionStrip.bounds.width-actionScroll.contentSize.width))
        actionScroll.contentView.scroll(to:NSPoint(x:horizontalOffset,y:0))
        actionScroll.reflectScrolledClipView(actionScroll.contentView)
        lock.frame = NSRect(x:14,y:12,width:13,height:16)
        let addressHeight = ceil(address.cell?.cellSize.height ?? 16)
        address.frame = NSRect(x:36,y:(40-addressHeight)/2,width:max(0,(compact ? bounds.width-12 : actionScroll.frame.minX-10)-36),height:addressHeight)
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGradient(starting:NSColor(srgbRed:0.24,green:0.25,blue:0.84,alpha:1),ending:NSColor(srgbRed:0.34,green:0.32,blue:0.9,alpha:1))?.draw(in:bounds,angle:0)
        NSColor.white.withAlphaComponent(0.028).setFill()
        for x in stride(from:-bounds.height,to:bounds.width+40,by:40) {
            let stripe = NSBezierPath(); stripe.move(to:NSPoint(x:x,y:0)); stripe.line(to:NSPoint(x:x+18,y:0))
            stripe.line(to:NSPoint(x:x+18+bounds.height,y:bounds.height)); stripe.line(to:NSPoint(x:x+bounds.height,y:bounds.height)); stripe.close(); stripe.fill()
        }
    }
}
