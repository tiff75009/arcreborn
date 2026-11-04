import AppKit

private final class CaptureTestScrollEvent:NSEvent {
    var position = CGPoint.zero
    var testPhase:NSEvent.Phase = []
    var testMomentum:NSEvent.Phase = []
    weak var testWindow:NSWindow?
    private let raw:CGEvent
    private let amount:CGFloat
    init(amount:CGFloat = -420) {
        self.amount = amount
        raw = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:2,wheel1:Int32(amount),wheel2:0,wheel3:0)!
        super.init()
    }
    required init?(coder:NSCoder) { fatalError() }
    override var type:NSEvent.EventType { .scrollWheel }
    override var cgEvent:CGEvent? { raw }
    override var window:NSWindow? { testWindow }
    override var windowNumber:Int { testWindow?.windowNumber ?? 0 }
    override var timestamp:TimeInterval { ProcessInfo.processInfo.systemUptime }
    override var modifierFlags:NSEvent.ModifierFlags { [] }
    override var phase:NSEvent.Phase { testPhase }
    override var momentumPhase:NSEvent.Phase { testMomentum }
    override var locationInWindow:NSPoint { position }
    override var scrollingDeltaY:CGFloat { amount }
    override var scrollingDeltaX:CGFloat { 0 }
    override var deltaY:CGFloat { amount }
    override var deltaX:CGFloat { 0 }
    override var hasPreciseScrollingDeltas:Bool { true }
}

