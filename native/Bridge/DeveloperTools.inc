// Native DevTools share the tab's AppKit container. Chromium retains a hidden
// backend widget, just as it does for the page; no second window is presented.
#import <objc/runtime.h>
static void LayoutChromeTab(const std::string& key);

// Chrome's hidden window still lays out a status-bubble window whose width is
// one third of the page width. A transient empty/tiny host would give that
// NSWindow a zero width and abort in NativeWidgetMacNSWindowHost.
static bool CanLayoutChromeBackend(NSRect frame) {
  return std::isfinite(frame.size.width) && std::isfinite(frame.size.height) &&
      frame.size.width >= 3 && frame.size.height >= 1;
}

@interface BrowserDeveloperDivider : NSView
@property(nonatomic,copy) void (^dragged)(CGFloat);
@end
@implementation BrowserDeveloperDivider
- (void)drawRect:(NSRect)rect { [NSColor.separatorColor setFill]; NSRectFill(self.bounds); }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.resizeLeftRightCursor]; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)mouseDown:(NSEvent*)event {
  while ((event = [self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp])) {
    if (self.dragged) self.dragged([self.superview convertPoint:event.locationInWindow fromView:nil].x);
    if (event.type == NSEventTypeLeftMouseUp) break;
  }
}
@end

struct DeveloperToolsState {
  CefRefPtr<CefBrowser> frontend;
  CefRefPtr<CefBrowserView> view;
  CefRefPtr<CefWindow> window;
  CefRefPtr<CefRegistration> inspection;
  CefRefPtr<CefRegistration> frontendEvents;
  __weak NSView *container = nil;
  __weak NSView *content = nil;
  NSView *pane = nil;
  BrowserDeveloperDivider *divider = nil;
  std::string panel = "elements";
  bool panelOpen = false;
  bool picking = false;
  bool frontendPicking = false;
  bool closed = false;
  bool opening = false;
  bool embeddedLayout = false;
  NSRect inspectedBounds = NSZeroRect; // DevTools DIP coordinates, top-left origin.
  double fraction = 0.34;
  int selectedNode = 0;
  int inspectionMessage = 0;
  uint64_t revision = 0;
  uint64_t boundsUpdates = 0;
  double lastBoundsTrace = 0;
};
static std::map<std::string, std::shared_ptr<DeveloperToolsState>> developerTools;
static void SetDeveloperToolsVisible(const std::string& key,bool visible);
static void ShowDeveloperTools(std::string key,std::shared_ptr<DeveloperToolsState> state,int attempt=0);
static void CloseTabDeveloperTools(const std::string& key);
static void DeveloperToolsChanged(std::string key) {
  NSString *tab = @(key.c_str());
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!quitting && browsers.count(key)) LayoutChromeTab(key);
    [NSNotificationCenter.defaultCenter postNotificationName:@"BrowserDeveloperToolsChanged" object:tab];
  });
}
static NSRect DeveloperPageRect(const std::string& key,NSView *container) {
  NSRect frame = container.bounds;
  auto it = developerTools.find(key);
  if (it == developerTools.end() || it->second->closed || !it->second->panelOpen) return frame;
  auto state = it->second;
  if (state->embeddedLayout && !NSIsEmptyRect(state->inspectedBounds)) {
    NSRect page = state->inspectedBounds;
    if (!container.isFlipped) page.origin.y = frame.size.height-NSMaxY(page);
    page = NSIntersectionRect(frame,page);
    if (CanLayoutChromeBackend(page)) return page;
    // The frontend can report its previous viewport during opening/resizing.
    // Use the ordinary split until it supplies bounds inside the new container.
  }
  double minimum = std::min(200.0,frame.size.width*0.4);
  double maximum = frame.size.width-std::min(260.0,frame.size.width*0.45)-6;
  frame.size.width = std::max(1.0,std::round(std::clamp(frame.size.width*(1-state->fraction),minimum,std::max(minimum,maximum))));
  return frame;
}
static void LayoutDeveloperTools(std::string key,NSView *container) {
  auto it = developerTools.find(key); if (it == developerTools.end()) return;
  auto state = it->second; state->container = container;
  if (!state->pane && state->panelOpen) {
    state->pane = [[NSView alloc] initWithFrame:NSZeroRect];
    state->pane.wantsLayer = YES; state->pane.layer.backgroundColor = [NSColor colorWithWhite:0.13 alpha:1].CGColor;
    state->pane.layer.masksToBounds = YES;
    state->divider = [[BrowserDeveloperDivider alloc] initWithFrame:NSZeroRect];
    std::weak_ptr<DeveloperToolsState> weak = state;
    state->divider.dragged = ^(CGFloat x) {
      auto current = weak.lock(); if (!current || current->closed || !current->container) return;
      current->fraction = std::clamp(1-x/std::max(1.0,current->container.bounds.size.width),0.15,0.8);
      LayoutChromeTab(key);
    };
    // The full DevTools frontend includes the responsive-device controls.
    // Its inspected-page placeholder sits behind the actual page NSView.
    [container addSubview:state->pane positioned:NSWindowBelow relativeTo:nil]; [container addSubview:state->divider];
  }
  const bool visible = !state->closed && state->panelOpen && tabVisibility[key] && !container.hiddenOrHasHiddenAncestor;
  NSRect page = DeveloperPageRect(key,container);
  state->divider.frame = NSMakeRect(NSMaxX(page),0,6,container.bounds.size.height);
  state->pane.frame = state->embeddedLayout ? container.bounds : NSMakeRect(NSMaxX(page)+6,0,std::max(1.0,container.bounds.size.width-NSMaxX(page)-6),container.bounds.size.height);
  state->pane.hidden = !visible; state->divider.hidden = !visible || state->embeddedLayout;
  if (!state->frontend || !state->view || !state->window || state->closed) return;
  using Attach = void* (*)(int,void*);
  using Visibility = int (*)(int,int);
  auto attach = reinterpret_cast<Attach>(BrowserEngineSymbol("browser_attach_native_view_v1"));
  auto visibility = reinterpret_cast<Visibility>(BrowserEngineSymbol("browser_native_view_visibility_v1"));
  if (!state->content && attach) state->content = (__bridge NSView*)attach(state->frontend->GetIdentifier(),(__bridge void*)state->pane);
  if (visibility) visibility(state->frontend->GetIdentifier(),visible);
  NSView *handle = (__bridge NSView*)state->window->GetWindowHandle();
  NSWindow *backend = handle.window, *document = container.window;
  if (backend && document) {
    NSRect frame = [document convertRectToScreen:[state->pane convertRect:state->pane.bounds toView:nil]];
    if (CanLayoutChromeBackend(frame)) {
      [backend setFrame:frame display:NO];
      state->view->SetBounds(CefRect(0,0,(int)frame.size.width,(int)frame.size.height));
    } else {
      BrowserTrace(@"devtools.backend-bounds-deferred",@{@"tab":@(key.c_str()),@"rect":NSStringFromRect(frame)});
    }
    [backend orderOut:nil];
    NSHashTable *owner = [NSHashTable weakObjectsHashTable]; [owner addObject:document];
    objc_setAssociatedObject(backend,sel_registerName("browserDocumentWindow"),owner,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  state->content.frame = state->pane.bounds;
}
static void StopNativeInspection(const std::string& key,std::shared_ptr<DeveloperToolsState> state) {
  if (!state->picking && !state->inspection) return;
  ++state->revision; state->picking = false;
  if (state->frontendPicking && state->frontend && state->frontend->IsValid()) {
    state->frontendPicking = false;
    auto params = CefDictionaryValue::Create();
    params->SetString("expression","globalThis.__browserStopInspection?.()");
    state->frontend->GetHost()->ExecuteDevToolsMethod(0,"Runtime.evaluate",params);
    DeveloperToolsChanged(key); return;
  }
  if (auto browser = browsers.find(key); browser != browsers.end()) {
    auto params = CefDictionaryValue::Create(); params->SetString("mode","none");
    browser->second->GetHost()->ExecuteDevToolsMethod(0,"Overlay.setInspectMode",params);
    browser->second->GetHost()->ExecuteDevToolsMethod(0,"Overlay.hideHighlight",nullptr);
    // Release this session's overlay before the frontend enables its own.
    // Two active InspectorOverlayAgents can paint the same compositor layer.
    browser->second->GetHost()->ExecuteDevToolsMethod(0,"Overlay.disable",nullptr);
  }
  // CEF must finish dispatching the observer before its registration is freed.
  auto registration = state->inspection; state->inspection = nullptr;
  dispatch_async(dispatch_get_main_queue(), ^{ (void)registration; });
  DeveloperToolsChanged(key);
}
static void CancelNativeInspection(const std::string& key) {
  auto it = developerTools.find(key);
  if (it != developerTools.end() && it->second->picking) StopNativeInspection(key,it->second);
}
static void ConfigureEmbeddedDeveloperTools(std::shared_ptr<DeveloperToolsState> state) {
  BrowserTrace(@"devtools.configure",@{@"browser":@(state->frontend->GetIdentifier())});
  auto host = state->frontend->GetHost();
  host->ExecuteDevToolsMethod(0,"Runtime.enable",nullptr);
  for (const char *name : {"__browserInspectionEnded","__browserDevToolsHost","__browserDevToolsTrace"}) {
    auto binding = CefDictionaryValue::Create(); binding->SetString("name",name);
    host->ExecuteDevToolsMethod(0,"Runtime.addBinding",binding);
  }
  // Reuse Chromium's device toolbar, presets, scaling and responsive handles.
  // AppKit only places the real page in its inspected-page placeholder.
  // Run in this trusted frontend's main world, never in the inspected site.
  const char *script = R"JS((()=>{
    if(globalThis.__browserEmbeddedHost)return;
    globalThis.__browserEmbeddedHost=true;
    const trace=(event,detail={})=>globalThis.__browserDevToolsTrace(JSON.stringify({event,...detail}));
    addEventListener('error',event=>trace('frontend.error',{message:String(event.message).slice(0,800)}));
    addEventListener('unhandledrejection',event=>trace('frontend.rejection',{message:String(event.reason).slice(0,800)}));
    let attempts=0;
    const setup=async()=>{try{
      if(!document.querySelector('.root-view'))throw 0;
      const UI=await import('/bundled/ui/legacy/legacy.js');
      const Host=await import('/bundled/core/host/host.js');
      const Emulation=await import('/bundled/panels/emulation/emulation.js');
      const Root=await import('/bundled/core/root/root.js');
      const host=Host.InspectorFrontendHost.InspectorFrontendHostInstance;
      host.setInspectedPageBounds=bounds=>globalThis.__browserDevToolsHost(JSON.stringify({type:'bounds',...bounds}));
      host.closeWindow=()=>globalThis.__browserDevToolsHost(JSON.stringify({type:'close'}));
      // Enable frontend emulation actions without asking Chrome to dock its
      // hidden backend window (CEF's host cannot handle SetIsDocked(true)).
      const queryParam=Root.Runtime.Runtime.queryParam.bind(Root.Runtime.Runtime);
      Root.Runtime.Runtime.queryParam=name=>name==='can_dock'?'true':queryParam(name);
      UI.ActionRegistry.ActionRegistry.instance().registerActions();
      UI.ShortcutRegistry.ShortcutRegistry.instance().registerBindings();
      const deviceAction=UI.ActionRegistry.ActionRegistry.instance().getAction('emulation.toggle-device-mode');
      if(!deviceAction.__browserTraced){
        deviceAction.__browserTraced=true;
        deviceAction.addEventListener('Toggled',event=>trace('device.state',{enabled:event.data}));
        const execute=deviceAction.execute.bind(deviceAction);
        deviceAction.execute=async()=>{trace('device.toggle.begin',{enabled:deviceAction.toggled()});
          try{const result=await execute();trace('device.toggle.end',{enabled:deviceAction.toggled()});return result;}
          catch(error){trace('device.toggle.error',{message:String(error).slice(0,800)});throw error;}};
      }
      const inspector=UI.InspectorView.InspectorView.instance();
      const root=inspector.parentWidget();
      const split=new UI.SplitWidget.SplitWidget(true,true,'browser-tools.split-view-state',368,300,true);
      const device=new Emulation.DeviceModeView.DeviceModeView();
      const placeholder=Emulation.InspectedPagePlaceholder.InspectedPagePlaceholder.instance();
      placeholder.addEventListener('Update',event=>host.setInspectedPageBounds(event.data));
      inspector.detach();
      split.show(root.element);
      split.setSidebarWidget(inspector);
      split.setMainWidget(device);
      split.setDefaultFocusedChild(inspector);
      inspector.setOwnerSplit(split);
      split.showBoth();
      const toolbar=inspector.tabbedPane.leftToolbar();
      toolbar.style.minWidth='69px';
      const button=UI.Toolbar.Toolbar.createActionButton('emulation.toggle-device-mode');
      button.element.dataset.browserDeviceToggle='true';
      toolbar.appendToolbarItem(button);
      UI.DockController.DockController.instance().closeButton.setVisible(true);
      placeholder.update();
      delete globalThis.__browserEmbeddedError;
      globalThis.__browserEmbeddedReady=true;
      trace('frontend.ready',{mobile:deviceAction.toggled()});
    }catch(error){globalThis.__browserEmbeddedError=String(error);if(attempts===0||attempts===79)trace('frontend.setup-error',{attempt:attempts,message:String(error).slice(0,800)});if(++attempts<80)setTimeout(setup,50);}};
    setup();
  })())JS";
  auto params = CefDictionaryValue::Create(); params->SetString("expression",script);
  host->ExecuteDevToolsMethod(0,"Runtime.evaluate",params);
}
static void ApplyDeveloperPanel(std::shared_ptr<DeveloperToolsState> state,int attempt=0) {
  if (!state->frontend || !state->frontend->IsValid() || state->closed) return;
  auto frame = state->frontend->GetMainFrame();
  if (!frame || frame->GetURL().ToString().rfind("devtools://",0) != 0) {
    if (attempt < 80) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{ ApplyDeveloperPanel(state,attempt+1); });
    return;
  }
  // Only trusted DevTools modules run this code. Backend node IDs identify the
  // actual selected node even if opening the dock changes the page's layout.
  std::string script = "(()=>{const request=globalThis.__browserPanelRequest=(globalThis.__browserPanelRequest||0)+1;let n=0;const open=async()=>{if(request!==globalThis.__browserPanelRequest)return;try{if(!document.querySelector('.root-view'))throw 0;const UI=await import('/bundled/ui/legacy/legacy.js');if(request!==globalThis.__browserPanelRequest)return;await UI.InspectorView.InspectorView.instance().showPanel('"+state->panel+"');";
  if (state->selectedNode > 0) {
    script += "const SDK=await import('/bundled/core/sdk/sdk.js');const Common=await import('/bundled/core/common/common.js');const target=SDK.TargetManager.TargetManager.instance().primaryPageTarget();if(!target)throw 0;const node=await new SDK.DOMModel.DeferredDOMNode(target,"+std::to_string(state->selectedNode)+").resolvePromise();if(!node)throw 0;if(request===globalThis.__browserPanelRequest)await Common.Revealer.reveal(node);";
  }
  script += "}catch(e){if(++n<80)setTimeout(open,50);}};open();})()";
  auto params = CefDictionaryValue::Create(); params->SetString("expression",script);
  state->frontend->GetHost()->ExecuteDevToolsMethod(0,"Runtime.evaluate",params);
}
class DeveloperToolsClient : public CefClient, public CefLifeSpanHandler, public CefLoadHandler, public CefRequestHandler {
 public:
  DeveloperToolsClient(std::string key,std::shared_ptr<DeveloperToolsState> state) : key_(std::move(key)),state_(std::move(state)) {}
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  void OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser,TerminationStatus status,int code,const CefString&) override {
    BrowserTrace(@"devtools.renderer-terminated",@{@"tab":@(key_.c_str()),@"browser":@(browser->GetIdentifier()),@"status":@(status),@"code":@(code)});
  }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    BrowserTrace(@"devtools.created",@{@"tab":@(key_.c_str()),@"browser":@(browser->GetIdentifier())});
    state_->frontend = browser; state_->opening = false;
    if (state_->closed) browser->GetHost()->CloseBrowser(true);
    DeveloperToolsChanged(key_);
  }
  void OnLoadEnd(CefRefPtr<CefBrowser>,CefRefPtr<CefFrame> frame,int) override {
    if (!frame->IsMain() || state_->closed) return;
    std::string url = frame->GetURL().ToString();
    if (url.rfind("devtools://devtools/bundled/devtools_app.html",0) != 0) return;
    state_->embeddedLayout = true;
    ConfigureEmbeddedDeveloperTools(state_);
    ApplyDeveloperPanel(state_); DeveloperToolsChanged(key_);
  }
  void OnBeforeClose(CefRefPtr<CefBrowser>) override {
    BrowserTrace(@"devtools.before-close",@{@"tab":@(key_.c_str()),@"quitting":@(quitting)});
    state_->frontendEvents = nullptr;
    state_->frontend = nullptr; state_->closed = true;
    StopNativeInspection(key_,state_);
    [state_->pane removeFromSuperview]; [state_->divider removeFromSuperview];
    auto it = developerTools.find(key_);
    if (it != developerTools.end() && it->second == state_) developerTools.erase(it);
    DeveloperToolsChanged(key_);
  }
 private:
  std::string key_;
  std::shared_ptr<DeveloperToolsState> state_;
  IMPLEMENT_REFCOUNTING(DeveloperToolsClient);
};
class DeveloperFrontendEvents : public CefDevToolsMessageObserver {
 public:
  DeveloperFrontendEvents(std::string key,std::shared_ptr<DeveloperToolsState> state) : key_(std::move(key)),state_(state) {}
  void OnDevToolsEvent(CefRefPtr<CefBrowser>,const CefString& method,const void* params,size_t size) override {
    auto state = state_.lock();
    if (!state || state->closed || method != "Runtime.bindingCalled" || size > 4096) return;
    id json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:params length:size] options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) return;
    if ([json[@"name"] isEqual:@"__browserDevToolsTrace"] && [json[@"payload"] isKindOfClass:NSString.class]) {
      id detail = [NSJSONSerialization JSONObjectWithData:[json[@"payload"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
      if ([detail isKindOfClass:NSDictionary.class]) BrowserTrace(@"devtools.frontend",@{@"tab":@(key_.c_str()),@"detail":detail});
      return;
    }
    if ([json[@"name"] isEqual:@"__browserDevToolsHost"] && [json[@"payload"] isKindOfClass:NSString.class]) {
      id event = [NSJSONSerialization JSONObjectWithData:[json[@"payload"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
      if (![event isKindOfClass:NSDictionary.class]) return;
      const std::string key = key_;
      if ([event[@"type"] isEqual:@"close"]) {
        BrowserTrace(@"devtools.frontend-close-request",@{@"tab":@(key_.c_str())});
        dispatch_async(dispatch_get_main_queue(), ^{ CloseTabDeveloperTools(key); });
      } else if ([event[@"type"] isEqual:@"bounds"]) {
        for (NSString *name in @[@"x",@"y",@"width",@"height"]) {
          if (![event[name] isKindOfClass:NSNumber.class] || !std::isfinite([event[name] doubleValue]) || [event[name] doubleValue] < 0 || [event[name] doubleValue] > 32768) return;
        }
        NSRect bounds = NSMakeRect([event[@"x"] doubleValue],[event[@"y"] doubleValue],[event[@"width"] doubleValue],[event[@"height"] doubleValue]);
        if (!CanLayoutChromeBackend(bounds)) {
          BrowserTrace(@"devtools.bounds-deferred",@{@"tab":@(key_.c_str()),@"rect":NSStringFromRect(bounds)});
          return;
        }
        if (!NSEqualRects(bounds,state->inspectedBounds)) {
          ++state->boundsUpdates;
          double now = NSDate.date.timeIntervalSince1970;
          if (now-state->lastBoundsTrace > 0.1) {
            state->lastBoundsTrace = now;
            BrowserTrace(@"devtools.bounds",@{@"tab":@(key_.c_str()),@"rect":NSStringFromRect(bounds),@"updates":@(state->boundsUpdates),
                @"container":NSStringFromRect(state->container.bounds),@"flipped":@(state->container.flipped)});
          }
          state->inspectedBounds = bounds;
          dispatch_async(dispatch_get_main_queue(), ^{ if (!state->closed && !quitting) LayoutChromeTab(key); });
        }
      }
      return;
    }
    if (!state->frontendPicking || ![json[@"name"] isEqual:@"__browserInspectionEnded"]) return;
    state->frontendPicking = false; state->picking = false;
    NSString *panel = json[@"payload"];
    if ([@[@"console",@"network",@"elements"] containsObject:panel]) state->panel = panel.UTF8String;
    DeveloperToolsChanged(key_);
  }
 private:
  std::string key_;
  std::weak_ptr<DeveloperToolsState> state_;
  IMPLEMENT_REFCOUNTING(DeveloperFrontendEvents);
};
class DeveloperToolsWindow : public TrackedChromeWindow {
 public:
  DeveloperToolsWindow(std::string key,std::shared_ptr<DeveloperToolsState> state,CefRefPtr<CefBrowserView> view) : key_(std::move(key)),state_(std::move(state)),view_(view) {}
  bool IsFrameless(CefRefPtr<CefWindow>) override { return true; }
  bool WithStandardWindowButtons(CefRefPtr<CefWindow>) override { return false; }
  bool CanResize(CefRefPtr<CefWindow>) override { return false; }
  bool CanMinimize(CefRefPtr<CefWindow>) override { return false; }
  bool CanMaximize(CefRefPtr<CefWindow>) override { return false; }
  cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  void WindowCreated(CefRefPtr<CefWindow> window) override {
    state_->window = window; state_->view = view_;
    state_->frontend = view_->GetBrowser(); state_->opening = false;
    state_->frontendEvents = state_->frontend->GetHost()->AddDevToolsMessageObserver(new DeveloperFrontendEvents(key_,state_));
    state_->frontend->GetHost()->ExecuteDevToolsMethod(0,"Runtime.enable",nullptr);
    auto binding = CefDictionaryValue::Create(); binding->SetString("name","__browserInspectionEnded");
    state_->frontend->GetHost()->ExecuteDevToolsMethod(0,"Runtime.addBinding",binding);
    window->AddChildView(view_);
    NSView *handle = (__bridge NSView*)window->GetWindowHandle();
    handle.window.identifier = @"local.browser.backend";
    handle.window.excludedFromWindowsMenu = YES; handle.window.hasShadow = NO;
    [handle.window orderOut:nil];
    LayoutChromeTab(key_);
    ApplyDeveloperPanel(state_);
  }
  bool CanClose(CefRefPtr<CefWindow>) override {
    auto browser = view_ ? view_->GetBrowser() : nullptr;
    return !browser || browser->GetHost()->TryCloseBrowser();
  }
  void WindowDestroyed(CefRefPtr<CefWindow>) override {
    [state_->content removeFromSuperview];
    state_->window = nullptr; state_->view = nullptr; view_ = nullptr;
  }
 private:
  std::string key_;
  std::shared_ptr<DeveloperToolsState> state_;
  CefRefPtr<CefBrowserView> view_;
  IMPLEMENT_REFCOUNTING(DeveloperToolsWindow);
};
static bool EmbedDeveloperTools(CefRefPtr<CefBrowserView> source,CefRefPtr<CefBrowserView> popup) {
  auto browser = source->GetBrowser();
  for (auto& entry : browsers) {
    if (!entry.second->IsSame(browser)) continue;
    auto it = developerTools.find(entry.first);
    if (it != developerTools.end()) CefWindow::CreateTopLevelWindow(new DeveloperToolsWindow(entry.first,it->second,popup));
    else popup->GetBrowser()->GetHost()->CloseBrowser(true);
    return true; // Never allow CEF's default detached window for a tab.
  }
  return false;
}
static void PrepareDeveloperPopup(const std::string& key,CefRefPtr<CefClient>& client) {
  auto& state = developerTools[key];
  if (!state || state->closed) state = std::make_shared<DeveloperToolsState>();
  state->panelOpen = true;
  client = new DeveloperToolsClient(key,state);
}
static void ShowDeveloperTools(std::string key,std::shared_ptr<DeveloperToolsState> state,int attempt) {
  if (!attempt) BrowserTrace(@"devtools.show",@{@"tab":@(key.c_str()),@"panel":@(state->panel.c_str()),@"existing":@(state->frontend != nullptr)});
  auto browser = browsers.find(key);
  if (state->closed || browser == browsers.end() || quitting) return;
  state->panelOpen = true; LayoutChromeTab(key);
  auto host = browser->second->GetHost();
  if (state->opening && !state->frontend) { DeveloperToolsChanged(key); return; }
  if (host->HasDevTools() && !state->frontend) {
    if (attempt == 0) host->CloseDevTools();
    if (attempt >= 40) { state->closed = true; developerTools.erase(key); DeveloperToolsChanged(key); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{ ShowDeveloperTools(key,state,attempt+1); });
    return;
  }
  // Reusing the embedded frontend must not ask Chromium to focus/show its
  // backend widget. Only its WebContents belongs to the visible AppKit window.
  if (state->frontend) { ApplyDeveloperPanel(state); state->frontend->GetHost()->SetFocus(true); }
  else {
    CefWindowInfo info; CefBrowserSettings settings; state->opening = true;
    host->ShowDevTools(info,new DeveloperToolsClient(key,state),settings,CefPoint());
  }
  DeveloperToolsChanged(key);
}
static void CloseTabDeveloperTools(const std::string& key) {
  BrowserTrace(@"devtools.close",@{@"tab":@(key.c_str()),@"quitting":@(quitting)});
  auto it = developerTools.find(key);
  if (it != developerTools.end()) {
    auto state = it->second; state->closed = true; StopNativeInspection(key,state);
    [state->pane removeFromSuperview]; [state->divider removeFromSuperview]; developerTools.erase(it);
  }
  auto browser = browsers.find(key);
  if (browser != browsers.end()) browser->second->GetHost()->CloseDevTools();
  DeveloperToolsChanged(key);
}
static void SetDeveloperToolsVisible(const std::string& key,bool visible) {
  if (!visible) CancelNativeInspection(key);
  auto it = developerTools.find(key);
  if (it == developerTools.end()) return;
  auto state = it->second;
  state->pane.hidden = !visible || !state->panelOpen;
  state->divider.hidden = !visible || !state->panelOpen || state->embeddedLayout;
  if (state->frontend) {
    using Visibility = int (*)(int,int);
    auto change = reinterpret_cast<Visibility>(BrowserEngineSymbol("browser_native_view_visibility_v1"));
    if (change) change(state->frontend->GetIdentifier(),visible && state->panelOpen);
  }
}
class NativeInspection : public CefDevToolsMessageObserver {
 public:
  NativeInspection(std::string key,std::shared_ptr<DeveloperToolsState> state) : key_(std::move(key)),state_(state) {}
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>,int id,bool success,const void*,size_t) override {
    auto state = state_.lock();
    if (state && state->picking && id == state->inspectionMessage && !success) StopNativeInspection(key_,state);
  }
  void OnDevToolsEvent(CefRefPtr<CefBrowser>,const CefString& method,const void* params,size_t size) override {
    auto state = state_.lock(); if (!state || !state->picking || state->closed) return;
    const auto name = method.ToString();
    if (name == "Overlay.inspectModeCanceled") { StopNativeInspection(key_,state); return; }
    if (name != "Overlay.inspectNodeRequested" || !params || size > 1024*1024) return;
    id json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:params length:size] options:0 error:nil];
    NSNumber *node = [json isKindOfClass:NSDictionary.class] ? json[@"backendNodeId"] : nil;
    if (![node isKindOfClass:NSNumber.class] || node.intValue <= 0) return;
    StopNativeInspection(key_,state); state->selectedNode = node.intValue; state->panel = "elements";
    const auto revision = state->revision; const std::string key = key_;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!state->closed && state->revision == revision && tabVisibility[key]) ShowDeveloperTools(key,state);
    });
  }
  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser>) override {
    if (auto state = state_.lock(); state && state->picking) {
      // The page is being torn down. Sending a protocol command here would
      // reattach its agent while CEF is iterating the detached observers.
      state->picking = false; ++state->revision;
      auto registration = state->inspection; state->inspection = nullptr;
      dispatch_async(dispatch_get_main_queue(), ^{ (void)registration; });
      DeveloperToolsChanged(key_);
    }
  }
 private:
  std::string key_;
  std::weak_ptr<DeveloperToolsState> state_;
  IMPLEMENT_REFCOUNTING(NativeInspection);
};
static void StartNativeInspection(const std::string& key,std::shared_ptr<DeveloperToolsState> state) {
  if (state->picking) { StopNativeInspection(key,state); return; }
  auto browser = browsers.find(key); if (browser == browsers.end()) return;
  state->picking = true; state->selectedNode = 0; ++state->revision;
  auto host = browser->second->GetHost();
  if (state->frontend) {
    // An open frontend already owns an overlay session. Use its selector so
    // we never enable a second overlay agent on the inspected page.
    state->frontendPicking = true;
    auto binding = CefDictionaryValue::Create(); binding->SetString("name","__browserInspectionEnded");
    state->frontend->GetHost()->ExecuteDevToolsMethod(0,"Runtime.enable",nullptr);
    state->frontend->GetHost()->ExecuteDevToolsMethod(0,"Runtime.addBinding",binding);
    auto params = CefDictionaryValue::Create();
    params->SetString("expression",R"((async()=>{
      const SDK=await import('/bundled/core/sdk/sdk.js');
      const UI=await import('/bundled/ui/legacy/legacy.js');
      globalThis.__browserStopInspection?.();
      const models=SDK.TargetManager.TargetManager.instance().models(SDK.OverlayModel.OverlayModel);
      const cleanup=()=>{for(const model of models)model.removeEventListener(SDK.OverlayModel.Events.EXITED_INSPECT_MODE,ended);delete globalThis.__browserStopInspection;};
      const ended=()=>{cleanup();setTimeout(()=>globalThis.__browserInspectionEnded(UI.InspectorView.InspectorView.instance().tabbedPane.selectedTabId||'elements'),150);};
      globalThis.__browserStopInspection=()=>{cleanup();for(const model of models)void model.setInspectMode('none');};
      for(const model of models){model.addEventListener(SDK.OverlayModel.Events.EXITED_INSPECT_MODE,ended);await model.setInspectMode('searchForNode');}
    })())");
    state->frontend->GetHost()->ExecuteDevToolsMethod(0,"Runtime.evaluate",params);
    host->SetFocus(true); DeveloperToolsChanged(key); return;
  }
  state->inspection = host->AddDevToolsMessageObserver(new NativeInspection(key,state));
  host->ExecuteDevToolsMethod(0,"DOM.enable",nullptr);
  host->ExecuteDevToolsMethod(0,"Overlay.enable",nullptr);
  auto value = CefParseJSON(R"({"mode":"searchForNode","highlightConfig":{"showInfo":true,"showStyles":true,"showAccessibilityInfo":true,"contentColor":{"r":111,"g":168,"b":220,"a":0.66},"paddingColor":{"r":147,"g":196,"b":125,"a":0.55},"borderColor":{"r":255,"g":229,"b":153,"a":0.66},"marginColor":{"r":246,"g":178,"b":107,"a":0.66}}})",JSON_PARSER_RFC);
  state->inspectionMessage = host->ExecuteDevToolsMethod(0,"Overlay.setInspectMode",value->GetDictionary());
  host->SetFocus(true); DeveloperToolsChanged(key);
}

