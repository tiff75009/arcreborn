// SPDX-License-Identifier: MPL-2.0
#include "include/cef_app.h"
#include "include/cef_sandbox_mac.h"
#include "include/wrapper/cef_library_loader.h"
#include "CdmProcess.h"

#ifndef CEF_USE_SANDBOX
#error The CDM helper requires the CEF sandbox.
#endif

int main(int argc, char* argv[]) {
  // The library constraint in this helper's signature is enforced from Sonoma.
  if (__builtin_available(macOS 14.0, *)) {
    CefScopedSandboxContext sandbox;
    if (!sandbox.Initialize(argc, argv)) return 1;
    CefScopedLibraryLoader loader;
    if (!loader.LoadInHelper()) return 1;
    auto command = CefCommandLine::CreateCommandLine();
    command->InitFromArgv(argc, argv);
    if (!IsCdmBrokerProcess(command)) return 1;
    return CefExecuteProcess(CefMainArgs(argc, argv), nullptr, nullptr);
  }
  return 1;
}
