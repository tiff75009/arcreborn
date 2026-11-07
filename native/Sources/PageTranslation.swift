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
    func translate(_ texts:[String], hint:String, page:Bool, owner:String, in window:NSWindow, completion:@escaping ([String]?)->Void) {
        guard #available(macOS 15.0, *), !texts.isEmpty, window.attachedSheet == nil else { completion(nil); return }
        PageTranslationSheet.show(texts:texts,hint:hint,page:page,owner:owner,window:window,completion:completion)
    }
    func dismissTranslation(for owner:String) {
        if #available(macOS 15.0, *) { PageTranslationSheet.active[owner]?.finish(nil) }
    }
}

@available(macOS 15.0, *)
@MainActor
private final class PageTranslationSheet {
    static var active = [String:PageTranslationSheet]()
    let sheet = NSPanel()
    let owner:String
    private var completion: (([String]?)->Void)?
    init(owner:String, completion:@escaping ([String]?)->Void) { self.owner = owner; self.completion = completion }
    static func show(texts:[String],hint:String,page:Bool,owner:String,window:NSWindow,completion:@escaping ([String]?)->Void) {
        guard active[owner] == nil else { completion(nil); return }
        let controller = PageTranslationSheet(owner:owner,completion:completion)
        active[owner] = controller
        let content = TranslationCard(texts:texts,source:PageTranslationSettings.source(texts,hint:hint),
            page:page, english:PageTranslationSettings.browser == "en",
            finish:{ [weak controller] in controller?.finish($0) })
        let host = NSHostingView(rootView:content)
        let sheet = controller.sheet
        sheet.styleMask = [.titled]; sheet.titleVisibility = .hidden
        sheet.titlebarAppearsTransparent = true
        sheet.title = PageTranslationSettings.browser == "en" ? "Translation" : "Traduction"
        sheet.contentView = host; sheet.setContentSize(host.fittingSize)
        window.beginSheet(sheet) { [weak controller] _ in controller?.finish(nil) }
    }
    func finish(_ text:[String]?) {
        guard let cb = completion else { return }; completion = nil
        sheet.sheetParent?.endSheet(sheet); sheet.orderOut(nil); sheet.contentView = nil
        Self.active[owner] = nil; cb(text)
    }
}

@available(macOS 15.0, *)
private struct TranslationCard: View {
    let texts:[String], source:Locale.Language?, page:Bool, english:Bool
    let finish:([String]?)->Void
    @State private var choice = PageTranslationSettings.choice
    @State private var destinations = [String]()
    private var ui:String { english ? "en" : "fr" }
    private var target:String { choice.isEmpty ? PageTranslationSettings.browser : choice }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Label(page ? (english ? "Translate Page" : "Traduire la page") : (english ? "Translate Selection" : "Traduire la sélection"),systemImage:"translate").font(.title2.weight(.semibold))
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
            TranslationOutput(texts:texts,source:source,target:.init(identifier:target),page:page,english:english,finish:finish).id(target)
        }.padding(22).frame(width:430)
         .task { destinations = await PageTranslationSettings.destinations(language:ui) }
         .onReceive(NotificationCenter.default.publisher(for:PageTranslationSettings.changed)) { _ in choice = PageTranslationSettings.choice }
    }
}

@available(macOS 15.0, *)
private struct TranslationOutput: View {
    let texts:[String], source:Locale.Language?, target:Locale.Language, page:Bool, english:Bool
    let finish:([String]?)->Void
    @State private var result:String?
    @State private var pageResult:[String]?
    @State private var error:String?
    @State private var completed = 0
    private func tr(_ fr:String,_ en:String)->String { english ? en : fr }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            if let error { Text(error).fixedSize(horizontal:false,vertical:true).accessibilityLabel(error) }
            else if let result {
                ScrollView { Text(result).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled).font(.body) }.frame(height:125)
            } else if pageResult != nil {
                Text(tr("La traduction est prête.","The translation is ready.")).foregroundStyle(.secondary)
            } else {
                HStack(spacing:10) {
                    ProgressView().controlSize(.small)
                    Text(completed == 0 ? tr("Préparation de la traduction…","Preparing translation…") :
                            tr("Traduction en cours…","Translating…") + " \(completed) / \(texts.count)")
                }.foregroundStyle(.secondary)
            }
            HStack {
                if let result {
                    Button(tr("Copier","Copy")) { let pb = NSPasteboard.general; pb.clearContents(); pb.setString(result,forType:.string) }
                }
                Spacer()
                Button(error == nil && result == nil ? tr("Annuler","Cancel") : tr("Fermer","Close")) { finish(nil) }.keyboardShortcut(.cancelAction)
                if let pageResult {
                    Button(tr("Appliquer à la page","Apply to Page")) { finish(pageResult) }.keyboardShortcut(.defaultAction)
                }
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
                // This view-backed session lets macOS ask for missing language packs.
                if source != nil { try await session.prepareTranslation() }
                var translated = Array(repeating:"",count:texts.count)
                for start in stride(from:0,to:texts.count,by:32) {
                    try Task.checkCancellation()
                    let range = start..<min(start+32,texts.count)
                    let requests = range.map { TranslationSession.Request(sourceText:texts[$0],clientIdentifier:String($0)) }
                    for response in try await session.translations(from:requests) {
                        guard let key = response.clientIdentifier, let i = Int(key), range.contains(i) else { continue }
                        translated[i] = response.targetText
                    }
                    completed = range.upperBound
                }
                try Task.checkCancellation()
                guard !translated.contains(where:{ $0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }) else {
                    error = tr("La traduction est incomplète. Réessayez.","Translation was incomplete. Please try again."); return
                }
                if page { pageResult = translated } else { result = translated.first }
            } catch is CancellationError { return }
              catch { self.error = tr("Traduction indisponible : ","Translation unavailable: ") + error.localizedDescription }
         }
    }
}
