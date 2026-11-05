import AppKit

// Opt-in, isolated integration diagnostics. Never inspect the regular profile.
func startNativeHostDiagnostics() {
    let env = ProcessInfo.processInfo.environment
    guard env["BROWSER_NATIVE_TEST_DATA"] != nil,
          let output = env["BROWSER_NATIVE_HOST_DIAGNOSTICS"] else { return }
    Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
        func rect(_ r: NSRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
        func views(_ v: NSView) -> [[String: Any]] {
            var result: [[String: Any]] = []
            let name = NSStringFromClass(type(of: v))
            if name.contains("WebContents") || name.contains("RenderWidget") || name.contains("TabCell") || v is NSButton || v is DownloadFlightView {
                result.append(["class": name, "window": v.window?.windowNumber ?? -1,
                               "hidden": v.isHiddenOrHasHiddenAncestor,
                               "label": v.accessibilityLabel() ?? "",
                               "rect": rect(v.window?.convertToScreen(v.convert(v.bounds, to: nil)) ?? .zero)])
            }
            for child in v.subviews { result += views(child) }
            return result
        }
        let rows: [[String: Any]] = NSApp.windows.map { w in
            ["number": w.windowNumber, "class": NSStringFromClass(type(of: w)),
             "identifier": w.identifier?.rawValue ?? "", "visible": w.isVisible,
             "key": w.isKeyWindow, "main": w.isMainWindow,
             "firstResponder": w.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "",
             "frame": rect(w.frame), "views": w.contentView.map(views) ?? []]
        }
        if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: output), options: .atomic)
        }
    }
}