class PageCaptureRequest : public CefDevToolsMessageObserver {
 public:
  explicit PageCaptureRequest(void (^completion)(NSData*)) : completion_([completion copy]) {}
  void Start(CefRefPtr<CefBrowser> browser,bool fullPage=false,double pixelScale=1) {
    browser_ = browser;
    registration_ = browser->GetHost()->AddDevToolsMessageObserver(this);
    full_page_ = fullPage; pixel_scale_ = std::max(1.0,pixelScale);
    if (fullPage) {
      phase_ = Phase::SaveScroll;
      // Keep the restore state in this document's execution context. Navigation
      // destroys the object instead of applying an old offset to a new page.
      auto params = CefDictionaryValue::Create();
      params->SetString("expression","({root:document.scrollingElement,x:scrollX,y:scrollY})");
      message_ = browser->GetHost()->ExecuteDevToolsMethod(0,"Runtime.evaluate",params);
    }
    else Screenshot(browser,nullptr);
    if (!message_) { Finish(nil); return; }
    CefRefPtr<PageCaptureRequest> keep(this);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ keep->Finish(nil); });
  }
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser,int message,bool success,const void* result,size_t size) override {
    if (message != message_ || finished_) return;
    if (phase_ == Phase::RestoreScroll) { Complete(success && IsTrueResult(result,size) ? pending_image_ : nil); return; }
    if (phase_ == Phase::SaveScroll) {
      id json = success && result && size < 65536 ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:result length:size] options:0 error:nil] : nil;
      id object = [json isKindOfClass:NSDictionary.class] ? json[@"result"] : nil;
      id identifier = [object isKindOfClass:NSDictionary.class] ? object[@"objectId"] : nil;
      if (![identifier isKindOfClass:NSString.class]) { Finish(nil); return; }
      scroll_object_ = CefStr(identifier); phase_ = Phase::ScrollTop;
      CallScrollFunction(R"JS(function(){
        if(this.root)this.root.scrollTo({left:0,top:0,behavior:'instant'});
        return new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(true))));
      })JS",true);
      if (!message_) Finish(nil); return;
    }
    if (phase_ == Phase::ScrollTop) {
      if (!success || !IsTrueResult(result,size)) { Finish(nil); return; }
      phase_ = Phase::Capture;
      message_ = browser->GetHost()->ExecuteDevToolsMethod(0,"Page.getLayoutMetrics",nullptr);
      if (!message_) Finish(nil); return;
    }
    if (full_page_ && !screenshot_) {
      id json = success && result && size < 65536 ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:result length:size] options:0 error:nil] : nil;
      if (clip_) {
        id result = [json isKindOfClass:NSDictionary.class] ? json[@"result"] : nil;
        id ratio = [result isKindOfClass:NSDictionary.class] ? result[@"value"] : nil;
        if (![ratio isKindOfClass:NSNumber.class] || !std::isfinite([ratio doubleValue]) || [ratio doubleValue] <= 0) { Finish(nil); return; }
        pixel_scale_ = std::max(pixel_scale_,[ratio doubleValue]);
        const double width = clip_->GetDouble("width"), height = clip_->GetDouble("height");
        const double scale = std::min({1.0,std::sqrt(64000000.0/(width*height*pixel_scale_*pixel_scale_)),30000.0/(std::max(width,height)*pixel_scale_)});
        clip_->SetDouble("scale",scale); Screenshot(browser,clip_); if (!message_) Finish(nil); return;
      }
      id content = [json isKindOfClass:NSDictionary.class] ? json[@"cssContentSize"] : nil;
      if (![content isKindOfClass:NSDictionary.class] || ![content[@"width"] isKindOfClass:NSNumber.class] || ![content[@"height"] isKindOfClass:NSNumber.class]) { Finish(nil); return; }
      const double width = [content[@"width"] doubleValue], height = [content[@"height"] doubleValue];
      if (!std::isfinite(width) || !std::isfinite(height) || width < 1 || height < 1 || width > 1e7 || height > 1e7) { Finish(nil); return; }
      // Keep the entire document, reducing resolution only for very long pages.
      // Bound both bitmap memory and Chromium's maximum texture dimension.
      clip_ = CefDictionaryValue::Create(); clip_->SetDouble("x",0); clip_->SetDouble("y",0);
      clip_->SetDouble("width",width); clip_->SetDouble("height",height);
      auto params = CefDictionaryValue::Create(); params->SetString("expression","devicePixelRatio"); params->SetBool("returnByValue",true);
      message_ = browser->GetHost()->ExecuteDevToolsMethod(0,"Runtime.evaluate",params); if (!message_) Finish(nil); return;
    }
    NSData *png = nil;
    if (success && result && size < 128*1024*1024) {
      NSData *json = [NSData dataWithBytes:result length:size];
      id value = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
      id encoded = [value isKindOfClass:NSDictionary.class] ? value[@"data"] : nil;
      if ([encoded isKindOfClass:NSString.class]) png = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    }
    Finish(png);
  }
  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser>) override { Complete(nil); }
 private:
  enum class Phase { SaveScroll, ScrollTop, Capture, RestoreScroll };
  static bool IsTrueResult(const void* result,size_t size) {
    if (!result || size > 65536) return false;
    id json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:result length:size] options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class] || json[@"exceptionDetails"] || ![json[@"result"] isKindOfClass:NSDictionary.class]) return false;
    id value = json[@"result"][@"value"];
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
  }
  void CallScrollFunction(const char* function,bool await) {
    auto params = CefDictionaryValue::Create(); params->SetString("objectId",scroll_object_);
    params->SetString("functionDeclaration",function); params->SetBool("awaitPromise",await); params->SetBool("returnByValue",true);
    message_ = browser_->GetHost()->ExecuteDevToolsMethod(0,"Runtime.callFunctionOn",params);
  }
  void Screenshot(CefRefPtr<CefBrowser> browser,CefRefPtr<CefDictionaryValue> clip) {
    screenshot_ = true;
    auto params = CefDictionaryValue::Create(); params->SetString("format","png");
    params->SetBool("fromSurface",true); params->SetBool("captureBeyondViewport",full_page_);
    if (clip) params->SetDictionary("clip",clip);
    message_ = browser->GetHost()->ExecuteDevToolsMethod(0,"Page.captureScreenshot",params);
  }
  void Finish(NSData *data) {
    if (finished_ || phase_ == Phase::RestoreScroll) return;
    if (!scroll_object_.empty() && browser_ && browser_->IsValid()) {
      pending_image_ = data; phase_ = Phase::RestoreScroll;
      CallScrollFunction("function(){if(this.root?.isConnected)this.root.scrollTo({left:this.x,top:this.y,behavior:'instant'});return true;}",false);
      if (!message_) { Complete(nil); return; }
      CefRefPtr<PageCaptureRequest> keep(this);
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ if (!keep->finished_) keep->Complete(nil); });
      return;
    }
    Complete(data);
  }
  void Complete(NSData *data) {
    if (finished_) return; finished_ = true;
    // Release the registration outside CEF's observer dispatch stack.
    CefRefPtr<PageCaptureRequest> keep(this);
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!keep->scroll_object_.empty() && keep->browser_ && keep->browser_->IsValid()) {
        auto params = CefDictionaryValue::Create(); params->SetString("objectId",keep->scroll_object_);
        keep->browser_->GetHost()->ExecuteDevToolsMethod(0,"Runtime.releaseObject",params);
      }
      keep->registration_ = nullptr;
      keep->browser_ = nullptr; keep->pending_image_ = nil;
      auto completion = keep->completion_; keep->completion_ = nil;
      if (completion) completion(data);
    });
  }
  int message_ = 0;
  bool finished_ = false;
  bool full_page_ = false, screenshot_ = false;
  Phase phase_ = Phase::Capture;
  CefString scroll_object_;
  CefRefPtr<CefBrowser> browser_;
  NSData *pending_image_ = nil;
  double pixel_scale_ = 1;
  CefRefPtr<CefDictionaryValue> clip_;
  CefRefPtr<CefRegistration> registration_;
  void (^completion_)(NSData*);
  IMPLEMENT_REFCOUNTING(PageCaptureRequest);
};

