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
        guard ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"] == nil else { return nil }
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
    private func token() -> String? {
        var query = keychainQuery; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&value) == errSecSuccess, let data = value as? Data else { return nil }
        return String(data:data,encoding:.utf8)
    }
    private func remember(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(keychainQuery as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = keychainQuery; query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(query as CFDictionary,nil) == errSecSuccess else { throw Failure.message("Le trousseau n’a pas pu enregistrer la connexion.") }
        } else if status != errSecSuccess { throw Failure.message("Le trousseau n’est pas accessible.") }
    }
    static func registrationError(username:String,email:String,password:String,confirmation:String) -> String? {
        guard username.range(of:"^[a-zA-Z0-9_]{3,32}$",options:.regularExpression) != nil else { return "Nom d’utilisateur : 3 à 32 lettres, chiffres ou tirets bas." }
        guard email.count <= 254, email.range(of:"^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$",options:.regularExpression) != nil else { return "Saisissez une adresse e-mail valide." }
        guard password.count >= 15, password.count <= 128, password.trimmingCharacters(in:.whitespacesAndNewlines).count >= 15, Set(password).count >= 6 else { return "Choisissez une phrase de passe de 15 à 128 caractères, avec plusieurs mots ou caractères différents." }
        guard password == confirmation else { return "Les mots de passe ne correspondent pas." }
        return nil
    }
    private func request(_ path:String,body:[String:String]? = nil,authenticated:Bool = false) async throws -> (Data,HTTPURLResponse) {
        do { return try await perform("api/auth/"+path,method:body == nil ? "GET" : "POST",body:body.map { try JSONSerialization.data(withJSONObject:$0) },authenticated:authenticated) }
        catch Failure.service(let status) {
            let messages = [401:"Identifiants incorrects ou session expirée.",403:"Vérifiez votre adresse e-mail avant de vous connecter.",422:"Ce nom ou cette adresse e-mail ne peut pas être utilisé.",429:"Trop de tentatives. Réessayez dans quelques minutes."]
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
        guard (200..<300).contains(response.statusCode) else { throw Failure.service(response.statusCode) }
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
                SecItemDelete(keychainQuery as CFDictionary); user = nil
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
        SecItemDelete(keychainQuery as CFDictionary); user = nil; NotificationCenter.default.post(name:Self.changed,object:nil)
    }
}
