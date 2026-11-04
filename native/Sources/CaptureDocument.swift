import AppKit

enum CaptureTool: String, CaseIterable {
    case select, image, text, ellipse, rectangle, arrow, pen
    var symbol: String { switch self {
        case .select: return "cursorarrow"
        case .image: return "photo"
        case .text: return "textformat"
        case .ellipse: return "circle"
        case .rectangle: return "square"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip.crop.circle"
    } }
    func title(_ fr: Bool) -> String {
        switch self {
        case .select: return fr ? "Sélectionner · V" : "Select · V"
        case .image: return fr ? "Ajouter une image · I" : "Add image · I"
        case .text: return fr ? "Texte · T" : "Text · T"
        case .ellipse: return fr ? "Ellipse · O" : "Ellipse · O"
        case .rectangle: return fr ? "Rectangle · R" : "Rectangle · R"
        case .arrow: return fr ? "Flèche · A" : "Arrow · A"
        case .pen: return fr ? "Dessiner · P" : "Draw · P"
        }
    }
}

struct CaptureMark {
    var id = UUID()
    var kind: CaptureTool
    var rect: CGRect
    var points: [CGPoint] = []
    var color: NSColor = .systemRed
    var width: CGFloat = 5
    var filled = false
    var text = ""
    var fontSize: CGFloat = 36
    var bold = true
    var image: NSImage?
    var bounds: CGRect {
        guard !points.isEmpty else { return rect }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x:xs.min()!,y:ys.min()!,width:max(1,xs.max()!-xs.min()!),height:max(1,ys.max()!-ys.min()!))
    }
    mutating func transform(to frame: CGRect) {
        let old = bounds
        points = points.map { CGPoint(x:frame.minX+($0.x-old.minX)*frame.width/max(1,old.width),y:frame.minY+($0.y-old.minY)*frame.height/max(1,old.height)) }
        if kind == .text { fontSize = max(8,min(400,fontSize*frame.height/max(1,old.height))) }
        rect = frame
    }
    func draw() {
        color.setStroke(); color.setFill()
        let path = NSBezierPath(); path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        switch kind {
        case .ellipse, .rectangle:
            let shape = kind == .ellipse ? NSBezierPath(ovalIn:rect) : NSBezierPath(roundedRect:rect,xRadius:3,yRadius:3)
            shape.lineWidth = width; filled ? shape.fill() : shape.stroke()
        case .arrow:
            guard let start = points.first, let end = points.last else { return }
            path.move(to:start); path.line(to:end); path.stroke()
            let angle = atan2(end.y-start.y,end.x-start.x), length = max(14,width*3.5)
            let head = NSBezierPath(); head.move(to:end)
            head.line(to:CGPoint(x:end.x-length*cos(angle-0.48),y:end.y-length*sin(angle-0.48)))
            head.line(to:CGPoint(x:end.x-length*cos(angle+0.48),y:end.y-length*sin(angle+0.48)))
            head.close(); head.fill()
        case .pen:
            guard let first = points.first else { return }
            path.move(to:first)
            if points.count == 1 { path.line(to:CGPoint(x:first.x+0.1,y:first.y)) }
            else { for point in points.dropFirst() { path.line(to:point) } }
            path.stroke()
        case .text:
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
            (text as NSString).draw(in:rect,withAttributes:[.font:NSFont.systemFont(ofSize:fontSize,weight:bold ? .semibold : .regular),.foregroundColor:color,.paragraphStyle:paragraph])
        case .image:
            image?.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
        case .select: break
        }
    }
    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        if kind == .pen || kind == .arrow {
            if points.count == 1 { return hypot(point.x-points[0].x,point.y-points[0].y) <= max(width/2,tolerance) }
            for (a,b) in zip(points,points.dropFirst()) {
                let dx = b.x-a.x, dy = b.y-a.y
                let t = max(0,min(1,((point.x-a.x)*dx+(point.y-a.y)*dy)/max(0.001,dx*dx+dy*dy)))
                if hypot(point.x-a.x-t*dx,point.y-a.y-t*dy) <= max(width/2,tolerance) { return true }
            }
            return false
        }
        return bounds.insetBy(dx:-tolerance,dy:-tolerance).contains(point)
    }
}

final class CaptureDocument {
    let original: NSImage
    let size: CGSize
    var marks: [CaptureMark] = []
    private var past: [[CaptureMark]] = [], future: [[CaptureMark]] = []
    struct Snapshot { fileprivate let marks:[CaptureMark], past:[[CaptureMark]], future:[[CaptureMark]] }
    func snapshot() -> Snapshot { Snapshot(marks:marks,past:past,future:future) }
    func restore(_ snapshot:Snapshot) { marks = snapshot.marks; past = snapshot.past; future = snapshot.future }
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    init(image: NSImage) {
        original = image
        let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil)
        size = CGSize(width:cg?.width ?? Int(image.size.width),height:cg?.height ?? Int(image.size.height))
    }
    func checkpoint() { past.append(marks); if past.count > 60 { past.removeFirst() }; future.removeAll() }
    func undo() { guard let previous = past.popLast() else { return }; future.append(marks); marks = previous }
    func redo() { guard let next = future.popLast() else { return }; past.append(marks); marks = next }
    func draw(excluding: UUID? = nil) {
        original.draw(in:CGRect(origin:.zero,size:size),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
        for mark in marks where mark.id != excluding { mark.draw() }
    }
    func rendered() -> NSImage? {
        guard size.width > 0, size.height > 0, size.width*size.height <= 80_000_000,
              let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width),pixelsHigh:Int(size.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
              let context = NSGraphicsContext(bitmapImageRep:rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        let cg = context.cgContext; cg.translateBy(x:0,y:size.height); cg.scaleBy(x:1,y:-1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext:cg,flipped:true)
        draw(); NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size:size); image.addRepresentation(rep); return image
    }
    static func crop(_ image: NSImage, normalized rect: CGRect) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return nil }
        let clipped = rect.intersection(CGRect(x:0,y:0,width:1,height:1))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        let pixels = CGRect(x:clipped.minX*CGFloat(cg.width),y:clipped.minY*CGFloat(cg.height),width:clipped.width*CGFloat(cg.width),height:clipped.height*CGFloat(cg.height)).integral
        guard let crop = cg.cropping(to:pixels) else { return nil }
        return NSImage(cgImage:crop,size:NSSize(width:crop.width,height:crop.height))
    }
    static func png(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return nil }
        return NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])
    }
}
