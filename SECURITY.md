# Security

This project is in development. A successful build is not a security audit.
Keep the pinned Chromium/CEF engine current; do not bypass its sandbox, certificate
checks, or signature verification to solve an integration problem.

Please use GitHub's private vulnerability reporting on this repository when it
is enabled. If unavailable, open an issue requesting a private contact without
including exploit details, credentials or personal browsing data.

Only maintainers publish official updates. Releases require Developer ID signing,
Apple notarization and Sparkle Ed25519 signatures. Both downloaded archives and
the update feed are verified. Signing keys belong in a private Keychain or the
protected GitHub `release` environment, never in Git or CI artifacts.

PR workflows must never access signing keys or run on a maintainer's personal
machine. Avoid `pull_request_target` with untrusted source checkout. Validate
dependencies by the committed checksums before running their tools.
