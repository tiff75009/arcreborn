// SPDX-License-Identifier: MPL-2.0
// One browser per explicit recovery keeps simultaneous retries of the same URL
// distinct and keeps the original profile alive if the initiating tab closes.
using DownloadRecoveryUpdate = void (^)(NSDictionary<NSString*, id>*);

class RecoveryClient : public CefClient, public CefLifeSpanHandler, public CefDownloadHandler {
 public:
  RecoveryClient(NSString* profile, NSString* source, NSString* original, NSString* guid, DownloadRecoveryUpdate update,
                 unsigned legacyID, NSString* partial)
      : profile_([profile copy]), source_([source copy]), original_([original copy]), guid_([guid copy]), update_([update copy]), legacyID_(legacyID), partial_([partial copy]) {}
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    browsers[Key(browser)] = browser;
    CefRefPtr<RecoveryClient> keep(this);
    dispatch_async(dispatch_get_main_queue(), ^{ keep->Start(browser, 0); });
  }
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    [timer_ invalidate]; timer_ = nil;
    browsers.erase(Key(browser));
    if (update_ && !quitting) update_(nil);
    update_ = nil;
    if (quitting) dispatch_async(dispatch_get_main_queue(), ^{ QuitNext(); });
  }
  void OnDownloadUpdated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
                         CefRefPtr<CefDownloadItemCallback> callback) override {
    if (!update_ || !item->IsValid()) return;
    [timer_ invalidate]; timer_ = nil;
    auto values = DownloadValues(browser, item, callback);
    update_(values);
    if (!item->IsInProgress()) Finish(browser);
  }
 private:
  std::string Key(CefRefPtr<CefBrowser> browser) {
    return "download-recovery:" + std::string(profile_.UTF8String) + ":" + std::to_string(browser->GetIdentifier());
  }
  void Finish(CefRefPtr<CefBrowser> browser) {
    [timer_ invalidate]; timer_ = nil;
    update_ = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (browser->IsValid()) browser->GetHost()->CloseBrowser(true);
    });
  }
  void Start(CefRefPtr<CefBrowser> browser, unsigned attempt) {
    if (!update_ || !browser->IsValid() || quitting) return;
    if (!guid_.length && !partial_) {
      // Requests rejected before item creation have no CEF download callback.
      CefRefPtr<RecoveryClient> keep(this);
      timer_ = [NSTimer scheduledTimerWithTimeInterval:60 repeats:NO block:^(NSTimer*) {
        if (!keep->update_ || !browser->IsValid() || quitting) return;
        keep->update_(nil);
        keep->Finish(browser);
      }];
      browser->GetHost()->StartDownload(CefStr(original_));
      return;
    }
    using Identify = void (*)(void*, const char*);
    using Recover = int (*)(int, const char*, const char*, uint32_t, const char*, void*, Identify);
    static auto recover = reinterpret_cast<Recover>(BrowserEngineSymbol("browser_recover_download_v1"));
    Identify identify = partial_ ? +[](void* ctx, const char* guid) {
      auto* client = static_cast<RecoveryClient*>(ctx);
      client->update_(@{@"guid":@(guid)});
    } : nullptr;
    int result = recover ? recover(browser->GetIdentifier(), guid_.UTF8String, source_.UTF8String,
        legacyID_, partial_.UTF8String, this, identify) : 0;
    if (result == 1) {
      if (partial_) Finish(browser);
      return;
    }
    if (result < 0 && attempt < 100) {
      CefRefPtr<RecoveryClient> keep(this);
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{
        keep->Start(browser, attempt + 1);
      });
      return;
    }
    update_(nil);
    Finish(browser);
  }
  NSTimer *timer_ = nil;
  NSString *profile_, *source_, *original_, *guid_;
  DownloadRecoveryUpdate update_;
  unsigned legacyID_;
  NSString* partial_;
  IMPLEMENT_REFCOUNTING(RecoveryClient);
};

class RecoveryWindow : public TrackedChromeWindow {
 public:
  explicit RecoveryWindow(CefRefPtr<CefBrowserView> view) : view_(view) {}
  cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  void WindowCreated(CefRefPtr<CefWindow> window) override { window->AddChildView(view_); }
  void WindowDestroyed(CefRefPtr<CefWindow>) override { view_ = nullptr; }
 private:
  CefRefPtr<CefBrowserView> view_;
  IMPLEMENT_REFCOUNTING(RecoveryWindow);
};

static void StartDownloadRecovery(NSString *source, NSString *original, NSString *guid,
                                  NSString *profile, DownloadRecoveryUpdate update, unsigned legacyID = 0, NSString* partial = nil) {
  if (!running || quitting) { update(nil); return; }
  NSURLComponents *url = [NSURLComponents componentsWithString:original];
  if (!url.host.length || ![@[@"http",@"https"] containsObject:url.scheme.lowercaseString]) { update(nil); return; }
  auto context = ContextForProfile(profile);
  if (!context) { update(nil); return; }
  if (!readyProfiles.count(profile.UTF8String)) {
    profileReadyCallbacks[profile.UTF8String].push_back([^{
      StartDownloadRecovery(source, original, guid, profile, update, legacyID, partial);
    } copy]);
    return;
  }
  auto view = CefBrowserView::CreateBrowserView(new RecoveryClient(profile,source,original,guid,update,legacyID,partial),
      "about:blank", CefBrowserSettings(), nullptr, context, nullptr);
  if (!view || !CefWindow::CreateTopLevelWindow(new RecoveryWindow(view))) update(nil);
}

static void ClosePrivateDownloadRecoveries(const std::string& profile) {
  std::string prefix = "download-recovery:" + profile + ":";
  for (const auto& [key, browser] : browsers) {
    if (key.compare(0, prefix.size(), prefix) != 0) continue;
    auto id = static_cast<uint64_t>(browser->GetIdentifier());
    auto control = downloadControls.lower_bound(id << 32);
    if (control != downloadControls.end() && (control->first >> 32) == id)
      control->second.callback->Cancel();
    browser->GetHost()->CloseBrowser(true);
  }
}
