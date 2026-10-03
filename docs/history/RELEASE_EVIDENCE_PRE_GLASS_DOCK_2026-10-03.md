# Canonical MyDock build baseline

Recorded **3 October 2026** (Europe/Warsaw), after the adaptive widget presentation redesign and visual corrections. Source of truth remains `Sources/MyDock/`; canonical app remains **`build/MyDock.app`**.

## Current behavior

Widget layout and icon treatment are independent settings. AI Activity offers Compact, Standard and Activity compositions; CPU offers Compact, Meter and Trend. Network, weather, battery, disk, media, clocks, reminders, timers and business metrics use appropriate information patterns. Horizontal widgets have variable widths with a consistent 54-point base height; side Docks use reduced narrow compositions. Hover brightens the surface subtly without magnifying data widgets.

Configuration includes an actual live Dock-sized preview, layout rows that show their real dimensions, compact Accent/Soft/Mono/Outline icon swatches and relevant secondary metrics. The old Live visual-style choice and generic Card size selector are removed from the product UI. Legacy saved styles and widths decode safely; existing provider snapshots, profiles, drafts, integrations and permissions remain connected. Long totals and their units scale as one metric rather than truncating separately.

The library contains **30 widget families**, including Disk Space, Calculator and Quick Checklist from the preceding utility work. Live widgets show only available real metrics; empty states do not invent totals, history or quotas. Illustrative gallery fixtures remain separate from user data.

## Current verification

- `./BuildMyDock.sh` succeeds for arm64 and x86_64. Both slices declare macOS 13.0 minimum and SDK 26.4. Strict ad-hoc signature, app/project plist, generated project, shell syntax and whitespace checks pass. Source files predate the final executable. The target was quit cleanly before rebuilding. Log: `.build/adaptive-widget-build-final.log`.
- `./TestMyDock.sh`: **246 reported tests in 19 suites passed**, with five explicit opt-ins skipped. Includes migration, round trips, geometry/style independence for every widget and real telemetry history regressions. Log: `.build/adaptive-widget-tests.log`.
- **34 final dark/light renders** cover all families’ semantic layouts, mixed Dock rhythm, eight configuration sheets, icon independence, narrow faces, long token totals and four real empty states. Contact sheets and selected full-size images were reviewed. Directory: `.build/visual-qa/adaptive-widgets-final/`; log: `.build/adaptive-widget-render-final.log`.
- Native isolated CUA checks verified AI layout/icon independence, Compact/Outline selection with real usage, CPU Trend/live sampling, bounded configuration scrolling and a mixed bottom Dock with app icons and live widgets. The intermediate canonical AI popover opened and exposed real provider/range/history controls through AX.
- Final canonical app launched from `build/MyDock.app`; its running executable path is verified. **Final CUA binding failed twice with `Sky Computer Use native pipe startup failed`.** Final text scaling and narrow refinements are verified in bitmap exports; the final native UI recheck remains unverified. Native popover arrow/frame screenshots, full Xcode UI, VoiceOver and the broader display/provider/platform matrix remain open.

[BUILD_BASELINE.json](BUILD_BASELINE.json) records hashes, process IDs, commands and distinctions between current checks and older evidence. The [adaptive presentation report](history/ADAPTIVE_WIDGET_PRESENTATION_2026-10-03.md) records design decisions, corrections and validation limits. Host: Apple Silicon, macOS 27.0.1 (26A434), Swift 6.3. This is a local ad-hoc development build, not a distribution or older-OS/Intel execution qualification.

## Earlier evidence

The preceding **242-test/76-render** widget pass and its Live/Color/Soft/Mono interpretation are historical and superseded. See [preceding release evidence](history/RELEASE_EVIDENCE_PRE_ADAPTIVE_WIDGETS_2026-10-03.md) and [prior widget report](history/WIDGET_PRESENTATION_AND_UTILITIES_2026-10-01.md). Earlier installed-app discovery, accessibility, panel runtime and workspace audits remain dated evidence, not rerun scenarios for this source.

Remaining provider, permission, display, performance and distribution acceptance is in [implementation status](IMPLEMENTATION_STATUS.md). No native mutation or synthetic/runtime opt-in, commit, push or publication was performed during this pass. Validation bundles remain under `.build/visual-qa/`; the final validation app is quit.
