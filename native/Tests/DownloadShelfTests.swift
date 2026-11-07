// SPDX-License-Identifier: MPL-2.0
import AppKit

@main enum DownloadShelfTests {
    static func main() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("arc-shelf-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let shelf = RecentMediaPeek(frame:.zero)
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:400),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView?.addSubview(shelf)
        var records = try ["Palette.txt","Carnet du jour.txt","Essai rapide.txt","Essai rapide (1).txt"].enumerated().map { index,name in
            let file = root.appendingPathComponent(name)
            try Data("Fichier d’essai, été.\n".utf8).write(to:file)
            return LibraryDownload(id:String(index),name:name,path:file.path,source:"",profileID:"test",
                            date:Date().addingTimeInterval(Double(index-4)*3600),received:32768,total:32768,state:"complete")
        }
        func display(_ width:CGFloat, language:String = "fr") -> [RecentFileRow] {
            shelf.frame.size.width = width
            shelf.update(files:RecentLibraryFile.collect(media:[],downloads:records),downloads:records,ink:.white,language:language,loading:false)
            shelf.frame.size.height = shelf.desiredHeight; shelf.layoutSubtreeIfNeeded(); shelf.layout()
            return shelf.subviews.compactMap { $0 as? RecentFileRow }.sorted { $0.frame.minY < $1.frame.minY }
        }
        for width:CGFloat in [224,245,400] {
            let rows = display(width)
            precondition(shelf.desiredHeight == 232 && rows.count == 4)
            for (i,row) in rows.enumerated() {
                let labels = row.subviews.compactMap { $0 as? NSTextField }
                precondition(labels.count == 2 && labels[0].stringValue == records[i].name)
                precondition(!labels[0].frame.intersects(labels[1].frame) && labels[0].frame.width > 140)
                precondition(labels[1].stringValue.contains("il y a"))
                let image = row.subviews.compactMap { $0 as? NSImageView }.first!
                precondition(image.frame.width == 40 && image.frame.maxX < labels[0].frame.minX)
            }
        }
        precondition(shelf.layer?.backgroundColor == nil && shelf.layer?.borderWidth == 0)
        precondition(!shelf.subviews.contains { $0 is NSButton },"no framed group or footer below the four files")
        var invoked = ""
        shelf.transferAction = { id,action in invoked = id+":"+action }
        let original = display(224).last!
        records[3].state = "progress"; records[3].received = 16000; records[3].speed = 8000
        let active = display(224).last!
        precondition(original === active && shelf.desiredHeight == 232,"stable rows when a transfer changes state")
        func action(_ label:String) -> NSButton { active.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == label && $0.isEnabled }! }
        action("Mettre en pause").performClick(nil); precondition(invoked == "3:pause")
        records[3].state = "paused"; _ = display(224)
        action("Reprendre").performClick(nil); precondition(invoked == "3:resume")
        action("Annuler le téléchargement").performClick(nil); precondition(invoked == "3:cancel")
        records[3].state = "complete"; let rows = display(224)
        precondition(rows.last === active && rows.count == 4)
        shelf.setPresented(true,animated:false)
        precondition(shelf.hitTest(NSPoint(x:1,y:1)) === shelf,"blank shelf space intercepts input")
        let label = rows[0].subviews.compactMap { $0 as? NSTextField }.first!
        let point = shelf.superview!.convert(NSPoint(x:label.frame.midX,y:label.frame.midY),from:rows[0])
        precondition(shelf.hitTest(point) === rows[0],"file labels are clickable rows")
        shelf.setPresented(false,animated:false); shelf.setPresented(true)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let times = rows.map { $0.layer!.animation(forKey:"shelf-reveal")!.beginTime }
            precondition(times[0] > times[1] && times[1] > times[2] && times[2] > times[3],"reveal travels from bottom to top")
            shelf.setPresented(false); shelf.setPresented(true)
            RunLoop.main.run(until:Date().addingTimeInterval(0.25))
            precondition(!shelf.isHidden,"an old close cannot hide a reopened shelf")
        }
        _ = display(224,language:"en")
        precondition(rows[0].subviews.compactMap { $0 as? NSTextField }.last!.stringValue.contains("ago"))
        records[3].state = "blocked"; records[3].path = ""
        let warning = display(224).first { $0.accessibilityLabel()?.contains("Bloqué pour votre sécurité") == true }!
        precondition(!warning.accessibilityPerformPress(),"a blocked transfer cannot open a preview")
        precondition(display(224,language:"en").contains { $0.accessibilityLabel()?.contains("Blocked for your safety") == true })
        let basket = LibraryBasketArtwork()
        let tray = basket.sublayers!.first!
        let frame = tray.frame
        basket.setExpanded(true,animated:true); basket.setExpanded(false,animated:true)
        precondition(tray.frame == frame && CATransform3DIsIdentity(tray.transform) && (tray.animationKeys() ?? []).isEmpty,"the basket base never jumps or scales")
        print("PASS: four thumbnail rows, FR/EN dates, transfer controls, stable completion, input interception, stagger and reversal, fixed basket base")
    }
}
