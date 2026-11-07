// The engine calls this synchronously on its UI thread before navigating a
// tab created by an extension. Return the real CEF browser ID, not a URL copy.
static int CreateNativeExtensionTab(int sourceBrowserID, int active,
                                    int pinned, int index) {
  CEF_REQUIRE_UI_THREAD();
  if (quitting) return -1;
  auto source = std::find_if(browsers.begin(), browsers.end(), [sourceBrowserID](const auto& entry) {
    return entry.second->GetIdentifier() == sourceBrowserID;
  });
  if (source == browsers.end() || !chromeTabs.count(source->first)) return 0;
  const auto owner = nativeTabOwners.find(source->first);
  BrowserEngine *engine = owner == nativeTabOwners.end() ? nil : owner->second.engine;
  if (!engine.delegate || ![engine.delegate respondsToSelector:@selector(browserPrepareExtensionTab:active:pinned:index:aboveSource:)] ||
      ![engine.delegate respondsToSelector:@selector(browserExtensionTabCreated:success:)]) return -1;
  auto sourceBrowser = source->second;
  if (!sourceBrowser->IsValid()) return -1;
  NSString *sourceID = @(source->first.c_str());
  NSDictionary *prepared = [engine.delegate browserPrepareExtensionTab:sourceID active:active != 0 pinned:pinned != 0 index:index
                                                aboveSource:[sourceID isEqualToString:contextLinkSource]];
  NSString *identifier = prepared[@"id"];
  NSView *container = prepared[@"view"];
  if (!identifier.length || !container) return -1;

  // Reuse the source context exactly: cookies, installed extensions and profile
  // permissions must not leak into a different space's profile.
  bool created = CreateChromeTab(engine, identifier, @"about:blank", container,
                                sourceBrowser->GetHost()->GetRequestContext());
  auto target = browsers.find(identifier.UTF8String);
  bool ready = created && target != browsers.end() && target->second->IsValid();
  int result = ready ? target->second->GetIdentifier() : -1;
  if (!ready && created) [engine discardTab:identifier];
  [engine.delegate browserExtensionTabCreated:identifier success:ready];
  return result;
}

static int NativeExtensionInstalled(const char *path, const char *identifier, const char *name) {
  CEF_REQUIRE_UI_THREAD();
  if (quitting || !path || !identifier || !name) return 0;
  for (const auto& profile : profiles) {
    if (profile.second->GetCachePath().ToString() != path) continue;
    for (const auto& entry : browsers) {
      if (!chromeTabs.count(entry.first) || !entry.second->GetHost()->GetRequestContext()->IsSame(profile.second)) continue;
      const auto owner = nativeTabOwners.find(entry.first);
      BrowserEngine *engine = owner == nativeTabOwners.end() ? nil : owner->second.engine;
      if (![engine.delegate respondsToSelector:@selector(browserExtensionInstalled:name:profile:)]) continue;
      NSString *extensionID = @(identifier), *title = @(name), *profileID = @(profile.first.c_str());
      // Never reenter AppKit or the installer while its success callback runs.
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!quitting) [engine.delegate browserExtensionInstalled:extensionID name:title profile:profileID];
      });
      return 1;
    }
  }
  return 0;
}

// Chromium's own toolbar is hidden. Confirmation dialogs use the complete
// AppKit window of the visible tab in this profile, never a toolbar anchor.
static int NativeExtensionDialogBounds(const char *path, int *bounds) {
  CEF_REQUIRE_UI_THREAD();
  if (quitting || !path || !bounds) return 0;
  for (const auto& profile : profiles) {
    if (profile.second->GetCachePath().ToString() != path) continue;
    for (const auto& entry : browsers) {
      if (!tabVisibility[entry.first] || !entry.second->GetHost()->GetRequestContext()->IsSame(profile.second)) continue;
      auto surface = chromeTabs.find(entry.first);
      if (surface == chromeTabs.end()) continue;
      NSWindow *window = surface->second.container.window;
      if (!window || !window.visible || window.miniaturized) continue;
      NSRect frame = window.frame;
      bounds[0] = (int)std::round(frame.origin.x);
      bounds[1] = (int)std::round(NSScreen.screens.firstObject.frame.size.height - NSMaxY(frame));
      bounds[2] = (int)std::round(frame.size.width);
      bounds[3] = (int)std::round(frame.size.height);
      return 1;
    }
  }
  return 0;
}

static void RegisterNativeExtensionTabs(bool enabled) {
  using Callback = int (*)(int, int, int, int);
  using Register = int (*)(Callback);
  auto install = reinterpret_cast<Register>(BrowserEngineSymbol("browser_set_extension_tab_creator_v1"));
  if (install) install(enabled ? CreateNativeExtensionTab : nullptr);
  using Notice = int (*)(const char *, const char *, const char *);
  using RegisterNotice = void (*)(Notice);
  auto notice = reinterpret_cast<RegisterNotice>(BrowserEngineSymbol("browser_set_extension_install_notice_v1"));
  if (notice) notice(enabled ? NativeExtensionInstalled : nullptr);
  using DialogBounds = int (*)(const char *, int *);
  using RegisterBounds = void (*)(DialogBounds);
  auto bounds = reinterpret_cast<RegisterBounds>(BrowserEngineSymbol("browser_set_extension_dialog_bounds_v1"));
  if (bounds) bounds(enabled ? NativeExtensionDialogBounds : nullptr);
}
