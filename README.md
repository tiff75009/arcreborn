# Arc Reborn

A native macOS browser built with **Swift, AppKit and a customized Chromium
Embedded Framework (CEF)**. Spaces, pinned tabs, split views, extensions and
native developer tools live in a macOS interface. This is a project in development,
not a production security guarantee or an official continuation of Arc.

## Download for macOS

Install the DMG for Apple Silicon from the [latest browser release](https://github.com/tiff75009/arcreborn/releases/latest). The first launch lets you bring over supported data from another browser and optionally set up encrypted sync.

## Start contributing

On an Apple Silicon Mac with Xcode and CMake (`brew install cmake`):

```sh
git clone https://github.com/tiff75009/arcreborn.git
cd arcreborn
make dev
```

The first build downloads the exact engine archive and Sparkle, verifies their
checksums, then compiles the native shell. Later builds reuse the engine.
No paid Apple Developer account, Node, React or Electron is needed.
Development uses `native/build/development/profile`, never your everyday profile.

The [pinned engine archive](https://github.com/tiff75009/arcreborn/releases/tag/engine-156.0.8078.80-arcreborn.1) is available separately. To build it from source, follow [the engine build instructions](docs/development/engine.md).

```sh
make build         # compile without launching
make check         # focused state/release checks
```

The runtime target is macOS 13+ / arm64. Liquid Glass icon sources are included;
normal builds reuse compiled assets, while icon changes require Xcode 27.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the code map and PR workflow.

## Sources and engine

All browser source and engine modifications live on the **same branch**, with
immutable upstream CEF/Chromium revisions and ordered patches. We do not copy
Chromium's full Git history or compiled frameworks into this repository.
The engine is an independently versioned GitHub Release asset with SHA-256
verification. Anyone can rebuild it from upstream source and the included patches.

- [Architecture and current limits](docs/development/architecture.md)
- [Engine build and versioning](docs/development/engine.md)
- [Signing, updates and releases](docs/development/releases.md)
- [Security reporting](SECURITY.md)

## Updates

Official builds use Sparkle. Check for updates from the Arc Reborn menu or
Preferences → General. By default the browser checks periodically, downloads signed
updates in the background and installs them when you quit. Curated release
notes appear once after an upgrade and remain accessible from Help.

GitHub Releases host the DMG, signed appcast and checksums. An ordinary push runs
CI. Maintainers can prepare a signed release locally or enable the protected release
workflow for version tags. Publishing the release makes it available to the updater. Contributor builds and
forks do not install official updates over their local modifications.

## Open source

Arc Reborn's original code is **MPL-2.0**. Upstream components keep their own
licences; see [NOTICE.md](NOTICE.md). Accounts and encrypted synchronization are
optional. The hosted account API is maintained separately and is not required
for local browsing or development.

Independent project; not affiliated with The Browser Company, Arc, Apple or Google.
