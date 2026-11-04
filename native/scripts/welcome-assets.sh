#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
native_root="$(cd "$(dirname "$0")/.." && pwd)"
destination="${1:?Welcome resource directory required}"
mkdir -p "$destination"
cp "$native_root/Resources/Welcome/arrival.mp3" "$destination/"
# AppKit draws the PNG layers reliably inside both Chromium and the preview.
for ribbon in 01-ribbon-right 02-ribbon-arch 03-ribbon-sweep; do
  /usr/bin/sips -s format png "$native_root/../design/app-icon/ArcReborn.icon/Assets/$ribbon.svg" \
    --out "$destination/$ribbon.png" >/dev/null
done
