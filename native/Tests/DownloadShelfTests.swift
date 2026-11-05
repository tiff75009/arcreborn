// SPDX-License-Identifier: MPL-2.0
import AppKit

@main enum DownloadShelfTests {
    static func main() throws {
        _ = NSApplication.shared
        let shelf = RecentMediaPeek(frame:.zero)
        var records = ["Palette.txt","Carnet du jour.txt","Essai rapide.txt","Essai rapide (1).txt"].enumerated().map { index,name in
            LibraryDownload(id:String(index),name:name,path:"/tmp/"+name,source:"",profileID:"test",
                            date:Date(timeIntervalSince1970:Double(index)),received:32768,total:32768,state:"complete")
        }
        func display(_ width:CGFloat) -> [DownloadCard] {
            shelf.frame.size.width = width
            shelf.update(files:[],downloads:records,ink:.white,language:"fr",loading:false)
            shelf.frame.size.height = shelf.desiredHeight
            shelf.layoutSubtreeIfNeeded()
            return shelf.subviews.compactMap { $0 as? DownloadCard }.sorted { $0.frame.minY < $1.frame.minY }
        }
        for width:CGFloat in [224,245,400] {
            let cards = display(width)
            precondition(shelf.desiredHeight == 168 && cards.count == 4)
            for (i,card) in cards.enumerated() {
                let labels = card.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden }
                precondition(labels.count == 2 && labels[0].stringValue == records[i].name)
                precondition(!labels[0].frame.intersects(labels[1].frame))
                precondition(labels[0].frame.width > 100 && !labels[1].stringValue.contains("/"))
                precondition(labels[1].stringValue.contains("ko") && labels[1].frame.width >= ceil(labels[1].attributedStringValue.size().width)+4)
            }
        }
        var invoked = ""
        shelf.transferAction = { id,action in invoked = id+":"+action }
        records[3].state = "progress"; records[3].received = 16000; records[3].speed = 8000
        let active = display(224).last!
        precondition(shelf.desiredHeight == 183)
        func action(_ label:String) -> NSButton { active.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == label && !$0.isHidden }! }
        action("Mettre en pause").performClick(nil); precondition(invoked == "3:pause")
        records[3].state = "paused"; _ = display(224)
        action("Reprendre").performClick(nil); precondition(invoked == "3:resume")
        action("Annuler le téléchargement").performClick(nil); precondition(invoked == "3:cancel")
        records[3].state = "complete"; _ = display(224)
        precondition(shelf.desiredHeight == 168)
        var openedAll = false
        shelf.showDownloads = { openedAll = true }
        let all = shelf.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Tous les téléchargements" }!
        all.performClick(nil); precondition(openedAll)
        print("PASS: compact download shelf heights, names, sizes, order and transfer controls")
    }
}
