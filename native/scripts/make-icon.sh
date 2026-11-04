#!/bin/bash
# Compile the layered Icon Composer document, including native Liquid Glass
# renditions and the fallback ICNS for macOS versions before Liquid Glass.
set -euo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON_SOURCE="$NATIVE_ROOT/../design/app-icon/ArcReborn.icon"
DESTINATION="${1:-$NATIVE_ROOT/Resources}"
BUILD_ROOT="${BROWSER_BUILD_ROOT:-$NATIVE_ROOT/build}"
mkdir -p "$BUILD_ROOT" "$DESTINATION"
STAGE="$(mktemp -d "$BUILD_ROOT/icon-compile.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
xcrun actool --compile "$STAGE" --platform macosx \
  --minimum-deployment-target 13.0 --app-icon ArcReborn \
  --output-partial-info-plist "$STAGE/partial.plist" "$ICON_SOURCE" \
  > "$STAGE/compilation.plist"
for resource in ArcReborn.icns Assets.car; do
  [[ -s "$STAGE/$resource" ]] || { echo "Missing compiled icon resource: $resource" >&2; exit 1; }
done
/usr/bin/python3 - "$STAGE/partial.plist" "$NATIVE_ROOT/Resources/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    generated = plistlib.load(source)
with open(sys.argv[2], 'rb') as source:
    bundle = plistlib.load(source)
for key in ('CFBundleIconFile', 'CFBundleIconName'):
    if generated.get(key) != bundle.get(key):
        raise SystemExit(f'{key} must match the Icon Composer asset name')
PY
cp "$STAGE/ArcReborn.icns" "$STAGE/Assets.car" "$DESTINATION/"
echo "Compiled Arc Reborn Liquid Glass icon: $DESTINATION"
