import AppKit

// Compare decoded pixels, not NSImage identity or PNG metadata. A fresh download
// with the same visible favicon keeps the existing NSImage and sidebar views.
func faviconPixels(_ image: NSImage) -> Data? {
    let size = 32
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:size*4,bitsPerPixel:32),
          let bytes = bitmap.bitmapData, let context = NSGraphicsContext(bitmapImageRep:bitmap) else { return nil }
    memset(bytes,0,size*size*4)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    image.draw(in:NSRect(x:0,y:0,width:size,height:size),from:.zero,operation:.copy,fraction:1)
    NSGraphicsContext.restoreGraphicsState()
    return Data(bytes:bytes,count:size*size*4)
}
