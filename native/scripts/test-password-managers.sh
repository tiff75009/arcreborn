#!/bin/bash
# Exercise password consent and exclusive providers in a disposable CEF profile.
set -euo pipefail
native="$(cd "$(dirname "$0")/.." && pwd)"
build="${BROWSER_BUILD_ROOT:-$native/build/development}"
app="$build/Arc Reborn.app"
[[ -d "$app" && -f "$build/cmake/libBrowserBridge.a" ]] || {
  echo 'Build the development app first, or set BROWSER_BUILD_ROOT.' >&2
  exit 1
}
scratch="$(mktemp -d "$native/build/password-runtime.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
cp -cR "$app" "$scratch/Arc Reborn.app"
exe="$scratch/Arc Reborn.app/Contents/MacOS/Arc Reborn"
sources=()
for source in "$native"/Sources/*.swift; do
  [[ "$(basename "$source")" == main.swift ]] || sources+=("$source")
done
xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 \
  -import-objc-header "$native/Bridge/BrowserBridge.h" "${sources[@]}" "$native/Tests/PasswordManagerHarness.swift" \
  "$build/cmake/libBrowserBridge.a" "$build/cmake/libcef_dll_wrapper/libcef_dll_wrapper.a" \
  -lc++ -framework Cocoa -framework IOSurface -framework Security -framework SecurityInterface \
  -F "$native/vendor/sparkle-2.10.1" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -Xlinker -ObjC -o "$exe"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.browser.password-manager-test' "$scratch/Arc Reborn.app/Contents/Info.plist"
codesign --force --sign - "$scratch/Arc Reborn.app"
PASSWORD_RUNTIME_APP="$scratch/Arc Reborn.app" PASSWORD_MANAGER_FIXTURES="$native/Tests/Fixtures/password-managers" \
  node "$native/Tests/password-managers.mjs"
