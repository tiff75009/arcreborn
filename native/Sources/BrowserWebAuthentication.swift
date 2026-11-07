// SPDX-License-Identifier: MPL-2.0
import AppKit
import AuthenticationServices

protocol BrowserAuthenticationRequest: AnyObject {
    var uuid: UUID { get }
    var url: URL { get }
    var shouldUseEphemeralSession: Bool { get }
    func matchesCallback(_ url: URL) -> Bool
    func complete(withCallbackURL url: URL)
    func cancelWithError(_ error: Error)
}

extension ASWebAuthenticationSessionRequest: BrowserAuthenticationRequest {
    func matchesCallback(_ url: URL) -> Bool {
        if #available(macOS 14.4, *), let callback {
            return callback.matchesURL(url)
        }
        guard let expected = callbackURLScheme, !expected.isEmpty else { return false }
        return url.scheme?.caseInsensitiveCompare(expected) == .orderedSame
    }
}

final class BrowserWebAuthentication: NSObject, ASWebAuthenticationSessionWebBrowserSessionHandling {
    private var sessions: [UUID: AuthenticationSession] = [:]
    private var regularProfile: (() -> String?)?

    var launchedForAuthentication: Bool {
        !sessions.isEmpty || ASWebAuthenticationSessionWebBrowserSessionManager.shared.wasLaunchedByAuthenticationServices
    }

    func register() {
        ASWebAuthenticationSessionWebBrowserSessionManager.shared.sessionHandler = self
    }

    func begin(_ request: ASWebAuthenticationSessionRequest) {
        DispatchQueue.main.async { self.receive(request) }
    }

    func cancel(_ request: ASWebAuthenticationSessionRequest) {
        DispatchQueue.main.async { self.cancelRequest(request) }
    }

    func receive(_ request: BrowserAuthenticationRequest) {
        let id = request.uuid
        guard sessions[id] == nil else { return }
        guard browserWebURL(request.url.absoluteString) != nil else {
            request.cancelWithError(URLError(.unsupportedURL))
            return
        }
        let session = AuthenticationSession(request:request) { [weak self] in
            self?.sessions.removeValue(forKey:id)
        }
        sessions[id] = session
        if let regularProfile { session.start(regularProfile:regularProfile()) }
    }

    func engineReady(regularProfile: @escaping () -> String?) {
        self.regularProfile = regularProfile
        for session in Array(sessions.values) { session.start(regularProfile:regularProfile()) }
    }

    func cancelRequest(_ request: BrowserAuthenticationRequest) {
        sessions[request.uuid]?.cancel(replyTo:request)
    }

    func cancelAll() {
        for session in Array(sessions.values) { session.cancel() }
    }
}

final class AuthenticationWindow: NSWindow {}

private final class AuthenticationSession: NSObject, BrowserEngineDelegate, NSWindowDelegate {
    private var request: BrowserAuthenticationRequest
    private let retired: () -> Void
    private let engine = BrowserEngine()
    private let rootID = UUID().uuidString
    private var privateProfile: String?
    private var windows: [String: AuthenticationWindow] = [:]
    private var result: Result<URL, Error>?

    init(request: BrowserAuthenticationRequest, retired: @escaping () -> Void) {
        self.request = request
        self.retired = retired
        super.init()
        engine.delegate = self
    }

    func start(regularProfile: String?) {
        guard result == nil, windows.isEmpty else { return }
        guard let regularProfile else { cancel(); return }
        if request.shouldUseEphemeralSession {
            let fresh = "auth-" + UUID().uuidString
            guard engine.registerPrivateProfile(fresh) else { finish(.failure(URLError(.resourceUnavailable))); return }
            privateProfile = fresh
        }
        let window = makeWindow(id:rootID)
        guard engine.createTab(rootID, profile:privateProfile ?? regularProfile, url:request.url.absoluteString,
                               container:window.contentView!) else {
            removeWindow(rootID)
            finish(.failure(URLError(.cannotLoadFromNetwork)))
            return
        }
        show(window)
    }

