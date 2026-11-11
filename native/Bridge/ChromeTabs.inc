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
  bool observingSound = false;
};
static std::map<std::string, ChromeTabSurface> chromeTabs;
static NSWindow *ChromeDocumentWindow(NSString *key) {
  auto it = chromeTabs.find(key.UTF8String);
  if (it == chromeTabs.end()) return nil;
  return it->second.container.window;
}
static NSView *VisibleChromePage(NSString *key) {
  auto it = chromeTabs.find(key.UTF8String);
  if (it == chromeTabs.end() || !it->second.visible) return nil;
  NSView *view = it->second.content;
  return view.window.isVisible && !view.hiddenOrHasHiddenAncestor ? view : nil;
}
struct ChromePopupDestination {
  NSView *container;
  CefClient *client;
  std::weak_ptr<bool> lifetime;
};
static std::map<std::string, ChromePopupDestination> chromePopupContainers;
static void PrepareChromePopup(NSString *key, NSView *container, CefRefPtr<CefClient> client, std::weak_ptr<bool> lifetime) {
  // CEF owns the client. Holding it here would prevent its destructor from
  // releasing an aborted popup when its opener has already closed.
  chromePopupContainers[key.UTF8String] = {container, client.get(), lifetime};
}
static void CancelChromePopup(const std::string& key) { chromePopupContainers.erase(key); }
static void TabSoundChanged(int browserID, int audible, int muted) {
  if (quitting) return;
  auto tab = std::find_if(browsers.begin(), browsers.end(), [browserID](const auto& entry) {
    return entry.second->GetIdentifier() == browserID;
  });
  if (tab == browsers.end()) return;
  if (audible) {
    audibleTabs.insert(tab->first);
    FinishArchiveProbe(tab->first, false);
  } else {
    audibleTabs.erase(tab->first);
  }
  auto owner = nativeTabOwners.find(tab->first);
  if (owner == nativeTabOwners.end()) return;
  id<BrowserEngineDelegate> delegate = owner->second.engine.delegate;
  if ([delegate respondsToSelector:@selector(browserSoundChanged:audible:muted:)])
    [delegate browserSoundChanged:@(tab->first.c_str()) audible:audible != 0 muted:muted != 0];
}
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
  if (!tab.observingSound) {
    using Observe = int (*)(int, void (*)(int, int, int));
    static auto observe = reinterpret_cast<Observe>(BrowserEngineSymbol("browser_observe_tab_sound_v1"));
    tab.observingSound = observe && observe(browser->GetIdentifier(), TabSoundChanged);
  }
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
  auto owner = nativeTabOwners.find(key);
  if (visible && owner != nativeTabOwners.end() &&
      ![owner->second.engine.delegate respondsToSelector:@selector(browserShouldCancelAuthenticationNavigation:url:)])
    ScheduleDiscordInviteOffer(browser,@(key.c_str()),tab.content);
}

class ChromeTabWindow : public TrackedChromeWindow {
 public:
  ChromeTabWindow(CefRefPtr<CefBrowserView> view, NSString *key, NSView *container)
      : view_(view), key_(key.UTF8String), container_(container) {}
  bool IsFrameless(CefRefPtr<CefWindow>) override { return true; }
  bool WithStandardWindowButtons(CefRefPtr<CefWindow>) override { return false; }
  bool CanResize(CefRefPtr<CefWindow>) override { return false; }
  bool CanMinimize(CefRefPtr<CefWindow>) override { return false; }
  bool CanMaximize(CefRefPtr<CefWindow>) override { return false; }
  cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  void WindowCreated(CefRefPtr<CefWindow> window) override {
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
  void WindowDestroyed(CefRefPtr<CefWindow> window) override {
    BrowserTrace(@"tab.window-destroyed",@{@"tab":@(key_.c_str()),@"quitting":@(quitting)});
    auto surface = chromeTabs.find(key_);
    // A quick wake may already have attached a replacement for this tab ID.
    if (surface != chromeTabs.end() && surface->second.window->IsSame(window)) {
      [surface->second.content removeFromSuperview];
      chromeTabs.erase(surface);
    }
    view_ = nullptr;
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
    if (!browser) return false;
    // CEF 156 Chrome calls this BEFORE NativeClient::OnAfterCreated, despite
    // the public header's ordering comment. The browser registry is not ready.
    // Identify the reserved destination by its client, which already exists.
    auto client = browser->GetHost()->GetClient();
    for (auto destination = chromePopupContainers.begin(); destination != chromePopupContainers.end(); ++destination) {
      if (destination->second.client != client.get() || destination->second.lifetime.expired()) continue;
      const std::string key = destination->first;
      NSView *container = destination->second.container;
      chromePopupContainers.erase(destination);
      CefWindow::CreateTopLevelWindow(new ChromeTabWindow(popup, @(key.c_str()), container));
      BrowserTrace(@"tab.popup-attached",@{@"tab":@(key.c_str()),@"browser":@(browser->GetIdentifier())});
      return true;
    }
    return false; // Chromium owns extension action bubbles and permission UI.
  }
 private:
  IMPLEMENT_REFCOUNTING(ChromeTabView);
};
static bool CreateChromeTab(BrowserEngine *engine, NSString *key, NSString *url, NSView *container, CefRefPtr<CefRequestContext> context, NSData *history = nil) {
  if (!BrowserEngineSymbol("browser_attach_native_view_v1") || !BrowserEngineSymbol("browser_native_view_visibility_v1")) return false;
  pendingBrowsers[key.UTF8String] = false;
  ExpectTabAddress(key,url);
  using Restore = bool (*)(int, const char*, const void*, size_t);
  auto restore = history.length ? reinterpret_cast<Restore>(BrowserEngineSymbol("browser_restore_tab_history_v1")) : nullptr;
  auto view = CefBrowserView::CreateBrowserView(new NativeClient(engine,key,true,true), restore ? CefString() : CefStr(url), CefBrowserSettings(), nullptr, context, new ChromeTabView());
  if (!view) { pendingBrowsers.erase(key.UTF8String); return false; }
  auto window = CefWindow::CreateTopLevelWindow(new ChromeTabWindow(view,key,container));
  if (!window) return false;
  if (restore) {
    auto browser = view->GetBrowser();
    if (!browser) { window->Close(); return false; }
    // Restore after AddChildView has installed the WebContents in its tab strip.
    if (!restore(browser->GetIdentifier(), url.UTF8String, history.bytes, history.length))
      browser->GetMainFrame()->LoadURL(CefStr(url));
  }
  return true;
}

