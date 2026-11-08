// SPDX-License-Identifier: MPL-2.0
import AppKit

enum OnboardingRelaunch {
    private static let handoffKey = "ARC_REBORN_ONBOARDING_HANDOFF"
    private static var incoming = ProcessInfo.processInfo.environment[handoffKey].flatMap(UUID.init(uuidString:))
    private static func notification(_ id: UUID) -> String {
        "arcreborn.onboarding.window." + id.uuidString
    }

    static func windowDidOpen(_ window: NSWindow) {
        guard let id = incoming else { return }
        incoming = nil
        unsetenv(handoffKey)
        // AppKit may deliver didBecomeKey before WindowServer has composited
        // the restored window, particularly when Chromium is opening settings.
        let number = CGWindowID(window.windowNumber)
        let deadline = DispatchTime.now() + 3
        func waitForPresentation() {
            let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, number) as? [[String:Any]]
            let presented = windows?.first.map {
                ($0[kCGWindowIsOnscreen as String] as? Bool) == true &&
                ($0[kCGWindowAlpha as String] as? Double ?? 0) >= 0.95
            } ?? false
            if presented || DispatchTime.now() >= deadline {
                notify_post(notification(id))
            } else {
                DispatchQueue.main.asyncAfter(deadline:.now() + .milliseconds(16), execute:waitForPresentation)
            }
        }
        DispatchQueue.main.async(execute:waitForPresentation)
    }

    /// Chromium has released its process lock. Keep the setup window on screen
    /// until the replacement has ordered its restored window to the front.
    static func launch() throws {
        guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        let id = UUID(), ready = DispatchSemaphore(value:0)
        var token: Int32 = 0
        let registered = notify_register_dispatch(notification(id), &token, .global()) { _ in ready.signal() } == NOTIFY_STATUS_OK
        defer { if registered { notify_cancel(token) } }
        let replacement = Process()
        replacement.executableURL = executable
        var environment = ProcessInfo.processInfo.environment
        environment[handoffKey] = id.uuidString
        replacement.environment = environment
        replacement.terminationHandler = { _ in ready.signal() }
        try replacement.run()
        if registered { _ = ready.wait(timeout:.now()+30) }
    }
}
