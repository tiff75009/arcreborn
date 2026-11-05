import Foundation

/// Track signals from the live page. A favorite's saved title may have been
/// renamed, synced, or copied from another profile.
struct FavoriteUnread {
    private(set) var visible = false
    private var scope: String?

    private static let number = #"([0-9]+(?:[., \u00A0\u202F][0-9]{3})*)\+?"#
    private static let explicit = try! NSRegularExpression(pattern:
        #"^\s*[\[(]?\s*"# + number + #"\s+(?:unread\b|(?:messages?\s+|e-mails?\s+)?non[\s-]+lu(?:s|es?)?\b)"#, options:.caseInsensitive)
    private static let prefix = try! NSRegularExpression(pattern: #"^\s*\("# + number + #"\)(?=\s|$)"#)
    private static let inbox = try! NSRegularExpression(pattern:
        #"^(?:inbox|bo[iî]te de réception)(?:\s+\("# + number + #"\))?(?:\s+[-–—]\s+|$)"#, options:.caseInsensitive)
    private static let messagingHosts: Set<String> = [
        "web.whatsapp.com", "discord.com", "app.slack.com",
        "x.com", "twitter.com", "teams.microsoft.com", "outlook.live.com", "outlook.office.com"
    ]

    mutating func navigate(to address: String) {
        let next = Self.scope(for:address)
        if scope != next { scope = next; visible = false }
    }

    mutating func update(title: String, address: String) {
        navigate(to:address)
        guard scope != nil, let host = URL(string:address)?.host?.lowercased() else { return }
        if let unread = Self.count(in:title, matching:Self.explicit) { visible = unread; return }
        if Self.messagingHosts.contains(host), let unread = Self.count(in:title, matching:Self.prefix) {
            visible = unread; return
        }
        if host == "mail.google.com" {
            // A conversation's subject does not report the inbox count. Keep
            // the last signal for this mailbox until its inbox reports again.
            if let unread = Self.count(in:title, matching:Self.inbox) { visible = unread }
        } else {
            visible = false
        }
    }

    mutating func updateInbox(_ unread:Bool, document:String, address:String) {
        guard document.hasPrefix("https://mail.google.com/mail/"), Self.scope(for:document) == Self.scope(for:address) else { return }
        navigate(to:address)
        visible = unread
    }

    private static func count(in title: String, matching expression: NSRegularExpression) -> Bool? {
        let text = title as NSString
        guard let match = expression.firstMatch(in:title,range:NSRange(location:0,length:text.length)) else { return nil }
        let number = match.range(at:1)
        return number.location != NSNotFound && text.substring(with:number).contains { "123456789".contains($0) }
    }

    private static func scope(for address: String) -> String? {
        guard let url = URLComponents(string:address), let scheme = url.scheme, ["https","http"].contains(scheme),
              let host = url.host?.lowercased() else { return nil }
        let origin = scheme + "://" + host + (url.port.map { ":\($0)" } ?? "")
        guard host == "mail.google.com" else { return origin }
        // Gmail routes folders and threads in the fragment, accounts in the
        // path (or authuser parameter). Never carry a dot to another mailbox.
        let account = url.queryItems?.first { $0.name == "authuser" }?.value ?? ""
        return origin + url.path.trimmingCharacters(in:CharacterSet(charactersIn:"/")) + "?" + account
    }
}
