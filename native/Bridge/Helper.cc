// Based on the BSD-licensed CEF tests/cefsimple/process_helper_mac.cc.
// Copyright (c) 2013 The Chromium Embedded Framework Authors.
#include "include/cef_app.h"
#include "include/cef_sandbox_mac.h"
#include "include/wrapper/cef_library_loader.h"

#ifndef CEF_USE_SANDBOX
#error Browser helpers must be built with the CEF sandbox enabled.
#endif

// Only a boolean leaves the frame. Never expose a JS binding or inspect the URL,
// text, stream, or media source. In particular a failed probe is not "idle".
class ArchiveRenderer : public CefApp, public CefRenderProcessHandler {
 public:
  CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override { return this; }
  bool OnProcessMessageReceived(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
      CefProcessId source, CefRefPtr<CefProcessMessage> message) override {
    if (source != PID_BROWSER || message->GetName() != "ArcReborn.ProbeIdleFrame") return false;
    bool idle = false;
    auto context = frame->GetV8Context();
    if (context && context->Enter()) {
      CefRefPtr<CefV8Value> result;
      CefRefPtr<CefV8Exception> error;
      // A buffering player may still be playing even without audible output.
      const char* probe = R"JS((()=>{
        if (document.pictureInPictureElement || navigator.mediaSession?.playbackState === 'playing') return false;
        const roots=[document]; let work=0;
        while(roots.length) {
          const root=roots.pop();
          for(const media of root.querySelectorAll('audio,video'))
            if(!media.paused && !media.ended) return false;
          const nodes=document.createTreeWalker(root,NodeFilter.SHOW_ELEMENT);
          while(nodes.nextNode()) {
            if(++work>45000) return false;
            if(nodes.currentNode.shadowRoot) roots.push(nodes.currentNode.shadowRoot);
          }
        }
        return true;
      })())JS";
      idle = context->Eval(probe,"",0,result,error) && result && result->IsBool() && result->GetBoolValue();
      context->Exit();
    }
    auto reply = CefProcessMessage::Create("ArcReborn.IdleFrameResult");
    reply->GetArgumentList()->SetString(0,message->GetArgumentList()->GetString(0));
    reply->GetArgumentList()->SetBool(1,idle);
    frame->SendProcessMessage(PID_BROWSER,reply);
    return true;
  }
 private:
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
