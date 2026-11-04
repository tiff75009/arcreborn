// SPDX-License-Identifier: MPL-2.0
import AppKit

/// Each card is one keyboard-accessible control. Its miniature uses the same
/// space painter as the window, so the comparison shows the user's own colors.
final class InterfaceChoice: ActionButton {
    let mode: BrowserInterface
    private let theme: SpaceTheme
    private let name: String
    private let detail: String
    private var tracking: NSTrackingArea?
    private var hovered = false
    var sidebarHidden = false { didSet { needsDisplay = true } }
    var selected = false {
        didSet { setAccessibilityValue(selected ? 1 : 0); needsDisplay = true }
    }

    init(mode: BrowserInterface, theme: SpaceTheme, english: Bool, action: @escaping () -> Void) {
        self.mode = mode
        self.theme = theme
        if mode == .compact {
            name = english ? "Compact" : "Compacte"
            detail = english ? "Address and navigation in the sidebar." : "L’adresse et la navigation dans la barre latérale."
        } else {
            name = english ? "Classic" : "Classique"
            detail = english ? "The address above the page. Tabs on the side." : "L’adresse au-dessus de la page. Les onglets sur le côté."
        }
        super.init("", action: action)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(name)
        setAccessibilityHelp(detail)
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero, options:[.activeInKeyWindow,.inVisibleRect,.mouseEnteredAndExited], owner:self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:2), xRadius:16,yRadius:16).fill()
    }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        let shell = NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:2),xRadius:16,yRadius:16)
        (selected ? ChapterInk.selected : ChapterInk.surface).setFill()
        shell.fill()
        (selected ? ChapterInk.accent : hovered ? NSColor.secondaryLabelColor : ChapterInk.line).setStroke()
        shell.lineWidth = selected ? 1.6 : 1
        shell.stroke()
        let screen = NSRect(x:15,y:15,width:bounds.width-30,height:141)
        drawWindow(in:screen,dark:dark)
        let label = NSRect(x:19,y:172,width:bounds.width-58,height:23)
        (name as NSString).draw(in:label,withAttributes:[.font:NSFont.systemFont(ofSize:17,weight:.semibold),.foregroundColor:NSColor.labelColor])
        (detail as NSString).draw(in:NSRect(x:19,y:200,width:bounds.width-38,height:38),
                                  withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.secondaryLabelColor])
        let circle = NSRect(x:bounds.width-39,y:174,width:18,height:18)
        (selected ? ChapterInk.accent : ChapterInk.line).setStroke()
        let ring = NSBezierPath(ovalIn:circle)
        ring.lineWidth = 1.4; ring.stroke()
        if selected {
            ChapterInk.accent.setFill(); ring.fill()
            let tick = NSBezierPath()
            tick.move(to:NSPoint(x:circle.minX+4.5,y:circle.midY))
            tick.line(to:NSPoint(x:circle.minX+8,y:circle.maxY-5.5))
            tick.line(to:NSPoint(x:circle.maxX-4.5,y:circle.minY+5))
            tick.lineWidth = 1.8; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
            ChapterInk.selected.setStroke(); tick.stroke()
        }
    }
    private func drawWindow(in rect: NSRect, dark: Bool) {
        func pill(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ color:NSColor,_ radius:CGFloat = 3) {
            color.setFill()
            NSBezierPath(roundedRect:NSRect(x:rect.minX+x,y:rect.minY+y,width:w,height:h),
                         xRadius:radius,yRadius:radius).fill()
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let mask = NSBezierPath(roundedRect:rect,xRadius:10,yRadius:10)
        mask.addClip(); ThemePainter.draw(theme,in:rect,dark:dark)
        let ink = (dark || (NSColor(browserHex:theme.points.first?.color ?? "")?.brightnessComponent ?? 1) < 0.45)
            ? NSColor.white : NSColor.black
        let side:CGFloat = sidebarHidden ? 4 : rect.width*0.26
        let compact = mode == .compact
        if !sidebarHidden {
            for i in 0..<3 { pill(8+CGFloat(i)*6,8,3.5,3.5,ink.withAlphaComponent(0.58),2) }
            for i in 0..<4 { pill(side-35+CGFloat(i)*7.5,8,4,3.5,ink.withAlphaComponent(0.54),1.2) }
            if compact {
                pill(6,19,side-12,13,ink.withAlphaComponent(0.14),4)
                pill(12,24.5,side*0.47,2,ink.withAlphaComponent(0.58))
            }
            let first:CGFloat = compact ? 45 : 34
            for (i,fraction) in [0.55,0.39,0.49].enumerated() {
                let y = first+CGFloat(i)*15
                if i == 1 { pill(5,y-4,side-10,13,ink.withAlphaComponent(0.13),4) }
                pill(10,y,5,5,ink.withAlphaComponent(0.51),2)
                pill(21,y+1,side*fraction-8,2.5,ink.withAlphaComponent(0.5),1.2)
            }
        }
        if !compact {
            let fieldX = sidebarHidden ? 42 : side+3
            if sidebarHidden {
                for i in 0..<4 { pill(8+CGFloat(i)*8,11,4,3.5,ink.withAlphaComponent(0.54),1.2) }
            }
            pill(fieldX,6,rect.width-fieldX-9,14,ink.withAlphaComponent(0.14),5)
            pill(fieldX+8,12,rect.width*0.22,2,ink.withAlphaComponent(0.62))
        }
        let top:CGFloat = compact ? 5 : 26
        let page = dark ? NSColor(white:0.115,alpha:1) : NSColor(white:0.99,alpha:1)
        let pageInk = dark ? NSColor.white : NSColor.black
        pill(side,top,rect.width-side-5,rect.height-top-5,page,6)
        let x = side+15, y = top+16
        pill(x,y,24,3,ChapterInk.accent,1.5)
        pill(x,y+12,rect.width*0.30,6,pageInk.withAlphaComponent(0.76))
        pill(x,y+25,rect.width*0.44,3,pageInk.withAlphaComponent(0.22))
        let cardWidth = (rect.width-side-44)/2
        for i in 0..<2 {
            let cardX = x+CGFloat(i)*(cardWidth+8)
            pill(cardX,y+41,cardWidth,30,ChapterInk.accent.withAlphaComponent(i == 0 ? 0.24 : 0.13),5)
            pill(cardX,y+78,cardWidth*0.72,3,pageInk.withAlphaComponent(0.36))
        }
        NSColor.labelColor.withAlphaComponent(0.14).setStroke(); mask.lineWidth = 1; mask.stroke()
    }
}
