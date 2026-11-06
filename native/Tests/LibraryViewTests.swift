// SPDX-License-Identifier: MPL-2.0
import AppKit

@main enum LibraryViewTests {
    static func main() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("browser-library-view-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = LibraryStore(directory:root,downloadsDirectory:root)
        let session = BrowserSession.fresh()
        func open() -> LibraryView {
            let view = LibraryView(store:store,session:session)
            view.frame = NSRect(x:0,y:0,width:850,height:760)
            view.layoutSubtreeIfNeeded()
            return view
        }
        func buttons(_ view:NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        for (section,key) in [(LibrarySection.downloads,"downloads"),(.spaces,"spaces"),(.archived,"archivedTabs"),(.media,"media")] {
            let view = open()
            let button = buttons(view).first { $0.title == L10n.text(key,language:"fr") }!
            button.performClick(nil)
            precondition(view.section == section && store.lastSection == section)
            view.dispose()
            let reopened = open()
            precondition(reopened.section == section,"reopening restores the section selected through the real button")
            precondition(reopened.expanded == (section == .spaces),"spaces restores its expanded layout")
            reopened.switchSection(.notes)
            precondition(reopened.section == section && store.lastSection == section,"disabled notes cannot change the saved destination")
            reopened.dispose()
        }
        let existing = open()
        let secondWindow = LibraryStore(directory:root,downloadsDirectory:root)
        secondWindow.rememberSection(.archived)
        precondition(existing.section == .media,"another window must not navigate an already open library")
        existing.dispose()
        let reopened = open()
        precondition(reopened.section == .archived,"next reopening adopts the latest user choice")
        reopened.dispose(); store.flush()
        var archivedSession = session
        archivedSession.closedTabs = (0..<3).map { i in
            NativeTab(id:"archived-\(i)",spaceID:session.activeSpaceID,url:"https://example.test/\(i)",title:"Café \(i)",pinned:false,favorite:false,autoArchivedAt:i == 1 ? Date() : nil)
        }
        let favicon = NSImage(size:NSSize(width:16,height:16),flipped:false) { rect in NSColor.systemPink.setFill(); rect.fill(); return true }
        var requested:[String] = []
        let archiveView = LibraryView(store:store,session:archivedSession,archivedIcon:{ tab in
            requested.append(tab.id)
            return tab.id == "archived-2" ? nil : favicon
        })
        archiveView.frame = NSRect(x:0,y:0,width:850,height:760); archiveView.layoutSubtreeIfNeeded()
        func collection(_ view:NSView) -> NSCollectionView? { (view as? NSCollectionView) ?? view.subviews.compactMap(collection).first }
        let list = collection(archiveView)!
        for index in 0..<3 {
            let item = archiveView.collectionView(list,itemForRepresentedObjectAt:IndexPath(item:index,section:0))
            let picture = item.view.subviews.compactMap { $0 as? NSImageView }.first!
            precondition(picture.image != nil && !picture.isHidden,"archive always has a visible icon or fallback")
            if index > 0 { precondition(picture.image === favicon,"both manually and automatically archived tabs show their actual favicon") }
        }
        precondition(Set(requested) == Set(archivedSession.closedTabs.map(\.id)))
        precondition(archivedSession.tabs.isEmpty,"reading archive artwork does not reopen tabs")
        archiveView.dispose()
        print("PASS: actual library buttons, close/reopen of all four sections, spaces layout, disabled notes and independent open windows")
        print("PASS: manual/automatic archive favicons and missing-icon fallback")
    }
}
