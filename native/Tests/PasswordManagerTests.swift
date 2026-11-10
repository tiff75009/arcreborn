import AppKit

@main struct PasswordManagerTests {
    static func main() throws {
        func check(_ value:Bool,_ name:String) { guard value else { fatalError(name) }; print("PASS \(name)") }
        var state = BrowserSession.fresh(language:"fr")
        let legacy = try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(state))
        check(legacy.passwordManagerID == nil,"older sessions keep the native manager")
        state.passwordManagerID = PasswordManagerProvider.all[0].id
        let restored = try JSONDecoder().decode(BrowserSession.self,from:JSONEncoder().encode(state))
        check(restored.passwordManagerID == state.passwordManagerID && restored.validated(),"manager choice survives session persistence")
        let privateState = restored.standaloneWindow(privateProfile:"isolated-private")
        check(privateState.passwordManagerID == state.passwordManagerID && privateState.savePasswords == false,"private windows retain provider choice without enabling saving")
        let proton = PasswordManagerProvider.all[0], one = PasswordManagerProvider.all[1]
        let settings:[String:Any] = [proton.id:["disable_reasons":[]],one.id:["disable_reasons":[1]]]
        let result = PasswordManagerDetection.scan(settings:settings,applicationExists: { $0 == "com.bitwarden.desktop" })
        check(result[0].extensionState == .enabled,"enabled Proton extension detected by immutable ID")
        check(result[1].extensionState == .disabled,"paused extension is not reported as active")
        check(result[2].appInstalled && result[2].extensionState == .missing,"desktop app does not imply browser extension installed")
        let legacyReasons = PasswordManagerDetection.scan(settings:[one.id:["disable_reasons":2]],applicationExists: {_ in false})
        check(legacyReasons[1].extensionState == .disabled,"legacy disable reasons respected")
        check(PasswordManagerChoice.isValid(proton.id) && PasswordManagerChoice.isValid("native"),"known and native providers accepted")
        check(!PasswordManagerChoice.isValid("../fake") && !PasswordManagerChoice.isValid(String(repeating:"z",count:32)),"invalid provider identity rejected")
        check(Set(PasswordManagerProvider.all.map(\.id)).count == PasswordManagerProvider.all.count,"provider identities unique")
        check(PasswordManagerProvider.all.allSatisfy { URL(string:$0.storeURL)?.host == "chromewebstore.google.com" },"installation destinations use the extension store")
    }
}
