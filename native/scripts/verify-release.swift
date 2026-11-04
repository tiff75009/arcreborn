// SPDX-License-Identifier: MPL-2.0
// Public-key-only verification: never opens the signing key or macOS Keychain.
import Foundation
import CryptoKit

enum VerificationError: Error { case invalid(String) }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw VerificationError.invalid(message) }
}
final class Feed: NSObject, XMLParserDelegate {
    var enclosures: [[String: String]] = []
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "enclosure" { enclosures.append(attributes) }
    }
}
do {
    try require(CommandLine.arguments.count == 3, "Usage: verify-release.swift Info.plist assets-directory")
    let infoURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let assets = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any]
    guard let encoded = info?["SUPublicEDKey"] as? String, let rawKey = Data(base64Encoded: encoded) else {
        throw VerificationError.invalid("Missing public key")
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
    let feedData = try Data(contentsOf: assets.appendingPathComponent("appcast.xml"))
    guard let xml = String(data: feedData, encoding: .utf8) else { throw VerificationError.invalid("Invalid XML encoding") }
    let pattern = "<!-- sparkle-signatures:\\nedSignature: ([A-Za-z0-9+/=]+)\\nlength: ([0-9]+)\\n-->\\s*$"
    let regex = try NSRegularExpression(pattern: pattern)
    guard let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
          let signatureRange = Range(match.range(at: 1), in: xml),
          let lengthRange = Range(match.range(at: 2), in: xml),
          let footerRange = Range(match.range, in: xml),
          let signature = Data(base64Encoded: String(xml[signatureRange])),
          let length = Int(xml[lengthRange]) else { throw VerificationError.invalid("Missing feed signature") }
    try require(length == xml[..<footerRange.lowerBound].utf8.count, "Unsigned content before signature footer")
    let signedFeed = feedData.prefix(length)
    try require(key.isValidSignature(signature, for: signedFeed), "Invalid feed signature")
    let feed = Feed(), parser = XMLParser(data: signedFeed)
    parser.delegate = feed; parser.shouldResolveExternalEntities = false
    try require(parser.parse() && feed.enclosures.count == 1, "Expected one signed update enclosure")
    let item = feed.enclosures[0]
    guard let address = item["url"], let url = URL(string: address),
          let size = item["length"].flatMap(Int.init),
          let archiveSignature = item["sparkle:edSignature"].flatMap({ Data(base64Encoded: $0) }) else {
        throw VerificationError.invalid("Invalid archive metadata")
    }
    let archive = try Data(contentsOf: assets.appendingPathComponent(url.lastPathComponent), options: .mappedIfSafe)
    try require(archive.count == size && key.isValidSignature(archiveSignature, for: archive), "Invalid update archive signature or size")
    print("PASS: feed and update archive verified using only the public key")
} catch {
    fputs("Release verification failed: \(error)\n", stderr)
    exit(1)
}
