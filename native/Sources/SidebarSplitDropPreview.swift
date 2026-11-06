// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

/// A view-only rehearsal of the split. No model, selection or page is changed
/// until drop; the original row is restored when the pointer leaves the centre.
final class SidebarSplitDropPreview: NSView {
    struct Item { let title:String; let image:NSImage? }
    private final class Label: NSView {
        let icon = NSImageView(), title = NSTextField(labelWithString:"")
        override init(frame:NSRect) {
            super.init(frame:frame); wantsLayer = true
            title.font = .systemFont(ofSize:14); title.lineBreakMode = .byTruncatingTail
            title.maximumNumberOfLines = 1; title.allowsExpansionToolTips = false
            icon.imageScaling = .scaleProportionallyUpOrDown
            addSubview(icon); addSubview(title)
        }
        required init?(coder:NSCoder) { fatalError() }
        override func layout() {
            super.layout()
            icon.frame = NSRect(x:10,y:bounds.midY-8,width:16,height:16)
            title.frame = NSRect(x:33,y:bounds.midY-9,width:max(0,bounds.width-39),height:19)
        }
    }
    override var isFlipped:Bool { true }
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    private let labels:[Label]
    private let slot = NSView()
    private let incomingCount:Int
    private weak var concealed:NSView?
    private var originalAlpha:CGFloat = 1
    private var cleanup:DispatchWorkItem?
    private(set) var before = false
    private var closing = false

    init(items:[Item], incomingCount:Int, ink:NSColor) {
        labels = items.map { item in
            let label = Label(frame:.zero); label.icon.image = item.image
            label.title.stringValue = item.title; label.title.textColor = ink
            return label
        }
        self.incomingCount = max(1,incomingCount)
        super.init(frame:.zero); wantsLayer = true; layer?.masksToBounds = true
        slot.wantsLayer = true; slot.layer?.cornerRadius = 12
        slot.layer?.backgroundColor = ink.withAlphaComponent(0.25).cgColor
        addSubview(slot); labels.forEach { addSubview($0) }
        setAccessibilityElement(false)
    }
    required init?(coder:NSCoder) { fatalError() }

    func present(in host:NSView, covering view:NSView, frame:NSRect, before:Bool, animated:Bool = true) {
        self.frame = frame; host.addSubview(self)
        concealed = view; originalAlpha = view.alphaValue; view.alphaValue = 0
        layoutLabels(split:false,before:before,animated:false)
        slot.alphaValue = 0
        setBefore(before,animated:animated,force:true)
    }
    func setBefore(_ value:Bool, animated:Bool = true, force:Bool = false) {
        guard !closing, before != value || force else { return }
        before = value; layoutLabels(split:true,before:value,animated:animated)
    }
    private func layoutLabels(split:Bool,before:Bool,animated:Bool) {
        let inset:CGFloat = 4, gap:CGFloat = 4
        let count = labels.count + (split ? incomingCount : 0)
        let width = max(1,(bounds.width-2*inset-gap*CGFloat(max(0,count-1)))/CGFloat(max(1,count)))
        let offset = split && before ? incomingCount : 0
        let height = min(36,bounds.height), y = (bounds.height-height)/2
        let targetSlot = NSRect(x:before ? inset : inset+CGFloat(labels.count)*(width+gap),y:y,
                                width:split ? width*CGFloat(incomingCount)+gap*CGFloat(incomingCount-1) : 0,height:height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.24 : 0
            context.timingFunction = CAMediaTimingFunction(controlPoints:0.22,0.82,0.24,1)
            for (index,label) in labels.enumerated() {
                let rect = NSRect(x:inset+CGFloat(index+offset)*(width+gap),y:y,width:width,height:height)
                label.animator().frame = rect
            }
            slot.animator().frame = targetSlot
            slot.animator().alphaValue = split ? 1 : 0
        }
    }
    func close(animated:Bool) {
        if closing { if !animated { finish() }; return }; closing = true
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { finish(); return }
        layoutLabels(split:false,before:before,animated:true)
        let work = DispatchWorkItem { [weak self] in self?.finish() }; cleanup = work
        DispatchQueue.main.asyncAfter(deadline:.now()+0.24,execute:work)
    }
    private func finish() {
        cleanup?.cancel(); cleanup = nil
        concealed?.alphaValue = originalAlpha; concealed = nil
        removeFromSuperview()
    }
    deinit { cleanup?.cancel(); concealed?.alphaValue = originalAlpha }

    static func dragImage(item:Item,size:NSSize,ink:NSColor) -> NSImage {
        NSImage(size:size,flipped:true) { rect in
            ink.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect:rect,xRadius:12,yRadius:12).fill()
            item.image?.draw(in:NSRect(x:12,y:rect.midY-8,width:16,height:16),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
            (item.title as NSString).draw(in:NSRect(x:35,y:rect.midY-9,width:max(0,rect.width-45),height:20),
                withAttributes:[.font:NSFont.systemFont(ofSize:14),.foregroundColor:ink,.paragraphStyle:style])
            return true
        }
    }
}
