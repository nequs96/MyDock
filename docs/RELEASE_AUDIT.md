# Canonical MyDock development baseline

Recorded on **5 October 2026** after the redesign: RD-01–RD-11, then fix waves FX-01–FX-10, follow-ups FU-S/FU-G/FU-W and T2. Source remains in `Sources/MyDock/`. The canonical app remains **`build/MyDock.app`**. The per-package record is [the redesign ledger](history/REDESIGN_LEDGER_2026-10-04.md). The pre-redesign baseline is preserved in [history/RELEASE_EVIDENCE_PRE_REDESIGN_2026-10-05.md](history/RELEASE_EVIDENCE_PRE_REDESIGN_2026-10-05.md).

## What this baseline adds

- **Design system:** `UI/DesignSystem` (grouped forms, glass modules, pill buttons, size pager, style swatches) and `DockDesign` tokens are used by the Dock, widgets, the Add Item gallery and Settings.
- **Dock surface:** five quick styles (Clear, Glass, Frosted, Solid, Midnight), Liquid Glass with a frosted fallback before macOS 26, and reorder and morph motion that respects Reduce Motion.
- **Widgets:**
  - Popouts show the reading first, with settings behind one disclosure, one refresh control and a centred hero. Non-numeric states use a calm status style.
  - Mono is the creation default, and the Auto accent is neutral at rest; colour shows only for active state (T2).
  - Calendar events carry their calendar colour, which is runtime-only and never persisted.
- **Add Item window:** Widgets, Apps and More tabs, a detail view with a size pager, floating previews and preset thumbnails that count every item.
- **Settings:** each page is its own file. Integrations, Dock Setup, both inspectors and Permissions were de-duplicated and use one label set (FX-10).
- **CI:** two load-sensitive timing tests now poll instead of racing wall-clock sleeps.

## Current verification

Evidence comes from two sources. **Native Mac evidence** comes from the orchestrator's Mac session. **CI evidence** comes from GitHub Actions `Validate MyDock` on macOS 26 runners. Work after FX-09 was done in a cloud session without a Swift toolchain, so its only compile and test evidence is CI.

| Check | Source | Result |
|---|---|---|
| `./TestMyDock.sh` after FX-08/FX-09 | Native Mac, 5 Oct | **685 tests in 84 suites passed** (`.build/redesign-refresh-test.log`) |
| Render matrix after FX-07 (`df50ea8`) | Native Mac, 5 Oct | 17 DEBUG modes, exit 0, **1,366 PNGs** in `.build/visual-qa/redesign-20261005/final/`, reviewed by an independent visual reviewer |
| Canonical build after FX-07 | Native Mac, 5 Oct | `./BuildMyDock.sh` exit 0. SHA-256 `3f81e5be8fd1e0dba75bea4227d2c8b541912b5b19b09835ada42f9396181a2f`. x86_64 + arm64; min macOS 13.0; SDK 26.4. Ad-hoc signature valid. |
| Isolated launch sample after FX-07 | Native Mac, 5 Oct | 60 s, steady RSS **96.1 MB** (78 MB before the redesign), mean CPU 0.00 % at `ps` resolution, normal quit |
| `Validate MyDock` at `3a0dd69` (FX-10, follow-ups, T2) | CI, 5 Oct | In progress when recorded; the result is added here when the run finishes |
| Static review of `cec6394..3a0dd69` | Opus reviewer | SAFE: no compile, test or behaviour regressions found; all 37 changed files parse |

**The canonical `build/MyDock.app` predates FX-08 onward.** It must be rebuilt on the Mac, and the render matrix re-run, before this baseline counts as natively verified.

## Not verified

- **Native rebuild and renders of FX-08 onward:** `./BuildMyDock.sh`, relaunch, and the full render matrix including Reduce Transparency and Increase Contrast.
- **Native acceptance (H1–H9):**
  - real Liquid Glass over several wallpapers, in light and dark;
  - hover and morph feel, reveal and auto-hide;
  - side Docks and multiple displays;
  - Intel and macOS 13–15 fallbacks;
  - keyboard-only Add Item and Settings flows;
  - VoiceOver.
- **Glass blending:** whether widget glass blends with the Dock glass natively (RD-11 follow-up).
- **Calendar with real EventKit data and colours:** all renders use DEBUG fixtures.
- **Live provider accounts:** none were used.
- **Release:** signing and notarization.
- **Performance:** only `ps` samples so far; no Instruments-grade measurements. RSS is about 18 MB higher than before the redesign.