    private func makeWindow(id: String) -> AuthenticationWindow {
        let size = NSSize(width:640,height:660)
        let window = AuthenticationWindow(contentRect:NSRect(origin:.zero,size:size),
                                          styleMask:[.titled,.closable,.resizable],
                                          backing:.buffered,defer:false)
        let english = UserDefaults.standard.string(forKey:"BrowserLanguage") == "en"
        if request.shouldUseEphemeralSession {
            window.title = english ? "Private Sign In" : "Connexion privée"
        } else {
            window.title = english ? "Sign In" : "Connexion"
        }
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width:360,height:320)
        window.delegate = self
        window.center()
        let button = NSButton(title:english ? "Cancel" : "Annuler", target:window, action:#selector(NSWindow.performClose(_:)))
        button.keyEquivalent = "\u{1b}"
        button.sizeToFit()
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.view = button
        window.addTitlebarAccessoryViewController(accessory)
        windows[id] = window
        return window
    }

    private func show(_ window: AuthenticationWindow) {
        guard result == nil, let id = window.identifier?.rawValue else { return }
        window.makeKeyAndOrderFront(nil)
        engine.setTab(id,visible:true)
        engine.focusTab(id)
        NSApp.activate(ignoringOtherApps:true)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? AuthenticationWindow,
              let id = window.identifier?.rawValue, let view = window.contentView else { return }
        engine.resizeTab(id,container:view)
    }

    func windowWillClose(_ notification: Notification) { cancel() }

    func cancel(replyTo cancellation: BrowserAuthenticationRequest? = nil) {
        guard result == nil else { return }
        if let cancellation { request = cancellation }
        finish(.failure(ASWebAuthenticationSessionError(.canceledLogin)))
    }

    private func finish(_ outcome: Result<URL, Error>) {
        guard result == nil else { return }
        result = outcome
        if windows.isEmpty { deliver(); return }
        // Decide synchronously, then unwind the CEF navigation/AppKit close
        // callback before destroying any WebContents. Late redirects lose.
        DispatchQueue.main.async {
            for (id, window) in Array(self.windows) {
                window.orderOut(nil)
                self.engine.discardTab(id)
            }
        }
    }

    private func deliver() {
        guard let result else { return }
        if let privateProfile { engine.releasePrivateProfile(privateProfile) }
        retired()
        switch result {
        case .success(let callback): request.complete(withCallbackURL:callback)
        case .failure(let error): request.cancelWithError(error)
        }
    }

    private func removeWindow(_ id: String) {
        guard let window = windows.removeValue(forKey:id) else { return }
        window.delegate = nil
        window.close()
    }

    func browserShouldCancelAuthenticationNavigation(_ id: String, url address: String) -> Bool {
        guard result == nil, windows[id] != nil, let url = URL(string:address) else { return true }
        if request.matchesCallback(url) {
            finish(.success(url))
            return true
        }
        return address != "about:blank" && browserWebURL(address) == nil
    }

    func browserURLChanged(_ id: String, url address: String) {
        // Same-document navigations can change an HTTPS callback's path
        // without running CEF's before-browse hook.
        guard !browserShouldCancelAuthenticationNavigation(id,url:address) else { return }
        var origin = URLComponents(string:address)
        origin?.path = ""
        origin?.query = nil
        origin?.fragment = nil
        windows[id]?.subtitle = origin?.host == nil ? "" : origin?.string ?? ""
    }

    func browserClosed(_ id: String) {
        guard windows[id] != nil else { return }
        removeWindow(id)
        if result != nil {
            if windows.isEmpty { deliver() }
        } else if id == rootID {
            cancel()
        }
    }

    func browserFailed(_ id: String, code: String, host: String?) {
        if id == rootID { finish(.failure(URLError(.cannotLoadFromNetwork))) }
    }

    // Providers can use a real popup (including window.opener and POST).
    // Keep every such page attached to its own originating system request.
    private func reservePage(from source: String) -> [String: Any]? {
        guard result == nil, windows[source] != nil else { return nil }
        let id = UUID().uuidString
        let window = makeWindow(id:id)
        show(window)
        return ["id":id, "view":window.contentView!]
    }

    func browserPreparePopup(_ url: String, sourceTab: String, active: Bool) -> [String: Any]? {
        reservePage(from:sourceTab)
    }

    func browserPrepareExtensionTab(_ source: String, active: Bool, pinned: Bool, index: Int, aboveSource: Bool) -> [String: Any]? {
        reservePage(from:source)
    }

    func browserExtensionTabCreated(_ id: String, success: Bool) {
        if !success { browserClosed(id) }
    }

    func browserRequestedNewTab(_ url: String, sourceTab: String) {}
    func browserTitleChanged(_ id: String, title: String) {}
    func browserLoadingChanged(_ id: String, loading: Bool, back: Bool, forward: Bool) {}
}
