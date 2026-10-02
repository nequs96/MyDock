# MyDock repository and product review

**Review date:** 29 September 2026  
**Reviewed checkout:** `/Users/jakubjalowiecki/Documents/ChatGPT/dockX`  
**Git base:** `18a664a48551d35c43232ba9f51b8f2c806afcce`, plus the existing uncommitted working tree  
**Deliverable:** an implementation-ready audit and improvement plan. Product code was not changed in this review.

## 1. Product verdict

MyDock already has substantial feature breadth: native and custom Dock profiles, 27 registered widget providers, local persistence, backup import/export, window previews, global shortcuts, Focus integration, business metrics, and optional system permissions. The foundation is worth keeping.

It is **not yet ready to be described as a better Dockset replacement**. The most important deficits are lost edits, incomplete runtime geometry, inconsistent refresh ownership, and a Dock interaction model that does not yet feel coherent. Adding more widget names or changing the blur will not resolve those problems.

The best direction is an original, native Mac utility that exceeds Dockset in reliability, preview accuracy, customization, and recovery. Use its documented behavior as a benchmark; build MyDock's own visual identity and implementation.

The first release milestone should be: **editing never loses data; the Dock always sizes and reveals correctly; visible widget data stays current; every failure has a useful recovery path.** Visual refinement should build on that milestone.

## 2. What was actually verified

| Work | Result | Limits |
| --- | --- | --- |
| Repository inventory | 77 Swift source files, 21,731 source lines; 9 test files, 3,425 test lines; build scripts, Xcode metadata, assets, and existing documentation inspected | This is a subsystem audit with targeted source tracing, not a claim that every branch was executed |
| Current unit suite | `./TestMyDock.sh`: **161 tests in 8 suites passed** | Fake backends isolate native Dock changes; passing tests do not establish live Dock correctness |
| Fresh production compilation | `swift build -c release --scratch-path .build/repo-review-release`: passed | Fresh build was the host's arm64 slice, not a new universal distribution bundle |
| Deployment metadata | `vtool -show-build` reports macOS minimum **13.0**, SDK 26.4 | A minimum-version load command does not prove runtime compatibility on macOS 13 |
| Live visual review | Disposable Debug preview: custom Dock, unified manager, Appearance, Dock Setup, Behavior, Permissions, Integrations, and presets inspected in dark system appearance | Preview bypasses the production Dock window controller; actual edge behavior, Spaces, and Mission Control were reviewed in source |
| Live state reproduction | Saving a dirty manager draft overwrote a later Appearance color change | Reproduced using an isolated per-process profile store |
| Live quit reproduction | An unsaved manager rename was lost on Command-Q without a save prompt | Isolated preview exited; its JSON still contained the previous saved name |
| App icon | Current `Resources/AppIcon.icns` visually inspected | Small-size variants need separate optical QA |
| Competitor comparison | Dockset's official manual and changelog checked | Dockset was not installed or driven; no pixel-perfect or measured performance comparison is claimed |

The host has macOS 26.5.1 and Command Line Tools, not full Xcode. UI XCTest was not run. The test linker warns that Swift Testing's framework was built for macOS 14 while the test target declares macOS 13. The fresh app Release build completed without compiler warnings.

The user's existing modified and untracked files were preserved. Review builds are ignored output. The disposable preview was quit after inspection. No native Dock layout was applied, no live Dock preference was written by this review, and no provider account was connected.

### Evidence labels

- **Reproduced:** observed in the disposable running app.
- **Source-confirmed:** the inspected code directly establishes the defect or missing implementation.
- **Risk:** a credible failure sequence is present, but the failure was not induced on this Mac.
- **Recommendation:** a proposed product or design change, not an existing bug.
- **Unverified:** requires another platform, permission, account, or real Dock session.

Severity: **P1** = data loss, crash exposure, recovery failure, or a major reliability gap; **P2** = broken interaction or significant product quality; **P3** = refinement or later differentiation. These are release priorities, not estimates of how often each issue occurs.

## 3. Dockset comparison: where to reach parity and where to exceed it

