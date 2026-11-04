#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export BROWSER_BUILD_ROOT="${BROWSER_BUILD_ROOT:-$NATIVE_ROOT/build/development}"
export BROWSER_ALLOW_ADHOC=1 BROWSER_SIGN_IDENTITY=-
export BROWSER_NATIVE_TEST_DATA="${BROWSER_NATIVE_TEST_DATA:-$BROWSER_BUILD_ROOT/profile}"
unset BROWSER_RELEASE_BUILD
"$NATIVE_ROOT/scripts/build.sh"
if [[ "${1:-}" != '--build-only' ]]; then
  exec "$BROWSER_BUILD_ROOT/Arc Reborn.app/Contents/MacOS/Arc Reborn"
fi
