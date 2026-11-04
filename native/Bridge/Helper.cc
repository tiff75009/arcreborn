// Based on the BSD-licensed CEF tests/cefsimple/process_helper_mac.cc.
// Copyright (c) 2013 The Chromium Embedded Framework Authors.
#include "include/cef_app.h"
#include "include/cef_sandbox_mac.h"
#include "include/wrapper/cef_library_loader.h"

#ifndef CEF_USE_SANDBOX
#error Browser helpers must be built with the CEF sandbox enabled.
#endif

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
  return CefExecuteProcess(main_args, nullptr, nullptr);
}
