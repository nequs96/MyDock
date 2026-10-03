# Canonical MyDock build baseline

Recorded **3 October 2026** (Europe/Warsaw), after installing the Dock interaction and Everyday Tools source. Source of truth remains `Sources/MyDock/`; canonical app remains **`build/MyDock.app`**.

## Current behavior

Running app menus expose normal Quit App. Minimized-window tiles and known app windows expose Close Window using the native close button and existing Accessibility access. Direct resize uses a temporary profile-scoped preview, retains the hosting root and live monitors, caches icon sources across fractional sizes, and saves once on release.

Appearance exposes Clear/Frosted Liquid Glass and independent **0–100% Glass opacity**, preserving profile/global scope, tint, Undo, older snapshots and accessible opaque fallbacks. Rounded material/native-host masks retain transparent corners without the previous rectangular outer shadow. Embedded Settings uses visible wrapping section buttons. Behavior offers **Fade, Slide, Gentle grow**, an off switch and Preview; Reduce Motion suppresses effects. Grow keeps the viewport constant to avoid reflow during the effect.

The adaptive widget system remains intact: semantic compositions, variable widths, independent layout/icon treatments and real metrics/empty states. The library now has **35 families**, including File Shelf, Text Snippets, Quick Links, Unit Converter and Color Picker. Existing user profiles, drafts, integrations and permissions are preserved.

## Current verification

- The user quit MyDock normally; process absence was verified before `./BuildMyDock.sh`. The canonical universal build succeeds (latest cached steps: 0.29s arm64 / 0.28s x86_64). Both slices declare macOS 13.0 minimum and SDK 26.4. Strict ad-hoc signature and app plist checks pass. Log `.build/utility-expansion-canonical-build.log`.
- Final source and test hashes match the validated interaction working tree: **258 reported tests in 20 suites passed**, five explicit opt-ins skipped. No source/test changes required rerunning the same suite. Log `.build/dock-interaction-tests.log`. Source inputs predate the final executable.
- **17 interaction renders** cover light/dark opacity levels, Settings navigation and the minimum embedded window; all four 6×6 corner regions of six native-host captures have alpha exactly zero. Directory `.build/visual-qa/dock-interaction-20261003/`. [The interaction report](history/DOCK_INTERACTION_2026-10-03.md) records inspections and limits.
- **32 Everyday Tools renders** and their isolated persistence/provider tests remain evidence for the unchanged source. [Tools report](history/EVERYDAY_TOOLS_2026-10-03.md), [validation record](history/EVERYDAY_TOOLS_VALIDATION_2026-10-03.json).
- Canonical app launched from `build/MyDock.app`; exact executable path verified (PID 28856). **Final CUA binding still fails with `Sky Computer Use native pipe startup failed`.** Native Close/save dialogs, drag frame pacing, reveal interruption, Finder/AirDrop/sampling, keyboard/VoiceOver and actual glass blur/refraction remain unverified. Bitmap exports do not prove native compositor appearance or animation smoothness.

[BUILD_BASELINE.json](BUILD_BASELINE.json) records current source/test/app hashes and distinguishes current versus historical evidence. Host: Apple Silicon, macOS 27.0.1 (26A434), Swift 6.3. This is a local ad-hoc development build, not distribution or older-OS/Intel execution qualification.

## Earlier evidence

The preceding glass build's 246-test/17-render verification is preserved in [the preceding release audit](history/RELEASE_EVIDENCE_PRE_DOCK_INTERACTION_2026-10-03.md) and [glass report](history/GLASS_DOCK_2026-10-03.md). Earlier adaptive 34-render/native observations and 242-test/76-render reports remain dated evidence. Remaining acceptance is in [implementation status](IMPLEMENTATION_STATUS.md).

The earlier clean-quit blocker is resolved. No running bundle was overwritten, force termination, native mutation/synthetic runtime opt-in, commit, push or publication occurred. Disposable validation bundles remain under `.build/visual-qa/`.
