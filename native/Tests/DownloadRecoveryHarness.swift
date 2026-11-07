// SPDX-License-Identifier: MPL-2.0
import AppKit

@main struct DownloadRecoveryHarness {
    static func main() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["BROWSER_NATIVE_TEST_DATA"], path.contains("download-recovery-check-"),
              let origin = env["RECOVERY_ORIGIN"], origin.hasPrefix("http://127.0.0.1:"),
              let mode = env["RECOVERY_MODE"], let phase = env["RECOVERY_PHASE"] else {
            fatalError("An isolated loopback fixture is required")
        }
        let app = BrowserEngine.createApplication()
        app.setActivationPolicy(.regular)
        let store = SessionStore(directory:URL(fileURLWithPath:path))
        let cache = store.directory.appendingPathComponent("Chromium")
        try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
        var session = try store.load() ?? BrowserSession.fresh(language:"fr")
        if phase == "first" {
            session.onboardingComplete = true
            _ = session.createTab(url:origin+"/page")
            try store.save(session)
        }
        let delegate = NativeAppDelegate(store:store,initial:session)
        app.delegate = delegate
        var stage = 0
        let deadline = Date().addingTimeInterval(45)
        func buttons(_ view:NSView) -> [NSButton] {
            if view.isHiddenOrHasHiddenAncestor { return [] }
            return (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        let metadata = store.directory.appendingPathComponent("library.json")
        let timer = Timer.scheduledTimer(withTimeInterval:0.12,repeats:true) { timer in MainActor.assumeIsolated {
            guard Date() < deadline else {
                let titles = delegate.controller?.window.contentView.map { buttons($0).map(\.title).filter { !$0.isEmpty } } ?? []
                print("Timed out during \(mode), \(phase), stage \(stage), visible buttons \(titles)"); fflush(stdout)
                exit(1)
            }
            guard let window = delegate.controller, window.window.isVisible, let tab = window.windowSession.tabs.last else { return }
            let data = try? Data(contentsOf:metadata)
            let json = data.flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] }
            let rows = json?["downloads"] as? [[String:Any]] ?? []
            if phase == "first" {
                if stage == 0 && tab.title == "Download fixture" {
                    WindowBrowserEngine(windowID:window.windowID).navigateTab(tab.id,url:origin+"/"+mode)
                    stage += 1
                } else if stage == 1, let row = rows.first, (row["received"] as? Int ?? 0) > 0 {
                    precondition(row["state"] as? String == "progress")
                    print("PASS partial recorded before quitting (\(mode))"); fflush(stdout)
                    if mode == "crash" { _exit(0) }
                    timer.invalidate(); delegate.requestQuit()
                }
            } else if stage == 0 && tab.title == "Restored fixture" {
                window.performBrowserCommand("downloads"); stage += 1
            } else if stage == 1, let root = window.window.contentView {
                let title = mode == "full" ? "Recommencer" : "Reprendre"
                if let action = buttons(root).first(where:{ $0.title == title && !$0.visibleRect.isEmpty }) {
                    action.performClick(nil); stage += 1
                    print("PASS clicked visible \(title) in native library"); fflush(stdout)
                }
            } else if stage == 2, mode == "changed", let root = window.window.contentView,
                      let restart = buttons(root).first(where:{ $0.title == "Recommencer" && !$0.visibleRect.isEmpty }) {
                restart.performClick(nil); stage += 1
            } else if stage >= 2, rows.count == 1, rows.first?["state"] as? String == "complete" {
                print("PASS recovered original library row (\(mode))"); fflush(stdout)
                timer.invalidate(); delegate.requestQuit()
            }
        } }
        guard BrowserEngine.start(cachePath:cache.path) else { fatalError("CEF initialization") }
        withExtendedLifetime((delegate,timer)) { BrowserEngine.runMessageLoop() }
        BrowserEngine.shutdown()
    }
}
