// SPDX-License-Identifier: MPL-2.0
import AppKit

@main enum DefaultBrowserTests {
    static func main() {
        let cancel = NSError(domain:NSOSStatusErrorDomain,code:Int(userCanceledErr))
        let wrapped = NSError(domain:NSCocoaErrorDomain,code:NSFileReadUnknownError,
                              userInfo:[NSUnderlyingErrorKey:cancel])
        precondition(DefaultBrowser.keptCurrentBrowser(wrapped))
        precondition(DefaultBrowser.keptCurrentBrowser(cancel))
        precondition(DefaultBrowser.keptCurrentBrowser(NSError(domain:NSCocoaErrorDomain,code:NSUserCancelledError)))
        precondition(!DefaultBrowser.keptCurrentBrowser(NSError(domain:NSCocoaErrorDomain,code:NSFileReadUnknownError)))
        precondition(!DefaultBrowser.keptCurrentBrowser(NSError(domain:NSPOSIXErrorDomain,code:Int(EACCES))))
        print("PASS: keeping the current browser, wrapped Launch Services cancellation and genuine failures")
    }
}
