# Canonical MyDock build baseline

Recorded **3 October 2026** (Europe/Warsaw), after adding accessible Clear/Frosted Liquid Glass controls and correcting the rounded Dock panel backing. Source of truth remains `Sources/MyDock/`; canonical app remains **`build/MyDock.app`**.

## Current behavior

Settings → Appearance now exposes **Clear glass** and **Frosted glass** quick styles, an immediate Glass clarity switch and the existing Tint strength adjustment. These use native clear and regular Liquid Glass on macOS 26 and later, with the existing frosted fallback on earlier systems. Material raw values, global/profile scope and Undo remain intact. Reduce Transparency and increased contrast retain accessible rounded surfaces.

The whole-Dock SwiftUI shadow is removed. The shared material clips to its rounded shape, and the transparent native host masks effect/backing layers to matching continuous corners with no extra shadow. The mask radius updates on profile/appearance changes. Bottom/side geometry and magnification bounds remain unchanged.

The adaptive widget redesign is preserved: independent semantic layout and Accent/Soft/Mono/Outline icon controls, variable horizontal widths, consistent 54-point base height, data-specific micro visualizations, real metrics/empty states, safe legacy decoding and 30 widget families. See [the preceding adaptive release evidence](history/RELEASE_EVIDENCE_PRE_GLASS_DOCK_2026-10-03.md).

## Current verification

- `./BuildMyDock.sh` succeeds for arm64 and x86_64 (98.83s / 99.50s), with macOS 13.0 minimum and SDK 26.4. Strict ad-hoc signature, app/project plist, shell syntax and whitespace checks pass. Source files predate the executable. Canonical app launched; executable path verified (PID 24062). Log `.build/glass-dock-build.log`.

- `./TestMyDock.sh`: **246 reported tests in 19 suites passed**, five explicit opt-ins skipped. Log: `.build/glass-dock-tests.log`.
- **17 isolated renders** cover both glass variants in light/dark, production transparent hosts on bottom/left/right Docks, non-glass materials, Reduce Transparency/increased contrast and appearance controls. The 11 transparent-host captures contain visible content and fully transparent outer corner pixels. Separate AppKit bitmap analysis verifies alpha exactly zero in all four **6×6 pixel corner regions** of every host capture. Directory: `.build/visual-qa/glass-dock-20261003/`; log `.build/glass-dock-render.log`; `corner-alpha-verification.json` records the measurements.
- **Native UI inspection unavailable:** `cua.getState()` reports `Sky Computer Use native pipe startup failed`. NSHostingView exports do not capture native Liquid Glass blur/refraction; actual wallpaper diffusion and reveal/hover inspection remain unverified. The source uses native glass variants, but bitmap evidence does not prove their compositor appearance.

[BUILD_BASELINE.json](BUILD_BASELINE.json) records current hashes, commands and build/launch results. [The focused glass report](history/GLASS_DOCK_2026-10-03.md) records the design, corner measurements and limits. Host: Apple Silicon, macOS 27.0.1 (26A434), Swift 6.3. This is a local ad-hoc development build, not distribution or older-OS/Intel execution qualification.

## Earlier evidence

The preceding adaptive pass's **34 renders** and isolated native layout/icon/CPU/scrolling/mixed Dock observations remain explicitly dated evidence in [the preceding release audit](history/RELEASE_EVIDENCE_PRE_GLASS_DOCK_2026-10-03.md) and [adaptive report](history/ADAPTIVE_WIDGET_PRESENTATION_2026-10-03.md). Earlier 242-test/76-render widget and workspace audits remain historical. Full Xcode UI, VoiceOver, provider permissions, display scale and broader platform acceptance remain open in [implementation status](IMPLEMENTATION_STATUS.md).

No native mutation or synthetic/runtime opt-in, commit, push or publication was performed. The canonical app was quit cleanly before the build. User profiles, drafts, credentials and integrations are preserved.
