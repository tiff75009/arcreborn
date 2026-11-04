// SPDX-License-Identifier: MPL-2.0
import AppKit

/// Only main-frame failures reach this view. The origin label deliberately
/// excludes user info, paths and queries, which can contain credentials.
struct NavigationFailure: Equatable {
    let code: String
    let host: String?

    func copy(english: Bool) -> (symbol: String, title: String, detail: String) {
        func text(_ fr: String, _ en: String) -> String { english ? en : fr }
        switch code {
        case "ERR_INTERNET_DISCONNECTED", "ERR_NETWORK_CHANGED":
            return ("wifi.slash", text("Connexion interrompue.", "Connection interrupted."),
                    text("Vérifiez votre connexion Internet, puis réessayez.", "Check your internet connection, then try again."))
        case "ERR_NAME_NOT_RESOLVED", "ERR_NAME_RESOLUTION_FAILED":
            return ("magnifyingglass", text("Adresse introuvable.", "Address not found."),
                    text("Vérifiez l’orthographe de l’adresse. Ce nom de domaine n’a pas pu être trouvé.", "Check the spelling of the address. This domain name could not be found."))
        case "ERR_TIMED_OUT", "ERR_CONNECTION_TIMED_OUT", "ERR_DNS_TIMED_OUT":
            return ("hourglass", text("Le site tarde à répondre.", "This site took too long."),
                    text("Le délai de connexion est écoulé. Vous pouvez réessayer dans un instant.", "The connection timed out. Try again in a moment."))
        case "ERR_CONNECTION_REFUSED", "ERR_ADDRESS_UNREACHABLE", "ERR_CONNECTION_FAILED":
            return ("antenna.radiowaves.left.and.right.slash", text("Serveur inaccessible.", "Server unreachable."),
                    text("Vérifiez l’adresse ou réessayez lorsque le serveur sera disponible.", "Check the address or try again when the server is available."))
        case "ERR_CONNECTION_RESET", "ERR_CONNECTION_CLOSED", "ERR_CONNECTION_ABORTED":
            return ("bolt.slash", text("La connexion a été coupée.", "The connection was lost."),
                    text("La connexion s’est interrompue avant la fin du chargement.", "The connection closed before the page finished loading."))
        case "ERR_PROXY_CONNECTION_FAILED", "ERR_TUNNEL_CONNECTION_FAILED":
            return ("network", text("Proxy inaccessible.", "Proxy unreachable."),
                    text("Vérifiez la configuration de votre proxy ou de votre VPN.", "Check your proxy or VPN settings."))
        case let code where code.hasPrefix("ERR_SSL_") || code.hasPrefix("ERR_CERT_"):
            return ("lock.trianglebadge.exclamationmark", text("Connexion non sécurisée.", "Connection isn’t secure."),
                    text("Le navigateur n’a pas pu établir une connexion sécurisée avec ce site.", "The browser could not establish a secure connection to this website."))
        case let code where code.hasPrefix("ERR_BLOCKED_") || code == "ERR_ACCESS_DENIED" || code == "ERR_UNSAFE_PORT":
            return ("hand.raised", text("Accès bloqué.", "Access blocked."),
                    text("Les règles de sécurité empêchent l’ouverture de cette adresse.", "Security rules prevent this address from opening."))
        case "TAB_RENDERER_STOPPED", "TAB_UNAVAILABLE":
            return ("rectangle.dashed", text("Onglet interrompu.", "Tab interrupted."),
                    text("Rechargez cet onglet pour reprendre votre navigation.", "Reload this tab to continue browsing."))
        default:
            return ("network.slash", text("Page indisponible.", "Page unavailable."),
                    text("La page n’a pas pu être chargée. Réessayez ou saisissez une autre adresse.", "The page couldn’t be loaded. Try again or enter a different address."))
        }
    }
}

private final class LandingAction: NSButton {
    enum Style { case search, retry }
    var style: Style = .search
    var shortcut = ""
    var invoke: (() -> Void)?
    private var pointer: NSTrackingArea?
    private var hovered = false

