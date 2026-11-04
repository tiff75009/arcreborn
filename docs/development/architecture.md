# Architecture

The application is Swift/AppKit, not the earlier Electron prototype. CEF provides
Chromium rendering, extensions, profiles and DevTools through an Objective-C++
bridge. AppKit owns windows, sidebar, selection, split panes and most product UI.

`main.swift` starts CEF, creates `NativeAppDelegate`, and uses CEF's message loop.
Closing the app goes through `requestQuit`, persists sessions, then waits for
CEF browsers to close. Sparkle sends a normal Apple quit event and waits for the
process to terminate; it does not bypass this path or delete profile data.

`SessionStore` holds local state. Each regular profile has a CEF request context;
private windows use temporary contexts. `BROWSER_NATIVE_TEST_DATA` redirects
state to a disposable directory and disables cloud sync and automatic updates.
`make dev` sets it automatically. Official data remains under
`~/Library/Application Support/BrowserNative` for compatibility.

The native engine ABI is checked by `engine-framework-fingerprint.py`. Stock CEF
is used for the matching SDK headers/wrapper only. It is never silently substituted
for the customized runtime: missing native-host exports cause a build failure.

Current limits: arm64 only, minimum macOS target not exhaustively tested;
extension window APIs are not yet fully unified with the AppKit window model;
account service is optional and separately hosted; Easels remain under development.
Do not infer feature completeness from a menu item or successful compilation.
