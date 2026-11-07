import AppKit
import NaturalLanguage
import SwiftUI
import Translation

enum PageTranslationSettings {
    static let targetKey = "PageTranslationTarget"
    static var browser: String { UserDefaults.standard.string(forKey:"BrowserLanguage") == "en" ? "en" : "fr" }
    static let changed = Notification.Name("PageTranslationDestinationChanged")
    static var choice:String { UserDefaults.standard.string(forKey:targetKey) ?? "" }
    static func choose(_ code:String) {
        guard code != choice else { return }
        UserDefaults.standard.set(code.isEmpty ? nil : code,forKey:targetKey)
        NotificationCenter.default.post(name:changed,object:nil)
    }
    @available(macOS 15.0, *)
    static func destinations(language:String) async -> [String] {
        let supported = await LanguageAvailability().supportedLanguages
        return Set(supported.map { $0.minimalIdentifier }).sorted {
            name($0,language:language).localizedStandardCompare(name($1,language:language)) == .orderedAscending
        }
    }
    static func name(_ id:String, language:String) -> String {
        Locale(identifier:language).localizedString(forIdentifier:id)?.localizedCapitalized ?? id
    }
    static func source(_ texts:[String], hint:String) -> Locale.Language? {
        let sample = texts.prefix(40).map { String($0.prefix(500)) }.joined(separator:" ").prefix(6000)
        let recognizer = NLLanguageRecognizer(); recognizer.processString(String(sample))
        if let best = recognizer.languageHypotheses(withMaximum:1).first, best.value >= 0.55 {
            return .init(identifier:best.key.rawValue)
        }
        // When neither the text nor the document identifies a language, let
        // Apple identify it; the interface language is never a source hint.
        guard !hint.isEmpty, hint.count <= 64 else { return nil }
        return .init(identifier:hint)
    }
}

extension NativeAppDelegate: BrowserTranslationPresenter {
    func translateSelection(_ text:String, owner:String, in window:NSWindow) {
        guard #available(macOS 15.0, *), !text.isEmpty, window.attachedSheet == nil else { return }
        PageTranslationSheet.show(text:text,owner:owner,window:window)
    }

    func translatePage(_ texts:[String], hint:String, owner:String, in view:NSView,
                       update:@escaping (Int,String)->Void, completion:@escaping (String?)->Void) {
        guard #available(macOS 15.0, *) else { completion("Unavailable"); return }
        InlinePageTranslation.start(texts:texts,hint:hint,owner:owner,in:view,update:update,completion:completion)
    }

    func cancelInlineTranslation(_ owner:String) {
        if #available(macOS 15.0, *) { InlinePageTranslation.active[owner]?.stop() }
    }

    func dismissTranslation(for owner:String) {
        cancelInlineTranslation(owner)
        if #available(macOS 15.0, *) { PageTranslationSheet.active[owner]?.finish() }
    }

    func showTranslationNotice(_ message:String, in window:NSWindow) {
        controllers.first { $0.window === window }?.showTranslationNotice(message)
    }
}

// SwiftUI provides an Apple Translation session on macOS 15 and later. Attach
// its noninteractive host to the live document so only Apple's own first-use
// language download, if needed, has UI. Reading and scrolling stay available.
@available(macOS 15.0, *)
@MainActor
private final class InlinePageTranslation {
    static var active = [String:InlinePageTranslation]()
    let owner:String
    private var host:NSView?
    private var running = true

    init(owner:String) { self.owner = owner }

    static func start(texts:[String], hint:String, owner:String, in view:NSView,
                      update:@escaping (Int,String)->Void, completion:@escaping (String?)->Void) {
        active[owner]?.stop()
        let job = InlinePageTranslation(owner:owner)
        active[owner] = job
        let code = PageTranslationSettings.choice
        let target = Locale.Language(identifier:code.isEmpty ? PageTranslationSettings.browser : code)
        let source = PageTranslationSettings.source(texts,hint:hint)
        let english = PageTranslationSettings.browser == "en"
        let task = Color.clear.frame(width:1,height:1).allowsHitTesting(false).accessibilityHidden(true)
            .translationTask(source:source,target:target) { [weak job] session in
                guard let job, job.running else { return }
                var failure:String?
                do {
                    if let source, source.isEquivalent(to:target) {
                        failure = english ? "This page is already in the selected language." : "Cette page est déjà dans la langue choisie."
                    } else if let source, await LanguageAvailability().status(from:source,to:target) == .unsupported {
                        failure = english ? "Apple doesn’t support this language pair." : "Apple ne prend pas en charge cette paire de langues."
                    } else {
                        try await job.stream(texts,using:session,update:update)
                    }
                } catch {
                    failure = english ? "Page translation was interrupted." : "La traduction de la page a été interrompue."
                }
                guard job.running else { return }
                job.stop()
                completion(failure)
            }
        let host = NSHostingView(rootView:task)
        job.host = host
        host.frame = NSRect(x:0,y:0,width:1,height:1)
        view.addSubview(host,positioned:.below,relativeTo:nil)
    }

    private func stream(_ texts:[String], using session:TranslationSession, update:(Int,String)->Void) async throws {
        var start = 0
        while start < texts.count {
            // First translate a few strings in the viewport for a quick first
            // paint, then feed larger batches. Apple can return them unordered.
            let end = min(texts.count,start + (start == 0 ? 4 : 32))
            var missing = Set(start..<end)
            let requests = (start..<end).map { TranslationSession.Request(sourceText:texts[$0],clientIdentifier:String($0)) }
            for try await response in session.translate(batch:requests) {
                try Task.checkCancellation()
                guard running else { throw CancellationError() }
                guard let key = response.clientIdentifier, let index = Int(key), missing.remove(index) != nil,
                      !response.targetText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
                    throw CocoaError(.coderInvalidValue)
                }
                update(index,response.targetText)
            }
            guard missing.isEmpty else { throw CocoaError(.coderInvalidValue) }
            start = end
        }
    }

    func stop() {
        guard running else { return }
        running = false
        if Self.active[owner] === self { Self.active[owner] = nil }
        host?.removeFromSuperview()
        host = nil
    }
}

