import AppKit

/// A snapshot of the sidebar tree. Previewing a folder never wakes its tabs.
private struct PeekItem {
    let id: SidebarItem
    let title: String
    let detail: String
    let address: String
}

private struct FolderPeekContents {
    var children = [String:[PeekItem]]()

    init(_ session: BrowserSession, root: NativeFolder) {
        let folders = Dictionary(uniqueKeysWithValues:session.folders.map { ($0.id,$0) })
        let tabs = Dictionary(uniqueKeysWithValues:session.tabs.map { ($0.id,$0) })
        var pending = [root]
        while let folder = pending.popLast() {
            guard children[folder.id] == nil else { continue }
            let items = folder.liveHost == nil ? session.sidebarChildren(spaceID:folder.spaceID,parentID:folder.id)
                          : session.tabs(in:folder).map { SidebarItem.tab($0.id) }
            children[folder.id] = items.compactMap { item in
                switch item {
                case .folder(let id):
                    guard let child = folders[id] else { return nil }
                    pending.append(child)
                    return PeekItem(id:item,title:child.name,detail:"",address:"")
                case .tab(let id):
                    guard let tab = tabs[id] else { return nil }
                    let host = URL(string:tab.url)?.host ?? tab.url
                    return PeekItem(id:item,title:tab.displayTitle.isEmpty ? host : tab.displayTitle,detail:host,address:tab.url)
                }
            }
        }
    }

    func results(in folder:String, query:String) -> [PeekItem] {
        let query = query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty else { return children[folder] ?? [] }
        var pending = Array((children[folder] ?? []).reversed()), seen = Set<SidebarItem>(), result = [PeekItem]()
        while let item = pending.popLast() {
            guard seen.insert(item.id).inserted else { continue }
            if item.title.localizedStandardContains(query) || item.address.localizedStandardContains(query) { result.append(item) }
            if case .folder(let id) = item.id { pending.append(contentsOf:(children[id] ?? []).reversed()) }
        }
        return result
    }
}

private final class PeekWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class PeekSurface: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event:NSEvent) {}
    override func rightMouseDown(with event:NSEvent) {}
}

private final class PeekRow: NSTableRowView {
    private var tracking: NSTrackingArea?
    private var hover = false { didSet { needsDisplay = true } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self)
        addTrackingArea(area); tracking = area
        if let window { hover = visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream,from:nil)) }
    }
    override func mouseEntered(with event:NSEvent) { hover = true }
    override func mouseExited(with event:NSEvent) { hover = false }
    override func drawBackground(in dirtyRect:NSRect) { if hover { fill(0.095) } }
    override func drawSelection(in dirtyRect:NSRect) { fill(0.13) }
    private func fill(_ opacity:CGFloat) {
        NSColor.white.withAlphaComponent(opacity).setFill()
        NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:1),xRadius:7,yRadius:7).fill()
    }
}

private final class PeekCell: NSTableCellView {
    let icon = NSImageView(), name = NSTextField(labelWithString:""), detail = NSTextField(labelWithString:""), arrow = NSImageView()
    override init(frame:NSRect) {
        super.init(frame:frame)
        name.font = .systemFont(ofSize:13,weight:.medium); name.textColor = .white.withAlphaComponent(0.92)
        detail.font = .systemFont(ofSize:11); detail.textColor = .white.withAlphaComponent(0.52)
        for label in [name,detail] { label.lineBreakMode = .byTruncatingTail; label.maximumNumberOfLines = 1 }
        icon.imageScaling = .scaleProportionallyDown
        arrow.image = NSImage(systemSymbolName:"chevron.right",accessibilityDescription:nil)
        arrow.contentTintColor = .white.withAlphaComponent(0.36)
        for view in [icon,name,detail,arrow] { addSubview(view) }
    }
    required init?(coder:NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height, width = max(10,w-49-(arrow.isHidden ? 0 : 12))
        icon.frame = NSRect(x:12,y:(h-17)/2,width:17,height:17)
        // NSTableCellView uses an unflipped coordinate system.
        name.frame = NSRect(x:39,y:detail.isHidden ? (h-17)/2 : h/2-1,width:width,height:17)
        detail.frame = NSRect(x:39,y:h/2-16,width:width,height:15)
        arrow.frame = NSRect(x:w-21,y:(h-10)/2,width:9,height:10)
    }
}

