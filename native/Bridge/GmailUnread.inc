// Gmail's inbox counter remains in the navigation rail while a conversation
// is open. Observe that counter without reading message rows or opening Gmail.
class GmailInboxSignal : public CefV8Handler {
 public:
  bool Execute(const CefString&, CefRefPtr<CefV8Value>, const CefV8ValueList& args,
               CefRefPtr<CefV8Value>&, CefString&) override {
    auto context = CefV8Context::GetCurrentContext();
    auto frame = context ? context->GetFrame() : nullptr;
    if (!frame || !frame->IsMain() || args.size() != 1 || !args[0]->IsBool()) return true;
    const auto document = frame->GetURL().ToString();
    if (document.rfind("https://mail.google.com/mail/", 0) != 0) return true;
    auto signal = CefProcessMessage::Create("ArcReborn.GmailInboxUnread");
    signal->GetArgumentList()->SetBool(0, args[0]->GetBoolValue());
    signal->GetArgumentList()->SetString(1, document.substr(0, document.find('#')));
    frame->SendProcessMessage(PID_BROWSER, signal);
    return true;
  }
 private:
  IMPLEMENT_REFCOUNTING(GmailInboxSignal);
};

static void ObserveGmailInbox(CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context> context) {
  if (!frame->IsMain() || frame->GetURL().ToString().rfind("https://mail.google.com/mail/", 0) != 0) return;
  static constexpr char script[] = R"JS((report => {
    let nav, last, mailbox, scheduled = false;
    function read() {
      const link = nav?.querySelector('a[href$="#inbox"]');
      if (!link || new URL(link.href).origin !== location.origin) return;
      const row = link.closest('.aio, .aim');
      const count = row?.querySelector('.bsU')?.textContent.trim();
      const label = link.getAttribute('aria-label') || '';
      const digits = count || label.match(/\d[\d.,\s]*\+?/)?.[0];
      if (!digits && !row && !/\b(unread|non lu)/i.test(label)) return;
      if (digits && !/^[\d.,\s]+\+?$/.test(digits)) return;
      const unread = /[1-9]/.test(digits || '');
      const currentMailbox = location.pathname + '?' + (new URLSearchParams(location.search).get('authuser') || '');
      if (unread !== last || mailbox !== currentMailbox) {
        last = unread; mailbox = currentMailbox; report(unread);
      }
    }
    const counter = new MutationObserver(read);
    function attach() {
      scheduled = false;
      if (nav?.isConnected) return;
      counter.disconnect();
      nav = Array.from(document.querySelectorAll('[role="navigation"]')).find(n => n.querySelector('a[href$="#inbox"]'));
      if (!nav) return;
      counter.observe(nav, {subtree:true, childList:true, characterData:true, attributes:true, attributeFilter:['aria-label','href']});
      read();
    }
    new MutationObserver(() => {
      if (!nav?.isConnected && !scheduled) { scheduled = true; setTimeout(attach, 100); }
    }).observe(document, {subtree:true, childList:true});
    attach();
  }))JS";
  CefRefPtr<CefV8Value> observer;
  CefRefPtr<CefV8Exception> error;
  if (context->Eval(script, "", 0, observer, error) && observer && observer->IsFunction()) {
    auto report = CefV8Value::CreateFunction("reportInboxState", new GmailInboxSignal());
    observer->ExecuteFunction(nullptr, {report});
  }
}
