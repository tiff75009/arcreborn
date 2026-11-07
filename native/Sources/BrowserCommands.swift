import AppKit

/// One catalog drives both the menu bar and the shortcut editor. IDs are persisted.
struct BrowserCommand {
    let id: String
    let fr: String
    let en: String
    let category: String
    var binding = SplitKeyBinding(key: "", modifiers: 0)
    var available = true
    func title(_ language: String) -> String { language == "en" ? en : fr }
}

enum BrowserCommands {
    static let changed = Notification.Name("BrowserShortcutsChanged")
    static let categories = ["Arc Reborn", "Fichier", "Présentation", "Développement", "Vue partagée", "Espaces", "Onglets", "Archives", "Extensions", "Fenêtre", "Aide"]
    static func categoryTitle(_ name: String, _ language: String) -> String {
        guard language == "en" else { return name }
        return ["Fichier":"File", "Présentation":"View", "Développement":"Developer", "Vue partagée":"Split View", "Espaces":"Spaces", "Onglets":"Tabs", "Archives":"Archive", "Fenêtre":"Window", "Aide":"Help"][name] ?? name
    }
    static let all: [BrowserCommand] = {
        var result: [BrowserCommand] = []
        var category = "Arc Reborn"
        func add(_ id: String, _ fr: String, _ en: String, _ key: String = "", _ flags: NSEvent.ModifierFlags = .command, available: Bool = true) {
            result.append(BrowserCommand(id:id,fr:fr,en:en,category:category,binding:SplitKeyBinding(key:key,modifiers:key.isEmpty ? 0 : flags.rawValue),available:available))
        }
        add("about", "À propos d’Arc Reborn", "About Arc Reborn")
        add("preferences", "Préférences…", "Preferences…", ",")
        add("shareBrowser", "Partager Arc Reborn", "Share Arc Reborn", available:false)
        add("defaultBrowser", "Définir comme navigateur par défaut…", "Set as Default Browser…")
        add("importBrowser", "Importer depuis un autre navigateur…", "Import from Another Browser…")
        add("whatsNew","Nouveautés d’Arc Reborn…","What’s New…")
        add("updates", "Rechercher des mises à jour…", "Check for Updates…")
        add("privacy", "Politique de confidentialité", "Privacy Policy", available:false)
        add("hide", "Masquer Arc Reborn", "Hide Arc Reborn", "h")
        add("hideOthers", "Masquer les autres applications", "Hide Others", "h", [.command,.option])
        add("showAll", "Tout afficher", "Show All")
        add("signOut", "Se déconnecter", "Sign Out", available:false)
        add("quit", "Quitter Arc Reborn", "Quit Arc Reborn", "q")
        category = "Fichier"
        add("newTab", "Nouvel onglet…", "New Tab…", "t")
        add("openFile", "Ouvrir un fichier…", "Open File…", "o")
        add("newWindow", "Nouvelle fenêtre", "New Window", "n")
        add("blankWindow", "Fenêtre vide", "Blank Window", "n", [.command,.control])
        add("incognito", "Nouvelle fenêtre privée", "New Incognito Window", "n", [.command,.control,.shift])
        add("littleWindow", "Nouvelle petite fenêtre", "New Little Window", "n", [.command,.option])
        add("restoreTab", "Rouvrir le dernier onglet fermé", "Restore Last Closed Tab", "t", [.command,.shift])
        add("commandBar", "Ouvrir la barre de commande…", "Open Command Bar…", "l")
        add("newProfile", "Nouveau profil…", "New Profile…")
        add("newEasel", "Nouvel Easel", "New Easel", available:false)
        add("closeWindow", "Fermer la fenêtre", "Close Window", "w", [.command,.shift])
        add("closeTab", "Archiver l’onglet", "Archive Tab", "w")
        add("sharePage", "Partager…", "Share…")
        add("capture", "Capturer une portion de la page…", "Capture…", "2", [.command,.shift])
        add("captureFull", "Capturer toute la page", "Capture Full Page")
        add("capturePortrait", "Capturer en mode portrait…", "Capture in Portrait Mode…")
        add("savePage", "Enregistrer la page sous…", "Save Page As…", "s", [.command,.shift])
        add("print", "Imprimer…", "Print…", "p")
        category = "Présentation"
        add("appearance.automatic", "Automatique", "Automatic")
        add("appearance.light", "Clair", "Light")
        add("appearance.dark", "Sombre", "Dark")
        add("sidebar", "Masquer la barre latérale", "Hide Sidebar", "s")
        add("toolbar", "Afficher la barre d’outils", "Show Toolbar", available:false)
        add("collapsePinned", "Replier les onglets épinglés", "Collapse Pinned Tabs")
        add("reload", "Recharger la page", "Reload Page", "r")
        add("stop", "Arrêter le chargement", "Stop Loading", ".")
        add("forceReload", "Forcer le rechargement de la page", "Force Refresh the Page", "r", [.command,.shift])
        add("clearCookies", "Effacer les cookies et recharger", "Clear Cookies and Refresh")
        add("clearCache", "Vider le cache et recharger", "Clear Cache and Refresh")
        add("zoomReset", "Taille réelle", "Actual Size", "0")
        add("zoomIn", "Zoom avant", "Zoom In", "+")
        add("zoomOut", "Zoom arrière", "Zoom Out", "-")
        add("find", "Rechercher dans la page…", "Find in Page…", "f")
        add("findNext", "Rechercher l’occurrence suivante", "Find Next", "g")
        add("findPrevious", "Rechercher l’occurrence précédente", "Find Previous", "g", [.command,.shift])
        add("pip", "Activer l’image dans l’image", "Enter Picture-in-Picture")
        add("cast", "Diffuser…", "Cast…", available:false)
        add("fullscreen", "Activer le mode plein écran", "Enter Full Screen", "f", [.command,.control])
        category = "Développement"
        add("developer", "Activer le mode développeur", "Enable Developer Mode")
        add("devtools", "Afficher les outils de développement", "Show Developer Tools", "i", [.command,.option])
        add("console", "Afficher la console", "Show Console", "j", [.command,.option])
        add("network", "Afficher le panneau Réseau", "Show Network Panel")
        add("inspect", "Inspecter un élément", "Inspect Element", "c", [.command,.shift])
        category = "Vue partagée"
        for action in SplitShortcutAction.allCases {
            result.append(BrowserCommand(id:"split."+action.rawValue,fr:action.title("fr"),en:action.title("en"),category:category,binding:action.defaultBinding,available:action != .note))
        }
        add("split.expand", "Agrandir le panneau actif", "Expand Current Split", available:false)
        category = "Espaces"
        add("newSpace", "Nouvel espace…", "New Space…", "n", [.command,.shift])
        add("spaceTheme", "Modifier le thème…", "Edit Theme…")
        add("spaceRename", "Renommer l’espace…", "Rename Space…")
        add("spaceNext", "Espace suivant", "Next Space", "\u{F703}", [.control,.option])
        add("spacePrevious", "Espace précédent", "Previous Space", "\u{F702}", [.control,.option])
        for n in 1...9 { add("space.\(n)", "Activer l’espace \(n)", "Switch to Space \(n)", String(n), .control) }
        add("manageSpaces", "Gérer les espaces…", "Manage Spaces…")
        category = "Onglets"
        add("pinTab", "Épingler l’onglet", "Pin Tab", "d")
        add("renameTab", "Renommer l’onglet…", "Rename Tab…")
        add("duplicateTab", "Dupliquer l’onglet", "Duplicate Tab")
        add("newFolder", "Nouveau dossier…", "New Folder…")
        add("tabNext", "Onglet suivant", "Next Tab", "\u{F701}", [.command,.option])
        add("tabPrevious", "Onglet précédent", "Previous Tab", "\u{F700}", [.command,.option])
        add("revealTab", "Afficher l’onglet dans la barre latérale", "Reveal Tab in Sidebar")
        add("clearToday", "Archiver les onglets temporaires", "Clear Today", "k", [.command,.shift])
        add("resetTabs", "Réinitialiser les onglets de cet espace", "Reset All Tabs in This Space", available:false)
        category = "Archives"
        add("back", "Page précédente", "Go Back", "[")
        add("forward", "Page suivante", "Go Forward", "]")
        add("history", "Afficher l’historique", "View History", "y")
        add("archive", "Afficher les archives…", "View Archive…")
        add("clearArchive", "Vider les archives…", "Clear Archive…")
        category = "Extensions"
        add("addExtension", "Ajouter une extension…", "Add Extension…")
        add("manageExtensions", "Gérer les extensions…", "Manage Extensions…")
        category = "Fenêtre"
        add("alwaysOnTop", "Garder au premier plan", "Stay on Top")
        add("minimize", "Réduire", "Minimize", "m")
        add("windowZoom", "Zoom", "Zoom")
        add("windowFill", "Remplir l’écran", "Fill Screen")
        add("windowCenter", "Centrer", "Center")
        for (id,fr,en) in [("Left","Moitié gauche","Left Half"),("Right","Moitié droite","Right Half"),("Top","Moitié supérieure","Top Half"),("Bottom","Moitié inférieure","Bottom Half")] {
            add("window"+id,fr,en)
        }
        add("library", "Ouvrir la bibliothèque…", "Open Library…", "l", [.command,.shift])
        add("downloads", "Afficher les téléchargements…", "View Downloads…", "j", [.command,.shift])
        add("easels", "Afficher les Easels…", "View Easels…", available:false)
        add("media", "Afficher les médias…", "View Media…")
        add("boosts", "Afficher les Boosts…", "View Boosts…", available:false)
        add("bringAll", "Tout ramener au premier plan", "Bring All to Front")
        category = "Aide"
        add("gettingStarted", "Premiers pas", "Getting Started", available:false)
        add("shortcuts", "Raccourcis clavier…", "Keyboard Shortcuts…")
        add("contact", "Contacter l’équipe", "Contact the Team", available:false)
        add("helpCenter", "Centre d’aide", "Visit Help Center", available:false)
        add("restoreData", "Restaurer les données…", "Restore Data…", available:false)
        add("exportNotes", "Exporter les notes…", "Export Notes…", available:false)
        add("logs", "Ouvrir le dossier des journaux", "Open Logs Folder")
        return result
    }()
    static func command(_ id: String) -> BrowserCommand? { all.first { $0.id == id } }
    static let reserved: [SplitKeyBinding] = [
        .init(key:"z",modifiers:NSEvent.ModifierFlags.command.rawValue),
        .init(key:"z",modifiers:NSEvent.ModifierFlags([.command,.shift]).rawValue),
        .init(key:"x",modifiers:NSEvent.ModifierFlags.command.rawValue),
        .init(key:"c",modifiers:NSEvent.ModifierFlags.command.rawValue),
        .init(key:"v",modifiers:NSEvent.ModifierFlags.command.rawValue),
        .init(key:"a",modifiers:NSEvent.ModifierFlags.command.rawValue)
    ]
    static func displayedBindings(_ overrides:[String:SplitKeyBinding]) -> [String:SplitKeyBinding] {
        var result = resolved(overrides)
        func visit(_ menu:NSMenu?) {
            for item in menu?.items ?? [] {
                if let id = item.representedObject as? String, command(id) != nil {
                    result[id] = .init(key:item.keyEquivalent,modifiers:item.keyEquivalentModifierMask.rawValue)
                }
                visit(item.submenu)
            }
        }
        visit(NSApp.mainMenu)
        return result
    }
    static func valid(_ binding: SplitKeyBinding) -> Bool {
        if binding.key.isEmpty { return true }
        let flags = NSEvent.ModifierFlags(rawValue:binding.modifiers)
        return binding.key.count == 1 && !binding.key.contains("\u{1b}") && !flags.intersection([.command,.control,.option]).isEmpty && flags.subtracting([.command,.control,.option,.shift]).isEmpty
    }
    /// Explicit user bindings take precedence over new defaults, including old Split View bindings.
    static func resolved(_ overrides: [String:SplitKeyBinding]) -> [String:SplitKeyBinding] {
        var result: [String:SplitKeyBinding] = [:]
        var used = reserved
        for explicit in [true,false] {
            for command in all where command.available && (overrides[command.id] != nil) == explicit {
                let binding = overrides[command.id] ?? command.binding
                if valid(binding) && (binding.key.isEmpty || !used.contains(binding)) {
                    result[command.id] = binding
                    if !binding.key.isEmpty { used.append(binding) }
                } else { result[command.id] = .init(key:"",modifiers:0) }
            }
        }
        return result
    }
}
