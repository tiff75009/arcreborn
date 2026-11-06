// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

/// NSTableView may cache a proposal while the pointer is stationary. Keep the
/// dwell alive in AppKit's drag-tracking run-loop mode, not only on mouse moves.
final class SidebarDragHeartbeat {
    private var timer:Timer?
    func start(_ refresh:@escaping () -> Void) {
        guard timer == nil else { return }
        let timer = Timer(timeInterval:1/30,repeats:true) { _ in refresh() }
        self.timer = timer
        RunLoop.main.add(timer,forMode:.common)
        RunLoop.main.add(timer,forMode:.eventTracking)
    }
    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
}

/// Dwell belongs to the target row, not an exact pointer location. Choosing a
/// side or making small adjustments must not restart the wait indefinitely.
struct SidebarSplitDropIntent {
    static let delay: TimeInterval = 0.32
    private var source: String?
    private var target: String?
    private var began: TimeInterval = 0
    private var ready = false

    mutating func cancel() { source = nil; target = nil; ready = false }

    static func contains(_ point:NSPoint, in row:NSRect, retainingPreview:Bool) -> Bool {
        // Keep top/bottom insertion lanes. Once open, slightly wider bounds
        // avoid flickering while the pointer crosses the two animated halves.
        let inset:CGFloat = retainingPreview ? 2.5 : 4.5
        return row.insetBy(dx:0,dy:min(inset,row.height/4)).contains(point)
    }

    mutating func update(source: String, target: String, at time: TimeInterval) -> Bool {
        if self.source != source || self.target != target {
            self.source = source; self.target = target; began = time; ready = false
        }
        if time-began >= Self.delay { ready = true }
        return ready
    }
}

/// Keep row identities alive across a move. AppKit animates the whole batch,
/// including the neighbours making room, and retains selection and hit testing.
enum SidebarRowMotion {
    static let duration: TimeInterval = 0.30

    static func update(_ table: NSTableView, from before: [String], to after: [String], animated: Bool) {
        guard table.numberOfRows == before.count,
              Set(before).count == before.count, Set(after).count == after.count else {
            table.reloadData(); return
        }
        guard before != after else { return }
        let new = Dictionary(uniqueKeysWithValues: after.enumerated().map { ($0.element, $0.offset) })
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? duration : 0
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.80, 0.24, 1)
            table.beginUpdates()
            table.removeRows(at: IndexSet(before.indices.filter { new[before[$0]] == nil }),
                             withAnimation: animate ? [.effectFade, .slideUp] : [])
            // Row operations are processed incrementally inside the batch.
            // Resolve each source against the order produced by earlier calls.
            var current = before.filter { new[$0] != nil }
            for (target, id) in after.enumerated() {
                if let source = current.firstIndex(of:id) {
                    if source != target {
                        table.moveRow(at:source,to:target)
                        current.insert(current.remove(at:source),at:target)
                    }
                } else {
                    table.insertRows(at:IndexSet(integer:target),withAnimation:animate ? [.effectFade,.slideDown] : [])
                    current.insert(id,at:target)
                }
            }
            table.endUpdates()
        }
    }

    /// Enable before performDragOperation: otherwise macOS discards the image
    /// immediately on mouse-up, even when the rows themselves are animated.
    static func prepare(_ info: NSDraggingInfo) {
        info.animatesToDestination = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func land(_ info: NSDraggingInfo, in view: NSView, frame: NSRect) {
        guard !frame.isEmpty else { return }
        info.enumerateDraggingItems(options: [], for: view, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
            item.draggingFrame = frame
        }
    }
}