// Read-only hit testing. The native capture overlay consumes the click, so no
// page event handlers, links or forms are activated by selecting a capture.
class CaptureElementRequest : public CefDevToolsMessageObserver {
 public:
  explicit CaptureElementRequest(void (^done)(NSDictionary*)) : completion_([done copy]) {}
  void Start(CefRefPtr<CefBrowser> browser,NSPoint point) {
    registration_ = browser->GetHost()->AddDevToolsMessageObserver(this);
    const char* body = R"JS((u,v)=>{
      const W=innerWidth,H=innerHeight;let x=u*W,y=v*H,doc=document,ox=0,oy=0,element;
      for(let depth=0;depth<12;depth++) {
        element=doc.elementFromPoint(x,y);if(!element)return null;
        for(let n=0;n<8&&element.shadowRoot;n++){const next=element.shadowRoot.elementFromPoint(x,y);if(!next||next===element)break;element=next;}
        if(element.tagName!=='IFRAME')break;
        try{if(!element.contentDocument)break;const r=element.getBoundingClientRect();x-=r.x+element.clientLeft;y-=r.y+element.clientTop;ox+=r.x+element.clientLeft;oy+=r.y+element.clientTop;doc=element.contentDocument;}catch{break;}
      }
      if(!element||element===doc.body||element===doc.documentElement)return null;
      const card=element.closest('a,button,article,figure,[role="button"]');
      if(card){const r=card.getBoundingClientRect();if(r.width*r.height<W*H*0.94)element=card;}
      let r=element.getBoundingClientRect();
      while((r.width<8||r.height<8)&&element.parentElement){element=element.parentElement;r=element.getBoundingClientRect();}
      if(element===doc.body||element===doc.documentElement||r.width*r.height>W*H*0.94)return null;
      // Empty layout wrappers are free-selection space, not capture targets.
      const style=doc.defaultView.getComputedStyle(element);
      const semantic=element.matches('a,button,article,figure,img,picture,video,canvas,svg,iframe,input,textarea,[role="button"]');
      const ownText=[...element.childNodes].some(n=>n.nodeType===3&&n.textContent.trim());
      const visual=style.backgroundImage!=='none'||(style.backgroundColor!=='rgba(0, 0, 0, 0)'&&style.backgroundColor!=='transparent');
      if(!semantic&&!ownText&&!visual)return null;
      const left=Math.max(0,r.left+ox),top=Math.max(0,r.top+oy),right=Math.min(W,r.right+ox),bottom=Math.min(H,r.bottom+oy);
      if(right<=left||bottom<=top)return null;
      const corner=style.borderTopLeftRadius;
      const radius=corner.includes('%')?Math.min(r.width,r.height)*parseFloat(corner)/100:parseFloat(corner);
      return {x:left/W,y:top/H,width:(right-left)/W,height:(bottom-top)/H,radius:Math.max(0,Math.min(r.width/2,r.height/2,radius||0))/W};
    })JS";
    NSString *script = [NSString stringWithFormat:@"(%s)(%.8f,%.8f)",body,point.x,point.y];
    auto params = CefDictionaryValue::Create(); params->SetString("expression",CefStr(script)); params->SetBool("returnByValue",true);
    message_ = browser->GetHost()->ExecuteDevToolsMethod(0,"Runtime.evaluate",params);
    if (!message_) { Finish(nil); return; }
    CefRefPtr<CaptureElementRequest> keep(this);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ keep->Finish(nil); });
  }
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>,int message,bool success,const void* result,size_t size) override {
    if (message != message_ || finished_) return;
    id rect = nil;
    if (success && result && size < 8192) {
      id json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:result length:size] options:0 error:nil];
      if ([json isKindOfClass:NSDictionary.class] && [json[@"result"] isKindOfClass:NSDictionary.class]) rect = json[@"result"][@"value"];
    }
    if (![rect isKindOfClass:NSDictionary.class]) { Finish(nil); return; }
    for (NSString *key in @[@"x",@"y",@"width",@"height"]) {
      if (![rect[key] isKindOfClass:NSNumber.class] || !std::isfinite([rect[key] doubleValue]) || [rect[key] doubleValue] < 0 || [rect[key] doubleValue] > 1) { Finish(nil); return; }
    }
    Finish(rect);
  }
  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser>) override { Finish(nil); }
 private:
  void Finish(NSDictionary *rect) {
    if (finished_) return; finished_ = true;
    CefRefPtr<CaptureElementRequest> keep(this);
    dispatch_async(dispatch_get_main_queue(), ^{
      keep->registration_ = nullptr; auto completion = keep->completion_; keep->completion_ = nil; if (completion) completion(rect);
    });
  }
  int message_ = 0;
  bool finished_ = false;
  CefRefPtr<CefRegistration> registration_;
  void (^completion_)(NSDictionary*);
  IMPLEMENT_REFCOUNTING(CaptureElementRequest);
};
