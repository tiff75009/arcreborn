// SPDX-License-Identifier: MPL-2.0
#import "../Bridge/TestKeychainPolicy.h"
#include <cassert>

int main() {
  @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *test = [root stringByAppendingPathComponent:@"test"];
    NSString *personal = [root stringByAppendingPathComponent:@"personal"];
    NSString *cache = [test stringByAppendingPathComponent:@"Chromium"];
    [fm createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:personal withIntermediateDirectories:YES attributes:nil error:nil];
    assert(BrowserMockKeychainCache(cache, test, personal) != nil);
    assert(BrowserMockKeychainCache(cache, @"", personal) == nil);
    assert(BrowserMockKeychainCache(personal, personal, personal) == nil);
    assert(BrowserMockKeychainCache([personal stringByAppendingPathComponent:@"Chromium"], personal, personal) == nil);
    assert(BrowserMockKeychainCache(cache, root, personal) == nil);
    assert(BrowserMockKeychainCache(cache, @"/", personal) == nil);
    assert(BrowserMockKeychainCache([root stringByAppendingPathComponent:@"test-sibling/Chromium"], test, personal) == nil);
    NSString *alias = [test stringByAppendingPathComponent:@"alias"];
    [fm createSymbolicLinkAtPath:alias withDestinationPath:personal error:nil];
    assert(BrowserMockKeychainCache(alias, test, personal) == nil);
    [fm createSymbolicLinkAtPath:[cache stringByAppendingPathComponent:@"MockKeychain"] withDestinationPath:personal error:nil];
    assert(BrowserMockKeychainCache(cache, test, personal) == nil);
    [fm removeItemAtPath:root error:nil];
    puts("PASS: 9 test keychain isolation checks");
  }
}
