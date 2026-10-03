# Liquid Glass and rounded panel corners

Recorded 3 October 2026, Europe/Warsaw. Source: `Sources/MyDock/`. Canonical app: `build/MyDock.app`.

## Changes

Clear glass and Frosted glass are visible in Settings → Appearance → Quick styles. A separate Glass clarity segmented control changes between native clear and regular Liquid Glass while preserving size, radius, theme and profile/global scope. Quick presets set a low tint (Clear: 0; Frosted: 0.02); the existing Tint strength slider permits further adjustment. The existing `liquidGlass` and `liquidGlassClear` persistence raw values are preserved; Regular is relabeled Frosted in the interface. There is no profile migration or reset.

The live Dock previously combined a shadowless, transparent NSPanel with a SwiftUI shadow on the entire rectangular hosting view. The outer SwiftUI shadow has been removed. The material clips to its rounded shape, and `DockSurfaceHostingView` applies a transparent, continuous rounded native layer mask with no shadow. Its radius updates with profile/appearance changes. This also covers native material backing layers. No panel geometry or hover magnification calculations changed.

The glass implementations use Apple's native SwiftUI glass API on macOS 26 and later and keep the existing older-system frosted fallback. Reduce Transparency renders an opaque rounded accessible surface. Apple's [glass API](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) and [clear variant](https://developer.apple.com/documentation/swiftui/glass/clear) informed the implementation.

## Verification

- Canonical target quit through `NSRunningApplication.terminate` and absence verified before rebuilding. `./BuildMyDock.sh` completes both slices (arm64 98.83s, x86_64 99.50s); strict signature, app/project plist, shell syntax and whitespace checks pass. Source inputs predate the executable. macOS minimum 13.0, SDK 26.4. Canonical `build/MyDock.app` launched; process executable path verified (PID 24062). Log `.build/glass-dock-build.log`.

- `./TestMyDock.sh`: 246 tests in 19 suites pass; five explicit opt-ins skipped. Log `.build/glass-dock-tests.log`.
- `MYDOCK_RENDER_QA=… MYDOCK_GLASS_QA=1 .build/swiftpm-test/arm64-apple-macosx/debug/MyDock`: 17 isolated bitmap exports. The render harness uses an isolated non-mutating ProfileStore and the production native hosting class. Log `.build/glass-dock-render.log`; directory `.build/visual-qa/glass-dock-20261003/`.
- Four wallpaper-backed glass fixtures cover clear/regular × dark/light. Eleven transparent-host fixtures cover both glass finishes/themes, left/right side positions and Frosted/Solid/Dark materials. The harness requires nonempty visible content and transparent outer corner pixels. A separate AppKit bitmap analysis confirms alpha exactly 0 in all four 6×6 pixel corner regions of all 11 captures; results `corner-alpha-verification.json`.
- Remaining exports cover Reduce Transparency with increased contrast and the appearance controls. Settings and selected Dock/corner/fallback exports were visually inspected.

## Limits

`cua.getState()` reports `Native apps: Error: Sky Computer Use native pipe startup failed`. A final native desktop screenshot or control/reveal/hover interaction cannot be obtained in this session. NSHostingView bitmap exports do not capture the native Liquid Glass compositor's blur/refraction, so the two glass finishes look similar in those exports. These images verify content, geometry, control placement and corner alpha, not actual wallpaper diffusion. Native wallpaper compositing, reveal/hover transitions, display scales and older OS/Intel runtime acceptance remain open.

Previous adaptive widget native observations and 34 renders remain dated evidence in [the preceding release audit](RELEASE_EVIDENCE_PRE_GLASS_DOCK_2026-10-03.md). The current pass preserves the adaptive widget source changes, user profiles/drafts, integrations and permissions. No credential access, native mutation opt-in, commit, push or publication was performed.
