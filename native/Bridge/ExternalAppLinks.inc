// SPDX-License-Identifier: MPL-2.0
// A handoff is a one-time action attached to a visible document. External URLs
// never become browser addresses, popup tabs, or entries in the session.
static NSString *ExternalAppScheme(NSString *address) {
  NSRange colon = [address rangeOfString:@":"];
  if (colon.location == NSNotFound || colon.location < 2 || colon.location > 128) return nil;
  NSString *scheme = [address substringToIndex:colon.location].lowercaseString;
  static NSSet<NSString *> *reserved = [NSSet setWithArray:@[
    @"http", @"https", @"about", @"blob", @"data", @"javascript", @"file", @"filesystem",
    @"chrome", @"devtools", @"view-source", @"ws", @"wss", @"ftp", @"urn",
    @"afp", @"applescript", @"disk", @"disks", @"hcp", @"ie.http", @"mk",
    @"ms-help", @"nntp", @"res", @"shell", @"vbscript", @"vnd.ms.radio",
    @"smb", @"nfs", @"sftp", @"ssh", @"telnet", @"vnc", @"jar", @"resource"
  ]];
  if ([reserved containsObject:scheme] || [scheme hasPrefix:@"chrome-"] || [scheme hasPrefix:@"local+"] ||
      [scheme hasPrefix:@"x-apple"] || [scheme hasPrefix:@"x-webkit"] || [scheme hasPrefix:@"webkit-"]) return nil;
  return scheme;
}

static bool DeclaresExternalScheme(NSBundle *bundle, NSString *scheme) {
  NSArray *types = [bundle objectForInfoDictionaryKey:@"CFBundleURLTypes"];
  if (![types isKindOfClass:NSArray.class]) return false;
  for (NSDictionary *type in types) {
    if (![type isKindOfClass:NSDictionary.class]) continue;
    NSArray *schemes = type[@"CFBundleURLSchemes"];
    if (![schemes isKindOfClass:NSArray.class]) continue;
    for (NSString *declared in schemes) {
      if ([declared isKindOfClass:NSString.class] && [declared caseInsensitiveCompare:scheme] == NSOrderedSame) return true;
    }
  }
  return false;
}

static std::map<std::string, NSWindow *> externalAppSheets;
static void DismissExternalAppSheet(const std::string& tab) {
  auto found = externalAppSheets.find(tab);
  if (found == externalAppSheets.end()) return;
  NSWindow *sheet = found->second;
  externalAppSheets.erase(found);
  [sheet.sheetParent endSheet:sheet returnCode:NSModalResponseCancel];
}

static void AskToOpenExternalApp(CefRefPtr<CefBrowser> browser, NSString *tabID, NSView *page, NSString *address, NSString *scheme) {
  CEF_REQUIRE_UI_THREAD();
  NSWindow *parent = page.window;
  if (!parent.isKeyWindow || !parent.isVisible || parent.attachedSheet || page.hiddenOrHasHiddenAncestor ||
      [address lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 32768 ||
      [address rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound ||
      [address rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound ||
      [address containsString:@"\\"] || [address containsString:@"%00"]) return;
  NSURL *url = [NSURL URLWithString:address];
  auto main = browser->GetMainFrame();
  if (![url.scheme.lowercaseString isEqualToString:scheme] || !main) return;
  NSString *source = Str(main->GetURL());
  NSURLComponents *origin = [NSURLComponents componentsWithString:source];
  bool local = LocalDocument(source) != nil;
  if (!local && (![@[@"http",@"https"] containsObject:origin.scheme.lowercaseString] || !origin.host.length)) return;

  NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
  NSURL *app = [workspace URLForApplicationToOpenURL:url];
  NSBundle *bundle = app ? [NSBundle bundleWithURL:app] : nil;
  // Hand Web links only to apps which explicitly register this scheme. macOS
  // system helpers also register administrative protocols unrelated to web links.
  if (app && (!DeclaresExternalScheme(bundle, scheme) || [bundle.bundleIdentifier isEqual:NSBundle.mainBundle.bundleIdentifier] ||
      ([bundle.bundleIdentifier hasPrefix:@"com.apple."] &&
       ![@[@"mailto",@"tel",@"sms",@"facetime",@"facetime-audio",@"maps",@"webcal",@"itms-apps",@"itms"] containsObject:scheme]))) return;
  NSAlert *alert = [NSAlert new];
  NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"] ?: app.lastPathComponent.stringByDeletingPathExtension;
  if (app) {
    alert.messageText = [NSString stringWithFormat:L(@"Ouvrir %@ ?", @"Open %@?"),name];
    alert.informativeText = local ? L(@"Ce fichier contient un lien vers cette application.", @"This file contains a link to this application.") :
        [NSString stringWithFormat:L(@"La page sur %@ contient un lien vers cette application.", @"The page on %@ contains a link to this application."),origin.host];
    alert.icon = [workspace iconForFile:app.path];
    [alert addButtonWithTitle:L(@"Annuler",@"Cancel")];
    [alert addButtonWithTitle:[NSString stringWithFormat:L(@"Ouvrir %@", @"Open %@"),name]];
  } else {
    alert.messageText = L(@"Aucune application disponible", @"No application available");
    if ([scheme isEqualToString:@"zoommtg"] || [scheme isEqualToString:@"zoomus"])
      alert.informativeText = L(@"Aucune application sur ce Mac ne peut ouvrir ce lien Zoom.", @"No app on this Mac can open this Zoom link.");
    else if ([scheme isEqualToString:@"mailto"])
      alert.informativeText = L(@"Choisissez un client de messagerie par défaut sur ce Mac pour ouvrir ce lien.", @"Choose a default email app on this Mac to open this link.");
    else
      alert.informativeText = [NSString stringWithFormat:L(@"Aucune application sur ce Mac ne prend en charge les liens « %@: ».", @"No app on this Mac handles “%@:” links."),scheme];
    [alert addButtonWithTitle:@"OK"];
  }
  const std::string key = tabID.UTF8String;
  NSWindow *sheet = alert.window;
  externalAppSheets[key] = sheet;
  [alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
    auto found = externalAppSheets.find(key);
    if (found == externalAppSheets.end() || found->second != sheet) return;
    externalAppSheets.erase(found);
    if (!app || response != NSAlertSecondButtonReturn || quitting || !browser->IsValid() ||
        !browser->GetMainFrame() || ![Str(browser->GetMainFrame()->GetURL()) isEqual:source] ||
        page.window != parent || page.hiddenOrHasHiddenAncestor || !parent.isVisible) return;
    [workspace openURLs:@[url] withApplicationAtURL:app configuration:[NSWorkspaceOpenConfiguration configuration]
      completionHandler:^(NSRunningApplication *opened, NSError *error) {
        if (error) dispatch_async(dispatch_get_main_queue(), ^{
          if (!quitting && page.window == parent && parent.isVisible && !parent.attachedSheet)
            [[NSAlert alertWithError:error] beginSheetModalForWindow:parent completionHandler:nil];
        });
      }];
  }];
}
