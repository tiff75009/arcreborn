// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Owns one advertised activity for the app's selected window. Publishing is
/// metadata-only: it must never reload, navigate or recreate a Chromium page.
final class BrowserHandoff {
    struct Page: Equatable {
        let url: URL
        let title: String

        init?(address:String?, title:String, isPrivate:Bool, isAvailable:Bool = true) {
            guard !isPrivate, isAvailable, let url = browserWebURL(address) else { return nil }
            self.url = url
            self.title = String(title.replacingOccurrences(of:"\0",with:"").prefix(512))
        }
    }

    private let makeActivity: () -> NSUserActivity
    private(set) var activity: NSUserActivity?

    init(makeActivity: @escaping () -> NSUserActivity = { NSUserActivity(activityType:NSUserActivityTypeBrowsingWeb) }) {
        self.makeActivity = makeActivity
    }

    @discardableResult static func receive(_ activity:NSUserActivity, open:(URL)->Void) -> Bool {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = browserWebURL(activity.webpageURL?.absoluteString) else { return false }
        open(url)
        return true
    }

    func update(_ page:Page?) {
        guard let page else { invalidate(); return }
        if let activity, activity.webpageURL == page.url {
            if activity.title != page.title { activity.title = page.title; activity.needsSave = true }
            return
        }
        invalidate()
        let next = makeActivity()
        next.webpageURL = page.url
        next.title = page.title
        next.isEligibleForHandoff = true
        next.isEligibleForSearch = false
        next.isEligibleForPublicIndexing = false
        activity = next
        next.becomeCurrent()
    }

    func invalidate() { activity?.invalidate(); activity = nil }
    deinit { activity?.invalidate() }
}
