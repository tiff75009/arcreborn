#!/bin/bash
set -euo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${BROWSER_BUILD_ROOT:-$NATIVE_ROOT/build}"
CMAKE_BUILD="$BUILD_ROOT/cmake"
APP_BUNDLE="$BUILD_ROOT/Arc Reborn.app"
PYTHON_BIN="/usr/bin/python3"
CMAKE_BIN="${CMAKE_BIN:-$(command -v cmake || true)}"
[[ -x "$CMAKE_BIN" ]] || { echo "Install CMake (brew install cmake)." >&2; exit 1; }
# Persist a real signing identity across builds so Keychain can recognize Arc Reborn.
# No certificate or private key is created/exported, and Keychain ACLs are untouched.
SIGN_IDENTITY="${BROWSER_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning | "$PYTHON_BIN" -c 'import re,sys; rows=re.findall(r"^\s*\d+\) ([A-F0-9]{40}) \"([^\n]+)\"",sys.stdin.read(),re.M); values=[sha for sha,name in rows if name.startswith("Developer ID Application:")] or [sha for sha,name in rows if name.startswith("Apple Development:")]; print(values[0] if len(values)==1 else "")')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  if [[ "${BROWSER_ALLOW_ADHOC:-0}" != "1" ]]; then
    echo 'Set BROWSER_SIGN_IDENTITY to a valid signing identity. Ad hoc builds require explicit BROWSER_ALLOW_ADHOC=1 and can repeat Keychain prompts after rebuilds.' >&2
    exit 1
  fi
  SIGN_IDENTITY='-'
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  echo 'This pinned CEF distribution targets Apple Silicon (arm64).' >&2
  exit 1
fi
"$PYTHON_BIN" "$NATIVE_ROOT/scripts/fetch-cef.py"
CEF_ROOT="$(cat "$NATIVE_ROOT/vendor/cef-path.txt")"
SOURCE_FRAMEWORK="$CEF_ROOT/Release/Chromium Embedded Framework.framework"
if [[ -z "${BROWSER_ENGINE_FRAMEWORK:-}" ]]; then
  BROWSER_ENGINE_FRAMEWORK="$("$PYTHON_BIN" "$NATIVE_ROOT/scripts/engine.py" fetch)"
fi
if [[ -n "${BROWSER_ENGINE_FRAMEWORK:-}" ]]; then
  PRIVATE_ENGINE_FINGERPRINT="$("$PYTHON_BIN" "$NATIVE_ROOT/scripts/engine-framework-fingerprint.py" "$BROWSER_ENGINE_FRAMEWORK" "$SOURCE_FRAMEWORK")"
  SOURCE_FRAMEWORK="$BROWSER_ENGINE_FRAMEWORK"
fi
SPARKLE_ROOT="$("$PYTHON_BIN" "$NATIVE_ROOT/scripts/fetch-sparkle.py")"
SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path)"
"$CMAKE_BIN" -S "$NATIVE_ROOT" -B "$CMAKE_BUILD" -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT="$SDK_ROOT" -DUSE_SANDBOX=ON -DCEF_ROOT="$CEF_ROOT"
BUILD_JOBS="${BROWSER_BUILD_JOBS:-8}"
if [[ "${1:-}" == '--wrapper-only' ]]; then
  "$CMAKE_BIN" --build "$CMAKE_BUILD" --target BrowserHelper --parallel "$BUILD_JOBS"
  exit 0
fi
if [[ "${BROWSER_REBUILD_ICON:-${BROWSER_RELEASE_BUILD:-0}}" == "1" || ! -s "$NATIVE_ROOT/Resources/Assets.car" ]]; then
  "$NATIVE_ROOT/scripts/make-icon.sh"
