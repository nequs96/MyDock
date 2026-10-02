# Account and interface follow-up

1 October 2026. Continued from the existing `Sources/MyDock/` working tree. Canonical output remains `build/MyDock.app`.

## Changes

- Added existing-account discovery and provider-owned Sign In / Find Account actions to AI widgets and Integrations. The app displays fixed connection messages and retains no CLI credential output.
- Corrected Codex’s unsupported `--stdio` argument, initialization sequencing and premature stdin closure. Account state uses `account/read`; quota data uses `account/rateLimits/read`.
- Added one-click Claude Code status-line setup using built-in macOS tools, preserving other settings and existing status-line output with a private backup and atomic writes.
- Added an explicit clickable spacer popover to Your Docks. Flattened live spacer menu choices and retained the live Dock during AppKit menu tracking.
- Replaced the corner grip with a separator; removed 5% quantization and panel animation during resizing, used screen-space pointer deltas, retained the panel during dragging, and made both size sliders continuous.
- Updated preview/runtime geometry and live data, including running apps, minimized windows and media visibility. Item thumbnails now respect the actual configured provider, layout and data.
- Unified sidebar headers, selection, groups, search fields, surfaces, controls and typography across Your Docks, Settings and Widgets. New installations follow the system appearance. Existing user appearance choices and drafts are retained. Widget cards expose Configure buttons; reopening the app brings back the workspace.

## Evidence

The universal canonical build succeeds and passes strict ad-hoc signature, plist, architecture/minimum-OS and generated project checks. The default suite reports 221 tests in 15 suites passing, with four explicit opt-ins skipped. Separate read-only existing Codex account and isolated panel scenarios pass. The final isolated render matrix exports 49 layouts.

Native inspection confirms canonical launch, the preserved active profile, live Dock/editor contents, current widget thumbnails and descriptive Configure labels. A spacer was added to the draft through the persistent popover, then the test edit was discarded, restoring the original item count. The floating Dock exposes its separator as Resize Custom Dock with increment/decrement/reset accessibility actions.

The Mac locked during initial validation and was later unlocked by the user. The first panel scenario encountered real overview/lock-screen metadata; its final isolated run injects overview absence, leaving the overview policy separately tested. This does not certify visible desktop behavior while locked. The live Codex check exposed a status-detection mismatch; structured account discovery fixed it, and the final check passes.

## Remaining acceptance

Native pointer drag automation returned noWindowsAvailable for the floating panel; no measured frame-rate claim is made. Claude Code is absent on this Mac; only its setup/parser/command preservation fixtures were executed. Provider login completion, expired accounts, multi-display/Spaces behavior, VoiceOver and distribution qualification remain open. No Apple Dock mutation opt-in, synthetic performance opt-in, commit or push was run.

The exact hashes, commands and log paths are in [verification](ACCOUNT_AND_INTERFACE_VERIFICATION_2026-10-01.json). Current baseline evidence is [RELEASE_AUDIT](../RELEASE_AUDIT.md).
