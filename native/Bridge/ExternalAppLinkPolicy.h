// SPDX-License-Identifier: MPL-2.0
#import <Foundation/Foundation.h>

// Native application offers are limited to canonical HTTPS invitation URLs.
// Other Discord routes and lookalike hosts remain ordinary web pages.
static NSString *DiscordWebInviteCode(NSURLComponents *url) {
  if (!url || url.user || url.password || (url.port && url.port.intValue != 443) ||
      ![url.scheme.lowercaseString isEqualToString:@"https"]) return nil;
  NSString *host = url.host.lowercaseString;
  NSMutableArray<NSString *> *path = [NSMutableArray array];
  for (NSString *part in [url.percentEncodedPath componentsSeparatedByString:@"/"]) if (part.length) [path addObject:part];
  NSString *code = nil;
  if ([@[@"discord.gg",@"www.discord.gg"] containsObject:host] && path.count == 1) code = path[0];
  if ([@[@"discord.com",@"www.discord.com"] containsObject:host] && path.count == 2 &&
      [@[@"invite",@"invite-proxy"] containsObject:path[0]]) code = path[1];
  NSCharacterSet *valid = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
  return code.length && code.length <= 128 && [code rangeOfCharacterFromSet:valid.invertedSet].location == NSNotFound ? code : nil;
}
