#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
@protocol BrowserEngineDelegate <NSObject>
- (void)browserTitleChanged:(NSString *)tabID title:(NSString *)title NS_SWIFT_NAME(browserTitleChanged(_:title:));
- (void)browserURLChanged:(NSString *)tabID url:(NSString *)url NS_SWIFT_NAME(browserURLChanged(_:url:));
- (void)browserLoadingChanged:(NSString *)tabID loading:(BOOL)loading back:(BOOL)back forward:(BOOL)forward NS_SWIFT_NAME(browserLoadingChanged(_:loading:back:forward:));
- (void)browserFailed:(NSString *)tabID code:(NSString *)code host:(nullable NSString *)host NS_SWIFT_NAME(browserFailed(_:code:host:));
- (void)browserRequestedNewTab:(NSString *)url sourceTab:(NSString *)tabID NS_SWIFT_NAME(browserRequestedNewTab(_:sourceTab:));
- (void)browserClosed:(NSString *)tabID NS_SWIFT_NAME(browserClosed(_:));
@optional
- (void)browserLoadProgress:(NSString *)tabID fraction:(double)fraction NS_SWIFT_NAME(browserLoadProgress(_:fraction:));
- (void)browserRequestedPrivateWindow:(NSString *)url sourceTab:(NSString *)tabID NS_SWIFT_NAME(browserRequestedPrivateWindow(_:sourceTab:));
- (void)browserRequestedNewWindow:(NSString *)url sourceTab:(NSString *)tabID NS_SWIFT_NAME(browserRequestedNewWindow(_:sourceTab:));
- (nullable NSDictionary<NSString *, id> *)browserPreparePopup:(NSString *)url sourceTab:(NSString *)tabID active:(BOOL)active NS_SWIFT_NAME(browserPreparePopup(_:sourceTab:active:));
- (void)browserPictureInPictureReturn:(NSString *)tabID NS_SWIFT_NAME(browserPictureInPictureReturn(_:));
- (void)browserExtensionInstalled:(NSString *)identifier name:(NSString *)name profile:(NSString *)profile NS_SWIFT_NAME(browserExtensionInstalled(_:name:profile:));
- (nullable NSDictionary<NSString *, id> *)browserPrepareExtensionTab:(NSString *)sourceTab active:(BOOL)active pinned:(BOOL)pinned index:(NSInteger)index NS_SWIFT_NAME(browserPrepareExtensionTab(_:active:pinned:index:));
- (void)browserExtensionTabCreated:(NSString *)tabID success:(BOOL)success NS_SWIFT_NAME(browserExtensionTabCreated(_:success:));
- (void)browserDownloadUpdated:(NSString *)tabID values:(NSDictionary<NSString *, id> *)values NS_SWIFT_NAME(browserDownloadUpdated(_:values:));
- (BOOL)browserUndoRequested;
- (void)browserFaviconChanged:(NSString *)tabID image:(nullable NSImage *)image NS_SWIFT_NAME(browserFaviconChanged(_:image:));
- (void)browserCloseCancelled:(NSString *)tabID NS_SWIFT_NAME(browserCloseCancelled(_:));
- (nullable NSDictionary<NSString *, id> *)browserPreparePopup:(NSString *)url sourceTab:(NSString *)tabID NS_SWIFT_NAME(browserPreparePopup(_:sourceTab:));
@end
@interface BrowserEngine : NSObject
@property(nonatomic, weak, nullable) id<BrowserEngineDelegate> delegate;
+ (BOOL)startWithCachePath:(NSString *)cachePath NS_SWIFT_NAME(start(cachePath:));
+ (void)shutdown;
+ (void)requestQuit;
+ (void)stopMessageLoop;
+ (void)runMessageLoop;
+ (NSString *)chromiumVersion;
+ (NSApplication *)createApplication;
- (BOOL)registerPrivateProfile:(NSString *)profileID;
- (void)releasePrivateProfile:(NSString *)profileID;
- (void)updateLanguages;
- (BOOL)setSearchProvider:(NSInteger)identifier name:(NSString *)name keyword:(NSString *)keyword templateURL:(NSString *)url forProfile:(NSString *)profile NS_SWIFT_NAME(setSearchProvider(_:name:keyword:templateURL:profile:));
- (BOOL)updateCredentialPreferences;
- (BOOL)createTab:(NSString *)tabID profile:(NSString *)profileID url:(NSString *)url inView:(NSView *)container NS_SWIFT_NAME(createTab(_:profile:url:container:));
- (void)navigateTab:(NSString *)tabID url:(NSString *)url;
- (void)resizeTab:(NSString *)tabID inView:(NSView *)container NS_SWIFT_NAME(resizeTab(_:container:));
- (void)setTab:(NSString *)tabID visible:(BOOL)visible;
- (void)focusTab:(NSString *)tabID;
- (void)toggleMute:(NSString *)tabID;
- (void)requestPictureInPicture:(NSString *)tabID automatic:(BOOL)automatic completion:(void (^)(NSString *))completion NS_SWIFT_NAME(requestPictureInPicture(_:automatic:completion:));
- (void)closePictureInPicture:(NSString *)tabID NS_SWIFT_NAME(closePictureInPicture(_:));
- (BOOL)hasPictureInPicture:(NSString *)tabID NS_SWIFT_NAME(hasPictureInPicture(_:));
- (void)goBack:(NSString *)tabID;
- (void)goForward:(NSString *)tabID;
- (void)reload:(NSString *)tabID;
- (void)reloadIgnoringCache:(NSString *)tabID;
- (double)zoomLevel:(NSString *)tabID;
- (void)setZoomLevel:(NSString *)tabID level:(double)level;
- (BOOL)canSavePage:(NSString *)tabID;
- (void)savePage:(NSString *)tabID;
- (void)printPage:(NSString *)tabID;
- (void)stop:(NSString *)tabID;
- (void)closeTab:(NSString *)tabID;
- (void)tryAutoArchiveTab:(NSString *)tabID;
- (void)discardTab:(NSString *)tabID;
- (void)findInTab:(NSString *)tabID text:(NSString *)text forward:(BOOL)forward next:(BOOL)next;
- (void)stopFinding:(NSString *)tabID;
- (nullable NSDictionary<NSString *, id> *)extensionSettingsForProfile:(NSString *)profile NS_SWIFT_NAME(extensionSettings(profile:));
- (BOOL)setExtensionPinned:(NSString *)identifier profile:(NSString *)profile pinned:(BOOL)pinned NS_SWIFT_NAME(setExtensionPinned(_:profile:pinned:));
- (NSInteger)activateExtension:(NSString *)identifier forTab:(NSString *)tabID anchor:(NSRect)screenAnchor NS_SWIFT_NAME(activateExtension(_:tab:anchor:));
- (void)closeExtensionPopup;
- (nullable NSDictionary<NSString *, id> *)certificateInfoForTab:(NSString *)tabID NS_SWIFT_NAME(certificateInfo(forTab:));
- (BOOL)hasDeveloperTools:(NSString *)tabID;
- (void)toggleDeveloperTools:(NSString *)tabID;
- (NSString *)developerToolForTab:(NSString *)tabID NS_SWIFT_NAME(developerTool(forTab:));
- (void)toggleDeveloperTool:(NSString *)tool forTab:(NSString *)tabID NS_SWIFT_NAME(toggleDeveloperTool(_:forTab:));
- (void)closeDeveloperTools:(NSString *)tabID;
- (void)capturePage:(NSString *)tabID completion:(void (^)(NSData * _Nullable))completion NS_SWIFT_NAME(capturePage(_:completion:));
- (void)captureFullPage:(NSString *)tabID completion:(void (^)(NSData * _Nullable))completion NS_SWIFT_NAME(captureFullPage(_:completion:));
- (void)checkArchiveIdle:(NSString *)tabID completion:(void (^)(BOOL))completion NS_SWIFT_NAME(checkArchiveIdle(_:completion:));
- (NSView * _Nullable)captureViewForTab:(NSString *)tabID NS_SWIFT_NAME(captureView(forTab:));
- (void)captureElementAtPoint:(NSPoint)point forTab:(NSString *)tabID completion:(void (^)(NSDictionary * _Nullable))completion NS_SWIFT_NAME(captureElement(at:forTab:completion:));
- (void)setPageInputSuppressed:(BOOL)suppressed forTab:(NSString *)tabID;
- (void)clearCacheForTab:(NSString *)tabID completion:(void (^)(BOOL))completion;
- (void)clearCookiesForTab:(NSString *)tabID completion:(void (^)(BOOL))completion;
- (void)controlDownload:(NSUInteger)identifier action:(NSString *)action NS_SWIFT_NAME(controlDownload(_:action:));
- (void)setAppearanceMode:(NSInteger)mode;
- (BOOL)showExtensionStoreForProfile:(NSString *)profileID name:(NSString *)name address:(NSString *)address NS_SWIFT_NAME(showExtensionStore(profile:name:address:));
- (BOOL)showExtensionsForProfile:(NSString *)profileID name:(NSString *)name store:(BOOL)store NS_SWIFT_NAME(showExtensions(profile:name:store:));
@end
NS_ASSUME_NONNULL_END
