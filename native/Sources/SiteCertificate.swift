import AppKit
import Security
import SecurityInterface

/// Certificates from Chromium's visible navigation entry, with its TLS status.
struct SiteCertificate {
    let trust: SecTrust
    let isSecure: Bool

    init?(info: [String:Any]) {
        guard let address = info["url"] as? String, let url = URL(string:address),
              url.scheme?.lowercased() == "https", let host = url.host,
              let encoded = info["certificates"] as? [Data], !encoded.isEmpty else { return nil }
        let certificates = encoded.compactMap { SecCertificateCreateWithData(nil,$0 as CFData) }
        // Do not accidentally display an issuer as the leaf if decoding fails.
        guard certificates.count == encoded.count else { return nil }
        var value: SecTrust?
        guard SecTrustCreateWithCertificates(certificates as CFArray,SecPolicyCreateSSL(true,host as CFString),&value) == errSecSuccess,
              let value else { return nil }
        SecTrustSetNetworkFetchAllowed(value,false)
        trust = value; isSecure = info["secure"] as? Bool ?? false
    }

    func show(in window: NSWindow) {
        guard window.attachedSheet == nil, let panel = SFCertificatePanel.shared() else { return }
        panel.appearance = window.effectiveAppearance
        panel.setDefaultButtonTitle("OK"); panel.setAlternateButtonTitle(nil)
        panel.beginSheet(for:window,modalDelegate:nil,didEnd:nil,contextInfo:nil,trust:trust,showGroup:true)
        if let view = panel.certificateView() {
            view.setDisplayTrust(true); view.setEditableTrust(false)
            view.setDisplayDetails(true); view.setDetailsDisclosed(true)
        }
    }
}
