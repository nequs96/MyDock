# Canonical MyDock build baseline

Recorded **3 October 2026** (Europe/Warsaw), after integrating the corrective batch and the design/architecture improvements tracked in the [execution ledger](history/EXECUTION_LEDGER_2026-10-03.md). The source of truth remains `Sources/MyDock/`, and the canonical app remains **`build/MyDock.app`** (git `f1c90b5`, 4 October 2026 follow-up wave included).

## What changed since the preceding baseline

The [ledger](history/EXECUTION_LEDGER_2026-10-03.md) records each package, with separate implementation and verification fields. The following changes are implemented and covered by fixtures. None of them is natively accepted.

**State and recovery**
- Future and oversized state files are refused before model decode, are left untouched, and disable saving.
- Create, duplicate and Restore validate and persist before anything is published.
- Sticky Note and snippet/link drafts survive rejected or failed saves, dismissal and relaunch.
- Removals have a bounded 15-second undo.
- Routine edits are coalesced off the main thread. Critical saves and quit still wait for disk.

**Providers**
- AI and market/billing/weather numbers are domain-bounded.
- AI Activity deduplicates records, and its Sessions total counts distinct sessions.
- One Claude config-directory resolver is used everywhere.
- Shopify replaces credentials for the same store correctly, with bounded pagination.
- Stripe fetches partial nested item lists or excludes them.
- Paddle setup asks for `metrics.read`.
- A network counter reset no longer produces a rate spike.
- Response size is capped while streaming.
- Changing tenant clears the old figures.

**Native actions**
- Window discovery for the context menu no longer depends on monitor toggles.
- Window identity uses the raw title plus the installed-copy and launch identity, and resolves windows by native AX object.
- The resize grip has a hit area of at least 14 pt.
- A narrow presentation signature stops unrelated settings from re-rooting the Dock.
- Mid-transition style or Off changes normalize the Dock immediately.
- Performance signposts were added.

**Lifecycle**
- Shortcuts can be cancelled.
- Folder popouts show loading, cancel obsolete work and cap their output.
- Location and Reminders have deadlines.
- Hydration reconciles its reminders at startup and on wake.
- Refresh is driven by typed demand from popouts as well as the Dock.

**Product**
- Widget setup comes before appearance, and the Settings header is compact.
- Edit, Activate and Apply are explained.
- Workspace actions are labelled.
- Example labels and VoiceOver labels were added.
- The AirDrop and Trash provider faces are restored.
- File Shelf has Locate and Retry.
- The Trash dialog states its Finder-wide scope.
- Focus guidance is accurate for CLI-built bundles.

**Validation isolation**
- `AppRuntimeEnvironment` sends isolated runs to a private root with memory-only defaults.
- It blocks native effects and credentials, including the real `~/.claude`, the Codex app-server, AI logs and the Trash watcher.

**Xcode project**
- `MyDock.xcodeproj` was regenerated with `./GenerateXcodeProject.sh` and lists every source and test file. The previous project was missing 8 sources and 15 test files added since 24f9c76.

## Current verification

- `./TestMyDock.sh` (isolated): **405 tests in 49 suites passed, 0 failed, 5 explicit opt-ins skipped.** Log: `.build/orchestrate/test-final2.log`.
- MyDock was quit with a normal quit Apple Event before building. The process exit was verified and no running bundle was overwritten.
- `./BuildMyDock.sh` exited 0.
  - Executable SHA-256: `a35bb831bb9867b89c16478be5f0f78a78e84355ee6b4f83d5ed847becf591bd`.
  - Universal x86_64 + arm64.
  - `codesign --verify --strict` passes (ad-hoc).
  - Log: `.build/orchestrate/build-wave5.log`.
- The canonical `build/MyDock.app` was relaunched (PID 98053). The coordinator did not exercise any UI or native scenario.
- [BUILD_BASELINE.json](BUILD_BASELINE.json) records the source, test and app hashes. The source fingerprint is `a01678fe…fabe76`.

## Follow-up wave (4 October 2026)

- **Provider caches:** provider readings now persist only in a separate private `runtime-cache.json`. They are excluded from state, backups and history. Existing embedded readings are migrated once at launch (PR-13 phase 1).
- **Provenance and help:** popouts and Connections show each reading's source, metric, freshness and state (PR-15). Settings has privacy and limitations help (PR-20).
- **Refactors:** the widget capability registry is typed (PR-17), and the Dock controller is split into four files.
- **Refresh demand:** editor previews and the Battery popout keep refreshing while the Dock is hidden.
- **Evidence:**
  - An isolated render export produced 143 PNGs under `.build/visual-qa/corrective-batch-20261004*`.
  - A synthetic writer/geometry baseline is in `.build/orchestrate/perf/synthetic-performance.json`. These are not UI latency figures.

## Not verified

- **Native acceptance has not been run.** That covers H1–H9 in the ledger: Close/Quit with unsaved documents, window identity with two installed copies, resize pointer feel and frame pacing, glass on real wallpaper, interrupted motion, VoiceOver, Finder/AirDrop/Trash, permissions, and native Dock preference restoration.
- **No Xcode build has run** because full Xcode is absent. The App Intents metadata, the UI test suite, signing, notarization and Gatekeeper are all unverified.
- **Live accounts were not used.** Stripe, Paddle, Shopify, market data, Claude, Codex and Copilot were checked against fixtures only.
- **No production performance measurements.** The signposts exist, but no Instruments trace has been recorded.

This is a local ad-hoc development build, not a qualified distribution. The previous baseline is preserved in [history/RELEASE_EVIDENCE_PRE_CORRECTIVE_BATCH_2026-10-03.md](history/RELEASE_EVIDENCE_PRE_CORRECTIVE_BATCH_2026-10-03.md) and [history/BUILD_BASELINE_PRE_CORRECTIVE_BATCH_2026-10-03.json](history/BUILD_BASELINE_PRE_CORRECTIVE_BATCH_2026-10-03.json). Nothing was pushed or published.
