# Canonical MyDock development baseline

Recorded on **4 October 2026**, after the [completion handoff](history/CLAUDE_COMPLETION_HANDOFF_2026-10-04.md) and its verification and fix wave were executed. Source remains in `Sources/MyDock/`. The canonical app remains **`build/MyDock.app`**, built from git `d0ad2d4`. Per-item outcomes are recorded in [the execution ledger](history/EXECUTION_LEDGER_2026-10-03.md).

## What this baseline contains

- **Package A (reliability):**
  - The coordinator loader API order is fixed.
  - AI Activity snapshots now carry their source scope. Previously, every real AI Activity refresh was rejected.
  - Previous-session work was verified: AI source-scope and in-flight attribution, Copilot last-good retention, App Folder installed-copy identity, and default-production network guards in isolated validation.
- **Package B (native):**
  - Calendar boundary fixture added.
  - ZIP short-stream tooling case added.
  - Corrected interaction and uninstall docs.
  - Alarm generations, Calendar selection, ZIP checks and the update-check guard were verified.
- **Package C (product):**
  - Settings "Editing: This Dock / App defaults" scope.
  - Exact-byte diagnostics preview.
  - Alarm edit flow.
  - Timing and status copy.
  - Normalized-URL duplicate guards.
  - AI Limits stale presentation with the original success time.
  - Corrected backup help text: cached provider readings are always excluded.
- **Independent verification:** Codex `gpt-6.1-sol` auditor X1 and render agent X2 checked the work.
- **Fixes from that audit:**
  - Appearance Undo now refuses to act outside the displayed scope.
  - Quick Style thumbnails follow the selected Dock's colour.
  - The reveal dwell rechecks system overview before showing the Dock.
  - Weather Forecast keeps its temperature.
  - Stale badges sit inside the rounded corner, with one badge per AI Limits face.
  - Narrow Stock/Watchlist/Disk side faces, Weather pickers, the Alarm edit row and the Reminders header are fixed.
  - The battery shows a display name, collection counts use the correct singular or plural, and the World Clock date fits.
  - The QA fixtures are honest.

## Current verification

| Check | Result |
|---|---|
| `./TestMyDock.sh` (isolated, outside any agent sandbox) | **506 tests in 64 suites passed, 0 failed, 5 explicit opt-in skips.** Log: `.build/orchestrate-c2/test-badgefix.log` |
| Python tooling (`PYTHONDONTWRITEBYTECODE=1`) | **11 passed** |
| `git diff --check` / Xcode project | Clean. `./GenerateXcodeProject.sh` regenerated the project, and every Swift source and test is listed. |
| Canonical build | MyDock was quit normally and its exit verified. `./BuildMyDock.sh` exited 0. |
| Executable | SHA-256 `d700e1b56fcf8d0f6b79289f413d2761d99c4334382edfdf13bc3b21ca7d6f39`. Universal x86_64 + arm64; minimum macOS 13.0; SDK 26.4; version 0.1.0 (1). |
| Signature and metadata | Strict deep ad-hoc signature valid; no TeamIdentifier; plist lint OK. **No `Metadata.appintents`** (CLI build). |
| Isolated launch | The exact canonical executable ran with a fresh `MYDOCK_VALIDATION_ROOT` for 12 s, then quit normally with status 0. It wrote only `ApplicationSupport/state.json` and `MyDock/instance.lock` inside that root. This is bounded launch/quit evidence, not a disposable-user trace. |
| Renders | Isolated DEBUG exports: Codex X2 produced 325 PNGs covering all 35 families, both appearances and side Docks. The coordinator rendered the integrated tree in the ADAPTIVE and SURFACES modes. The images were inspected. |
| Relaunch | Your normal `build/MyDock.app` was relaunched (PID 78338). |

The source fingerprint is `347cd61b…a37138`; see [BUILD_BASELINE.json](BUILD_BASELINE.json).

## Not verified

- **Native acceptance has not been run.** H1–H9 cover 40 procedures: window and Quit with unsaved documents, resize, glass on wallpaper, motion and Mission Control, small windows and VoiceOver, Finder, AirDrop and Trash, permissions and preference restoration, failure traces, and release.
- **Live provider accounts were not used.**
- **No Xcode build, signing or notarization.** Full Xcode is absent, so Focus discovery and CI or distribution qualification are also unverified.
- **Calendar rendering is partial.** Its production empty and ongoing states have no fixture hook, so they were rendered through presentation fixtures only.
- **No real performance or energy measurements.**

The previous baseline is preserved in [history/RELEASE_EVIDENCE_PRE_COMPLETION_HANDOFF_2026-10-04.md](history/RELEASE_EVIDENCE_PRE_COMPLETION_HANDOFF_2026-10-04.md). Nothing was pushed or published.
