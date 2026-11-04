import AppKit
import QuartzCore

/// Alpha clipping keeps the trailing text soft without painting over the theme.
final class FadingTextViewport: NSView {
    private let fade = CAGradientLayer()
    var overflows = false { didSet { needsLayout = true } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fade.frame = bounds
        fade.locations = [0, NSNumber(value: Double(max(0, 1 - 22 / max(1, bounds.width)))), 1]
        layer?.mask = overflows ? fade : nil
        CATransaction.commit()
    }
}

final class FadingAddressButton: ActionButton {
    private let fade = CAGradientLayer()
    override func draw(_ dirtyRect: NSRect) {
        let textFont = font ?? .systemFont(ofSize: 14)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: textFont, .foregroundColor: contentTintColor ?? NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        wantsLayer = true
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fade.frame = bounds
        fade.startPoint = CGPoint(x: 0, y: 0.5); fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, NSNumber(value: Double(max(0, 1 - 20 / max(1, bounds.width)))), 1]
        layer?.mask = size.width > bounds.width ? fade : nil
        CATransaction.commit()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        text.draw(in: NSRect(x: 0, y: (bounds.height-size.height)/2, width: max(bounds.width,size.width), height: size.height), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }
}
