import Foundation
import Security

/// The account is separate from a local Chromium profile. Credentials never enter session.json.
private final class AccountRedirectPolicy:NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) { completionHandler(nil) }
}
final class ArcAccount {
    static let shared = ArcAccount()
    struct User: Codable { let id: String; let name: String; let email: String; let emailVerified: Bool }
    struct Login: Decodable { let token: String?; let user: User }
    enum Failure: LocalizedError {
        case message(String)
        case service(Int)
        var errorDescription: String? {
            if case let .message(text) = self { return text }
            if case let .service(status) = self {
                return [401:"Votre connexion a expiré. Reconnectez-vous pour reprendre la synchronisation.",403:"Cette demande n’est pas autorisée.",409:"Un autre appareil vient de modifier vos données. Nouvelle tentative…",413:"Votre session est trop volumineuse pour être synchronisée.",429:"Trop de demandes. Réessayez dans quelques minutes."][status] ?? "Le service est temporairement indisponible. Vos données restent enregistrées sur ce Mac."
            }
            return nil
        }
    }
    private(set) var user: User?
    static let changed = Notification.Name("ArcRebornAccountChanged")
    var server: URL? {
        // UI/test builds must never read the user's account token or contact
        // the live account service just by opening onboarding/preferences.
        let env = ProcessInfo.processInfo.environment
        if env["BROWSER_NATIVE_TEST_DATA"] != nil {
            // Explicit opt-in to a local preview; never use the real service or account token.
            guard Bundle.main.object(forInfoDictionaryKey:"ArcRebornDevelopmentBuild") as? Bool == true, let port = env["ARC_ACCOUNT_PREVIEW_PORT"].flatMap(UInt16.init), port > 1024 else { return nil }
            return URL(string:"http://127.0.0.1:\(port)")
        }
        let raw = Bundle.main.object(forInfoDictionaryKey:"ArcRebornAccountURL") as? String ?? ""
        guard let url = URL(string:raw), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }
    private let network: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        return URLSession(configuration:config,delegate:AccountRedirectPolicy(),delegateQueue:nil)
    }()
    private var keychainQuery: [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"app.arc-reborn.account",kSecAttrAccount as String:server?.absoluteString ?? "unconfigured"]
    }
    private let isolated = ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"] != nil
    private var previewToken:String?
    private func forget() {
        if isolated { previewToken = nil } else { SecItemDelete(keychainQuery as CFDictionary) }
    }
    private func token() -> String? {
        if isolated { return previewToken }
        var query = keychainQuery; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&value) == errSecSuccess, let data = value as? Data else { return nil }
        return String(data:data,encoding:.utf8)
    }
    private func remember(_ token: String) throws {
        if isolated { previewToken = token; return }; let data = Data(token.utf8)
        let status = SecItemUpdate(keychainQuery as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = keychainQuery; query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(query as CFDictionary,nil) == errSecSuccess else { throw Failure.message("Le trousseau n’a pas pu enregistrer la connexion.") }
        } else if status != errSecSuccess { throw Failure.message("Le trousseau n’est pas accessible.") }
    }
    static func validName(_ name:String) -> Bool {
        (3...32).contains(name.utf8.count) && name.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95
        }
    }
    static func validEmail(_ email:String) -> Bool {
        email.utf16.count <= 254 && email.range(of:#"^[^\s@]+@[^\s@]+\.[^\s@]+$"#,options:.regularExpression) != nil
    }
    static func passwordRules(_ password:String) -> (length:Bool, varied:Bool, withinLimit:Bool) {
        (password.trimmingCharacters(in:.whitespacesAndNewlines).unicodeScalars.count >= 15,
         Set(password.unicodeScalars).count >= 6, password.utf16.count <= 128)
    }
    static func registrationError(username:String,email:String,password:String,confirmation:String) -> String? {
        guard validName(username) else { return "Nom d’utilisateur : 3 à 32 lettres, chiffres ou tirets bas." }
        guard validEmail(email) else { return "Saisissez une adresse e-mail valide." }
        let rules = passwordRules(password)
        guard rules.length && rules.varied && rules.withinLimit else { return "Utilisez 15 à 128 caractères, dont au moins 6 différents." }
        guard password.utf8.elementsEqual(confirmation.utf8) else { return "Les mots de passe ne correspondent pas." }
        return nil
    }
    func nameIsAvailable(_ name:String) async throws -> Bool {
        struct Answer:Decodable { let available:Bool }
        let body = try JSONEncoder().encode(["username":name])
        let (data,_) = try await perform("api/auth/is-username-available",method:"POST",body:body,authenticated:false)
        return try JSONDecoder().decode(Answer.self,from:data).available
    }
    private func request(_ path:String,body:[String:String]? = nil,authenticated:Bool = false) async throws -> (Data,HTTPURLResponse) {
        do { return try await perform("api/auth/"+path,method:body == nil ? "GET" : "POST",body:body.map { try JSONSerialization.data(withJSONObject:$0) },authenticated:authenticated) }
        catch Failure.service(let status) {
            let messages = [400:"Vérifiez les informations saisies, puis réessayez.",409:"Ce nom n’est plus disponible. Choisissez-en un autre.",503:"Le service de comptes est momentanément indisponible. Réessayez dans un instant.",401:"Identifiants incorrects ou session expirée.",403:"Vérifiez votre adresse e-mail avant de vous connecter.",422:"Ce nom ou cette adresse e-mail ne peut pas être utilisé.",429:"Trop de tentatives. Réessayez dans quelques minutes."]
            throw Failure.message(messages[status] ?? "Le service n’a pas pu terminer la demande. Réessayez plus tard.")
        }
    }
    private func perform(_ resource:String,method:String,body:Data?,authenticated:Bool) async throws -> (Data,HTTPURLResponse) {
        guard let server else { throw Failure.message("Le service de comptes n’est pas encore raccordé. Vous pouvez continuer sans compte.") }
        var request = URLRequest(url:server.appendingPathComponent(resource))
        request.httpMethod = method
        // Better Auth also validates the origin of native JSON requests.
        var origin = URLComponents(url:server,resolvingAgainstBaseURL:false)!
        origin.path = ""; origin.query = nil; origin.fragment = nil
        request.setValue(origin.string,forHTTPHeaderField:"Origin")
        if let body { request.httpBody = body; request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        if authenticated, let token = token() { request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization") }
        let (data,response) = try await network.data(for:request)
        guard let response = response as? HTTPURLResponse, response.url?.host == server.host else { throw Failure.message("Réponse du serveur invalide.") }
        guard (200..<300).contains(response.statusCode) else {
            if resource.hasPrefix("api/auth/"), let reply = try? JSONDecoder().decode([String:String].self,from:data),
               let code = reply["code"] {
                let messages = ["USERNAME_IS_ALREADY_TAKEN":"Ce nom d’utilisateur est déjà pris. Essayez une variante.",
                                "INVALID_EMAIL":"Cette adresse e-mail n’est pas valide.",
                                "INVALID_EMAIL_OR_PASSWORD":"Adresse e-mail ou mot de passe incorrect.",
                                "EMAIL_NOT_VERIFIED":"Confirmez votre adresse e-mail avant de vous connecter.",
                                "USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL":"Impossible de créer ce compte. Essayez de vous connecter ou de réinitialiser le mot de passe."]
                if let message = messages[code] { throw Failure.message(message) }
            }
            throw Failure.service(response.statusCode)
        }
        if authenticated, let renewed = response.value(forHTTPHeaderField:"set-auth-token"), !renewed.isEmpty { try remember(renewed) }
        return (data,response)
    }
    func syncRequest(body:Data? = nil) async throws -> Data {
        let (data,_) = try await perform("api/sync/state",method:body == nil ? "GET" : "PUT",body:body,authenticated:true)
        guard data.count <= 9*1024*1024 else { throw SessionStoreError.oversizedFile }
        return data
    }
    @MainActor func resendVerification(email:String) async throws {
        _ = try await request("send-verification-email",body:["email":email,"callbackURL":server?.appendingPathComponent("verified").absoluteString ?? ""])
    }
    @MainActor func signUp(username:String,email:String,password:String) async throws {
        _ = try await request("sign-up/email",body:["name":username,"username":username,"email":email,"password":password])
    }
    @MainActor func signIn(email:String,password:String) async throws {
        let (data,response) = try await request("sign-in/email",body:["email":email,"password":password])
        let login = try JSONDecoder().decode(Login.self,from:data)
        guard login.user.emailVerified, let token = response.value(forHTTPHeaderField:"set-auth-token") ?? login.token, !token.isEmpty else { throw Failure.message("Confirmez votre adresse e-mail pour terminer la connexion.") }
        try remember(token); user = login.user; NotificationCenter.default.post(name:Self.changed,object:nil)
    }
    @MainActor func refresh() async {
        guard server != nil, token() != nil else { return }
        do {
            let (data,_) = try await request("get-session",authenticated:true)
            if (try? JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed)) is NSNull {
                forget(); user = nil
                NotificationCenter.default.post(name:Self.changed,object:nil); return
            }
            struct Session:Decodable { let user:User }
            user = try JSONDecoder().decode(Session.self,from:data).user
            NotificationCenter.default.post(name:Self.changed,object:nil)
        } catch { /* A transient offline error must not delete credentials. */ }
    }
    @MainActor func resetPassword(email:String) async throws {
        guard let server else { throw Failure.message("Le service de comptes n’est pas encore raccordé.") }; _ = try await request("request-password-reset",body:["email":email,"redirectTo":server.appendingPathComponent("reset-password").absoluteString])
    }
    @MainActor func signOut() async throws {
        _ = try await request("sign-out",body:[:],authenticated:true)
        forget(); user = nil; NotificationCenter.default.post(name:Self.changed,object:nil)
    }
}
