// SPDX-License-Identifier: MPL-2.0
// Keep local document navigation separate from web popups, authentication,
// favicons and external protocols.
static NSURL *LocalDocument(NSString *address) {
  if (![address hasPrefix:@"file:///"] || [address lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 32768) return nil;
  NSURLComponents *u = [NSURLComponents componentsWithString:address];
  if (u.host.length || u.user || u.password || u.port || ![u.path hasPrefix:@"/"] || [u.path hasPrefix:@"//"] ||
      [u.percentEncodedPath containsString:@"%00"] || ![@[@"html", @"htm", @"pdf", @"svg"] containsObject:u.URL.pathExtension.lowercaseString]) return nil;
  u.query = nil;
  u.fragment = nil;
  return u.URL;
}

// A native request is bound to one renderer until its file commits.
static std::map<std::string, std::string> requestedLocalDocuments;
static void ExpectTabAddress(NSString *key, NSString *address) {
  NSURL *file = LocalDocument(address);
  if (file) requestedLocalDocuments[key.UTF8String] = file.path.UTF8String;
  else requestedLocalDocuments.erase(key.UTF8String);
}
