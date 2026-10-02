# Canonical MyDock build baseline

## Integration in progress

A concurrent session is editing the worktree. The focus/library follow-up is not an integrated validated baseline: a build failed after `AppleWidgetCard.swift` changed during compilation, and this session cancelled its competing build. The verification below describes the earlier dated accessibility baseline. Current source/binary association and native focus acceptance must be refreshed after the other session finishes. See [the focus handoff](history/FOCUS_HANDOFF_2026-10-01.md).

Recorded **1 October 2026** (Europe/Warsaw), after the Dock workspace product rebuild. This is a validated development baseline; product acceptance remains open.

## Development target

- Source of truth: `Sources/MyDock/`; existing working-tree changes and user data were preserved.
- Canonical app: **`build/MyDock.app`**, built with `./BuildMyDock.sh` while that app was not running.
- Disposable validation stays under `.build/visual-qa/`. Stale and refreshed isolated previews were quit cleanly after native access resumed; no running bundle was overwritten.

## Current behavior

One sidebar leads to Docks, Explore and Settings. The Dock canvas replaces the permanent item grid and competing navigation. Click selects; native drag arranges; contextual menus and inspectors edit items and appearance. Searchable Add Library and Command-K expose apps, widgets, spacers and common actions. Per-profile debounced autosave retains failed drafts and offers Retry; native Undo merges edits without overwriting unrelated live widget updates.

Editor and live Dock share material and semantic item identity. Profile changes transform shared items with spring motion and respect Reduce Motion. Widget rendering, provider services, permissions, native apply/rollback/recovery and existing persistence formats remain connected. Settings uses the same shell and separated rows. Native layouts expose Apply, mode-aware Applied status and a typed creation choice. No schema migration was needed.

## Current verification

- Canonical universal build succeeds. arm64 and x86_64 slices declare macOS 13.0; strict ad-hoc signature, Info.plist, regenerated Xcode project and whitespace checks pass.
- `./TestMyDock.sh`: **230 reported tests in 16 suites pass**, with four explicit opt-ins skipped by default. Added coverage includes autosave coalescing/retry/discard/Undo, visual identity and mode-aware profile status, native pointer event delivery/cancellation and ordered native pasteboard URL batches.
- The separately opted-in isolated panel test was rerun after the accessibility refinement and **passed in 18.380 seconds** across all three edges, mode/polling transitions, menu tracking and resize retention. It injects overview metadata and does not mutate Apple's Dock. The earlier run remains historical evidence.
- **74 isolated layouts** exported for the current build. Contact sheets and selected full-size images reviewed. The prior 56-surface matrix is extended by 18 dark/light Increase Contrast, Reduce Transparency and combined variants across workspace, actual Settings shell and Dock. DEBUG overrides affect app-owned drawing and do not change system preferences. Shared semantic outline tokens now adapt editor controls, widget containers and the live/editor Dock; the Dock material owns one outline. Light-mode Midnight style preview icons were corrected. Includes dark/light, compact/normal/large canvas, inspector, selected item, empty/error states, Add Library/commands, native-only status/library, all settings categories at 780 and 1160 points, all 27 widget catalog entries, onboarding and Dock edges/overflow. Hosting-view bitmap renders do not certify live animation or pointer behavior. The old gallery renders are DEBUG comparison surfaces, absent from shipping navigation.
- Earlier native checks on the rebuilt canonical app preserved existing profiles and real widget contents. Disposable UI checks verified search/add, keyboard reorder, Delete/Undo, profile creation/rename/duplicate/delete, first Configure, profile shortcut and Command-K transitions. Single-item pointer drag was delivered and its new order persisted.
- **Editor pointer fix passes in isolated native UI.** The user confirmed physical-mouse end drops failed in the preceding SwiftUI implementation. `DockCanvasDragView` now tracks internal pointer moves/releases directly, with a native snapshot lift and shared insertion destination. Clock dropped at the end; Undo restored it; selected Clock/Weather moved to both ends in order; a spacer moved between widgets; an outside release cancelled; right-click remained available. The final isolated source also retested end drop and focus transfer to a newly added spacer. External Finder/browser drops still use a registered AppKit destination; ordered URL pasteboard regression passes, but cross-app/empty-Dock pointer acceptance remains open. The obsolete asynchronous item-provider loader/delegates were removed after replacement checks.
- The canonical app was quit cleanly before rebuilding. **Latest canonical native launch passed**: the MyDock menu opened Manage Docks, all five existing profiles and real widget contents remained, Command-K opened commands and Escape returned to the workspace. Later CUA access again returned `cgWindowNotFound` for canonical and isolated windows, leaving broader native drag/focus/window acceptance open. No running bundle was overwritten or forcibly terminated. The disposable pointer probe remains running because CUA cannot select it for a clean quit.
- Xcode UI scenarios were refreshed to use the rebuilt product: autosave/word-boundary rename through Settings, Add Library/Delete/Undo, Command-K, creation/duplication and pointer end-drop/Undo. The removed Your Docks/Save/Discard navigation and timing-dependent dirty-Quit scenario are no longer targets; failed-save/quit policies remain covered by domain tests and manual acceptance. Preview teardown now uses Command-Q and waits for normal termination. Swift parser and whitespace checks pass. **This UI suite has not been typechecked or executed**: full Xcode is unavailable; selector and interaction acceptance remain pending. App sources and the canonical binary are unchanged by this test-only follow-up.
- Executable SHA-256: `d5a4a0d7dc15e6bed895ec5eb4782df442b9e01391db4a1d652ed47edfeae9a8`.

[BUILD_BASELINE.json](BUILD_BASELINE.json) records source hashes and exact evidence. Logs: `.build/product-rebuild-build.log`, `.build/product-accessibility-tests.log`, `.build/product-accessibility-runtime.log`, `.build/product-accessibility-render.log`, `.build/product-rebuild-project.log`. See the [rebuild inventory](history/DOCK_WORKSPACE_REBUILD_2026-10-01.md) and [complete directive acceptance ledger](history/PRODUCT_DESIGN_ACCEPTANCE_2026-10-01.md).

## Historical evidence and qualification limits

The preceding [account/interface verification](history/ACCOUNT_AND_INTERFACE_VERIFICATION_2026-10-01.json) records 221 tests, 49 layouts and read-only existing Codex account acceptance. It does not describe the latest bundle. Claude Code remains unavailable locally; no new provider connection or credential operation was performed.

Production motion/frame pacing, full VoiceOver/accessibility/keyboard matrix, Spaces/multiple displays, first-run/restart/recovery UI branches and provider expiry remain open. Developer ID/notarization, older supported macOS and Intel runtime qualification require other environments. This ad-hoc app is not a completed release qualification. No commit, push, publication or native-Dock mutation test was performed in this rebuild. See [implementation status](IMPLEMENTATION_STATUS.md).
