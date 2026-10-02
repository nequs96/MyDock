# Canonical MyDock build baseline

Recorded 30 September 2026 after repository consolidation.

## Development target

- Source of truth: `Sources/MyDock/` in this repository.
- Canonical local application: **`build/MyDock.app`**.
- Build: `./BuildMyDock.sh`, after quitting the running app.
- Launch: `open build/MyDock.app`.
- Temporary validation output: `.build/visual-qa/`; it is not a replacement development baseline.

The canonical app includes the latest premium redesign, code/performance audit, disappearing-Dock repairs, sharp widget previews, compact gallery size selection, replacement-mode recovery and corrected resize grip. All app source files were compared with the last verified replacement-build manifest and remain identical. Existing user changes and editor debugger configurations were preserved.

## Verification

- Default build script successfully produces one universal app at the canonical path.
- Both arm64 and x86_64 architectures are present; minimum deployment remains macOS 13.
- Strict ad-hoc signature and Info.plist validation pass.
- Canonical executable SHA-256: `c9182523a6d021681f9fae5c28c79280b4e2996df7687399ed98f4db9dda20d5`. It is byte-for-byte identical to the latest verified `MyDockReplacement` executable.
- The canonical app was launched through native app controls. Its floating Dock and resize control are present, with the existing replacement mode and user-selected size preserved.
- Attempting to rebuild while the canonical app is running is rejected before any executable modification. The before/after hash remains identical.
- Shell syntax and editor JSON checks pass. CI and the default VS Code build task target `build/MyDock.app`.
- The unchanged app-code baseline has **215 registered tests in 14 suites reported passing**, with three opt-ins skipped, and a separately passing isolated real-panel test. The 49-layout render matrix and native gallery/resizing/restoration checks are recorded in [the preceding verification](history/REPLACEMENT_MODE_AND_GALLERY_VERIFICATION_2026-09-30.json). App tests were not repeated for this filesystem/documentation consolidation.

The current baseline manifest is [BUILD_BASELINE.json](BUILD_BASELINE.json). Build and running-app guard logs are in `.build/canonical-build.log` and `.build/canonical-running-guard.log`.

## Repository cleanup and recovery

`build/` contains one application. Dated reports and their verification manifests are grouped under [history](history/README.md), with a [documentation index](README.md) for active guides. `.DS_Store` is ignored. Obsolete candidate/preview apps, old release staging, experimental compiler artifacts, logs, visual renders and prior source snapshots were moved outside the repository. Useful active SwiftPM/editor caches remain in ignored `.build/`.

The recoverable archive is `../dockX-archive/2026-09-30-canonical-baseline/`. It contains ZIPs for legacy builds and local artifacts, the full source tree before cleanup, a working-tree patch/status, source hashes, relocation mapping and archive verification. Source code, saved profiles and credentials were preserved. No Git reset or commit was performed.

## Qualification limits

This is a local ad-hoc signed development app. Developer ID signing, notarization, full-Xcode App Intents metadata qualification, actual Intel/older-macOS execution and broader system/provider acceptance remain open in [implementation status](IMPLEMENTATION_STATUS.md). Existing visual/system limitations are retained in [the replacement/gallery report](history/REPLACEMENT_MODE_AND_GALLERY_2026-09-30.md). Historical build names are evidence labels; use the canonical path for future development.
