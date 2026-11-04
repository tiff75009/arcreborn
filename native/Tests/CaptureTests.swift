import AppKit

@main struct CaptureTests {
    static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        func check(_ ok:Bool,_ message:String) { precondition(ok,message); print("PASS \(message)"); fflush(stdout) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:480,pixelsHigh:320,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let navy = NSColor(deviceRed:0.15,green:0.24,blue:0.5,alpha:1), rose = NSColor(deviceRed:0.65,green:0.24,blue:0.42,alpha:1)
        for y in 0..<320 { for x in 0..<480 { bitmap.setColor(y<160 ? navy : rose,atX:x,y:y) } }
        let image = NSImage(size:NSSize(width:240,height:160)); image.addRepresentation(bitmap) // Retina: points differ from pixels.
        let document = CaptureDocument(image:image)
        check(document.size == CGSize(width:480,height:320),"Retina pixels retained")
        let top = CaptureDocument.crop(image,normalized:CGRect(x:0,y:0,width:0.5,height:0.5))!
        let bottom = CaptureDocument.crop(image,normalized:CGRect(x:0.5,y:0.5,width:0.5,height:0.5))!
        func color(_ image:NSImage,_ x:Int=10,_ y:Int=10) -> NSColor { NSBitmapImageRep(cgImage:image.cgImage(forProposedRect:nil,context:nil,hints:nil)!).colorAt(x:x,y:y)!.usingColorSpace(.sRGB)! }
        check(top.size == CGSize(width:240,height:160) && color(top).blueComponent > color(top).redComponent,"Top-left crop has correct scale and orientation")
        check(color(bottom).redComponent > color(bottom).blueComponent,"Bottom-right crop has correct orientation")
        check(color(document.rendered()!).blueComponent > color(document.rendered()!).redComponent,"Export preserves original orientation")
        document.checkpoint()
        document.marks.append(CaptureMark(kind:.rectangle,rect:CGRect(x:40,y:40,width:60,height:50),color:.green,filled:true))
        check(color(document.rendered()!,60,60).greenComponent > 0.8,"Annotations export at native pixel coordinates")
        document.undo(); check(document.marks.isEmpty,"Undo restores image")
        document.redo(); check(document.marks.count == 1,"Redo restores annotations")
        let snapshot = document.snapshot(); document.checkpoint(); document.marks.removeAll(); document.restore(snapshot)
        check(document.marks.count == 1 && !document.canRedo,"Cancelled editing restores both document and undo history")
        let root = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("capture-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at:root) }
        let library = LibraryStore(directory:root,downloadsDirectory:root.appendingPathComponent("ungranted-downloads"))
        let data = CaptureDocument.png(document.rendered()!)!
        let url = try library.saveCapture(data)
        check(!library.mediaEnabled && library.media.count == 1 && library.media[0].url.standardizedFileURL == url.standardizedFileURL,"Library capture requires no Downloads opt-in: enabled=\(library.mediaEnabled), count=\(library.media.count), paths=\(library.media.map { $0.url.path }), url=\(url.path)")
        check(LibraryStore(directory:root).media.count == 1,"Capture survives Library reload")
        check(try Data(contentsOf:url) == data,"Saved PNG matches edited export")
        let window = NSWindow(contentRect:CGRect(x:0,y:0,width:960,height:700),styleMask:[.titled],backing:.buffered,defer:false)
        window.orderBack(nil)
        let editor = CaptureEditor(document:document,language:"fr"); editor.frame = window.contentView!.bounds; window.contentView!.addSubview(editor); editor.layoutSubtreeIfNeeded()
        let canvas = editor.canvas
        func event(_ type:NSEvent.EventType,_ x:CGFloat,_ y:CGFloat) -> NSEvent {
            let r = canvas.imageRect
            let p = canvas.convert(CGPoint(x:r.minX+x/document.size.width*r.width,y:r.minY+y/document.size.height*r.height),to:nil)
            return NSEvent.mouseEvent(with:type,location:p,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        }
        for tool in [CaptureTool.ellipse,.rectangle,.arrow,.pen] {
            canvas.tool = tool; canvas.mouseDown(with:event(.leftMouseDown,140,90)); canvas.mouseDragged(with:event(.leftMouseDragged,240,150)); canvas.mouseUp(with:event(.leftMouseUp,240,150))
            check(document.marks.last?.kind == tool,"Native \(tool.rawValue) gesture creates annotation")
        }
        canvas.tool = .text; canvas.mouseDown(with:event(.leftMouseDown,30,220)); canvas.mouseUp(with:event(.leftMouseUp,30,220))
        guard let field = canvas.subviews.compactMap({ $0 as? NSTextField }).first else { fatalError("Text editor missing; canvas=\(canvas.frame), tool=\(canvas.tool), marks=\(document.marks.count), selected=\(String(describing:canvas.selected))") }
        field.stringValue = "Une capture, vos idées."; canvas.commitText()
        check(document.marks.last?.text == "Une capture, vos idées.","Inline text survives mouse-up and commits")
        canvas.insertImage(top); check(document.marks.last?.kind == .image,"Image import remains independently editable")
        canvas.tool = .select
        let originalFrame = document.marks.last!.bounds
        canvas.mouseDown(with:event(.leftMouseDown,originalFrame.minX,originalFrame.minY))
        canvas.mouseDragged(with:event(.leftMouseDragged,originalFrame.minX-25,originalFrame.minY-10))
        canvas.mouseUp(with:event(.leftMouseUp,originalFrame.minX-25,originalFrame.minY-10))
        let resized = document.marks.last!.bounds
        check(abs(resized.maxX-originalFrame.maxX)<0.01 && abs(resized.maxY-originalFrame.maxY)<0.01 && abs(resized.width/resized.height-originalFrame.width/originalFrame.height)<0.01,"Image resizing preserves aspect ratio and opposite anchor")
        let count = document.marks.count; canvas.delete(nil); check(document.marks.count == count-1,"Selected annotation can be deleted")
        canvas.undo(nil); check(document.marks.count == count,"Delete can be undone")
        canvas.selected = nil; editor.layoutSubtreeIfNeeded(); editor.displayIfNeeded()
        let output = URL(fileURLWithPath:"native/build/capture-check"); try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        if let rep = editor.bitmapImageRepForCachingDisplay(in:editor.bounds) { editor.cacheDisplay(in:editor.bounds,to:rep); try rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("editor.png")) }
        try CaptureDocument.png(document.rendered()!)!.write(to:output.appendingPathComponent("export.png"))
        print("CAPTURE_TESTS_PASS")
    }
}
