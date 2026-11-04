// SPDX-License-Identifier: MPL-2.0
import AppKit

private func chapterColor(_ light:Int, _ dark:Int) -> NSColor {
    NSColor(name:nil) { appearance in
        let v = appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? dark : light
        return NSColor(srgbRed:CGFloat((v>>16)&255)/255,green:CGFloat((v>>8)&255)/255,blue:CGFloat(v&255)/255,alpha:1)
    }
}
enum ChapterInk {
    static let accent = chapterColor(0x574790,0xC6B7FF)
    static let surface = chapterColor(0xFFFDFF,0x232237).withAlphaComponent(0.88)
    static let line = chapterColor(0x49435C,0xE0D8F6).withAlphaComponent(0.16)
    static let selected = chapterColor(0xECE7FC,0x3A3454)
}

final class ChapterPlate: NSView {
    let radius:CGFloat
    let color:NSColor
    init(_ frame:NSRect,radius:CGFloat = 18,color:NSColor = ChapterInk.surface) {
        self.radius = radius; self.color = color; super.init(frame:frame); setAccessibilityElement(false)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func hitTest(_ point:NSPoint)->NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect:NSRect) {
        let shape = NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:radius,yRadius:radius)
        color.setFill(); shape.fill(); ChapterInk.line.setStroke(); shape.lineWidth = 1; shape.stroke()
    }
}

class ChapterButton: ActionButton {
    enum Style { case solid, soft, link }
    private let style:Style
    private var tracking:NSTrackingArea?, hovering = false
    init(_ title:String,style:Style,action:@escaping()->Void) {
        self.style = style; super.init(title,action:action); focusRingType = .exterior
    }
    required init?(coder:NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect:.zero,options:[.inVisibleRect,.activeInKeyWindow,.mouseEnteredAndExited],owner:self)
        tracking = area; addTrackingArea(area)
    }
    override func mouseEntered(with event:NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event:NSEvent) { hovering = false; needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect:NSRect) {
        let p = NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:10,yRadius:10)
        if style != .link {
            let bg = style == .solid ? chapterColor(0x4C397A,0xD1C3F7) : ChapterInk.surface
            bg.withAlphaComponent(isEnabled ? (isHighlighted ? 0.66 : 1) : 0.30).setFill(); p.fill()
            (hovering && isEnabled ? ChapterInk.accent : ChapterInk.line).setStroke(); p.stroke()
        }
        let fg:NSColor = isEnabled ? (style == .solid ? chapterColor(0xFFFFFF,0x251F36) : style == .link ? ChapterInk.accent : .labelColor) : .secondaryLabelColor
        let a:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:13,weight:.semibold),.foregroundColor:fg]
        let text = title as NSString, s = text.size(withAttributes:a)
        text.draw(at:NSPoint(x:(bounds.width-s.width)/2,y:(bounds.height-s.height)/2),withAttributes:a)
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:10,yRadius:10).fill() }
}

final class ImportSourceTile: ActionButton {
    private let browser:ImportBrowser
    private let icon:NSImage?, detail:String, selectedLabel:String
    var selected = false { didSet { needsDisplay = true; setAccessibilityValue(selected ? selectedLabel : nil) } }
    init(browser:ImportBrowser,english:Bool,action:@escaping()->Void) {
        self.browser = browser
        let url = browser.application
        self.icon = url.map { NSWorkspace.shared.icon(forFile:$0.path) } ?? NSImage(systemSymbolName:"globe",accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[.secondaryLabelColor]))
        detail = url != nil ? (english ? "Detected" : "Détecté") : (english ? "Not installed" : "Non installé")
        selectedLabel = english ? "Selected" : "Sélectionné"
        super.init(browser.name,action:action); setAccessibilityLabel(browser.name+", "+detail); focusRingType = .exterior
    }
    required init?(coder:NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect:NSRect) {
        let p = NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:14,yRadius:14)
        (selected || isHighlighted ? ChapterInk.selected : ChapterInk.surface).setFill(); p.fill()
        (selected ? ChapterInk.accent : ChapterInk.line).setStroke(); p.lineWidth = selected ? 1.5 : 1; p.stroke()
        icon?.draw(in:NSRect(x:12,y:(bounds.height-37)/2,width:37,height:37),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
        let top = isFlipped ? bounds.midY-18 : bounds.midY
        let bottom = isFlipped ? bounds.midY+3 : bounds.midY-17
        (browser.name as NSString).draw(at:NSPoint(x:56,y:top),withAttributes:[.font:NSFont.systemFont(ofSize:15,weight:.semibold),.foregroundColor:NSColor.labelColor])
        (detail as NSString).draw(at:NSPoint(x:56,y:bottom),withAttributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.secondaryLabelColor])
        if selected {
            let c = NSBezierPath(ovalIn:NSRect(x:bounds.width-17,y:isFlipped ? 10 : bounds.height-17,width:7,height:7))
            ChapterInk.accent.setFill(); c.fill()
        }
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:14,yRadius:14).fill() }
}