    override init(frame: NSRect) {
        super.init(frame:frame)
        isBordered = false; focusRingType = .exterior
        setButtonType(.momentaryPushIn); target = self; action = #selector(activate)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func activate() { invoke?() }
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointer { removeTrackingArea(pointer) }
        let area = NSTrackingArea(rect:.zero,options:[.inVisibleRect,.activeInKeyWindow,.mouseEnteredAndExited],owner:self)
        addTrackingArea(area); pointer = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.pointingHand) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    private var shape: NSBezierPath { NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:14,yRadius:14) }
    override func drawFocusRingMask() { shape.fill() }
    override func draw(_ dirtyRect: NSRect) {
        let path = shape
        (isHighlighted || hovered ? ChapterInk.selected : ChapterInk.surface).setFill(); path.fill()
        (hovered ? ChapterInk.accent : ChapterInk.line).setStroke(); path.lineWidth = 1; path.stroke()
        let middle = bounds.midY
        let glyph = style == .search ? "magnifyingglass" : "arrow.clockwise"
        SpaceIcon.draw("sf:"+glyph,in:NSRect(x:16,y:middle-8,width:16,height:16),color:ChapterInk.accent,size:15)
        var end = bounds.width-13
        if style == .search && !shortcut.isEmpty && bounds.width > 260 {
            let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.monospacedSystemFont(ofSize:11,weight:.medium),.foregroundColor:NSColor.secondaryLabelColor]
            let size = (shortcut as NSString).size(withAttributes:attrs)
            if size.width < bounds.width/3 {
                let chip = NSRect(x:end-size.width-14,y:middle-10,width:size.width+14,height:20)
                ChapterInk.line.setStroke(); NSBezierPath(roundedRect:chip,xRadius:5,yRadius:5).stroke()
                (shortcut as NSString).draw(at:NSPoint(x:chip.minX+7,y:middle-size.height/2),withAttributes:attrs)
                end = chip.minX-10
            }
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:style == .retry ? 14 : 15,weight:.medium),.foregroundColor:NSColor.labelColor,.paragraphStyle:paragraph]
        let h = ceil((title as NSString).size(withAttributes:attrs).height)
        (title as NSString).draw(in:NSRect(x:44,y:floor(middle-h/2),width:max(0,end-44),height:h),withAttributes:attrs)
    }
}

