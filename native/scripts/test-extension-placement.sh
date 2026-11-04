#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# Exercise the real AppKit/CEF popup with the same extension at both edges.
set -euo pipefail
native="$(cd "$(dirname "$0")/.." && pwd)"
build="${BROWSER_BUILD_ROOT:-$native/build/development}"
app="$build/Arc Reborn.app"
fixture="$native/Tests/Fixtures/extension-probe"
[[ -d "$app" && -f "$build/cmake/libBrowserBridge.a" ]] || {
  echo 'Build the development app with native/scripts/dev.sh --build-only first.' >&2
  exit 1
}
scratch="$(mktemp -d "$native/build/popup-placement.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
cp -cR "$app" "$scratch/Arc Reborn.app"
exe="$scratch/Arc Reborn.app/Contents/MacOS/Arc Reborn"
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx13.0 \
  -import-objc-header "$native/Bridge/BrowserBridge.h" "$native/Tests/ExtensionPopupHarness.swift" \
  "$build/cmake/libBrowserBridge.a" "$build/cmake/libcef_dll_wrapper/libcef_dll_wrapper.a" \
  -lc++ -framework Cocoa -framework IOSurface -framework Security -framework SecurityInterface \
  -Xlinker -ObjC -o "$exe"
codesign --force --sign - "$scratch/Arc Reborn.app"
identifier="$(python3 -c 'import hashlib,sys; print("".join("abcdefghijklmnop"[int(i,16)] for i in hashlib.sha256(sys.argv[1].encode()).hexdigest()[:32]))' "$fixture")"
export BROWSER_NATIVE_TEST_DATA="$scratch/profile" BROWSER_EXTENSION_TEST_ID="$identifier" BROWSER_EXTENSION_TEST_PLACEMENT=1
mkdir -m 700 "$BROWSER_NATIVE_TEST_DATA"
status=0
"$exe" --disable-component-update "--load-extension=$fixture" || status=$?
if [[ -f "$BROWSER_NATIVE_TEST_DATA/latency.json" ]]; then cat "$BROWSER_NATIVE_TEST_DATA/latency.json"; fi
exit "$status"
