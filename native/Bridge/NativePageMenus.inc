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
  if (!menu.numberOfItems) { callback->Cancel(); return true; }
  NSPoint point = NSMakePoint(params->GetXCoord(), params->GetYCoord());
  if (!view.isFlipped) point.y = view.bounds.size.height - point.y;
  BrowserTrace(@"tab.context-menu",@{@"tab":key,@"items":@(menu.numberOfItems)});
  [menu popUpMenuPositioningItem:nil atLocation:point inView:view];
  if (target.command >= 0 && !quitting) callback->Continue((int)target.command, target.flags);
  else callback->Cancel();
  return true;
}
