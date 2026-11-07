// SPDX-License-Identifier: MPL-2.0
import AppKit

final class PageFindBar: NSVisualEffectView, NSSearchFieldDelegate {
    let field = NSSearchField()
    var queryChanged: (() -> Void)?
    var step: ((Bool) -> Void)?
    var dismiss: (() -> Void)?

    private let counter = NSTextField(labelWithString: "")
    private lazy var previous = ActionButton("", symbol: "chevron.up") { [weak self] in self?.step?(false) }
    private lazy var next = ActionButton("", symbol: "chevron.down") { [weak self] in self?.step?(true) }
    private lazy var close = ActionButton("", symbol: "xmark") { [weak self] in self?.dismiss?() }
    private var language = "fr"
    private var result: (position: Int, total: Int)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        field.delegate = self
        field.sendsWholeSearchString = true
        field.font = .systemFont(ofSize: 13)
        counter.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        counter.textColor = .secondaryLabelColor
        counter.alignment = .center
        for view in [field, counter, previous, next, close] { addSubview(view) }
        localize("fr")
        clearResult()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func localize(_ language: String) {
        self.language = language
        field.placeholderString = L10n.text("find", language: language)
        field.setAccessibilityLabel(field.placeholderString)
        for (button, key) in [(previous, "findPrevious"), (next, "findNext"), (close, "close")] {
            let title = L10n.text(key, language: language)
            button.setAccessibilityLabel(title)
            button.toolTip = title
        }
        updateCounter()
    }

    func clearResult() { result = nil; updateCounter() }
    func showResult(position: Int, total: Int) {
        result = (position, total)
        updateCounter()
    }

    private func updateCounter() {
        if let result {
            let format = language == "en" ? "%d of %d" : "%d sur %d"
            counter.stringValue = String(format: format, result.position, result.total)
        } else {
            counter.stringValue = ""
        }
        previous.isEnabled = (result?.total ?? 0) > 0
        next.isEnabled = previous.isEnabled
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let buttonsX = bounds.width - 84
        let countWidth = counter.stringValue.isEmpty ? 0 : ceil(counter.intrinsicContentSize.width) + 14
        field.frame = NSRect(x: 7, y: (bounds.height-24)/2, width: max(36, buttonsX-countWidth-9), height: 24)
        counter.frame = NSRect(x: buttonsX-countWidth, y: (bounds.height-16)/2, width: countWidth, height: 16)
        for (index, button) in [previous, next, close].enumerated() {
            button.frame = NSRect(x: buttonsX+CGFloat(index)*26, y: (bounds.height-24)/2, width: 25, height: 24)
        }
    }

    func controlTextDidChange(_ notification: Notification) { queryChanged?() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { dismiss?(); return true }
        if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.insertLineBreak(_:)) {
            step?(NSApp.currentEvent?.modifierFlags.contains(.shift) != true)
            return true
        }
        return false
    }
}
