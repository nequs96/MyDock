# Adaptive widget presentation — 3 October 2026

This replaces the earlier icon-tile interpretation of the widget redesign. Source of truth: `Sources/MyDock/`; canonical app: `build/MyDock.app`.

## Presentation architecture

`WidgetPresentationCatalog` supplies meaningful layouts and widths per family. `WidgetConfiguration` stores layout separately from icon treatment and secondary metric choices. `WidgetContainer`, `MetricText`, `WidgetHeader`, `MicroSparkline`, `UsageBar` and `WidgetIcon` provide shared materials and small primitives; provider-specific faces compose them differently. Horizontal height is 54 points; widths range from 54-point actions to 186-point media. Display scale still applies at the Dock level. Widgets do not receive icon magnification.

AI Activity uses real matching provider/range snapshots for totals, available metadata and small history. Today totals retain the existing seven-day history contract, described in the tooltip. CPU keeps up to 30 actual valid readings at the existing cadence; no seeded activity appears in the live face. Network, disk, battery, weather, media, clocks, reminders, business metrics and local tools use their own information patterns. Shared metric/unit text scales together to preserve long totals. SF Symbol colors are applied explicitly so small provider icons retain the selected treatment.

Settings have an actual live preview, dimensionally accurate layout rows and 44-point icon swatches. Icon choices never alter the layout, metric hierarchy or dimensions. Legacy Live/Color/Soft/Mono styles migrate to Soft/Accent/Soft/Mono icon treatments; old generic widths map to supported semantic layouts. New Outline remains a separate choice. Legacy stored fields remain compatible. Field-level draft merges continue to preserve runtime snapshots.

## Validation

- Host: Apple Silicon, macOS 27.0.1 (26A434), Swift 6.3; shipping minimum remains macOS 13.0 and is not an older-OS execution claim.
- `./TestMyDock.sh`: 246 reported tests in 19 suites passed; five opt-ins skipped. Regression coverage includes migration, new-style round trips, every registered widget’s geometry/style independence and bounded telemetry history. Log: `.build/adaptive-widget-tests.log`.
- 34 final NSHostingView bitmap renders under `.build/visual-qa/adaptive-widgets-final/`: mixed Dock in each theme, three pages of all 30 families’ layouts per theme, eight configuration sheets per theme, icon-independence matrices, narrow faces, long partial token totals and four real empty configurations. Contact sheets supplement those exports and do not count as independent renders. Illustrative fixtures are labeled and never written as provider data to the user’s profiles.
- Visual review corrected CPU label clipping, compact action word wrapping, long metric truncation, forecast coloring and narrow network/weather/battery compositions. The final mixed Dock shows different widths and internal hierarchies with a consistent height.
- Native CUA isolated preview: selected AI Activity and Mono independently; verified unchanged usage information with an updated icon, selected Compact and Outline, selected CPU Trend with actual live sampling, scrolled System Activity settings to the bottom while keeping Close reachable, and inspected a mixed bottom Dock with installed app icons and real AI/CPU/network/disk/battery/clock data. The final text-scaling refinement was verified in bitmap exports; canonical checks are recorded in RELEASE_AUDIT.md.
- The canonical intermediate app was launched and the existing side Dock’s AI popover opened. CUA exposed the provider controls and real totals/history. The screenshot target remained the Dock panel and did not capture the complete native arrow/frame, so that screenshot acceptance remains open.
- CUA cached the validation bundle’s earlier identifier after its metadata changed. Its inventory still saw the final isolated process but binding failed; normal AppKit termination was used for that process. The preview identifier was corrected to the app’s recognized VisualPreview prefix so an environment-free relaunch remains isolated. An earlier CUA post-quit observation had relaunched the preview without isolation under its old identifier; it was quit normally immediately, without editing the live profile. No forced kill or running-bundle overwrite was used.
- One build was superseded by additional visual fixes; the compiler rejected changed input files before updating the app bundle. That log is `.build/adaptive-widget-build-superseded.log` and is not final build evidence. The final build is `.build/adaptive-widget-build-final.log`.

Final universal `./BuildMyDock.sh` passed with arm64/x86_64 slices, strict ad-hoc signature and plist checks. The canonical app is running from `build/MyDock.app`. Final CUA binding failed twice with `Sky Computer Use native pipe startup failed`; CLI process-path verification passed. Current hashes and evidence are in `docs/BUILD_BASELINE.json`.

## Remaining acceptance

Full Xcode UI execution, VoiceOver, all reduced-transparency/contrast variants, native popover arrow/frame screenshots, shortest-display/side/popover combinations, live provider credential/permission flows, Intel execution, supported older OS execution and distribution qualification remain outside this local pass. No native mutation or synthetic/runtime test opt-in was enabled. The existing persistence, integrations, permission flows and local utilities were preserved.
