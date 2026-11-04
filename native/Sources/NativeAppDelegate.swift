import AppKit

final class NativeAppDelegate: NSObject, NSApplicationDelegate {
    var controller: BrowserController?
    private(set) var controllers: [BrowserController] = []
    private var menus: BrowserMenus?
    private var pendingAddresses: [String] = []
    private var baselines: [String:BrowserSession] = [:]
    private var privateProfile: String?
    private var publishTask: DispatchWorkItem?
    let store: SessionStore
    var initial: BrowserSession
    private(set) var sharedSession: BrowserSession
    var booted = false
    var quitting = false
    var observers: [NSObjectProtocol] = []
    init(store: SessionStore, initial: BrowserSession) {
        self.store = store; self.initial = initial; sharedSession = initial
        super.init()
        let center = NotificationCenter.default
        for name in [BrowserCommands.changed, Notification.Name("BrowserLanguageChanged")] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in self?.buildMenu() })
        }
        observers.append(center.addObserver(forName: Notification.Name("BrowserEngineReady"), object:nil, queue:.main) { [weak self] _ in DispatchQueue.main.async { self?.boot() } })
        observers.append(center.addObserver(forName: Notification.Name("BrowserNativeRequestQuit"), object:nil, queue:.main) { [weak self] _ in self?.requestQuit() })
        observers.append(center.addObserver(forName: Notification.Name("BrowserEngineReadyToQuit"), object:nil, queue:.main) { _ in BrowserEngine.stopMessageLoop() })
        observers.append(center.addObserver(forName: Notification.Name("BrowserEngineQuitCancelled"), object:nil, queue:.main) { [weak self] _ in self?.quitting = false; self?.controller?.show() })
    }
    func boot() {
        guard !booted else { return }; booted = true
        if ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"] == nil {
            Task { @MainActor [weak self] in
                ArcSync.shared.configure(current:{ [weak self] in self?.sharedSession },apply:{ [weak self] state in
                    guard let self else { throw SessionStoreError.invalidState }
                    try self.applyCloudSession(state)
                })
            }
        }
        let records = WindowPersistence(directory:store.directory).load()
        for record in records {
            guard let state = record.restoredSession(shared:sharedSession) else { continue }
            let window = makeController(state:state,kind:record.kind,privateWindow:false)
            if record.frame.count == 4, record.frame.allSatisfy(\.isFinite), record.frame[2] >= 760, record.frame[3] >= 540 {
                let rect = NSRect(x:record.frame[0],y:record.frame[1],width:min(8000,record.frame[2]),height:min(8000,record.frame[3]))
                if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) { window.window.setFrame(rect,display:false) }
            }
            window.show()
        }
        if controllers.isEmpty { _ = openWindow(.normal) }
        pendingAddresses.forEach { controller?.openExternalAddress($0) }; pendingAddresses.removeAll()
        controller?.show(); NSApp.activate(ignoringOtherApps:true); buildMenu(); startNativeHostDiagnostics()
        BrowserUpdates.shared.start()
        BrowserUpdates.shared.presentNewsAfterUpgrade { [weak self] in self?.sharedSession.onboardingComplete == true && self?.quitting == false }
        if ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"] != nil,
           let raw = ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_AUTOCLOSE"], let seconds = Double(raw), seconds >= 10 {
            DispatchQueue.main.asyncAfter(deadline:.now()+seconds) { [weak self] in self?.requestQuit() }
        }
    }
    private func makeController(state:BrowserSession,kind:BrowserWindowKind,privateWindow:Bool) -> BrowserController {
        let id = UUID().uuidString
        let localStore = SessionStore(directory:store.directory); localStore.memoryOnly = true
        let next = BrowserController(session:state,store:localStore,windowID:id,kind:kind,privateWindow:privateWindow)
        baselines[id] = state; controllers.append(next)
        localStore.saveHandler = { [weak self] value in try self?.save(value,from:id) }
        next.becameKey = { [weak self] value in self?.controller = value; self?.buildMenu() }
        next.windowClosed = { [weak self] value in self?.closed(value) }
        next.newWindowRequested = { [weak self,weak next] kind in _ = self?.openWindow(kind,from:next) }
        next.privateAddressRequested = { [weak self,weak next] address in
            guard let self else { return }
            self.openWindow(.privateWindow,from:next).openExternalAddress(address)
        }
        next.windowAddressRequested = { [weak self,weak next] address in
            guard let self else { return }
            self.openWindow(.blank,from:next).openExternalAddress(address)
        }
        next.promoteWindowRequested = { [weak self,weak next] in
            guard let self, let next else { return }
            let target = self.openWindow(next.isPrivateWindow ? .privateWindow : .normal,from:next)
            if let url = next.selectedWindowURL, url != "about:blank" { target.openExternalAddress(url) }
            next.requestWindowClose()
        }
        controller = next
        return next
    }
    @discardableResult func openWindow(_ kind:BrowserWindowKind,from source:BrowserController? = nil) -> BrowserController {
        publishTask?.cancel(); publish()
        let source = source ?? controller
        let ephemeral = kind == .privateWindow || ((kind == .compact || kind == .blank) && source?.isPrivateWindow == true)
        if ephemeral, privateProfile == nil {
            let id = "private-"+UUID().uuidString
            precondition(BrowserEngine().registerPrivateProfile(id),"Cannot register an isolated private context")
            privateProfile = id
        }
        let seed = source?.windowSession ?? sharedSession
        var state = kind == .normal ? sharedSession : seed.standaloneWindow(privateProfile:ephemeral ? privateProfile : nil,compact:kind == .compact)
        // Every window opens a usable command surface, even when there are no tabs.
        if state.tabs.isEmpty { _ = state.createTab(); if kind == .normal { sharedSession = state } }
        let result = makeController(state:state,kind:kind,privateWindow:ephemeral)
        if let source {
            let offset = source.window.frame.offsetBy(dx:28,dy:-28)
            let size = result.window.frame.size
            if let screen = source.window.screen {
                let area = screen.visibleFrame
                result.window.setFrameOrigin(NSPoint(x:min(max(area.minX,offset.minX),area.maxX-size.width),y:min(max(area.minY,offset.minY),area.maxY-size.height)))
            }
        }
        result.show(); buildMenu(); persistWindows()
        if kind != .normal || result.selectedWindowURL == "about:blank" { result.openLocationAction(nil) }
        return result
    }
    private func save(_ state:BrowserSession,from id:String) throws {
        guard let source = controllers.first(where: { $0.windowID == id }), let base = baselines[id] else { return }
        guard base != state else { return }
        if source.windowKind == .normal && !source.isPrivateWindow {
            let merged = try BrowserSession.merging(base:base,incoming:state,latest:sharedSession)
            try store.save(merged); sharedSession = merged
        } else {
            // Explicit global preference edits may persist; private URLs, tabs,
            // cookies, archives and site preferences never enter the regular state.
            var updated = sharedSession
            if state.commandShortcuts != base.commandShortcuts { updated.commandShortcuts = state.commandShortcuts }
            if state.splitShortcuts != base.splitShortcuts { updated.splitShortcuts = state.splitShortcuts }
            if state.language != base.language { updated.language = state.language }
            if state.themeAppearance != base.themeAppearance { updated.themeAppearance = state.themeAppearance }
            if state.savePasswords != base.savePasswords { updated.savePasswords = state.savePasswords }
            if state.automaticSignIn != base.automaticSignIn { updated.automaticSignIn = state.automaticSignIn }
            if state.formSuggestions != base.formSuggestions { updated.formSuggestions = state.formSuggestions }
            if updated != sharedSession { try store.save(updated); sharedSession = updated }
        }
        baselines[id] = state
        Task { @MainActor in ArcSync.shared.localChanged() }
        publishTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.publish() }; publishTask = task
        DispatchQueue.main.async(execute:task)
    }
    private func publish() {
        guard !quitting else { return }
        let before = sharedSession
        // Include unsaved in-flight changes (for example a title callback) before
        // publishing the shared model. Selection stays local to each window.
        for item in controllers where item.windowKind == .normal && !item.isPrivateWindow && !item.isClosingWindow {
            if let base = baselines[item.windowID], base != item.windowSession, let merged = try? BrowserSession.merging(base:base,incoming:item.windowSession,latest:sharedSession) { sharedSession = merged }
        }
        for item in controllers where item.windowKind == .normal && !item.isPrivateWindow && !item.isClosingWindow {
            item.receiveSharedSession(sharedSession); baselines[item.windowID] = item.windowSession
        }
        if sharedSession != before { do { try store.save(sharedSession); Task { @MainActor in ArcSync.shared.localChanged() } } catch { NSLog("Browser shared session save failed: %@",error.localizedDescription) } }
        persistWindows()
    }
    private func applyCloudSession(_ state:BrowserSession) throws {
        guard !quitting, state.validated() else { throw SessionStoreError.invalidState }
        let previous = sharedSession
        // Session + encrypted sync baseline are one atomic write with a backup.
        try store.save(state); sharedSession = state
        for item in controllers where item.windowKind == .normal && !item.isPrivateWindow && !item.isClosingWindow {
            item.receiveSharedSession(state); baselines[item.windowID] = item.windowSession
        }
        let defaults = UserDefaults.standard
        defaults.set(state.language,forKey:"BrowserLanguage")
        defaults.set(state.savePasswords ?? true,forKey:"BrowserSavePasswords")
        defaults.set(state.automaticSignIn ?? true,forKey:"BrowserAutomaticSignIn")
        defaults.set(state.formSuggestions ?? true,forKey:"BrowserFormSuggestions")
        if previous.language != state.language { BrowserEngine().updateLanguages() }
        if previous.savePasswords != state.savePasswords || previous.automaticSignIn != state.automaticSignIn || previous.formSuggestions != state.formSuggestions {
            _ = BrowserEngine().updateCredentialPreferences()
        }
        buildMenu(); persistWindows()
    }
    private func closed(_ value:BrowserController) {
        controllers.removeAll { $0 === value }; baselines.removeValue(forKey:value.windowID)
        if controller === value { controller = controllers.first(where: { $0.window.isKeyWindow }) ?? controllers.last }
        if !controllers.contains(where: \.isPrivateWindow), let profile = privateProfile { BrowserEngine().releasePrivateProfile(profile); privateProfile = nil }
        buildMenu(); persistWindows()
    }
    private func persistWindows() {
        guard booted else { return }
        do { try WindowPersistence(directory:store.directory).save(controllers) }
        catch { NSLog("Browser window state save failed: %@",error.localizedDescription) }
    }
    func requestQuit() {
        guard !quitting else { return }
        publishTask?.cancel(); publish()
        for item in controllers { if !item.prepareToQuit() { controllers.forEach { $0.resumeAfterCancelledQuit() }; return } }
        persistWindows(); quitting = true; BrowserEngine.requestQuit()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationDockMenu(_ sender:NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let language = controller?.menuLanguage ?? sharedSession.language
        let actions:[(String,Selector)] = [
            (language == "en" ? "New Window" : "Nouvelle fenêtre",#selector(newDockWindow(_:))),
            (language == "en" ? "New Private Window" : "Nouvelle fenêtre privée",#selector(newDockPrivateWindow(_:)))
        ]
        for (title,action) in actions {
            let item = NSMenuItem(title:title,action:action,keyEquivalent:"")
            item.target = self
            item.isEnabled = booted && sharedSession.onboardingComplete == true && !quitting
            menu.addItem(item)
        }
        return menu
    }
    @objc private func newDockWindow(_ sender:Any?) {
        guard booted, sharedSession.onboardingComplete == true, !quitting else { return }
        openWindow(.normal)
        NSApp.activate(ignoringOtherApps:true)
    }
    @objc private func newDockPrivateWindow(_ sender:Any?) {
        guard booted, sharedSession.onboardingComplete == true, !quitting else { return }
        openWindow(.privateWindow)
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationSupportsSecureRestorableState(_ app:NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool {
        if let controller { controller.show() } else { _ = openWindow(.normal) }; return true
    }
    @objc func about(_ sender:Any?) {
        NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"Arc Reborn",.applicationVersion:BrowserUpdates.version,.version:"Chromium \(BrowserEngine.chromiumVersion())",.credits:NSAttributedString(string:"Swift · AppKit · Chromium Embedded Framework\nLicences : dossier Resources de l’application.")])
    }
    func buildMenu() { menus = BrowserMenus(controller:controller,appDelegate:self); menus?.build() }
    func application(_ application:NSApplication,open urls:[URL]) {
        let addresses = urls.filter { ["https","http"].contains($0.scheme?.lowercased() ?? "") && isAllowedBrowserURL($0.absoluteString) }.map(\.absoluteString)
        if !booted { pendingAddresses.append(contentsOf:addresses); return }
        // External links always use a regular window, never an incidental private one.
        let target = controllers.first(where: { $0 === controller && !$0.isPrivateWindow }) ?? controllers.first(where: { !$0.isPrivateWindow && $0.windowKind == .normal }) ?? openWindow(.normal)
        addresses.forEach { target.openExternalAddress($0) }; target.show()
    }
}
