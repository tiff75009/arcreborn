import AppKit

let application = BrowserEngine.createApplication()
application.setActivationPolicy(.regular)
let directory = ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BrowserNative", isDirectory: true)
let store = SessionStore(directory: directory)
do {
    let initial = try store.load() ?? BrowserSession.fresh(language: Locale.preferredLanguages.first?.hasPrefix("fr") == true ? "fr" : "en")
    UserDefaults.standard.set(initial.language, forKey: "BrowserLanguage")
UserDefaults.standard.set(initial.savePasswords ?? true, forKey: "BrowserSavePasswords")
UserDefaults.standard.set(initial.automaticSignIn ?? true, forKey: "BrowserAutomaticSignIn")
UserDefaults.standard.set(initial.formSuggestions ?? true, forKey: "BrowserFormSuggestions")
    let delegate = NativeAppDelegate(store: store, initial: initial)
    application.delegate = delegate
    let cache = directory.appendingPathComponent("Chromium", isDirectory: true)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    guard BrowserEngine.start(cachePath: cache.path) else {
        let alert = NSAlert(); alert.messageText = "Chromium n’a pas pu démarrer"; alert.informativeText = "Consultez le journal Chromium dans le dossier de session. Les données existantes sont conservées."; alert.runModal(); exit(1)
    }
    withExtendedLifetime(delegate) { BrowserEngine.runMessageLoop() }
    BrowserEngine.shutdown()
} catch {
    let alert = NSAlert(); alert.messageText = "Impossible d’ouvrir la session"; alert.informativeText = error.localizedDescription; alert.runModal(); exit(1)
}