The comparison baseline is Dockset **v0.2.6**, published 22 September 2026. Its recent changes emphasize compact sizing, App Folder, window preview caching, richer system information, battery states, and restrained background work. [Official changelog](https://dockset.app/changelog).

| Capability | Public benchmark | MyDock assessment | Better MyDock target |
| --- | --- | --- | --- |
| Native layout management | Saving an inactive native profile does not activate it; application is explicit. [Saved layouts](https://dockset.app/manual/save-switch-dock-layouts-mac) | Transaction machinery is strong, but create/delete can mark an unapplied native profile active | Separate editor selection, saved version, and successfully applied version; expose recovery and layout history |
| Custom Dock interaction | Documented ordering, item drag, folder browsing, overflow gestures, specific-window restore, Mission Control hiding, and fullscreen edge dwell. [Custom Dock manual](https://dockset.app/manual/use-custom-docks) | Much is implemented, but geometry, magnification, drag endpoints, window identity, and visibility policy have gaps | One render model shared by panel, preview, motion, drop targets, and accessibility |
| Appearance | Position/display, resize, material/glass variants, accessibility adaptation, and space for expanded windows with Accessibility access. [Appearance manual](https://dockset.app/manual/appearance) | Core controls exist; appearance is largely global and the live preview is missing from Settings | Per-profile appearance overrides, real preview, explicit display fallback, measurable legibility across wallpapers |
| Presets | Public workflow examples are templates to assemble, not installed presets. [Custom Dock manual](https://dockset.app/manual/use-custom-docks) | Four local presets already offer an opportunity to exceed this | Previewable, editable presets with installed-app alternatives, resolved permissions, and atomic creation |
| AI usage | Multiple provider sources and setup paths are documented. [AI usage manual](https://dockset.app/manual/ai-usage) | Codex, configured Claude status-line, and personal Copilot limits have readers; activity supports local Codex/Claude/Grok records; other paths are unavailable | Capability-aware adapters, honest source/age labels, preservation of existing provider setup, and safe background refresh |
| Business widgets | At-a-glance account data is a central part of the product proposition. [Dockset product](https://dockset.app/) | Real parsers and Keychain storage exist, but compact views do not own refresh | Freshness independent of whether a popout happens to be open; unified account management and error recovery |

**The strongest opportunities to win:** accurate live previews, safe concurrent editing, useful built-in presets, reliable compact data, inspectable recovery, and cleaner interaction details. Widget-count parity is already close enough to stop treating count as the main milestone.

## 4. Fix these reliability issues first

### R01 — P1: manager Save overwrites newer profile changes

**Reproduced.** `DockManagerView` keeps a full `DockProfileDraft` and ignores store updates while it is dirty. Saving replaces the entire latest profile with that older snapshot.

Evidence: [draft state subscription](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/DockManagerView.swift:132), [saveDraft](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/DockManagerView.swift:421), [replaceProfile](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Persistence/ProfileStore.swift:294).

Reproduction: rename the profile without saving → switch to Settings → change Blue to Purple → return to the manager and Save → Appearance returns to Blue. This also exposes note text, timer state, connection references, hydration history, and other live configuration to stale replacement.

**Change:** store a base revision and an explicit editor patch. Merge untouched fields from the latest profile; merge item order by stable identity; preserve latest widget configuration unless that exact field was edited. Show a conflict only when both paths changed the same field. A revision counter alone is insufficient unless the save path resolves the conflict.

**Acceptance:** a dirty rename plus a live note edit, timer transition, color change, and connection removal all survive Save. Deleting an item concurrently cannot silently resurrect it. Cover same-field conflicts and persistence failure.

### R02 — P1: Quit loses manager drafts

**Reproduced.** Manager dirtiness lives in local SwiftUI state. Application termination checks failed persistence and flushes note drafts, but does not inspect the manager draft.

Evidence: [manager state](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/DockManagerView.swift:10), [termination handling](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/MyDockApp.swift:146). In the preview, `Unsaved exit draft` was visible with Save enabled; Command-Q exited without a prompt. The temporary state file still contained `Review draft`.

**Change:** introduce a shared edit-session coordinator. Route Quit and any destructive session replacement through Save / Discard / Cancel. Make dirty state visible in the profile row and window title. Define whether closing the manager preserves the draft or resolves it; use the same rule everywhere.

**Acceptance:** Command-Q, menu Quit, switching profiles, creating a preset, importing, and deleting the edited profile use one consistent policy. Save failure keeps the session and app open. Cancel leaves the draft untouched.

### R03 — P1: paused countdown resumes with a late notification

**Source-confirmed.** Starting/resuming computes its alert from `countdownStartedAt + countdownDurationSeconds`, while the timer model correctly subtracts elapsed time before the pause.

Evidence: [notification deadline](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/WidgetViews.swift:790), [remaining-time model](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Models/DockModels.swift:699).

Example: a ten-minute timer runs for four minutes, pauses, then resumes. The UI has six minutes left; the notification is scheduled ten minutes after resume.

**Change:** capture the start transition and remaining duration together. Schedule at `transitionTime + remaining`; retain generation guards and compare the actual captured start value when the async request returns.

**Acceptance:** resume at several elapsed durations, pause during permission resolution, reset during scheduling, and finish during scheduling. UI completion and notification deadline agree; obsolete requests cannot return.

### R04 — P1: a new native apply can overwrite an unresolved recovery journal

**Risk supported by source.** Launch recovery errors are logged while the UI remains usable. `FileDockTransactionJournal.begin` atomically replaces the journal without rejecting an existing unresolved record; the next apply can therefore replace the original recovery snapshot.

Evidence: [startup recovery](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/MyDockApp.swift:139), [journal begin](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/NativeDockController.swift:84), [apply/transact](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/NativeDockController.swift:166).

**Change:** represent native Dock health explicitly: recovering / ready / recovery required / applying. Complete recovery before permitting native mutations. Journal creation must reject unresolved records even if a caller bypasses the UI. Surface a persistent recovery action and keep the original snapshot until restoration is verified.

**Acceptance:** failed launch recovery followed by Apply never overwrites the original journal. All manager, menu, shortcut, Settings, and Focus paths share the gate. Test failed read, write, restart, verification, and clear operations with fake backends.

### R05 — P1: active native profile can describe a layout that was never applied

**Source-confirmed.** Creating a native profile immediately changes `activeNativeProfileID`; deleting the active native profile selects the first remaining one. Neither action applies that selected layout.

Evidence: [createProfile](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Persistence/ProfileStore.swift:64), [deleteProfile](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Persistence/ProfileStore.swift:125), [native autosave binding](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/NativeDockAutoSaveMonitor.swift:31).

Consequences: incorrect checkmarks and status; automatic native-layout saving can attach later external changes to the wrong saved profile.

**Change:** distinguish selected editor profile from successfully applied native profile. Create/duplicate should select for editing. Deleting the applied profile should clear that association, or apply a fallback through an explicit successful transaction. Never infer application from selection.

**Acceptance:** create, duplicate, delete, apply failure, and external Dock edits leave status truthful. Autosave writes only to the verified association. Saving an inactive native layout does not change the actual Dock or active marker.

### R06 — P1: imported timer numbers can crash rendering

**Source-confirmed boundary gap.** The decoder accepts unrestricted durations and elapsed values. Backup validation checks size, counts, URLs, and icons, but not those numeric domains. `timerText` directly converts a rounded `Double` to `Int`.

Evidence: [duration decoding](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Models/DockModels.swift:551), [countdown decoding](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Models/DockModels.swift:601), [backup validation](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Backup/BackupManager.swift:129), [timer formatting](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/WidgetViews.swift:1463).

A valid JSON `countdownDurationSeconds: 9223372036854775807` fits `Int` but converts to a `Double` outside the representable `Int` range after rounding. A safe scalar check returned `Int(exactly: displayedValue) == nil`; the formatter's direct initializer can trap. Huge negative elapsed values create another route to an excessive remaining time. The application crash itself was not induced.

**Change:** use shared semantic validation for disk state, backup import, and store mutations. Bound finite durations, elapsed values, reminder amounts, nested counts, chart data, and dates to defined product domains. Harden all numeric formatting regardless of input source. Return an actionable import report instead of allowing invalid state into the renderer.

**Acceptance:** boundary and malformed fixtures cannot crash, overflow totals, create impossible schedules, or destroy a recoverable store. Unknown widget kinds should remain safely representable with a clear unsupported state.

### R07 — P1: compact data can remain stale indefinitely

**Source-confirmed.** Stripe, Paddle, Shopify, Stock, Watchlist, AI Limits, and AI Activity compact views display saved snapshots. Their refresh tasks live inside popout views. Closing the popout removes the refresh owner; relaunching without opening it can leave old compact data on screen indefinitely.

Evidence: [Stripe compact/provider](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/StripeWidgetViews.swift:1), [Stripe refresh task](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/StripeWidgetViews.swift:149), [Stock compact](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/StockWidgetViews.swift:25), [AI Limits compact](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/AIUsageWidgetViews.swift:24); Paddle and Shopify use the same pattern.

**Change:** move refresh ownership to a shared widget-data coordinator keyed by provider/account/query. Compact views and popouts subscribe to the same snapshot. Coalesce duplicate queries, respect provider limits, suspend unnecessary polling while hidden, refresh after wake/connection changes, and retain the last successful value with explicit age/error status.

An age check using `Date.now` in a static body does not make the stale badge advance by itself. Use a lightweight age timeline or coordinator event. Never present cached data as newly fetched.

**Acceptance:** visible compact data refreshes without opening any popout. Two widgets for the same query make one request. Hidden widgets stop unnecessary work. Failure keeps the last value labeled with age; a changed account cannot receive another account's late response.

### R08 — P1 reliability risk: slow external apps can block the UI

**Risk supported by source.** Window enumeration performs synchronous Accessibility calls across regular apps on the main actor without setting a messaging timeout. Now Playing executes synchronous AppleScript and Music artwork reads on the main actor as well.

Evidence: [window enumeration](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/WindowAccessibilityService.swift:36), [main-actor refresh](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/WindowAccessibilityService.swift:195), [Now Playing execution](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/NowPlayingService.swift:295). Badge reading already demonstrates an explicit AX timeout elsewhere.

**Change:** use bounded service workers for cross-process operations and immutable snapshots for UI publication. Set AX timeouts, coalesce requests, limit concurrency, and use event observation where useful. For automation, choose an execution mechanism that supports a deadline and termination; moving an unbounded call off the main thread alone does not establish cancellation.

**Acceptance:** an unresponsive target app cannot freeze profile switching, pointer response, or the workspace. Timed-out operations degrade to an icon/status and remain retryable. Record latency in development diagnostics without logging personal content.

## 5. Dock behavior, layout, and motion

| ID / priority | Evidence and current effect | Required change and completion criterion |
| --- | --- | --- |
| R09 / P2 — reveal dwell bypass | `updateAutoHide` checks `shouldRevealImmediately` before edge dwell. The expanded frame is padded by 10 pt and includes the edge/handle for the computed layout. [Policy](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/CustomDockWindowController.swift:491), [placement](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/CustomDockWindowController.swift:183) | Separate hidden reveal eligibility from visible retention. Hidden: edge + dwell only. Visible: Dock/popout retention bounds. Test the actual generated bottom/left/right geometry with handle on/off; passing a disconnected synthetic frame is insufficient |
| R10 / P2 — panel size differs from content | Panel placement measures `profile.items`; the SwiftUI estimate separately includes visible items, runtime apps, Trash, and minimized windows. [Panel](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/CustomDockWindowController.swift:183), [view estimate](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/CustomDockWindowController.swift:942) | One ordered runtime item model must feed geometry, overflow, scrolling, and hit testing. A widgets-only or empty pinned profile with running apps must expand correctly; hidden Now Playing must reclaim space; window changes must resize the panel |
| R11 / P2 — magnification excludes runtime apps | Magnification resolves indices only in `profile.items`; running apps have newly constructed item UUIDs. [Magnification](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/CustomDockWindowController.swift:1432), [runtime apps](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/CustomDockWindowController.swift:1508) | Use stable render IDs and continuous pointer position. Include runtime apps consistently; reserve overscan and adjust neighbor layout/hit areas. Test the first/last tile, overflow boundaries, side edges, and Reduce Motion |
| R12 / P2 — drag has no complete insertion model | Drop handlers insert before a target; there is no clear terminal insertion target. Spacers bypass normal draggable tiles. Pin/unpin divider exists only when running apps exist. [Dock items](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/CustomDockWindowController.swift:1050), [manager drops](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/DockManagerView.swift:322) | Typed drag payload, stable item IDs, before/after/end/empty targets, visible insertion indicator, auto-scroll, and cancel semantics. Support moving selected groups and spacers; allow pin/unpin with zero other runtime apps |
| R13 / P2 — Trash is not the final system item | Automatic Trash is rendered before running apps and minimized windows. [Ordering](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/CustomDockWindowController.swift:1065) | Define pinned → running → minimized → system Trash, with one final Trash and relevant menus. End-jump must reveal the actual terminal item. An automatic Trash must not offer meaningless duplicate/pin actions |
| R14 / P2 — show/hide snaps | Panel reveal uses `orderFrontRegardless`; hide uses `orderOut`; geometry updates disable animation. Broad item animation also observes full item values, including changing data. [Visibility](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/CustomDockWindowController.swift:420), [placement](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/CustomDockWindowController.swift:205) | Add one interruptible motion coordinator. Animate visibility and structural identity changes deliberately; keep text/snapshot updates from moving the entire Dock. Reverse an in-flight reveal without flicker; respect reduced motion |
| R15 / P2 — window identity can target the wrong window | Restore falls back to first matching title, then current array index. Duplicate titles and a changed window list can select the wrong target. [activate](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/WindowAccessibilityService.swift:95) | Retain validated live AX identity where feasible; only use a unique title fallback and verify PID/identity before action. Fail visibly instead of guessing from a stale index. Test duplicate names, closed windows, relaunch, and window reordering |
| R16 / P2 — missing production visibility policy | No explicit Mission Control suppression or expanded-window fitting implementation was found; fullscreen support currently relies on window collection behavior | Add a capability-aware visibility state machine and evaluate a supported approach to Mission Control/Space changes. Test fullscreen dwell and existing-Space restore on real displays. Optional fit-to-Dock must record and restore only adjustments MyDock owns; do not add brittle window manipulation merely for parity |
| R17 / P2 — redundant updates and broad invalidation | Both the app delegate and `CustomDockWindowController` subscribe to the whole store and call `update`; each update recreates the root and places the panel. [App subscriber](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/MyDockApp.swift:115), [controller subscriber](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/CustomDockWindowController.swift:61) | Keep one controller subscription, derive narrow layout/appearance/runtime streams, and compare before updating frames. Note typing and cached-metric refresh must not rebuild menu, reposition panel, and reconfigure every monitor twice |
| R18 / P2 — quiet failures and missing target repair | Launch return values are ignored; missing top-level apps/files require re-adding. Links without a symbol/favicon use `icon(forFile: url.path)`. [AppLauncher](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/AppLauncher.swift:11) | Return launch outcomes, show compact progress/failure, resolve moved apps by bundle identifier, offer Locate/Replace, and use a globe fallback for websites. Keep title/order/configuration when repairing a reference |

### Proposed motion specification

These are starting design values to tune in the production panel, not measured performance claims.

| Interaction | Starting specification | Rules |
| --- | --- | --- |
| Normal edge reveal | 250–350 ms dwell, followed by 160–200 ms short inward slide and fade | Dwell applies only while hidden; cancel immediately when pointer leaves the edge |
| Fullscreen reveal | Separate longer dwell, initially 350–500 ms | No accidental reveal while interacting with a fullscreen app's ordinary content |
| Hide | 100–180 ms departure grace; 140–180 ms outward slide/fade | Stay open for active popouts, dragging, and keyboard interaction; stop monitor work after visibility completes |
| Hover magnification | Continuous falloff based on physical pointer distance; spring settling roughly 120–180 ms | Preserve bottom/side baseline; stable IDs; neighbors move enough to avoid overlap; cap expansion at screen limits |
| Reordering | Live insertion gap with roughly 120–180 ms layout transition | Animate ordered IDs rather than snapshots; drag image tracks the pointer without a delayed spring |
| Profile switch | Brief fade/size transition around a stable anchor | Never sweep old items through new items; defer while dragging or applying a transaction |
| Popout | 100–160 ms restrained opacity/scale from the actual anchor | Open toward screen center, clamp to visible bounds, preserve editor state when changing tabs |
| Reduced motion | Immediate positioning, subtle short opacity change where appropriate | No wave magnification, spring bounce, or attention loops |

Implement motion after the unified geometry model. Otherwise animation will make incorrect sizes, anchors, and hit areas more noticeable.

## 6. UX and UI redesign brief

### Keep the unified workspace, make it useful

The unified Your Docks / Settings window is a good direction. The current dark preview is readable, but the manager is dominated by empty canvas, a large serif profile heading, generic square tiles, and repeated item counts. Settings relies on long vertical lists and explanatory paragraphs. Appearance has many controls without showing their combined result.

**Proposed manager layout:** a compact profile sidebar; one toolbar with profile name, applied/draft status, Add, and Use Profile; a central preview using the actual Dock renderer; an inspector for the selected item; a clear Save/Discard area only when there is a draft. Preserve native keyboard navigation and split-view resizing.

The preview must render actual widget data, material, size, spacing, labels, position, overflow, and missing targets. Provide a clearly labeled sample-data mode so credential-free presets can be inspected. Editing preview data must never start a real timer, run a Shortcut, send AirDrop, or request a permission accidentally.

**Proposed Settings layout:** retain the current pages, add a small persistent Dock preview on Appearance and Behavior, make setting scope explicit, and show concise rows with secondary explanations only where they help a decision. Search should find a setting and navigate/highlight it, rather than only filter page names.

### R19 — P2: scope and theme behavior are surprising

Appearance presets currently reset material, tint, corners, size, spacing, and widget style together. All but profile color are global. Editing Appearance affects the active profile, which can differ from the profile selected in the manager.

Evidence: [preset mutation](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/SettingsView.swift:548), [settings model](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Models/DockModels.swift:1019).

**Change:** split Material, Density, and Complete Theme into distinct controls. A complete theme shows exactly which settings it changes and offers Undo. Support global defaults with optional profile overrides. Show “Editing appearance for [profile]” or “Global defaults” explicitly. Separate Dark/Light/System color scheme from physical material.

**Acceptance:** changing Frosted to Glass preserves custom spacing and card style; choosing a complete theme previews all changes; switching profiles restores their overrides; resetting defaults has defined scope.

### R20 — P2: onboarding disclosure and completion need correction

The final setup screen says the macOS Dock will not change until a native profile is applied, while custom-main mode later sets the Apple Dock's auto-hide preference. That message is too broad. Finishing also closes setup without checking whether the store persisted successfully. A replacement profile begins mainly with widgets, which may leave users without their expected pinned apps.

Evidence: [final disclosure](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/OnboardingView.swift:217), [finish](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/OnboardingView.swift:243), [replacement-mode synchronization](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/MyDockApp.swift:125).

**Change:** show a mode-specific final summary: which Dock appears, whether Apple Dock auto-hide changes, how it restores, chosen screen/edge, and what the initial profile contains. Offer copying compatible pinned apps into the custom profile without altering the native layout. Keep setup open on persistence or replacement-mode failure and offer a useful retry.

### R21 — P2: integrations are fragmented and copy is inconsistent

Settings shows Stripe explanatory text and Market/Copilot credentials, but Paddle/Shopify are configured elsewhere. Stripe text says only Balance and Subscriptions, while the provider requests Account and Balance Transactions as well; the popout also directs users toward Settings inconsistently.

**Change:** a single Connections page with provider cards: connected identities, exact read scopes, last success, affected widgets, Test Connection, Replace Credential, and Disconnect. Widget popouts should link directly to the right setup card and can keep a concise contextual connect flow. Use one source for scope text and validation rules.

### Typography, spacing, and surface rules

| Area | Adjustment |
| --- | --- |
| Workspace headings | Use a compact system heading hierarchy for routine editing. Reserve the serif treatment for a welcome/marketing moment if retained |
| Sidebar | Profile name, kind, active marker, dirty marker, and optional shortcut. Add search when the list grows; support profile reorder and rename in place |
| Settings content | Start near a 640–720 pt reading width and 20–24 pt section spacing; reduce overly wide text and unnecessary top chrome |
| Dock surfaces | One main material surface. Use inner cards only when their information structure justifies them; avoid blur inside blur inside blur |
| Widget labels | Current 5–9 pt microtext and scaling are too aggressive for primary information. Favor a readable primary number/name, hide optional detail at small density, expose full values in accessible labels/tooltips |
| Information cards | Compact / Standard / Wide must change useful content layout. Current wide cards mainly add label room around a 54 pt compact renderer |
| Actions | One primary action per context. Use consistent verbs: Add, Save Changes, Use Profile, Customize, Disconnect, Restore |
| Empty states | Explain the next action with a real Add button and a rendered example; avoid a large empty decorative canvas |
| Failures | Error + last good state + a direct corrective action. Avoid silent no-op buttons or a generic “refresh” when the real issue is a missing connection |
| Small displays | Test 1280×800 and common scaled resolutions; ensure minimum window sizes and sheets fit without hiding the primary action |

### Icons and product identity

The app icon communicates a floating shelf with cards and already has an independent visual concept. Keep that direction. Simplify small-size details, tune shelf/card contrast, and optically correct the 16/32 px versions rather than only scaling the large composition. The current large icon is clean but its tiny text strokes and dots may collapse at menu/sidebar sizes.

Use platform app icons at their natural silhouette. Use one SF Symbol size/weight convention for utilities and one token palette for profile/category accents. Consolidate the duplicated profile colors in `DockDesign`, Dock rendering, and App Folder. Category dots currently resemble status indicators; either make them clearly categorical or reserve colored dots for actual state.

Define distinct markers for active profile, running app, badge count, stale data, missing reference, draft, and error. Use shape/text as well as color. Do not make a category accent look like an alert or unread badge. Give link icons an explicit globe fallback and allow resetting a custom override to the site icon.

### Widget popouts

Create a shared popout frame with icon/name, Close, Refresh where relevant, connection/permission state, content, and a consistent Customize area. Each provider supplies content and actions rather than repeating header, error, save, and account controls.

Normalize width classes, scrolling, focus placement, Escape/Command-W behavior, loading placeholders, and restoration of in-progress input. Preserve per-widget state when moving between tabs; a popout should anchor to the active item or clearly communicate its grouped host. Tall content must fit the available display height.

## 7. Presets: turn an existing advantage into a polished feature

Current presets are four hardcoded app/widget combinations. They choose installed alternatives well, but the picker shows names rather than a rendered Dock. Selecting a preset creates/activates an empty profile, then separately replaces items and applies color.

Evidence: [preset picker and creation](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/DockManagerView.swift:632), [preset definitions](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/DockManagerView.swift:1012).

**Change:** model a preset as metadata + layout + appearance + widget configuration + app alternatives. Resolve it into a complete proposed profile, preview it, allow substitutions, and commit that complete profile atomically. Offer Create Profile and, separately, Use Now. Persist user-defined presets after removing personal content and connection identifiers by default.

| Initial preset | Proposed content | Why |
| --- | --- | --- |
| Everyday | Finder, preferred browser, communication app, Calendar, Weather, Battery | Practical first run with familiar apps and useful status |
| Deep Work | Editor, browser, chosen project folder, Focus Timer, Hydration, Sticky Note | A small task-focused Dock with clear timer behavior |
| Development | Editor, Terminal, browser, project folder, System Activity, optional AI Limits | Preserve the existing useful developer direction; disclose unavailable providers |
| Creative | Design app alternatives, project folder, reference file, Now Playing, Sticky Note | Useful file access without turning the Dock into a dashboard |
| Travel / Minimal | Browser, Calendar, Battery, World Clock, optional Weather | Lower information density; no credential requirement |

Do not auto-add business widgets to a default preset. Offer a Business template only with explicit sample data and a clear connect step. Avoid preset duplication purely to increase count.

**Acceptance:** missing apps are substituted or visibly omitted; no blank intermediate Dock appears; cancel changes nothing; one creation emits one complete profile update; preview can show all edges and small/large density; user presets exclude secrets and optionally personal notes/history.

## 8. Every registered widget: status and next improvement

This table covers all 27 providers. “Exists” means a real source implementation was found, not that every provider has been validated with live accounts or hardware.

| Widget | Current implementation | Next change / verification |
| --- | --- | --- |
| Clock | Local clock/date formatting and compact/popout views | Consistent 12/24-hour presentation, readable small density, locale/DST/midnight visual checks |
| World Clock | Searchable system time-zone city catalog and additional zones | Distinguish same-named cities, home/remote day difference, sensible ordering; test long labels and DST boundaries |
| Stopwatch | Persistent state plus a sleep-inclusive monotonic anchor | Preserve this clock model; validate reboot fallback and extreme elapsed values; optionally add laps after core reliability |
| Countdown | Duration and absolute target modes, notification generation guards | Fix R03, harden R06; verify completion with popout closed, permission denied, sleep, wall-clock changes, and app relaunch |
| Time Progress | Calendar-based day/week/month/year progress | Label week convention and timezone consistently; midnight/DST/leap-year checks; avoid recreating formatters every tick |
| Focus Timer | Persistent start/pause/reset with view-owned completion tasks | Move completion ownership to timer service; optional reliable completion alert and explicit finished state; profile switches must not govern timer semantics |
| Sticky Note | Debounced draft saving, flush-on-close/quit, color choices | Protect against R01; plain text paste and long-note behavior; count/limits only if necessary; Undo works as users expect |
| Hydration | Amount/history controls, grouped history, removal/undo, reminders | Add a day-boundary refresh: compact count currently derives Today without a timeline. Verify reminder restart, time-only records, persistent undo semantics, and caps |
| Battery | Public power-source percentage/charging/internal readings | Richer supported condition/health/power details, explicit full charge state, good desktop/no-battery state; do not promise unavailable accessory data |
| App Folder | App collection, local customization, order controls, missing-app replacement | Reuse its Replace pattern for top-level items; keyboard grid navigation, drag reorder, bundle-ID repair, and live compact identity |
| Shortcuts | Bounded catalog command; execution service prevents duplicate runs | Add cancel/status handling for long runs, avoid indefinite “Running” after app exit, allow direct Run as an explicit option; do not constrain intentional interactive shortcuts with an arbitrary short timeout |
| Calendar | Actor-isolated EventKit, selected calendars, next event, meeting links | Share compact/popout data; robust permission revocation and calendar deletion; busy/all-day/timezone/duplicate-title QA |
| Reminders | EventKit lists, add and complete, authorization guards | Event-driven refresh, keyboard add/complete, completion feedback/Undo, unavailable list recovery; permission/live data tests still needed |
| Alarm | One-time/repeating notifications and startup reconciliation | Verify DST, timezone change, partial schedule failure, macOS notification cap, fired one-time state, and removal across profiles |
| System Activity | CPU/per-core/load/thermal/uptime, memory/pressure, storage scan | Keep user-triggered bounded scans. Mark partial scans clearly; consider allocated disk size vs current logical file size; ensure concurrent sample requests do not reorder baselines |
| Network Activity | Interface counters and rate calculation, shared monitor | Active interface vs aggregate clarity, byte-rate units, sleep/wake baseline resets, VPN/bridge double-counting explanation; optional connection details where APIs permit |
| AirDrop | File/link drop loading and native sharing pickers | Native popout drop target registers only file URL even though it checks URL objects: verify/extend link registration. Surface rejected drops, preserve order, and anchor on all Dock edges |
| Trash | Home Trash count/watcher, Finder open/empty with confirmation | Fix final ordering; include mounted-volume Trash semantics if supported; watcher rebind after rename/delete; accurate unreadable state instead of implying empty |
| Now Playing | Music/Spotify automation, shared subscriptions, artwork, controls | Bound automation latency; metadata transport robust to embedded newlines; avoid clearing good data on transient read failure; richer 54 pt vs wide layouts |
| Weather | Open-Meteo, search/current location, cached forecast, unit/layout controls | Shared cache/query ownership, timeout for unresolved location request, visible cache age, compact layout that actually uses wide-card space; offline/sleep/long-city QA |
| Stock | End-of-day Alpha Vantage data, symbol search, price/chart/range controls | Compact refresh R07; truthful range coverage R22; market date/currency/error labels; rate-limit aware shared cache |
| Watchlist | Multiple stock snapshots and selected compact symbol | Coalesce with Stock, bounded batch refresh, show partial failure per symbol, preserve selection after deletion, usable keyboard search |
| Stripe | Restricted key, account/balance/subscription/transaction parsing, currency separation | Compact refresh, unified scopes/setup, exactly defined revenue vs balance metrics, partial pagination/error fixtures, live read-only account validation |
| Paddle | Billing API data and chart/configuration | Compact refresh; clearly separate current snapshot metrics from period metrics; validate read-only key requirements and partial responses with a real account |
| Shopify | Same-organization client credentials, GraphQL pagination, token caching | Compact refresh; explain store/org and order lookback limitations; account switching, token expiry, pagination/missing data, and defined gross/net/refund metric tests |
| AI Limits | Codex reader, configured Claude snapshot, personal Copilot billing; unavailable adapters for others | Capability badges, age/reset labels, compact refresh, no fake zero percentages; safe provider-specific setup and source validation |
| AI Activity | Local Codex/Claude/Grok usage field parsing; estimates/partial labels | Incremental file-offset/index cache instead of repeated large scans; cancellation checks throughout traversal/parsing; clear local-only coverage and day attribution |

### R22 — P2: the “1Y” range does not provide a year

`StockChartRange.year` is labeled `1Y` but uses 100 points, while requests use Alpha Vantage's `compact` output. Actual date labels beneath the chart help, but do not make the range selector accurate. [Range model](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Models/DockModels.swift:274), [request](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/MarketDataService.swift:81).

Alpha Vantage documents compact daily output as the latest 100 data points; full history depends on the endpoint/access tier. [Official API documentation](https://www.alphavantage.co/documentation/).

**Change:** derive date ranges from actual trading dates. Request/cache sufficient history where available; disable unavailable ranges with a useful explanation or label the fallback as “100 sessions.” Compute change from the chosen chart period if that is the displayed claim; keep daily change separately labeled.

### Cross-widget data contract

Every data widget should express: unconfigured, requesting permission, loading, ready, refreshing with last value, stale, partial, unavailable, and failed. The visual shell decides how those states look; provider services supply typed state and corrective actions. Distinguish no data from a measured zero. Name the period, unit, currency, source, and age where those distinctions affect interpretation.

## 9. Architecture and maintainability

### Preserve these strengths

- Native SwiftUI/AppKit with no declared third-party Swift packages.
- Injectable native Dock backend, serializer, transaction journal, verification, rollback, and a shared operation gate.
- Separate exact auto-hide restoration record, including the case where the original preference was absent.
- Atomic state writes, newer-schema protection, and preservation of undecodable state.
- Bounded backup reads, count caps, URL/icon validation, fresh imported identities, and disabled duplicated alarm/reminder schedules.
- Keychain credential separation; portable profile backups exclude those credentials.
- Bounded subprocess capture and useful cancellation/output-limit tests.
- Redacted typed diagnostics, shared refresh scheduling, optional permissions, and reduced-motion/transparency adaptation.
- Immutable EventKit snapshots, generation-aware notification operations, monotonic stopwatch time, and bounded preview caching.

### Proposed module ownership

| Module / service | Owns | Must not own |
| --- | --- | --- |
| Profile repository | Validated profiles, revisions, migrations, atomic persistence, write status | Window visibility, network requests, SwiftUI local drafts |
| Edit-session coordinator | Base snapshot, changes, merge/conflicts, Undo, save/quit decisions | Provider credentials or real Dock writes |
| Dock render model | Stable ordered pinned/runtime/window/Trash IDs, visible content and measured geometry | Storage mutation on body evaluation |
| Dock visibility/motion controller | Visibility state, reveal dwell, transitions, pointer/drag/popout retention | Widget polling and duplicated whole-state subscriptions |
| Profile activation coordinator | Custom selection and native apply/recovery status through one path | Silent association changes from create/delete |
| Widget data coordinator | Shared subscriptions, query keys, refresh/backoff, snapshot freshness | View-specific input drafts or blanket profile replacement |
| Timer/notification coordinator | Deadlines, schedule generations, startup/wake reconciliation, completion | Dependence on a compact view remaining mounted |
| Connections repository | Keychain identities, capability/scope state, reference cleanup | Secrets in backups or generic diagnostic strings |
| Design system | Colors, metrics, icon roles, typography, common popout/state presentation | Provider business rules |

The large files are a maintenance signal: `CustomDockWindowController.swift` 1,584 lines, `WidgetViews.swift` 1,552, `DockModels.swift` 1,159, `DockManagerView.swift` 1,054, `SettingsView.swift` 955. Split by these responsibilities while fixing defects, not by arbitrary line-count targets.

### Persistence and migration

The main actor currently encodes and atomically writes the entire pretty-printed state for every commit. Notes, live snapshots, and UI settings all share that path. Large profiles can therefore make frequent small edits expensive.

Move encoding/writes to a serialized writer with immutable snapshots and revisions. Coalesce suitable rapid edits, retain explicit flush behavior at save/quit, and ensure an older write cannot complete after a newer one. Keep errors observable. Separate transient provider caches from user-authored layout/configuration where practical; choose backup inclusion explicitly.

Add a semantic migration layer and fixture corpus for old schemas. Unknown enum values should degrade deliberately where safe instead of turning one future setting into an unreadable entire state file. Preserve recovery originals. Define nested limits as well as archive-size limits.

Consolidate the two registry concepts, provider metadata, supported sizes, configuration capabilities, and permission requirements. Replace string widget kinds incrementally with stable identifiers while decoding old names. Remove or clearly isolate redundant/unused UI paths such as the separate SwiftUI menu implementation after confirming references.

## 10. Performance, accessibility, privacy, and recovery

### Performance work to measure

No CPU, memory, frame-time, or battery superiority claim was measured in this review. Establish baselines before setting release budgets.

| Scenario | Measure | First optimization |
| --- | --- | --- |
| Hidden empty Dock | CPU wakeups, timers, cross-process requests | Stop work with no visible subscribers; event-driven running-app updates |
| Visible apps-only Dock | Frame pacing during hover/reorder, main-thread time | Stable identity, narrow subscriptions, one geometry update path |
| 20 mixed widgets | Request count, redraws, memory, save latency | Shared query cache, bounded refresh concurrency, separate runtime data |
| Hung Music/AX app | Worst input stall and timeout | R08 bounded workers |
| Large backup/note/history | Decode/encode duration, peak memory, UI blocking | Semantic caps, off-main serialization, incremental changes |
| Large AI history | Files/bytes processed per refresh, cancellation latency | Incremental index; cap total scanned bytes/time, not just per-line size/file count |
| Many thumbnails | Cache cost and in-flight work | Add NSCache count/cost limits and cancellation; avoid repeated icon/file reads during body evaluation |
| Sleep/display disconnect | Stale baselines, refresh burst, frame relocation | Reset sampling baselines and coalesce wake refresh; stable display fallback |

Initial acceptance targets should be relative to a recorded baseline: no avoidable polling while hidden, no repeated identical account requests, no unbounded external call on the main thread, and no stale save replacing a newer revision. Tune frame budgets against both 60 Hz and high-refresh displays.

### Accessibility and input

Run VoiceOver through setup, profile selection, reorder, item activation, configuration, permission recovery, and Quit. Drag-only interaction needs keyboard Move Before/After/Start/End alternatives and Undo. Add accessible labels/values to icon-only controls and live metrics; prevent a one-second clock from flooding announcements.

Test Reduce Motion, Reduce Transparency, Increase Contrast, large text/zoom, bright/dark/high-detail wallpapers, and keyboard-only use. The Dock already has display preference handling; the manager, popouts, indicators, and theme previews need the same intentional treatment. Avoid color-only category/status distinction.

### Privacy and recovery

Keep current permission-on-use and Keychain practices. Explain permission purpose beside the feature and show usable fallbacks. Permissions should refresh automatically when the app becomes active after System Settings, with manual Refresh retained as a fallback.

Backups intentionally contain notes, history, URLs, and cached provider snapshots even though they exclude credentials. Offer “layout only” and “include personal widget data” export choices. On another Mac, detect missing connection IDs, label widgets disconnected, and offer remapping to a local account instead of silently showing stale saved metrics.

Window screenshots remain local and expire; preserve that design. Make retention visible, clear caches when permission is revoked, and test cleanup after restart. A hashed filename does not make the screenshot itself anonymous.

Provide a recovery center for failed persistence, unresolved native transactions, auto-hide restoration, missing references, and disconnected accounts. Give each failure a specific Retry/Locate/Restore action. Add a small local profile revision history for accidental edits; distinguish it from native preference rollback.

## 11. Build, distribution, tests, and documentation

`BuildMyDock.sh` already builds both CPU slices, checks source fingerprints, refuses to overwrite a running output, generates an icon, and signs locally. Preserve those safeguards.

The distribution flow still needs a publisher-owned Developer ID signature, appropriate hardened-runtime entitlements, notarization/stapling, reproducible version/build numbers, and install/update validation. The shell build uses ad-hoc signing; the Xcode Release target declares hardened runtime, so verify that the eventual distribution path has equivalent settings rather than assuming the two build paths are identical.

Add CI for unit tests and both release slices, plus a scheduled supported-macOS compatibility matrix. Test a clean install, second launch, duplicate instances, migration, update with saved data, and uninstall after replacement mode. Consider Launch at Login and a trusted update flow as later product work; neither should precede the data-safety fixes.

Current UI XCTest primarily checks that preview windows exist and attaches screenshots. That is useful capture infrastructure, but it does not assert save/quit safety, selection semantics, overflow, drag behavior, or actual Dock policy. Add interaction assertions for those behaviors and reviewed screenshot baselines for important layouts. Keep tests behavior-driven rather than mirroring implementation functions.

Existing audits are useful context, but their dates and “current” titles overlap. `docs/reference/VISUAL_PARITY.md` still contains earlier separate-manager/Settings dimensions and accumulated historical observations; `docs/ARCHITECTURE.md` describes seven unit test files where the current test suite has eight. Use one current product status document, one feature/capability matrix, one acceptance plan, and an archive for prior audits. Every “verified” claim should name its build, platform, date, and method.

### Release validation matrix

| Area | Required scenarios | Status in this review |
| --- | --- | --- |
| State/drafts | Concurrent live edits, save failure, quit/cancel, import merge, delete/Undo | Two losses reproduced; current unit suite passes; fixes needed |
| Native Dock | Apply, rapid switch, verification failure, rollback, restart recovery, absent preference, autosave association | Fake backend coverage; live apply/restore unverified |
| Replacement mode | Enter, leave, quit, crash/relaunch, restart failure, external preference change | Source/tests reviewed; live preference restoration unverified |
| Custom panel | All edges, auto-hide, hidden handle, fullscreen, Mission Control, desktop mode, Apple Dock overlap | Source audit; isolated preview does not exercise production controller |
| Displays/Spaces | Retina/non-Retina, mixed scaling, negative coordinates, disconnect/reconnect, Space change | Unverified |
| Dock content | Empty, one item, runtime-only, many widgets/windows, hidden media, final Trash, overflow endpoints | Source gaps identified; comprehensive live matrix outstanding |
| Motion/input | Continuous hover, interrupted reveal, drag/end targets, swipe vs scroll, keyboard alternatives | Source gaps identified; measured production motion outstanding |
| Widget service state | Offline, revoked permission, expired token, rate limit, malformed/partial data, changed account | Fixtures cover selected services; complete live provider matrix outstanding |
| Notifications/time | Pause/resume, DST, timezone change, sleep/wake, app closed, notification cap | R03 identified; complete system validation outstanding |
| Accessibility/visual | Light/dark, contrast/transparency/motion, VoiceOver, small screen, long localized text | Dark default preview inspected; broad matrix outstanding |
| Distribution | arm64/Intel, macOS 13/14/15/26, signed/notarized clean install/update | Fresh arm64 Release compile passes; runtime/distribution matrix outstanding |

## 12. Orchestrator backlog and execution order

Owners below describe responsibilities for implementation, not agents spawned during this review. Effort is relative scope: S = localized, M = several components, L = foundational. Dependencies matter more than calendar guesses.

| Ticket | Priority / scope | Responsible area | Depends on | Definition of done |
| --- | --- | --- | --- | --- |
| T01 Draft merge safety | P1 / L | State + manager | — | R01 concurrent edit matrix passes; no full stale snapshot replacement |
| T02 Unified quit/save policy | P1 / M | State + app lifecycle | T01 | R02 Save/Discard/Cancel behavior covers all edit-session exits |
| T03 Countdown deadline | P1 / S | Timer service | — | R03 UI/notification agreement and scheduling race tests |
| T04 Recovery health gate | P1 / M | Native Dock | — | R04 journal preserved across repeated failure; actionable recovery UI |
| T05 Applied native association | P1 / M | Activation + autosave | T04 | R05 create/delete/save semantics truthful on every activation path |
| T06 Semantic validation | P1 / M | Models + backup | — | R06 invalid state safely rejected/normalized; formatting cannot trap |
| T07 Shared widget freshness | P1 / L | Data services | T01 | R07 visible compact refresh, query coalescing, stale/error states |
| T08 Bounded external calls | P1 / M | AX + automation | — | R08 hung targets leave UI responsive and retryable |
| T09 Unified render geometry | P2 / L | Custom Dock | T06 | R10 panel/content agreement with all dynamic item classes |
| T10 Visibility state machine | P2 / M | Custom Dock | T09 | R09 correct dwell/retention; R16 tested supported policies |
| T11 Typed complete drag model | P2 / M | Dock + manager | T01, T09 | R12 endpoint/empty/spacer/group drag and keyboard move work |
| T12 Runtime identity/order | P2 / M | Dock + AX | T08, T09 | R13 final Trash; R15 unique window restore and safe fallback |
| T13 Motion and magnification | P2 / L | Dock interaction | T09–T12 | R11/R14 continuous motion, correct bounds, interruption, reduced motion |
| T14 Narrow updates/writer | P2 / M | State + controller | T01, T09 | R17 one update owner; revision-ordered off-main writes and flush |
| T15 Real manager preview | P2 / L | Workspace + design | T01, T09 | Same renderer and appearance as live Dock; safe sample mode |
| T16 Profile appearance scope | P2 / M | Models + Settings | T06, T15 | R19 inheritance/overrides, independent controls, preview and Undo |
| T17 Atomic preset flow | P2 / M | Manager + models | T01, T15, T16 | Complete previewable profile committed once; app substitution and cancel verified |
| T18 Onboarding completion | P2 / M | Setup + activation | T04, T05, T17 | R20 accurate summary, pinned-app option, persistent failure recovery |
| T19 Connections center | P2 / M | Services + Settings | T07 | R21 scopes/setup consistent; account remapping and cleanup verified |
| T20 Popout design system | P2 / M | UI + widgets | T07, T15 | Shared state shell, width/height rules, focus/close/customize behavior |
| T21 Reference repair/icons | P2 / M | Launch + design | T09, T20 | R18 launch result/repair/globe fallback; shared palette and status language |
| T22 Market history contract | P2 / M | Market data | T07 | R22 honest range/date/change semantics under limited history |
| T23 Widget lifecycle sweep | P2 / M | Widget services | T03, T07, T08 | Timer ownership, hydration midnight, Trash watcher, AirDrop links, media parsing covered |
| T24 Accessibility/search | P2 / M | Workspace + Dock | T11, T15, T20 | Keyboard/VoiceOver flow; setting-level search; all accessibility variants |
| T25 Performance baseline | P2 / M | Runtime + QA | T07–T14 | Recorded comparable scenarios, bounded work, no unsupported superiority claims |
| T26 Live system acceptance | P1 release gate / M | macOS integration + QA | T01–T14 | Real apply/restore, recovery, Spaces/displays, notification scenarios verified on a disposable system |
| T27 Distribution pipeline | P1 distribution gate / M | Release | T26 | Both slices, signing/notarization/install/update and supported OS checks |
| T28 Canonical docs | P2 / S | Product + QA | Each completed ticket | Current matrix and evidence updated; historical audits clearly archived |
| T29 Recovery/history center | P3 / M | State + workspace | T01, T04, T14 | Inspectable local history and feature-specific recovery without exposing secrets |
| T30 Login/update/user presets | P3 / M | Product + release | T17, T27 | Reliable launch/update and reusable sanitized presets |

### Milestone gates

1. **Trust:** T01–T08. Do not ship a replacement-mode claim with known lost edits or recovery gaps.
2. **Dock correctness:** T09–T14. One render model, complete drag, stable windows, correct dwell, and smooth motion.
3. **Product experience:** T15–T24. Real previews, useful presets, clear scope, consistent popouts/connections/icons, accessible workflows.
4. **Release proof:** T25–T28. Measured performance, live system acceptance, compatibility, signed distribution, and truthful documentation.
5. **Differentiation:** T29–T30. History/recovery, personal presets, and convenient lifecycle features.

During implementation, keep each ticket reviewable and independently verifiable. Ship fixes behind coherent behavior rather than large unrelated rewrites. A bug fix is complete when its trigger and recovery path are covered; a visual change is complete when inspected in real light/dark/edge/overflow states.

## 13. Definition of “better than Dockset”

Use observable outcomes rather than a percentage or a feature-count score:

- Editing and quitting cannot silently lose user work, including while widgets update.
- Applying a native layout has trustworthy status and recoverable failure on all entry points.
- The preview is the actual Dock rendering and accurately predicts the result.
- Compact values stay current without requiring the user to open every widget.
- Hover, reveal, reordering, overflow, windows, and Trash behave consistently at every supported edge.
- Presets save time, show the result before creation, and adapt to installed apps.
- Small/large density, accessibility preferences, and common display configurations remain usable.
- Unsupported provider data is identified honestly; failures retain useful context and a direct recovery action.
- Performance and supported-platform claims have recorded evidence.

MyDock has enough breadth to reach that standard. The next work should make the existing software dependable and cohesive before expanding its catalog.

## Appendix A. Repository coverage inventory

The inventory below records the reviewed source surface and its size. Detailed findings above trace the highest-risk paths; inclusion does not imply live execution of every file. Existing docs, resources, project metadata, and build/test scripts are covered in sections 2 and 11.

| Source file | Lines | Area |
| --- | ---: | --- |
| [BackupManager.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Backup/BackupManager.swift) | 177 | Backup |
| [Product.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Core/Product.swift) | 8 | Core |
| [SingleInstanceLock.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Core/SingleInstanceLock.swift) | 39 | Core |
| [AIUsageWidgetViews.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/AIUsageWidgetViews.swift) | 620 | CustomDock |
| [AirDropWidgetViews.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/AirDropWidgetViews.swift) | 339 | CustomDock |
| [AlarmWidgetViews.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/AlarmWidgetViews.swift) | 215 | CustomDock |
| [CalendarRemindersWidgetViews.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift) | 663 | CustomDock |
| [FileThumbnailView.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/FileThumbnailView.swift) | 103 | CustomDock |
| [FolderContentsPopout.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/FolderContentsPopout.swift) | 111 | CustomDock |
| [FolderIconView.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/FolderIconView.swift) | 54 | CustomDock |
| [NetworkActivityWidgetViews.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/NetworkActivityWidgetViews.swift) | 225 | CustomDock |
| [NowPlayingWidgetViews.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/NowPlayingWidgetViews.swift) | 343 | CustomDock |
| [PaddleWidgetViews.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/PaddleWidgetViews.swift) | 406 | CustomDock |
| [ShopifyWidgetViews.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/ShopifyWidgetViews.swift) | 471 | CustomDock |
| [StockWidgetViews.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/StockWidgetViews.swift) | 773 | CustomDock |
| [StripeWidgetViews.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/StripeWidgetViews.swift) | 458 | CustomDock |
| [SystemActivityWidgetViews.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/SystemActivityWidgetViews.swift) | 444 | CustomDock |
| [TrashWidgetViews.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/TrashWidgetViews.swift) | 87 | CustomDock |
| [WeatherWidgetViews.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/WeatherWidgetViews.swift) | 624 | CustomDock |
| [WidgetViews.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/CustomDock/WidgetViews.swift) | 1,552 | CustomDock |
| [CustomDockWindowController.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/CustomDockWindowController.swift) | 1,584 | DockManagement |
| [DockSwitchFreezeProvider.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/DockSwitchFreezeProvider.swift) | 83 | DockManagement |
| [NativeDockAutoHideController.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/NativeDockAutoHideController.swift) | 149 | DockManagement |
| [NativeDockAutoSaveMonitor.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/NativeDockAutoSaveMonitor.swift) | 106 | DockManagement |
| [NativeDockController.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/DockManagement/NativeDockController.swift) | 339 | DockManagement |
| [FocusDockFilterIntent.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Focus/FocusDockFilterIntent.swift) | 87 | Focus |
| [DockModels.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Models/DockModels.swift) | 1,159 | Models |
| [LocalClockFormatter.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Models/LocalClockFormatter.swift) | 25 | Models |
| [StopwatchClock.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Models/StopwatchClock.swift) | 39 | Models |
| [WorldClockCityCatalog.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Models/WorldClockCityCatalog.swift) | 51 | Models |
| [MyDockApp.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/MyDockApp.swift) | 446 | Application lifecycle |
| [ProfileStore.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Persistence/ProfileStore.swift) | 422 | Persistence |
| [DiagnosticsService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Services/DiagnosticsService.swift) | 182 | Services |
| [WidgetSetupDraftStore.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Services/WidgetSetupDraftStore.swift) | 110 | Services |
| [AIUsageService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/AIUsageService.swift) | 772 | SystemServices |
| [AccessibilityDisplayState.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/AccessibilityDisplayState.swift) | 30 | SystemServices |
| [AlarmNotificationService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/AlarmNotificationService.swift) | 232 | SystemServices |
| [AppLauncher.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/AppLauncher.swift) | 37 | SystemServices |
| [BatteryReader.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/BatteryReader.swift) | 37 | SystemServices |
| [BoundedSubprocessCapture.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/BoundedSubprocessCapture.swift) | 419 | SystemServices |
| [CalendarRemindersService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/CalendarRemindersService.swift) | 270 | SystemServices |
| [CountdownNotificationService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/CountdownNotificationService.swift) | 105 | SystemServices |
| [CurrentLocationService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/CurrentLocationService.swift) | 106 | SystemServices |
| [DockBadgeService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/DockBadgeService.swift) | 135 | SystemServices |
| [FinancialCurrencyFormatter.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/FinancialCurrencyFormatter.swift) | 23 | SystemServices |
| [FolderContentsReader.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/FolderContentsReader.swift) | 26 | SystemServices |
| [GitHubCopilotService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/GitHubCopilotService.swift) | 266 | SystemServices |
| [GlobalShortcutController.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/GlobalShortcutController.swift) | 173 | SystemServices |
| [HydrationReminderService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/HydrationReminderService.swift) | 82 | SystemServices |
| [MarketDataService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/MarketDataService.swift) | 220 | SystemServices |
| [NetworkActivityReader.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/NetworkActivityReader.swift) | 124 | SystemServices |
| [NowPlayingArtwork.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/NowPlayingArtwork.swift) | 83 | SystemServices |
| [NowPlayingService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/NowPlayingService.swift) | 308 | SystemServices |
| [PaddleDataService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/PaddleDataService.swift) | 414 | SystemServices |
| [RefreshScheduler.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/RefreshScheduler.swift) | 77 | SystemServices |
| [RunningApplications.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/RunningApplications.swift) | 20 | SystemServices |
| [ShopifyDataService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/ShopifyDataService.swift) | 570 | SystemServices |
| [ShortcutsService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/ShortcutsService.swift) | 112 | SystemServices |
| [SiteFaviconFetcher.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/SiteFaviconFetcher.swift) | 207 | SystemServices |
| [StripeDataService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/StripeDataService.swift) | 503 | SystemServices |
| [SystemActivityReader.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/SystemActivityReader.swift) | 300 | SystemServices |
| [SystemDockVisibilityService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/SystemDockVisibilityService.swift) | 51 | SystemServices |
| [TrashService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/TrashService.swift) | 114 | SystemServices |
| [WeatherService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/WeatherService.swift) | 216 | SystemServices |
| [WidgetNotificationGenerationPolicy.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/WidgetNotificationGenerationPolicy.swift) | 23 | SystemServices |
| [WindowAccessibilityService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/WindowAccessibilityService.swift) | 254 | SystemServices |
| [WindowPreviewCache.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/WindowPreviewCache.swift) | 195 | SystemServices |
| [WindowPreviewService.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/SystemServices/WindowPreviewService.swift) | 110 | SystemServices |
| [AboutView.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/AboutView.swift) | 25 | UI |
| [DockDesign.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/DockDesign.swift) | 74 | UI |
| [DockManagerView.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/DockManagerView.swift) | 1,054 | UI |
| [KeyboardShortcutEditor.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/KeyboardShortcutEditor.swift) | 139 | UI |
| [MenuBarProfileTitle.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/MenuBarProfileTitle.swift) | 53 | UI |
| [MenuBarView.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/MenuBarView.swift) | 39 | UI |
| [OnboardingView.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/OnboardingView.swift) | 269 | UI |
| [SettingsView.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/UI/SettingsView.swift) | 955 | UI |
| [TimeProgressCalculator.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Sources/MyDock/Widgets/TimeProgressCalculator.swift) | 15 | Widgets |

| Test file | Lines | Coverage focus |
| --- | ---: | --- |
| [BoundedSubprocessCaptureTests.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Tests/MyDockTests/BoundedSubprocessCaptureTests.swift) | 143 | Unit fixtures and behavior |
| [DiagnosticsServiceTests.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Tests/MyDockTests/DiagnosticsServiceTests.swift) | 54 | Unit fixtures and behavior |
| [DockBadgePolicyTests.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Tests/MyDockTests/DockBadgePolicyTests.swift) | 30 | Unit fixtures and behavior |
| [GitHubCopilotBillingTests.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Tests/MyDockTests/GitHubCopilotBillingTests.swift) | 98 | Unit fixtures and behavior |
| [ProfileStoreTests.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Tests/MyDockTests/ProfileStoreTests.swift) | 2,860 | Unit fixtures and behavior |
| [SingleInstanceLockTests.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Tests/MyDockTests/SingleInstanceLockTests.swift) | 20 | Unit fixtures and behavior |
| [WeatherServiceTests.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Tests/MyDockTests/WeatherServiceTests.swift) | 71 | Unit fixtures and behavior |
| [WindowPreviewCacheTests.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Tests/MyDockTests/WindowPreviewCacheTests.swift) | 102 | Unit fixtures and behavior |
| [MyDockVisualPreviewUITests.swift](/Users/jakubjalowiecki/Documents/ChatGPT/dockX/Tests/MyDockUITests/MyDockVisualPreviewUITests.swift) | 47 | Preview capture infrastructure |