// Runs only against a temporary profile and a local test page. Commands and
// geometry snapshots let the short integration check use the real CEF bridge.
@main struct DeveloperDockHarness {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["BROWSER_NATIVE_TEST_DATA"], let address = env["BROWSER_DOCK_TEST_URL"], address.hasPrefix("http://127.0.0.1:") else { fatalError("Isolated local test required") }
        let app = BrowserEngine.createApplication(); app.setActivationPolicy(.prohibited)
        let engine = BrowserEngine()
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:700),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame:window.contentView!.bounds); container.autoresizingMask = [.width,.height]
        window.contentView!.addSubview(container)
        var observers:[NSObjectProtocol] = []
        var lastCommand = ""
        var capture:PageCapture?
        let root = URL(fileURLWithPath:directory)
        let quit = { BrowserEngine.requestQuit() }
        observers.append(NotificationCenter.default.addObserver(forName:NSNotification.Name("BrowserEngineReady"),object:nil,queue:.main) { _ in
            DispatchQueue.main.async {
                window.orderBack(nil)
                _ = engine.createTab("dock-test",profile:"dock-profile",url:address,container:container)
                engine.setTab("dock-test",visible:true)
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName:NSNotification.Name("BrowserEngineReadyToQuit"),object:nil,queue:.main) { _ in BrowserEngine.stopMessageLoop() })
        let timer = Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { _ in
            func allViews(_ view:NSView) -> [NSView] { [view]+view.subviews.flatMap(allViews) }
            func captureClick(_ name:String) { allViews(window.contentView!).compactMap { $0 as? NSButton }.first { $0.title == name }?.performClick(nil) }
            func pointer(_ view:NSView,_ type:NSEvent.EventType,_ point:CGPoint) {
                let location = view.convert(point,to:nil)
                let event = NSEvent.mouseEvent(with:type,location:location,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
                switch type { case .mouseMoved:view.mouseMoved(with:event); case .leftMouseDown:view.mouseDown(with:event); case .leftMouseDragged:view.mouseDragged(with:event); default:view.mouseUp(with:event) }
            }
            if let raw = try? String(contentsOf:root.appendingPathComponent("command")), raw != lastCommand {
                lastCommand = raw
                switch raw.split(separator:" ").last.map(String.init) {
                case "console", "network", "inspect": engine.toggleDeveloperTool(raw.split(separator:" ").last.map(String.init)!,forTab:"dock-test")
                case "close": engine.closeDeveloperTools("dock-test")
                case "hide": container.isHidden = true; engine.setTab("dock-test",visible:false)
                case "show": container.isHidden = false; engine.setTab("dock-test",visible:true)
                case "resize": container.setFrameSize(NSSize(width:820,height:600)); engine.resizeTab("dock-test",container:container)
                case "capture":
                    capture?.close(); let next = PageCapture(tabID:"dock-test",engine:engine,window:window,language:"fr"); capture = next
                    next.saved = { data in
                        try data.write(to:root.appendingPathComponent("capture-result.png"))
                        // Pixel-level regression for the full-page fixture's fixed red header.
                        if let bitmap = NSBitmapImageRep(data:data) {
                            let x = min(bitmap.pixelsWide-1,10)
                            var redRows:[Int] = []
                            for y in 0..<bitmap.pixelsHigh {
                                if let color = bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB), color.redComponent > 0.8, color.greenComponent < 0.25, color.blueComponent < 0.4 { redRows.append(y) }
                            }
                            let result:[String:Any] = ["redFirst":redRows.first ?? -1,"redLast":redRows.last ?? -1,"redCount":redRows.count]
                            try JSONSerialization.data(withJSONObject:result).write(to:root.appendingPathComponent("capture-pixels.json"))
                        }
                    }; next.start()
                case "hover-capture", "take-capture", "drag-capture", "empty-capture", "hover-hint-capture", "take-hint-capture", "scroll-capture", "scroll-burst-capture":
                    if let overlay = allViews(window.contentView!).first(where: { NSStringFromClass(type(of:$0)).contains("CaptureOverlay") }), let page = engine.captureView(forTab:"dock-test") {
                        var point = overlay.convert(CGPoint(x:90,y:page.isFlipped ? 100:page.bounds.height-100),from:page)
                        if raw.hasSuffix("empty-capture") { point.x = overlay.bounds.width-80 }
                        if raw.contains("hint-capture"), let hint = allViews(overlay).first(where: { NSStringFromClass(type(of:$0)).contains("CaptureHint") }) { point = CGPoint(x:hint.frame.midX,y:hint.frame.midY) }
                        if raw.hasSuffix("scroll-burst-capture") {
                            for step in 0...20 {
                                DispatchQueue.main.asyncAfter(deadline:.now()+Double(step)/60) { [weak overlay] in
                                    guard let overlay, overlay.window != nil else { return }
                                    let event = CaptureTestScrollEvent(amount:step == 9 || step == 20 ? 0 : -12)
                                    event.position = overlay.convert(point,to:nil); event.testWindow = window
                                    event.testPhase = step == 0 ? .began : step < 9 ? .changed : step == 9 ? .ended : []
                                    event.testMomentum = step == 10 ? .began : step > 10 && step < 20 ? .changed : step == 20 ? .ended : []
                                    overlay.scrollWheel(with:event)
                                }
                            }
                        }
                        else if raw.hasSuffix("scroll-capture") {
                            let event = CaptureTestScrollEvent(); event.position = overlay.convert(point,to:nil); event.testWindow = window; overlay.scrollWheel(with:event)
                        }
                        else if raw.hasSuffix("hover-capture") || raw.hasSuffix("empty-capture") || raw.hasSuffix("hover-hint-capture") { pointer(overlay,.mouseMoved,point) }
                        else { pointer(overlay,.leftMouseDown,point); if raw.hasSuffix("drag-capture") { pointer(overlay,.leftMouseDragged,CGPoint(x:point.x+120,y:point.y+90)) }; pointer(overlay,.leftMouseUp,point) }
                    }
                case "full-capture": captureClick("Toute la page")
                case "edit-capture": captureClick("Modifier la capture")
                case "retake-capture": captureClick("Reprendre la capture")
                case "done-capture": captureClick("Terminé")
                case "save-capture": captureClick("Enregistrer dans la bibliothèque")
                case "cancel-capture": capture?.close(); capture = nil
                case "draw-capture":
                    if let editor = allViews(window.contentView!).compactMap({ $0 as? CaptureEditor }).first {
                        editor.canvas.tool = .arrow; let rect = editor.canvas.imageRect
                        pointer(editor.canvas,.leftMouseDown,CGPoint(x:rect.minX+20,y:rect.minY+20)); pointer(editor.canvas,.leftMouseDragged,CGPoint(x:rect.midX,y:rect.midY)); pointer(editor.canvas,.leftMouseUp,CGPoint(x:rect.midX,y:rect.midY))
                    }
                case "capture-preview":
                    if let view = allViews(window.contentView!).first(where: { NSStringFromClass(type(of:$0)).contains("CaptureOverlay") }), let rep = view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:rep); try? rep.representation(using:.png,properties:[:])?.write(to:root.appendingPathComponent("capture-preview.png")) }
                case "quit": quit()
                default: break
                }
            }
            func scan(_ view:NSView)->[[String:Any]] {
                var result:[[String:Any]] = []
                let name = NSStringFromClass(type(of:view))
                if name.contains("WebContents") {
                    let frame = view.convert(view.bounds,to:container)
                    result.append(["class":name,"window":view.window?.windowNumber ?? -1,"width":view.bounds.width,"height":view.bounds.height,"x":frame.minX,"y":frame.minY,"hidden":view.isHiddenOrHasHiddenAncestor])
                }
                return result+view.subviews.flatMap(scan)
            }
            // Chromium's remote-cocoa backend exposes synthetic window IDs.
            // Check actual on-screen windows, not those hidden backend proxies.
            let onscreen = (CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []).filter {
                ($0[kCGWindowOwnerPID as String] as? Int) == Int(getpid()) && ($0[kCGWindowLayer as String] as? Int) == 0
            }
            let captureViews = allViews(window.contentView!).filter { NSStringFromClass(type(of:$0)).contains("Capture") }
            let hint = captureViews.first { NSStringFromClass(type(of:$0)).contains("CaptureHint") }
            let overlay = captureViews.first { NSStringFromClass(type(of:$0)).contains("CaptureOverlay") }
            let highlight = overlay?.layer?.sublayers?.first { $0.name == "capture.highlight" }
            let outline = overlay?.layer?.sublayers?.first { $0.name == "capture.outline" }
            let visualLayers = [highlight,highlight?.mask,outline].compactMap { $0 }
            let animations = visualLayers.flatMap { layer in (layer.animationKeys() ?? []).compactMap { layer.animation(forKey:$0) } }
            let hintPoint = hint.map { $0.convert(CGPoint(x:$0.bounds.midX,y:$0.bounds.midY),to:window.contentView) } ?? .zero
            let snapshot:[String:Any] = ["captureViews":captureViews.map { NSStringFromClass(type(of:$0)) },"captureHint":hint?.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.first ?? "", "highlightHidden":highlight?.isHidden ?? true,"captureAnimations":animations.count,"maxCaptureDuration":animations.map(\.duration).max() ?? 0,"hintOpacity":hint?.alphaValue ?? 1,"hintPassesThrough":window.contentView?.hitTest(hintPoint) === overlay,"captureReady":captureViews.compactMap { $0 as? NSButton }.first { $0.title == "Toute la page" }?.isEnabled ?? false,"tool":engine.developerTool(forTab:"dock-test"),"open":engine.hasDeveloperTools("dock-test"),"window":window.windowNumber,"views":scan(container),"visibleWindows":onscreen.compactMap { $0[kCGWindowNumber as String] as? Int }]
            if let data = try? JSONSerialization.data(withJSONObject:snapshot) { try? data.write(to:root.appendingPathComponent("snapshot.json"),options:.atomic) }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+35) { quit() }
        try! FileManager.default.createDirectory(at:root.appendingPathComponent("Chromium"),withIntermediateDirectories:true)
        guard BrowserEngine.start(cachePath:root.appendingPathComponent("Chromium").path) else { fatalError("CEF failed") }
        withExtendedLifetime((engine,window,timer,observers)) { BrowserEngine.runMessageLoop() }
        timer.invalidate(); BrowserEngine.shutdown()
    }
}
