// Chromium owns the video surface and playback controls. No media URL is
// extracted and no second player/browser is created (including blob streams).
#import <objc/runtime.h>
class NativePictureInPicture;
static CefRefPtr<NativePictureInPicture> nativePiP;

class NativePictureInPicture : public CefDevToolsMessageObserver {
 public:
  NativePictureInPicture(NSString *tab, bool automatic, void (^completion)(NSString*))
      : tab_([tab copy]), automatic_(automatic), completion_([completion copy]) {}
  NSString *tab() const { return tab_; }
  bool active() const { return active_; }
  void Start(CefRefPtr<CefBrowser> browser) {
    browser_ = browser;
    registration_ = browser->GetHost()->AddDevToolsMessageObserver(this);
    Send("Page.getFrameTree",nullptr,Phase::Frames);
    CefRefPtr<NativePictureInPicture> keep(this);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
      if (keep->completion_) keep->Stop(@"unavailable");
    });
  }
  void Close() {
    closing_ = true;
    if (active_) Exit(); // A pending entry is closed as soon as its reply arrives.
  }
  void Stop(NSString *result) {
    if (stopped_) return;
    stopped_ = true; active_ = false;
    BrowserTrace(@"pip.closed",@{@"tab":tab_,@"result":result});
    Complete(result);
    CefRefPtr<NativePictureInPicture> keep(this);
    dispatch_async(dispatch_get_main_queue(), ^{
      keep->registration_ = nullptr; keep->browser_ = nullptr;
      if (nativePiP.get() == keep.get()) nativePiP = nullptr;
    });
  }
  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser>) override { Stop(@"unavailable"); }
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>,int message,bool success,const void *bytes,size_t size) override {
    if (stopped_ || message != message_) return;
    NSDictionary *json = nil;
    if (success && bytes && size < 1024*1024) {
      id value = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:size] options:0 error:nil];
      if ([value isKindOfClass:NSDictionary.class]) json = value;
    }
    if (phase_ == Phase::Exit) { Stop(@"closed"); return; }
    if (phase_ == Phase::Frames) {
      CollectFrames(json[@"frameTree"]);
      NextFrame(); return;
    }
    if (phase_ == Phase::World) {
      context_ = [json[@"executionContextId"] intValue];
      if (!context_) { NextFrame(); return; }
      Evaluate(Probe(),Phase::Probe); return;
    }
    id remote = json[@"result"];
    id value = [remote isKindOfClass:NSDictionary.class] ? remote[@"value"] : nil;
    if (json[@"exceptionDetails"]) value = nil;
    if (phase_ == Phase::Probe) {
      if ([value isKindOfClass:NSDictionary.class]) {
        const bool existing = [value[@"active"] boolValue];
        const double score = [value[@"score"] doubleValue];
        if (existing || (!existing_ && score > best_score_)) {
          existing_ = existing; best_score_ = score; best_context_ = context_;
        }
      }
      NextFrame(); return;
    }
    if (phase_ == Phase::Enter) {
      if (![value isEqual:@"opened"]) { Stop(@"unavailable"); return; }
      active_ = true;
      BrowserTrace(@"pip.opened",@{@"tab":tab_,@"automatic":@(automatic_)});
      Complete(@"opened");
      if (closing_) Exit(); else PollLater();
      return;
    }
    if (phase_ == Phase::Poll) {
      if (![value isEqual:@YES]) { Stop(@"closed"); return; }
      if (closing_) Exit(); else PollLater();
    }
  }
 private:
  enum class Phase { Frames, World, Probe, Enter, Poll, Exit };
  void Send(const char *method,CefRefPtr<CefDictionaryValue> params,Phase phase) {
    if (stopped_ || !browser_ || !browser_->IsValid()) { Stop(@"unavailable"); return; }
    phase_ = phase;
    message_ = browser_->GetHost()->ExecuteDevToolsMethod(0,method,params);
    if (!message_) Stop(@"unavailable");
  }
  void Evaluate(const std::string& expression,Phase phase) {
    auto params = CefDictionaryValue::Create(); params->SetString("expression",expression);
    params->SetInt("contextId",context_); params->SetBool("returnByValue",true);
    params->SetBool("awaitPromise",true);
    // Entry only follows an explicit Browser action or the user's site preference.
    params->SetBool("userGesture",phase == Phase::Enter);
    Send("Runtime.evaluate",params,phase);
  }
  void CollectFrames(id tree) {
    if (![tree isKindOfClass:NSDictionary.class] || frames_.size() >= 64) return;
    id frame = tree[@"frame"];
    if (![frame isKindOfClass:NSDictionary.class]) return;
    id identifier = frame[@"id"];
    if ([identifier isKindOfClass:NSString.class]) frames_.push_back([identifier UTF8String]);
    id children = tree[@"childFrames"];
    if ([children isKindOfClass:NSArray.class]) for (id child in children) CollectFrames(child);
  }
  void NextFrame() {
    if (closing_) { Stop(@"cancelled"); return; }
    if (next_frame_ < frames_.size()) {
      auto params = CefDictionaryValue::Create(); params->SetString("frameId",frames_[next_frame_++]);
      params->SetString("worldName","Browser Picture in Picture");
      Send("Page.createIsolatedWorld",params,Phase::World); return;
    }
    if (!best_context_) { Stop(@"no-video"); return; }
    context_ = best_context_;
    if (existing_) {
      active_ = true;
      if (!automatic_) { Exit(); return; }
      Complete(@"existing"); PollLater(); return;
    }
    Evaluate(R"JS((async()=>{
      const v=globalThis.__browserPiPVideo?.deref();delete globalThis.__browserPiPVideo;
      if(!v||!v.isConnected||v.readyState<1) return 'unavailable';
      try { await v.requestPictureInPicture(); return 'opened'; }
      catch { return 'unavailable'; }
    })())JS",Phase::Enter);
  }
  std::string Probe() {
    return std::string(R"JS((()=>{
      if(document.pictureInPictureElement)return {active:true,score:1};
      if(!document.pictureInPictureEnabled)return null;
      const videos=[];const roots=[document];
      while(roots.length){const root=roots.pop();videos.push(...root.querySelectorAll('video'));
        for(const el of root.querySelectorAll('*'))if(el.shadowRoot)roots.push(el.shadowRoot);}
      let best=null,score=0;
      for(const v of videos){
        if(v.readyState<1||!v.videoWidth||v.ended||v.disablePictureInPicture)continue;
        if()JS") + (automatic_ ? "true" : "false") + R"JS( && (v.paused||v.muted||v.volume===0))continue;
        const r=v.getBoundingClientRect(),style=getComputedStyle(v);
        if(r.width<80||r.height<45||style.display==='none'||style.visibility==='hidden')continue;
        // Favor the main player over thumbnails and decorative video loops.
        const area=Math.min(r.width,innerWidth)*Math.min(r.height,innerHeight);
        const s=area*(v.paused?1:4)*(v.muted?1:2);
        if(s>score){score=s;best=v;}
      }
      globalThis.__browserPiPVideo=best?new WeakRef(best):null;
      return best?{active:false,score}:null;
    })())JS";
  }
  void Exit() {
    Evaluate("(async()=>{if(document.pictureInPictureElement)await document.exitPictureInPicture();return true})()",Phase::Exit);
  }
  void PollLater() {
    CefRefPtr<NativePictureInPicture> keep(this);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
      if (!keep->stopped_ && !keep->closing_) keep->Evaluate("!!document.pictureInPictureElement",Phase::Poll);
    });
  }
  void Complete(NSString *result) {
    auto completion = completion_; completion_ = nil;
    if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
  }
  NSString *tab_;
  bool automatic_, active_ = false, closing_ = false, stopped_ = false, existing_ = false;
  int message_ = 0, context_ = 0, best_context_ = 0;
  double best_score_ = 0;
  size_t next_frame_ = 0;
  std::vector<std::string> frames_;
  Phase phase_ = Phase::Frames;
  CefRefPtr<CefBrowser> browser_;
  CefRefPtr<CefRegistration> registration_;
  void (^completion_)(NSString*);
  IMPLEMENT_REFCOUNTING(NativePictureInPicture);
};

