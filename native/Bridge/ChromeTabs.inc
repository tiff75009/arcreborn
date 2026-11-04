#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
struct ImmediateNativeSurfaceUpdate {
  ImmediateNativeSurfaceUpdate() { [CATransaction begin]; [CATransaction setDisableActions:YES]; }
  ~ImmediateNativeSurfaceUpdate() { [CATransaction commit]; }
};
// Chrome retains its Browser/WebContents and extension services in a hidden
// backend widget. The real WebContents NSView lives inside the AppKit shell;
// it never has its own visible/key NSWindow.
struct ChromeTabSurface {
  CefRefPtr<CefWindow> window;
  CefRefPtr<CefBrowserView> view;
  __weak NSView *container = nil;
  __weak NSView *content = nil;
  bool visible = false;
};
static std::map<std::string, ChromeTabSurface> chromeTabs;
static std::map<std::string, NSView *> chromePopupContainers;
static void PrepareChromePopup(NSString *key, NSView *container) { chromePopupContainers[key.UTF8String] = container; }
static void LayoutChromeTab(const std::string& key) {
  ImmediateNativeSurfaceUpdate immediate;
  auto it = chromeTabs.find(key); if (it == chromeTabs.end()) return;
  auto& tab = it->second;
  NSView *container = tab.container;
  NSView *nativeView = (__bridge NSView *)tab.window->GetWindowHandle();
  NSWindow *native = nativeView.window, *parent = container.window;
  if (!native || !parent) return;
  auto browser = tab.view->GetBrowser();
  if (!browser) return;
  using Attach = void* (*)(int, void*);
  using Visibility = int (*)(int, int);
  auto attach = reinterpret_cast<Attach>(BrowserEngineSymbol("browser_attach_native_view_v1"));
  auto visibility = reinterpret_cast<Visibility>(BrowserEngineSymbol("browser_native_view_visibility_v1"));
  if (!attach || !visibility) return; // Packaging requires both private exports.
  if (!tab.content) tab.content = (__bridge NSView*)attach(browser->GetIdentifier(), (__bridge void*)container);
  if (!tab.content) return;
  const bool visible = tabVisibility[key] && !container.hiddenOrHasHiddenAncestor;
  if (tab.visible && !visible) CloseNativeExtensionPopup(key);
  if (!NSEqualSizes(tab.content.frame.size, container.bounds.size)) CloseNativeExtensionPopup(key);
  NSRect pageFrame = DeveloperPageRect(key,container);
  tab.content.frame = pageFrame;
  if (tab.visible != visible || tab.content.hidden == visible)
    visibility(browser->GetIdentifier(), visible);
  tab.visible = visible;
  // Backend geometry is retained for Chromium's dialog/toolbar calculations.
  // It is never presented and cannot acquire keyboard focus.
  NSRect frame = [parent convertRectToScreen:[container convertRect:pageFrame toView:nil]];
  if (CanLayoutChromeBackend(frame)) {
    [native setFrame:frame display:NO];
    tab.view->SetBounds(CefRect(0,0,(int)frame.size.width,(int)frame.size.height));
    if (auto toolbar = tab.view->GetChromeToolbar()) toolbar->SetBounds(CefRect(0,-48,(int)frame.size.width,48));
  } else {
    // Keep the last backend geometry while an AppKit container is collapsed.
    BrowserTrace(@"tab.backend-bounds-deferred",@{@"tab":@(key.c_str()),@"rect":NSStringFromRect(frame)});
  }
  // orderOut detaches native child windows, so keep an explicit weak owner
  // for Chromium bubbles instead of relying on NSWindow.parentWindow.
  NSHashTable *document = objc_getAssociatedObject(native, sel_registerName("browserDocumentWindow"));
  if (!document || [document anyObject] != parent) {
    document = [NSHashTable weakObjectsHashTable];
    [document addObject:parent];
    objc_setAssociatedObject(native, sel_registerName("browserDocumentWindow"), document, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  [native orderOut:nil];
  tab.content.frame = pageFrame;
  LayoutDeveloperTools(key,container);
}

class ChromeTabWindow : public CefWindowDelegate {
 public:
  ChromeTabWindow(CefRefPtr<CefBrowserView> view, NSString *key, NSView *container)
      : view_(view), key_(key.UTF8String), container_(container) {}
  bool IsFrameless(CefRefPtr<CefWindow>) override { return true; }
  bool WithStandardWindowButtons(CefRefPtr<CefWindow>) override { return false; }
  bool CanResize(CefRefPtr<CefWindow>) override { return false; }
  bool CanMinimize(CefRefPtr<CefWindow>) override { return false; }
  bool CanMaximize(CefRefPtr<CefWindow>) override { return false; }
  cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  void OnWindowCreated(CefRefPtr<CefWindow> window) override {
    BrowserTrace(@"tab.window-created",@{@"tab":@(key_.c_str())});
    window->AddChildView(view_);
    if (auto toolbar = view_->GetChromeToolbar()) window->AddChildView(toolbar);
    chromeTabs[key_] = {window, view_, container_};
    NSView *handle = (__bridge NSView *)window->GetWindowHandle();
    NSWindow *native = handle.window;
    native.identifier = @"local.browser.backend";
    InstallPictureInPictureReturnRouting(native,@(key_.c_str()));
    native.hasShadow = NO; native.movable = NO;
    native.excludedFromWindowsMenu = YES;
    native.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorTransient;
    native.backgroundColor = NSColor.clearColor;
    native.contentView.wantsLayer = YES;
    native.contentView.layer.cornerRadius = 7;
    native.contentView.layer.masksToBounds = YES;
    // Native toolbar remains owned by Chromium for extension actions, but is
    // not laid out as a second address bar in Browser's content area.
    LayoutChromeTab(key_);
  }
  bool CanClose(CefRefPtr<CefWindow>) override {
    auto browser = view_ ? view_->GetBrowser() : nullptr;
    return !browser || browser->GetHost()->TryCloseBrowser();
  }
  void OnWindowDestroyed(CefRefPtr<CefWindow>) override {
    BrowserTrace(@"tab.window-destroyed",@{@"tab":@(key_.c_str()),@"quitting":@(quitting)});
    auto surface = chromeTabs.find(key_);
    if (surface != chromeTabs.end()) [surface->second.content removeFromSuperview];
    chromeTabs.erase(key_); view_ = nullptr;
  }
 private:
  CefRefPtr<CefBrowserView> view_;
  std::string key_;
  __weak NSView *container_;
  IMPLEMENT_REFCOUNTING(ChromeTabWindow);
};

class ChromeTabView : public CefBrowserViewDelegate {
 public:
  cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  ChromeToolbarType GetChromeToolbarType(CefRefPtr<CefBrowserView>) override { return CEF_CTT_NORMAL; }
  bool OnPopupBrowserViewCreated(CefRefPtr<CefBrowserView> source, CefRefPtr<CefBrowserView> popup, bool devtools) override {
    if (devtools) return EmbedDeveloperTools(source,popup);
    auto browser = popup->GetBrowser();
    for (auto &entry : browsers) {
      if (!entry.second->IsSame(browser)) continue;
      auto destination = chromePopupContainers.find(entry.first);
      if (destination == chromePopupContainers.end()) break;
      NSView *container = destination->second;
      chromePopupContainers.erase(destination);
      CefWindow::CreateTopLevelWindow(new ChromeTabWindow(popup, @(entry.first.c_str()), container));
      return true;
    }
    return false; // Chromium owns extension action bubbles and permission UI.
  }
 private:
  IMPLEMENT_REFCOUNTING(ChromeTabView);
};
static bool CreateChromeTab(BrowserEngine *engine, NSString *key, NSString *url, NSView *container, CefRefPtr<CefRequestContext> context) {
  if (!BrowserEngineSymbol("browser_attach_native_view_v1") || !BrowserEngineSymbol("browser_native_view_visibility_v1")) return false;
  pendingBrowsers[key.UTF8String] = false;
  auto view = CefBrowserView::CreateBrowserView(new NativeClient(engine,key,true,true), CefStr(url), CefBrowserSettings(), nullptr, context, new ChromeTabView());
  if (!view) { pendingBrowsers.erase(key.UTF8String); return false; }
  return CefWindow::CreateTopLevelWindow(new ChromeTabWindow(view,key,container)) != nullptr;
}

