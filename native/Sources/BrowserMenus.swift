import AppKit

struct BrowserMenuState {
    var enabled = true
    var checked = false
    var title: String? = nil
}

final class BrowserMenus: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private weak var controller: BrowserController?
    private weak var appDelegate: NativeAppDelegate?
    private let language: String
    private let bindings: [String:SplitKeyBinding]
    private let customized: Set<String>
    private var spaces: NSMenu?
    private var profiles: NSMenu?
    private var extensions: NSMenu?
    init(controller: BrowserController?, appDelegate: NativeAppDelegate) {
        self.controller = controller; self.appDelegate = appDelegate
        language = controller?.menuLanguage ?? appDelegate.sharedSession.language
        bindings = BrowserCommands.resolved(controller?.commandOverrides ?? appDelegate.sharedSession.commandShortcuts ?? [:])
        customized = Set((controller?.commandOverrides ?? appDelegate.sharedSession.commandShortcuts ?? [:]).keys)
        super.init()
    }
    private func text(_ fr: String, _ en: String) -> String { language == "en" ? en : fr }
    private func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
        let item = NSMenuItem(title:title,action:nil,keyEquivalent:"")
        let menu = NSMenu(title:title); menu.delegate = self; item.submenu = menu; parent.addItem(item); return menu
    }
    private func add(_ ids: [String], to menu: NSMenu) {
        for id in ids {
            if id == "-" { menu.addItem(.separator()); continue }
            guard let command = BrowserCommands.command(id) else { continue }
            let binding = bindings[id] ?? .init(key:"",modifiers:0)
            let item = NSMenuItem(title:command.title(language),action:#selector(run(_:)),keyEquivalent:binding.key)
            item.allowsAutomaticKeyEquivalentLocalization = !customized.contains(id)
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue:binding.modifiers)
            item.representedObject = id; item.target = self
            if !command.available {
                item.action = nil; item.isEnabled = false
                item.toolTip = text("Cette fonctionnalité n’est pas encore disponible.","This feature is not available yet.")
            } else if id == "about" { item.target = appDelegate; item.action = #selector(NativeAppDelegate.about(_:)) }
            else if let selector = ["hide":"hide:","hideOthers":"hideOtherApplications:","showAll":"unhideAllApplications:","quit":"terminate:","bringAll":"arrangeInFront:"][id] {
                item.target = NSApp; item.action = NSSelectorFromString(selector)
            } else if let selector = ["closeWindow":"performClose:","minimize":"performMiniaturize:","windowZoom":"performZoom:"][id] {
                item.target = nil; item.action = NSSelectorFromString(selector)
            }
            menu.addItem(item)
        }
    }
    func build() {
        let root = NSMenu()
        let app = submenu("Arc Reborn",in:root)
        add(["about","-","preferences","shareBrowser","defaultBrowser","-","importBrowser","updates","-"],to:app)
        NSApp.servicesMenu = submenu(text("Services","Services"),in:app)
        add(["privacy","-","hide","hideOthers","showAll","-","signOut","-","quit"],to:app)
        let file = submenu(text("Fichier","File"),in:root)
        add(["newTab","newWindow","blankWindow","incognito","littleWindow","restoreTab","-","openFile","commandBar","-","newProfile","newEasel","-","closeWindow","closeTab","-","sharePage","capture","captureFull","capturePortrait","savePage","print"],to:file)
        let edit = submenu(text("Édition","Edit"),in:root)
        for (fr,en,selector,key,flags) in [
            ("Annuler","Undo","undo:","z",NSEvent.ModifierFlags.command),
            ("Rétablir","Redo","redo:","z",[.command,.shift]),
            ("-","-","","",[]),
            ("Couper","Cut","cut:","x",.command), ("Copier","Copy","copy:","c",.command),
            ("Coller","Paste","paste:","v",.command), ("Tout sélectionner","Select All","selectAll:","a",.command)] {
            if fr == "-" { edit.addItem(.separator()); continue }
            let item = NSMenuItem(title:text(fr,en),action:NSSelectorFromString(selector),keyEquivalent:key)
            item.keyEquivalentModifierMask = flags; edit.addItem(item)
        }
        edit.addItem(.separator()); add(["find","findNext","findPrevious"],to:edit)
        let view = submenu(text("Présentation","View"),in:root)
        let appearance = submenu(text("Apparence","Appearance"),in:view)
        add(["appearance.automatic","appearance.light","appearance.dark"],to:appearance)
        add(["-","sidebar","toolbar","collapsePinned","-","reload","stop","forceReload","clearCookies","clearCache","-","split.add","split.close","split.separate","split.expand"],to:view)
        let panels = submenu(text("Activer un panneau","Switch to Split Pane"),in:view)
        add(["split.pane1","split.pane2","split.pane3","split.pane4","-","split.next","split.previous","-","split.note"],to:panels)
        add(["-","zoomReset","zoomIn","zoomOut","-","pip","cast","-"],to:view)
        let developer = submenu(text("Développement","Developer"),in:view)
        add(["developer","-","devtools","console","network","inspect"],to:developer)
        add(["-","fullscreen"],to:view)
        let spaces = submenu(text("Espaces","Spaces"),in:root); self.spaces = spaces
        add(["newSpace","spaceTheme","spaceRename"],to:spaces)
        profiles = submenu(text("Changer de profil","Change Profile"),in:spaces)
        add(["-","spaceNext","spacePrevious","-"],to:spaces)
        add(["manageSpaces"],to:spaces)
        let tabs = submenu(text("Onglets","Tabs"),in:root)
        add(["newTab","pinTab","renameTab","duplicateTab","-","newFolder","-","tabNext","tabPrevious","revealTab","-","clearToday","resetTabs"],to:tabs)
        let archive = submenu(text("Archives","Archive"),in:root)
        add(["back","forward","-","history","archive","clearArchive"],to:archive)
        let extensions = submenu("Extensions",in:root); self.extensions = extensions
        add(["addExtension","manageExtensions"],to:extensions)
        let window = submenu(text("Fenêtre","Window"),in:root)
        add(["alwaysOnTop","minimize","windowZoom","windowFill","windowCenter","-"],to:window)
        let move = submenu(text("Déplacer et redimensionner","Move and Resize"),in:window)
        add(["windowLeft","windowRight","windowTop","windowBottom","-","windowFill","windowCenter"],to:move)
        add(["-","library","downloads","easels","media","boosts","-","bringAll"],to:window)
        NSApp.windowsMenu = window
        let help = submenu(text("Aide","Help"),in:root)
        add(["whatsNew","gettingStarted","shortcuts","contact","helpCenter","restoreData","exportNotes","-"],to:help)
        let troubleshooting = submenu(text("Dépannage","Troubleshooting"),in:help)
        add(["logs","about"],to:troubleshooting)
        NSApp.helpMenu = help
        NSApp.mainMenu = root
        refreshSpaces(); refreshProfiles(); refreshExtensions(); reconcileBindings()
    }
    @objc private func run(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, validateMenuItem(item) else { return }
        if id == "closeTab", let window = NSApp.keyWindow as? AuthenticationWindow {
            window.performClose(item); return
        }
        if let kind = ["newWindow":BrowserWindowKind.normal,"blankWindow":.blank,"incognito":.privateWindow,"littleWindow":.compact][id] {
            appDelegate?.openWindow(kind,from:controller); return
        }
        if id == "updates" { BrowserUpdates.shared.check(); return }
        if id == "openFile" { appDelegate?.chooseBrowserDocuments(in:controller); return }
        if id == "whatsNew" { BrowserUpdates.shared.showNews(); return }
        controller?.performBrowserCommand(id)
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let id = item.representedObject as? String else { return false }
        if id == "closeTab", NSApp.keyWindow is AuthenticationWindow {
            item.title = text("Annuler la connexion","Cancel Sign In")
            return true
        }
        if ["newWindow","blankWindow","incognito","littleWindow"].contains(id) { return appDelegate?.sharedSession.onboardingComplete == true && appDelegate?.quitting == false }
        if id == "updates" { return appDelegate?.quitting == false && BrowserUpdates.shared.canCheck }
        if id == "openFile" {
            return appDelegate?.booted == true && appDelegate?.quitting == false &&
                appDelegate?.sharedSession.onboardingComplete == true && !(NSApp.keyWindow is AuthenticationWindow) &&
                (controller.map { $0.window.isKeyWindow && $0.window.attachedSheet == nil } ?? (NSApp.keyWindow == nil))
        }
        if id == "whatsNew" { return appDelegate?.quitting == false }
        guard let controller else { return false }
        let state = controller.browserCommandState(id)
        item.state = state.checked ? .on : .off
        if let title = state.title { item.title = title }
        return state.enabled
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === spaces { refreshSpaces() }
        if menu === profiles { refreshProfiles() }
        if menu === extensions { refreshExtensions() }
        reconcileBindings()
    }
    /// AppKit localizes default key equivalents for AZERTY and other layouts.
    /// Custom bindings are literal keystrokes. Resolve any resulting collision in their favor.
    private func reconcileBindings() {
        func entries(_ menu:NSMenu?) -> [NSMenuItem] {
            (menu?.items ?? []).flatMap { [$0] + entries($0.submenu) }
        }
        let items = entries(NSApp.mainMenu)
        var used: [(SplitKeyBinding,String)] = []
        for item in items where !(item.representedObject is String) && !item.keyEquivalent.isEmpty {
            used.append((.init(key:item.keyEquivalent,modifiers:item.keyEquivalentModifierMask.rawValue),"reserved"))
        }
        for explicit in [true,false] {
            for item in items {
                guard let id = item.representedObject as? String, customized.contains(id) == explicit, !item.keyEquivalent.isEmpty else { continue }
                let key = SplitKeyBinding(key:item.keyEquivalent,modifiers:item.keyEquivalentModifierMask.rawValue)
                if used.contains(where: { $0.0 == key && $0.1 != id }) { item.keyEquivalent = "" }
                else { used.append((key,id)) }
            }
        }
    }
    private func refreshSpaces() {
        guard let menu = spaces, let controller else { return }
        for item in menu.items where item.tag == 1001 { menu.removeItem(item) }
        let insertion = menu.numberOfItems-1
        for (n, space) in controller.menuSpaces.enumerated() {
            let id = n < 9 ? "space.\(n+1)" : "spaceID."+space.id
            let binding = bindings[id]
            let item = NSMenuItem(title:space.name,action:#selector(run(_:)),keyEquivalent:binding?.key ?? "")
            item.target = self; item.representedObject = id; item.tag = 1001
            item.allowsAutomaticKeyEquivalentLocalization = !customized.contains(id)
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue:binding?.modifiers ?? 0)
            item.image = NSImage(size:NSSize(width:16,height:16),flipped:false) { rect in SpaceIcon.draw(space.icon,in:rect,color:.labelColor,size:14); return true }
            menu.insertItem(item,at:insertion+n)
        }
        let divider = NSMenuItem.separator(); divider.tag = 1001; menu.insertItem(divider,at:menu.numberOfItems-1)
    }
    private func refreshProfiles() {
        guard let menu = profiles, let controller else { return }; menu.removeAllItems()
        for profile in controller.menuProfiles {
            let item = NSMenuItem(title:profile.name,action:#selector(run(_:)),keyEquivalent:"")
            item.target = self; item.representedObject = "profile."+profile.id; menu.addItem(item)
        }
        menu.addItem(.separator()); add(["newProfile"],to:menu)
    }
    private func refreshExtensions() {
        guard let menu = extensions, let controller else { return }; menu.removeAllItems()
        let entries = controller.menuExtensions
        for entry in entries {
            let item = NSMenuItem(title:entry.name,action:#selector(run(_:)),keyEquivalent:"")
            item.target = self; item.representedObject = "extension."+entry.id
            item.image = entry.image?.copy() as? NSImage; item.image?.size = NSSize(width:18,height:18); menu.addItem(item)
        }
        if !entries.isEmpty { menu.addItem(.separator()) }
        add(["addExtension","manageExtensions"],to:menu)
    }
}
