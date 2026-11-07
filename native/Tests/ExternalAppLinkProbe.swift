// SPDX-License-Identifier: MPL-2.0
import AppKit
import ApplicationServices

// In the fixture bundle, record only URLs delivered to its unique test scheme.
final class Receiver: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("received.json")
        try? JSONEncoder().encode(urls.map(\.absoluteString)).write(to: output, options: .atomic)
        application.terminate(nil)
    }
}

func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name, &value)
    return value
}

// Only examine a sheet belonging to the isolated test process.
func inspect(_ element: AXUIElement, button: String?) {
    let role = attribute(element, kAXRoleAttribute as CFString) as? String
    if role == kAXStaticTextRole || role == kAXButtonRole {
        let text = (attribute(element, kAXTitleAttribute as CFString) as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? attribute(element, kAXValueAttribute as CFString) as? String ?? ""
        print(text)
        if role == kAXButtonRole, text == button {
            exit(AXUIElementPerformAction(element, kAXPressAction as CFString) == .success ? 0 : 1)
        }
    }
    for child in attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] {
        inspect(child, button: button)
    }
}

if CommandLine.arguments.dropFirst().first == "--sheet" {
    guard AXIsProcessTrusted(), CommandLine.arguments.count >= 3, let pid = Int32(CommandLine.arguments[2]) else { exit(2) }
    let app = AXUIElementCreateApplication(pid)
    let button = CommandLine.arguments.dropFirst(3).first
    for window in attribute(app, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? [] {
        for sheet in attribute(window, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] {
            if attribute(sheet, kAXRoleAttribute as CFString) as? String == kAXSheetRole { inspect(sheet, button: button) }
        }
    }
    exit(button == nil ? 0 : 1)
} else {
    let receiver = Receiver()
    NSApplication.shared.delegate = receiver
    withExtendedLifetime(receiver) { NSApplication.shared.run() }
}
