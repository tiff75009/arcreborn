#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPDATE_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/arcreborn-update-test.XXXXXX")"
trap 'rm -rf "$UPDATE_TEST_ROOT"' EXIT
UPDATE_TEST_APP="$UPDATE_TEST_ROOT/Update Preferences.app"
SPARKLE_ROOT="$NATIVE_ROOT/vendor/sparkle-2.10.1"
mkdir -p "$UPDATE_TEST_APP/Contents/MacOS" "$UPDATE_TEST_APP/Contents/Resources"
cp "$NATIVE_ROOT/Resources/Info.plist" "$UPDATE_TEST_APP/Contents/Info.plist"
cp "$NATIVE_ROOT/Resources/ReleaseNotes.json" "$UPDATE_TEST_APP/Contents/Resources/"
if [[ -f "$NATIVE_ROOT/Resources/PreviousVisibleReleaseNotes.json" ]]; then
  cp "$NATIVE_ROOT/Resources/PreviousVisibleReleaseNotes.json" "$UPDATE_TEST_APP/Contents/Resources/"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.arcreborn.update-test.$(uuidgen)" "$UPDATE_TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable UpdatePreferencesTests' "$UPDATE_TEST_APP/Contents/Info.plist"
xcrun swiftc -parse-as-library -F "$SPARKLE_ROOT" -framework Sparkle -framework AppKit \
    -Xlinker -rpath -Xlinker "$SPARKLE_ROOT" "$NATIVE_ROOT/Sources/BrowserUpdates.swift" "$NATIVE_ROOT/Sources/SidebarUpdateDriver.swift" "$NATIVE_ROOT/Sources/SidebarUpdateSession.swift" "$NATIVE_ROOT/Tests/UpdatePreferencesTests.swift" \
    -o "$UPDATE_TEST_APP/Contents/MacOS/UpdatePreferencesTests"
"$UPDATE_TEST_APP/Contents/MacOS/UpdatePreferencesTests"
