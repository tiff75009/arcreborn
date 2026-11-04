# Releases and automatic updates

## One-time setup

The repository is `tiff75009/arcreborn`. Protect `main`, restrict `v*` tags to
maintainers, and create a GitHub **release** environment with required reviewers
and tag restrictions. PR jobs have no secrets and use GitHub-hosted runners.
Never attach a personal signing Mac as an untrusted public PR runner.

For hosted signing, set the following environment secrets. Enable the repository variable `RELEASE_SIGNING_ENABLED=true` after configuring them. With local signing, leave the variable unset and use the local release commands below.

| Secret | Content |
| --- | --- |
| `APPLE_CERTIFICATE_P12` | Base64 Developer ID Application certificate **with private key** |
| `APPLE_CERTIFICATE_PASSWORD` | Password protecting the exported P12 |
| `APPLE_NOTARY_KEY` | App Store Connect API `.p8` contents |
| `APPLE_NOTARY_KEY_ID` | Key identifier |
| `APPLE_NOTARY_ISSUER` | Issuer identifier |
| `SPARKLE_PRIVATE_KEY` | Sparkle Ed25519 private key export (base64 text) |

These secrets have **not** been uploaded by the preparation scripts. Locally the
Apple key remains in the login Keychain and Sparkle uses account `arc-reborn`.
Back up that key securely; the public key in Info.plist must match it. Forks must
generate their own key and update their feed/bundle/signing configuration.
Do not rotate keys casually: installed versions trust the previous public key.

CI creates an ephemeral keychain and removes it and private files in an `always`
cleanup step. No signing material is uploaded as an artifact. The app account API,
Resend, Coolify and database credentials have no role in this pipeline.

## Release steps

1. Update `native/Resources/ReleaseNotes.json`: semantic version, strictly increasing
   integer build, French/English title, subtitle and curated highlights.
2. Update the same two version fields in `native/Resources/Info.plist`.
   `release.py check` rejects inconsistencies.
   For a small fix, set `"showOnLaunch": false` in the release notes to skip
   the startup window. The notes remain available in Preferences and on GitHub.
3. Commit and review. Push a tag such as `v0.3.0` at that exact commit.
4. The release workflow builds the shell against the pinned engine, signs nested
   components inside-out, notarizes the app, creates/signs/notarizes the DMG, and
   signs both the Sparkle archive and feed. It creates a **draft GitHub Release**.
5. Check the draft DMG/changelog. Publish the release with Latest enabled.

An ordinary push only runs CI. Publishing the draft is the explicit distribution
step, allowing a bad build to be stopped before users are offered it. GitHub's
source archive points to the exact tag; the engine lock points to matching sources.
Do not replace published assets or reuse build numbers. Withdraw a faulty release
and ship a higher build, rather than silently downgrading installed applications.

## Local equivalent

```sh
export BROWSER_RELEASE_BUILD=1
./native/scripts/build.sh
# Configure BROWSER_NOTARY_KEYCHAIN_PROFILE, or BROWSER_NOTARY_KEY,
# BROWSER_NOTARY_KEY_ID and BROWSER_NOTARY_ISSUER privately in the shell.
/usr/bin/python3 native/scripts/release.py prepare
/usr/bin/python3 native/scripts/release.py draft
```

`prepare` can resume a pending notarization; use a new output directory for a new
build. `draft` requires a clean reviewed Git checkout with its version tag already
pushed. It uploads only DMG, appcast.xml, release.json and SHA256SUMS, never the
working directory, signing credentials or server code.

For local signing, the prepared draft can be verified and published by GitHub
Actions without uploading Apple or Sparkle private keys:

```sh
gh workflow run publish-prepared.yml --ref main -f tag=v0.4.1
```

Run this after uploading the tagged draft assets. The publication workflow runs
the native macOS build and tests for that tag before opening the publishing job.
The workflow checks version/engine metadata, every checksum, the signed Sparkle
feed and DMG, the Apple signatures and stapled notarization tickets, then publishes
the draft as Latest. A failed verification leaves the release unpublished.

## Update behavior

Feed: `https://github.com/tiff75009/arcreborn/releases/latest/download/appcast.xml`.
Sparkle 2.10.1 handles scheduling, download, authenticity checks and installation.
By default, it checks every **6 hours** while Arc Reborn is running, downloads
updates in the background and installs them when the app quits. An overdue check
resumes on launch using Sparkle's scheduler. No separate timer or background daemon
runs while the browser is closed. If a downloaded update has been waiting for
24 hours, Sparkle may remind the user; it never forces a restart while browsing.
Preferences → General can disable checks or automatic installation independently.
Defaults are declared in Info.plist, not reset on launch: explicit user choices
survive upgrades. System profiling stays disabled.

Cadence references: Chrome's enterprise documentation specifies a default of
[295 minutes](https://support.google.com/chrome/a/answer/2657289?hl=en), Firefox's
[release defaults specify 6 hours](https://github.com/mozilla-firefox/firefox/blob/main/browser/branding/official/pref/firefox-branding.js), while
[Sparkle defaults to 24 hours](https://sparkle-project.org/documentation/customization/).
Six hours keeps browser update discovery frequent without constant polling.
Feed and archive signatures are required, and signatures are checked before
extraction. Feed verification does not silently expire into accepting unsigned feeds.
`verify-release.swift` validates the feed and archive with the public key only;
verification never needs access to the private signing key or macOS Keychain.

The app retains `local.browser.native` and its existing profile path. Sparkle
replaces the app bundle, not Application Support. Quit still goes through normal
CEF shutdown and session persistence. A canceled page unload can postpone the update.

`ReleaseNotes.json` ships inside the signed app. The native highlights window is
shown once per higher build after onboarding and launch sheets. First installations
establish a baseline; the Help menu can always reopen the notes. No remote HTML or
JavaScript drives this native window. Sparkle's update dialog also shows the release
notes before installation.

Every published update needs a new Apple signature and notarization, but the same
valid certificate and API key automate them. No repeated Apple portal wizard is
needed. Certificate renewal and key backup remain maintainer responsibilities.

References: [Sparkle](https://sparkle-project.org/documentation/),
[GitHub releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases),
[Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
