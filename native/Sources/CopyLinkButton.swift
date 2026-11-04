import AppKit
import QuartzCore

final class CopyLinkButton: NavigationButton {
    private var resetTask: DispatchWorkItem?
    func copied() {
        resetTask?.cancel()
        image = NSImage(systemSymbolName:"checkmark",accessibilityDescription:nil)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let pulse = CAKeyframeAnimation(keyPath:"transform.scale")
            pulse.values = [1,0.86,1.08,1]; pulse.keyTimes = [0,0.25,0.65,1]; pulse.duration = 0.3
            pulse.timingFunctions = Array(repeating:CAMediaTimingFunction(name:.easeInEaseOut),count:3)
            layer?.add(pulse,forKey:"copied")
        }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.image = NSImage(systemSymbolName:"link",accessibilityDescription:nil)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let fade = CATransition(); fade.type = .fade; fade.duration = 0.16; self.layer?.add(fade,forKey:"copy-reset")
            }
            self.resetTask = nil
        }
        resetTask = task; DispatchQueue.main.asyncAfter(deadline:.now()+1,execute:task)
    }
    deinit { resetTask?.cancel() }
}
