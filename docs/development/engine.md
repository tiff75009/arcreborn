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
Xcode, its accepted licence, the Metal Toolchain component, Git and Python.
Install a missing Metal compiler with `xcodebuild -downloadComponent MetalToolchain`. Source download and compilation are
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
is compiled with Xcode 27.2. Engine `arcreborn.5` replaces that incremental build with a complete optimized
build from the same pinned source revisions using Xcode 27.2. Its `engine.json`
records the effective GN arguments, PGO profile and validated V8 configuration.
Engine `arcreborn.6` adds `browser_observe_tab_sound_v1` on top of that build.
It reports audibility and mute changes from each tab's Chromium WebContents
on the UI thread. The observer lives for the lifetime of the WebContents.
In `arcreborn.7`, the shell passes `--arc-reborn-sidebar-downloads` to let
AppKit draw the transfer animation and completion feedback. Chromium handles
download destinations, collision resolution and explicit security dialogs.
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

Engine `arcreborn.10` adds WebRTC H.264 encoding to the download recovery and tab
history support in `arcreborn.9`. The default and Apple passkey variants use
separate binary deltas against their respective published `arcreborn.7` archives.
A clean `make build` reconstructs the precompiled framework and verifies the
archive, source patches, delta, build flag changes and framework hashes. Source builds
apply `appkit-tab-history.patch` and `appkit-download-recovery.patch`. Run
`python3 native/scripts/test-download-recovery.py` after building the development app
to exercise both library actions against a local HTTP server.

## Password managers

Engine `arcreborn.11` adds native password-save and update prompts. Chromium
retains the pending credential and performs its existing encrypted, profile-scoped
write after explicit consent. Only an origin, username and opaque request token
cross the AppKit presentation boundary. Dismissal, site blocklisting, request
expiry and tab destruction release the pending form without saving it.

Selecting an external manager disables the built-in saving, generation, sign-in
and filling paths, including credentials already cached by open documents.
Recognized competing extensions are paused through Chromium’s extension registrar;
the engine records which ones it paused so switching back can restore them without
reactivating extensions previously disabled by the user or by policy. The iCloud
passkey proposal is suppressed for external managers other than Apple’s selected
extension. Installation and activation are detected independently for each profile.

The default precompiled engine includes the native passkey window anchor. Its
binary delta reconstructs the framework from the immutable public `arcreborn.7`
archive. `BROWSER_PASSKEY_ENGINE=1` therefore selects the same current engine.
Run `native/scripts/check.sh` for state and detection checks, and
`BROWSER_BUILD_ROOT=/path/to/build native/scripts/test-password-managers.sh` for
the isolated form-consent and extension lifecycle test (Node.js 22 or later).
The latter uses only Node built-ins, mock-keychain profiles and local,
nonfunctional extension fixtures with stable provider identities. It does not
access a personal vault or sign in to a password-manager account.

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
to the runtime itself. The sections below cover encrypted playback and WebRTC
encoding, which use separate Chromium components.

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

### Widevine on macOS

