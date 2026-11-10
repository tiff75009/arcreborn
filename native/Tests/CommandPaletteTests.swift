import AppKit

private final class PaletteTestContent: NSView {
    override var isFlipped: Bool { true }
}

@main enum CommandPaletteTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let parent = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:700),
                              styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        parent.contentView = PaletteTestContent(frame:NSRect(x:0,y:0,width:1000,height:700))
        parent.isReleasedWhenClosed = false
        parent.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps:true)
        var actions:[String] = [], dismissals = 0, checks = 0
        func check(_ value:Bool,_ name:String) {
            precondition(value,name); checks += 1; print("PASS",name)
        }
        func views(_ root:NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
        func palette(centered:Bool = true) -> CommandPalette {
            CommandPalette(parent:parent,newTab:centered,initial:"café",icon:nil,tint:.systemBlue,language:"fr",searchProvider:"DuckDuckGo",suggestions:{ query in
                [.init(title:query,detail:"Rechercher avec DuckDuckGo",image:nil,symbol:"magnifyingglass",kind:.search,perform:{actions.append("search:"+query)}),
                 .init(title:"Été à Lyon",detail:"Aller à l’onglet",image:nil,symbol:"globe",kind:.tab,perform:{actions.append("tab")}),
                 .init(title:"Musée",detail:"Rouvrir",image:nil,symbol:"clock",kind:.archived,perform:{actions.append("archive")})]
            },onDismiss:{dismissals += 1})
        }
        for appearance in [NSAppearance.Name.darkAqua,.aqua] {
            parent.appearance = NSAppearance(named:appearance)
            let command = palette(); command.show()
            guard let panel = parent.childWindows?.last, let root = panel.contentView,
                  let field = views(root).compactMap({$0 as? NSTextField}).first(where:{$0.isEditable}) else { fatalError("Missing command input") }
            root.layoutSubtreeIfNeeded()
            check(panel.frame.width == 765 && panel.frame.height == 472,"Centered glass dimensions")
            check(panel.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == appearance,"Follows window appearance")
            let labels = views(root).compactMap { ($0 as? NSTextField)?.stringValue }
            check(labels.contains("Rechercher avec DuckDuckGo") && labels.contains("café") && labels.contains("DuckDuckGo"),"Search and provider retain accents and chosen engine")
            check(labels.contains("Onglets ouverts") && labels.contains("Onglets archivés"),"Groups open and archived results")
            if #available(macOS 26.0, *) {
                check(views(root).contains { $0 is NSGlassEffectView },"Uses native Liquid Glass")
            }
            let editor = field.currentEditor() as? NSTextView ?? NSTextView()
            _ = command.control(field,textView:editor,doCommandBy:#selector(NSResponder.moveDown(_:)))
            _ = command.control(field,textView:editor,doCommandBy:#selector(NSResponder.insertNewline(_:)))
            check(actions.last == "tab","Keyboard selects an existing tab")
            let count = dismissals
            command.close()
            check(dismissals == count,"Dismissal runs once")
        }
        let command = palette(); command.show()
        let panel = parent.childWindows!.last!, root = panel.contentView!
        let field = views(root).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
        field.stringValue = "crème brûlée"
        command.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:field))
        _ = command.control(field,textView:NSTextView(),doCommandBy:#selector(NSResponder.insertNewline(_:)))
        check(actions.last == "search:crème brûlée","Typing searches the complete accented query")
        let cancelled = palette(); cancelled.show()
        let before = actions
        _ = cancelled.control(field,textView:NSTextView(),doCommandBy:#selector(NSResponder.cancelOperation(_:)))
        check(actions == before,"Escape never performs a suggestion")
        let compact = palette(centered:false); compact.show()
        check(parent.childWindows!.last!.frame.width == 420,"Address editing retains its compact layout")
        compact.close()
        parent.close()
        print("PASS \(checks) command palette checks")
    }
}
