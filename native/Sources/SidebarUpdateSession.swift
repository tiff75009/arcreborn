// SPDX-License-Identifier: MPL-2.0
import Foundation

/// One update transaction shared by every window. Replies are consumed before
/// invoking Sparkle, which may synchronously advance to the next stage.
final class SidebarUpdateSession {
    enum Phase { case hidden, available, downloading, preparing, ready, installing, awaitingRestart }
    static let changed = Notification.Name("BrowserSidebarUpdateChanged")
    static let focus = Notification.Name("BrowserSidebarUpdateFocus")
    private(set) var phase: Phase = .hidden
    private(set) var progress: Double?
    private var reply: (() -> Void)?
    private var installRequested = false
    var actionable: Bool { reply != nil }

    func offer(ready: Bool, reply: @escaping () -> Void) {
        installRequested = false
        self.reply = reply
        set(ready ? .ready : .available)
    }
    func activate() {
        guard let action = reply else { return }
        reply = nil
        installRequested = true
        set((phase == .ready || phase == .awaitingRestart) ? .installing : .downloading)
        action()
    }
    func downloading(_ progress: Double? = nil) { reply = nil; set(.downloading, progress:progress) }
    func preparing(_ progress: Double? = nil) { reply = nil; set(.preparing, progress:progress) }
    func ready(reply: @escaping () -> Void) {
        self.reply = reply
        set(.ready)
        // The explicit "Restart and Update" press authorizes the complete flow.
        if installRequested { activate() }
    }
    func installing() { reply = nil; set(.installing) }
    func awaitingTermination(retry: @escaping () -> Void) { reply = retry; set(.awaitingRestart) }
    func finish() { reply = nil; installRequested = false; set(.hidden) }
    private func set(_ phase: Phase, progress: Double? = nil) {
        let previousProgress = self.progress
        let continuing = self.phase == phase && (phase == .downloading || phase == .preparing)
        self.phase = phase
        self.progress = progress.flatMap { $0.isFinite ? min(1,max(0,$0)) : nil }
        // Sparkle may deliver hundreds of chunks per second. Repaint each
        // sidebar when its displayed percentage changes.
        if continuing, previousProgress.map({ Int($0 * 100) }) == self.progress.map({ Int($0 * 100) }) { return }
        NotificationCenter.default.post(name:Self.changed,object:self)
    }
}
