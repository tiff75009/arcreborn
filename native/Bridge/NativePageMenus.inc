// Chromium's WebContents lives in the AppKit document, while its Views widget
// is hidden. Present the original CEF menu model in the visible document rather
// than asking the hidden widget to track a menu in the wrong window.
@interface BrowserPageMenuTarget : NSObject
@property(nonatomic) NSInteger command;
@property(nonatomic) cef_event_flags_t flags;
- (void)choose:(NSMenuItem *)item;
@end
@implementation BrowserPageMenuTarget
- (instancetype)init {
  if ((self = [super init])) _command = -1;
  return self;
}
- (void)choose:(NSMenuItem *)item {
  self.command = item.tag;
  NSEventModifierFlags modifiers = NSApp.currentEvent.modifierFlags;
  int flags = EVENTFLAG_NONE;
  if (modifiers & NSEventModifierFlagShift) flags |= EVENTFLAG_SHIFT_DOWN;
  if (modifiers & NSEventModifierFlagControl) flags |= EVENTFLAG_CONTROL_DOWN;
  if (modifiers & NSEventModifierFlagOption) flags |= EVENTFLAG_ALT_DOWN;
  if (modifiers & NSEventModifierFlagCommand) flags |= EVENTFLAG_COMMAND_DOWN;
  self.flags = static_cast<cef_event_flags_t>(flags);
}
@end

static NSMenu *CopyNativePageMenu(CefRefPtr<CefMenuModel> model, BrowserPageMenuTarget *target) {
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
  menu.autoenablesItems = NO;
  for (size_t index = 0; index < model->GetCount(); ++index) {
    if (!model->IsVisibleAt(index)) continue;
    auto type = model->GetTypeAt(index);
    if (type == MENUITEMTYPE_SEPARATOR) { [menu addItem:NSMenuItem.separatorItem]; continue; }
    // CEF labels use ampersands for keyboard mnemonics. AppKit handles menu
    // navigation itself; retain literal escaped ampersands, remove markers.
    NSString *label = Str(model->GetLabelAt(index));
    NSMutableString *title = [NSMutableString string];
    for (NSUInteger i = 0; i < label.length; ++i) {
      unichar character = [label characterAtIndex:i];
      if (character == '&') {
        if (i + 1 >= label.length || [label characterAtIndex:i + 1] != '&') continue;
        ++i;
      }
      [title appendFormat:@"%C", character];
    }
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                action:@selector(choose:) keyEquivalent:@""];
    item.tag = model->GetCommandIdAt(index);
    item.target = target;
    item.enabled = model->IsEnabledAt(index);
    if (type == MENUITEMTYPE_CHECK || type == MENUITEMTYPE_RADIO)
      item.state = model->IsCheckedAt(index) ? NSControlStateValueOn : NSControlStateValueOff;
    if (type == MENUITEMTYPE_SUBMENU) {
      if (auto submenu = model->GetSubMenuAt(index)) item.submenu = CopyNativePageMenu(submenu, target);
    }
    [menu addItem:item];
  }
  return menu;
}

