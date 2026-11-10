import AppKit

/// Isolated controller fixture; the Node driver exercises real Chromium links.
@main struct TabOriginHarness {
    static func main() throws {
        guard let path = ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"],
              path.contains("tab-origin-check-") else { fatalError("Isolated fixture required") }
        let directory = URL(fileURLWithPath:path)
        let store = SessionStore(directory:directory)
        let initial = try store.load()!
        let app = BrowserEngine.createApplication(); app.setActivationPolicy(.regular)
        let delegate = NativeAppDelegate(store:store,initial:initial); app.delegate = delegate
        var last = "", snapshot = Data()
        let timer = Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { _ in MainActor.assumeIsolated {
            guard let controller = delegate.controller else { return }
            if let data = try? Data(contentsOf:directory.appendingPathComponent("command.json")),
               let command = try? JSONSerialization.jsonObject(with:data) as? [String:String],
               let id = command["id"], id != last {
                last = id
                switch command["action"] {
                case "new": controller.performBrowserCommand("newTab")
                case "close": controller.performBrowserCommand("closeTab")
                case "select":
                    for _ in 0..<controller.windowSession.tabs.count {
                        let session = controller.windowSession
                        if session.spaces.first(where:{ $0.id == session.activeSpaceID })?.selectedTabID == command["tab"] { break }
                        controller.performBrowserCommand("tabNext")
                    }
                case "capture":
                    if let view = controller.window.contentView?.superview,
                       let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                        view.cacheDisplay(in:view.bounds,to:bitmap)
                        try? bitmap.representation(using:.png,properties:[:])?.write(to:directory.appendingPathComponent("observed.png"))
                    }
                case "quit": delegate.requestQuit()
                default: break
                }
            }
            if let data = try? JSONEncoder().encode(controller.windowSession), data != snapshot {
                snapshot = data
                try? data.write(to:directory.appendingPathComponent("observed.json"),options:.atomic)
            }
            try? last.write(to:directory.appendingPathComponent("ack"),atomically:true,encoding:.utf8)
        } }
        guard BrowserEngine.start(cachePath:directory.appendingPathComponent("Chromium").path) else { fatalError("CEF initialization") }
        withExtendedLifetime((delegate,timer)) { BrowserEngine.runMessageLoop() }
        BrowserEngine.shutdown()
    }
}
