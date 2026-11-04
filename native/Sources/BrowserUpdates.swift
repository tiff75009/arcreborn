// SPDX-License-Identifier: MPL-2.0
import AppKit
import Sparkle

/// Sparkle owns scheduling, verification, download and installation. The native
/// application keeps its normal CEF shutdown path (including beforeunload).
final class BrowserUpdates: NSObject {
    static let shared = BrowserUpdates()
    private var controller: SPUStandardUpdaterController?
    private var news: ReleaseNotesWindow?
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    private var disabled: Bool {
        ProcessInfo.processInfo.environment["BROWSER_NATIVE_TEST_DATA"] != nil ||
        Bundle.main.object(forInfoDictionaryKey: "ArcRebornDevelopmentBuild") as? Bool == true
    }
    var canCheck: Bool { !disabled && controller?.updater.canCheckForUpdates == true }
    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
    var automaticallyDownloads: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { controller?.updater.automaticallyDownloadsUpdates = newValue }
    }
    var isAvailable: Bool { !disabled && controller != nil }
    var allowsAutomaticDownloads: Bool { isAvailable && controller?.updater.allowsAutomaticUpdates == true }
    func start() {
        guard !disabled, controller == nil else { return }
        // Defaults live in Info.plist, so Sparkle preserves explicit user choices.
        // Its scheduler resumes overdue checks at launch; no competing timer or
        // unconditional launch check (which would ignore the six-hour cadence).
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    func check() { guard canCheck else { return }; controller?.checkForUpdates(nil) }

    /// Fresh installs establish a baseline. An upgrade is shown once, never on
    /// downgrade, and only after onboarding/other launch sheets have finished.
    func presentNewsAfterUpgrade(ready: @escaping () -> Bool) {
        guard !disabled, let current = Int(Self.build) else { return }
        let defaults = UserDefaults.standard, key = "ArcRebornLastNewsBuild"
        if defaults.object(forKey: key) == nil { defaults.set(current, forKey: key); return }
        guard current > defaults.integer(forKey: key) else { return }
        func attempt(_ remaining: Int) {
            guard remaining > 0 else { return } // Retry at next launch if busy.
            if ready(), NSApp.modalWindow == nil, !NSApp.windows.contains(where: { $0.attachedSheet != nil }) {
                if self.showNews() { defaults.set(current, forKey: key) }
            } else { DispatchQueue.main.asyncAfter(deadline: .now()+2) { attempt(remaining-1) } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+2) { attempt(60) }
    }
    @discardableResult func showNews() -> Bool {
        if news == nil {
            guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "json"),
                  let data = try? Data(contentsOf: url), let notes = try? JSONDecoder().decode(ReleaseNotes.self, from: data),
                  notes.version == Self.version, String(notes.build) == Self.build else { return false }
            news = ReleaseNotesWindow(notes: notes)
        }
        news?.showWindow(nil); news?.window?.makeKeyAndOrderFront(nil)
        return true
    }
}

struct ReleaseNotes: Decodable {
    struct Text: Decodable {
        let fr: String
        let en: String
        var localized: String { UserDefaults.standard.string(forKey: "BrowserLanguage") == "en" ? en : fr }
    }
    struct Highlight: Decodable { let symbol: String; let title: Text; let detail: Text }
    let version: String
    let build: Int
    let title: Text
    let subtitle: Text
    let highlights: [Highlight]
}

private class ReleaseNotesSurface: NSView {
    override var isFlipped: Bool { true }
}

private final class ReleaseNotesCanvas: ReleaseNotesSurface {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        // A quiet wash behind the app icon; the reading area remains uniform.
        NSGradient(starting: NSColor.systemIndigo.withAlphaComponent(0.10), ending: .clear)?
            .draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: 234), angle: 90)
    }
}

private final class ReleaseHighlightRow: ReleaseNotesSurface {
    private let tint: NSColor
    private let separator: Bool
    init(item: ReleaseNotes.Highlight, width: CGFloat, tint: NSColor, separator: Bool) {
        self.tint = tint; self.separator = separator
        let title = NSTextField(wrappingLabelWithString: item.title.localized)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: item.detail.localized)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        let textWidth = width - 60
        let titleHeight = ceil(title.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height)
        let detailHeight = ceil(detail.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height)
        let rowHeight = max(76, titleHeight + detailHeight + 31)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: rowHeight))
        let glyph = NSImageView(frame: NSRect(x: 11, y: 24, width: 22, height: 22))
        glyph.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .medium))
        glyph.contentTintColor = tint
        addSubview(glyph)
        title.frame = NSRect(x: 60, y: 14, width: textWidth, height: titleHeight)
        detail.frame = NSRect(x: 60, y: 19 + titleHeight, width: textWidth, height: detailHeight)
        addSubview(title); addSubview(detail)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        tint.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 13, width: 44, height: 44), xRadius: 13, yRadius: 13).fill()
        if separator {
            NSColor.separatorColor.withAlphaComponent(0.35).setFill()
            NSRect(x: 60, y: bounds.height - 0.5, width: bounds.width - 60, height: 0.5).fill()
        }
    }
}

