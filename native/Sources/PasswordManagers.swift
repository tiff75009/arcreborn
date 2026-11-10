import AppKit

/// Public extension identities, never inferred from a translated display name.
struct PasswordManagerProvider: Equatable {
    let id: String, name: String, symbol: String
    let appIDs: [String]
    var icon:NSImage? {
        if let url = Bundle.main.url(forResource:id,withExtension:"png",subdirectory:"PasswordManagers") { return NSImage(contentsOf:url) }
        if let app = appIDs.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier:$0) }).first { return NSWorkspace.shared.icon(forFile:app.path) }
        return nil
    }
    var storeURL: String { "https://chromewebstore.google.com/detail/" + id }
    static let all: [Self] = [
        .init(id:"ghmbeldphafepmbegfdlkpapadhbakde",name:"Proton Pass",symbol:"key.horizontal",appIDs:["me.proton.pass"]),
        .init(id:"aeblfdkhhhdcdjpifhhbdiojplfjncoa",name:"1Password",symbol:"lock.circle",appIDs:["com.1password.1password"]),
        .init(id:"nngceckbapebfimnlniiiahkandclblb",name:"Bitwarden",symbol:"shield",appIDs:["com.bitwarden.desktop"]),
        .init(id:"fdjamakpfbbddfjaooikfcpapjohcfmg",name:"Dashlane",symbol:"lock.shield",appIDs:["com.dashlane.Dashlane"]),
        .init(id:"bfogiafebfohielmmehodmfbbebbbpei",name:"Keeper",symbol:"key",appIDs:["com.callpod.keeper"]),
        .init(id:"hdokiejnpimakedhajhdlcegeplioahd",name:"LastPass",symbol:"ellipsis.rectangle",appIDs:["com.lastpass.LastPass"]),
        .init(id:"oboonakemofpalcgghocfoadofidjkkk",name:"KeePassXC",symbol:"lock.rectangle",appIDs:["org.keepassxc.keepassxc"]),
        .init(id:"pejdijmoenmkgeppbflobdenhhabjlaj",name:"Mots de passe iCloud",symbol:"icloud",appIDs:["com.apple.Passwords"]),
    ]
}

enum PasswordManagerExtensionState: Equatable { case missing, disabled, enabled }

struct PasswordManagerDetection {
    let provider: PasswordManagerProvider
    let extensionState: PasswordManagerExtensionState
    let appInstalled: Bool
    static func scan(settings:[String:Any], applicationExists:(String)->Bool = {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier:$0) != nil
    }) -> [Self] {
        PasswordManagerProvider.all.map { provider in
            let entry = settings[provider.id] as? [String:Any]
            let reasons = entry?["disable_reasons"]
            let disabled = (reasons as? [Any]).map { !$0.isEmpty } ?? ((reasons as? Int ?? 0) != 0)
            return Self(provider:provider,extensionState:entry == nil ? .missing : disabled ? .disabled : .enabled,
                        appInstalled:provider.appIDs.contains(where:applicationExists))
        }
    }
}

enum PasswordManagerChoice {
    static let native = "native"
    static func isValid(_ id:String) -> Bool {
        id == native || (id.count == 32 && id.allSatisfy { ("a"..."p").contains(String($0)) })
    }
}
