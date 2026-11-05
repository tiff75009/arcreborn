import AppKit

/// A logical tab may appear in several windows. Each renderer has a separate CEF
/// identity; its callbacks are translated back to the shared sidebar tab ID.
final class WindowBrowserEngine: BrowserEngine, BrowserEngineDelegate {
    private let bridge = BrowserEngine()
    private let prefix: String
    private weak var receiver: BrowserEngineDelegate?
    override var delegate: BrowserEngineDelegate? { get { receiver } set { receiver = newValue } }
    init(windowID:String) { prefix = windowID+":"; super.init(); bridge.delegate = self }
    func rendererID(_ id:String) -> String { prefix+id }
    private func logical(_ id:String) -> String { id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id }
    override func createTab(_ id:String,profile:String,url:String,container:NSView) -> Bool { bridge.createTab(rendererID(id),profile:profile,url:url,container:container) }
    override func navigateTab(_ id:String,url:String) { bridge.navigateTab(rendererID(id),url:url) }
    override func resizeTab(_ id:String,container:NSView) { bridge.resizeTab(rendererID(id),container:container) }
    override func setTab(_ id:String,visible:Bool) { bridge.setTab(rendererID(id),visible:visible) }
    override func focusTab(_ id:String) { bridge.focusTab(rendererID(id)) }
    override func toggleMute(_ id:String) { bridge.toggleMute(rendererID(id)) }
    override func requestPictureInPicture(_ id:String,automatic:Bool,completion:@escaping (String)->Void) { bridge.requestPictureInPicture(rendererID(id),automatic:automatic,completion:completion) }
    override func closePictureInPicture(_ id:String) { bridge.closePictureInPicture(rendererID(id)) }
    override func hasPictureInPicture(_ id:String) -> Bool { bridge.hasPictureInPicture(rendererID(id)) }
    override func checkArchiveIdle(_ id:String,completion:@escaping (Bool)->Void) { bridge.checkArchiveIdle(rendererID(id),completion:completion) }
    override func goBack(_ id:String) { bridge.goBack(rendererID(id)) }
    override func goForward(_ id:String) { bridge.goForward(rendererID(id)) }
    override func reload(_ id:String) { bridge.reload(rendererID(id)) }
    override func reloadIgnoringCache(_ id:String) { bridge.reloadIgnoringCache(rendererID(id)) }
    override func zoomLevel(_ id:String) -> Double { bridge.zoomLevel(rendererID(id)) }
    override func setZoomLevel(_ id:String,level:Double) { bridge.setZoomLevel(rendererID(id),level:level) }
    override func canSavePage(_ id:String) -> Bool { bridge.canSavePage(rendererID(id)) }
    override func savePage(_ id:String) { bridge.savePage(rendererID(id)) }
    override func printPage(_ id:String) { bridge.printPage(rendererID(id)) }
    override func stop(_ id:String) { bridge.stop(rendererID(id)) }
    override func closeTab(_ id:String) { bridge.closeTab(rendererID(id)) }
    override func tryAutoArchiveTab(_ id:String) { bridge.tryAutoArchiveTab(rendererID(id)) }
    override func discardTab(_ id:String) { bridge.discardTab(rendererID(id)) }
    override func find(inTab id:String,text:String,forward:Bool,next:Bool) { bridge.find(inTab:rendererID(id),text:text,forward:forward,next:next) }
    override func stopFinding(_ id:String) { bridge.stopFinding(rendererID(id)) }
    override func activateExtension(_ id:String,tab:String,anchor:NSRect) -> Int { bridge.activateExtension(id,tab:rendererID(tab),anchor:anchor) }
    override func certificateInfo(forTab id:String) -> [String:Any]? { bridge.certificateInfo(forTab:rendererID(id)) }
    override func hasDeveloperTools(_ id:String) -> Bool { bridge.hasDeveloperTools(rendererID(id)) }
    override func toggleDeveloperTools(_ id:String) { bridge.toggleDeveloperTools(rendererID(id)) }
    override func developerTool(forTab id:String) -> String { bridge.developerTool(forTab:rendererID(id)) }
    override func toggleDeveloperTool(_ tool:String,forTab id:String) { bridge.toggleDeveloperTool(tool,forTab:rendererID(id)) }
    override func closeDeveloperTools(_ id:String) { bridge.closeDeveloperTools(rendererID(id)) }
    override func capturePage(_ id:String,completion:@escaping (Data?)->Void) { bridge.capturePage(rendererID(id),completion:completion) }
    override func captureFullPage(_ id:String,completion:@escaping (Data?)->Void) { bridge.captureFullPage(rendererID(id),completion:completion) }
    override func captureView(forTab id:String) -> NSView? { bridge.captureView(forTab:rendererID(id)) }
    override func captureElement(at point:NSPoint,forTab id:String,completion:@escaping ([AnyHashable:Any]?)->Void) { bridge.captureElement(at:point,forTab:rendererID(id),completion:completion) }
    override func setPageInputSuppressed(_ value:Bool,forTab id:String) { bridge.setPageInputSuppressed(value,forTab:rendererID(id)) }
    override func clearCache(forTab id:String,completion:@escaping (Bool)->Void) { bridge.clearCache(forTab:rendererID(id),completion:completion) }
    override func clearCookies(forTab id:String,completion:@escaping (Bool)->Void) { bridge.clearCookies(forTab:rendererID(id),completion:completion) }
    // Profile/global operations do not contain a tab ID and use the shared bridge implementation.
    func browserTitleChanged(_ id:String,title:String) { receiver?.browserTitleChanged(logical(id),title:title) }
    func browserSoundChanged(_ id:String,audible:Bool,muted:Bool) { receiver?.browserSoundChanged?(logical(id),audible:audible,muted:muted) }
    func browserInboxChanged(_ id:String,document:String,unread:Bool) { receiver?.browserInboxChanged?(logical(id),document:document,unread:unread) }
    func browserURLChanged(_ id:String,url:String) { receiver?.browserURLChanged(logical(id),url:url) }
    func browserLoadProgress(_ id:String,fraction:Double) { receiver?.browserLoadProgress?(logical(id),fraction:fraction) }
    func browserLoadingChanged(_ id:String,loading:Bool,back:Bool,forward:Bool) { receiver?.browserLoadingChanged(logical(id),loading:loading,back:back,forward:forward) }
    func browserFailed(_ id:String,code:String,host:String?) { receiver?.browserFailed(logical(id),code:code,host:host) }
    func browserRequestedNewTab(_ url:String,sourceTab:String) { receiver?.browserRequestedNewTab(url,sourceTab:logical(sourceTab)) }
    func browserRequestedPrivateWindow(_ url:String,sourceTab:String) { receiver?.browserRequestedPrivateWindow?(url,sourceTab:logical(sourceTab)) }
    func browserRequestedNewWindow(_ url:String,sourceTab:String) { receiver?.browserRequestedNewWindow?(url,sourceTab:logical(sourceTab)) }
    func browserClosed(_ id:String) { receiver?.browserClosed(logical(id)) }
    func browserCloseCancelled(_ id:String) { receiver?.browserCloseCancelled?(logical(id)) }
    func browserPictureInPictureReturn(_ id:String) { receiver?.browserPictureInPictureReturn?(logical(id)) }
    func browserFaviconChanged(_ id:String,document:String,image:NSImage) { receiver?.browserFaviconChanged?(logical(id),document:document,image:image) }
    func browserDownloadUpdated(_ id:String,values:[String:Any]) { receiver?.browserDownloadUpdated?(logical(id),values:values) }
    func browserUndoRequested() -> Bool { receiver?.browserUndoRequested?() ?? false }
    func browserExtensionInstalled(_ id:String,name:String,profile:String) { receiver?.browserExtensionInstalled?(id,name:name,profile:profile) }
    private func reservation(_ value:[String:Any]?) -> [String:Any]? {
        guard var value, let id = value["id"] as? String else { return nil }; value["id"] = rendererID(id); return value
    }
    func browserPrepareExtensionTab(_ source:String,active:Bool,pinned:Bool,index:Int) -> [String:Any]? { reservation(receiver?.browserPrepareExtensionTab?(logical(source),active:active,pinned:pinned,index:index)) }
    func browserExtensionTabCreated(_ id:String,success:Bool) { receiver?.browserExtensionTabCreated?(logical(id),success:success) }
    func browserPreparePopup(_ url:String,sourceTab:String) -> [String:Any]? { reservation(receiver?.browserPreparePopup?(url,sourceTab:logical(sourceTab))) }
    func browserPreparePopup(_ url:String,sourceTab:String,active:Bool) -> [String:Any]? { reservation(receiver?.browserPreparePopup?(url,sourceTab:logical(sourceTab),active:active)) }
}