final class BrowserLandingView: NSView {
    struct Page: Equatable {
        let language: String
        let space: String
        let isPrivate: Bool
        let shortcut: String
        let failure: NavigationFailure?
    }
    var search: (() -> Void)?
    var retry: (() -> Void)?
    private var page: Page?
    private let paper = WelcomePaper(), left = WelcomeEngraving(right:false), right = WelcomeEngraving(right:true)
    private let mark = WelcomeRibbonMark(), emblem = NSImageView()
    private let brand = NSTextField(labelWithString:"Arc Reborn"), context = NSTextField(labelWithString:"")
    private let category = NSTextField(labelWithString:""), title = NSTextField(wrappingLabelWithString:"")
    private let detail = NSTextField(wrappingLabelWithString:""), diagnostic = NSTextField(labelWithString:"")
    private let primary = LandingAction(frame:.zero)
    private lazy var edit = ChapterButton("",style:.link) { [weak self] in self?.search?() }
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame:frame)
        for view in [paper,left,right,mark,emblem,brand,context,category,title,detail,diagnostic,primary,edit] as [NSView] { addSubview(view) }
        left.alphaValue = 0.55; right.alphaValue = 0.55
        brand.font = .systemFont(ofSize:12,weight:.semibold)
        context.font = .systemFont(ofSize:11,weight:.medium); context.textColor = .secondaryLabelColor; context.alignment = .right
        category.font = .monospacedSystemFont(ofSize:10,weight:.semibold); category.textColor = ChapterInk.accent
        detail.font = .systemFont(ofSize:14); detail.textColor = .secondaryLabelColor
        diagnostic.font = .monospacedSystemFont(ofSize:10,weight:.regular); diagnostic.textColor = .secondaryLabelColor
        for label in [category,title,detail,diagnostic] { label.alignment = .center }
        for label in [brand,context,category,diagnostic] { label.lineBreakMode = .byTruncatingTail }
        emblem.contentTintColor = ChapterInk.accent
        emblem.imageScaling = .scaleProportionallyDown; emblem.setAccessibilityElement(false)
        primary.invoke = { [weak self] in
            guard let self else { return }
            if self.page?.failure == nil { self.search?() } else { self.retry?() }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ value: Page) {
        guard page != value else { return }
        page = value
        let en = value.language == "en"
        context.stringValue = value.isPrivate ? (en ? "Private browsing" : "Navigation privée") : value.space
        if let failure = value.failure {
            let copy = failure.copy(english:en)
            category.stringValue = failure.host ?? "NAVIGATION"
            title.stringValue = copy.title; detail.stringValue = copy.detail
            diagnostic.stringValue = failure.code
            emblem.image = NSImage(systemSymbolName:copy.symbol,accessibilityDescription:nil) ?? NSImage(systemSymbolName:"exclamationmark.circle",accessibilityDescription:nil)
            emblem.symbolConfiguration = .init(pointSize:34,weight:.light)
            primary.style = .retry; primary.title = en ? "Try again" : "Réessayer"
            edit.title = en ? "Edit address" : "Modifier l’adresse"
            edit.setAccessibilityLabel(edit.title)
        } else {
            category.stringValue = en ? "NEW TAB" : "NOUVEL ONGLET"
            title.stringValue = en ? "Where to next?" : "Où allons-nous ?"
            detail.stringValue = ""; diagnostic.stringValue = ""
            primary.style = .search; primary.title = en ? "Search or enter an address" : "Rechercher ou saisir une adresse"
        }
        primary.shortcut = value.shortcut; primary.setAccessibilityLabel(primary.title); primary.needsDisplay = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let page else { return }
        let w = bounds.width, h = bounds.height, failed = page.failure != nil
        let inset:CGFloat = w < 360 ? 12 : 26
        let column = max(0,min(w-2*inset,520)), x = (w-column)/2
        let tight = h < 360 || w < 370
        let masthead = h >= 360 && w >= 330
        paper.frame = bounds
        // Each band occupies one outer margin, keeping the search area clear.
        let bandWidth = min(1240,w*1.16)
        left.frame = NSRect(x:-bandWidth*0.13,y:h*0.54,width:bandWidth,height:min(h*0.37,280))
        right.frame = NSRect(x:w-bandWidth*0.85,y:h*0.14,width:bandWidth,height:min(h*0.39,290))
        left.isHidden = tight; right.isHidden = tight
        brand.isHidden = !masthead; context.isHidden = !masthead
        brand.frame = NSRect(x:inset,y:20,width:96,height:18)
        context.frame = NSRect(x:inset+103,y:20,width:max(0,w-2*inset-103),height:18)

        let displayMark = h >= (failed ? 330 : 240)
        let markSide: CGFloat = failed ? 46 : tight ? 54 : 80
        let categoryShown = h > 245
        let showDetail = failed && h >= 193
        let showCode = failed && h >= 315
        let titleSize:CGFloat = tight ? (w < 250 ? 19 : 25) : (failed ? 34 : 43)
        title.font = .systemFont(ofSize:titleSize,weight:.semibold)
        func textHeight(_ label:NSTextField, maxLines:Int) -> CGFloat {
            guard column > 0, let cell = label.cell else { return 0 }
            let measured = cell.cellSize(forBounds:NSRect(x:0,y:0,width:column,height:500)).height
            return min(ceil(measured)+2, ceil((label.font?.boundingRectForFont.height ?? 18) * CGFloat(maxLines))+4)
        }
        let headingHeight = textHeight(title,maxLines:2)
        let detailHeight:CGFloat = showDetail ? textHeight(detail,maxLines:3)+9 : 0
        let buttonHeight:CGFloat = tight ? 36 : 48
        let stacked = failed && column < 285
        let showEdit = failed && (!stacked || h >= 206)
        let extra:CGFloat = stacked && showEdit ? 31 : 0
        let markHeight = displayMark ? markSide+11 : 0
        let categoryHeight:CGFloat = categoryShown ? 21 : 0
        let actionGap:CGFloat = tight ? 10 : 22
        let total = markHeight + categoryHeight + headingHeight + detailHeight + actionGap + buttonHeight + extra + (showCode ? 26 : 0)
        let top:CGFloat = masthead ? 41 : 4
        var y = max(top,top+(h-top-total)/2-5)
        mark.isHidden = !displayMark || failed; emblem.isHidden = !displayMark || !failed
        let markFrame = NSRect(x:(w-markSide)/2,y:y,width:markSide,height:markSide); mark.frame = markFrame; emblem.frame = markFrame; y += markHeight
        category.isHidden = !categoryShown; category.frame = NSRect(x:x,y:y,width:column,height:16); y += categoryHeight
        title.frame = NSRect(x:x,y:y,width:column,height:headingHeight); y += headingHeight
        detail.isHidden = !showDetail; detail.frame = NSRect(x:x,y:y+7,width:column,height:max(0,detailHeight-7)); y += detailHeight + actionGap
        let primaryW = min(column,failed ? 136 : 434)
        let editW:CGFloat = showEdit && !stacked ? 140 : 0
        let start = (w-primaryW-editW)/2
        primary.frame = NSRect(x:start,y:y,width:primaryW,height:buttonHeight)
        edit.isHidden = !showEdit
        edit.frame = stacked ? NSRect(x:x,y:y+buttonHeight+1,width:column,height:30) : NSRect(x:start+primaryW+5,y:y,width:max(0,editW-5),height:buttonHeight)
        diagnostic.isHidden = !showCode; diagnostic.frame = NSRect(x:x,y:y+buttonHeight+extra+12,width:column,height:16)
    }
}
