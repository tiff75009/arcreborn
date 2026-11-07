// Public Apple Translation UI is owned by Swift. Only the document explicitly
// chosen by the user is read/written, in a private execution context in CEF.
static id<BrowserTranslationPresenter> TranslationPresenter() {
  id delegate = NSApp.delegate;
  return [delegate conformsToProtocol:@protocol(BrowserTranslationPresenter)] ? delegate : nil;
}

class PageTranslationJob : public CefDevToolsMessageObserver {
 public:
  explicit PageTranslationJob(NSString *tab) : tab_([tab copy]), token_(NSUUID.UUID.UUIDString), pending_([NSMutableArray array]) {}
  void Start(CefRefPtr<CefBrowser> browser) {
    browser_ = browser;
    registration_ = browser->GetHost()->AddDevToolsMessageObserver(this);
    Send("Page.getFrameTree",nullptr,Stage::Frame);
  }
  bool canRestore() const {
    return !ended_ && (stage_ == Stage::Translating || stage_ == Stage::Apply || stage_ == Stage::Translated);
  }
  void Restore() {
    if (!canRestore()) return;
    stage_ = Stage::Restore;
    [TranslationPresenter() cancelInlineTranslation:tab_];
    [pending_ removeAllObjects];
    // CDP executes this after any patch already sent to this document.
    Eval(@"restore",nil,Stage::Restore);
  }
  void End();
  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser>) override { End(); }
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>,int msg,bool success,const void *bytes,size_t size) override {
    if (ended_ || msg != message_) return;
    CefRefPtr<PageTranslationJob> keep(this);
    NSDictionary *json = nil;
    if (success && bytes && size < 8*1024*1024) {
      id decoded = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:size] options:0 error:nil];
      if ([decoded isKindOfClass:NSDictionary.class]) json = decoded;
    }
    if (!json || json[@"exceptionDetails"]) { Fail(); return; }
    if (stage_ == Stage::Frame) {
      NSString *frame = json[@"frameTree"][@"frame"][@"id"]; if (!frame.length) { Fail(); return; }
      auto params = CefDictionaryValue::Create(); params->SetString("frameId",CefStr(frame));
      params->SetString("worldName","ArcReborn Page Translation");
      Send("Page.createIsolatedWorld",params,Stage::World); return;
    }
    if (stage_ == Stage::World) {
      context_ = [json[@"executionContextId"] intValue];
      if (!context_) { Fail(); return; }
      Eval(@"collect",nil,Stage::Collect); return;
    }
    id value = json[@"result"][@"value"];
    if (stage_ == Stage::Collect) {
      NSArray *texts = [value isKindOfClass:NSDictionary.class] ? value[@"strings"] : nil;
      if (![texts isKindOfClass:NSArray.class] || !texts.count) {
        NSString *error = [value isKindOfClass:NSDictionary.class] ? value[@"error"] : nil;
        Fail(error); return;
      }
      stage_ = Stage::Translating;
      NSView *view = VisibleChromePage(tab_);
      if (!view || !TranslationPresenter()) { Restore(); return; }
      [TranslationPresenter() translatePageStrings:texts hint:value[@"lang"] ?: @"" owner:tab_ inView:view
        update:^(NSInteger index, NSString *translated) {
          if (!keep->acceptingResults()) return;
          [keep->pending_ addObject:@[@(index),translated]];
          keep->SchedulePaint();
        } completion:^(NSString *error) {
          if (!keep->acceptingResults()) return;
          if (error) { keep->NotifyReader(error); keep->Restore(); return; }
          keep->receivedAll_ = true;
          keep->SchedulePaint();
        }];
    } else if (stage_ == Stage::Apply) {
      if (![value isEqual:@YES]) { Fail(); return; }
      stage_ = Stage::Translating;
      SchedulePaint();
    } else End();
  }
 private:
  enum class Stage { Frame,World,Collect,Translating,Apply,Translated,Restore };
  bool acceptingResults() const { return !ended_ && (stage_ == Stage::Translating || stage_ == Stage::Apply); }
  void SchedulePaint() {
    if (stage_ != Stage::Translating || paintScheduled_) return;
    if (!pending_.count) {
      if (receivedAll_) stage_ = Stage::Translated;
      return;
    }
    // Coalesce Apple responses while the last renderer edit is in flight.
    // Never wait for translation of the rest of the document to start painting.
    paintScheduled_ = true;
    CefRefPtr<PageTranslationJob> keep(this);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,16*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
      keep->paintScheduled_ = false;
      if (keep->ended_ || keep->stage_ != Stage::Translating) return;
      NSArray *batch = [keep->pending_ copy];
      [keep->pending_ removeAllObjects];
      keep->Eval(@"apply",batch,Stage::Apply);
    });
  }
  void NotifyReader(NSString *message) {
    NSWindow *window = VisibleChromePage(tab_).window;
    if (!quitting && window) [TranslationPresenter() showTranslationNotice:message inWindow:window];
  }
  void Fail(NSString *reason = nil) {
    if (ended_) return;
    NSString *message = [reason isEqual:@"limit"] ? L(@"Cette page est trop longue. Sélectionnez un passage à traduire.",@"This page is too long. Select a passage to translate.")
        : [reason isEqual:@"empty"] ? L(@"Aucun texte à traduire sur cette page.",@"There is no text to translate on this page.")
        : L(@"La traduction de cette page est indisponible.",@"Translation is unavailable for this page.");
    NotifyReader(message);
    if (canRestore()) Restore();
    else End();
  }
  void Send(const char *method,CefRefPtr<CefDictionaryValue> params,Stage next) {
    if (ended_ || !browser_ || !browser_->IsValid()) { End(); return; }
    stage_ = next; message_ = browser_->GetHost()->ExecuteDevToolsMethod(0,method,params);
    if (!message_) { Fail(); return; }
    const int pending = message_;
    CefRefPtr<PageTranslationJob> keep(this);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_main_queue(),^{
      if (!keep->ended_ && keep->message_ == pending && keep->stage_ == next) keep->Fail();
    });
  }
  void Eval(NSString *mode,NSArray *values,Stage next) {
    static NSString *script = [NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"PageTranslation" withExtension:@"js"] encoding:NSUTF8StringEncoding error:nil];
    if (!script.length) { Fail(); return; }
    NSArray *args = @[mode,token_,values ?: NSNull.null];
    NSData *data = [NSJSONSerialization dataWithJSONObject:args options:0 error:nil];
    if (!data) { Fail(); return; }
    NSString *expression = [NSString stringWithFormat:@"(%@)(...%@)",script,[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
    auto params = CefDictionaryValue::Create(); params->SetInt("contextId",context_);
    params->SetBool("returnByValue",true); params->SetString("expression",CefStr(expression));
    Send("Runtime.evaluate",params,next);
  }
  NSString *tab_, *token_;
  NSMutableArray *pending_;
  bool paintScheduled_ = false, receivedAll_ = false;
  CefRefPtr<CefBrowser> browser_; CefRefPtr<CefRegistration> registration_;
  int message_ = 0, context_ = 0; Stage stage_ = Stage::Frame; bool ended_ = false;
  IMPLEMENT_REFCOUNTING(PageTranslationJob);
};
static std::map<std::string,CefRefPtr<PageTranslationJob>> pageTranslations;
void PageTranslationJob::End() {
  if (ended_) return;
  CefRefPtr<PageTranslationJob> keep(this);
  ended_ = true;
  [TranslationPresenter() cancelInlineTranslation:tab_];
  auto it = pageTranslations.find(tab_.UTF8String);
  if (it != pageTranslations.end() && it->second.get() == this) pageTranslations.erase(it);
  dispatch_async(dispatch_get_main_queue(),^{ keep->registration_ = nullptr; keep->browser_ = nullptr; });
}
static void ForgetPageTranslation(NSString *key) {
  auto it = pageTranslations.find(key.UTF8String);
  if (it != pageTranslations.end()) it->second->End();
  [TranslationPresenter() dismissTranslationForOwner:key];
}
