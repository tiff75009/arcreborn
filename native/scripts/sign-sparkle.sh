#!/bin/bash
set -euo pipefail
FRAMEWORK="${1:?Sparkle.framework required}"
IDENTITY="${2:?Signing identity required}"
SIGN_ARGS=(--force --sign "$IDENTITY" --options runtime --preserve-metadata=entitlements)
if [[ "$IDENTITY" != '-' ]]; then SIGN_ARGS+=(--timestamp); fi
# Sign physical nested code, not symlink aliases. Preserve Sparkle's own XPC
# sandbox entitlements; Chromium's JIT entitlements must never be applied here.
for component in Autoupdate Updater.app XPCServices/Installer.xpc XPCServices/Downloader.xpc; do
  codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/$component"
done
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK"
