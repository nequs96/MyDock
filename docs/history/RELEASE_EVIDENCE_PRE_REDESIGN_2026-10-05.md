# Canonical MyDock development baseline

Recorded on **4 October 2026**, after the remaining-work wave that followed the [completion handoff](history/CLAUDE_COMPLETION_HANDOFF_2026-10-04.md). Source remains in `Sources/MyDock/`. The canonical app remains **`build/MyDock.app`**. It was built from the integrated tree whose last code commit is `78fc9a4`. Per-item outcomes are in [the execution ledger](history/EXECUTION_LEDGER_2026-10-03.md), section "Remaining-work resumption".

## What this baseline adds

The completion-handoff contents are listed in the [previous baseline](history/RELEASE_EVIDENCE_PRE_REMAINING_WORK_2026-10-04.md).

- **PR-13 phase 2 (reliability):**
  - `ProfileStore.publishRuntimeReadings` is the only path that writes provider readings, and `WidgetDataCoordinator` uses it.
  - It writes to the runtime cache only, after re-resolving each reading against the authored widget identity.
  - Provider refreshes cannot change authored state, history, Undo or open drafts.
  - New tests cover:
    - a refresh during an open draft, followed by Save;
    - a stale draft reading;
    - a cache-only publish;
    - a symbol switch and widget deletion.
- **PR-17 capability consumers (product):**
  - Required DEBUG render states (layouts, plus a setup state for `hasSetupState` families) are derived from `WidgetCapabilities`.
  - The QA export fails if a registry family's required state was not rendered.
  - Widget settings show a short access note derived from capabilities, for example "May ask for Calendar access… Can show personal content on your Dock". It never claims that access was granted.
- **Calendar fixture hook (product):**
  - A DEBUG-only `CalendarQAFixture` feeds empty, ongoing and upcoming events to the *production* Calendar face and popout without EventKit.
  - The WIDGET and SURFACES QA exports now render those states.
- **Ledger correction:** the reveal-monitor extraction was already present (`DockRevealMonitor.swift`). Most capability flags were already used by the Add Library filters.

## Current verification

| Check | Result |
|---|---|
| `./TestMyDock.sh` (isolated, coordinator shell) | **516 tests in 66 suites passed, 0 failed, 5 explicit opt-in skips.** Log: `.build/orchestrate-d/test-integrated.log` |
| Python tooling (`PYTHONDONTWRITEBYTECODE=1`) | **11 passed** |
| `git diff --check` / Xcode project | Clean. Regenerated with `./GenerateXcodeProject.sh`, and the new sources and tests are listed. |
| Canonical build | MyDock was not running. `./BuildMyDock.sh` exited 0. Log: `.build/orchestrate-d/build.log` |
| Executable | SHA-256 `e66cf75801ff9861d7811664c773dc569316afc75866e304c206da674a65e55c`. Universal x86_64 + arm64; min macOS 13.0; SDK 26.4. |
| Signature and metadata | Strict deep ad-hoc signature valid; plist lint OK. **No `Metadata.appintents`** (CLI build). |
| Isolated launch and resource sample | The canonical executable ran with a fresh `MYDOCK_VALIDATION_ROOT` for 60 s and was sampled every 2 s with `ps`. **Steady RSS 78 MB (peak 95.8 MB during launch), mean CPU 0.23 %.** It then quit through a normal quit Apple Event, and the process was confirmed gone. It wrote only `ApplicationSupport/state.json` and `MyDock/instance.lock` in that root. This used an empty default profile with native effects disabled. It is not an Instruments, energy or frame-pacing measurement. |
| Renders | Isolated DEBUG exports: WIDGET produced 130 PNGs and SURFACES produced 44, both with exit 0. The WIDGET export passed the capability matrix validation. The coordinator viewed the production Calendar popout (ongoing), the Dock face (empty), the Stripe setup state and the Quick Checklist access note. |
| Relaunch | Your normal `build/MyDock.app` was relaunched (PID 87859). |

The source fingerprint is `54730d96…19d50`; see [BUILD_BASELINE.json](BUILD_BASELINE.json).

## Not verified

- **Native acceptance has not been run.** H1–H9 cover 40 procedures: window and Quit with unsaved documents, resize, glass on wallpaper, motion and Mission Control, small windows and VoiceOver, Finder, AirDrop and Trash, permissions and preference restoration, failure traces, and release.
- **Live provider accounts were not used**, so there is no offline relaunch or tenant switch against a real provider.
- **No Xcode build, signing or notarization.** Full Xcode is absent, so Focus discovery and CI or distribution qualification are also unverified.
- **Calendar with real EventKit data is unverified.** All Calendar renders use DEBUG fixtures.
- **Performance is only the `ps` sample above.** There are no Instruments, energy, frame-pacing or many-widget measurements (PR-18).

The previous baseline is preserved in [history/RELEASE_EVIDENCE_PRE_REMAINING_WORK_2026-10-04.md](history/RELEASE_EVIDENCE_PRE_REMAINING_WORK_2026-10-04.md). Nothing was pushed or published.
