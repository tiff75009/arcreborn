#!/bin/bash
set -euo pipefail
native="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "$native/build/handoff-check.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
# APFS clone: the fixture cannot modify the dev bundle, framework or user profile.
cp -cR "$native/build/Arc Reborn.app" "$scratch/Arc Reborn.app"
sources=()
for source in "$native"/Sources/*.swift; do
  [[ "$source" == "$native/Sources/main.swift" ]] || sources+=("$source")
done
xcrun swiftc -Onone -g -swift-version 5 -target arm64-apple-macosx13.0 \
  -import-objc-header "$native/Bridge/BrowserBridge.h" "${sources[@]}" "$native/Tests/HandoffHarness.swift" \
  "$native/build/cmake/libBrowserBridge.a" "$native/build/cmake/libcef_dll_wrapper/libcef_dll_wrapper.a" \
  -lc++ -framework Cocoa -framework IOSurface -framework Security -framework SecurityInterface \
  -F "$native/vendor/sparkle-2.10.1" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -Xlinker -ObjC -o "$scratch/Arc Reborn.app/Contents/MacOS/Arc Reborn"
# Only this disposable fixture uses ad-hoc signing; BROWSER_NATIVE_TEST_DATA
# forces Chromium's isolated mock Keychain, as in the other native harnesses.
codesign --force --sign - "$scratch/Arc Reborn.app"
node "$native/Tests/handoff.mjs" "$scratch/Arc Reborn.app/Contents/MacOS/Arc Reborn"
