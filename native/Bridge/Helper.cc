// Based on the BSD-licensed CEF tests/cefsimple/process_helper_mac.cc.
// Copyright (c) 2013 The Chromium Embedded Framework Authors.
#include "include/cef_app.h"
#include "include/cef_sandbox_mac.h"
#include "include/wrapper/cef_library_loader.h"

#ifndef CEF_USE_SANDBOX
#error Browser helpers must be built with the CEF sandbox enabled.
#endif

#include <map>
#include <unistd.h>
#include "GmailUnread.inc"
#include "IdleDocument.inc"

// For archive probes, only an idle flag leaves the frame. A failed probe
// never authorizes closing a page.
class ArchiveRenderer : public CefApp, public CefRenderProcessHandler {
 public:
  CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override { return this; }
  void OnContextCreated(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
                        CefRefPtr<CefV8Context> context) override {
    // CEF also calls this hook for extension worlds. Only the page's own
    // context should install listeners and answer probes about its document.
    auto page = frame->GetV8Context();
    if (!page || !context->IsSame(page)) return;
    ObserveGmailInbox(frame, context);
    CefRefPtr<CefV8Value> check;
    CefRefPtr<CefV8Exception> error;
    if (context->Eval(kObserveEdits, "", 0, check, error) && check && check->IsFunction())
      documents_[frame->GetIdentifier().ToString()] = {context, check};
  }
  void OnContextReleased(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
                         CefRefPtr<CefV8Context> context) override {
    auto it = documents_.find(frame->GetIdentifier().ToString());
    if (it != documents_.end() && it->second.first->IsSame(context)) documents_.erase(it);
  }
  bool OnProcessMessageReceived(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
      CefProcessId source, CefRefPtr<CefProcessMessage> message) override {
    if (source != PID_BROWSER || message->GetName() != "ArcReborn.ProbeIdleFrame") return false;
    bool idle = false;
    auto context = frame->GetV8Context();
    auto it = documents_.find(frame->GetIdentifier().ToString());
    if (context && it != documents_.end() && it->second.first->IsSame(context) && context->Enter()) {
      auto result = it->second.second->ExecuteFunction(nullptr, {CefV8Value::CreateBool(message->GetArgumentList()->GetBool(1))});
      idle = result && result->IsBool() && result->GetBoolValue();
      context->Exit();
    }
    auto reply = CefProcessMessage::Create("ArcReborn.IdleFrameResult");
    reply->GetArgumentList()->SetString(0,message->GetArgumentList()->GetString(0));
    reply->GetArgumentList()->SetBool(1,idle);
    reply->GetArgumentList()->SetInt(2, getpid());
    frame->SendProcessMessage(PID_BROWSER,reply);
    return true;
  }
 private:
  std::map<std::string, std::pair<CefRefPtr<CefV8Context>, CefRefPtr<CefV8Value>>> documents_;
  IMPLEMENT_REFCOUNTING(ArchiveRenderer);
};

int main(int argc, char* argv[]) {
  CefScopedSandboxContext sandbox_context;
  if (!sandbox_context.Initialize(argc, argv)) {
    return 1;
  }
  CefScopedLibraryLoader library_loader;
  if (!library_loader.LoadInHelper()) {
    return 1;
  }
  CefMainArgs main_args(argc, argv);
  return CefExecuteProcess(main_args, new ArchiveRenderer(), nullptr);
}
