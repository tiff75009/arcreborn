// SPDX-License-Identifier: MPL-2.0
import AppKit

class ActionButton: NSButton {
    var invoke: (() -> Void)?
    init(_ title: String = "", symbol: String? = nil, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title; self.invoke = action; target = self; self.action = #selector(invokeAction)
        bezelStyle = .inline; isBordered = false; font = .systemFont(ofSize: 12)
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); imagePosition = title.isEmpty ? .imageOnly : .imageLeading }
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invokeAction() { invoke?() }
}
