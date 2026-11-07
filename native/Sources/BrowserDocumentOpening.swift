// SPDX-License-Identifier: MPL-2.0
import AppKit

extension NativeAppDelegate {
    func chooseBrowserDocuments(in windowController: BrowserController?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = BrowserDocuments.contentTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        let process: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let self, !self.quitting else { return }
            // A private window's own open panel stays in that window.
            if let windowController, !self.controllers.contains(where: { $0 === windowController }) { return }
            var batch = BrowserDocuments.Batch(); batch.append(panel.urls)
            self.deliverBrowserDocuments(batch,in:windowController)
        }
        if let window = windowController?.window { panel.beginSheetModal(for:window,completionHandler:process) }
        else { panel.begin(completionHandler:process) }
    }

    func deliverBrowserDocuments(_ batch: BrowserDocuments.Batch, in requested: BrowserController? = nil) {
        guard !batch.isEmpty, !quitting else { return }
        // Finder/Dock events never select an incidental private window.
        let target = requested ?? controller.flatMap { $0.isPrivateWindow ? nil : $0 }
            ?? controllers.first(where: { !$0.isPrivateWindow && $0.windowKind == .normal }) ?? openWindow(.normal)
        target.openDocumentTabs(batch.addresses); target.show()
        if !batch.unreadable.isEmpty {
            let alert = NSAlert()
            let en = target.menuLanguage == "en"
            alert.messageText = en ? "Couldn’t open the file" : "Impossible d’ouvrir le fichier"
            alert.informativeText = batch.unreadable.prefix(5).joined(separator:"\n") + "\n\n" +
                (en ? "Choose a readable HTML, PDF or SVG file, or a web shortcut containing an HTTP or HTTPS address."
                    : "Choisissez un fichier HTML, PDF ou SVG lisible, ou un raccourci web contenant une adresse HTTP ou HTTPS.")
            alert.beginSheetModal(for:target.window)
        }
    }
}
