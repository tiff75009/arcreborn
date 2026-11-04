import AppKit

@main struct DeveloperModeTests {
    private static var checks = 0
    private static func require(_ condition:Bool,_ message:String) {
        precondition(condition,message); checks += 1
    }
    static func main() throws {
        var session = BrowserSession.fresh()
        let first = session.createTab(url:"https://example.com/one")
        let second = session.createTab(url:"https://example.com/two")
        let index = session.tabs.firstIndex { $0.id == first }!
        session.tabs[index].developerMode = true
        session.tabs[index].developerCaptureColor = "#E971B8"
        session.selectTab(id:second); session.selectTab(id:first)
        require(session.tabs[index].developerMode == true && session.tabs.first { $0.id == second }?.developerMode != true,"Switching tabs keeps Developer Mode isolated")
        session.tabs[index].url = "https://example.com/next"
        require(session.mergeSplit(second,onto:first),"Create a mixed Developer Mode split")
        require(session.tabs[index].developerMode == true && session.tabs.first { $0.id == second }?.developerMode != true,"Split View does not propagate Developer Mode")
        session.detachSplitTab(first)
        session.closeTab(id:first); session.restoreTab()
        let reopened = session.tabs.first { $0.id == first }!
        require(reopened.developerMode == true && reopened.developerCaptureColor == "#E971B8","Navigation, separation and reopening retain the tab's settings")
        let data = try JSONEncoder().encode(session)
        let restored = try JSONDecoder().decode(BrowserSession.self,from:data)
        require(restored == session && restored.validated(),"Developer Mode and capture color survive a valid session round trip")
        var legacy = try JSONSerialization.jsonObject(with:data) as! [String:Any]
        legacy["tabs"] = (legacy["tabs"] as! [[String:Any]]).map { tab in
            var old = tab; old.removeValue(forKey:"developerMode"); old.removeValue(forKey:"developerCaptureColor"); return old
        }
        let compatible = try JSONDecoder().decode(BrowserSession.self,from:JSONSerialization.data(withJSONObject:legacy))
        require(compatible.validated() && compatible.tabs.allSatisfy { $0.developerMode != true },"Existing profiles load with Developer Mode disabled")

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        for width:CGFloat in [160,320,1280] {
            // Match the real window's title-bar layout without showing a window
            // or loading the user's profile. Detached views miss AppKit insets.
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:600),styleMask:[.titled,.fullSizeContentView],backing:.buffered,defer:false)
            window.isReleasedWhenClosed = false; window.titlebarAppearsTransparent = true
            let bar = DeveloperToolbar(tabID:first,language:"fr")
            let height = DeveloperToolbar.height(for:width)
            bar.frame = NSRect(x:0,y:600-height,width:width,height:height)
            window.contentView!.addSubview(bar)
            bar.update(url:"https://example.com/next",tool:"network",loadingCapture:false)
            bar.needsLayout = true; bar.layoutSubtreeIfNeeded()
            let address = bar.subviews.compactMap { $0 as? NSTextField }.first!
            let lock = bar.subviews.compactMap { $0 as? NSImageView }.first!
            let controls = bar.subviews.compactMap { $0 as? NSScrollView }.first!
            require(abs(address.frame.midY-lock.frame.midY) < 0.5,"The URL and lock share a vertical center")
            require(bar.bounds.contains(address.frame) && bar.bounds.contains(controls.frame) && !address.frame.intersects(controls.frame),"URL and action bar stay separate at width \(width)")
            for button in controls.documentView!.subviews.compactMap({ $0 as? NSButton }) {
                let rect = button.convert(button.bounds,to:bar)
                require(rect.minY >= controls.frame.minY && rect.maxY <= controls.frame.maxY,"Every action icon fits vertically inside the toolbar at width \(width): \(rect)")
            }
            require(controls.documentView!.subviews.compactMap { $0 as? NSButton }.filter { !$0.isEnabled }.count == 1,"Only the deferred region capture action is disabled")
            if width == 1280, let image = bar.bitmapImageRepForCachingDisplay(in:bar.bounds) {
                bar.cacheDisplay(in:bar.bounds,to:image)
                try image.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"native/build/developer-toolbar-preview.png"))
            }
            window.close()
        }
        let screenshot = NSImage(size:NSSize(width:800,height:500),flipped:false) { rect in
            NSColor(srgbRed:0.09,green:0.10,blue:0.14,alpha:1).setFill(); rect.fill()
            NSColor.systemBlue.setFill(); NSRect(x:0,y:440,width:800,height:60).fill()
            let attributes:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:30,weight:.bold),.foregroundColor:NSColor.white]
            "Aperçu de la capture".draw(at:NSPoint(x:40,y:355),withAttributes:attributes)
            NSColor.systemTeal.setFill(); NSBezierPath(roundedRect:NSRect(x:40,y:60,width:450,height:250),xRadius:16,yRadius:16).fill()
            NSColor.systemPurple.setFill(); NSBezierPath(roundedRect:NSRect(x:520,y:60,width:240,height:250),xRadius:16,yRadius:16).fill()
            return true
        }
        let image = PortraitRenderer.image(screenshot,color:NSColor(browserHex:"#E971B8")!)!
        let png = PortraitRenderer.png(image)!
        let decoded = NSBitmapImageRep(data:png)!
        require(decoded.pixelsWide > 800 && decoded.pixelsHigh > 500,"Export keeps the complete page with background margins")
        require(decoded.colorAt(x:decoded.pixelsWide/2,y:decoded.pixelsHigh/2)!.alphaComponent == 1,"The exported page is opaque")
        let other = PortraitRenderer.png(PortraitRenderer.image(screenshot,color:.systemBlue)!)!
        require(png != other,"Changing the background changes the actual PNG export")
        require(PortraitRenderer.image(NSImage(size:.zero),color:.systemPink) == nil,"Invalid captures are rejected")
        try png.write(to:URL(fileURLWithPath:"native/build/developer-capture-preview.png"))
        print("Developer Mode: \(checks) checks passed")
    }
}
