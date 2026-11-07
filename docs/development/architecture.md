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

Finder’s Open With, dropping documents on the Dock icon, and File → Open File
(⌘O) open HTML, PDF and SVG documents as tabs. Internet shortcuts (`.webloc`)
open their HTTP or HTTPS destination. Finder uses a regular window; the file
picker uses the window that opened it, including private windows. Local file
paths stay on this Mac and are excluded from Handoff and cloud sync.
On macOS, run `node native/Tests/local-documents.mjs "/path/to/Arc Reborn.app"`
against a development build to exercise Launch Services and verify rendered
content. Add `--try-open-panel` for the interactive shortcut check.

Search engine, new-tab page and automatic archiving are profile preferences.
Automatic archiving is off unless the profile has an explicit opt-in date.
Enabling it starts a fresh interval (12 hours, 24 hours, 7 days or 30 days);
changing the interval does not enable it. A sweep at startup, after wake and
while running considers temporary tabs only. Visible tabs in any window,
favorites, pinned tabs and split groups are excluded. A loaded page must
confirm that its frames are idle; an unanswered probe or a before-unload
warning keeps the tab open. Archived tabs remain restorable from the Library.

Undo Close, the Library and archived results in the command bar all restore the
original tab. On close, the bridge captures Chromium’s serialized navigation
entries and selected index. On restore, a fresh WebContents in the same profile
installs the entries before loading the selected page. The snapshot stays local
and private windows keep it in memory. Each snapshot keeps up to 50 entries and
256 KiB. Archived tabs share a 6 MiB snapshot budget, newest first. Older
URL-only records and unusable snapshots still open at the saved URL. After
`make build`, run `python3 native/scripts/test-tab-history.py` to exercise the native
commands across origins and a complete app restart with an isolated profile.

The native engine ABI is checked by `engine-framework-fingerprint.py`. Stock CEF
is used for the matching SDK headers/wrapper only. It is never silently substituted
for the customized runtime: missing native-host exports cause a build failure.

Current limits: arm64 only, minimum macOS target not exhaustively tested;
extension window APIs are not yet fully unified with the AppKit window model;
account service is optional and separately hosted; Easels remain under development.
Do not infer feature completeness from a menu item or successful compilation.
