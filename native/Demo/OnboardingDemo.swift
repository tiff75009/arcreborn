// SPDX-License-Identifier: MPL-2.0
import AppKit

@main
final class OnboardingDemo: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var welcome: WelcomeWindow?

    static func main() {
        // Keep the account form offline under Launch Services and from the CLI.
        setenv("BROWSER_NATIVE_TEST_DATA", "onboarding-demo", 1)
        let app = NSApplication.shared
        let delegate = OnboardingDemo()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bar = NSMenu()
        let item = NSMenuItem()
        let menu = NSMenu(title: "Démo Arc Reborn")
        let replay = menu.addItem(withTitle: "Recommencer la démo", action: #selector(restart), keyEquivalent: "r")
        replay.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter la démo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = menu
        bar.addItem(item)
        NSApp.mainMenu = bar
        restart()
    }

    @objc private func restart() {
        welcome?.window?.delegate = nil
        welcome?.close()
        let controller = WelcomeWindow(language: "fr")
        var scratch = BrowserSession.fresh(language: "fr")
        let profile = scratch.profiles[0].id
        controller.importLinks = { links, source in
            try scratch.importLinks(links, from: source, profileID: profile)
        }
        controller.finish = { _, _ in NSApp.terminate(nil) }
        welcome = controller
        guard let window = controller.window else { return }
        window.delegate = self
        window.styleMask.insert(.closable)
        (window as? NSPanel)?.hidesOnDeactivate = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restart()
        return false
    }

    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}
