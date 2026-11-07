// Included by BrowserBridge.mm after the shared browser/context lifecycle.
// Do not reparent Chromium's native view: its window owns extension permissions,
// popup anchors, focus, and lifetime. The main AppKit browser keeps its design.
static std::map<std::string, CefRefPtr<CefWindow>> extensionWindows;
static std::map<std::string, CefRefPtr<CefBrowserView>> extensionViews;

static CefRefPtr<CefRequestContext> ContextForProfile(NSString *profileID) {
  NSCharacterSet *valid = [NSCharacterSet characterSetWithCharactersInString:
      @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"];
  if (!profileID.length || profileID.length > 100 ||
      [profileID rangeOfCharacterFromSet:valid.invertedSet].location != NSNotFound) return nullptr;
  auto found = profiles.find(profileID.UTF8String);
  if (found != profiles.end()) return found->second;
  CefRequestContextSettings settings;
  CefString(&settings.accept_language_list) = WebLanguages();
  // An empty CEF cache path creates an off-the-record request context. It must
  // never be substituted with the global context or a temporary disk profile.
  const bool ephemeral = privateProfiles.count(profileID.UTF8String) != 0;
  if (!ephemeral) CefString(&settings.cache_path) = rootCache + "/Profile-" + profileID.UTF8String;
  settings.persist_session_cookies = !ephemeral;
  auto context = CefRequestContext::CreateContext(settings, new ThemeContextHandler(profileID.UTF8String));
  if (context) profiles[profileID.UTF8String] = context;
  return context;
}

// The Store checks client hints before exposing installation. Limit this
// compatibility hint to its exact HTTPS origin; Chromium still validates CRX
// signatures and displays the real permissions dialog. Other sites keep CEF UA.
static void ExtensionStoreCompatibility(CefRefPtr<CefBrowser> browser, bool enabled) {
  auto params = CefDictionaryValue::Create();
  params->SetString("userAgent", "");
  if (enabled) {
    std::string major = std::to_string(CHROME_VERSION_MAJOR);
    std::string version = major + "." + std::to_string(CHROME_VERSION_MINOR) + "." + std::to_string(CHROME_VERSION_BUILD) + "." + std::to_string(CHROME_VERSION_PATCH);
    params->SetString("userAgent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/" + major + ".0.0.0 Safari/537.36");
    auto metadata = CefDictionaryValue::Create();
    auto brands = CefListValue::Create();
    auto versions = CefListValue::Create();
    for (int i = 0; i < 2; i++) {
      auto entry = CefDictionaryValue::Create();
      entry->SetString("brand", i == 0 ? "Chromium" : "Google Chrome");
      entry->SetString("version", major);
      auto fullEntry = entry->Copy(false);
      fullEntry->SetString("version", version);
      brands->SetDictionary(i, entry);
      versions->SetDictionary(i, fullEntry);
    }
    metadata->SetList("brands", brands);
    metadata->SetList("fullVersionList", versions);
    metadata->SetString("platform", "macOS");
    auto os = NSProcessInfo.processInfo.operatingSystemVersion;
    metadata->SetString("platformVersion", std::to_string(os.majorVersion) + "." + std::to_string(os.minorVersion) + "." + std::to_string(os.patchVersion));
    metadata->SetString("architecture", "arm");
    metadata->SetString("bitness", "64");
    metadata->SetString("model", "");
    metadata->SetBool("mobile", false);
    params->SetDictionary("userAgentMetadata", metadata);
  }
  browser->GetHost()->ExecuteDevToolsMethod(0, "Network.setUserAgentOverride", params);
}

class ExtensionClient : public CefClient,
                        public CefLifeSpanHandler,
                        public CefJSDialogHandler,
                        public CefRequestHandler {
 public:
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                      CefRefPtr<CefRequest> request, bool, bool) override {
    if (frame->IsMain()) {
      NSURLComponents *url = [NSURLComponents componentsWithString:Str(request->GetURL())];
      bool store = [url.scheme.lowercaseString isEqualToString:@"https"] &&
                   [url.host.lowercaseString isEqualToString:@"chromewebstore.google.com"] && !url.user && !url.password;
      ExtensionStoreCompatibility(browser, store);
    }
    return false;
  }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    BrowserTrace(@"chrome.unmanaged-created",@{@"browser":@(browser->GetIdentifier()),@"popup":@(browser->IsPopup())});
    browsers[Key(browser)] = browser;
    browser->GetHost()->SetAccessibilityState(STATE_ENABLED);
    if (quitting) dispatch_async(dispatch_get_main_queue(), ^{ QuitNext(); });
  }
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    BrowserTrace(@"chrome.unmanaged-closed",@{@"browser":@(browser->GetIdentifier()),@"quitting":@(quitting)});
    browsers.erase(Key(browser));
    if (quitting) dispatch_async(dispatch_get_main_queue(), ^{ QuitNext(); });
  }
  bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser> browser, const CefString&, bool,
                           CefRefPtr<CefJSDialogCallback> callback) override {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = L(@"Quitter cette page ?", @"Leave this page?");
    alert.informativeText = L(@"Les modifications non enregistrées risquent d’être perdues.",
                              @"Unsaved changes may be lost.");
    [alert addButtonWithTitle:L(@"Rester", @"Stay")];
    [alert addButtonWithTitle:L(@"Quitter", @"Leave")];
    auto finish = ^(NSModalResponse response) {
      bool leave = response == NSAlertSecondButtonReturn;
      if (!leave && quitting) CancelBrowserQuit();
      callback->Continue(leave, CefString());
    };
    NSView *view = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    if (view.window) [alert beginSheetModalForWindow:view.window completionHandler:finish];
    else finish([alert runModal]);
    return true;
  }
 private:
  static std::string Key(CefRefPtr<CefBrowser> browser) {
    return "extension-window:" + std::to_string(browser->GetIdentifier());
  }
  IMPLEMENT_REFCOUNTING(ExtensionClient);
};
static CefRefPtr<CefClient> NewExtensionClient() { return new ExtensionClient(); }

