// SPDX-License-Identifier: MPL-2.0
import AppKit
import AuthenticationServices

private final class Request: BrowserAuthenticationRequest {
    let uuid = UUID()
    let url: URL
    let shouldUseEphemeralSession: Bool
    var replies = [Result<URL,Error>]()

    init(_ origin: URL, _ path: String, ephemeral: Bool = false) {
        url = origin.appendingPathComponent(path)
        shouldUseEphemeralSession = ephemeral
    }

    func matchesCallback(_ url: URL) -> Bool {
        if #available(macOS 14.4, *) {
            return ASWebAuthenticationSession.Callback.customScheme("arctest").matchesURL(url) ||
                ASWebAuthenticationSession.Callback.https(host:"auth-callback.invalid",path:"/finished").matchesURL(url)
        }
        return url.scheme == "arctest"
    }
    func complete(withCallbackURL url: URL) { replies.append(.success(url)) }
    func cancelWithError(_ error: Error) { replies.append(.failure(error)) }

    var cancelled: Bool {
        guard replies.count == 1, case .failure(let error) = replies[0] else { return false }
        return (error as NSError).domain == ASWebAuthenticationSessionErrorDomain &&
            (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }
}

// Exercise a provider's link with a user gesture in the isolated CEF target.
// AppKit and Chromium live in different processes. Synthetic NSEvents are not
// reliably forwarded as trusted input by remote Cocoa.
private func clickProviderLink(at url: URL, debugPort: String) async throws {
    let endpoint = URL(string:"http://127.0.0.1:" + debugPort + "/json/list")!
    for _ in 0..<50 {
        let (data, _) = try await URLSession.shared.data(from:endpoint)
        let targets = try JSONSerialization.jsonObject(with:data) as? [[String:Any]]
        if let target = targets?.first(where:{ $0["url"] as? String == url.absoluteString }),
           let address = target["webSocketDebuggerUrl"] as? String, let socketURL = URL(string:address) {
            let socket = URLSession.shared.webSocketTask(with:socketURL)
            socket.resume()
            defer { socket.cancel(with:.normalClosure,reason:nil) }
            let expression = "(() => { const link = document.querySelector('a'); if (link) link.click(); return Boolean(link); })()"
            let message: [String:Any] = ["id":1,"method":"Runtime.evaluate",
                "params":["expression":expression,"userGesture":true,"returnByValue":true]]
            try await socket.send(.string(String(decoding:try JSONSerialization.data(withJSONObject:message),as:UTF8.self)))
            if case .string(let response) = try await socket.receive(),
               let reply = try JSONSerialization.jsonObject(with:Data(response.utf8)) as? [String:Any],
               let wrapper = reply["result"] as? [String:Any], let value = wrapper["result"] as? [String:Any],
               value["value"] as? Bool == true { return }
        }
        try await Task.sleep(nanoseconds:100_000_000)
    }
    fatalError("Provider link not available")
}

