// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

/// The strength rail represents the actual account policy. No guessed entropy scores.
private final class PasswordRail: NSView {
    private let segments = (0..<3).map { _ in CALayer() }
    private var level = 0
    override init(frame:NSRect) {
        super.init(frame:frame); wantsLayer = true; setAccessibilityElement(false)
        for segment in segments { segment.cornerRadius = 2; layer?.addSublayer(segment) }
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(_ value:Int) { guard value != level else { return }; level = value; paint(animated:true) }
    override func layout() {
        super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true)
        let w = (bounds.width-8)/3
        for (i,s) in segments.enumerated() { s.frame = CGRect(x:CGFloat(i)*(w+4),y:0,width:w,height:bounds.height) }
        CATransaction.commit(); paint(animated:false)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); paint(animated:false) }
    private func paint(animated:Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin(); CATransaction.setDisableActions(!animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            CATransaction.setAnimationDuration(0.18)
            for (i,s) in segments.enumerated() { s.backgroundColor = (i < level ? (level == 3 ? NSColor.systemGreen : ChapterInk.accent) : ChapterInk.line).cgColor }
            CATransaction.commit()
        }
    }
}

private final class AccountFieldPlate:NSView {
    var focused = false { didSet { needsDisplay = true } }
    var invalid = false { didSet { needsDisplay = true } }
    override func hitTest(_ point:NSPoint)->NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect:NSRect) {
        let p = NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:9,yRadius:9)
        ChapterInk.surface.setFill(); p.fill()
        (invalid ? NSColor.systemRed : focused ? ChapterInk.accent : ChapterInk.line).setStroke()
        p.lineWidth = focused ? 1.6 : 1; p.stroke()
    }
}

