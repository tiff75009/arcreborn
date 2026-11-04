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

## Extension popups

The app passes the actual toolbar button's screen bounds to Chromium. The
engine chooses a corner **before** sizing the extension's web contents: opening
toward the page keeps the Compact sidebar and Classic toolbar usable at
opposite window edges. The available space is measured on the button's own
display, in logical points. Leave the native dismissal and permission paths
intact; moving the popup after it opens does not restore a clipped viewport.

Blink reports the preferred content size even when the embedding window has
not presented a compositor frame yet. The bubble applies it within the available
screen bounds and reacts to further size changes.

After building the development app, run `native/scripts/test-extension-placement.sh`.
It opens the same fixed-width extension at both edges of the display and checks
direction, visible bounds and equal width in an isolated profile.

## Video playback

The arm64 engine includes the Chromium FFmpeg H.264/AAC configuration, Media
Source Extensions, the HLS demuxer, and HEVC/H.265 decoding through macOS VideoToolbox. The GN settings in the lock file apply
to the runtime itself; changing a user agent or JavaScript capability check
cannot add a decoder. This change does not add a DRM module or a WebRTC encoder.

To exercise real decoding (including a VP9/Opus control) in a disposable
profile, build the development app and run the following with Node and ffmpeg:

```sh
node native/Tests/media-playback.mjs
# Release check: also decode VP8, AV1, HEVC Main and Main 10 with audio.
BROWSER_MEDIA_TEST_MATRIX=1 node native/Tests/media-playback.mjs
# Optional: use an original H.264/AAC MP4 and also test a remote HLS playlist.
# The playlist and segments must allow cross-origin requests from localhost.
BROWSER_MEDIA_TEST_HLS_URL=https://example.org/playlist.m3u8 node native/Tests/media-playback.mjs /path/to/sample.mp4
```

Set `BROWSER_SMOKE_APP` to test a different local app bundle. The check requires
advancing playback, decoded audio and video frames in the real renderer.
