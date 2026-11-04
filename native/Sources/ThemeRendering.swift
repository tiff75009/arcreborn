import AppKit
import QuartzCore

extension NSColor {
    var themeHex: String {
        let c = usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int((c.redComponent*255).rounded()), Int((c.greenComponent*255).rounded()), Int((c.blueComponent*255).rounded()))
    }
    func themeTone(dark: Bool) -> NSColor {
        blended(withFraction: dark ? 0.62 : 0, of: .black) ?? self
    }
}

/// One immutable noise tile shared by the frame, floating sidebar and editor.
enum ThemePainter {
    static let noise: NSImage = {
        let size = 512
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: size*4, bitsPerPixel: 32)!
        var seed: UInt32 = 0xA8C24
        for i in 0..<(size*size) {
            // Narrow, centered distribution: texture modulates the theme instead of
            // covering it with high-contrast monochrome static. One texel per Retina pixel.
            seed = seed &* 1664525 &+ 1013904223
            let value = UInt8(88 + Int(seed >> 24)*80/255)
            let bytes = bitmap.bitmapData! + i*4
            bytes[0] = value; bytes[1] = value; bytes[2] = value; bytes[3] = 255
        }
        let image = NSImage(size: NSSize(width: size/2, height: size/2))
        image.addRepresentation(bitmap); return image
    }()

    static func draw(_ theme: SpaceTheme, in rect: NSRect, dark: Bool) {
        guard let first = theme.points.first else { return }
        let base = (NSColor(browserHex: first.color) ?? .systemPurple).themeTone(dark: dark)
        base.setFill(); rect.fill()
        let amount = CGFloat(theme.gradient)
        // A single color can still vary in lightness; additional handles blend spatially.
        if amount > 0 && theme.pickerVersion == 1 && theme.points.count > 1 {
            // Wheel coordinates describe hue relationships, not light positions.
            // Keep the blend stable while the linked handles rotate through colors.
            let colors = theme.points.compactMap { NSColor(browserHex:$0.color)?.themeTone(dark:dark) }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(amount)
            NSGradient(colors:colors)?.draw(in:rect,angle:90)
            NSGraphicsContext.restoreGraphicsState()
        } else if amount > 0 {
            let glow = base.blended(withFraction: dark ? 0.24 : 0.45, of: .white) ?? base
            let center = NSPoint(x: rect.minX + first.x*rect.width, y: rect.minY + first.y*rect.height)
            radial(glow.withAlphaComponent(amount*0.8), center: center, radius: max(rect.width,rect.height)*0.9)
            for point in theme.points.dropFirst() {
                let color = (NSColor(browserHex: point.color) ?? base).themeTone(dark: dark)
                radial(color.withAlphaComponent(min(1,amount*1.6)),
                    center: NSPoint(x: rect.minX+point.x*rect.width,y: rect.minY+point.y*rect.height),
                    radius: max(rect.width,rect.height)*(0.45+amount*0.55))
            }
        }
        if theme.grain > 0 {
            // NSRect.fill() overrides the blend operation. Use Core Graphics all
            // the way through so neutral noise preserves saturated theme colors.
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState(); context.clip(to:rect)
                context.setBlendMode(.softLight)
                context.setAlpha(CGFloat(pow(theme.grain,1.25))*0.5)
                context.draw(noisePixels,in:CGRect(x:0,y:0,width:256,height:256),byTiling:true)
                context.restoreGState()
            }
        }
    }
    private static let noisePixels = noise.cgImage(forProposedRect:nil,context:nil,hints:nil)!
    private static func radial(_ color: NSColor, center: NSPoint, radius: CGFloat) {
        NSGradient(starting: color, ending: color.withAlphaComponent(0))?.draw(fromCenter: center, radius: 0,
            toCenter: center, radius: radius, options: [])
    }
}

class ThemeBackdropView: NSView {
    private var previewView: NSImageView?
    func beginPreview(theme next: SpaceTheme, dark nextDark: Bool) {
        endPreview()
        guard paintsTheme else { return }
        let radius = rounded
        let image = NSImage(size:bounds.size,flipped:true) { rect in
            NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius).addClip()
            ThemePainter.draw(next,in:rect,dark:nextDark); return true
        }
        let preview = NSImageView(frame:bounds)
        preview.image = image; preview.imageScaling = .scaleAxesIndependently
        preview.wantsLayer = true; preview.alphaValue = 0
        addSubview(preview,positioned:.below,relativeTo:subviews.first)
        previewView = preview
    }
    func setPreviewProgress(_ progress: CGFloat, duration: Double = 0) {
        guard let preview = previewView else { return }
        if duration > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(controlPoints:0.22,0.75,0.24,1)
                preview.animator().alphaValue = progress
            }
        } else {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            preview.alphaValue = progress; CATransaction.commit()
        }
    }
    func endPreview() { previewView?.removeFromSuperview(); previewView = nil }
    private var themeFadeLayer: CALayer?
    func transition(to next: SpaceTheme, dark nextDark: Bool) {
        guard paintsTheme, bounds.width > 0, bounds.height > 0,
              theme != next || dark != nextDark,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            theme = next; dark = nextDark; return
        }
        let previous = theme, wasDark = dark, radius = rounded, size = bounds.size
        let image = NSImage(size:size,flipped:true) { rect in
            NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius).addClip()
            ThemePainter.draw(previous,in:rect,dark:wasDark); return true
        }
        themeFadeLayer?.removeFromSuperlayer()
        let fading = CALayer(); fading.frame = bounds
        fading.contents = image.cgImage(forProposedRect:nil,context:nil,hints:nil)
        wantsLayer = true; layer?.insertSublayer(fading,at:0); themeFadeLayer = fading
        theme = next; dark = nextDark; displayIfNeeded()
        CATransaction.begin(); CATransaction.setDisableActions(true); fading.opacity = 0; CATransaction.commit()
        let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.14
        fade.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut); fading.add(fade,forKey:"theme-fade")
        DispatchQueue.main.asyncAfter(deadline:.now()+0.15) { [weak self, weak fading] in
            fading?.removeFromSuperlayer()
            if self?.themeFadeLayer === fading { self?.themeFadeLayer = nil }
        }
    }
    var theme = SpaceTheme.solid("#B367A5") { didSet { needsDisplay = true } }
    var dark = false { didSet { needsDisplay = true } }
    var rounded: CGFloat = 0 { didSet { needsDisplay = true } }
    var paintsTheme = true { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard paintsTheme else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: rounded, yRadius: rounded).addClip()
        ThemePainter.draw(theme, in: bounds, dark: dark)
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension NSColor {
    convenience init?(browserHex: String) {
        let hex = browserHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
