# Canonical MyDock build baseline

Recorded **1 October 2026** (Europe/Warsaw), after the widget presentation, icon-style and utility follow-up. Source of truth remains `Sources/MyDock/`; canonical app remains **`build/MyDock.app`**. Existing working-tree changes and user data were preserved.

## Current behavior

All widget popovers share a native-matched surface and consistent header. Customize opens per-widget Live/Color/Soft/Mono choices and card size directly. System Activity uses a bounded, stacked layout without its previous horizontal clipping; visible popovers continue live sampling when the Dock hides. AI Activity shares the surface and inset totals treatment while preserving provider/range/chart/recovery behavior. Dock icons and information cards use saved per-widget styles.

The library now contains **30 widget families**, including the new **Disk Space, Calculator and Quick Checklist**. Checklists are saved locally with the profile and excluded from sanitized shared presets unless notes are explicitly included. Existing profiles default to Live style. Integrations, credentials and permission flows remain connected.

See the [widget implementation and validation report](history/WIDGET_PRESENTATION_AND_UTILITIES_2026-10-01.md) for exact behavior and limits.

## Current verification

- Universal arm64/x86_64 `./BuildMyDock.sh` succeeds. Strict ad-hoc signature, app/project plist, regenerated project and whitespace checks pass. The canonical target was quit cleanly before rebuilding; validation bundles remain under `.build/visual-qa/`.
- `./TestMyDock.sh`: **242 reported tests in 18 suites passed**; five explicit opt-ins skipped. Log: `.build/widget-redesign-tests.log`.
- **76 final dark/light renders** cover all 30 popovers, seven configuration sheets, and icon styles. Both complete contact sheets and selected full-size images were reviewed. Directory: `.build/visual-qa/widget-redesign-final/`; log: `.build/widget-redesign-render-final.log`.
- Final canonical process launched from `build/MyDock.app`, with its executable path verified. **CUA returned `cgWindowNotFound` for canonical and isolated preview windows.** Native style-selection, utility actions, popover arrow appearance and short-screen scrolling remain unverified in this pass. The isolated preview was terminated cleanly without replacing its bundle.
- Full Xcode UI tests/typechecking and VoiceOver remain unrun. The host is not an older-macOS/Intel runtime qualification.

[BUILD_BASELINE.json](BUILD_BASELINE.json) records current hashes and evidence. Build log: `.build/widget-redesign-build.log`.

## Earlier evidence

The Add Item/AI Activity follow-up's **237-test suite, 116-installed-app audit, 26 renders and native browser checks** are now explicitly historical. They were not rerun as installed-app/browser scenarios for this widget baseline. See [the preceding release evidence](history/RELEASE_EVIDENCE_PRE_WIDGET_REDESIGN_2026-10-01.md) and [focused report](history/FOCUSED_ITEM_BROWSER_AND_AI_ACTIVITY_2026-10-01.md).

The earlier 74-layout matrix, isolated panel runtime test and broader workspace acceptance are also historical. The [Dock focus handoff](history/FOCUS_HANDOFF_2026-10-01.md) remains pending controlled native acceptance. Current remaining provider, permission, display, performance and distribution work is in [implementation status](IMPLEMENTATION_STATUS.md). No native mutation opt-in, live connection, commit, push or publication was performed.
