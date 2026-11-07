// SPDX-License-Identifier: MPL-2.0
import AppKit

@main struct SidebarTabDragTests {
    static func main() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let url = URL(string: "https://example.org/r%C3%A9sum%C3%A9?x=1&y=2#section")!
        let title = "Résumé et nouvelles"
        let item = SidebarTabDrag.item(id: "tab-A", url: url, title: title)
        precondition(board.writeObjects([item]))
        precondition(board.pasteboardItems?.count == 1)
        precondition(board.string(forType: SidebarTabDrag.tabType) == "tab-A")
        precondition(NSURL(from: board) as URL? == url)
        precondition(board.string(forType: .string) == url.absoluteString)
        precondition(board.string(forType: .init("public.url-name")) == title)
        precondition(board.propertyList(forType: .init("WebURLsWithTitlesPboardType")) as? [[String]] == [[url.absoluteString], [title]])
        precondition(SidebarTabDrag.operation(in: .withinApplication, pasteboard: board) == .move)
        precondition(SidebarTabDrag.operation(in: .outsideApplication, pasteboard: board) == .copy)

        board.clearContents()
        precondition(board.writeObjects([SidebarTabDrag.item(id: "local", url: nil, title: "Local")]))
        precondition(board.string(forType: SidebarTabDrag.tabType) == "local")
        precondition(board.availableType(from: [.URL, .string, .fileURL]) == nil)
        precondition(SidebarTabDrag.operation(in: .withinApplication, pasteboard: board) == .move)
        precondition(SidebarTabDrag.operation(in: .outsideApplication, pasteboard: board).isEmpty)
        print("PASS: one native URL, title and text, internal move, external copy, local-only drag")
    }
}
