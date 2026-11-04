import Foundation

/// Policy is kept outside the page: a site cannot enable the automatic setting.
/// A manual PiP session stays open when returning to the tab; an automatic one
/// returns inline as soon as its source panel becomes visible again.
final class PictureInPictureController {
    private let engine: BrowserEngine
    private var visible = [String]()
    private var eligible = Set<String>()
    private var automaticTab: String?
    private var pendingTab: String?
    private var stopped = false
    init(engine: BrowserEngine) { self.engine = engine }

    func update(visible next: [String], eligible: Set<String>) {
        let departing = visible.filter { !next.contains($0) && eligible.contains($0) }
        visible = next; self.eligible = eligible
        if let id = pendingTab, next.contains(id) || !eligible.contains(id) { engine.closePictureInPicture(id) }
        if let id = automaticTab, next.contains(id) || !eligible.contains(id) {
            engine.closePictureInPicture(id); automaticTab = nil
        }
        guard !stopped, pendingTab == nil, let id = departing.first else { return }
        pendingTab = id
        engine.requestPictureInPicture(id, automatic: true) { [weak self] result in
            guard let self else { return }
            self.pendingTab = nil
            guard result == "opened" else { return }
            if self.stopped || self.visible.contains(id) || !self.eligible.contains(id) {
                self.engine.closePictureInPicture(id)
            } else { self.automaticTab = id }
        }
    }

    func toggle(_ id: String, completion: @escaping (String) -> Void) {
        guard !stopped else { return }
        automaticTab = nil
        engine.requestPictureInPicture(id, automatic: false, completion: completion)
    }

    func resume() { stopped = false }

    func stop() {
        stopped = true
        if let id = pendingTab { engine.closePictureInPicture(id) }
        if let id = automaticTab { engine.closePictureInPicture(id) }
        automaticTab = nil
    }
}
