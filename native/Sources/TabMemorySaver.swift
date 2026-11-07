// SPDX-License-Identifier: MPL-2.0
import Foundation

enum TabMemorySaver {
    static let setting = "ArcRebornTabMemorySaver"
    static var enabled: Bool {
        (UserDefaults.standard.object(forKey:setting) as? Bool) ?? true
    }
    static func idleInterval(lowPower: Bool) -> TimeInterval { (lowPower ? 10 : 30) * 60 }

    // The exception is a local performance preference shared by all windows of
    // this profile. Private profiles never write site names to defaults.
    static let exceptionsChanged = Notification.Name("ArcRebornTabMemorySaverSitesChanged")
    private static var hostsByProfile = [String:Set<String>]()
    private static var privateHosts = [String:Set<String>]()
    private static func key(_ profile:String) -> String { "ArcRebornAlwaysActiveSites."+profile }

    static func host(for address:String) -> String? {
        guard let url = URL(string:address), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", var host = url.host?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        return host.isEmpty ? nil : host
    }
    static func hosts(in profile:String, privately:Bool) -> Set<String> {
        if privately { return privateHosts[profile] ?? [] }
        if let hosts = hostsByProfile[profile] { return hosts }
        let hosts = Set(UserDefaults.standard.stringArray(forKey:key(profile)) ?? [])
        hostsByProfile[profile] = hosts
        return hosts
    }
    static func setKeptActive(_ enabled:Bool, host:String, profile:String, privately:Bool) {
        var sites = hosts(in:profile,privately:privately)
        if enabled { sites.insert(host) } else { sites.remove(host) }
        defer { NotificationCenter.default.post(name:exceptionsChanged,object:nil) }
        if privately { privateHosts[profile] = sites; return }
        hostsByProfile[profile] = sites
        if sites.isEmpty { UserDefaults.standard.removeObject(forKey:key(profile)) }
        else { UserDefaults.standard.set(sites.sorted(),forKey:key(profile)) }
    }
    static func forgetPrivateProfile(_ profile:String) { privateHosts.removeValue(forKey:profile) }
}
