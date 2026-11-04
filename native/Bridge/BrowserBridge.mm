#import "BrowserBridge.h"
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_command_handler.h"
#include "include/cef_context_menu_handler.h"
#include "include/cef_id_mappers.h"
#include "include/cef_image.h"
#include "include/cef_parser.h"
#include "include/cef_cookie.h"
#include "include/cef_request_context.h"
#include "include/cef_request_context_handler.h"
#include "include/cef_ssl_info.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_version.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_browser_view_delegate.h"
#include "include/views/cef_box_layout.h"
#include "include/views/cef_fill_layout.h"
#include "include/views/cef_window.h"
#include "include/views/cef_window_delegate.h"
#include "include/wrapper/cef_library_loader.h"
#include "include/wrapper/cef_helpers.h"
#include <map>
#include <set>
#include <memory>
#include <string>
#include <vector>
#include <algorithm>
#include <crt_externs.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <cmath>
#include <functional>
#include "BrowserDiagnostics.inc"
#include "TestKeychainPolicy.h"

static std::unique_ptr<CefScopedLibraryLoader> loader;
static bool mockTestKeychain = false;
static std::map<std::string, CefRefPtr<CefBrowser>> browsers;
struct NativeTabOwner { __weak BrowserEngine *engine = nil; };
static std::map<std::string, NativeTabOwner> nativeTabOwners;
static std::set<std::string> discardedBrowsers;
static std::map<uint32_t, CefRefPtr<CefDownloadItemCallback>> downloadControls;
static std::map<std::string, CefRefPtr<CefRequestContext>> profiles;
static std::set<std::string> privateProfiles;
// Resolve only in the CEF image already loaded by CefScopedLibraryLoader.
// The stock framework deliberately has no Browser-private extension ABI.
static void *BrowserEngineSymbol(const char *name) {
  for (uint32_t index = 0; index < _dyld_image_count(); ++index) {
    const char *path = _dyld_get_image_name(index);
    if (!path || ![[NSString stringWithUTF8String:path].lastPathComponent isEqualToString:@"Chromium Embedded Framework"]) continue;
    void *library = dlopen(path, RTLD_LAZY | RTLD_NOLOAD);
    if (!library) continue;
    void *symbol = dlsym(library, name);
    dlclose(library);
    return symbol;
  }
  return nullptr;
}
static std::string activeExtensionTab, activeExtensionID;
static NSRect activeExtensionAnchor;
static NSTimer *extensionOpenTraceTimer;
static void TraceExtensionPopupOpening(int browserID, NSString *identifier) {
  [extensionOpenTraceTimer invalidate]; extensionOpenTraceTimer = nil;
  using State = int (*)(int, const char *, int *);
  auto state = reinterpret_cast<State>(BrowserEngineSymbol("browser_extension_popup_state_v1"));
  if (!state) return;
  const double started = NSProcessInfo.processInfo.systemUptime;
  extensionOpenTraceTimer = [NSTimer timerWithTimeInterval:0.025 repeats:YES block:^(NSTimer *timer) {
    int bounds[4] = {};
    const int status = state(browserID,identifier.UTF8String,bounds);
    const double elapsed = (NSProcessInfo.processInfo.systemUptime-started)*1000;
    if (status == 2 || status == 0 || elapsed >= 10000) {
      BrowserTrace(@"extension.popup",@{@"extension":identifier,@"browser":@(browserID),
          @"state":@(status),@"elapsedMs":@(elapsed),@"timeout":@(status == 1)});
      [timer invalidate];
      if (extensionOpenTraceTimer == timer) extensionOpenTraceTimer = nil;
    }
  }];
  [NSRunLoop.mainRunLoop addTimer:extensionOpenTraceTimer forMode:NSRunLoopCommonModes];
}
static void CloseNativeExtensionPopup(const std::string& key) {
  const std::string tabKey = key;
  if (activeExtensionTab == tabKey) {
    [extensionOpenTraceTimer invalidate]; extensionOpenTraceTimer = nil;
    activeExtensionTab.clear(); activeExtensionID.clear();
  }
  using Close = int (*)(int);
  auto browser = browsers.find(tabKey);
  if (browser == browsers.end()) return;
  auto close = reinterpret_cast<Close>(BrowserEngineSymbol("browser_close_extension_popup_v1"));
  if (close) close(browser->second->GetIdentifier());
}
// Intercept before AppKit/Chromium changes window focus. This covers the native
// sidebar and the Chrome child window, including a popup still loading.
static bool HandleNativeExtensionEvent(NSEvent *event) {
  if (activeExtensionTab.empty()) return false;
  const bool click = event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeRightMouseDown || event.type == NSEventTypeOtherMouseDown;
  const bool escape = event.type == NSEventTypeKeyDown && event.keyCode == 53;
  if (!click && !escape) return false;
  auto browser = browsers.find(activeExtensionTab);
  using State = int (*)(int, const char *, int *);
  auto state = reinterpret_cast<State>(BrowserEngineSymbol("browser_extension_popup_state_v1"));
  int bounds[4] = {};
  int visible = browser != browsers.end() && state ? state(browser->second->GetIdentifier(), activeExtensionID.c_str(), bounds) : 0;
  if (!visible) { activeExtensionTab.clear(); activeExtensionID.clear(); return false; }
  const NSPoint point = NSEvent.mouseLocation;
  const CGFloat top = NSScreen.screens.firstObject.frame.size.height;
  const NSRect popup = NSMakeRect(bounds[0], top - bounds[1] - bounds[3], bounds[2], bounds[3]);
  if (escape || (click && (visible != 2 || !NSPointInRect(point, popup)))) {
    const bool anchorClick = click && NSPointInRect(point, activeExtensionAnchor);
    CloseNativeExtensionPopup(activeExtensionTab);
    return escape || anchorClick;
  }
  return false;
}
static cef_color_variant_t appearanceMode = CEF_COLOR_VARIANT_SYSTEM;
// Alloy's embedded native views do not propagate Chrome's profile theme to
// prefers-color-scheme on macOS. Set the media preference through CEF's internal
// protocol channel (no remote debugging port or injected page script).
static void ApplyPageAppearance(CefRefPtr<CefBrowser> browser) {
  auto params = CefDictionaryValue::Create();
  auto features = CefListValue::Create();
  if (appearanceMode != CEF_COLOR_VARIANT_SYSTEM) {
    auto feature = CefDictionaryValue::Create();
    feature->SetString("name", "prefers-color-scheme");
    feature->SetString("value", appearanceMode == CEF_COLOR_VARIANT_DARK ? "dark" : "light");
    features->SetDictionary(0, feature);
  }
  params->SetList("features", features);
  browser->GetHost()->ExecuteDevToolsMethod(0, "Emulation.setEmulatedMedia", params);
}
class SiteCompletion : public CefCompletionCallback {
 public:
  explicit SiteCompletion(void (^done)(BOOL)) : done_([done copy]) {}
  void OnComplete() override { done_(YES); }
 private:
  void (^done_)(BOOL);
  IMPLEMENT_REFCOUNTING(SiteCompletion);
};
// VisitUrlCookies includes domain cookies and HttpOnly cookies for this URL.
// Deletion is limited to those cookies; other hosts and profiles are untouched.
class SiteCookieVisitor : public CefCookieVisitor {
 public:
  SiteCookieVisitor(CefRefPtr<CefCookieManager> manager, void (^done)(BOOL)) : manager_(manager), done_([done copy]) {}
  bool accepted = false;
  bool Visit(const CefCookie&, int, int, bool& delete_cookie) override { delete_cookie = true; return true; }
  ~SiteCookieVisitor() override {
    auto manager = manager_; auto done = done_; bool success = accepted;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!success || !manager->FlushStore(new SiteCompletion(done))) done(NO);
    });
  }
 private:
  CefRefPtr<CefCookieManager> manager_;
  void (^done_)(BOOL);
  IMPLEMENT_REFCOUNTING(SiteCookieVisitor);
};
class SiteDevToolsClient : public CefClient {
 private:
  IMPLEMENT_REFCOUNTING(SiteDevToolsClient);
};
static std::set<std::string> readyProfiles;
static std::map<std::string, CefRefPtr<CefRegistration>> extensionPreferenceRegistrations;
static void NotifyExtensionPreferences(const std::string& profile) {
  NSString *profileID = @(profile.c_str());
  // Leave Chromium's preference mutation before touching the AppKit hierarchy.
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSNotificationCenter.defaultCenter postNotificationName:@"BrowserExtensionPreferencesChanged" object:profileID];
  });
}
class ExtensionPreferenceObserver : public CefPreferenceObserver {
 public:
  explicit ExtensionPreferenceObserver(std::string profile) : profile_(std::move(profile)) {}
  void OnPreferenceChanged(const CefString&) override { NotifyExtensionPreferences(profile_); }
 private:
  std::string profile_;
  IMPLEMENT_REFCOUNTING(ExtensionPreferenceObserver);
};
static std::map<std::string, std::vector<void (^)(void)>> profileReadyCallbacks;
static const char* WebLanguages() {
  return [[[NSUserDefaults standardUserDefaults] stringForKey:@"BrowserLanguage"] isEqualToString:@"en"]
      ? "en-US,en" : "fr-FR,fr,en-US,en";
}
static void ApplyWebLanguage(CefRefPtr<CefRequestContext> context) {
  if (!context) return;
  // Chromium derives Accept-Language and navigator.languages from the selected
  // languages preference. Apply it to restored profiles as well as new ones.
  auto value = CefValue::Create(); value->SetString(WebLanguages());
  CefString error;
  if (context->CanSetPreference("intl.selected_languages")) {
    if (!context->SetPreference("intl.selected_languages", value, error))
      NSLog(@"Browser language preference: %s", error.ToString().c_str());
  }
}
// Apply native preferences through Chromium's registered profile preferences.
// Disabling saving also disables generation; it does not erase stored credentials.
static bool ApplyCredentialPreferences(CefRefPtr<CefRequestContext> context) {
  if (!context) return false;
  const std::pair<const char*, NSString*> keys[] = {
    {"credentials_enable_service", @"BrowserSavePasswords"},
    {"credentials_enable_autosignin", @"BrowserAutomaticSignIn"},
    {"autofill.profile_enabled", @"BrowserFormSuggestions"}
  };
  for (const auto& key : keys) {
    if (!context->CanSetPreference(key.first)) return false;
  }
  for (const auto& key : keys) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:key.second];
    auto value = CefValue::Create(); value->SetBool(context->GetCachePath().empty() ? false : (stored ? [stored boolValue] : true));
    CefString error;
    if (!context->SetPreference(key.first, value, error)) {
      NSLog(@"Browser preference %s: %s", key.first, error.ToString().c_str());
      return false;
    }
  }
  return true;
}
class ThemeContextHandler : public CefRequestContextHandler {
 public:
  explicit ThemeContextHandler(std::string profile) : profile_(std::move(profile)) {}
  void OnRequestContextInitialized(CefRefPtr<CefRequestContext> context) override {
    CEF_REQUIRE_UI_THREAD();
    ApplyWebLanguage(context);
    ApplyCredentialPreferences(context);
    context->SetChromeColorScheme(appearanceMode, 0);
    readyProfiles.insert(profile_);
    if (!privateProfiles.count(profile_)) {
      extensionPreferenceRegistrations[profile_] = context->AddPreferenceObserver(
          "extensions.settings", new ExtensionPreferenceObserver(profile_));
      NotifyExtensionPreferences(profile_);
    }
    auto callbacks = std::move(profileReadyCallbacks[profile_]);
    profileReadyCallbacks.erase(profile_);
    for (auto callback : callbacks) callback();
  }
 private:
  std::string profile_;
  IMPLEMENT_REFCOUNTING(ThemeContextHandler);
};
// Creation is asynchronous: a new on-disk profile is not immediately ready.
static std::map<std::string, bool> pendingBrowsers;
static std::map<std::string, std::string> pendingNavigation;
static std::map<std::string, bool> tabVisibility;
static std::string rootCache;
static bool running = false;
static bool quitting = false;
static NSString *Str(const CefString& value) { return [NSString stringWithUTF8String:value.ToString().c_str()] ?: @""; }
static CefString CefStr(NSString *value) { return CefString(value.UTF8String ?: ""); }
static bool Allowed(NSString *value) {
  if ([value hasPrefix:@"view-source:"]) {
    NSString *source = [value substringFromIndex:12];
    NSString *scheme = [NSURLComponents componentsWithString:source].scheme.lowercaseString;
    return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) && Allowed(source);
  }
  if ([value isEqualToString:@"about:blank"] || [value isEqualToString:@"chrome://extensions/"] || [value isEqualToString:@"chrome://history/"]) return true;
  NSURLComponents *internal = [NSURLComponents componentsWithString:value];
  if ([internal.scheme.lowercaseString isEqualToString:@"chrome"] && ([internal.host.lowercaseString isEqualToString:@"settings"] || [internal.host.lowercaseString isEqualToString:@"password-manager"]) &&
      !internal.user && !internal.password && !internal.port && internal.URL && [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= 32768 &&
      [value rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location == NSNotFound &&
      [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound && ![value containsString:@"\\"]) return true;
  if ([internal.scheme isEqualToString:@"chrome-extension"] && internal.host.length == 32 &&
      [internal.host rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnop"].invertedSet].location == NSNotFound &&
      !internal.user && !internal.password && !internal.port) return true;
  NSURLComponents *u = [NSURLComponents componentsWithString:value];
  return u && ([u.scheme.lowercaseString isEqualToString:@"https"] || [u.scheme.lowercaseString isEqualToString:@"http"]) && u.host.length && !u.user.length && !u.password.length;
}
static bool French() { return ![[NSUserDefaults standardUserDefaults] stringForKey:@"BrowserLanguage"] || [[[NSUserDefaults standardUserDefaults] stringForKey:@"BrowserLanguage"] isEqualToString:@"fr"]; }
static NSString *L(NSString *fr, NSString *en) { return French() ? fr : en; }
static void QuitNext();
static CefRefPtr<CefClient> NewExtensionClient();
static void ExtensionStoreCompatibility(CefRefPtr<CefBrowser> browser, bool enabled);
static void PrepareChromePopup(NSString *key, NSView *container, CefRefPtr<CefClient> client, std::weak_ptr<bool> lifetime);
static void CancelChromePopup(const std::string& key);
static NSView *VisibleChromePage(NSString *key);
static NSWindow *ChromeDocumentWindow(NSString *key);
static bool RunNativePageMenu(NSString *key, CefRefPtr<CefContextMenuParams> params,
                              CefRefPtr<CefMenuModel> model, CefRefPtr<CefRunContextMenuCallback> callback);
static void RegisterNativeExtensionTabs(bool enabled);
static void Notify(NSString *name) { [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil]; }
#include "DeveloperTools.inc"
#include "PictureInPicture.inc"

@interface BrowserNativeApplication : NSApplication <CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@end
@implementation BrowserNativeApplication
- (BOOL)isHandlingSendEvent { return _handlingSendEvent; }
- (void)sendEvent:(NSEvent *)event { CefScopedSendingEvent scope; if (!HandleNativeExtensionEvent(event)) [super sendEvent:event]; }
- (void)terminate:(id)sender {
  BrowserTrace(@"app.terminate-request",@{@"sender":sender ? NSStringFromClass([sender class]) : @"nil",@"stack":NSThread.callStackSymbols});
  Notify(@"BrowserNativeRequestQuit");
}
@end

class NativeApp : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }
  void OnContextInitialized() override { BrowserTrace(@"cef.ready"); ApplyCredentialPreferences(CefRequestContext::GetGlobalContext()); ApplyWebLanguage(CefRequestContext::GetGlobalContext()); RegisterNativeExtensionTabs(true); Notify(@"BrowserEngineReady"); }
  CefRefPtr<CefClient> GetDefaultClient() override { BrowserTrace(@"cef.default-client"); return NewExtensionClient(); }
  void OnBeforeCommandLineProcessing(const CefString&, CefRefPtr<CefCommandLine> command) override {
    // Chromium provides a fake keychain specifically for disposable tests.
    // Never accept this switch for the everyday profile, even from argv.
    command->RemoveSwitch("use-mock-keychain");
    if (mockTestKeychain) command->AppendSwitch("use-mock-keychain");
    // AppKit restores its own tabs. CEF keeps session cookies by enabling
    // Chrome session restore, which must not open an extra browser window.
    command->AppendSwitch("no-startup-window");
    // Our CEF helpers initialize the sandbox through CefScopedSandboxContext.
    // Chromium's experimental Aperitif helper bundles are not shipped by CEF.
    auto disabled = command->GetSwitchValue("disable-features").ToString();
    if (!disabled.empty()) disabled += ",";
    command->AppendSwitchWithValue("disable-features", disabled + "AperitifHelpers");
  }
 private:
  IMPLEMENT_REFCOUNTING(NativeApp);
};

// Shared only with in-flight image callbacks. A reload invalidates callbacks even
// when it navigates to the same URL; closing a tab never resurrects its icon.
struct FaviconState {
  uint64_t generation = 0;
  bool closed = false;
  std::string document;
  std::vector<std::string> candidates;
};
static std::string DocumentURL(CefRefPtr<CefBrowser> browser) {
  if (!browser || !browser->IsValid() || !browser->GetMainFrame()) return {};
  NSURLComponents *url = [NSURLComponents componentsWithString:Str(browser->GetMainFrame()->GetURL())];
  url.fragment = nil;
  return url.string.UTF8String ?: "";
}

class FaviconDownload : public CefDownloadImageCallback {
 public:
  FaviconDownload(BrowserEngine *engine, NSString *tabID, CefRefPtr<CefBrowser> browser,
                  std::shared_ptr<FaviconState> state, uint64_t generation,
                  std::string document, size_t candidate)
      : engine_(engine), tabID_([tabID copy]), browser_(browser), state_(state),
        generation_(generation), document_(std::move(document)), candidate_(candidate) {}
  void OnDownloadImageFinished(const CefString& image_url, int status, CefRefPtr<CefImage> image) override {
    CEF_REQUIRE_UI_THREAD();
    auto live = browsers.find(tabID_.UTF8String);
    if (state_->closed || state_->generation != generation_ || !browser_->IsValid() ||
        live == browsers.end() || !live->second->IsSame(browser_) || DocumentURL(browser_) != document_) return;
    NSImage *icon = nil;
    // CEF decodes/downsizes the remote image. Bound both the decoded dimensions
    // and the PNG transferred into AppKit; never instantiate NSImage from the URL.
    if (status < 400 && image && !image->IsEmpty() && image->GetWidth() <= 64 && image->GetHeight() <= 64) {
      int width = 0, height = 0;
      auto png = image->GetAsPNG(2.0f, true, width, height);
      constexpr size_t maximumPNGBytes = 256 * 1024;
      if (png && png->GetSize() > 0 && png->GetSize() <= maximumPNGBytes &&
          width > 0 && height > 0 && width <= 256 && height <= 256) {
        NSMutableData *data = [NSMutableData dataWithLength:png->GetSize()];
        if (png->GetData(data.mutableBytes, data.length, 0) == data.length) {
          icon = [[NSImage alloc] initWithData:data];
          icon.size = NSMakeSize(16, 16);
        }
      }
    }
    if (icon) {
      if ([engine_.delegate respondsToSelector:@selector(browserFaviconChanged:image:)])
        [engine_.delegate browserFaviconChanged:tabID_ image:icon];
    } else if (candidate_ + 1 < state_->candidates.size()) {
      const size_t next = candidate_ + 1;
      browser_->GetHost()->DownloadImage(state_->candidates[next], true, 64, false,
          new FaviconDownload(engine_, tabID_, browser_, state_, generation_, document_, next));
    }
  }
 private:
  __weak BrowserEngine *engine_;
  NSString *tabID_;
  CefRefPtr<CefBrowser> browser_;
  std::shared_ptr<FaviconState> state_;
  uint64_t generation_;
  std::string document_;
  size_t candidate_;
  IMPLEMENT_REFCOUNTING(FaviconDownload);
};

// A site sheet belongs to exactly one tab, including in split view.
struct SitePermissionSheet {
  uint64_t promptID;
  NSWindow *window;
};
static std::map<std::string, SitePermissionSheet> sitePermissionSheets;

static void DismissSitePermissionSheet(const std::string& tab) {
  auto found = sitePermissionSheets.find(tab);
  if (found == sitePermissionSheets.end()) return;
  NSWindow *sheet = found->second.window;
  if (sheet.sheetParent) [sheet.sheetParent endSheet:sheet returnCode:NSModalResponseCancel];
}

static NSArray<NSString *> *SitePermissionNames(uint32_t permissions) {
  // Only generic decisions whose scope can be described by origin and type.
  // Device, file and screen choosers require the user's specific selection.
  struct Description { uint32_t bit; NSString *fr; NSString *en; };
  const Description descriptions[] = {
    {CEF_PERMISSION_TYPE_MIC_STREAM, @"microphone", @"microphone"},
    {CEF_PERMISSION_TYPE_CAMERA_STREAM, @"caméra", @"camera"},
    {CEF_PERMISSION_TYPE_CAMERA_PAN_TILT_ZOOM, @"contrôle des mouvements et du zoom de la caméra", @"camera pan, tilt and zoom controls"},
    {CEF_PERMISSION_TYPE_GEOLOCATION, @"position", @"location"},
    {CEF_PERMISSION_TYPE_NOTIFICATIONS, @"notifications", @"notifications"},
    {CEF_PERMISSION_TYPE_CLIPBOARD, @"presse-papiers", @"clipboard"},
    {CEF_PERMISSION_TYPE_LOCAL_FONTS, @"polices installées sur votre Mac", @"fonts installed on your Mac"},
    {CEF_PERMISSION_TYPE_WINDOW_MANAGEMENT, @"informations sur vos écrans et placement des fenêtres", @"screen information and window placement"},
    {CEF_PERMISSION_TYPE_MULTIPLE_DOWNLOADS, @"téléchargement automatique de plusieurs fichiers", @"automatic download of multiple files"},
  };
  NSMutableArray *names = [NSMutableArray array];
  for (const auto& description : descriptions) {
    if (permissions & description.bit) {
      [names addObject:L(description.fr, description.en)];
      permissions &= ~description.bit;
    }
  }
  return permissions == 0 && names.count > 0 ? names : nil;
}

class NativeClient : public CefClient,
                     public CefCommandHandler,
                     public CefContextMenuHandler,
                     public CefLifeSpanHandler,
                     public CefDisplayHandler,
                     public CefLoadHandler,
                     public CefRequestHandler,
                     public CefJSDialogHandler,
                     public CefPermissionHandler,
                     public CefDownloadHandler,
                     public CefKeyboardHandler {
 public:
  NativeClient(BrowserEngine *engine, NSString *tabID, bool embedded = true, bool chrome = false) : engine_(engine), tabID_([tabID copy]), embedded_(embedded), chrome_(chrome) {}
  ~NativeClient() override {
    // CEF does not send OnBeforePopupAborted after the opener was destroyed.
    // Release a failed reservation even in that case, on the native UI thread.
    if (popupFinished_) {
      auto finish = std::move(popupFinished_);
      dispatch_async(dispatch_get_main_queue(), ^{ finish(false); });
    }
  }
  CefRefPtr<CefCommandHandler> GetCommandHandler() override { return this; }
  CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override { return this; }
  bool RunContextMenu(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>,
                      CefRefPtr<CefContextMenuParams> params, CefRefPtr<CefMenuModel> model,
                      CefRefPtr<CefRunContextMenuCallback> callback) override {
    if (!embedded_ || !chrome_) return false;
    return RunNativePageMenu(tabID_, params, model, callback);
  }
  bool OnContextMenuCommand(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>,
                            CefRefPtr<CefContextMenuParams> params, int command, EventFlags) override {
    if (!embedded_ || command < 0) return false;
    const bool privateWindow = command == cef_id_for_command_id_name("IDC_CONTENT_CONTEXT_OPENLINKOFFTHERECORD");
    if (!privateWindow && command != cef_id_for_command_id_name("IDC_CONTENT_CONTEXT_OPENLINKNEWWINDOW")) return false;
    NSString *url = Str(params->GetLinkUrl()), *source = tabID_;
    if (quitting || !Allowed(url)) return true;
    __weak BrowserEngine *engine = engine_;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (quitting || !browser->IsValid()) return;
      if (privateWindow) {
        if ([engine.delegate respondsToSelector:@selector(browserRequestedPrivateWindow:sourceTab:)])
          [engine.delegate browserRequestedPrivateWindow:url sourceTab:source];
      } else if ([engine.delegate respondsToSelector:@selector(browserRequestedNewWindow:sourceTab:)])
        [engine.delegate browserRequestedNewWindow:url sourceTab:source];
    });
    return true;
  }
  bool OnChromeCommand(CefRefPtr<CefBrowser> browser, int command_id,
                       cef_window_open_disposition_t) override {
    if (!chrome_ || !embedded_ || !engine_.delegate || command_id < 0) return false;
    // Commands issued by Chromium menus must use the same AppKit tab model
    // as our toolbar. Resolve IDs by name; their numbers vary with Chromium.
    NSString *address = nil;
    for (const char *name : {"IDC_MANAGE_EXTENSIONS",
                             "IDC_SAFETY_HUB_MANAGE_EXTENSIONS",
                             "IDC_EXTENSIONS_SUBMENU_MANAGE_EXTENSIONS"}) {
      if (command_id == cef_id_for_command_id_name(name)) address = @"chrome://extensions/";
    }
    for (const char *name : {"IDC_EXTENSIONS_SUBMENU_VISIT_CHROME_WEB_STORE",
                             "IDC_FIND_EXTENSIONS"}) {
      if (command_id == cef_id_for_command_id_name(name))
        address = @"https://chromewebstore.google.com/category/extensions";
    }
    if (!address) return false;
    __weak BrowserEngine *engine = engine_;
    NSString *source = tabID_;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!quitting && browser->IsValid())
        [engine.delegate browserRequestedNewTab:address sourceTab:source];
    });
    return true;
  }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
  void OnBeforeDevToolsPopup(CefRefPtr<CefBrowser>,CefWindowInfo&,CefRefPtr<CefClient>& client,
                            CefBrowserSettings&,CefRefPtr<CefDictionaryValue>&,bool* use_default_window) override {
    if (!chrome_ || !embedded_) return;
    *use_default_window = false; PrepareDeveloperPopup(tabID_.UTF8String,client);
  }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    if (popupFinished_) { popupFinished_(true); popupFinished_ = nullptr; }
    browsers[tabID_.UTF8String] = browser;
    if (embedded_ && chrome_) nativeTabOwners[tabID_.UTF8String] = {engine_};
    ApplyPageAppearance(browser);
    browser->GetHost()->SetAccessibilityState(STATE_ENABLED);
    NSView *view = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    if (!chrome_) { view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    if (view.superview) view.frame = view.superview.bounds; }
    const std::string key = tabID_.UTF8String;
    bool closePending = pendingBrowsers.count(key) && pendingBrowsers[key];
    bool forced = discardedBrowsers.count(key) != 0;
    pendingBrowsers.erase(key);
    if (!chrome_ && tabVisibility.count(key)) view.hidden = !tabVisibility[key];
    auto navigation = pendingNavigation.find(key);
    if (navigation != pendingNavigation.end()) {
      browser->GetMainFrame()->LoadURL(navigation->second);
      pendingNavigation.erase(navigation);
    }
    if (quitting) dispatch_async(dispatch_get_main_queue(), ^{ QuitNext(); });
    else if (closePending) dispatch_async(dispatch_get_main_queue(), ^{ browser->GetHost()->CloseBrowser(forced); });
    else if (!view.hiddenOrHasHiddenAncestor && view.window.isKeyWindow && !view.window.attachedSheet) browser->GetHost()->SetFocus(true);
  }
  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    BrowserTrace(@"tab.do-close",@{@"tab":tabID_,@"browser":@(browser->GetIdentifier()),@"quitting":@(quitting)});
    if (!embedded_ || chrome_) return false;
    NSView *view = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    [view removeFromSuperview];
    return true;
  }
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    BrowserTrace(@"tab.before-close",@{@"tab":tabID_,@"browser":@(browser->GetIdentifier()),@"quitting":@(quitting)});
    DismissSitePermissionSheet(tabID_.UTF8String);
    favicon_->closed = true;
    ++favicon_->generation;
    CloseTabDeveloperTools(tabID_.UTF8String);
    ForgetPictureInPicture(tabID_);
    browsers.erase(tabID_.UTF8String);
    nativeTabOwners.erase(tabID_.UTF8String);
    discardedBrowsers.erase(tabID_.UTF8String);
    tabVisibility.erase(tabID_.UTF8String);
    pendingNavigation.erase(tabID_.UTF8String);
    [engine_.delegate browserClosed:tabID_];
    if (quitting) dispatch_async(dispatch_get_main_queue(), ^{ QuitNext(); });
  }
  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) override {
    if (embedded_) [engine_.delegate browserTitleChanged:tabID_ title:Str(title)];
    else { NSView *view = (__bridge NSView *)browser->GetHost()->GetWindowHandle(); view.window.title = Str(title); }
  }
  void OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, TransitionType transition) override {
    CEF_REQUIRE_UI_THREAD();
    if (!embedded_ || !frame->IsMain()) return;
    CancelNativeInspection(tabID_.UTF8String);
    ++favicon_->generation;
    favicon_->candidates.clear();
    const auto document = DocumentURL(browser);
    const bool changedDocument = favicon_->document != document;
    favicon_->document = document;
    // Reloading the same document keeps its current icon until a different
    // decoded image arrives. Generation still rejects stale downloads.
    if (changedDocument && [engine_.delegate respondsToSelector:@selector(browserFaviconChanged:image:)])
      [engine_.delegate browserFaviconChanged:tabID_ image:nil];
  }
  void OnFaviconURLChange(CefRefPtr<CefBrowser> browser, const std::vector<CefString>& icon_urls) override {
    CEF_REQUIRE_UI_THREAD();
    if (!embedded_ || favicon_->closed || !browser->IsValid()) return;
    std::vector<std::string> candidates;
    for (const auto& candidate : icon_urls) {
      std::string url = candidate.ToString();
      // Bound inline images and keep acquisition inside this browser's CEF
      // context. Favicon mode deliberately sends/accepts no cookies (CEF API).
      if (url.empty() || url.size() > 32768) continue;
      const bool supported = (Allowed(Str(candidate)) && url != "about:blank") || url.rfind("data:image/", 0) == 0;
      if (!supported) continue;
      if (std::find(candidates.begin(), candidates.end(), url) == candidates.end()) candidates.push_back(url);
      if (candidates.size() == 4) break;
    }
    if (favicon_->candidates == candidates) return;
    favicon_->candidates = std::move(candidates);
    ++favicon_->generation;
    if (favicon_->candidates.empty()) {
      // Empty candidates can be transient during reload. A navigation to a
      // different document already cleared the previous icon in OnLoadStart.
      return;
    }
    browser->GetHost()->DownloadImage(favicon_->candidates[0], true, 64, false,
        new FaviconDownload(engine_, tabID_, browser, favicon_, favicon_->generation, DocumentURL(browser), 0));
  }
  void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& url) override {
    if (frame->IsMain() && Allowed(Str(url))) [engine_.delegate browserURLChanged:tabID_ url:Str(url)];
  }
  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool loading, bool back, bool forward) override {
    [engine_.delegate browserLoadingChanged:tabID_ loading:loading back:back forward:forward];
  }
  void OnLoadError(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, ErrorCode errorCode, const CefString& errorText, const CefString& failedURL) override {
    if (frame->IsMain() && errorCode != ERR_ABORTED) [engine_.delegate browserFailed:tabID_ message:Str(errorText)];
  }
  bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefRequest> request, bool gesture, bool redirect) override {
    NSString *url = Str(request->GetURL());
    if (chrome_ && frame->IsMain()) {
      NSURLComponents *location = [NSURLComponents componentsWithString:url];
      ExtensionStoreCompatibility(browser, [location.scheme isEqualToString:@"https"] && [location.host isEqualToString:@"chromewebstore.google.com"] && !location.user && !location.password);
    }
    if (frame->IsMain()) return !Allowed(url);
    NSString *scheme = [NSURLComponents componentsWithString:url].scheme.lowercaseString;
    return [scheme isEqualToString:@"file"] || [scheme isEqualToString:@"chrome"] || [scheme isEqualToString:@"devtools"];
  }
  bool OnOpenURLFromTab(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>,
                        const CefString& target, WindowOpenDisposition disposition, bool) override {
    // Normal new-tab navigations are routed inside the engine with their full
    // OpenURLParams. This callback only exposes a URL, and cannot preserve POST.
    if (!embedded_ || disposition != CEF_WOD_OFF_THE_RECORD) return false;
    NSString *url = Str(target), *source = tabID_;
    if (quitting || !Allowed(url)) return true;
    __weak BrowserEngine *engine = engine_;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (quitting || !browser->IsValid()) return;
      if ([engine.delegate respondsToSelector:@selector(browserRequestedPrivateWindow:sourceTab:)])
        [engine.delegate browserRequestedPrivateWindow:url sourceTab:source];
    });
    BrowserTrace(@"tab.open-url-routed",@{@"tab":source,@"disposition":@(disposition)});
    return true;
  }
  bool OnBeforePopup(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int popup_id, const CefString& target_url, const CefString& target_frame_name, WindowOpenDisposition disposition, bool gesture, const CefPopupFeatures& features, CefWindowInfo& info, CefRefPtr<CefClient>& client, CefBrowserSettings& settings, CefRefPtr<CefDictionaryValue>& extra, bool* no_javascript_access) override {
    NSString *url = target_url.empty() ? @"about:blank" : Str(target_url);
    if (quitting || !Allowed(url)) return true;
    NSDictionary *prepared = nil;
    if ([engine_.delegate respondsToSelector:@selector(browserPreparePopup:sourceTab:active:)])
      prepared = [engine_.delegate browserPreparePopup:url sourceTab:tabID_ active:disposition != CEF_WOD_NEW_BACKGROUND_TAB];
    else if ([engine_.delegate respondsToSelector:@selector(browserPreparePopup:sourceTab:)])
      prepared = [engine_.delegate browserPreparePopup:url sourceTab:tabID_];
    NSView *container = prepared[@"view"];
    NSString *identifier = prepared[@"id"];
    if (container && identifier.length) {
      auto popupClient = new NativeClient(engine_, identifier, true, chrome_);
      auto reservations = pendingPopups_;
      const std::string key = identifier.UTF8String;
      __weak BrowserEngine *owner = engine_;
      popupClient->popupLifetime_ = std::make_shared<bool>(true);
      popupClient->popupFinished_ = [reservations, popup_id, key, owner, identifier](bool created) {
        reservations->erase(popup_id);
        if (created) return;
        CancelChromePopup(key);
        if (!pendingBrowsers.erase(key)) return; // Already handled by the abort callback.
        pendingNavigation.erase(key); discardedBrowsers.erase(key); tabVisibility.erase(key);
        [owner.delegate browserClosed:identifier];
        if (quitting) QuitNext();
      };
      client = popupClient;
      pendingBrowsers[identifier.UTF8String] = false;
      (*pendingPopups_)[popup_id] = identifier.UTF8String;
      if (chrome_) {
        info.runtime_style = CEF_RUNTIME_STYLE_CHROME;
        PrepareChromePopup(identifier, container, client, popupClient->popupLifetime_);
      } else {
        info.SetAsChild((__bridge CefWindowHandle)container, CefRect(0, 0, (int)container.bounds.size.width, (int)container.bounds.size.height));
        info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
      }
    } else {
      // A page can never fall back to a standalone Chromium window.
      BrowserTrace(@"tab.popup-rejected",@{@"tab":tabID_,@"popup":@(popup_id)});
      return true;
    }
    BrowserTrace(@"tab.popup-prepared",@{@"tab":identifier,@"source":tabID_,@"popup":@(popup_id)});
    // CEF creates the real browsing context, preserving POST bodies and opener relationships.
    return false;
  }
  void OnBeforePopupAborted(CefRefPtr<CefBrowser>, int popup_id) override {
    const auto found = pendingPopups_->find(popup_id);
    if (found == pendingPopups_->end()) return;
    const std::string key = found->second;
    pendingPopups_->erase(found);
    if (browsers.count(key)) return;
    CancelChromePopup(key);
    pendingBrowsers.erase(key); pendingNavigation.erase(key); discardedBrowsers.erase(key);
    NSString *identifier = @(key.c_str());
    __weak BrowserEngine *engine = engine_;
    dispatch_async(dispatch_get_main_queue(), ^{ [engine.delegate browserClosed:identifier]; });
  }
  void OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser, TerminationStatus status, int code, const CefString& message) override {
    BrowserTrace(@"tab.renderer-terminated",@{@"tab":tabID_,@"browser":@(browser->GetIdentifier()),@"status":@(status),@"code":@(code)});
    [engine_.delegate browserFailed:tabID_ message:L(@"Cet onglet s’est arrêté. Rechargez la page.", @"This tab stopped. Reload the page.")];
  }
  bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser> browser, const CefString& message, bool reload, CefRefPtr<CefJSDialogCallback> callback) override {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = L(@"Quitter cette page ?", @"Leave this page?");
    alert.informativeText = L(@"Les modifications non enregistrées risquent d’être perdues.", @"Unsaved changes may be lost.");
    [alert addButtonWithTitle:L(@"Rester", @"Stay")];
    [alert addButtonWithTitle:L(@"Quitter", @"Leave")];
    NSWindow *parent = embedded_ && chrome_ ? ChromeDocumentWindow(tabID_) :
        ((__bridge NSView *)browser->GetHost()->GetWindowHandle()).window;
    auto complete = ^(NSModalResponse response) {
      bool leave = response == NSAlertSecondButtonReturn;
      if (!leave) { if ([engine_.delegate respondsToSelector:@selector(browserCloseCancelled:)]) [engine_.delegate browserCloseCancelled:tabID_]; if (quitting) { quitting = false; Notify(@"BrowserEngineQuitCancelled"); } }
      callback->Continue(leave, CefString());
    };
    if (parent.isVisible) [alert beginSheetModalForWindow:parent completionHandler:complete]; else complete([alert runModal]);
    return true;
  }
  bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& origin, uint32_t requested, CefRefPtr<CefMediaAccessCallback> callback) override {
    constexpr uint32_t devices = CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE | CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE;
    constexpr uint32_t display = CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE | CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE;
    const bool chromeTab = embedded_ && chrome_;
    NSView *view = chromeTab ? VisibleChromePage(tabID_) : (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    if (!view.window.isVisible || view.hiddenOrHasHiddenAncestor) { callback->Cancel(); return true; }
    // Delegate the original request, including its constraints and requesting frame.
    // For display capture Chromium owns source selection, cancellation and stop;
    // CEF's callback->Continue would instead pick the whole desktop by default.
    // CEF 156 does not map DISPLAY_VIDEO_CAPTURE_THIS_TAB into this mask, so a
    // valid preferCurrentTab request without audio can arrive with zero bits.
    if (chromeTab) {
      BrowserTrace((requested & display) ? @"permission.display-request" : @"permission.media-request", @{@"tab":tabID_, @"devices":@(requested)});
      return false;
    }
    // The legacy device-only sheet has no surface picker.
    if (!requested || (requested & ~devices) || view.window.attachedSheet) { callback->Cancel(); return true; }
    NSAlert *alert = [[NSAlert alloc] init];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    if (requested & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE) [names addObject:L(@"microphone", @"microphone")];
    if (requested & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE) [names addObject:L(@"caméra", @"camera")];
    alert.messageText = L(@"Autorisation du site", @"Website permission");
    alert.informativeText = [NSString stringWithFormat:L(@"%@ demande l’accès à : %@.", @"%@ requests access to: %@."), Str(origin), [names componentsJoinedByString:@", "]];
    [alert addButtonWithTitle:L(@"Refuser", @"Deny")]; [alert addButtonWithTitle:L(@"Autoriser", @"Allow")];
    std::string before = browser->GetMainFrame()->GetURL();
    [alert beginSheetModalForWindow:view.window completionHandler:^(NSModalResponse response) {
      if (response == NSAlertSecondButtonReturn && browser->IsValid() && browser->GetMainFrame()->GetURL().ToString() == before) callback->Continue(requested); else callback->Cancel();
    }];
    return true;
  }
  bool OnShowPermissionPrompt(CefRefPtr<CefBrowser> browser, uint64_t promptID, const CefString& origin, uint32_t permissions, CefRefPtr<CefPermissionPromptCallback> callback) override {
    NSView *view = embedded_ && chrome_ ? VisibleChromePage(tabID_) : (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    NSArray<NSString *> *names = SitePermissionNames(permissions);
    if (!names) {
      BrowserTrace(@"permission.unsupported", @{@"types":@(permissions)});
      callback->Continue(CEF_PERMISSION_RESULT_DISMISS);
      return true;
    }
    const std::string tab = tabID_.UTF8String;
    auto frame = browser->GetMainFrame();
    NSWindow *window = view.window;
    if (!frame || !window.isVisible || view.hiddenOrHasHiddenAncestor || window.attachedSheet || sitePermissionSheets.count(tab)) {
      callback->Continue(CEF_PERMISSION_RESULT_DISMISS);
      return true;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = L(@"Autorisation du site", @"Website permission");
    alert.informativeText = [NSString stringWithFormat:L(@"%@ demande l’accès à : %@.", @"%@ requests access to: %@."), Str(origin), [names componentsJoinedByString:@", "]];
    [alert addButtonWithTitle:L(@"Refuser", @"Deny")]; [alert addButtonWithTitle:L(@"Autoriser", @"Allow")];
    std::string before = frame->GetURL();
    NSNumber *key = @(promptID);
    sitePermissionSheets.emplace(tab, SitePermissionSheet{promptID, alert.window});
    BrowserTrace(@"permission.prompt-shown", @{@"prompt":key, @"types":@(permissions)});
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
      auto found = sitePermissionSheets.find(tab);
      if (found == sitePermissionSheets.end() || found->second.promptID != promptID) return;
      sitePermissionSheets.erase(found);
      auto current = browser->IsValid() ? browser->GetMainFrame() : nullptr;
      if (!current || current->GetURL().ToString() != before || view.window != window || !window.isVisible || view.hiddenOrHasHiddenAncestor) {
        callback->Continue(CEF_PERMISSION_RESULT_DISMISS);
      } else if (response == NSAlertFirstButtonReturn) {
        callback->Continue(CEF_PERMISSION_RESULT_DENY);
      } else {
        callback->Continue(response == NSAlertSecondButtonReturn ? CEF_PERMISSION_RESULT_ACCEPT : CEF_PERMISSION_RESULT_DISMISS);
      }
    }];
    return true;
  }
  void OnDismissPermissionPrompt(CefRefPtr<CefBrowser>, uint64_t promptID, cef_permission_request_result_t) override {
    BrowserTrace(@"permission.prompt-dismissed", @{@"prompt":@(promptID)});
    auto found = sitePermissionSheets.find(tabID_.UTF8String);
    if (found == sitePermissionSheets.end() || found->second.promptID != promptID) return;
    NSWindow *sheet = found->second.window;
    sitePermissionSheets.erase(found);
    if (sheet.sheetParent) [sheet.sheetParent endSheet:sheet returnCode:NSModalResponseCancel];
  }
  void OnDownloadUpdated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item, CefRefPtr<CefDownloadItemCallback> callback) override {
    CEF_REQUIRE_UI_THREAD();
    // CRX transfers belong to Chromium's extension installer, not the library.
    if (chrome_ && item->GetMimeType().ToString() == "application/x-chrome-extension") {
      downloadControls.erase(item->GetId());
      return;
    }
    if (!item->IsValid() || ![engine_.delegate respondsToSelector:@selector(browserDownloadUpdated:values:)]) return;
    NSString *path = [NSString stringWithUTF8String:item->GetFullPath().ToString().c_str()];
    NSString *url = [NSString stringWithUTF8String:item->GetURL().ToString().c_str()];
    NSString *name = path.lastPathComponent;
    if (!name.length) name = [NSString stringWithUTF8String:item->GetSuggestedFileName().ToString().c_str()];
    if (item->IsInProgress()) downloadControls[item->GetId()] = callback;
    else downloadControls.erase(item->GetId());
    NSString *state = item->IsComplete() ? @"complete" : item->IsCanceled() ? @"cancelled" : item->IsInProgress() ? (item->IsPaused() ? @"paused" : @"progress") : @"interrupted";
    [engine_.delegate browserDownloadUpdated:tabID_ values:@{@"id":@(item->GetId()),@"path":path ?: @"",@"url":url ?: @"",@"name":name ?: @"",@"received":@(item->GetReceivedBytes()),@"total":@(item->GetTotalBytes()),@"state":state,@"speed":@(item->GetCurrentSpeed())}];
  }
  bool OnBeforeDownload(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item, const CefString& name, CefRefPtr<CefBeforeDownloadCallback> callback) override {
    // Delegate CRX downloads without invoking the callback. Forcing a save
    // dialog also makes Chromium classify them as ordinary file downloads,
    // bypassing its normal extension installation and permission flow.
    if (chrome_ && item->GetMimeType().ToString() == "application/x-chrome-extension") return false;
    callback->Continue(name, true);
    return true;
  }
  bool OnPreKeyEvent(CefRefPtr<CefBrowser> browser, const CefKeyEvent& event, CefEventHandle osEvent, bool* shortcut) override {
    if (event.windows_key_code == 27 && (event.type == KEYEVENT_RAWKEYDOWN || event.type == KEYEVENT_KEYDOWN)) {
      auto tools = developerTools.find(tabID_.UTF8String);
      if (tools != developerTools.end() && tools->second->picking) { CancelNativeInspection(tabID_.UTF8String); return true; }
    }
    if ((event.modifiers & (EVENTFLAG_COMMAND_DOWN | EVENTFLAG_CONTROL_DOWN | EVENTFLAG_ALT_DOWN)) && (event.type == KEYEVENT_RAWKEYDOWN || event.type == KEYEVENT_KEYDOWN)) {
      NSEvent *nativeEvent = (__bridge NSEvent *)osEvent;
      const bool undo = (event.modifiers & EVENTFLAG_COMMAND_DOWN) && !(event.modifiers & (EVENTFLAG_SHIFT_DOWN | EVENTFLAG_ALT_DOWN | EVENTFLAG_CONTROL_DOWN)) && event.windows_key_code == 'Z';
      // Text editing keeps Chromium's native Undo. On the page background, Cmd-Z
      // can restore the last browser deletion even after the toast has faded.
      if (undo && event.focus_on_editable_field) return false;
      if (undo && embedded_ && [engine_.delegate respondsToSelector:@selector(browserUndoRequested)] && [engine_.delegate browserUndoRequested]) return true;
      if (nativeEvent && [NSApp.mainMenu performKeyEquivalent:nativeEvent]) return true;
      // AppKit owns browser shortcuts, including disabled/unassigned ones. Do not
      // fall through to Chrome's hidden owner window after a shortcut is remapped
      // (notably Cmd-N, Cmd-T, Cmd-L and DevTools). Text-editing shortcuts stay native.
      if (embedded_ && chrome_) {
        const int flags = event.modifiers;
        const bool command = flags & EVENTFLAG_COMMAND_DOWN;
        const bool option = flags & EVENTFLAG_ALT_DOWN;
        const bool control = flags & EVENTFLAG_CONTROL_DOWN;
        const bool shift = flags & EVENTFLAG_SHIFT_DOWN;
        const int key = event.windows_key_code;
        if (command && !option && !control &&
            (key == 'N' || key == 'T' || key == 'W' || key == 'L' ||
             key == 'S' || key == 'P' || key == 'D' || key == 'R' ||
             key == 'F' || key == 'Y' || (key == 'J' && shift) ||
             (key == 'C' && shift))) return true;
        if (command && !option && !control &&
            ((key >= '0' && key <= '9') || key == 187 || key == 189 ||
             key == 107 || key == 109 || key == 219 || key == 221)) return true;
        if (command && control && !option && key == 'F') return true;
        if (command && option && !control && (key == 'I' || key == 'J')) return true;
        if (control && !command && !option && key == 9) return true;
      }
    }
    return false;
  }
 private:
  __weak BrowserEngine *engine_;
  NSString *tabID_;
  bool embedded_;
  bool chrome_;
  std::shared_ptr<std::map<int, std::string>> pendingPopups_ = std::make_shared<std::map<int, std::string>>();
  std::shared_ptr<bool> popupLifetime_;
  std::function<void(bool)> popupFinished_;
  std::shared_ptr<FaviconState> favicon_ = std::make_shared<FaviconState>();
  IMPLEMENT_REFCOUNTING(NativeClient);
};

