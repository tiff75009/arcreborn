import AppKit
import QuartzCore

final class UndoToast {
    private final class Panel: NSPanel { override var canBecomeKey: Bool { false } }
    private let panel = Panel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    private var dismissal: DispatchWorkItem?
    private weak var parent: NSWindow?
    private var generation = 0
    private var width: CGFloat = 340
    var undo: (() -> Void)?
    func show(in parent: NSWindow, message: String, suffix: String, undoLabel: String, color: NSColor, offersUndo: Bool = true, securityWarning: Bool = false) {
        dismiss(animated:false); self.parent = parent; generation += 1
        let body = NSView(); body.wantsLayer = true; body.layer?.cornerRadius = 16
        body.layer?.backgroundColor = (color.blended(withFraction:0.82,of:NSColor(srgbRed:0.055,green:0.02,blue:0.11,alpha:1)) ?? .black).cgColor
        body.layer?.borderWidth = 0.5; body.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        let title = NSTextField(labelWithString:message), ending = NSTextField(labelWithString:suffix)
        for label in [title,ending] { label.font = .systemFont(ofSize:14,weight:.semibold); label.textColor = .white; label.sizeToFit(); body.addSubview(label) }
        let button = NSButton(title:"⌘Z",target:self,action:#selector(undoClicked))
        button.isBordered = false; button.font = .systemFont(ofSize:14,weight:.bold); button.contentTintColor = .white
        button.wantsLayer = true; button.layer?.cornerRadius = 7; button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.11).cgColor
        button.setAccessibilityLabel(undoLabel); body.addSubview(button)
        if securityWarning {
            let shield = NSImageView(frame:NSRect(x:14,y:15,width:20,height:20))
            shield.image = NSImage(systemSymbolName:"exclamationmark.shield.fill",accessibilityDescription:nil)
            shield.contentTintColor = .systemOrange
            body.addSubview(shield)
            title.setAccessibilityIdentifier("download-protection-warning")
        }
        title.frame.origin = NSPoint(x:securityWarning ? 42 : 16,y:16)
        button.frame = NSRect(x:title.frame.maxX+10,y:10,width:42,height:30)
        ending.frame.origin = NSPoint(x:button.frame.maxX+8,y:16)
        button.isHidden = !offersUndo; ending.isHidden = !offersUndo
        width = offersUndo ? ending.frame.maxX+16 : title.frame.maxX+16
        panel.contentView = body; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        layout(in:parent)
        let target = panel.frame
        parent.addChildWindow(panel,ordered:.above)
        panel.alphaValue = 0; panel.setFrame(target.offsetBy(dx:0,dy:7),display:false); panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            context.timingFunction = CAMediaTimingFunction(name:.easeOut)
            panel.animator().alphaValue = 1; panel.animator().setFrame(target,display:true)
        }
        let task = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissal = task; DispatchQueue.main.asyncAfter(deadline:.now()+(offersUndo ? 6 : 3),execute:task)
    }
    func layout(in parent: NSWindow) {
        let frame = parent.contentRect(forFrameRect:parent.frame)
        panel.setFrame(NSRect(x:frame.maxX-min(width,frame.width-28)-14,y:frame.maxY-64,width:min(width,frame.width-28),height:50),display:true)
    }
    @objc private func undoClicked() { undo?() }
    func dismiss(animated: Bool = true) {
        dismissal?.cancel(); dismissal = nil; generation += 1
        let token = generation
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.14 : 0
            panel.animator().alphaValue = 0
        },completionHandler:{ [weak self] in
            guard let self, self.generation == token else { return }
            self.parent?.removeChildWindow(self.panel); self.panel.orderOut(nil)
        })
    }
    deinit { dismissal?.cancel(); panel.orderOut(nil) }
}