private final class ReleaseNotesWindow: NSWindowController {
    private var entranceViews: [NSView] = []
    private var hasAppeared = false

    init(notes: ReleaseNotes) {
        let english = UserDefaults.standard.string(forKey: "BrowserLanguage") == "en"
        let width: CGFloat = 520, margin: CGFloat = 38
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 610),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = english ? "What’s new in Arc Reborn" : "Nouveautés d’Arc Reborn"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.isMovableByWindowBackground = true
        window.animationBehavior = .documentWindow
        super.init(window: window)
        let root = ReleaseNotesCanvas(frame: NSRect(x: 0, y: 0, width: width, height: 610))
        window.contentView = root

        func label(_ text: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
                   color: NSColor = .labelColor, parent: NSView) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: size, weight: weight); field.textColor = color
            field.alignment = .center
            let textWidth = width - margin * 2
            let height = ceil(field.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height)
            field.frame = NSRect(x: margin, y: y, width: textWidth, height: height)
            parent.addSubview(field); return field
        }

        let header = ReleaseNotesSurface(frame: NSRect(x: 0, y: 0, width: width, height: 244))
        let icon = NSImageView(frame: NSRect(x: (width - 80) / 2, y: 37, width: 80, height: 80))
        icon.image = NSApp.applicationIconImage; icon.imageScaling = .scaleProportionallyUpOrDown
        header.addSubview(icon)
        _ = label("ARC REBORN  ·  \(notes.version)", y: 129, size: 10, weight: .semibold,
                  color: .secondaryLabelColor, parent: header)
        let title = label(notes.title.localized, y: 155, size: 27, weight: .semibold, parent: header)
        let subtitle = label(notes.subtitle.localized, y: title.frame.maxY + 9, size: 12.5,
                             color: .secondaryLabelColor, parent: header)
        header.frame.size.height = subtitle.frame.maxY + 22
        root.addSubview(header)

        let contentWidth = width - margin * 2
        let list = ReleaseNotesSurface(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 0))
        let colors: [NSColor] = [.systemIndigo, .systemTeal, .systemOrange]
        var y: CGFloat = 0
        for (index, item) in notes.highlights.enumerated() {
            let row = ReleaseHighlightRow(item: item, width: contentWidth,
                                          tint: colors[index % colors.count], separator: index < notes.highlights.count - 1)
            row.frame.origin.y = y; y += row.frame.height; list.addSubview(row)
        }
        list.frame.size.height = y
        // Long future release notes scroll without pushing the actions off screen.
        let maxHeight = min(680, (NSScreen.main?.visibleFrame.height ?? 800) - 70)
        let listHeight = min(y, max(100, maxHeight - header.frame.height - 118))
        let scroll = NSScrollView(frame: NSRect(x: margin, y: header.frame.maxY, width: contentWidth, height: listHeight))
        scroll.drawsBackground = false; scroll.hasVerticalScroller = y > listHeight
        scroll.scrollerStyle = .overlay; scroll.autohidesScrollers = true
        scroll.documentView = list; root.addSubview(scroll)

        let footer = ReleaseNotesSurface(frame: NSRect(x: 0, y: scroll.frame.maxY + 24, width: width, height: 94))
        let done = NSButton(title: english ? "Continue browsing" : "Continuer à naviguer", target: self, action: #selector(dismiss))
        done.bezelStyle = .rounded; done.controlSize = .large
        done.font = .systemFont(ofSize: 13, weight: .semibold); done.bezelColor = .systemIndigo
        done.keyEquivalent = "\r"
        done.frame = NSRect(x: 92, y: 0, width: width - 184, height: 38)
        footer.addSubview(done)
        window.defaultButtonCell = done.cell as? NSButtonCell
        let history = NSButton(title: english ? "See all release notes  ↗" : "Voir toutes les nouveautés  ↗", target: self, action: #selector(openHistory))
        history.isBordered = false; history.font = .systemFont(ofSize: 11)
        history.contentTintColor = .secondaryLabelColor
        history.frame = NSRect(x: margin, y: 47, width: contentWidth, height: 22)
        footer.addSubview(history); root.addSubview(footer)
        entranceViews = [header, scroll, footer]
        root.frame.size.height = footer.frame.maxY
        window.setContentSize(root.frame.size)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard !hasAppeared else { return }
        hasAppeared = true
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        for (index, view) in entranceViews.enumerated() {
            view.wantsLayer = true
            guard let layer = view.layer else { continue }
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0; opacity.toValue = 1
            let lift = CABasicAnimation(keyPath: "transform.translation.y")
            lift.fromValue = -6; lift.toValue = 0
            let animation = CAAnimationGroup()
            animation.animations = [opacity, lift]; animation.duration = 0.28
            animation.beginTime = CACurrentMediaTime() + Double(index) * 0.04
            animation.fillMode = .backwards
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "release-entrance")
        }
    }
    @objc private func dismiss() { close() }
    @objc private func openHistory() {
        NSWorkspace.shared.open(URL(string: "https://github.com/tiff75009/arcreborn/releases")!)
    }
}
