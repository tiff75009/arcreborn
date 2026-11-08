// SPDX-License-Identifier: MPL-2.0
import AppKit

enum OnboardingRelaunch {
    private static let handoffKey = "ARC_REBORN_ONBOARDING_HANDOFF"
    private static var incoming = ProcessInfo.processInfo.environment[handoffKey].flatMap(UUID.init(uuidString:))
    private static func notification(_ id: UUID) -> String {
        "arcreborn.onboarding.window." + id.uuidString
    }

    static func windowDidOpen() {
        guard let id = incoming else { return }
        incoming = nil
        unsetenv(handoffKey)
        // Ordering the window only schedules its presentation. Let AppKit
        // finish processing didBecomeKey before retiring the previous window.
        DispatchQueue.main.async { notify_post(notification(id)) }
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
