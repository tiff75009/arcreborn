// SPDX-License-Identifier: MPL-2.0
import AppKit

enum FooterControlArtwork {
    // Logical size of the artwork, independent of the much larger button.
    private static let size = NSSize(width:14,height:16.5)
    static func drawLibrary(in bounds:NSRect,flipped:Bool,color:NSColor) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let t = NSAffineTransform()
        t.translateX(by:bounds.midX-size.width/2,yBy:bounds.midY+(flipped ? -1 : 1)*size.height/2)
        if !flipped { t.scaleX(by:1,yBy:-1) }
        t.concat()
        color.setFill()
        let bin = NSBezierPath()
        bin.move(to:NSPoint(x:1.3,y:7.9)); bin.line(to:NSPoint(x:13.1,y:7.9))
        bin.line(to:NSPoint(x:13.1,y:14.2))
        bin.curve(to:NSPoint(x:10.8,y:16.5),controlPoint1:NSPoint(x:13.1,y:15.5),controlPoint2:NSPoint(x:12.2,y:16.5))
        bin.line(to:NSPoint(x:3.6,y:16.5))
        bin.curve(to:NSPoint(x:1.3,y:14.2),controlPoint1:NSPoint(x:2.2,y:16.5),controlPoint2:NSPoint(x:1.3,y:15.5))
        bin.close(); bin.windingRule = .evenOdd
        bin.appendRoundedRect(NSRect(x:5.2,y:9,width:4,height:2.4),xRadius:1,yRadius:1); bin.fill()
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