CEF obtains Google's signed Widevine CDM through Chromium's component updater.
An empty profile can report `NotSupportedError` until the download completes.
After registration, `requestMediaKeySystemAccess` and `createMediaKeys` exercise
two different stages. In the signed 1.2.1 build, the first succeeded but macOS
rejected the Google library in the ordinary utility process because the two
Developer ID teams differ. The resulting EME error was `CreateCdmFunc not available`.
[CEF component updater](https://github.com/chromiumembedded/cef/issues/3149).

Arc Reborn routes the sandboxed CDM service into its own helper on macOS 14 and
later. Its signed library constraint identifies Google's CDM by team, signing
identifier and Developer ID validation category. The rest of the application
uses its ordinary signing policy. The component updater manages CDM version
selection, verification and updates. Test the **Hardened Runtime build** because
development signing alone cannot reproduce the original loading error.
[Apple library constraints](https://developer.apple.com/documentation/security/defining-launch-environment-and-library-constraints).

```sh
BROWSER_SMOKE_APP='/path/to/signed/Arc Reborn.app' node native/Tests/protected-media-webrtc.mjs widevine
```

The test starts a clean profile, clicks the Widevine update button, waits for
component registration, requests a
temporary Widevine license for Shaka's public *Angel One* film, and requires a
usable key, advancing playback and decoded H.264 frames. It needs the network.
On first use, open `arc://components` in the address bar, find *Widevine Content
Decryption Module*, and click *Check for update* if it has no installed version.
Reload the player after installation. macOS can register the CDM while the
browser is running. A timeout on first use can be a component download delay.
[Official demo assets](https://github.com/shaka-project/shaka-player/blob/main/demo/common/assets.js).

Google requires a license agreement for Widevine products and services. For
a public browser, contact Google about desktop browser integration and host
signing. A distributor's EME license policy can require Verified Media Path
(VMP) and additional device or output protection. For macOS, CEF looks for a
signature named after the executing helper in the main app's Resources, and
one named after the CEF binary in its framework Resources. Apple's Developer
ID signature and notarization cover a different verification step. Record a
service-specific playback result before claiming support for its catalog.
Netflix publishes its own list of supported desktop browsers and resolutions.
[Widevine licensing](https://developers.google.com/widevine/drm/overview),
[integration contact](https://support.google.com/widevine/troubleshooter/6027072),
[CEF host signature paths](https://github.com/chromiumembedded/cef/blob/cf671c072925b27823a61181152f4f288e8e4306/libcef/common/cdm_host_file_path.cc),
[Netflix browser requirements](https://help.netflix.com/en/node/30081).

### WebRTC H.264 sending

In Chromium 156 on macOS the WebRTC hardware H.264 encoder requires an
available software fallback. Build both `media_use_openh264=true` and
`rtc_use_h264=true` with the existing proprietary-codec and FFmpeg settings.
H.264 file playback or a receiver capability does not exercise this path.
[Chromium's encoder selection](https://github.com/chromium/chromium/blob/fb096c0011f9d50f0a264a9376420cdea9c421e3/third_party/blink/renderer/platform/peerconnection/webrtc_util.cc),
[WebRTC build flags](https://webrtc.googlesource.com/src/+/19576e37870bfe5a0a910a32f98ff411f722f43a/webrtc.gni).

```sh
BROWSER_SMOKE_APP='/path/to/Arc Reborn.app' node native/Tests/protected-media-webrtc.mjs h264
BROWSER_RTC_SOFTWARE_ONLY=1 BROWSER_SMOKE_APP='/path/to/Arc Reborn.app' node native/Tests/protected-media-webrtc.mjs h264
```

The two local peers negotiate only H.264 and report encoded and decoded frames
from RTP statistics. The second command exercises software encoding with a
generated video source. Cisco distinguishes builds using its source from the
binary it distributes when describing coverage of applicable patent royalties.
[Cisco OpenH264 FAQ](https://www.openh264.org/faq.html).

On November 7, 2026, the signed arm64 preview played the Shaka Widevine film
with four usable keys. A separate H.264-only WebRTC call exchanged eight frames
and the software-only run exchanged six, all decoded on the receiving peer.
Both negotiated packetization mode 1 and profile-level-id `42001f`. The call
used a generated video track on one Mac.

## Profiling the browser and building a separate optimized engine

A CEF directory called `Release` does not imply that development checks were
compiled out. The published `arcreborn.4` engine was built with
`is_official_build=false`, leaving expensive V8 development checks enabled.
The current `arcreborn.5` pin enables official release compilation and PGO,
disables development-only checks, and retains the V8 sandbox and optimizing
compilers. ThinLTO is disabled to bound linker memory on a 16 GB Mac.
`engine.py configure` fetches the exact upstream release optimization profiles
before generating the build graph. Old archives stay immutable.

For future experiments without replacing the normal output directory, start
with a pinned and configured CEF checkout as described above:

```sh
python3 native/scripts/performance-engine.py --root /path/to/engine --jobs 4
BROWSER_ENGINE_FRAMEWORK='/path/to/engine/chromium_git/chromium/src/out/Arc_Performance_arm64/Chromium Embedded Framework.framework' \
  BROWSER_BUILD_ROOT="$PWD/native/build/performance" native/scripts/dev.sh --build-only
```

The separate output uses the existing CEF configuration, the locked codec
settings and patch stack, official Chromium arm64 and V8 optimization profiles,
and release compiler flags. It checks the generated V8 config (including its
sandbox and optimizing compilers) before compiling. Interrupting and rerunning
reuses the candidate's own objects. Do not copy object files from the published
engine's build directory: these options also change definitions shared between
translation units and the V8 snapshot.

To compare builds on the same idle Mac, run them separately on AC power with
the same window size. The runner opens Speedometer 3.1 in a disposable profile
with the test keychain and exports the benchmark's full JSON. It discards
backgrounded or incomplete runs and never changes the normal profile. Keep the
window visible; compare ten iterations per browser and report uncertainty.

```sh
node native/Tests/speedometer.mjs '/Applications/Arc Reborn.app' 10 > before.json
node native/Tests/speedometer.mjs 'native/build/performance/Arc Reborn.app' 10 > after.json
BROWSER_SMOKE_APP="$PWD/native/build/performance/Arc Reborn.app" \
  BROWSER_MEDIA_TEST_MATRIX=1 node native/Tests/media-playback.mjs
BROWSER_BUILD_ROOT="$PWD/native/build/performance" native/scripts/test-extension-placement.sh
```

Do not promote a candidate on the strength of a stock CEF score. Verify the
complete app and its codecs, extension popups and native embedding before
assigning a new engine version or publishing an update.

To track the local candidate, run `make monitor` from the repository root.
It opens a read-only dashboard at <http://127.0.0.1:8770>, updated every two
seconds. Closing the tab or stopping the monitor does not affect the build.
For future builds, `native/scripts/check-performance-candidate.sh ENGINE_ROOT 7`
runs the engine, development app, playback and extension checks, and Speedometer
in sequence. An optional third argument supplies a local MP4. Both commands
use `native/build/perf-check` for the journal (override with `ARC_PERF_WORK`).
The progress bar counts engine steps, including steps retained on a retry;
it doesn't estimate the duration of the subsequent tests.

The [0.6.0 performance report](performance-0.6.0.md) documents the diagnosis,
measurements and validation boundaries for the optimized engine.
