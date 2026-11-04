import AppKit
import Darwin

// Short, isolated latency check using an already installed test extension.
// No user profile, browser account or extension storage is opened.
@main struct ExtensionPopupHarness {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["BROWSER_NATIVE_TEST_DATA"], path.contains("/native/build/"),
              let identifier = env["BROWSER_EXTENSION_TEST_ID"] else { fatalError("Isolated profile required") }
        let root = URL(fileURLWithPath:path)
        let address = env["BROWSER_EXTENSION_TEST_URL"] ?? "about:blank"
        precondition(address == "about:blank" || address.hasPrefix("http://127.0.0.1:"))
        let app = BrowserEngine.createApplication(); app.setActivationPolicy(.accessory)
        let engine = BrowserEngine()
        let window = NSWindow(contentRect:NSRect(x:200,y:200,width:900,height:600),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame:window.contentView!.bounds)
        window.contentView!.addSubview(container)
        var observers:[NSObjectProtocol] = []
        var phase = 0, started:TimeInterval = 0, next:TimeInterval = .greatestFiniteMagnitude
        var records:[[String:Any]] = []
        typealias State = @convention(c) (Int32,UnsafePointer<CChar>?,UnsafeMutablePointer<Int32>?) -> Int32
        var state:State?
        var polls:Timer?
        func record(_ event:String,_ fields:[String:Any] = [:]) {
            var item = fields; item["event"] = event; records.append(item)
            try? JSONSerialization.data(withJSONObject:records,options:.prettyPrinted).write(to:root.appendingPathComponent("latency.json"),options:.atomic)
        }
        observers.append(NotificationCenter.default.addObserver(forName:NSNotification.Name("BrowserEngineReady"),object:nil,queue:.main) { _ in
            DispatchQueue.main.async {
                window.makeKeyAndOrderFront(nil)
                _ = engine.createTab("popup-test",profile:"profile-a",url:address,container:container)
                engine.setTab("popup-test",visible:true)
                let library = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework")
                if let handle = dlopen(library.path,RTLD_LAZY | RTLD_NOLOAD), let symbol = dlsym(handle,"browser_extension_popup_state_v1") { state = unsafeBitCast(symbol,to:State.self) }
                next = ProcessInfo.processInfo.systemUptime+3
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName:NSNotification.Name("BrowserEngineReadyToQuit"),object:nil,queue:.main) { _ in BrowserEngine.stopMessageLoop() })
        polls = Timer.scheduledTimer(withTimeInterval:0.016,repeats:true) { _ in
            MainActor.assumeIsolated {
                let now = ProcessInfo.processInfo.systemUptime
                if phase % 2 == 0 && now >= next && phase < 4 {
                    started = now
                    let result = engine.activateExtension(identifier,tab:"popup-test",anchor:window.convertToScreen(NSRect(x:20,y:560,width:26,height:25)))
                    record("dispatch",["attempt":phase/2+1,"result":result,"ms":(ProcessInfo.processInfo.systemUptime-started)*1000])
                    phase += 1
                } else if phase % 2 == 1 {
                    var bounds = [Int32](repeating:0,count:4)
                    let visible = identifier.withCString { id in state?(1,id,&bounds) ?? 0 }
                    if visible == 2 || now-started > 8 {
                        record(visible == 2 ? "visible" : "timeout",["attempt":(phase+1)/2,"state":visible,"ms":(now-started)*1000])
                        phase += 1; next = now+2
                        DispatchQueue.main.asyncAfter(deadline:.now()+1) {
                            engine.closeExtensionPopup()
                            if phase == 4 { BrowserEngine.requestQuit() }
                        }
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+24) { BrowserEngine.requestQuit() }
        guard BrowserEngine.start(cachePath:root.appendingPathComponent("Chromium").path) else { fatalError("CEF failed") }
        withExtendedLifetime((engine,window,observers,polls)) { BrowserEngine.runMessageLoop() }
        polls?.invalidate(); BrowserEngine.shutdown()
    }
}
