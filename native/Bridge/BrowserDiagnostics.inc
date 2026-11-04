// Append-only breadcrumbs and stderr survive an abnormal exit and a relaunch.
// Record native state only: no page contents, form values, cookies or full URLs.
#include <fcntl.h>
#include <unistd.h>
#include <mutex>
#include <cstdlib>
#include <mach-o/loader.h>

static int diagnosticFD = -1;
static std::mutex diagnosticMutex;
static NSString *diagnosticDirectory;
static NSUncaughtExceptionHandler *previousExceptionHandler;

static void BrowserTrace(NSString *event, NSDictionary *fields = nil) {
  if (diagnosticFD < 0) return;
  @autoreleasepool {
    @try {
      NSMutableDictionary *record = [NSMutableDictionary dictionaryWithDictionary:fields ?: @{}];
      record[@"event"] = event;
      record[@"time"] = @(NSDate.date.timeIntervalSince1970);
      record[@"pid"] = @(getpid());
      record[@"mainThread"] = @(NSThread.isMainThread);
      NSMutableData *data = [[NSJSONSerialization dataWithJSONObject:record options:0 error:nil] mutableCopy];
      if (!data) return;
      [data appendBytes:"\n" length:1];
      std::lock_guard<std::mutex> lock(diagnosticMutex);
      // No userspace buffer: even an immediate Chromium abort leaves the trace.
      (void)write(diagnosticFD, data.bytes, data.length);
    } @catch (NSException *) { }
  }
}
static void BrowserUncaughtException(NSException *exception) {
  BrowserTrace(@"app.uncaught-exception", @{@"name":exception.name ?: @"",
      @"reason":exception.reason ?: @"", @"stack":exception.callStackSymbols ?: @[]});
  if (previousExceptionHandler) previousExceptionHandler(exception);
}
static void BrowserTraceLoadedEngine() {
  for (uint32_t i=0;i<_dyld_image_count();++i) {
    const char *path = _dyld_get_image_name(i);
    if (!path || ![[NSString stringWithUTF8String:path].lastPathComponent isEqualToString:@"Chromium Embedded Framework"]) continue;
    auto *header = _dyld_get_image_header(i);
    if (header->magic != MH_MAGIC_64) continue;
    auto *command = reinterpret_cast<const load_command*>(reinterpret_cast<const char*>(header)+sizeof(mach_header_64));
    for (uint32_t n=0;n<header->ncmds;++n) {
      if (command->cmd == LC_UUID) {
        auto *uuid = reinterpret_cast<const uuid_command*>(command);
        BrowserTrace(@"cef.loaded-image",@{@"path":@(path),@"uuid":[[NSUUID alloc] initWithUUIDBytes:uuid->uuid].UUIDString});
        return;
      }
      command = reinterpret_cast<const load_command*>(reinterpret_cast<const char*>(command)+command->cmdsize);
    }
  }
}
static void BrowserDiagnosticsBegin(NSString *cachePath) {
  if (diagnosticFD >= 0) return;
  NSDateFormatter *date = [[NSDateFormatter alloc] init];
  date.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  date.dateFormat = @"yyyyMMdd-HHmmss";
  NSString *run = [NSString stringWithFormat:@"%@-%d",[date stringFromDate:NSDate.date],getpid()];
  cachePath = cachePath.stringByResolvingSymlinksInPath;
  diagnosticDirectory = [[cachePath stringByAppendingPathComponent:@"Diagnostics"] stringByAppendingPathComponent:run];
  if (![NSFileManager.defaultManager createDirectoryAtPath:diagnosticDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) return;
  diagnosticFD = open([diagnosticDirectory stringByAppendingPathComponent:@"events.jsonl"].fileSystemRepresentation,O_WRONLY|O_CREAT|O_APPEND|O_CLOEXEC,0600);
  int errors = open([diagnosticDirectory stringByAppendingPathComponent:@"process.log"].fileSystemRepresentation,O_WRONLY|O_CREAT|O_APPEND|O_CLOEXEC,0600);
  if (errors >= 0) { (void)dup2(errors,STDERR_FILENO); if (errors != STDERR_FILENO) close(errors); }
  previousExceptionHandler = NSGetUncaughtExceptionHandler();
  NSSetUncaughtExceptionHandler(BrowserUncaughtException);
  std::atexit([] { BrowserTrace(@"app.normal-exit"); });
  BrowserTrace(@"app.start", @{@"executable":NSBundle.mainBundle.executablePath ?: @"",
      @"isolated":@(NSProcessInfo.processInfo.environment[@"BROWSER_NATIVE_TEST_DATA"] != nil)});
  // Keep CEF's sandbox-compatible log path. Save its previous contents before
  // CefInitialize truncates it; stderr also captures the current run separately.
  NSString *previousLog = [cachePath stringByAppendingPathComponent:@"chromium.log"];
  if ([NSFileManager.defaultManager fileExistsAtPath:previousLog])
    [NSFileManager.defaultManager copyItemAtPath:previousLog toPath:[diagnosticDirectory stringByAppendingPathComponent:@"previous-chromium.log"] error:nil];
  // Observe window identity/geometry, never its title or document URL.
  for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification,NSWindowWillCloseNotification]) {
    [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
      NSWindow *window = [note.object isKindOfClass:NSWindow.class] ? note.object : nil;
      if (window) BrowserTrace(@"window.lifecycle",@{@"notification":note.name,@"class":NSStringFromClass(window.class),
          @"identifier":window.identifier ?: @"",@"number":@(window.windowNumber),@"visible":@(window.visible)});
    }];
  }
}
