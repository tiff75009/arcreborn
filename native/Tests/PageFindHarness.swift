// SPDX-License-Identifier: MPL-2.0
// swift native/Tests/PageFindHarness.swift "/path/to/Arc Reborn.app" [en]
import AppKit
import ApplicationServices

struct Failure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
func waitFor(_ description: String, _ condition: () -> Bool) throws {
    for _ in 0..<100 {
        if condition() { return }
        Thread.sleep(forTimeInterval: 0.06)
    }
    throw Failure(description)
}
func attribute(_ element: AXUIElement, _ key: String) -> AnyObject? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, key as CFString, &value)
    return value
}
func elements(_ root: AXUIElement, matching predicate: (AXUIElement) -> Bool) -> [AXUIElement] {
    if predicate(root) { return [root] }
    if attribute(root, "AXRole") as? String == "AXWebArea" { return [] }
    return (attribute(root, "AXChildren") as? [AXUIElement] ?? []).flatMap { elements($0, matching: predicate) }
}

func run() throws {
    guard CommandLine.arguments.count >= 2, AXIsProcessTrusted() else { throw Failure("Pass a development app and enable Accessibility for this test.") }
    let english = CommandLine.arguments.last == "en"
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("arc-find-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("lecture.html")
    let rows = (1...18).map { "<p style='min-height:180px'>\($0). Café</p>" }.joined()
    try ("<meta charset=utf-8><title>Lecture longue</title>" + rows).write(to: file, atomically: true, encoding: .utf8)
    let second = dir.appendingPathComponent("suite.html")
    try "<meta charset=utf-8><title>Autre lecture</title><p>Café</p>".write(to: second, atomically: true, encoding: .utf8)
    let state: [String: Any] = ["language": english ? "en" : "fr", "onboardingComplete": true, "sidebarWidth": 240, "sidebarHidden": false,
        "profiles":[["id":"p","name":"Essai"]], "spaces":[["id":"s","name":"Lecture","color":"#817BAF","icon":"✦","profileID":"p","selectedTabID":"t"]],
        "tabs":[["id":"t","spaceID":"s","title":"Chargement","url":file.absoluteString,"pinned":false,"favorite":false],
                ["id":"t2","spaceID":"s","title":"Suite","url":second.absoluteString,"pinned":false,"favorite":false]],
        "activeSpaceID":"s","closedTabs":[],"folders":[]]
    try JSONSerialization.data(withJSONObject: state).write(to: dir.appendingPathComponent("session.json"))
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Contents/MacOS/Arc Reborn")
    process.environment = ProcessInfo.processInfo.environment.merging(["BROWSER_NATIVE_TEST_DATA": dir.path]) { _, new in new }
    process.standardError = FileHandle.nullDevice
    try process.run()
    defer {
        if process.isRunning { _ = NSRunningApplication(processIdentifier:process.processIdentifier)?.terminate() }
        try? waitFor("exit") { !process.isRunning }
        if process.isRunning { process.terminate(); process.waitUntilExit() }
    }
    let ax = AXUIElementCreateApplication(process.processIdentifier)
    func window() -> AXUIElement? { (attribute(ax, "AXWindows") as? [AXUIElement])?.first }
    try waitFor("Local page did not load") { window().flatMap { attribute($0, "AXTitle") as? String } == "Lecture longue" }
    func key(_ code: CGKeyCode, _ flags: CGEventFlags = [], text: String? = nil) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource:nil, virtualKey:code, keyDown:down)!
            event.flags = flags
            if let text {
                let units = Array(text.utf16)
                event.keyboardSetUnicodeString(stringLength:units.count, unicodeString:units)
            }
            event.postToPid(process.processIdentifier)
        }
    }
    func hasText(_ text: String) -> Bool {
        guard let window = window() else { return false }
        return !elements(window) { attribute($0, "AXRole") as? String == "AXStaticText" && attribute($0, "AXValue") as? String == text }.isEmpty
    }
    func expect(_ index: Int, total: Int = 18) throws {
        let caption = english ? "\(index) of \(total)" : "\(index) sur \(total)"
        do { try waitFor("Missing counter: " + caption) { hasText(caption) } }
        catch {
            let labels = window().map { elements($0) { ["AXStaticText","AXTextField"].contains(attribute($0, "AXRole") as? String ?? "") } } ?? []
            throw Failure("Expected " + caption + ", found " + labels.compactMap { attribute($0, "AXValue") as? String }.joined(separator: " · "))
        }
        print("PASS",caption)
    }
    func focusedSearch() -> Bool {
        guard let focused = attribute(ax, "AXFocusedUIElement") else { return false }
        return attribute(focused as! AXUIElement, "AXSubrole") as? String == "AXSearchField"
    }
    key(3, .maskCommand)
    try waitFor("⌘F did not focus the search field", focusedSearch)
    key(0, text: "Café")
    try expect(1)
    key(36); try expect(2)
    key(5, .maskCommand); try expect(3)
    key(5, [.maskCommand, .maskShift]); try expect(2)
    key(36, .maskShift); try expect(1)
    key(5, [.maskCommand, .maskShift]); try expect(18)
    key(5, .maskCommand); try expect(1)
    key(53)
    try waitFor("Escape did not close the find bar") { !focusedSearch() && !hasText(english ? "1 of 18" : "1 sur 18") }
    key(5, .maskCommand); try expect(2)
    key(3, .maskCommand)
    try waitFor("⌘F did not refocus the search field", focusedSearch)
    if let window = window() {
        let matches = elements(window) { element in
            attribute(element, "AXRole") as? String == "AXButton" && ["AXDescription","AXHelp","AXTitle"].contains {
                attribute(element, $0) as? String == (english ? "Next" : "Suivant")
            }
        }
        guard let next = matches.last, AXUIElementPerformAction(next, kAXPressAction as CFString) == .success else { throw Failure("Cannot press the Next button") }
        try expect(3)
    }
    key(3, .maskCommand)
    key(0, text: "Introuvable")
    try expect(0, total: 0)
    key(3, .maskCommand); key(51)
    try waitFor("Empty query still shows results") { !hasText(english ? "0 of 0" : "0 sur 0") }
    key(0, text: "Café")
    try expect(1)
    key(125, [.maskCommand,.maskAlternate])
    try waitFor("Tab switch kept a stale counter") {
        window().flatMap { attribute($0, "AXTitle") as? String } == "Autre lecture" && !hasText(english ? "1 of 18" : "1 sur 18")
    }
    key(5, .maskCommand)
    try expect(1, total: 1)
}

do { try run() } catch { fputs((error.localizedDescription + "\n"), stderr); exit(1) }
