import AppKit

private final class PiPDelegate:NSObject,BrowserEngineDelegate {
    var returned = false
    var onReturn:(()->Void)?
    func browserTitleChanged(_ tabID:String,title:String) {}
    func browserURLChanged(_ tabID:String,url:String) {}
    func browserLoadingChanged(_ tabID:String,loading:Bool,back:Bool,forward:Bool) {}
    func browserFailed(_ tabID:String,code:String,host:String?) {}
    func browserRequestedNewTab(_ url:String,sourceTab:String) {}
    func browserClosed(_ tabID:String) {}
    func browserPictureInPictureReturn(_ tabID:String) { returned = true; onReturn?() }
}

@main struct PictureInPictureHarness {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["BROWSER_NATIVE_TEST_DATA"], let address = env["BROWSER_PIP_TEST_URL"], address.hasPrefix("http://127.0.0.1:") else { fatalError("Isolated test only") }
        let app = BrowserEngine.createApplication(); app.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath:directory)
        let engine = BrowserEngine(), delegate = PiPDelegate(); engine.delegate = delegate
        let pip = PictureInPictureController(engine:engine)
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:600),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame:window.contentView!.bounds); container.autoresizingMask = [.width,.height]; window.contentView!.addSubview(container)
        var eligible:Set<String> = ["pip-test"]
        let show = {
            pip.update(visible:["pip-test"],eligible:eligible)
            container.isHidden = false; engine.setTab("pip-test",visible:true)
        }
        delegate.onReturn = show
        var observers:[NSObjectProtocol] = []
        observers.append(NotificationCenter.default.addObserver(forName:NSNotification.Name("BrowserEngineReady"),object:nil,queue:.main) { _ in
            DispatchQueue.main.async { window.orderBack(nil); _ = engine.createTab("pip-test",profile:"pip-profile",url:address,container:container); show() }
        })
        observers.append(NotificationCenter.default.addObserver(forName:NSNotification.Name("BrowserEngineReadyToQuit"),object:nil,queue:.main) { _ in BrowserEngine.stopMessageLoop() })
        var command = "", result = ""
        let timer = Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { _ in
            if let value = try? String(contentsOf:root.appendingPathComponent("command")), value != command {
                command = value
                switch value.split(separator:" ").last.map(String.init) {
                case "toggle": pip.toggle("pip-test") { result = $0 }
                case "hide": pip.update(visible:[],eligible:eligible); container.isHidden = true; engine.setTab("pip-test",visible:false)
                case "show": show()
                case "disable": eligible = []; pip.update(visible:container.isHidden ? [] : ["pip-test"],eligible:eligible)
                case "enable": eligible = ["pip-test"]; pip.update(visible:container.isHidden ? [] : ["pip-test"],eligible:eligible)
                case "quick-switch":
                    pip.update(visible:[],eligible:eligible); engine.setTab("pip-test",visible:false); show()
                case "return-pip":
                    var debug:[String] = []
                    func press(_ value:Any,depth:Int=0)->Bool {
                        guard depth<25, let node = value as? NSAccessibilityProtocol else { return false }
                        let object = value as? NSObject
                        let label = [node.accessibilityLabel(),node.accessibilityTitle(),node.accessibilityHelp(),object?.accessibilityAttributeValue(.description) as? String].compactMap{$0}.joined(separator:" ")
                        debug.append("\(node.accessibilityRole()?.rawValue ?? "?") \(label) \(node.accessibilityFrame())")
                        if node.accessibilityRole() == .button && (label.lowercased().contains("onglet") || label.lowercased().contains("back to tab")) { object?.accessibilityPerformAction(.press); return true }
                        for child in node.accessibilityChildren() ?? [] { if press(child,depth:depth+1) { return true } }
                        return false
                    }
                    for candidate in NSApp.windows where candidate.isVisible && NSStringFromClass(type(of:candidate)) == "NativeWidgetMacFramelessNSWindow" { _ = press(candidate) }
                    try? JSONSerialization.data(withJSONObject:debug).write(to:root.appendingPathComponent("return-accessibility.json"))
                case "focus-pip":
                    app.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps:true)
                    NSApp.windows.first { NSStringFromClass(type(of:$0)) == "NativeWidgetMacFramelessNSWindow" && $0.isVisible }?.makeKeyAndOrderFront(nil)
                case "close-tab": engine.closeTab("pip-test")
                case "quit": pip.stop(); BrowserEngine.requestQuit()
                default: break
                }
            }
            let state:[String:Any] = ["active":engine.hasPictureInPicture("pip-test"),"result":result,"returned":delegate.returned,
                "backendVisible":NSApp.windows.contains { $0.identifier?.rawValue == "local.browser.backend" && $0.isVisible }]
            try? JSONSerialization.data(withJSONObject:state).write(to:root.appendingPathComponent("snapshot.json"),options:.atomic)
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+45) { BrowserEngine.requestQuit() }
        try! FileManager.default.createDirectory(at:root.appendingPathComponent("Chromium"),withIntermediateDirectories:true)
        guard BrowserEngine.start(cachePath:root.appendingPathComponent("Chromium").path) else { fatalError("CEF failed") }
        withExtendedLifetime((engine,delegate,pip,window,timer,observers)) { BrowserEngine.runMessageLoop() }
        timer.invalidate(); BrowserEngine.shutdown()
    }
}
