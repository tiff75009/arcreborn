// SPDX-License-Identifier: MPL-2.0
import AppKit

enum DefaultBrowser {
    static let webSchemes = ["http", "https"]

    // A scheme-only lookup asks Launch Services without opening a page or
    // accidentally matching a site's universal link. Dev has its own bundle ID.
    static func owns(_ scheme: String) -> Bool {
        guard let id = Bundle.main.bundleIdentifier, let url = URL(string: scheme + ":"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
        return Bundle(url: handler)?.bundleIdentifier == id
    }
    static var isCurrent: Bool { webSchemes.allSatisfy(owns) }
}