static bool RunNativePageMenu(NSString *key, CefRefPtr<CefContextMenuParams> params,
                              CefRefPtr<CefMenuModel> model, CefRefPtr<CefRunContextMenuCallback> callback) {
  auto found = chromeTabs.find(key.UTF8String);
  NSView *view = found == chromeTabs.end() ? nil : found->second.content;
  if (quitting || !view.window || view.hiddenOrHasHiddenAncestor) { callback->Cancel(); return true; }
  BrowserPageMenuTarget *target = [[BrowserPageMenuTarget alloc] init];
  NSMenu *menu = CopyNativePageMenu(model, target);
  NSString *selection = Str(params->GetSelectionText());
  const bool hasSelection = [selection stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
  NSString *documentURL = Str(params->GetPageUrl());
  NSString *scheme = [NSURL URLWithString:documentURL].scheme.lowercaseString;
  const bool web = [scheme isEqual:@"https"] || [scheme isEqual:@"http"] || [scheme isEqual:@"file"];
  if (@available(macOS 15.0, *)) {
    if (web && TranslationPresenter() && (!params->IsEditable() || (hasSelection && (params->GetEditStateFlags() & CM_EDITFLAG_CAN_COPY)))) {
      for (NSMenuItem *item in [menu.itemArray copy]) {
        if (item.tag >= 0 && (item.tag == cef_id_for_command_id_name("IDC_CONTENT_CONTEXT_TRANSLATE") ||
                              item.tag == cef_id_for_command_id_name("IDC_CONTENT_CONTEXT_PARTIAL_TRANSLATE"))) [menu removeItem:item];
      }
      auto existing = pageTranslations.find(key.UTF8String);
      const bool restore = !hasSelection && existing != pageTranslations.end() && existing->second->applied();
      NSString *label = hasSelection ? L(@"Traduire la sélection…",@"Translate Selection…")
                             : restore ? L(@"Afficher l’original",@"Show Original")
                                       : L(@"Traduire la page…",@"Translate Page…");
      if (menu.numberOfItems && ![menu itemAtIndex:0].isSeparatorItem) [menu insertItem:NSMenuItem.separatorItem atIndex:0];
      NSMenuItem *action = [menu insertItemWithTitle:label action:@selector(choose:) keyEquivalent:@"" atIndex:0];
      action.target = target; action.tag = restore ? -3 : -2;
      action.enabled = hasSelection || restore || existing == pageTranslations.end();
      action.image = [NSImage imageWithSystemSymbolName:@"translate" accessibilityDescription:nil];
    }
  }
  if (!menu.numberOfItems) { callback->Cancel(); return true; }
  NSPoint point = NSMakePoint(params->GetXCoord(), params->GetYCoord());
  if (!view.isFlipped) point.y = view.bounds.size.height - point.y;
  BrowserTrace(@"tab.context-menu",@{@"tab":key,@"items":@(menu.numberOfItems)});
  // A positioning pop-up is not a contextual menu: AppKit skips macOS
  // selection services, including Ask Siri. Use the actual document responder.
  NSPoint location = [view convertPoint:point toView:nil];
  NSView *context = [view.window.firstResponder isKindOfClass:NSView.class] ? (NSView *)view.window.firstResponder : nil;
  if (!context || ![context isDescendantOf:view]) context = view;
  NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:location
                                 modifierFlags:NSApp.currentEvent.modifierFlags timestamp:NSProcessInfo.processInfo.systemUptime
                                  windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
  [NSMenu popUpContextMenu:menu withEvent:event forView:context];
  if (target.command == -2 || target.command == -3) {
    callback->Cancel();
    const bool restore = target.command == -3;
    dispatch_async(dispatch_get_main_queue(), ^{
      auto browser = browsers.find(key.UTF8String);
      NSWindow *window = VisibleChromePage(key).window;
      if (quitting || !window || window.attachedSheet || browser == browsers.end() || !browser->second->IsValid()) return;
      auto frame = browser->second->GetMainFrame();
      if (!frame || ![Str(frame->GetURL()) isEqual:documentURL]) return;
      if (hasSelection) {
        [TranslationPresenter() translateStrings:@[selection] hint:@"" page:NO owner:key inWindow:window completion:^(NSArray *unused) {}];
      } else {
        auto existing = pageTranslations.find(key.UTF8String);
        if (restore && existing != pageTranslations.end()) existing->second->Restore();
        else if (!restore && existing == pageTranslations.end()) {
          CefRefPtr<PageTranslationJob> job = new PageTranslationJob(key);
          pageTranslations[key.UTF8String] = job; job->Start(browser->second);
        }
      }
    });
    return true;
  }
  if (target.command >= 0 && !quitting) callback->Continue((int)target.command, target.flags);
  else callback->Cancel();
  return true;
}
