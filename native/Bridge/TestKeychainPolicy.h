// SPDX-License-Identifier: MPL-2.0
#import <Foundation/Foundation.h>

// Test encryption must never use, contain, or alias the everyday profile.
static NSString *BrowserMockKeychainCache(NSString *cache, NSString *testRoot,
                                        NSString *personalRoot) {
  if (!cache.length || !testRoot.length || !personalRoot.length) return nil;
  NSString *(^canonical)(NSString *) = ^NSString *(NSString *path) {
    return path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
  };
  BOOL (^within)(NSString *, NSString *) = ^BOOL(NSString *path, NSString *root) {
    return [path isEqualToString:root] ||
        [path hasPrefix:[root isEqualToString:@"/"] ? @"/" : [root stringByAppendingString:@"/"]];
  };
  testRoot = canonical(testRoot); personalRoot = canonical(personalRoot);
  cache = canonical(cache);
  if (!testRoot.isAbsolutePath || !within(cache, testRoot) ||
      within(testRoot, personalRoot) || within(personalRoot, testRoot) ||
      within(cache, personalRoot)) return nil;
  NSString *mock = canonical([cache stringByAppendingPathComponent:@"MockKeychain"]);
  if (!within(mock, testRoot) || within(mock, personalRoot)) return nil;
  return mock;
}
