# Canonical MyDock build baseline

Recorded **1 October 2026** (Europe/Warsaw), after the focused Add Item/discovery/AI Activity rebuild. Source of truth remains `Sources/MyDock/`; canonical app remains **`build/MyDock.app`**. Existing working-tree changes and user data were preserved.

## Current behavior

Add Item is a native two-pane browser with category navigation, grouped actual widget previews, System previews and compact application rows. Installed applications are validated against current filesystem metadata and executable availability; stale records/remnants are excluded. Added state and keyboard navigation support repeated intentional customization. Command-K retains its separate command experience.

AI Activity uses a compact provider/range header, human-readable aligned totals, readable daily chart, restrained local-log provenance and partial-data information. Setup/failure/loading states have clear recovery and retain saved data during refresh. The Dock tile uses the shared provider/metric hierarchy at actual Dock widths.

The broader Dock workspace, persistence, integrations and existing profile formats remain connected. See the [focused implementation and acceptance report](history/FOCUSED_ITEM_BROWSER_AND_AI_ACTIVITY_2026-10-01.md) for investigation, data flow, screenshots, commands and exact limits.

## Current verification

- Universal arm64/x86_64 `./BuildMyDock.sh` succeeds; strict ad-hoc signature, app/project plist, regenerated project and whitespace checks pass. The target app was quit normally before rebuilding. Disposable bundles remain in `.build/visual-qa/`.
- `./TestMyDock.sh`: **237 reported tests in 17 suites passed**; five explicit opt-ins skipped by default. Log: `.build/focused-tests-verified.log`.
- Read-only installed-app audit explicitly opted in: **116 valid current bundles**, zero unreadable roots; all paths revalidated, stale Adobe remnants excluded and valid installed Adobe products retained. Log: `.build/focused-installed-audit.log`.
- **26 current focused dark/light PNGs** reviewed in `.build/visual-qa/focused-ui-verified/`: All/Applications/Widgets/System/search/empty, six AI popover states and tiles at 54/108/144/196 points plus setup. Hosting-view renders do not certify native event behavior.
- Isolated native checks passed for search, real icons, stale Acrobat exclusion, Return-to-add, duplicate prevention, Added state, arrows, Escape, category navigation and bounded sheet presentation after zooming the parent window. Earlier canonical native checks in this pass showed real local Codex usage, readable chart and partial warning, refresh preservation and Escape dismissal.
- Latest final canonical process launched from `build/MyDock.app`; process path verified. **CUA then returned `cgWindowNotFound`**, preventing a final live refresh-role recheck and normal isolated-preview quit. That isolated preview was left untouched; no running bundle was replaced or forcibly terminated. Canonical MyDock remains running.
- UI test expectations were updated and parser checked. **Full Xcode UI execution/typechecking and full VoiceOver remain unrun.** Native popover child-window screenshot capture is unavailable in CUA; full shared-view renders and native AX inspection are distinguished in the report.

[BUILD_BASELINE.json](BUILD_BASELINE.json) records current source hashes, executable identity and evidence. Build log: `.build/focused-build-verified.log`; render log: `.build/focused-render-verified.log`.

## Historical evidence and qualification limits

The prior broad **74-layout accessibility matrix** and **18.380-second isolated panel runtime test** are explicitly historical; they were not rerun for this final focused source. [Previous release evidence](history/RELEASE_EVIDENCE_PRE_FOCUSED_UI_2026-10-01.md) preserves the prior baseline and integration handoff. The preserved concurrent [Dock focus follow-up](history/FOCUS_HANDOFF_2026-10-01.md) builds/tests with current source but still requires controlled native focus acceptance.

Actual install/move/volume-event UI acceptance, final tile refresh AX role, click-outside dismissal and broader VoiceOver/provider/permissions scenarios remain to be exercised. Production motion/frame pacing, Spaces/displays, recovery, supported OS/Intel runtime, Developer ID and notarization remain outside this local development qualification. No commit, push, publication, credential operation or native-Dock mutation opt-in was performed. See [implementation status](IMPLEMENTATION_STATUS.md).
