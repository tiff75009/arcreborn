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

    static func keptCurrentBrowser(_ error: NSError) -> Bool {
        // Launch Services wraps userCanceledErr in NSFileReadUnknownError.
        if error.domain == NSOSStatusErrorDomain && error.code == Int(userCanceledErr) { return true }
        if error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError { return true }
        guard let cause = error.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
        return keptCurrentBrowser(cause)
    }
}
