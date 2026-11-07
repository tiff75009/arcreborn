// SPDX-License-Identifier: MPL-2.0
// Ask every renderer, including cross-origin frames. Lack of a reply never
// authorizes closing a live page. There is no polling until the tab is overdue.
// Blink counts even silent RTCPeerConnections in its renderer process.
// Query the counter only for overdue documents. Multiple renderer processes
// cannot be cleared by the main target's counter, so keep those tabs alive.
class IdleAudioRtcCheck : public CefDevToolsMessageObserver {
 public:
  void Start(CefRefPtr<CefBrowser> browser, void (^reply)(BOOL)) {
    host_ = browser->GetHost();
    reply_ = [reply copy];
    registration_ = host_->AddDevToolsMessageObserver(this);
    enable_ = host_->ExecuteDevToolsMethod(0, "Performance.enable", nullptr);
    if (!enable_) reply_(NO);
  }
  void Stop() {
    if (enable_ && host_) host_->ExecuteDevToolsMethod(0, "Performance.disable", nullptr);
    reply_ = nil;
    CefRefPtr<IdleAudioRtcCheck> keep(this);
    dispatch_async(dispatch_get_main_queue(), ^{ keep->registration_ = nullptr; keep->host_ = nullptr; });
  }
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int id, bool success, const void* data, size_t size) override {
    auto reply = reply_;
    if (!reply) return;
    if (id == enable_) {
      if (!success || !(metrics_ = host_->ExecuteDevToolsMethod(0, "Performance.getMetrics", nullptr))) reply(NO);
      return;
    }
    if (id != metrics_) return;
    bool clear = false;
    if (success && data && size < 65536) {
      NSDictionary *result = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:data length:size] options:0 error:nil];
      for (NSDictionary *metric in result[@"metrics"]) {
        NSString *name = metric[@"name"];
        if ([name isEqual:@"RTCPeerConnections"]) clear = [metric[@"value"] isEqual:@0];
        // Web Audio can play without an element or an audible sample at this instant.
        if (([name isEqual:@"AudioHandlers"] || [name isEqual:@"AudioWorkletProcessors"]) &&
            [metric[@"value"] integerValue] > 0) { clear = false; break; }
      }
    }
    reply(clear);
  }
 private:
  int enable_ = 0, metrics_ = 0;
  void (^reply_)(BOOL) = nil;
  CefRefPtr<CefBrowserHost> host_;
  CefRefPtr<CefRegistration> registration_;
  IMPLEMENT_REFCOUNTING(IdleAudioRtcCheck);
};
struct ArchiveProbe {
  std::string nonce;
  std::set<std::string> frames;
  void (^reply)(BOOL);
  size_t frameCount;
  int process = 0;
  CefRefPtr<IdleAudioRtcCheck> rtc;
};
static std::map<std::string,ArchiveProbe> archiveProbes;
static std::set<std::string> capturingTabs, automaticallyClosing;
static std::set<std::string> audibleTabs;
static void FinishArchiveProbe(const std::string& tab, bool idle) {
  auto it = archiveProbes.find(tab); if (it == archiveProbes.end()) return;
  auto reply = it->second.reply;
  if (it->second.rtc) it->second.rtc->Stop();
  archiveProbes.erase(it);
  dispatch_async(dispatch_get_main_queue(), ^{ reply(idle); });
}
static bool HasActiveDownload(CefRefPtr<CefBrowser> browser) {
  const uint64_t prefix = uint64_t(browser->GetIdentifier()) << 32;
  auto entry = downloadControls.lower_bound(prefix);
  return entry != downloadControls.end() && (entry->first >> 32) == (prefix >> 32);
}
static void CheckArchiveMedia(NSString* key, bool forSleep, void (^reply)(BOOL)) {
  std::string tab = key.UTF8String;
  auto it = browsers.find(tab);
  if (quitting || it == browsers.end() || !it->second->IsValid() || it->second->IsLoading()
      || capturingTabs.count(tab) || audibleTabs.count(tab) || HasActiveDownload(it->second) || archiveProbes.count(tab)) { reply(NO); return; }
  std::vector<CefString> ids; it->second->GetFrameIdentifiers(ids);
  if (ids.empty() || ids.size() > 128) { reply(NO); return; }
  std::string nonce = NSUUID.UUID.UUIDString.UTF8String;
  ArchiveProbe probe{nonce,{},[reply copy],ids.size()};
  for (const auto& id : ids) probe.frames.insert(id.ToString());
  archiveProbes.emplace(tab,std::move(probe));
  for (const auto& id : ids) {
    auto frame = it->second->GetFrameByIdentifier(id);
    if (!frame || !frame->IsValid()) { FinishArchiveProbe(tab,false); return; }
    auto message = CefProcessMessage::Create("ArcReborn.ProbeIdleFrame");
    message->GetArgumentList()->SetString(0,nonce);
    message->GetArgumentList()->SetBool(1,forSleep);
    frame->SendProcessMessage(PID_RENDERER,message);
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
    auto it = archiveProbes.find(tab);
    if (it != archiveProbes.end() && it->second.nonce == nonce) FinishArchiveProbe(tab,false);
  });
}

static void ReceiveIdleFrame(const std::string& tab, CefRefPtr<CefBrowser> browser,
                             CefRefPtr<CefFrame> frame, CefRefPtr<CefListValue> args) {
  auto it = archiveProbes.find(tab);
  if (it == archiveProbes.end() || !args || args->GetString(0).ToString() != it->second.nonce ||
      !frame || !it->second.frames.erase(frame->GetIdentifier().ToString())) return;
  auto& probe = it->second;
  int process = args->GetInt(2);
  if (process <= 0 || (probe.process && probe.process != process) || args->GetType(1) != VTYPE_BOOL ||
      !args->GetBool(1) || capturingTabs.count(tab) || audibleTabs.count(tab)) {
    FinishArchiveProbe(tab,false);
    return;
  }
  probe.process = process;
  if (!probe.frames.empty()) return;
  probe.rtc = new IdleAudioRtcCheck();
  const auto nonce = probe.nonce;
  const size_t frameCount = probe.frameCount;
  const std::string identifier = tab;
  probe.rtc->Start(browser, ^(BOOL clear) {
    auto active = archiveProbes.find(identifier);
    if (active != archiveProbes.end() && active->second.nonce == nonce)
      FinishArchiveProbe(identifier,clear && browser->IsValid() && !browser->IsLoading() &&
                          frameCount == browser->GetFrameCount() && !HasActiveDownload(browser));
  });
}
