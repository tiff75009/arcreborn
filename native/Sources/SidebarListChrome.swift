// SPDX-License-Identifier: MPL-2.0
import AppKit

/// The footer has an input surface across its full width, including the gaps
/// around the update pill and spaces. Transparent artwork never means click-through.
final class SidebarFooterBarrier: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override func mouseDown(with event:NSEvent) {}
    override func rightMouseDown(with event:NSEvent) {}
    override func otherMouseDown(with event:NSEvent) {}
    override func scrollWheel(with event:NSEvent) {}
    override func menu(for event:NSEvent) -> NSMenu? { nil }
}

final class SidebarListSeparator: NSView {
    var ink = NSColor.white { didSet { needsDisplay = true } }
    private var shown = false
    override init(frame:NSRect) {
        super.init(frame:frame); wantsLayer = true; layer?.opacity = 0
    }
    required init?(coder:NSCoder) { fatalError() }
    func setShown(_ value:Bool) {
        guard value != shown else { return }; shown = value
        let from = layer?.presentation()?.opacity ?? layer?.opacity ?? 0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.opacity = value ? 1 : 0
        CATransaction.commit()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CABasicAnimation(keyPath:"opacity")
            fade.fromValue = from; fade.toValue = value ? 1 : 0; fade.duration = 0.14
            layer?.add(fade,forKey:"edge")
        }
    }
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect:NSRect) {
        ink.withAlphaComponent(0.045).setFill()
        bounds.fill()
    }
}
