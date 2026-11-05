// SPDX-License-Identifier: MPL-2.0
import AppKit
import Sparkle

/// Runs inside a disposable bundle, never starts the updater or contacts a feed.
@main
struct UpdatePreferencesTests {
    static func main() {
        guard let domain = Bundle.main.bundleIdentifier,
              domain.hasPrefix("local.arcreborn.update-test.") else {
            fatalError("A disposable test bundle is required")
        }
        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        func controller() -> SPUStandardUpdaterController {
            SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        }
        let first = controller()
        precondition(first.updater.automaticallyChecksForUpdates)
        precondition(first.updater.automaticallyDownloadsUpdates)
        precondition(first.updater.updateCheckInterval == 6 * 60 * 60)
        first.updater.automaticallyDownloadsUpdates = false
        first.updater.automaticallyChecksForUpdates = false
        let restored = controller()
        precondition(!restored.updater.automaticallyChecksForUpdates)
        precondition(!restored.updater.automaticallyDownloadsUpdates)
        restored.updater.automaticallyChecksForUpdates = true
        precondition(!restored.updater.automaticallyDownloadsUpdates,
                     "Re-enabling checks must preserve the manual installation choice")
        restored.updater.automaticallyDownloadsUpdates = true
        precondition(controller().updater.automaticallyDownloadsUpdates)
        print("PASS: Sparkle defaults and persistent opt-outs (no network or Keychain)")
        _ = NSApplication.shared
        let updates = BrowserUpdates.shared
        let resource = Bundle.main.url(forResource:"ReleaseNotes",withExtension:"json")!
        let notes = try! JSONDecoder().decode(ReleaseNotes.self,from:Data(contentsOf:resource))
        if notes.showOnLaunch == false {
            let key = "ArcRebornLastNewsBuild"
            defaults.set(notes.build - 1, forKey: key)
            for _ in 0..<2 { // Upgrade, then relaunch on the same build.
                updates.presentNewsAfterUpgrade { fatalError("Silent update scheduled a news window") }
                precondition(defaults.integer(forKey:key) == notes.build)
            }
            RunLoop.main.run(until:Date(timeIntervalSinceNow:2.2))
            precondition(!NSApp.windows.contains(where:{ $0.isVisible }))
            print("PASS: silent update and subsequent launch leave release notes closed")
        } else {
            let key = "ArcRebornLastNewsBuild"
            defaults.set("fr",forKey:"BrowserLanguage")
            updates.presentNewsAfterUpgrade { true }
            precondition(defaults.integer(forKey:key) == notes.build && !NSApp.windows.contains(where:{ $0.isVisible }),"Fresh install establishes a baseline")
            defaults.set(notes.build - 1,forKey:key)
            updates.presentNewsAfterUpgrade { true }
            RunLoop.main.run(until:Date(timeIntervalSinceNow:2.5))
            guard let window = NSApp.windows.first(where:{ $0.isVisible && $0.title == "Nouveautés d’Arc Reborn" }) else {
                fatalError("Release highlights were not shown after the upgrade")
            }
            precondition(defaults.integer(forKey:key) == notes.build)
            window.close()
            updates.presentNewsAfterUpgrade { fatalError("Replay of release highlights on the next launch") }
            precondition(!window.isVisible)
            print("PASS: upgrading opens release notes once, fresh installs and subsequent launches stay quiet")
        }
        func fields(_ view:NSView) -> [String] {
            (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap(fields)
        }
        for (index, lang) in ["fr", "en", "fr"].enumerated() {
            defaults.set(lang,forKey:"BrowserLanguage")
            NotificationCenter.default.post(name:Notification.Name("BrowserLanguageChanged"),object:lang)
            if index != 1 { precondition(updates.showNews()) } // English must refresh an already visible window.
            let isFrench = lang == "fr"
            let title = isFrench ? "Nouveautés d’Arc Reborn" : "What’s new in Arc Reborn"
            guard let window = NSApp.windows.first(where:{ $0.isVisible && $0.title == title }) else {
                fatalError("No visible release notes for "+lang)
            }
            let text = fields(window.contentView!)
            precondition(text.contains(isFrench ? notes.title.fr : notes.title.en))
            for row in notes.highlights { precondition(text.contains(isFrench ? row.detail.fr : row.detail.en)) }
            precondition(updates.feedURLString(for:first.updater)?.hasSuffix("/appcast-"+lang+".xml") == true)
            if index == 1 { window.close() }
        }
        print("PASS: open, live and reopened release notes and update feeds follow the browser language")
    }
}
