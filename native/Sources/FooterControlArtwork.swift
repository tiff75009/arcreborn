// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

enum FooterControlArtwork {
    // Logical size of the artwork, independent of the much larger button.
    private static let size = NSSize(width:14,height:16.5)
    static func drawLibrary(in bounds:NSRect,flipped:Bool,color:NSColor,body:Bool = true,contents:Bool = true) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let t = NSAffineTransform()
        t.translateX(by:bounds.midX-size.width/2,yBy:bounds.midY+(flipped ? -1 : 1)*size.height/2)
        if !flipped { t.scaleX(by:1,yBy:-1) }
        t.concat()
        color.setFill()
        if body {
        let bin = NSBezierPath()
        bin.move(to:NSPoint(x:1.3,y:7.9)); bin.line(to:NSPoint(x:13.1,y:7.9))
        bin.line(to:NSPoint(x:13.1,y:14.2))
        bin.curve(to:NSPoint(x:10.8,y:16.5),controlPoint1:NSPoint(x:13.1,y:15.5),controlPoint2:NSPoint(x:12.2,y:16.5))
        bin.line(to:NSPoint(x:3.6,y:16.5))
        bin.curve(to:NSPoint(x:1.3,y:14.2),controlPoint1:NSPoint(x:2.2,y:16.5),controlPoint2:NSPoint(x:1.3,y:15.5))
        bin.close(); bin.windingRule = .evenOdd
        bin.appendRoundedRect(NSRect(x:5.2,y:9,width:4,height:2.4),xRadius:1,yRadius:1); bin.fill()
        }
        guard contents else { return }
        let lid = NSBezierPath()
        lid.move(to:NSPoint(x:0.9,y:6.1)); lid.line(to:NSPoint(x:7.6,y:6.1))
        lid.curve(to:NSPoint(x:9.1,y:4.6),controlPoint1:NSPoint(x:8.5,y:6.1),controlPoint2:NSPoint(x:9.1,y:5.5))
        lid.curve(to:NSPoint(x:8,y:3.2),controlPoint1:NSPoint(x:9.1,y:3.8),controlPoint2:NSPoint(x:8.7,y:3.3))
        lid.line(to:NSPoint(x:5.6,y:3)); lid.line(to:NSPoint(x:5,y:1.6))
        lid.curve(to:NSPoint(x:3.3,y:1.6),controlPoint1:NSPoint(x:4.6,y:0.6),controlPoint2:NSPoint(x:3.5,y:0.8))
        lid.line(to:NSPoint(x:2.9,y:3.9)); lid.line(to:NSPoint(x:0.9,y:4.2))
        lid.curve(to:NSPoint(x:0.9,y:6.1),controlPoint1:NSPoint(x:-0.2,y:4.3),controlPoint2:NSPoint(x:-0.3,y:6.1))
        lid.close(); lid.fill()
        NSBezierPath(ovalIn:NSRect(x:8.3,y:0,width:2.1,height:2.1)).fill()
        let slip = NSBezierPath(roundedRect:NSRect(x:10.6,y:3.1,width:2.8,height:3.4),xRadius:0.8,yRadius:0.8)
        let rotate = AffineTransform(translationByX:12,byY:4.8)
        var angle = rotate; angle.rotate(byDegrees:-24); angle.translate(x:-12,y:-4.8)
        slip.transform(using:angle); slip.fill()
    }
}

/// The tray stays anchored; only the objects above its rim expand on hover.
final class LibraryBasketArtwork: CALayer {
    private let tray = CALayer(), objects = CALayer()
    private var expanded = false
    var ink = NSColor.labelColor.withAlphaComponent(0.65) {
        didSet { if ink != oldValue { updateImages() } }
    }
    override init() {
        super.init()
        bounds = CGRect(x:0,y:0,width:24,height:24)
        for part in [tray,objects] {
            part.frame = bounds; part.contentsScale = 2
            addSublayer(part)
        }
        objects.shadowOffset = .zero; objects.shadowRadius = 2
        updateImages()
    }
    override init(layer:Any) { super.init(layer:layer) }
    required init?(coder:NSCoder) { fatalError() }
    private func updateImages() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (part,isBody) in [(tray,true),(objects,false)] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:48,pixelsHigh:48,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            bitmap.size = NSSize(width:24,height:24)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
            FooterControlArtwork.drawLibrary(in:NSRect(x:0,y:0,width:24,height:24),flipped:false,color:ink,body:isBody,contents:!isBody)
            NSGraphicsContext.restoreGraphicsState()
            part.contents = bitmap.cgImage
        }
        objects.shadowColor = ink.cgColor
        CATransaction.commit()
    }
    func setExpanded(_ value:Bool, animated:Bool) {
        guard value != expanded else { return }; expanded = value
        let from = objects.presentation()?.transform ?? objects.transform
        let transform = value ? CATransform3DScale(CATransform3DMakeTranslation(0,0.6,0),1.24,1.24,1) : CATransform3DIdentity
        let shadow = objects.presentation()?.shadowOpacity ?? objects.shadowOpacity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        objects.transform = transform; objects.shadowOpacity = value ? 0.35 : 0
        objects.removeAnimation(forKey:"contents-expansion"); objects.removeAnimation(forKey:"contents-glow")
        CATransaction.commit()
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let spring = CASpringAnimation(keyPath:"transform")
        spring.mass = 1; spring.stiffness = 340; spring.damping = 31
        spring.fromValue = NSValue(caTransform3D:from); spring.toValue = NSValue(caTransform3D:transform)
        spring.duration = 0.42; objects.add(spring,forKey:"contents-expansion")
        let glow = CABasicAnimation(keyPath:"shadowOpacity")
        glow.fromValue = shadow; glow.toValue = objects.shadowOpacity; glow.duration = 0.2
        objects.add(glow,forKey:"contents-glow")
    }
}
