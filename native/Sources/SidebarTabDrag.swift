// SPDX-License-Identifier: MPL-2.0
import AppKit
import UniformTypeIdentifiers

enum SidebarTabDrag {
    static let tabType = NSPasteboard.PasteboardType("local.browser.tab")

    // NSPasteboardItem accepts the UTI, while WebKit's original format is a pasteboard tag.
    private static let webURLsWithTitles = UTType(tag: "WebURLsWithTitlesPboardType",
        tagClass: UTTagClass(rawValue: "com.apple.nspboard-type"), conformingTo: .data)
        .map { NSPasteboard.PasteboardType($0.identifier) }

    static func item(id: String, url: URL?, title: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(id, forType: tabType)
        guard let url else { return item }
        let address = url.absoluteString
        item.setString(address, forType: .URL)
        item.setString(title, forType: .init("public.url-name"))
        if let webURLsWithTitles {
            item.setPropertyList([[address], [title]], forType: webURLsWithTitles)
        }
        item.setString(address, forType: .string)
        return item
    }

    static func operation(in context: NSDraggingContext, pasteboard: NSPasteboard) -> NSDragOperation {
        if context == .withinApplication { return .move }
        return pasteboard.availableType(from: [.URL]) == nil ? [] : .copy
    }
}
