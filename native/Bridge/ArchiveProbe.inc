// SPDX-License-Identifier: MPL-2.0
// Ask every renderer, including cross-origin frames. Lack of a reply never
// authorizes closing a live page. There is no polling until the tab is overdue.
struct ArchiveProbe {
  std::string nonce;
  std::set<std::string> frames;
  void (^reply)(BOOL);
};
static std::map<std::string,ArchiveProbe> archiveProbes;
static std::set<std::string> capturingTabs, automaticallyClosing;
static std::set<std::string> audibleTabs;
static void FinishArchiveProbe(const std::string& tab, bool idle) {
  auto it = archiveProbes.find(tab); if (it == archiveProbes.end()) return;
  auto reply = it->second.reply;
  archiveProbes.erase(it);
  dispatch_async(dispatch_get_main_queue(), ^{ reply(idle); });
}
static void CheckArchiveMedia(NSString* key, void (^reply)(BOOL)) {
  std::string tab = key.UTF8String;
  auto it = browsers.find(tab);
  if (quitting || it == browsers.end() || !it->second->IsValid() || it->second->IsLoading()
      || capturingTabs.count(tab) || audibleTabs.count(tab) || archiveProbes.count(tab)) { reply(NO); return; }
  std::vector<CefString> ids; it->second->GetFrameIdentifiers(ids);
  if (ids.empty() || ids.size() > 128) { reply(NO); return; }
  std::string nonce = NSUUID.UUID.UUIDString.UTF8String;
  ArchiveProbe probe{nonce,{},[reply copy]};
  for (const auto& id : ids) probe.frames.insert(id.ToString());
  archiveProbes.emplace(tab,std::move(probe));
  for (const auto& id : ids) {
    auto frame = it->second->GetFrameByIdentifier(id);
    if (!frame || !frame->IsValid()) { FinishArchiveProbe(tab,false); return; }
    auto message = CefProcessMessage::Create("ArcReborn.ProbeIdleFrame");
    message->GetArgumentList()->SetString(0,nonce);
    frame->SendProcessMessage(PID_RENDERER,message);
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
    auto it = archiveProbes.find(tab);
    if (it != archiveProbes.end() && it->second.nonce == nonce) FinishArchiveProbe(tab,false);
  });
}
