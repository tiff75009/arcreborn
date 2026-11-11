import AppKit

final class NativeAppDelegate: NSObject, NSApplicationDelegate {
    var controller: BrowserController?
    private(set) var controllers: [BrowserController] = []
    private var menus: BrowserMenus?
    let handoff = BrowserHandoff()
    let webAuthentication = BrowserWebAuthentication()
    private var pendingDocuments = BrowserDocuments.Batch()
    private var deferredWindowRestore = false
    private var baselines: [String:BrowserSession] = [:]
    private var privateOrigins: [String:String] = [:] // ephemeral CEF context ID → originating regular profile
    private var publishTask: DispatchWorkItem?
    private var archiveTimer: Timer?
    private var favoriteMigrationAliases: [String:String] = [:]
    let store: SessionStore
    var initial: BrowserSession
    private(set) var sharedSession: BrowserSession
    var booted = false
    var quitting = false
    private var cancelledOnboardingRelaunch: (() -> Void)?
    var shouldRelaunchAfterOnboarding: Bool { cancelledOnboardingRelaunch != nil }
    var observers: [NSObjectProtocol] = []
    init(store: SessionStore, initial: BrowserSession) {
        self.store = store; self.initial = initial; sharedSession = initial
        favoriteMigrationAliases = sharedSession.normalizeFavoriteTabs()
        self.initial = sharedSession
        super.init()
        webAuthentication.register()
        let center = NotificationCenter.default
        for name in [BrowserCommands.changed, Notification.Name("BrowserLanguageChanged")] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in self?.buildMenu() })
        }
        observers.append(center.addObserver(forName: Notification.Name("BrowserEngineReady"), object:nil, queue:.main) { [weak self] _ in DispatchQueue.main.async { self?.boot() } })
        observers.append(center.addObserver(forName: Notification.Name("BrowserNativeRequestQuit"), object:nil, queue:.main) { [weak self] _ in self?.requestQuit() })
        observers.append(center.addObserver(forName: Notification.Name("BrowserEngineReadyToQuit"), object:nil, queue:.main) { _ in BrowserEngine.stopMessageLoop() })
        observers.append(center.addObserver(forName: Notification.Name("BrowserEngineQuitCancelled"), object:nil, queue:.main) { [weak self] _ in
            guard let self else { return }
            self.quitting = false
            let resume = self.cancelledOnboardingRelaunch
            self.cancelledOnboardingRelaunch = nil
            DispatchQueue.main.async { resume?(); self.controller?.show() }
        })
    }
    func boot() {
        guard !booted else { return }; booted = true
        var pendingHistoryErrors: [String] = []
        for profile in sharedSession.profiles {
            guard let directory = BrowserEngine.historyImportDirectory(for:profile.id, initialize:false) else { continue }
            do { try BrowserHistoryImport.applyPending(in:directory) }
            catch { pendingHistoryErrors.append(profile.name) }
        }
        if !pendingHistoryErrors.isEmpty {
            DispatchQueue.main.async {
                let english = self.sharedSession.language == "en"
                let alert = NSAlert()
                alert.messageText = english ? "History import pending" : "Import de l’historique en attente"
                let names = pendingHistoryErrors.joined(separator:", ")
                alert.informativeText = english ? "The history for \(names) could not be updated. The saved visits will be retried the next time you open Arc Reborn." : "L’historique de \(names) n’a pas pu être mis à jour. Les visites conservées seront importées lors d’une prochaine ouverture d’Arc Reborn."
                alert.runModal()
            }
        }
        if ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"] == nil {
            observers.append(NotificationCenter.default.addObserver(forName:Notification.Name("BrowserExtensionPreferencesChanged"),object:nil,queue:.main) { [weak self] note in
                guard let id = note.object as? String,
                      self?.sharedSession.profiles.contains(where:{ $0.id == id }) == true else { return }
                Task { @MainActor in ArcSync.shared.localChanged() }
            })
            Task { @MainActor [weak self] in
                ArcSync.shared.configure(current:{ [weak self] in self?.sharedSession },apply:{ [weak self] state in
                    guard let self else { throw SessionStoreError.invalidState }
                    try self.applyCloudSession(state)
                })
            }
        }
        deferredWindowRestore = webAuthentication.launchedForAuthentication && pendingDocuments.isEmpty
        if !deferredWindowRestore {
            restoreWindows()
            deliverBrowserDocuments(pendingDocuments)
            pendingDocuments = .init()
            controller?.show(); NSApp.activate(ignoringOtherApps:true)
        }
        buildMenu(); startNativeHostDiagnostics()
        let profilePreview = CommandLine.arguments.contains("--preview-profiles")
        let interfacePreview = CommandLine.arguments.contains("--preview-interface")
        if (interfacePreview || profilePreview || CommandLine.arguments.contains("--preview-account")), ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"] != nil {
            DispatchQueue.main.async { [weak self] in self?.controller?.showPreferencesPreview(profiles:profilePreview,interface:interfacePreview) }
        }
        let timer = Timer(timeInterval:60,repeats:true) { [weak self] _ in self?.sweepArchives() }
        timer.tolerance = 10; RunLoop.main.add(timer,forMode:.common); archiveTimer = timer
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(sweepArchives),name:NSWorkspace.didWakeNotification,object:nil)
        DispatchQueue.main.async { [weak self] in self?.sweepArchives() }
        BrowserUpdates.shared.sidebarAvailable = { [weak self] in self?.controllers.contains(where: { $0.canPresentSidebarUpdate }) == true }
        observers.append(NotificationCenter.default.addObserver(forName:SidebarUpdateSession.focus,object:nil,queue:.main) { [weak self] _ in
            guard let self else { return }
            let target = self.controller.flatMap { $0.canPresentSidebarUpdate ? $0 : nil } ?? self.controllers.first(where: { $0.canPresentSidebarUpdate })
            target?.focusSidebarUpdate()
        })
        BrowserUpdates.shared.start()
        BrowserUpdates.shared.presentNewsAfterUpgrade(existingInstallation: initial.onboardingComplete) { [weak self] in self?.sharedSession.onboardingComplete == true && self?.quitting == false && self?.deferredWindowRestore == false }
        webAuthentication.engineReady { [weak self] in
            guard let self, !self.quitting else { return nil }
            let state = self.controller?.windowSession ?? self.sharedSession
            guard let id = state.profile(forSpace:state.activeSpaceID)?.id else { return nil }
            return self.privateOrigins[id] ?? id
        }
        if ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"] != nil,
           let raw = ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_AUTOCLOSE"], let seconds = Double(raw), seconds >= 10 {
            DispatchQueue.main.asyncAfter(deadline:.now()+seconds) { [weak self] in self?.requestQuit() }
        }
    }
    private func restoreWindows() {
        deferredWindowRestore = false
        let records = WindowPersistence(directory:store.directory).load()
        for record in records {
            guard let state = record.restoredSession(shared:sharedSession,favoriteAliases:favoriteMigrationAliases) else { continue }
            let window = makeController(state:state,kind:record.kind,privateWindow:false)
            if record.frame.count == 4, record.frame.allSatisfy(\.isFinite), record.frame[2] >= 760, record.frame[3] >= 540 {
                let rect = NSRect(x:record.frame[0],y:record.frame[1],width:min(8000,record.frame[2]),height:min(8000,record.frame[3]))
                if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) { window.window.setFrame(rect,display:false) }
            }
            window.show()
        }
        if controllers.isEmpty { _ = openWindow(.normal) }
    }
    private func makeController(state:BrowserSession,kind:BrowserWindowKind,privateWindow:Bool) -> BrowserController {
        let id = UUID().uuidString
        let localStore = SessionStore(directory:store.directory); localStore.memoryOnly = true
        let next = BrowserController(session:state,store:localStore,windowID:id,kind:kind,privateWindow:privateWindow)
        baselines[id] = state; controllers.append(next)
        localStore.saveHandler = { [weak self] value in try self?.save(value,from:id) }
        next.becameKey = { [weak self] value in
            self?.controller = value; self?.buildMenu(); self?.refreshHandoff()
            OnboardingRelaunch.windowDidOpen(value.window)
        }
        next.handoffPageChanged = { [weak self] value in
            guard let self, self.controller === value else { return }
            self.refreshHandoff()
        }
        next.windowClosed = { [weak self] value in self?.closed(value) }
        if kind == .normal && !privateWindow {
            // A shared sidebar tab can have a renderer only in another window.
            next.sharedTabHistory = { [weak self, weak next] tab, profile in
                guard let self else { return nil }
                for peer in self.controllers where peer !== next && peer.windowKind == .normal && !peer.isPrivateWindow {
                    if let data = peer.liveTabHistory(tab,profile:profile) { return data }
                }
                return nil
            }
        }
        next.newWindowRequested = { [weak self,weak next] kind in _ = self?.openWindow(kind,from:next) }
        next.relaunchAfterHistoryImport = { [weak self] cancelled in self?.requestQuit(onRelaunchCancelled:cancelled) }
        next.privateAddressRequested = { [weak self,weak next] address in
            guard let self else { return }
            self.openWindow(.privateWindow,from:next,initialAddress:address)
        }
        next.windowAddressRequested = { [weak self,weak next] address in
            guard let self else { return }
            self.openWindow(.blank,from:next,initialAddress:address)
        }
        next.promoteWindowRequested = { [weak self,weak next] in
            guard let self, let next else { return }
            let url = next.selectedWindowURL.flatMap { $0 == "about:blank" ? nil : $0 }
            if next.isPrivateWindow { self.openWindow(.privateWindow,from:next,initialAddress:url) }
            else {
                let target = self.openWindow(.normal,from:next)
                if let url { target.openDocumentTabs([url]) }
            }
            next.requestWindowClose()
        }
        controller = next
        return next
    }
    @discardableResult func openWindow(_ kind:BrowserWindowKind,from source:BrowserController? = nil,initialAddress:String? = nil) -> BrowserController {
        if deferredWindowRestore {
            restoreWindows()
            if kind == .normal, let restored = controllers.last(where:{ $0.windowKind == .normal }) {
                restored.show()
                return restored
            }
        }
        publishTask?.cancel(); publish()
        let source = source ?? controller
        let ephemeral = kind == .privateWindow || ((kind == .compact || kind == .blank) && source?.isPrivateWindow == true)
        let seed = source?.windowSession ?? sharedSession
        let origin = seed.profile(forSpace:seed.activeSpaceID)?.id ?? sharedSession.profiles[0].id
        var privateID: String?
        if ephemeral {
            let regular = privateOrigins[origin] ?? origin
            if let existing = privateOrigins.first(where:{ $0.value == regular })?.key { privateID = existing }
            else {
                let id = "private-"+UUID().uuidString
                precondition(BrowserEngine().registerPrivateProfile(id),"Cannot register an isolated private context")
                privateOrigins[id] = regular; privateID = id
            }
        }
        var state = kind == .normal ? sharedSession : seed.standaloneWindow(privateProfile:privateID,compact:kind == .compact,initialAddress:initialAddress)
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
        if result.selectedWindowURL == "about:blank" { result.openLocationAction(nil) }
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
            if state.interfaceStyle != base.interfaceStyle { updated.interfaceStyle = state.interfaceStyle }
            if state.tabPreviewsEnabled != base.tabPreviewsEnabled { updated.tabPreviewsEnabled = state.tabPreviewsEnabled }
            if state.themeAppearance != base.themeAppearance { updated.themeAppearance = state.themeAppearance }
            if state.passwordManagerID != base.passwordManagerID { updated.passwordManagerID = state.passwordManagerID }
            if state.savePasswords != base.savePasswords { updated.savePasswords = state.savePasswords }
            if state.automaticSignIn != base.automaticSignIn { updated.automaticSignIn = state.automaticSignIn }
            if state.formSuggestions != base.formSuggestions { updated.formSuggestions = state.formSuggestions }
            if !source.isPrivateWindow {
                for profile in state.profiles {
                    guard let previous = base.profiles.first(where:{ $0.id == profile.id }),
                          let i = updated.profiles.firstIndex(where:{ $0.id == profile.id }) else { continue }
                    if previous.searchEngineID != profile.searchEngineID { updated.profiles[i].searchEngineID = profile.searchEngineID }
                    if previous.newTabAddress != profile.newTabAddress { updated.profiles[i].newTabAddress = profile.newTabAddress }
                    if previous.autoArchiveEnabledSince != profile.autoArchiveEnabledSince { updated.profiles[i].autoArchiveEnabledSince = profile.autoArchiveEnabledSince }
                    if previous.archiveAfterHours != profile.archiveAfterHours { updated.profiles[i].archiveAfterHours = profile.archiveAfterHours }
                }
            }
            if updated != sharedSession { try store.save(updated); sharedSession = updated }
        }
        baselines[id] = state
        Task { @MainActor in ArcSync.shared.localChanged() }
        publishTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.publish() }; publishTask = task
        DispatchQueue.main.async(execute:task)
    }
    // Chromium reports a new URL before the window's debounced save. Apply
    // those edits against each window's own baseline before distributing a
    // snapshot, or receiveSharedSession can navigate the renderer backwards.
    private func mergingPendingWindowEdits(into snapshot:BrowserSession) throws -> BrowserSession {
        var merged = snapshot
        for item in controllers where item.windowKind == .normal && !item.isPrivateWindow && !item.isClosingWindow {
            let local = item.windowSession
            guard let base = baselines[item.windowID], local != base else { continue }
            merged = try BrowserSession.merging(base:base,incoming:local,latest:merged)
        }
        return merged
    }
    private func publish() {
        guard !quitting else { return }
        let before = sharedSession
        do { sharedSession = try mergingPendingWindowEdits(into:sharedSession) }
        catch { NSLog("Browser window edits could not be merged: %@",error.localizedDescription); return }
        for item in controllers where item.windowKind == .normal && !item.isPrivateWindow && !item.isClosingWindow {
            item.receiveSharedSession(sharedSession); baselines[item.windowID] = item.windowSession
        }
        publishStandaloneNavigation()
        if sharedSession != before { do { try store.save(sharedSession); Task { @MainActor in ArcSync.shared.localChanged() } } catch { NSLog("Browser shared session save failed: %@",error.localizedDescription) } }
        persistWindows()
    }
    private func publishStandaloneNavigation() {
        for item in controllers where (item.windowKind != .normal || item.isPrivateWindow) && !item.isClosingWindow {
            item.receiveInterfaceStyle(sharedSession.interfaceStyle)
            item.receiveTabPreviews(sharedSession.tabPreviewsEnabled)
            baselines[item.windowID]?.tabPreviewsEnabled = sharedSession.tabPreviewsEnabled
            baselines[item.windowID]?.interfaceStyle = sharedSession.interfaceStyle
            for local in item.windowSession.profiles {
                let regular = privateOrigins[local.id] ?? local.id
                guard let source = sharedSession.profiles.first(where:{ $0.id == regular }),
                      let i = baselines[item.windowID]?.profiles.firstIndex(where:{ $0.id == local.id }) else { continue }
                item.receiveNavigationPreferences(source,as:local.id)
                baselines[item.windowID]?.profiles[i].searchEngineID = source.searchEngineID
                baselines[item.windowID]?.profiles[i].newTabAddress = source.newTabAddress
                baselines[item.windowID]?.profiles[i].autoArchiveEnabledSince = source.autoArchiveEnabledSince
                baselines[item.windowID]?.profiles[i].archiveAfterHours = source.archiveAfterHours
            }
        }
    }
    func applyCloudSession(_ snapshot:BrowserSession) throws {
        guard !quitting, snapshot.validated() else { throw SessionStoreError.invalidState }
        let state = try mergingPendingWindowEdits(into:snapshot)
        let previous = sharedSession
        // Session + encrypted sync baseline are one atomic write with a backup.
        try store.save(state); sharedSession = state
        for item in controllers where item.windowKind == .normal && !item.isPrivateWindow && !item.isClosingWindow {
            item.receiveSharedSession(state); baselines[item.windowID] = item.windowSession
        }
        publishStandaloneNavigation()
        let defaults = UserDefaults.standard
        defaults.set(state.language,forKey:"BrowserLanguage")
        defaults.set(state.passwordManagerID ?? "native",forKey:"BrowserPasswordManager")
        defaults.set(state.savePasswords ?? true,forKey:"BrowserSavePasswords")
        defaults.set(state.automaticSignIn ?? true,forKey:"BrowserAutomaticSignIn")
        defaults.set(state.formSuggestions ?? true,forKey:"BrowserFormSuggestions")
        if previous.language != state.language {
            BrowserEngine().updateLanguages()
            NotificationCenter.default.post(name: Notification.Name("BrowserLanguageChanged"), object: state.language)
        }
        if previous.passwordManagerID != state.passwordManagerID || previous.savePasswords != state.savePasswords || previous.automaticSignIn != state.automaticSignIn || previous.formSuggestions != state.formSuggestions {
            _ = BrowserEngine().updateCredentialPreferences()
        }
        buildMenu(); persistWindows()
    }
    private func closed(_ value:BrowserController) {
        controllers.removeAll { $0 === value }; baselines.removeValue(forKey:value.windowID)
        if controller === value { controller = controllers.first(where: { $0.window.isKeyWindow }) ?? controllers.last }
        if value.isPrivateWindow, let id = value.windowSession.profiles.first?.id,
           !controllers.contains(where:{ $0.isPrivateWindow && $0.windowSession.profiles.first?.id == id }) {
            BrowserEngine().releasePrivateProfile(id); privateOrigins.removeValue(forKey:id)
            TabMemorySaver.forgetPrivateProfile(id)
        }
        buildMenu(); persistWindows(); refreshHandoff()
    }
    // A regular sidebar is shared but each window can have its own renderer and
    // selection. Never close an ID based on a single window's view of it.
    @objc private func sweepArchives() {
        guard booted, !quitting else { return }
        for window in controllers { window.sleepIdleTab() }
        let regular = controllers.filter { $0.windowKind == .normal && !$0.isPrivateWindow }
        sweepArchiveGroup(regular)
        for window in controllers where window.windowKind != .normal && window.windowKind != .compact {
            sweepArchiveGroup([window])
        }
    }
    private func archiveCandidates(_ group:[BrowserController],at now:Date) -> [String] {
        guard let first = group.first, group.allSatisfy({ !$0.isClosingWindow && $0.windowSession.onboardingComplete }) else { return [] }
        let protected = group.reduce(into:Set<String>()) { $0.formUnion($1.archiveProtectedIDs) }
        var candidates = first.windowSession.idleArchiveIDs(at:now,protecting:protected)
        for other in group.dropFirst() where !candidates.isEmpty {
            let eligible = Set(other.windowSession.idleArchiveIDs(at:now,protecting:protected))
            candidates.removeAll { !eligible.contains($0) }
        }
        return candidates
    }
    private func sweepArchiveGroup(_ group:[BrowserController]) {
        guard let first = group.first, group.allSatisfy({ !$0.isClosingWindow && $0.windowSession.onboardingComplete }) else { return }
        guard first.windowSession.profiles.contains(where: \.autoArchiveEnabled) else { return }
        let now = Date(); first.seedArchiveDates(at:now)
        let candidates = archiveCandidates(group,at:now)
        var dormant = [String](), live = [(BrowserController,String)]()
        for id in candidates {
            let owners = group.filter { $0.hasArchiveRenderer(id) }
            if owners.isEmpty, dormant.count < 100 { dormant.append(id) }
            else if owners.count == 1 { live.append((owners[0],id)) }
        }
        first.archiveDormantTabs(dormant,at:now)
        for (owner,id) in live {
            owner.probeForAutoArchive(id) { [weak self, weak owner] in
                guard let self, let owner, !self.quitting, self.controllers.contains(where:{ $0 === owner }) else { return false }
                let peers = owner.windowKind == .normal ? self.controllers.filter { $0.windowKind == .normal && !$0.isPrivateWindow } : [owner]
                return peers.filter { $0.hasArchiveRenderer(id) }.count == 1 && self.archiveCandidates(peers,at:Date()).contains(id)
            }
        }
    }
    private func persistWindows() {
        guard booted, !deferredWindowRestore else { return }
        do { try WindowPersistence(directory:store.directory).save(controllers) }
        catch { NSLog("Browser window state save failed: %@",error.localizedDescription) }
    }
    func requestQuit(onRelaunchCancelled: (() -> Void)? = nil) {
        guard !quitting else { return }
        publishTask?.cancel(); publish()
        for item in controllers {
            if !item.prepareToQuit() {
                controllers.forEach { $0.resumeAfterCancelledQuit() }; onRelaunchCancelled?(); return
            }
        }
        cancelledOnboardingRelaunch = onRelaunchCancelled
        persistWindows(); quitting = true; handoff.invalidate(); webAuthentication.cancelAll(); BrowserEngine.requestQuit()
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
    private func refreshHandoff() {
        handoff.update(booted && !quitting ? controller?.handoffPage : nil)
    }
    func application(_ application:NSApplication, willContinueUserActivityWithType type:String) -> Bool {
        !quitting && type == NSUserActivityTypeBrowsingWeb
    }
    func application(_ application:NSApplication, continue userActivity:NSUserActivity,
                     restorationHandler:@escaping ([NSUserActivityRestoring])->Void) -> Bool {
        guard !quitting else { return false }
        return BrowserHandoff.receive(userActivity) { url in
            // Reuse the regular external-link route, including its cold-start
            // queue and private-window exclusion. No current tab is overwritten.
            self.application(application,open:[url])
        }
    }
    func application(_ application:NSApplication,open urls:[URL]) {
        guard !quitting else { return }
        if !booted { pendingDocuments.append(urls); return }
        var batch = BrowserDocuments.Batch(); batch.append(urls)
        deliverBrowserDocuments(batch)
    }
}
