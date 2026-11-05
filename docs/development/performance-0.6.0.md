# Arc Reborn 0.6.0: optimized Chromium / V8 runtime

## What changed

Engine `156.0.8078.80-arcreborn.5` is a complete release rebuild of the pinned
Chromium/CEF sources and all seven Arc Reborn patches. It replaces `.4`, which
was marked Release but still used `is_official_build=false`, V8 debug code and
always-on development checks. The new build uses `is_official_build=true`,
`chrome_pgo_phase=2`, Chromium and V8 optimization profiles matching the pinned
revision, and disables development-only DCHECK/debug-code paths.

Production CHECKs, the V8 sandbox, optimizing compilers, the Chromium sandbox
and certificate validation remain enabled. ThinLTO is disabled to keep peak
linker memory within the build Mac's limits. No flags detect a benchmark site
or give it special treatment. No user agent workaround is involved.

## Measurement

Test machine: Apple M4, 10 CPU cores, 16 GB RAM, macOS. Speedometer **3.1**,
all 20 suites, **10 iterations**. Higher scores are better.

| Measurement | Score | Scope |
| --- | ---: | --- |
| Previous complete browser, user-provided result | 8.21 ± 0.27 | Existing user profile |
| Old `.4` CEF, isolated diagnostic harness | 8.56 ± 0.25 | Same minimal harness as stock comparison |
| Stock optimized CEF, same upstream version | 52.3 ± 4.0 | Diagnostic comparison only, not shipped |
| Complete Arc Reborn app with new patched engine | **51.79 ± 5.02** | Visible 1264 × 802 viewport, disposable profile |

The complete-app score is about 6.3 times the original reported score. That is
**a benchmark score ratio, not a claim that every website loads 6.3 times faster**.
The old user profile and new disposable profile differ. The matched minimal
harness comparison isolates the engine-build problem; the complete-app result
confirms that the improvement also exists with the native shell and all patches.

The full candidate run includes its slower first iteration (31.96); it was not
dropped to improve the result. Power, temperature, background activity, profile
and extensions affect scores. Measure repeated runs under comparable conditions
before comparing browsers or machines.

## Regression checks

The complete app decoded video and audio, with advancing playback, for H.264/AAC
MP4, MSE H.264/AAC, HLS fMP4, VP8, VP9, AV1, HEVC Main and HEVC Main 10. This does
not claim support for every codec, DRM provider or WebRTC encoder.

The extension-placement check opened the same fixed-width popup at both display
edges, validating direction, bounds and equal width. Native navigation, context
menus, extension lifecycle and DevTools patches remain in the seven-patch stack.

See [engine.md](engine.md) for the disposable-profile benchmark, media and popup
commands. The binary archive contains `engine.json` provenance and is pinned by
SHA-256. Contributors use this archive without recompiling Chromium; source
rebuilds and the optional local build dashboard remain available.
