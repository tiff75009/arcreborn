# Contributing to Arc Reborn

Welcome! Small, focused pull requests are encouraged. UI development does not
require rebuilding Chromium, a paid Apple account, or the hosted account API.

1. Fork and clone this repository on an Apple Silicon Mac.
2. Install Xcode (accept its licence) and CMake (`brew install cmake`).
3. Run `make dev`. It downloads the checksum-pinned engine and Sparkle, builds
   locally with an ad hoc signature, and opens an isolated development profile.
4. Change `native/Sources` (Swift/AppKit), or `native/Bridge` (Objective-C++).
5. Run `make check`, and exercise the affected feature in the development app.
6. Open a PR describing the problem, the change, and what you actually tested.

The current target is macOS 13+ on arm64. Building the layered icon from its
source requires Xcode 27; normal builds reuse the committed compiled icon assets.
Intel, Windows and Linux are not currently supported targets.

## Structure

- `native/Sources`: windows, tabs, spaces, preferences and native UI.
- `native/Bridge`: CEF integration, browser lifecycle and native host.
- `native/Engine`: upstream revisions, ordered patches, licence notices.
- `native/Tests`: state checks and optional isolated integration harnesses.
- `native/Resources`: icons, localisation and curated release notes.
- `docs/development`: engine builds, architecture and release process.

See [engine builds](docs/development/engine.md) when changing Chromium/CEF.
Do not commit vendor frameworks, Chromium checkouts, profile data, captures of
personal sessions, API credentials or signing keys. Do not remove another
contributor’s changes while fixing an unrelated issue.

## Pull requests and forks

PR CI uses hosted macOS runners without release secrets. Release signing only
runs on version tags in the original repository’s protected `release` environment.
Forks must use their own bundle identifier, feed, Sparkle key and signing identity
before distributing updates. Development builds cannot install official updates.

New code authored for this project is MPL-2.0; retain upstream notices on copied
or modified third-party files. Contributions are accepted under the same licence.
Use English for technical identifiers; UI copy supports French and English.

## Optional integration tests

Node-based harnesses in `native/Tests/*.mjs` are optional and require Playwright.
They must use `BROWSER_NATIVE_TEST_DATA` pointing to a disposable directory.
These isolated runs use Chromium's mock keychain, keep their cache under
`Chromium/MockKeychain`, and disable the live Arc Reborn account service. They do
not access your macOS passwords or request Keychain approval. Do not use real
credentials in these disposable profiles. Older test caches are left untouched.
Never automate tests against `~/Library/Application Support/BrowserNative`.
Do not run a long Chromium build or a broad test campaign for a small UI change.
