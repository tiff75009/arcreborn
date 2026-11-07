// SPDX-License-Identifier: MPL-2.0
#pragma once
#include "include/cef_command_line.h"

inline bool IsCdmBrokerProcess(CefRefPtr<CefCommandLine> command) {
  return command->GetSwitchValue("type") == "utility" &&
         command->GetSwitchValue("utility-sub-type") == "media.mojom.CdmServiceBroker" &&
         command->GetSwitchValue("service-sandbox-type") == "cdm" &&
         !command->HasSwitch("no-sandbox");
}