@main struct WebAuthenticationHarness {
    static func main() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["BROWSER_NATIVE_TEST_DATA"], path.contains("web-auth-check."),
              let raw = env["BROWSER_WEBAUTH_ORIGIN"], let site = URL(string:raw),
              site.host == "127.0.0.1" else { fatalError("Isolated test profile required") }
        var session = BrowserSession.fresh(language:"fr")
        session.onboardingComplete = true
        let tab = session.createTab(url:raw + "/seed")
        let store = SessionStore(directory:URL(fileURLWithPath:path))
        let cache = store.directory.appendingPathComponent("Chromium")
        try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
        try store.save(session)
        let app = BrowserEngine.createApplication()
        app.setActivationPolicy(.regular)
        let delegate = NativeAppDelegate(store:store,initial:session)
        app.delegate = delegate
        let handler = delegate.webAuthentication
        precondition(ASWebAuthenticationSessionWebBrowserSessionManager.shared.sessionHandler === handler)
        let cold = Request(site,"never",ephemeral:true)
        handler.receive(cold)
        handler.cancelRequest(cold)
        precondition(cold.cancelled)
        let early = Request(site,"finish/cold",ephemeral:true)
        handler.receive(early)
        let firstCase: String
        if #available(macOS 14.4, *) { firstCase = "private-a" } else { firstCase = "private-legacy" }
        let regular = Request(site,"regular")
        let first = Request(site,firstCase,ephemeral:true)
        let second = Request(site,"private-b",ephemeral:true)
        let closed = Request(site,"close",ephemeral:true)
        let cancelled = Request(site,"cancel",ephemeral:true)
        let popup = Request(site,"popup")
        let stopped = Request(site,"quit",ephemeral:true)
        var stage = -1, started = Date()
        var clickedPopup = false
        func advance() { stage += 1; started = Date() }
        func verifyCallback(_ request: Request, _ expected: String) {
            guard request.replies.count == 1, case .success(let url) = request.replies[0], url.absoluteString == expected else {
                fatalError("Unexpected result for \(request.url.lastPathComponent): \(request.replies)")
            }
        }
        let timer = Timer.scheduledTimer(withTimeInterval:0.08,repeats:true) { timer in MainActor.assumeIsolated {
            if Date().timeIntervalSince(started) > 15 {
                fatalError("Timeout at stage \(stage), cancel=\(cancelled.replies), popup=\(popup.replies), clicked=\(clickedPopup), windows=\(app.windows.compactMap { $0 as? AuthenticationWindow }.map { [$0.subtitle, String($0.isVisible)] })")
            }
            switch stage {
            case -1:
                guard !early.replies.isEmpty else { return }
                verifyCallback(early,"arctest://done?case=cold&state=A%2FB#result")
                precondition(ASWebAuthenticationSessionWebBrowserSessionManager.shared.sessionHandler === handler)
                precondition(delegate.controllers.isEmpty)
                _ = delegate.applicationShouldHandleReopen(app,hasVisibleWindows:false)
                advance()
            case 0:
                guard delegate.controller?.windowSession.tabs.first(where:{ $0.id == tab })?.title == "Seeded" else { return }
                handler.receive(regular)
                handler.receive(first)
                handler.receive(second)
                advance()
            case 1:
                guard [regular,first,second].allSatisfy({ !$0.replies.isEmpty }) else { return }
                verifyCallback(regular,"arctest://done?case=regular&state=A%2FB#result")
                if #available(macOS 14.4, *) {
                    verifyCallback(first,"https://auth-callback.invalid/finished?case=private-a#result")
                } else {
                    verifyCallback(first,"arctest://done?case=private-legacy&state=A%2FB#result")
                }
                verifyCallback(second,"arctest://done?case=private-b&state=A%2FB#result")
                handler.receive(closed)
                advance()
            case 2:
                guard let window = app.keyWindow as? AuthenticationWindow, !window.subtitle.isEmpty else { return }
                window.performClose(nil)
                advance()
            case 3:
                guard closed.cancelled else { return }
                handler.receive(cancelled)
                handler.cancelRequest(cancelled)  // While its private context is initializing.
                handler.receive(popup)
                advance()
            case 4:
                if !clickedPopup, cancelled.cancelled,
                   app.windows.contains(where:{ $0 is AuthenticationWindow && $0.isVisible && !$0.subtitle.isEmpty }) {
                    clickedPopup = true
                    Task {
                        do { try await clickProviderLink(at:popup.url, debugPort:env["BROWSER_NATIVE_DEBUG_PORT"]!) }
                        catch { fatalError("Could not activate the test provider link: \(error)") }
                    }
                }
                guard cancelled.cancelled, !popup.replies.isEmpty else { return }
                verifyCallback(popup,"arctest://done?case=popup&state=A%2FB#result")
                precondition(!app.windows.contains(where:{ $0 is AuthenticationWindow && $0.isVisible }))
                precondition(delegate.controller?.selectedWindowTabID == tab)
                precondition(delegate.sharedSession.tabs.allSatisfy { !$0.url.contains("private-") })
                precondition(cold.cancelled && closed.cancelled && cancelled.cancelled)
                handler.receive(stopped)
                advance()
            default:
                guard let window = app.keyWindow as? AuthenticationWindow, !window.subtitle.isEmpty else { return }
                timer.invalidate()
                delegate.requestQuit()
            }
        } }
        guard BrowserEngine.start(cachePath:cache.path) else { fatalError("CEF initialization") }
        withExtendedLifetime((delegate,timer)) { BrowserEngine.runMessageLoop() }
        precondition(stopped.cancelled)
        BrowserEngine.shutdown()
        print("PASS native web authentication")
    }
}