class ExtensionWindow : public CefWindowDelegate {
 public:
  ExtensionWindow(CefRefPtr<CefBrowserView> view, std::string profile, NSString *name)
      : view_(view), profile_(std::move(profile)), title_(CefStr([@"Extensions — " stringByAppendingString:name])) {}
  void OnWindowCreated(CefRefPtr<CefWindow> window) override {
    if (!profile_.empty()) { extensionWindows[profile_] = window; extensionViews[profile_] = view_; }
    window->SetTitle(title_);
    CefBoxLayoutSettings settings;
    settings.horizontal = false;
    window->SetToFillLayout();
    auto page = CefPanel::CreatePanel(nullptr);
    auto layout = page->SetToBoxLayout(settings);
    window->AddChildView(page);
    page->AddChildView(view_);
    layout->SetFlexForView(view_, 1);
    if (auto toolbar = view_->GetChromeToolbar()) page->AddChildViewAt(toolbar, 0);
    window->SetSize(CefSize(1000, 720));
    window->Layout();
    window->Show();
    view_->RequestFocus();
  }
  void OnWindowDestroyed(CefRefPtr<CefWindow> window) override {
    auto found = extensionWindows.find(profile_);
    if (found != extensionWindows.end() && found->second->IsSame(window)) { extensionWindows.erase(found); extensionViews.erase(profile_); }
    view_ = nullptr;
  }
  bool CanClose(CefRefPtr<CefWindow>) override {
    auto browser = view_ ? view_->GetBrowser() : nullptr;
    return !browser || browser->GetHost()->TryCloseBrowser();
  }
  CefSize GetMinimumSize(CefRefPtr<CefView>) override { return CefSize(640, 480); }
  cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
 private:
  CefRefPtr<CefBrowserView> view_;
  const std::string profile_;
  const CefString title_;
  IMPLEMENT_REFCOUNTING(ExtensionWindow);
};

class ExtensionView : public CefBrowserViewDelegate {
 public:
  cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  ChromeToolbarType GetChromeToolbarType(CefRefPtr<CefBrowserView>) override { return CEF_CTT_NORMAL; }
  bool OnPopupBrowserViewCreated(CefRefPtr<CefBrowserView>, CefRefPtr<CefBrowserView> popup, bool) override {
    if (quitting) { popup->GetBrowser()->GetHost()->CloseBrowser(true); return true; }
    CefWindow::CreateTopLevelWindow(new ExtensionWindow(popup, "", @"Arc Reborn"));
    return true;
  }
 private:
  IMPLEMENT_REFCOUNTING(ExtensionView);
};

static bool ShowExtensionAddress(NSString *profileID, NSString *name, const std::string& url) {
  CEF_REQUIRE_UI_THREAD();
  auto context = ContextForProfile(profileID);
  if (!context) return false;
  const std::string key = profileID.UTF8String;
  if (!readyProfiles.count(key)) {
    profileReadyCallbacks[key].push_back([^{
      if (!quitting) ShowExtensionAddress(profileID, name, url);
    } copy]);
    return true;
  }
  auto existing = extensionWindows.find(key);
  if (existing != extensionWindows.end() && !existing->second->IsClosed()) {
    auto window = existing->second;
    auto found = extensionViews.find(key);
    if (found != extensionViews.end() && found->second->GetBrowser()) {
      found->second->GetBrowser()->GetMainFrame()->LoadURL(url);
      found->second->RequestFocus();
    }
    window->Show(); window->Activate();
    return true;
  }
  CefBrowserSettings settings;
  auto view = CefBrowserView::CreateBrowserView(NewExtensionClient(), url, settings, nullptr, context, new ExtensionView());
  return view && CefWindow::CreateTopLevelWindow(new ExtensionWindow(view, key, name));
}

static bool ShowExtensionWindow(NSString *profileID, NSString *name, bool store) {
  return ShowExtensionAddress(profileID, name, store ? "https://chromewebstore.google.com/category/extensions" : "chrome://extensions/");
}

static bool RouteExtensionStore(CefRefPtr<CefBrowser> browser, NSString *address) {
  NSURLComponents *url = [NSURLComponents componentsWithString:address];
  if (quitting || ![url.scheme.lowercaseString isEqualToString:@"https"] ||
      ![url.host.lowercaseString isEqualToString:@"chromewebstore.google.com"] || url.user || url.password) return false;
  for (auto &entry : profiles) {
    if (entry.second->IsSame(browser->GetHost()->GetRequestContext())) {
      // Leave the current page intact. Opening the store is application work,
      // scheduled after Chromium returns from its navigation callback.
      NSString *profile = [NSString stringWithUTF8String:entry.first.c_str()];
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!quitting) ShowExtensionAddress(profile, L(@"Profil actif", @"Active profile"), address.UTF8String);
      });
      return true;
    }
  }
  return false;
}