final class FolderPeek: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let panel = PeekWindow(contentRect:.zero,styleMask:[.borderless],backing:.buffered,defer:false)
    // The child window owns input throughout the animation. Only its card moves.
    private let stage = NSView()
    private var attachment = NSRect.zero
    private var motionGeneration = 0
    private let surface = PeekSurface(), search = NSTextField(), lead = NSButton(), separator = NSBox()
    private let scroll = NSScrollView(), list = NSTableView(), column = NSTableColumn(identifier:.init("entry"))
    private let empty = NSTextField(labelWithString:"")
    private var contents: FolderPeekContents
    private var path: [(id:String,name:String)]
    private var items = [PeekItem]()
    private let french: Bool
    private let artwork: (String) -> NSImage?
    private let openTab: (String) -> Void
    private var monitor: Any?
    private var closing = false
    weak var parent: NSWindow?
    var pointerChanged: (() -> Void)?
    var dismiss: (() -> Void)?
    func containsPointer(_ point:NSPoint) -> Bool {
        // The table has a trailing inset. Cover that space and the visual gap
        // to the card so users can cross slowly without restarting the hover.
        let bridge = NSRect(x:attachment.maxX-15,y:attachment.minY,
                            width:max(15,panel.frame.minX-attachment.maxX+16),height:attachment.height)
        return panel.frame.contains(point) || bridge.contains(point)
    }
    var isKey: Bool { panel.isKeyWindow }
    private(set) var folderID: String

    init?(session:BrowserSession,folder:NativeFolder,artwork:@escaping (String)->NSImage?,open:@escaping (String)->Void) {
        contents = FolderPeekContents(session,root:folder)
        guard contents.children[folder.id]?.isEmpty == false else { return nil }
        folderID = folder.id; path = [(folder.id,folder.name)]; french = session.language != "en"
        self.artwork = artwork; openTab = open
        super.init()
        panel.isReleasedWhenClosed = false; panel.hasShadow = true; panel.backgroundColor = .clear; panel.isOpaque = false
        panel.isMovable = false; panel.hidesOnDeactivate = false; panel.animationBehavior = .none
        panel.appearance = NSAppearance(named:.darkAqua); panel.acceptsMouseMovedEvents = true
        panel.title = folder.name; panel.contentView = stage
        stage.wantsLayer = true; stage.addSubview(surface)
        surface.wantsLayer = true
        surface.layer?.backgroundColor = NSColor(srgbRed:0.090,green:0.090,blue:0.101,alpha:1).cgColor
        surface.layer?.cornerRadius = 12; surface.layer?.cornerCurve = .continuous
        surface.layer?.masksToBounds = true; surface.layer?.borderWidth = 1
        surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.17).cgColor
        lead.isBordered = false; lead.imagePosition = .imageOnly; lead.target = self; lead.action = #selector(goBack)
        lead.contentTintColor = .white.withAlphaComponent(0.58); lead.focusRingType = .none
        search.isBezeled = false; search.drawsBackground = false; search.focusRingType = .none
        search.font = .systemFont(ofSize:14,weight:.medium); search.textColor = .white
        search.cell?.usesSingleLineMode = true; search.cell?.isScrollable = true
        search.delegate = self
        separator.boxType = .separator
        empty.textColor = .secondaryLabelColor; empty.font = .systemFont(ofSize:13); empty.alignment = .center
        list.headerView = nil; list.backgroundColor = .clear; list.intercellSpacing = .zero
        list.style = .plain; list.rowHeight = 42; list.focusRingType = .none
        list.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        list.allowsColumnResizing = false; list.allowsEmptySelection = true
        list.addTableColumn(column); list.delegate = self; list.dataSource = self
        list.target = self; list.action = #selector(clicked)
        scroll.documentView = list; scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true; scroll.drawsBackground = false; scroll.borderType = .noBorder
        for view in [lead,search,separator,scroll,empty] { surface.addSubview(view) }
    }

    private func targetFrame(anchor:NSRect,available:NSRect) -> NSRect {
        let count = contents.children[folderID]?.count ?? 1
        let width = min(300,available.maxX-anchor.maxX-14)
        let height = min(available.height-16,54+42*CGFloat(min(7,max(2,count))))
        let y = min(available.maxY-height-8,max(available.minY+8,anchor.midY-height/2))
        attachment = anchor
        return NSRect(x:anchor.maxX+5,y:y,width:width,height:height).integral
    }

    private func compactFrame(_ rect:NSRect) -> NSRect {
        let scale:CGFloat = 0.90
        return NSRect(x:rect.minX,y:attachment.midY+(rect.minY-attachment.midY)*scale,
                      width:rect.width*scale,height:rect.height*scale)
    }

    private func layoutCard() {
        let width = surface.bounds.width, height = surface.bounds.height
        lead.frame = NSRect(x:9,y:9,width:27,height:28)
        search.frame = NSRect(x:41,y:14,width:width-53,height:21)
        separator.frame = NSRect(x:0,y:45,width:width,height:1)
        scroll.frame = NSRect(x:5,y:50,width:width-10,height:height-55)
        column.width = scroll.contentSize.width
        empty.frame = NSRect(x:9,y:scroll.frame.midY-9,width:width-18,height:20)
    }

    /// Capture a transition mid-flight before moving the host to its next frame.
    private var displayedFrame: NSRect {
        let local = surface.layer?.presentation()?.frame ?? surface.frame
        return panel.convertToScreen(stage.convert(local,to:nil))
    }

    // Interpolate the outline and the attachment point independently. The text
    // keeps its native size even when a three-row folder changes to seven rows.
    private func converge(from:NSRect,to:NSRect,opening:Bool) {
        motionGeneration += 1
        let generation = motionGeneration
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let host = reduced ? to : from.union(to).integral
        CATransaction.begin(); CATransaction.setDisableActions(true)
        panel.setFrame(host,display:false)
        let local = to.offsetBy(dx:-host.minX,dy:-host.minY)
        surface.frame = local; layoutCard(); surface.layoutSubtreeIfNeeded()
        CATransaction.commit()
        guard !reduced, let layer = surface.layer else { panel.invalidateShadow(); return }

        let start = from.offsetBy(dx:-host.minX,dy:-host.minY)
        let pin = layer.anchorPoint
        let oldPosition = CGPoint(x:layer.position.x+start.minX-local.minX+(start.width-local.width)*pin.x,
                                  y:layer.position.y+start.minY-local.minY+(start.height-local.height)*pin.y)
        func spring(_ property:String,_ initial:Any,_ end:Any) -> CASpringAnimation {
            let spring = CASpringAnimation(keyPath:property)
            spring.mass = 1; spring.stiffness = opening ? 340 : 420
            spring.damping = opening ? 34 : 40
            spring.fromValue = initial; spring.toValue = end; spring.duration = spring.settlingDuration
            return spring
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, !self.closing, self.motionGeneration == generation else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self.panel.setFrame(to,display:false); self.surface.frame = self.stage.bounds
            self.panel.invalidateShadow(); CATransaction.commit()
        }
        layer.add(spring("bounds.size",NSValue(size:start.size),NSValue(size:local.size)),forKey:"peek.size")
        layer.add(spring("position",NSValue(point:oldPosition),NSValue(point:layer.position)),forKey:"peek.position")
        if opening {
            let fade = CABasicAnimation(keyPath:"opacity")
            fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.17
            fade.timingFunction = CAMediaTimingFunction(name:.easeOut)
            layer.add(fade,forKey:"peek.opacity")
        }
        CATransaction.commit()
    }

    func replace(with folder:NativeFolder,session:BrowserSession,anchor:NSRect,available:NSRect) -> Bool {
        let next = FolderPeekContents(session,root:folder)
        guard next.children[folder.id]?.isEmpty == false else { return false }
        let old = displayedFrame
        contents = next; folderID = folder.id; path = [(folder.id,folder.name)]
        panel.title = folder.name; search.stringValue = ""
        transitionList(forward:nil); rebuild()
        converge(from:old,to:targetFrame(anchor:anchor,available:available),opening:false)
        return true
    }

    private func transitionList(forward:Bool?) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        scroll.wantsLayer = true
        let change = CATransition()
        change.type = forward == nil ? .fade : .push
        change.subtype = forward == false ? .fromLeft : .fromRight
        change.duration = forward == nil ? 0.15 : 0.20
        change.timingFunction = CAMediaTimingFunction(controlPoints:0.2,0.72,0.24,1)
        scroll.layer?.add(change,forKey:"peek.contents")
    }

    func show(parent:NSWindow,anchor:NSRect,available:NSRect) {
        self.parent = parent
        let target = targetFrame(anchor:anchor,available:available)
        panel.setFrame(target,display:false)
        rebuild()
        converge(from:compactFrame(target),to:target,opening:true)
        parent.addChildWindow(panel,ordered:.above); panel.orderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching:[.mouseMoved,.mouseEntered,.mouseExited,.leftMouseDragged,.leftMouseDown,.rightMouseDown,.otherMouseDown,.scrollWheel,.keyDown]) { [weak self] event in
            guard let self, !self.closing else { return event }
            if event.type == .keyDown { return self.handleKey(event) ? nil : event }
            if event.window === self.panel { self.pointerChanged?(); return event }
            if [.leftMouseDown,.rightMouseDown,.otherMouseDown,.scrollWheel].contains(event.type), let window = event.window {
                let point = window.convertPoint(toScreen:event.locationInWindow)
                if window === parent && self.panel.frame.contains(point) { return nil }
                if event.type != .scrollWheel { self.dismiss?() }
            }
            return event
        }
    }

    private func handleKey(_ event:NSEvent) -> Bool {
        guard event.window === panel || event.window === parent else { return false }
        if event.keyCode == 53 { dismiss?(); return true }
        if event.window === parent && !containsPointer(NSEvent.mouseLocation) && !attachment.contains(NSEvent.mouseLocation) { return false }
        guard event.modifierFlags.intersection([.command,.control,.function]).isEmpty else { return false }
        if event.keyCode == 36 { activate(list.selectedRow >= 0 ? list.selectedRow : 0); return true }
        if event.window === parent, let chars = event.characters, !chars.isEmpty,
           chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            panel.makeKey(); panel.makeFirstResponder(search)
            search.currentEditor()?.interpretKeyEvents([event]); return true
        }
        return false
    }

    func controlTextDidChange(_ notification:Notification) { rebuild() }
    func control(_ control:NSControl,textView:NSTextView,doCommandBy command:Selector) -> Bool {
        let delta: Int
        if command == #selector(NSResponder.moveDown(_:)) { delta = 1 }
        else if command == #selector(NSResponder.moveUp(_:)) { delta = -1 }
        else { return false }
        guard !items.isEmpty else { return true }
        let row = max(0,min(items.count-1,list.selectedRow+delta))
        list.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false); list.scrollRowToVisible(row)
        return true
    }
    private func rebuild() {
        guard let current = path.last else { return }
        let placeholder = (french ? "Rechercher dans " : "Search ") + current.name
        search.placeholderString = placeholder; search.setAccessibilityLabel(placeholder)
        let back = path.count > 1
        lead.image = NSImage(systemSymbolName:back ? "chevron.left" : "magnifyingglass",accessibilityDescription:nil)
        lead.setAccessibilityLabel(back ? (french ? "Retour" : "Back") : placeholder)
        items = contents.results(in:current.id,query:search.stringValue)
        list.reloadData(); empty.isHidden = !items.isEmpty
        empty.stringValue = search.stringValue.isEmpty ? (french ? "Ce dossier est vide" : "This folder is empty") : (french ? "Aucun résultat" : "No results")
        list.deselectAll(nil); scroll.contentView.scroll(to:.zero); scroll.reflectScrolledClipView(scroll.contentView)
        if !items.isEmpty && !search.stringValue.isEmpty { list.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false) }
    }
    @objc private func goBack() {
        if path.count > 1 { transitionList(forward:false); path.removeLast(); search.stringValue = ""; rebuild() }
        else { panel.makeKey(); panel.makeFirstResponder(search) }
    }
    @objc private func clicked() { activate(list.clickedRow) }
    private func activate(_ row:Int) {
        guard items.indices.contains(row) else { return }
        let item = items[row]
        switch item.id {
        case .tab(let id): openTab(id)
        case .folder(let id):
            guard !path.contains(where:{ $0.id == id }) else { return }
            transitionList(forward:true); path.append((id,item.title)); search.stringValue = ""; rebuild()
        }
    }

    func numberOfRows(in tableView:NSTableView) -> Int { items.count }
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int) -> NSTableRowView? { PeekRow() }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        guard items.indices.contains(row) else { return nil }
        let item = items[row], cellID = NSUserInterfaceItemIdentifier("peekCell")
        let cell = tableView.makeView(withIdentifier:cellID,owner:self) as? PeekCell ?? PeekCell(frame:.zero)
        cell.identifier = cellID; cell.name.stringValue = item.title
        switch item.id {
        case .folder:
            cell.arrow.isHidden = false; cell.detail.isHidden = true
            cell.icon.image = NSImage(systemSymbolName:"folder",accessibilityDescription:nil)
        case .tab(let id):
            cell.arrow.isHidden = true; cell.detail.isHidden = item.detail.isEmpty; cell.detail.stringValue = item.detail
            cell.icon.image = artwork(id) ?? NSImage(systemSymbolName:"globe",accessibilityDescription:nil)
        }
        cell.icon.contentTintColor = cell.icon.image?.isTemplate == true ? .secondaryLabelColor : nil
        cell.needsLayout = true; return cell
    }
    func close(animated:Bool) {
        guard !closing else { return }; closing = true
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        let panel = panel
        let finish = { [weak parent] in parent?.removeChildWindow(panel); panel.orderOut(nil) }
        if panel.isKeyWindow && NSApp.isActive { parent?.makeKey() }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = surface.layer {
            let current = displayedFrame, end = compactFrame(current)
            let visibleOpacity = layer.presentation()?.opacity ?? 1
            let position = layer.presentation()?.position ?? layer.position
            let pin = layer.anchorPoint
            let fade = CABasicAnimation(keyPath:"opacity")
            fade.fromValue = visibleOpacity; fade.toValue = 0
            let size = CABasicAnimation(keyPath:"bounds.size")
            size.fromValue = NSValue(size:current.size); size.toValue = NSValue(size:end.size)
            let offset = CABasicAnimation(keyPath:"position")
            offset.fromValue = NSValue(point:position)
            offset.toValue = NSValue(point:NSPoint(x:position.x+end.minX-current.minX+(end.width-current.width)*pin.x,
                                                  y:position.y+end.minY-current.minY+(end.height-current.height)*pin.y))
            CATransaction.begin(); CATransaction.setCompletionBlock(finish)
            let exit = CAAnimationGroup(); exit.animations = [fade,size,offset]
            exit.duration = 0.15; exit.fillMode = .forwards; exit.isRemovedOnCompletion = false
            exit.timingFunction = CAMediaTimingFunction(controlPoints:0.35,0,0.70,1)
            layer.removeAnimation(forKey:"peek.position"); layer.removeAnimation(forKey:"peek.size")
            layer.removeAnimation(forKey:"peek.opacity"); layer.add(exit,forKey:"peek.exit")
            CATransaction.commit()
        } else { finish() }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
