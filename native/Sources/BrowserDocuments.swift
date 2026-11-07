// SPDX-License-Identifier: MPL-2.0
import Foundation
import UniformTypeIdentifiers

/// Finder, Dock drops and the open panel all supply file URLs (never search terms).
enum BrowserDocuments {
    static let contentTypes: [UTType] = [.html, .pdf, .svg, UTType("com.apple.web-internet-location")!]

    struct Batch {
        var addresses: [String] = []
        var unreadable: [String] = []
        var isEmpty: Bool { addresses.isEmpty && unreadable.isEmpty }

        mutating func append(_ urls: [URL]) {
            for url in urls {
                if url.isFileURL {
                    if let address = BrowserDocuments.address(for: url) { addresses.append(address) }
                    else { unreadable.append(url.lastPathComponent) }
                } else if let web = browserWebURL(url.absoluteString) { addresses.append(web.absoluteString) }
            }
        }
    }

    private static func address(for source: URL) -> String? {
        guard (source.host ?? "").isEmpty || source.host?.lowercased() == "localhost" else { return nil }
        let file = source.standardizedFileURL
        guard (try? file.resourceValues(forKeys:[.isRegularFileKey, .isReadableKey])).map({
            $0.isRegularFile == true && $0.isReadable == true
        }) == true else { return nil }
        if file.pathExtension.lowercased() != "webloc" {
            return isLocalTabDocument(file.absoluteString) ? file.absoluteString : nil
        }
        // A .webloc is a property list, not executable content. Keep malformed
        // or oversized shortcuts from opening another local path or scheme.
        let limit = 128 * 1024
        guard let handle = try? FileHandle(forReadingFrom:file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount:limit + 1), data.count <= limit,
              let plist = (try? PropertyListSerialization.propertyList(from:data,format:nil)) as? [String:Any],
              let target = plist["URL"] as? String else { return nil }
        return browserWebURL(target)?.absoluteString
    }
}
