# Widget presentation and utilities — 1 October 2026

## Result

The shared widget popover now uses the native window background through its outer padding, matching its frame and arrow. The popover follows the Dock theme without changing the application-wide appearance. All 30 widget providers use one shared header with a category emblem, direct per-widget Customize control and close button. Existing provider controls, permission flows, credentials and persisted configurations remain connected.

System Activity was previously 620 points wide inside a wrapper capped at 440 points; its 488-point settings sheet visibly clipped CPU/memory/swap, health details and storage actions. It now uses a 420-point layout: two primary readings, a four-column processor grid, health rows, a three-column memory breakdown, capacity and storage exploration. A visible system popover keeps sampling even when the Dock hides. Scanning remains explicit and continues across popover dismissal.

AI Activity now has a consistent header, inset totals panel and shared surface, with its provider/range/chart/freshness and recovery behavior preserved. The AI and System Activity Dock identities and compact readings were revised. Network Activity fits the shared width.

## Icon choices and new widgets

Every widget has per-item **Live, Color, Soft and Mono** styles in its configuration sheet and Dock popover. Live keeps information cards/readings; the other styles provide a distinct icon and open the full widget on click. Card size remains independent. Both the actual Dock and manager preview use persisted choices. Older profiles default to Live. The application icon was not changed.

- **Disk Space:** actual startup-volume available/total capacity, used fraction, manual refresh and one-minute updates while mounted.
- **Calculator:** bounded arithmetic parser with precedence, unary signs, parentheses, decimal numbers and postfix percentages; native keypad, keyboard expression entry, three-result session history and Copy Result. No expression executes code or a shell.
- **Quick Checklist:** local per-widget tasks with add, edit, complete/reopen, remove and clear completed; remaining count in the live tile. Limited to 100 tasks. Private checklist content is stripped from shareable presets/history wherever note content is stripped, and included only through the existing include-notes choice.

All three appear in the existing searchable Add Item library. No new account, permission, dependency or credential is required.

## Current verification

- Final `./TestMyDock.sh`: **242 reported tests in 18 suites passed** (1.802 seconds); five existing explicit opt-ins remain skipped. New tests cover arithmetic/rejection, backwards-compatible decode, style/task round trips, private-content sanitization, invalid duplicate tasks and disk fraction boundaries. Log: `.build/widget-redesign-tests.log`.
- Final `./BuildMyDock.sh`: universal arm64/x86_64 canonical `build/MyDock.app`; both release compilations succeeded. Strict ad-hoc signature, app/project plist, regenerated Xcode project and whitespace checks passed. Log: `.build/widget-redesign-build.log`; project log: `.build/widget-redesign-project.log`.
- **76 final renders** in `.build/visual-qa/widget-redesign-final/`: 30 popovers in each of dark/light, seven configuration sheets in each appearance, and two icon-style comparison sheets. Both complete popover contact sheets and selected full-size AI/System/settings/utility/icon images were reviewed. The long configuration views intentionally scroll in their bounded viewport. Log: `.build/widget-redesign-render-final.log`. Two additional contact-sheet composites are review aids, not counted as independent renders.
- The old canonical app was quit through its normal Quit flow before the first rebuild. After render corrections, clean AppKit termination was requested and the process exited before rebuilding. No running bundle was overwritten. The isolated interaction preview was also terminated cleanly after CUA failed to acquire its window.
- Final canonical app launched and its executable path was checked with `lsof`. **CUA returned `cgWindowNotFound`** for both the rebuilt canonical app and unique isolated preview, including after resetting the connection. Therefore final native style-selection clicks, calculator/checklist actions, popover arrow appearance and short-screen scrolling are not certified by this pass. Rendering is not native event acceptance. The initial old System Activity sheet screenshot and AX tree did confirm its clipping before implementation.

## Boundaries

No native-Dock mutation opt-in, live account connection, permission grant, commit, push or publication was performed. User Application Support data and credentials were not edited by cleanup or validation. Full Xcode UI execution, VoiceOver, provider/permission flows, real popover interactions and older macOS/Intel runtime qualification remain pending. Current fingerprints are in `docs/BUILD_BASELINE.json`; previous evidence is preserved in `RELEASE_EVIDENCE_PRE_WIDGET_REDESIGN_2026-10-01.md` and `BUILD_BASELINE_PRE_WIDGET_REDESIGN_2026-10-01.json`.