@available(macOS 15.0, *)
@MainActor
private final class PageTranslationSheet {
    static var active = [String:PageTranslationSheet]()
    let sheet = NSPanel()
    let owner:String
    init(owner:String) { self.owner = owner }
    static func show(text:String,owner:String,window:NSWindow) {
        guard active[owner] == nil else { return }
        let controller = PageTranslationSheet(owner:owner)
        active[owner] = controller
        let content = TranslationCard(text:text,source:PageTranslationSettings.source([text],hint:""),
            english:PageTranslationSettings.browser == "en",finish:{ [weak controller] in controller?.finish() })
        let host = NSHostingView(rootView:content)
        let sheet = controller.sheet
        sheet.styleMask = [.titled]; sheet.titleVisibility = .hidden
        sheet.titlebarAppearsTransparent = true
        sheet.title = PageTranslationSettings.browser == "en" ? "Translation" : "Traduction"
        sheet.contentView = host; sheet.setContentSize(host.fittingSize)
        window.beginSheet(sheet) { [weak controller] _ in controller?.finish() }
    }
    func finish() {
        guard Self.active[owner] === self else { return }
        Self.active[owner] = nil
        sheet.sheetParent?.endSheet(sheet); sheet.orderOut(nil); sheet.contentView = nil
    }
}

@available(macOS 15.0, *)
private struct TranslationCard: View {
    let text:String, source:Locale.Language?, english:Bool
    let finish:()->Void
    @State private var choice = PageTranslationSettings.choice
    @State private var destinations = [String]()
    private var ui:String { english ? "en" : "fr" }
    private var target:String { choice.isEmpty ? PageTranslationSettings.browser : choice }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Label(english ? "Translate Selection" : "Traduire la sélection",systemImage:"translate").font(.title2.weight(.semibold))
            HStack {
                Text(source.map { PageTranslationSettings.name($0.minimalIdentifier,language:ui) } ?? (english ? "Auto-detect" : "Détection auto")).foregroundStyle(.secondary)
                Image(systemName:"arrow.right").font(.caption).accessibilityHidden(true)
                Picker(english ? "Translate to" : "Traduire vers",selection:Binding(get:{choice},set:{choice = $0; PageTranslationSettings.choose($0)})) {
                    Text((english ? "Browser language" : "Langue du navigateur") + " · " + PageTranslationSettings.name(PageTranslationSettings.browser,language:ui)).tag("")
                    Divider()
                    ForEach(destinations.isEmpty && !choice.isEmpty ? [choice] : destinations,id:\.self) { code in
                        Text(PageTranslationSettings.name(code,language:ui)).tag(code)
                    }
                }.labelsHidden().accessibilityLabel(english ? "Translate to" : "Traduire vers").accessibilityIdentifier("translation.destination")
            }
            Divider()
            // Each destination owns its results and Apple session. A late reply
            // for the previous choice cannot overwrite or apply the new one.
            TranslationOutput(text:text,source:source,target:.init(identifier:target),english:english,finish:finish).id(target)
        }.padding(22).frame(width:430)
         .task { destinations = await PageTranslationSettings.destinations(language:ui) }
         .onReceive(NotificationCenter.default.publisher(for:PageTranslationSettings.changed)) { _ in choice = PageTranslationSettings.choice }
    }
}

@available(macOS 15.0, *)
private struct TranslationOutput: View {
    let text:String, source:Locale.Language?, target:Locale.Language, english:Bool
    let finish:()->Void
    @State private var result:String?
    @State private var error:String?
    private func tr(_ fr:String,_ en:String)->String { english ? en : fr }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            if let error { Text(error).fixedSize(horizontal:false,vertical:true).accessibilityLabel(error) }
            else if let result {
                ScrollView { Text(result).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled).font(.body) }.frame(height:125)
            } else {
                HStack(spacing:10) {
                    ProgressView().controlSize(.small)
                    Text(tr("Traduction en cours…","Translating…"))
                }.foregroundStyle(.secondary)
            }
            HStack {
                if let result {
                    Button(tr("Copier","Copy")) { let pb = NSPasteboard.general; pb.clearContents(); pb.setString(result,forType:.string) }
                }
                Spacer()
                Button(error == nil && result == nil ? tr("Annuler","Cancel") : tr("Fermer","Close")) { finish() }.keyboardShortcut(.cancelAction)

            }
        }
         .translationTask(source:source,target:target) { session in
            do {
                if let source, source.isEquivalent(to:target) {
                    error = tr("Ce texte est déjà dans la langue choisie. Choisissez une autre langue ci-dessus.",
                               "This text is already in the selected language. Choose another language above."); return
                }
                if let source, await LanguageAvailability().status(from:source,to:target) == .unsupported {
                    error = tr("Apple ne prend pas en charge cette paire de langues sur ce Mac.","Apple doesn’t support this language pair on this Mac."); return
                }
                let response = try await session.translate(text)
                try Task.checkCancellation()
                result = response.targetText
            } catch is CancellationError { return }
              catch { self.error = tr("Traduction indisponible : ","Translation unavailable: ") + error.localizedDescription }
         }
    }
}
