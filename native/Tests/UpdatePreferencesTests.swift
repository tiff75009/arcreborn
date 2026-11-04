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
    }
}