static void ForgetPictureInPicture(NSString *tab) {
  if (nativePiP && [nativePiP->tab() isEqual:tab]) nativePiP->Stop(@"closed");
}

static bool ReturnFromPictureInPicture(const std::string& key) {
  if (!nativePiP || ![nativePiP->tab() isEqual:@(key.c_str())]) return false;
  auto owner = nativeTabOwners.find(key);
  if (owner == nativeTabOwners.end()) return false;
  __weak BrowserEngine *engine = owner->second.engine;
  NSString *tab = @(key.c_str());
  BrowserTrace(@"pip.return-to-tab",@{@"tab":tab});
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([engine.delegate respondsToSelector:@selector(browserPictureInPictureReturn:)])
      [engine.delegate browserPictureInPictureReturn:tab];
  });
  return true;
}

static void InstallPictureInPictureReturnRouting(NSWindow *window, NSString *tab) {
  // The engine deliberately refuses canBecomeKeyWindow/orderWindow for its
  // invisible backend. Consequently CEF's activation delegate is never called.
  // Intercept the public AppKit activation request on this backend instance,
  // before that guard, and leave every other NSWindow (including PiP) untouched.
  SEL key = sel_registerName("browserPictureInPictureTab");
  objc_setAssociatedObject(window,key,tab,OBJC_ASSOCIATION_COPY_NONATOMIC);
  // Keep the object's isa intact: AppKit may already be observing this window
  // through KVO. Add a guarded override on CEF's class, never on NSWindow.
  Class hostClass = NSClassFromString(@"CefNSWindow");
  if (!hostClass || ![window isKindOfClass:hostClass]) return;
  static std::set<Class> installed;
  if (!installed.insert(hostClass).second) return;
  SEL selector = @selector(makeKeyAndOrderFront:);
  Method method = class_getInstanceMethod(hostClass,selector);
  IMP original = method_getImplementation(method);
  IMP routed = imp_implementationWithBlock(^(NSWindow *host,id sender) {
    NSString *source = objc_getAssociatedObject(host,key);
    if ([host.identifier isEqualToString:@"local.browser.backend"] && source &&
        ReturnFromPictureInPicture(source.UTF8String)) return;
    reinterpret_cast<void(*)(id,SEL,id)>(original)(host,selector,sender);
  });
  class_replaceMethod(hostClass,selector,routed,method_getTypeEncoding(method));
}
