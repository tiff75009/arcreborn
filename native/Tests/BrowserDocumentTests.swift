// SPDX-License-Identifier: MPL-2.0
import Foundation
import UniformTypeIdentifiers

@main struct BrowserDocumentTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        func write(_ name:String, _ bytes:Data = Data()) throws -> URL {
            let url = directory.appendingPathComponent(name); try bytes.write(to:url); return url.standardizedFileURL
        }
        func shortcut(_ name:String, _ address:String, _ format:PropertyListSerialization.PropertyListFormat) throws -> URL {
            try write(name,PropertyListSerialization.data(fromPropertyList:["URL":address],format:format,options:0))
        }
        let docs = try ["Café & thé #1.HTML","Page.htm","100%.pdf","Schéma.SvG"].map { try write($0) }
        let web = "https://example.org/caf%C3%A9?x=1#lecture"
        let xml = try shortcut("Lien.webloc",web,.xml), binary = try shortcut("Autre.WEBLOC",web,.binary)
        let invalid = try [write("Cassé.webloc",Data("not a plist".utf8)), shortcut("Local.webloc",docs[0].absoluteString,.xml),
                           shortcut("Action.webloc","javascript:void(0)",.binary), write("Gros.webloc",Data(count:131073)),
                           write("notes.txt"), write("exemple.svgz")] + [directory,directory.appendingPathComponent("Absent.pdf")]
        var batch = BrowserDocuments.Batch()
        batch.append(docs + [xml,URL(string:web)!,binary] + invalid)
        precondition(batch.addresses == docs.map(\.absoluteString) + [web,web,web])
        precondition(batch.unreadable == invalid.map(\.lastPathComponent))
        precondition(["file://serveur/partage/page.html","file:////serveur/page.htm","file:///tmp/%00.svg","file:///tmp/","file:///etc/hosts"].allSatisfy { !isLocalTabDocument($0) })
        var session = BrowserSession.fresh()
        let id = session.createTab(url:docs[0].absoluteString)
        precondition(!id.isEmpty && session.tabs.last?.displayTitle == docs[0].lastPathComponent)
        session.closeTab(id:id); try FileManager.default.removeItem(at:docs[0])
        precondition(session.validated() && session.closedTabs.last?.url == docs[0].absoluteString)
        precondition(browserWebURL(docs[1].absoluteString) == nil && !isAllowedBrowserURL(docs[1].absoluteString))
        let plist = try PropertyListSerialization.propertyList(from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])),format:nil) as! [String:Any]
        let documents = (plist["CFBundleDocumentTypes"] as! [[String:Any]]).filter {
            $0["CFBundleTypeRole"] as? String == "Viewer" && $0["LSHandlerRank"] as? String == "Alternate"
        }
        precondition(Set(documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }) == Set(BrowserDocuments.contentTypes.map(\.identifier)))
        precondition(["html","htm","pdf","svg","webloc"].allSatisfy { ext in BrowserDocuments.contentTypes.contains { UTType(filenameExtension:ext)?.conforms(to:$0) == true } })
        print("PASS Finder registration, ordered mixed files, XML/binary shortcuts, rejected inputs and offline session restore")
    }
}
