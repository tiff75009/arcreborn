import AppKit
@main struct PasswordRuntimeHarness {
    static func main() throws {
        guard let path = ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"], path.contains("password-runtime") else { fatalError("isolated test only") }
        let directory = URL(fileURLWithPath:path), store = SessionStore(directory:directory)
        let initial = try store.load()!
        UserDefaults.standard.set(initial.language,forKey:"BrowserLanguage")
        UserDefaults.standard.set(initial.passwordManagerID ?? "native",forKey:"BrowserPasswordManager")
        UserDefaults.standard.set(true,forKey:"BrowserSavePasswords")
        UserDefaults.standard.set(false,forKey:"BrowserAutomaticSignIn")
        UserDefaults.standard.set(true,forKey:"BrowserFormSuggestions")
        let app = BrowserEngine.createApplication(); app.setActivationPolicy(.regular)
        let delegate = NativeAppDelegate(store:store,initial:initial); app.delegate = delegate
        var last = "", reported:Set<String> = []
        func log(_ value:String) { print(value); fflush(stdout) }
        func button(_ title:String,in view:NSView) -> NSButton? {
            if let b = view as? NSButton, b.title == title { return b }
            for child in view.subviews { if let found = button(title,in:child) { return found } }; return nil
        }
        let timer = Timer.scheduledTimer(withTimeInterval:0.15,repeats:true) { _ in MainActor.assumeIsolated {
            guard let controller = delegate.controller else { return }
            let panels = NSApp.windows.filter { $0 is NSPanel && $0.isVisible && $0.parent === controller.window }
            for panel in panels {
                if let view = panel.contentView, let save = button("Enregistrer",in:view) ?? button("Mettre à jour",in:view), !reported.contains(String(panel.windowNumber)) {
                    reported.insert(String(panel.windowNumber)); log(save.title == "Enregistrer" ? "PROMPT save" : "PROMPT update")
                    view.layoutSubtreeIfNeeded();view.displayIfNeeded()
                    let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds)!
                    view.cacheDisplay(in:view.bounds,to:bitmap)
                    try? bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("actual-prompt.png"))
                    if ProcessInfo.processInfo.environment["PASSWORD_TEST_SCREENSHOT"] == "1",
                       !FileManager.default.fileExists(atPath:directory.appendingPathComponent("actual-window.png").path),
                       let screen = NSScreen.screens.first {
                        let frame = controller.window.frame
                        let capture = Process(); capture.executableURL = URL(fileURLWithPath:"/usr/sbin/screencapture")
                        capture.arguments = ["-x","-R", "\(Int(frame.minX)),\(Int(screen.frame.maxY-frame.maxY)),\(Int(frame.width)),\(Int(frame.height))",directory.appendingPathComponent("actual-window.png").path]
                        try? capture.run(); capture.waitUntilExit()
                    }
                    _ = save
                }
            }
            guard let command = try? String(contentsOf:directory.appendingPathComponent("command")), command != last else { return }
            last = command
            let action = command.split(separator:" ").last.map(String.init) ?? ""
            switch action {
            case "settings": controller.settingsAction(nil); log("SETTINGS")
            case "external", "native":
                guard let window = NSApp.windows.first(where: { $0.title == "Préférences" && $0.isVisible }), let content = window.contentView else { log("ERROR no preferences"); return }
                if let tab = button("Mots de passe",in:content) { tab.performClick(nil) }
                func modeControl(_ view:NSView) -> NSSegmentedControl? {
                    if let segment = view as? NSSegmentedControl, segment.identifier?.rawValue == "password-manager-mode" { return segment }
                    for child in view.subviews { if let value = modeControl(child) { return value } }; return nil
                }
                guard let mode = modeControl(content) else { log("ERROR no mode control"); return }
                mode.selectedSegment = action == "native" ? 0 : 1
                mode.sendAction(mode.action,to:mode.target)
                if action == "external", let choice = button("Proton Pass",in:content) { choice.performClick(nil) }
                log("MANAGER " + (controller.windowSession.passwordManagerID ?? "native"))
                content.layoutSubtreeIfNeeded(); content.displayIfNeeded()
                if let view = window.contentView?.superview, let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                    view.cacheDisplay(in:view.bounds,to:bitmap)
                    try? bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("actual-settings-"+action+".png"))
                }
                window.orderOut(nil); controller.window.makeKeyAndOrderFront(nil)
            case "save", "later", "never":
                let title = action == "save" ? "Enregistrer" : action == "never" ? "Jamais pour ce site" : "Pas maintenant"
                guard let b = panels.compactMap({ $0.contentView.flatMap { button(title,in:$0) ?? (action == "save" ? button("Mettre à jour",in:$0) : nil) } }).first else { log("ERROR no prompt action"); return }
                b.performClick(nil); log("ACTION " + action)
            case "quit": delegate.requestQuit()
            default: break
            }
        } }
        guard BrowserEngine.start(cachePath:directory.appendingPathComponent("Chromium").path) else { fatalError("engine") }
        withExtendedLifetime((timer,delegate)) { BrowserEngine.runMessageLoop() }; timer.invalidate(); BrowserEngine.shutdown()
        log("QUIT OK")
    }
}