fi
"$CMAKE_BIN" --build "$CMAKE_BUILD" --target BrowserBridge BrowserHelper --parallel "$BUILD_JOBS"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Frameworks" "$APP_BUNDLE/Contents/Resources"
xcrun swiftc -O -g -swift-version 5 -target arm64-apple-macosx13.0 -sdk "$SDK_ROOT" \
  -import-objc-header "$NATIVE_ROOT/Bridge/BrowserBridge.h" \
  "$NATIVE_ROOT"/Sources/*.swift \
  "$CMAKE_BUILD/libBrowserBridge.a" "$CMAKE_BUILD/libcef_dll_wrapper/libcef_dll_wrapper.a" \
  -lc++ -framework Cocoa -framework IOSurface -framework Security -framework SecurityInterface \
  -F "$SPARKLE_ROOT" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -Xlinker -ObjC -o "$APP_BUNDLE/Contents/MacOS/Arc Reborn"
cp "$NATIVE_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
# Contributor builds cannot be overwritten by official updates.
if [[ "${BROWSER_RELEASE_BUILD:-0}" != "1" ]]; then
  /usr/libexec/PlistBuddy -c "Add :ArcRebornDevelopmentBuild bool true" "$APP_BUNDLE/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.browser.native.development" "$APP_BUNDLE/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Arc Reborn Dev" "$APP_BUNDLE/Contents/Info.plist"
fi
/usr/bin/ditto "$SPARKLE_ROOT/Sparkle.framework" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
"$NATIVE_ROOT/scripts/sign-sparkle.sh" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" "$SIGN_IDENTITY"
/usr/bin/ditto "$NATIVE_ROOT/Resources" "$APP_BUNDLE/Contents/Resources"
"$NATIVE_ROOT/scripts/welcome-assets.sh" "$APP_BUNDLE/Contents/Resources/Welcome"
cp "$CEF_ROOT/LICENSE.txt" "$APP_BUNDLE/Contents/Resources/CEF-LICENSE.txt"
cp "$NATIVE_ROOT/../LICENSE" "$APP_BUNDLE/Contents/Resources/MPL-2.0.txt"
cp "$NATIVE_ROOT/../NOTICE.md" "$APP_BUNDLE/Contents/Resources/NOTICE.md"
cp "$NATIVE_ROOT/Engine/licenses/Chromium.txt" "$APP_BUNDLE/Contents/Resources/Chromium-LICENSE.txt"
FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Chromium Embedded Framework.framework"
FRAMEWORK_STAMP="$BUILD_ROOT/cef-framework.sha1"
PIN_SHA="$($PYTHON_BIN -c 'import json,sys; print(json.load(open(sys.argv[1]))["archive"]["sha1"])' "$NATIVE_ROOT/Resources/cef-version.json")"
PIN_SHA="${PRIVATE_ENGINE_FINGERPRINT:-$PIN_SHA}"
if [[ ! -d "$FRAMEWORK" || ! -f "$FRAMEWORK_STAMP" || "$(cat "$FRAMEWORK_STAMP")" != "$PIN_SHA" ]]; then
  # Stage a complete framework so removed files cannot survive an engine change.
  STAGED_FRAMEWORK="$(mktemp -d "$BUILD_ROOT/cef-stage.XXXXXX")/Chromium Embedded Framework.framework"
  /usr/bin/ditto "$SOURCE_FRAMEWORK" "$STAGED_FRAMEWORK"
  if [[ -d "$FRAMEWORK" ]]; then
    PREVIOUS_FRAMEWORK="$(mktemp -d "$BUILD_ROOT/cef-previous.XXXXXX")/Chromium Embedded Framework.framework"
    mv "$FRAMEWORK" "$PREVIOUS_FRAMEWORK"
  fi
  mv "$STAGED_FRAMEWORK" "$FRAMEWORK"
  FRAMEWORK_COPIED=1
fi
FRAMEWORK_SIGNER_STAMP="$BUILD_ROOT/cef-framework.signer"
if [[ "${FRAMEWORK_COPIED:-0}" == "1" || ! -f "$FRAMEWORK_SIGNER_STAMP" || "$(cat "$FRAMEWORK_SIGNER_STAMP")" != "$PIN_SHA:$SIGN_IDENTITY" ]]; then
  while IFS= read -r -d '' library; do /usr/bin/codesign --force --sign "$SIGN_IDENTITY" "$library"; done < <(find "$FRAMEWORK/Libraries" -type f -name '*.dylib' -print0)
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" "$FRAMEWORK"
  printf '%s\n' "$PIN_SHA" > "$FRAMEWORK_STAMP"
  printf '%s\n' "$PIN_SHA:$SIGN_IDENTITY" > "$FRAMEWORK_SIGNER_STAMP"
fi
for suffix in '' ' (GPU)' ' (Renderer)' ' (Plugin)' ' (Alerts)'; do
  HELPER_NAME="Arc Reborn Helper$suffix"
  HELPER_BUNDLE="$APP_BUNDLE/Contents/Frameworks/$HELPER_NAME.app"
  mkdir -p "$HELPER_BUNDLE/Contents/MacOS"
  cp "$CMAKE_BUILD/BrowserHelper" "$HELPER_BUNDLE/Contents/MacOS/$HELPER_NAME"
  "$PYTHON_BIN" - "$HELPER_BUNDLE/Contents/Info.plist" "$HELPER_NAME" "$suffix" <<'PY'
import plistlib,sys
suffix = sys.argv[3].strip(' ()').lower()
info = {'CFBundleExecutable':sys.argv[2], 'CFBundleName':sys.argv[2], 'CFBundleIdentifier':'local.browser.native.helper' + ('.'+suffix if suffix else ''), 'CFBundlePackageType':'APPL', 'CFBundleVersion':'1', 'CFBundleShortVersionString':'0.1.0', 'LSMinimumSystemVersion':'13.0', 'LSUIElement':True, 'LSFileQuarantineEnabled':True, 'NSSupportsAutomaticGraphicsSwitching':True, 'LSEnvironment':{'MallocNanoZone':'0'}}
with open(sys.argv[1],'wb') as output: plistlib.dump(info,output)
PY
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" "$HELPER_BUNDLE"
done
# Local development signing uses the selected stable identity without Hardened
# Runtime exceptions. CEF sandbox and Keychain encryption remain active.
# Public distribution still requires a Developer ID + notarization pipeline.
/usr/bin/codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
printf 'Built and locally signed: %s\n' "$APP_BUNDLE"