final class ArcAccountForm:NSView,NSTextFieldDelegate {
    override var isFlipped:Bool { true }
    var completed:(()->Void)?
    private let username = NSTextField(), email = NSTextField(), password = NSSecureTextField(), confirmation = NSSecureTextField()
    private var fields:[NSTextField] { login ? [email,password] : [username,email,password,confirmation] }
    private var hints:[ObjectIdentifier:NSTextField] = [:], plates:[ObjectIdentifier:AccountFieldPlate] = [:], visited = Set<ObjectIdentifier>()
    private var counters:[ObjectIdentifier:NSTextField] = [:]
    private var status = NSTextField(), submit:ChapterButton?, alternate:ChapterButton?, rail:PasswordRail?
    private var actions:[ChapterButton] = []
    private var login:Bool, busy = false
    private let english:Bool
    private var lookup:Task<Void,Never>?, operation:Task<Void,Never>?, accountObserver:NSObjectProtocol?
    private enum NameState { case idle, checking, free, taken, unknown, limited }
    private var availability:NameState = .idle
    private func t(_ fr:String,_ en:String)->String { english ? en : fr }
    private var mail:String { email.stringValue.trimmingCharacters(in:.whitespacesAndNewlines) }
    init(frame:NSRect,login:Bool = false,chapterLanguage:String? = nil) {
        self.login = login; english = chapterLanguage == "en"; super.init(frame:frame); build()
        accountObserver = NotificationCenter.default.addObserver(forName:ArcAccount.changed,object:nil,queue:.main) { [weak self] _ in
            guard let self, !self.busy else { return }; self.build()
        }
        Task { await ArcAccount.shared.refresh() }
    }
    required init?(coder:NSCoder) { fatalError() }
    deinit { lookup?.cancel(); operation?.cancel(); if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) } }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { lookup?.cancel() } }
    @discardableResult private func text(_ s:String,_ y:CGFloat,_ h:CGFloat,_ size:CGFloat,_ weight:NSFont.Weight = .regular,_ color:NSColor = .labelColor)->NSTextField {
        let l = NSTextField(wrappingLabelWithString:s); l.frame = NSRect(x:0,y:y,width:bounds.width,height:h)
        l.font = .systemFont(ofSize:size,weight:weight); l.textColor = color; addSubview(l); return l
    }
    @discardableResult private func button(_ s:String,_ y:CGFloat,_ h:CGFloat,style:ChapterButton.Style,action:@escaping()->Void)->ChapterButton {
        let b = ChapterButton(s,style:style,action:action); b.frame = NSRect(x:0,y:y,width:bounds.width,height:h)
        addSubview(b); actions.append(b); return b
    }
    private func field(_ f:NSTextField,_ title:String,_ placeholder:String,_ y:CGFloat,hintY:CGFloat? = nil) {
        let id = ObjectIdentifier(f)
        text(title,y,16,11.5,.semibold)
        if !login && (f === username || f === password) {
            let count = text("",y,15,10,.medium,.secondaryLabelColor); count.alignment = .right
            count.font = .monospacedDigitSystemFont(ofSize:10,weight:.medium); counters[id] = count
        }
        let plate = AccountFieldPlate(frame:NSRect(x:0,y:y+17,width:bounds.width,height:31)); plates[id] = plate; addSubview(plate)
        f.isBezeled = false; f.drawsBackground = false; f.focusRingType = .none
        f.font = .systemFont(ofSize:13); f.placeholderString = placeholder; f.setAccessibilityLabel(title)
        f.delegate = self; f.cell?.usesSingleLineMode = true; f.cell?.isScrollable = true
        f.frame = NSRect(x:10,y:y+24,width:bounds.width-20,height:19); addSubview(f)
        hints[id] = text("",hintY ?? y+49,16,10.5,.medium,.secondaryLabelColor)
    }
    private func build() {
        lookup?.cancel(); availability = .idle; visited.removeAll()
        subviews.forEach { $0.removeFromSuperview() }; actions.removeAll(); counters.removeAll(); hints.removeAll(); plates.removeAll(); rail = nil
        status = NSTextField(); submit = nil; alternate = nil
        if let user = ArcAccount.shared.user {
            text(user.name,0,35,25,.semibold); text(user.email,36,28,13,.medium,.secondaryLabelColor)
            addSubview(ArcSyncSettingsView(frame:NSRect(x:0,y:79,width:bounds.width,height:249)))
            _ = button(t("Se déconnecter","Sign out"),342,35,style:.soft) { [weak self] in self?.perform(.signOut) }
            status = text("",389,56,12); return
        }
        text(login ? t("Bon retour.","Welcome back.") : t("Créer un compte","Create an account"),0,33,24,.semibold)
        var y:CGFloat = 42
        if !login { field(username,t("Nom d’utilisateur","Username"),t("votre_nom","your_name"),y); y += 69 }
        field(email,t("Adresse e-mail","Email address"),t("vous@exemple.fr","you@example.com"),y); y += 68
        field(password,t("Mot de passe","Password"),login ? "••••••••" : t("Une phrase que vous retiendrez","A phrase you’ll remember"),y,hintY:login ? nil : y+58)
        if !login {
            let r = PasswordRail(frame:NSRect(x:1,y:y+51,width:bounds.width-2,height:3)); addSubview(r); rail = r
            y += 79; field(confirmation,t("Confirmation","Confirm password"),t("Répétez le mot de passe","Repeat your password"),y); y += 70
        } else { y += 65 }
        submit = button(login ? t("Se connecter","Sign in") : t("Créer mon compte","Create my account"),y,36,style:.solid) { [weak self] in self?.send() }
        alternate = button(login ? t("Créer un compte","Create an account") : t("J’ai déjà un compte","I already have an account"),y+40,28,style:.link) { [weak self] in
            guard let self, !self.busy else { return }
            self.window?.makeFirstResponder(nil); self.password.stringValue = ""; self.confirmation.stringValue = ""
            self.login.toggle(); self.build(); self.fields.first?.selectText(nil)
        }
        if login {
            _ = button(t("Mot de passe oublié ?","Forgot password?"),y+72,28,style:.link) { [weak self] in self?.perform(.reset) }
            _ = button(t("Renvoyer l’e-mail de confirmation","Resend confirmation email"),y+103,28,style:.link) { [weak self] in self?.perform(.resend) }
        }
        status = text("",y+(login ? 140 : 74),44,11.5,.medium,.secondaryLabelColor)
        let chain:[NSView] = fields + actions.map { $0 as NSView }
        for (a,b) in zip(chain,chain.dropFirst()) { a.nextKeyView = b }
        if !login { checkName() }; update()
    }
    private func hint(_ f:NSTextField,_ s:String,_ bad:Bool = false,_ good:Bool = false) {
        let id = ObjectIdentifier(f); hints[id]?.stringValue = s
        hints[id]?.textColor = bad ? .systemRed : good ? .systemGreen : .secondaryLabelColor
        plates[id]?.invalid = bad; f.setAccessibilityHelp(s)
    }
    func controlTextDidBeginEditing(_ note:Notification) {
        if let f = note.object as? NSTextField { plates[ObjectIdentifier(f)]?.focused = true }
    }
    func controlTextDidEndEditing(_ note:Notification) {
        if let f = note.object as? NSTextField { visited.insert(ObjectIdentifier(f)); plates[ObjectIdentifier(f)]?.focused = false; update() }
    }
    func controlTextDidChange(_ note:Notification) {
        if (note.object as? NSTextField) === username { checkName() }
        status.stringValue = ""; update()
    }
    func control(_ control:NSControl,textView:NSTextView,doCommandBy command:Selector)->Bool {
        guard let i = fields.firstIndex(where:{ $0 === control }) else { return false }
        if command == #selector(NSResponder.insertNewline(_:)) { send(); return true }
        let direction = command == #selector(NSResponder.insertTab(_:)) ? 1 : command == #selector(NSResponder.insertBacktab(_:)) ? -1 : 0
        guard direction != 0 else { return false }
        let next = i+direction
        if fields.indices.contains(next) { fields[next].selectText(nil); return true }
        if direction > 0, let button = actions.first(where:{$0.isEnabled}) { window?.makeFirstResponder(button); return true }
        return false
    }
    private func checkName() {
        lookup?.cancel(); let name = username.stringValue; availability = .idle
        guard !login, ArcAccount.validName(name) else { return }
        guard ArcAccount.shared.server != nil else { availability = .unknown; return }
        availability = .checking
        lookup = Task { [weak self] in
            let result:NameState
            do { try await Task.sleep(nanoseconds:400_000_000); result = try await ArcAccount.shared.nameIsAvailable(name) ? .free : .taken }
            catch ArcAccount.Failure.service(429) { result = .limited }
            catch { result = .unknown }
            guard !Task.isCancelled, let self, self.username.stringValue == name, !self.login else { return }
            self.availability = result; self.update()
        }
    }
    private func update() {
        guard ArcAccount.shared.user == nil else { return }
        let name = username.stringValue, secret = password.stringValue, confirm = confirmation.stringValue
        let validMail = ArcAccount.validEmail(mail)
        if !login {
            let guidance = t("3 à 32 caractères : A–Z, 0–9 et _.","3–32 characters: A–Z, 0–9 and _.")
            let count = name.unicodeScalars.count
            counters[ObjectIdentifier(username)]?.stringValue = "\(count) / 32"
            counters[ObjectIdentifier(password)]?.stringValue = "\(secret.utf16.count) / 128"
            if name.isEmpty { hint(username,guidance,visited.contains(ObjectIdentifier(username))) }
            else if !ArcAccount.validName(name) {
                let msg = count < 3 ? t("3 caractères minimum · \(count) saisi\(count == 1 ? "" : "s").","3 characters minimum · \(count) entered.") : count > 32 ? t("\(count)/32 · Raccourcissez votre nom.","\(count)/32 · Shorten your username.") : guidance
                hint(username,msg,true)
            } else {
                switch availability {
                case .checking: hint(username,t("Vérification de la disponibilité…","Checking availability…"))
                case .free: hint(username,t("✓ Disponible","✓ Available"),false,true)
                case .taken: hint(username,t("Déjà pris. Essayez un autre nom.","Already taken. Try another name."),true)
                case .limited: hint(username,t("Trop de vérifications. Réessayez dans une minute.","Too many checks. Try again in a minute."))
                default: hint(username,t("Disponibilité à confirmer à l’inscription.","Availability will be confirmed at sign-up."))
                }
            }
            let rules = ArcAccount.passwordRules(secret)
            let matches = !confirm.isEmpty && secret.utf8.elementsEqual(confirm.utf8)
            rail?.update(secret.isEmpty || !rules.withinLimit ? 0 : 1 + (rules.length ? 1 : 0) + (rules.varied ? 1 : 0))
            let p = !rules.withinLimit ? t("128 caractères maximum.","128 characters maximum.") : secret.isEmpty ? t("15 à 128 caractères · au moins 6 différents.","15–128 characters · at least 6 different characters.") : !rules.length ? t("15 caractères minimum, hors espaces aux extrémités.","At least 15 characters, excluding surrounding spaces.") : !rules.varied ? t("Utilisez au moins 6 caractères différents.","Use at least 6 different characters.") : t("✓ Mot de passe conforme","✓ Password meets all requirements")
            hint(password,p,!rules.withinLimit,rules.length && rules.varied && rules.withinLimit)
            hint(confirmation,matches ? t("✓ Les mots de passe correspondent","✓ Passwords match") : !confirm.isEmpty ? t("Les mots de passe diffèrent.","Passwords do not match.") : "",!confirm.isEmpty && !matches,matches)
        }
        let showEmail = !validMail && visited.contains(ObjectIdentifier(email))
        hint(email,showEmail ? t("Saisissez une adresse comme nom@exemple.fr.","Enter an address like name@example.com.") : (validMail ? t("✓ Format valide","✓ Valid format") : !mail.isEmpty ? t("Format attendu : nom@exemple.fr","Expected format: name@example.com") : ""),showEmail,validMail)
        let valid = login ? validMail && !secret.isEmpty : ArcAccount.registrationError(username:name,email:mail,password:secret,confirmation:confirm) == nil && availability != .taken && availability != .checking
        submit?.isEnabled = !busy && valid && ArcAccount.shared.server != nil
        if ArcAccount.shared.server == nil && status.stringValue.isEmpty { message(t("Comptes hors ligne. Vous pouvez continuer sans compte.","Accounts are offline. You can continue without an account.")) }
    }
    private func message(_ s:String,error:Bool = false) {
        status.stringValue = s; status.textColor = error ? .systemRed : .secondaryLabelColor
        if let window, !s.isEmpty { NSAccessibility.post(element:window,notification:.announcementRequested,userInfo:[.announcement:s,.priority:NSAccessibilityPriorityLevel.medium.rawValue]) }
    }
    private enum Operation { case register, signIn, reset, resend, signOut }
    private func send() {
        guard !busy else { return }; fields.forEach { visited.insert(ObjectIdentifier($0)) }; update()
        if submit?.isEnabled == true { perform(login ? .signIn : .register) }
    }
    private func perform(_ kind:Operation) {
        guard !busy else { return }
        if (kind == .reset || kind == .resend) && !ArcAccount.validEmail(mail) { visited.insert(ObjectIdentifier(email)); update(); email.selectText(nil); return }
        let name = username.stringValue, address = mail, secret = password.stringValue
        busy = true; actions.forEach { $0.isEnabled = false }; fields.forEach { $0.isEditable = false }
        message(t("Demande en cours…","Working…"))
        operation = Task { [weak self] in
            do {
                let api = ArcAccount.shared
                switch kind {
                case .register: try await api.signUp(username:name,email:address,password:secret)
                case .signIn: try await api.signIn(email:address,password:secret)
                case .reset: try await api.resetPassword(email:address)
                case .resend: try await api.resendVerification(email:address)
                case .signOut: try await api.signOut()
                }
                guard let self, !Task.isCancelled else { return }; self.unlock()
                switch kind {
                case .register:
                    self.password.stringValue = ""; self.confirmation.stringValue = ""; self.login = true; self.build()
                    self.message(self.t("Consultez votre messagerie pour confirmer votre adresse, puis connectez-vous.","Check your inbox to confirm your email, then sign in."))
                case .signIn,.signOut:
                    self.password.stringValue = ""; self.confirmation.stringValue = ""; self.build(); if kind == .signIn { self.completed?() }
                case .reset,.resend: self.message(self.t("Si cette adresse correspond à un compte, vous recevrez un e-mail.","If this address matches an account, you will receive an email."))
                }
            } catch {
                guard let self, !Task.isCancelled else { return }; self.unlock()
                if let e = error as? URLError {
                    self.message(e.code == .timedOut ? self.t("Le serveur met du temps à répondre. Réessayez.","The server took too long to respond. Try again.") : self.t("Impossible de joindre le serveur. Vérifiez votre connexion.","Cannot reach the server. Check your connection."),error:true)
                } else { self.message(error.localizedDescription,error:true) }
                if kind == .register { self.checkName(); self.update() }
            }
        }
    }
    private func unlock() { busy = false; fields.forEach { $0.isEditable = true }; actions.forEach { $0.isEnabled = true }; update() }
}
