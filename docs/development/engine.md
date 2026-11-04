# The engine belongs to the source release

Browser source, CEF/Chromium patches, source revisions and build settings stay
on the same branch. A contributor can review the complete difference from
upstream without downloading Chromium's history. Binaries belong in GitHub
Releases, not Git LFS, Git submodules containing binaries, or another source branch.

`native/Engine/engine.lock.json` pins Chromium, CEF, depot_tools, ordered patch
hashes, build settings and the arm64 archive URL/SHA-256. Normal builds use this
archive and fetch the matching official CEF SDK for its public headers/wrapper.
Stock CEF cannot replace the customized runtime.

## Rebuild from upstream sources

Use a dedicated local APFS directory on a disk with several hundred GB available,
Xcode, its accepted licence, Git and Python. Source download and compilation are
large operations; normal UI contributors do not need them.

```sh
/usr/bin/python3 native/scripts/engine.py prepare --root /path/to/engine
/usr/bin/python3 native/scripts/engine.py configure --root /path/to/engine
/usr/bin/python3 native/scripts/engine.py build --root /path/to/engine --jobs 4
BROWSER_ENGINE_FRAMEWORK='/path/to/engine/chromium_git/chromium/src/out/Release_GN_arm64/Chromium Embedded Framework.framework' make dev
```

The script uses upstream CEF automate-git, validates the checked-out commits,
applies the included patch stack and builds `cef_framework`. Re-running configure
recognizes the complete applied stack without reversing live edits. The initial
engine objects were compiled with Xcode 26.2. Engine `arcreborn.2` rebuilds the
navigation changes with Xcode 27.2 and links them with unchanged pinned objects;
its `engine.json` records this incremental build and its base version. The shell
is compiled with Xcode 27.2. A full clean engine build with 27.2 remains unvalidated.
A macOS SDK is obtained through the developer's Xcode installation.

Before changing the patch stack, update its hashes and increment the engine
version. Rebuild and verify the private ABI before packaging a new archive.
The current source build scripts replace the old machine-specific volume paths.

## Binary release format

An engine `.tar.gz` contains the framework, `engine.json` provenance, the exact
patches, and licence notices. Its archive checksum is committed to engine.lock.json.
The maintainer publishes it as an `engine-<version>` release with **Latest disabled**,
then commits the lock update. Engine releases never replace the browser's latest
Sparkle appcast. Keep previous engine assets immutable so old source tags still build.

The first archive is published in the [engine release](https://github.com/tiff75009/arcreborn/releases/tag/engine-156.0.8078.80-arcreborn.1). The contributor build caches the verified archive in `native/vendor/`.
Never redistribute Apple's SDKs, signing keys, user profiles, or proprietary CDMs.
Chromium's third-party credits remain accessible via `chrome://credits`.

References: [CEF build guide](https://chromiumembedded.github.io/cef/branches_and_building),
[Chromium macOS build instructions](https://chromium.googlesource.com/chromium/src/+/main/docs/mac_build_instructions.md).

## Native navigation and menus

`appkit-native-navigation.patch` routes Chromium's complete `OpenURLParams` to a
same-profile AppKit tab. This keeps POST data, referrers and initiator information.
A URL-only `OnOpenURLFromTab` replacement loses form bodies. Explicit link menu
commands for normal/private windows use the existing native window controller.

CEF 156 Chrome delivers the popup view callback before the lifespan creation
callback, despite the public header's ordering comment. Popup reservations are
matched by their `CefClient`, with the tab marked pending before AppKit redraws.
Hidden backend windows are excluded from Chromium session restoration; the native
session remains responsible for restoring tabs and windows.

The website context menu retains Chromium's command model and callbacks, and
presents an `NSMenu` in the actual document view. Chromium keyboard mnemonic
markers are removed from labels; escaped literal ampersands remain visible.
`browser_native_navigation_version_v1` identifies engines with full-request routing.

Mouse context menus also preserve the existing DOM selection. The selection
controller skips automatic word/link selection for mouse menus; keyboard and
touch paths retain their existing behavior. This applies inside the engine,
without injecting page event handlers or clearing the user's selected text.
