#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# Run the complete local candidate pipeline; the monitor only reads its journal.
set -euo pipefail
native="$(cd "$(dirname "$0")/.." && pwd)"
root="${1:?Usage: check-performance-candidate.sh ENGINE_ROOT [JOBS] [SAMPLE_MP4]}"
jobs="${2:-4}"
work="${ARC_PERF_WORK:-$native/build/perf-check}"
mkdir -p "$work"
exec >>"$work/candidate.log" 2>&1
mark() { printf '\n@arc-build %s %s %s %s\n' "$(date +%s)" "$$" "$jobs" "$1"; }
trap 'rc=$?; if (( rc != 0 )); then mark stopped; fi' EXIT
mark engine
python3 -u "$native/scripts/performance-engine.py" --root "$root" --jobs "$jobs"
mark app
unset TMPDIR
export BROWSER_ENGINE_FRAMEWORK="$root/chromium_git/chromium/src/out/Arc_Performance_arm64/Chromium Embedded Framework.framework"
export BROWSER_BUILD_ROOT="$work/candidate-dev"
"$native/scripts/dev.sh" --build-only
export BROWSER_SMOKE_APP="$BROWSER_BUILD_ROOT/Arc Reborn.app"
mark media
BROWSER_MEDIA_TEST_MATRIX=1 node "$native/Tests/media-playback.mjs" "${@:3:1}" >"$work/candidate-media.json"
mark extensions
if ! "$native/scripts/test-extension-placement.sh" >"$work/candidate-extensions.log" 2>&1; then
  tail -12 "$work/candidate-extensions.log" >&2
  exit 1
fi
mark speedometer
node "$native/Tests/speedometer.mjs" "$BROWSER_SMOKE_APP" 10 >"$work/candidate-speedometer.json"
mark complete
