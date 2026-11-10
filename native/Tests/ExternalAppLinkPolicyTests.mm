// SPDX-License-Identifier: MPL-2.0
#include "../Bridge/ExternalAppLinkPolicy.h"
#include <cassert>
#include <cstdio>

int main() {
  @autoreleasepool {
    for (NSString *source in @[@"https://discord.gg/Test_Code-123",@"https://discord.com/invite/Test_Code-123",
         @"https://www.discord.com:443/invite/Test_Code-123?event=1",@"https://discord.com/invite-proxy/Test_Code-123"])
      assert([DiscordWebInviteCode([NSURLComponents componentsWithString:source]) isEqualToString:@"Test_Code-123"]);
    assert([DiscordWebInviteCode([NSURLComponents componentsWithString:@"https://discord.gg/gca"]) isEqualToString:@"gca"]);
    for (NSString *source in @[@"http://discord.com/invite/Test_Code-123",
         @"https://discord.com.example.org/invite/Test_Code-123",@"https://example.org/invite/Test_Code-123",
         @"https://discord.com@evil.example/invite/Test_Code-123",@"https://user@discord.com/invite/Test_Code-123",
         @"https://discord.com:444/invite/Test_Code-123",@"https://discord.com/channels/Test_Code-123",
         @"https://discord.com/invite/Test_Code-123/other",@"https://discord.com/invite/Test%2FCode",
         @"https://discord.gg/Test_Code-123/other",@"https://discord.com/invite/",@"file:///invite/gca",
         @"javascript:alert(1)",@"discord:///invite-proxy/gca"])
      assert(DiscordWebInviteCode([NSURLComponents componentsWithString:source]) == nil);
    puts("PASS: canonical Discord HTTPS invitations, exact codes, credentials, ports, lookalikes and unrelated routes");
  }
}