static void QuitNext() {
  if (!quitting) return;
  if (browsers.empty()) { if (pendingBrowsers.empty()) Notify(@"BrowserEngineReadyToQuit"); return; }
  browsers.begin()->second->GetHost()->CloseBrowser(false);
}

// Chrome-owned windows provide the real extension actions and installation UI.
// They share the exact request context used by the AppKit tab containers.
#include "ExtensionWindows.inc"
#include "ChromeTabs.inc"
#include "NativePageMenus.inc"
#include "NativeExtensionTabs.inc"

@implementation BrowserEngine
- (BOOL)registerPrivateProfile:(NSString *)profileID {
  CEF_REQUIRE_UI_THREAD();
  if (!profileID.length || profileID.length > 100 ||
      [profileID rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"].invertedSet].location != NSNotFound) return NO;
  const std::string key = profileID.UTF8String;
  if (profiles.count(key) && !privateProfiles.count(key)) return NO;
  privateProfiles.insert(key); return YES;
}
- (void)releasePrivateProfile:(NSString *)profileID {
  CEF_REQUIRE_UI_THREAD();
  const std::string key = profileID.UTF8String;
  if (!privateProfiles.count(key)) return;
  extensionPreferenceRegistrations.erase(key); readyProfiles.erase(key);
  profileReadyCallbacks.erase(key); profiles.erase(key); privateProfiles.erase(key);
}
- (void)controlDownload:(NSUInteger)identifier action:(NSString *)action {
  CEF_REQUIRE_UI_THREAD();
  auto found = downloadControls.find((uint32_t)identifier);
  if (found == downloadControls.end()) return;
  auto callback = found->second;
  if ([action isEqualToString:@"pause"]) callback->Pause();
  else if ([action isEqualToString:@"resume"]) callback->Resume();
  else if ([action isEqualToString:@"cancel"]) callback->Cancel();
}

+ (NSApplication *)createApplication { return [BrowserNativeApplication sharedApplication]; }
+ (NSString *)chromiumVersion { return [NSString stringWithFormat:@"%d.%d.%d.%d", CHROME_VERSION_MAJOR, CHROME_VERSION_MINOR, CHROME_VERSION_BUILD, CHROME_VERSION_PATCH]; }
+ (BOOL)startWithCachePath:(NSString *)cachePath {
  if (running) return YES;
  NSString *testRoot = NSProcessInfo.processInfo.environment[@"BROWSER_NATIVE_TEST_DATA"];
  NSString *mockCache = nil;
  if (testRoot != nil) {
    NSString *personal = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject.path stringByAppendingPathComponent:@"BrowserNative"];
    mockCache = BrowserMockKeychainCache(cachePath, testRoot, personal);
    if (!mockCache) { NSLog(@"Refusing a test keychain outside an isolated profile."); return NO; }
  }
  BrowserDiagnosticsBegin(cachePath);
  if (mockCache) {
    if (![NSFileManager.defaultManager createDirectoryAtPath:mockCache withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) return NO;
    cachePath = mockCache;
    mockTestKeychain = true;
    BrowserTrace(@"test.mock-keychain.enabled");
  }
  BrowserTrace(@"cef.initialize.begin");
  loader = std::make_unique<CefScopedLibraryLoader>();
  if (!loader->LoadInMain()) { loader.reset(); return NO; }
  BrowserTraceLoadedEngine();
  char *canonical = realpath(cachePath.fileSystemRepresentation, nullptr);
  if (!canonical) { loader.reset(); return NO; }
  cachePath = [NSString stringWithUTF8String:canonical];
  free(canonical);
  CefMainArgs args(*_NSGetArgc(), *_NSGetArgv());
  CefSettings settings;
  CefString(&settings.locale) = [[[NSUserDefaults standardUserDefaults] stringForKey:@"BrowserLanguage"] isEqualToString:@"en"] ? "en-US" : "fr";
  CefString(&settings.accept_language_list) = WebLanguages();
  settings.no_sandbox = false;
  settings.persist_session_cookies = true;
  // A private, stable service avoids accessing Chromium's shared Keychain item.
  // Isolated tests use Chromium's mock, with a separate cache. These production
  // service/account names are stable: renaming them would lose decryption keys.
  BOOL isolatedTest = NSProcessInfo.processInfo.environment[@"BROWSER_NATIVE_TEST_DATA"] != nil;
  CefString(&settings.keychain_service_name) = isolatedTest ? "Browser Tests Safe Storage" : "Browser Safe Storage";
  CefString(&settings.keychain_account_name) = isolatedTest ? "Browser Tests" : "Browser";
  CefString(&settings.root_cache_path) = CefStr(cachePath);
  CefString(&settings.cache_path) = CefStr([cachePath stringByAppendingPathComponent:@"Default"]);
  CefString(&settings.log_file) = CefStr([cachePath stringByAppendingPathComponent:@"chromium.log"]);
  settings.log_severity = LOGSEVERITY_WARNING;
  rootCache = cachePath.UTF8String;
  NSString *debugPort = NSProcessInfo.processInfo.environment[@"BROWSER_NATIVE_DEBUG_PORT"];
  if (debugPort && NSProcessInfo.processInfo.environment[@"BROWSER_NATIVE_TEST_DATA"]) settings.remote_debugging_port = debugPort.intValue;
  running = CefInitialize(args, settings, new NativeApp(), nullptr);
  BrowserTrace(@"cef.initialize.end",@{@"success":@(running)});
  return running;
}
+ (void)runMessageLoop { if (running) { BrowserTrace(@"cef.loop.begin"); CefRunMessageLoop(); BrowserTrace(@"cef.loop.end",@{@"quitting":@(quitting)}); } }
+ (void)stopMessageLoop {
  if (!running || !quitting || !browsers.empty() || !pendingBrowsers.empty()) return;
  BrowserTrace(@"cef.loop.stop-request",@{@"quitting":@(quitting)});
  CefQuitMessageLoop();
  // The host owns NSApplication's loop. Chrome can retain a macOS keep-alive
  // after the last private window closes; all native browser owners are already
  // drained here, so let the host return from its loop and run CefShutdown.
  [NSApp stop:nil];
  [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined
      location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0
      context:nil subtype:0 data1:0 data2:0] atStart:NO];
}
+ (void)requestQuit {
  BrowserTrace(@"app.quit-request",@{@"alreadyQuitting":@(quitting),@"browsers":@(browsers.size()),@"stack":NSThread.callStackSymbols});
  if (quitting) return;
  quitting = true;
  QuitNext();
}
+ (void)shutdown {
  [extensionOpenTraceTimer invalidate]; extensionOpenTraceTimer = nil;
  BrowserTrace(@"cef.shutdown.begin",@{@"browsers":@(browsers.size()),@"pending":@(pendingBrowsers.size())});
  downloadControls.clear();
  if (!running || !browsers.empty() || !pendingBrowsers.empty()) return;
  RegisterNativeExtensionTabs(false);
  profileReadyCallbacks.clear();
  extensionPreferenceRegistrations.clear();
  readyProfiles.clear();
  profiles.clear();
  CefShutdown();
  running = false;
  loader.reset();
  BrowserTrace(@"cef.shutdown.end");
}
- (void)setAppearanceMode:(NSInteger)mode {
  appearanceMode = mode == 2 ? CEF_COLOR_VARIANT_DARK : mode == 1 ? CEF_COLOR_VARIANT_LIGHT : CEF_COLOR_VARIANT_SYSTEM;
  for (auto &entry : profiles) if (readyProfiles.count(entry.first)) entry.second->SetChromeColorScheme(appearanceMode, 0);
  for (auto &entry : browsers) ApplyPageAppearance(entry.second);
}
- (BOOL)updateCredentialPreferences {
  if (!running || quitting) return NO;
  bool success = ApplyCredentialPreferences(CefRequestContext::GetGlobalContext());
  for (auto &entry : profiles)
    if (readyProfiles.count(entry.first)) success = ApplyCredentialPreferences(entry.second) && success;
  return success;
}
- (void)updateLanguages {
  if (!running || quitting) return;
  ApplyWebLanguage(CefRequestContext::GetGlobalContext());
  for (auto &entry : profiles)
    if (readyProfiles.count(entry.first)) ApplyWebLanguage(entry.second);
}
- (BOOL)createTab:(NSString *)tabID profile:(NSString *)profileID url:(NSString *)url inView:(NSView *)container {
  if (!running || quitting || !Allowed(url)) return NO;
  if (browsers.count(tabID.UTF8String) || pendingBrowsers.count(tabID.UTF8String)) return YES;
  auto context = ContextForProfile(profileID);
  if (!context) return NO;
  if (readyProfiles.count(profileID.UTF8String)) return CreateChromeTab(self, tabID, url, container, context);
  pendingBrowsers[tabID.UTF8String] = false;
  __weak BrowserEngine *owner = self;
  profileReadyCallbacks[profileID.UTF8String].push_back([^{
    BrowserEngine *engine = owner;
    const std::string key = tabID.UTF8String;
    if (!engine || quitting || pendingBrowsers[key]) {
      pendingBrowsers.erase(key);
      pendingNavigation.erase(key);
      discardedBrowsers.erase(key);
      [engine.delegate browserClosed:tabID];
      if (quitting) QuitNext();
      return;
    }
    if (!CreateChromeTab(engine, tabID, url, container, context)) {
      pendingBrowsers.erase(key);
      [engine.delegate browserClosed:tabID];
    }
  } copy]);
  return YES;
}

- (BOOL)showExtensionStoreForProfile:(NSString *)profileID name:(NSString *)name address:(NSString *)address {
  NSURLComponents *url = [NSURLComponents componentsWithString:address];
  if (!running || quitting || ![url.scheme.lowercaseString isEqualToString:@"https"] ||
      ![url.host.lowercaseString isEqualToString:@"chromewebstore.google.com"] || url.user || url.password) return NO;
  return ShowExtensionAddress(profileID, name, address.UTF8String);
}
- (BOOL)showExtensionsForProfile:(NSString *)profileID name:(NSString *)name store:(BOOL)store {
  if (!running || quitting) return NO;
  return ShowExtensionWindow(profileID, name, store);
}
- (void)navigateTab:(NSString *)tabID url:(NSString *)url { if (!Allowed(url)) return; auto i = browsers.find(tabID.UTF8String); if (i != browsers.end()) i->second->GetMainFrame()->LoadURL(CefStr(url)); else if (pendingBrowsers.count(tabID.UTF8String)) pendingNavigation[tabID.UTF8String] = url.UTF8String; }
- (void)resizeTab:(NSString *)tabID inView:(NSView *)container { if (chromeTabs.count(tabID.UTF8String)) { LayoutChromeTab(tabID.UTF8String); return; } auto i = browsers.find(tabID.UTF8String); if (i == browsers.end()) return; NSView *view = (__bridge NSView *)i->second->GetHost()->GetWindowHandle(); view.frame = container.bounds; }
- (void)setTab:(NSString *)tabID visible:(BOOL)visible { SetDeveloperToolsVisible(tabID.UTF8String,visible); if (!visible && tabVisibility[tabID.UTF8String]) { DismissSitePermissionSheet(tabID.UTF8String); CloseNativeExtensionPopup(tabID.UTF8String); } tabVisibility[tabID.UTF8String] = visible; if (chromeTabs.count(tabID.UTF8String)) { LayoutChromeTab(tabID.UTF8String); return; } auto i = browsers.find(tabID.UTF8String); if (i == browsers.end()) return; NSView *view = (__bridge NSView *)i->second->GetHost()->GetWindowHandle(); BOOL wasHidden = view.hidden; view.hidden = !visible; if (visible && wasHidden && view.window.isKeyWindow && !view.window.attachedSheet) i->second->GetHost()->SetFocus(true); }
- (void)focusTab:(NSString *)tabID {
  auto chrome = chromeTabs.find(tabID.UTF8String);
  if (chrome != chromeTabs.end() && chrome->second.content) {
    NSView *view = chrome->second.content;
    if (!view.hiddenOrHasHiddenAncestor && view.window.isKeyWindow) [view.window makeFirstResponder:view];
    return;
  }
  auto i = browsers.find(tabID.UTF8String); if (i != browsers.end()) i->second->GetHost()->SetFocus(true);
}
- (void)toggleMute:(NSString *)tabID { auto i = browsers.find(tabID.UTF8String); if (i != browsers.end()) { auto host = i->second->GetHost(); host->SetAudioMuted(!host->IsAudioMuted()); } }
- (void)requestPictureInPicture:(NSString *)tabID automatic:(BOOL)automatic completion:(void (^)(NSString *))completion {
  CEF_REQUIRE_UI_THREAD();
  auto i = browsers.find(tabID.UTF8String);
  if (quitting || i == browsers.end()) { completion(@"unavailable"); return; }
  if (automatic && i->second->GetHost()->IsAudioMuted()) { completion(@"no-video"); return; }
  if (nativePiP) {
    if (automatic) { completion(@"busy"); return; }
    bool same = [nativePiP->tab() isEqual:tabID];
    nativePiP->Close();
    if (same) { completion(@"closed"); return; }
  }
  BrowserTrace(@"pip.request",@{@"tab":tabID,@"automatic":@(automatic)});
  nativePiP = new NativePictureInPicture(tabID,automatic,completion);
  nativePiP->Start(i->second);
}
- (void)closePictureInPicture:(NSString *)tabID { if (nativePiP && [nativePiP->tab() isEqual:tabID]) nativePiP->Close(); }
- (BOOL)hasPictureInPicture:(NSString *)tabID { return nativePiP && nativePiP->active() && [nativePiP->tab() isEqual:tabID]; }
- (void)goBack:(NSString *)tabID { auto i = browsers.find(tabID.UTF8String); if (i != browsers.end() && i->second->CanGoBack()) i->second->GoBack(); }
- (void)goForward:(NSString *)tabID { auto i = browsers.find(tabID.UTF8String); if (i != browsers.end() && i->second->CanGoForward()) i->second->GoForward(); }
- (void)reload:(NSString *)tabID { auto i = browsers.find(tabID.UTF8String); if (i != browsers.end()) i->second->Reload(); }
- (void)reloadIgnoringCache:(NSString *)tabID { auto i = browsers.find(tabID.UTF8String); if (i != browsers.end()) i->second->ReloadIgnoreCache(); }
- (double)zoomLevel:(NSString *)tabID { auto i = browsers.find(tabID.UTF8String); return i == browsers.end() ? 0 : i->second->GetHost()->GetZoomLevel(); }
- (void)setZoomLevel:(NSString *)tabID level:(double)level {
  auto i = browsers.find(tabID.UTF8String);
  if (i != browsers.end() && std::isfinite(level)) i->second->GetHost()->SetZoomLevel(std::max(-6.0, std::min(9.0, level)));
}
- (BOOL)canSavePage:(NSString *)tabID {
  auto i = browsers.find(tabID.UTF8String); int command = cef_id_for_command_id_name("IDC_SAVE_PAGE");
  return i != browsers.end() && command > 0 && i->second->GetHost()->CanExecuteChromeCommand(command);
}
- (void)savePage:(NSString *)tabID {
  auto i = browsers.find(tabID.UTF8String); int command = cef_id_for_command_id_name("IDC_SAVE_PAGE");
  if (i != browsers.end() && command > 0 && i->second->GetHost()->CanExecuteChromeCommand(command))
    i->second->GetHost()->ExecuteChromeCommand(command, CEF_WOD_CURRENT_TAB);
}
- (void)printPage:(NSString *)tabID { auto i = browsers.find(tabID.UTF8String); if (i != browsers.end()) i->second->GetHost()->Print(); }
- (void)stop:(NSString *)tabID { auto i = browsers.find(tabID.UTF8String); if (i != browsers.end()) i->second->StopLoad(); }
- (void)closeTab:(NSString *)tabID { auto i = browsers.find(tabID.UTF8String); if (i != browsers.end()) i->second->GetHost()->CloseBrowser(false); else if (pendingBrowsers.count(tabID.UTF8String)) pendingBrowsers[tabID.UTF8String] = true; else [self.delegate browserClosed:tabID]; }
- (void)discardTab:(NSString *)tabID {
  const std::string key = tabID.UTF8String;
  auto i = browsers.find(key);
  if (i != browsers.end()) { discardedBrowsers.insert(key); i->second->GetHost()->CloseBrowser(true); }
  else if (pendingBrowsers.count(key)) { discardedBrowsers.insert(key); pendingBrowsers[key] = true; }
  else [self.delegate browserClosed:tabID];
}
- (void)findInTab:(NSString *)tabID text:(NSString *)text forward:(BOOL)forward next:(BOOL)next { auto i = browsers.find(tabID.UTF8String); if (i != browsers.end()) i->second->GetHost()->Find(CefStr(text), forward, false, next); }
- (NSDictionary<NSString *, id> *)extensionSettingsForProfile:(NSString *)profile {
  CEF_REQUIRE_UI_THREAD();
  auto found = profiles.find(profile.UTF8String);
  if (found == profiles.end() || !readyProfiles.count(profile.UTF8String)) return nil;
  auto value = found->second->GetPreference("extensions.settings");
  if (!value || value->GetType() != VTYPE_DICTIONARY) return nil;
  auto json = CefWriteJSON(value, JSON_WRITER_DEFAULT).ToString();
  NSData *data = [NSData dataWithBytes:json.data() length:json.size()];
  return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}
- (BOOL)setExtensionPinned:(NSString *)identifier profile:(NSString *)profile pinned:(BOOL)pinned {
  if (identifier.length != 32 || [identifier rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnop"].invertedSet].location != NSNotFound) return NO;
  auto context = ContextForProfile(profile);
  if (!context || !readyProfiles.count(profile.UTF8String) || !context->CanSetPreference("extensions.pinned_extensions")) return NO;
  auto old = context->GetPreference("extensions.pinned_extensions");
  auto values = CefListValue::Create(); size_t next = 0;
  if (old && old->GetType() == VTYPE_LIST) {
    auto list = old->GetList();
    for (size_t i=0;i<list->GetSize();i++) if (list->GetType(i) == VTYPE_STRING && list->GetString(i) != CefStr(identifier)) values->SetString(next++,list->GetString(i));
  }
  if (pinned) values->SetString(next,CefStr(identifier));
  auto value = CefValue::Create(); value->SetList(values); CefString error;
  return context->SetPreference("extensions.pinned_extensions",value,error);
}
- (NSInteger)activateExtension:(NSString *)identifier forTab:(NSString *)tabID anchor:(NSRect)screenAnchor {
  CEF_REQUIRE_UI_THREAD();
  if (identifier.length != 32 || [identifier rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnop"].invertedSet].location != NSNotFound) return -2;
  auto browser = browsers.find(tabID.UTF8String);
  if (browser == browsers.end() || !chromeTabs.count(tabID.UTF8String) || !tabVisibility[tabID.UTF8String]) return -3;
  if (!std::isfinite(screenAnchor.origin.x) || !std::isfinite(screenAnchor.origin.y) ||
      !std::isfinite(screenAnchor.size.width) || !std::isfinite(screenAnchor.size.height)) return -2;
  using Execute = int (*)(int, const char *, int, int, int, int);
  auto execute = reinterpret_cast<Execute>(BrowserEngineSymbol("browser_execute_extension_action_v1"));
  if (!execute) return -100; // Adapted framework has not been installed yet.
  // Cocoa uses bottom-left screen coordinates. Chromium uses top-left DIPs,
  // relative to the primary screen, even on secondary displays and Retina.
  CGFloat top = NSScreen.screens.firstObject.frame.size.height;
  CGFloat x = NSMinX(screenAnchor), y = top - NSMaxY(screenAnchor);
  if (std::abs(x) > 1048576 || std::abs(y) > 1048576 ||
      screenAnchor.size.width < 1 || screenAnchor.size.width > 512 ||
      screenAnchor.size.height < 1 || screenAnchor.size.height > 512) return -2;
  if (!activeExtensionTab.empty() && (activeExtensionTab != tabID.UTF8String || activeExtensionID != identifier.UTF8String)) CloseNativeExtensionPopup(activeExtensionTab);
  const double started = NSProcessInfo.processInfo.systemUptime;
  BrowserTrace(@"extension.action",@{@"extension":identifier,@"browser":@(browser->second->GetIdentifier())});
  int result = execute(browser->second->GetIdentifier(), identifier.UTF8String,
                 (int)std::round(x), (int)std::round(y),
                 (int)std::ceil(screenAnchor.size.width), (int)std::ceil(screenAnchor.size.height));
  BrowserTrace(@"extension.dispatched",@{@"extension":identifier,@"result":@(result),
      @"elapsedMs":@((NSProcessInfo.processInfo.systemUptime-started)*1000)});
  if (result == 0) {
    activeExtensionTab = tabID.UTF8String; activeExtensionID = identifier.UTF8String; activeExtensionAnchor = screenAnchor;
    TraceExtensionPopupOpening(browser->second->GetIdentifier(),identifier);
  }
  return result;
}
- (void)closeExtensionPopup { if (!activeExtensionTab.empty()) CloseNativeExtensionPopup(activeExtensionTab); }
- (NSDictionary<NSString *, id> *)certificateInfoForTab:(NSString *)tabID {
  CEF_REQUIRE_UI_THREAD();
  if (!running || quitting) return nil;
  auto browser = browsers.find(tabID.UTF8String);
  if (browser == browsers.end()) return nil;
  auto entry = browser->second->GetHost()->GetVisibleNavigationEntry();
  if (!entry || !entry->IsValid()) return nil;
  NSString *address = Str(entry->GetURL());
  NSURL *url = [NSURL URLWithString:address];
  if (![url.scheme.lowercaseString isEqualToString:@"https"] || !url.host.length) return nil;
  auto ssl = entry->GetSSLStatus();
  auto certificate = ssl ? ssl->GetX509Certificate() : nullptr;
  if (!certificate) return nil;
  // Snapshot the visible document's chain; never start a separate connection
  // that could return a different certificate after a redirect or proxy change.
  auto dataFor = [](CefRefPtr<CefBinaryValue> value) -> NSData * {
    if (!value || !value->GetSize()) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:value->GetSize()];
    return value->GetData(data.mutableBytes, data.length, 0) == data.length ? data : nil;
  };
  NSData *leaf = dataFor(certificate->GetDEREncoded());
  if (!leaf) return nil;
  NSMutableArray<NSData *> *chain = [NSMutableArray arrayWithObject:leaf];
  CefX509Certificate::IssuerChainBinaryList issuers;
  certificate->GetDEREncodedIssuerChain(issuers);
  for (auto issuer : issuers) {
    if (NSData *data = dataFor(issuer)) [chain addObject:data];
  }
  const bool secure = ssl->IsSecureConnection() && !CefIsCertStatusError(ssl->GetCertStatus()) &&
      ssl->GetContentStatus() == SSL_CONTENT_NORMAL_CONTENT;
  return @{@"url":address, @"certificates":chain, @"secure":@(secure)};
}
- (BOOL)hasDeveloperTools:(NSString *)tabID {
  auto i = browsers.find(tabID.UTF8String);
  return i != browsers.end() && i->second->GetHost()->HasDevTools();
}
- (void)toggleDeveloperTools:(NSString *)tabID {
  [self toggleDeveloperTool:@"console" forTab:tabID];
}
- (NSString *)developerToolForTab:(NSString *)tabID {
  auto it = developerTools.find(tabID.UTF8String);
  if (it == developerTools.end() || it->second->closed) return @"";
  return it->second->picking ? @"inspect" : (it->second->panelOpen ? @(it->second->panel.c_str()) : @"");
}
- (void)toggleDeveloperTool:(NSString *)tool forTab:(NSString *)tabID {
  CEF_REQUIRE_UI_THREAD();
  if (quitting || !browsers.count(tabID.UTF8String) || ![@[@"console",@"network",@"inspect"] containsObject:tool]) return;
  const std::string key = tabID.UTF8String;
  auto it = developerTools.find(key);
  if (![tool isEqualToString:@"inspect"] && it != developerTools.end() && !it->second->closed && it->second->panelOpen && it->second->panel == tool.UTF8String) { CloseTabDeveloperTools(key); return; }
  auto state = it != developerTools.end() && !it->second->closed ? it->second : std::make_shared<DeveloperToolsState>();
  developerTools[key] = state;
  if ([tool isEqualToString:@"inspect"]) { StartNativeInspection(key,state); return; }
  if (state->picking) StopNativeInspection(key,state);
  state->panel = tool.UTF8String; state->selectedNode = 0; ShowDeveloperTools(key,state);
}
- (void)closeDeveloperTools:(NSString *)tabID { CEF_REQUIRE_UI_THREAD(); CloseTabDeveloperTools(tabID.UTF8String); }
- (void)capturePage:(NSString *)tabID completion:(void (^)(NSData *))completion {
  CEF_REQUIRE_UI_THREAD();
  auto browser = browsers.find(tabID.UTF8String);
  if (quitting || browser == browsers.end() || !tabVisibility[tabID.UTF8String]) { completion(nil); return; }
  CefRefPtr<PageCaptureRequest> request = new PageCaptureRequest(completion);
  request->Start(browser->second);
}
- (void)captureFullPage:(NSString *)tabID completion:(void (^)(NSData *))completion {
  CEF_REQUIRE_UI_THREAD();
  auto browser = browsers.find(tabID.UTF8String);
  if (quitting || browser == browsers.end() || !tabVisibility[tabID.UTF8String]) { completion(nil); return; }
  NSView *view = [self captureViewForTab:tabID];
  CefRefPtr<PageCaptureRequest> request = new PageCaptureRequest(completion);
  request->Start(browser->second,true,view.window.backingScaleFactor ?: 2);
}
- (NSView *)captureViewForTab:(NSString *)tabID {
  auto it = chromeTabs.find(tabID.UTF8String);
  return it != chromeTabs.end() ? it->second.content : nil;
}
- (void)captureElementAtPoint:(NSPoint)point forTab:(NSString *)tabID completion:(void (^)(NSDictionary *))completion {
  CEF_REQUIRE_UI_THREAD();
  auto browser = browsers.find(tabID.UTF8String);
  if (quitting || browser == browsers.end() || !tabVisibility[tabID.UTF8String] ||
      !std::isfinite(point.x) || !std::isfinite(point.y) || point.x < 0 || point.x > 1 || point.y < 0 || point.y > 1) { completion(nil); return; }
  CefRefPtr<CaptureElementRequest> request = new CaptureElementRequest(completion);
  request->Start(browser->second,point);
}
- (void)clearCacheForTab:(NSString *)tabID completion:(void (^)(BOOL))completion {
  auto i = browsers.find(tabID.UTF8String); if (i == browsers.end()) { completion(NO); return; }
  i->second->GetHost()->GetRequestContext()->ClearHttpCache(new SiteCompletion(completion));
}
- (void)setPageInputSuppressed:(BOOL)suppressed forTab:(NSString *)tabID {
  auto i = browsers.find(tabID.UTF8String); if (i == browsers.end()) return;
  auto params = CefDictionaryValue::Create(); params->SetBool("ignore", suppressed);
  i->second->GetHost()->ExecuteDevToolsMethod(0, "Input.setIgnoreInputEvents", params);
}
- (void)clearCookiesForTab:(NSString *)tabID completion:(void (^)(BOOL))completion {
  auto i = browsers.find(tabID.UTF8String); if (i == browsers.end()) { completion(NO); return; }
  NSString *address = [NSString stringWithUTF8String:i->second->GetMainFrame()->GetURL().ToString().c_str()];
  NSURL *url = [NSURL URLWithString:address];
  if (!url.host.length || !([url.scheme isEqualToString:@"https"] || [url.scheme isEqualToString:@"http"])) { completion(NO); return; }
  auto manager = i->second->GetHost()->GetRequestContext()->GetCookieManager(nullptr);
  if (!manager) { completion(NO); return; }
  CefRefPtr<SiteCookieVisitor> visitor = new SiteCookieVisitor(manager, completion);
  visitor->accepted = manager->VisitUrlCookies(CefStr(address), true, visitor);
}
- (void)stopFinding:(NSString *)tabID { auto i = browsers.find(tabID.UTF8String); if (i != browsers.end()) i->second->GetHost()->StopFinding(true); }
@end
