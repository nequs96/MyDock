# What was and was not done against the professional product review

**Prepared:** 4 October 2026 (Europe/Warsaw)
**Measured against:** [PROFESSIONAL_PRODUCT_REVIEW_2026-10-03.md](PROFESSIONAL_PRODUCT_REVIEW_2026-10-03.md), the review dated 3 October 2026, with the [execution ledger](EXECUTION_LEDGER_2026-10-03.md) as the item-by-item record
**Code state:** local `main` at `7832a38`. Nothing was pushed or published.
**Canonical app:** `build/MyDock.app`, executable SHA-256 `a35bb831…f591bd`. It was rebuilt and relaunched on 4 October 2026.

## Timeline

| Date | What happened |
|---|---|
| 3 Oct 2026 | The audit, the product review and the 155-record execution ledger were written. Codex started implementing and stopped part-way; its edits were committed as `6f94afd`. |
| 3 Oct 2026 | The Claude coordinator resumed and found that Codex's code did not compile. It fixed that and ran three waves of specialist agents (reliability, native platform, product experience), each in its own worktree. Every branch was reviewed, merged one at a time, tested, built and launched. |
| 3–4 Oct 2026 | The Xcode project gap was found and fixed. The evidence documents were refreshed. |
| 4 Oct 2026 | The user approved continuing with the unfinished authorized packages (PR-13 phase 1, PR-15, PR-17, PR-20 and the loose ends). The coordinator also ran a synthetic performance baseline and an isolated render export of 143 PNGs. |

**Test results:** the suite went from 253 passing tests on the review date to **428 tests in 52 suites, 0 failed, 5 explicit opt-ins skipped**.

**Status words used below:**
- **Done** means implemented, coordinator-reviewed, merged and covered by isolated fixtures.
- **Partial** means some of the recommendation is implemented.
- **Not done** means it is authorized but was not built.
- **Deferred** means the review itself made it a product decision.
- **Blocked** means it needs an environment, account or desktop session that was not available.

**Nothing below has been accepted natively.** No VoiceOver session, live account, Xcode build or real desktop interaction was performed.

---

## 1. Reviewer assessment: the eight problem areas

| Area the review named | What changed | What is still open |
|---|---|---|
| Product clarity | The workspace caption, button help, menu bar and onboarding now explain Select, Activate and Apply, and what Apply does to Apple's Dock. | No onboarding capture or tutorial. The sidebar does not group layouts by type. "Explore" is not renamed. |
| Correctness and trust | All confirmed save/reporting, migration, parser, credential-replacement and aggregation defects (MD-A01–A06, MD-P01–P10) are fixed with fixtures. | Live-account checks are blocked. |
| Editing | Widget setup now comes before appearance. Drafts survive. Removals have undo. | No Organize/list view (Batch 3). |
| Native Dock quality | Window discovery, untitled windows and multi-copy identity (MD-D01–D03) are fixed. The resize grip is wider. Motion interruption is fixed. | All desktop acceptance is open. |
| Design | The configuration sheet, Settings header, Clock fit and Example labels changed. | The large unused editing space and Organize view are untouched. |
| Widget portfolio | A typed capability registry was added, and QA coverage now includes all 35 families. | Per-family improvements are mostly not done (section 6). |
| Performance | Routine saves are coalesced off the main thread, unrelated settings no longer reassign the Dock root, signposts were added and a synthetic baseline was recorded. | No real Instruments, frame-pacing or energy measurements. |
| Release maturity | The Xcode project is complete, and docs and evidence are truthful. | Signing, notarization, Xcode build and supported-OS matrix are blocked. |

**Recommended product promise and capability tracks:** no positioning or mode-default change was made, deliberately; the review says not to silently change modes. The new copy explains the existing tracks.

**Audience research and task studies:** not done. They require real users.

## 2. Making the whole task chain coherent

| Recommendation | Status |
|---|---|
| A stable mental model (Select, Activate, Apply, Saved, Appearance, Connections, Recovery) | **Partial.** Select, Activate and Apply are explained, and Saved means durable for critical actions. Appearance inheritance wording is in the inspector. Connections show "Credentials saved". Recovery descriptions are precise. There is no single unified status line. |
| Readable status beside the title and in the sidebar | **Partial.** A caption sits under the title, and sidebar VoiceOver labels include kind and status. There is no visual type grouping. |
| First use: "Start with my current pinned apps" (read-only capture) | **Deferred** (Batch 3). |
| Contextual, dismissible help after setup | **Not done.** |
| Documented click contract (zero, one, minimized or many windows) | **Not done.** |
| Recovery access from replacement mode with the manager closed | **Not done.** Native acceptance is open. |
| Profile switching preserves pending changes at every level | **Done.** Note, snippet and link drafts survive switch, close, Escape and relaunch (MD-A05/A06). |
| Three kinds of editing with predictable Escape behaviour | **Partial.** Instant controls are coalesced, saved-object edits are durable, and new-object drafts are private and recoverable. There is no formal per-surface audit. |
| Failure feedback says what happened, what is safe and what to do next | **Partial.** Note save, snippet/link drafts, File Shelf Locate, the Trash failure, Automation denied, provider provenance and the quit alert now follow it. Not every message was rewritten. |

## 3. Screen by screen

| Screen | Done | Not done |
|---|---|---|
| Workspace and sidebar | Caption and help; labelled Move earlier/later, Duplicate, Remove and Replace…; Undo/Redo in the profile menu; truncation with full-name help; canvas VoiceOver labels. | Compact header redesign; Organize/list view (deferred); sidebar type grouping; "Explore" → "Presets". |
| Add Item and library | "Example" labels in AddLibrary, CommandLibrary and the gallery. | Capability filters (the registry now has the data, but nothing uses it); "Add another" naming; task synonyms in search; list browsing. |
| Widget configuration and popouts | Content first, Appearance collapsed, compact preview on top; validation errors shown for notes and snippets; drafts preserved. | A formal Use-versus-Configure split per family; focus moving to the invalid field. |
| Settings and appearance | Compact narrow header with all 7 categories; one shared spacing/corner/tint range everywhere (MD-U06); clearer inheritance wording and "Reset to Global" in the inspector; privacy and limitations help. | An "Editing: This Dock / App defaults" scope control in Settings; a single standalone Settings window; per-property overrides (deferred). |
| Onboarding | Each setup mode states its consequence for Apple's Dock. | Read-only capture of pinned apps (deferred); a post-setup tutorial. |
| Connections and integrations | "Connected" becomes "Credentials saved". Each row shows the newest reading and its freshness. Shopify same-store replacement and tenant-change clearing work. Paddle `metrics.read` copy is fixed. | Tested/authentication-required/offline states based on a real health check (deliberately not invented); listing the widgets that use each connection. |
| Permissions | Isolated runs never request permissions. Shortcuts, Location, Reminders, Hydration and Trash have accurate denied or timeout messages. | Rewriting the screen per operation; denied, revoked and regranted acceptance (blocked). |
| Backup, history, drafts and recovery | Restore only reports success after a durable save. All retained history and presets are reachable. The privacy label is precise. Backups and history never contain provider readings. Drafts are recoverable. | Persistent privacy preference and persistent undo (deferred); a "Pending drafts" overview and Restore preview. |
| Alerts and feedback | Trash confirmation states its Finder-wide scope; File Shelf says originals are not deleted; specific quit-alert text. | A full copy audit. |
| Menu bar, command palette and keyboard | Menu bar section titles and help. | Every core action as a named palette command; palette search over saved content (OP-03, deferred). |
| The activated Dock | Resize grip of at least 14 pt; AirDrop and Trash faces restored; transition normalization. | Hit-testing, wallpaper and readability acceptance (blocked/open). |

## 4. Native interaction

| Recommendation | Status |
|---|---|
| One identity and outcome contract for launch, activate, window, Close and Quit | **Done in code.** Identity combines installed copy, PID and launch date. Windows resolve by native AX object. Stale or ambiguous targets refuse. Close and Quit are reported as requests, and there is no force-quit. Codex's version had three defects, all fixed. **Native acceptance (H1) is blocked.** |
| Window discovery independent of unrelated preferences | **Done** (MD-D01). |
| Spatial external drop insertion | **Deferred** (MD-D04). |
| Keyboard reorder and named remove with undo | **Partial.** Canvas tiles have Move earlier/later actions and collection removals have undo. A Dock item removal undo exists through the profile Undo. |
| Missing-target Locate for the File Shelf | **Done** (MD-D05). Volume eject and reconnect acceptance is open. |
| Bounded folder popout loading and cancellation | **Done** (MD-S02). |
| Popout focus and dismissal model | **Not done** beyond existing behaviour. |
| Replacement-mode states, conflict policy and display reconnection policy | **Not done.** |
| Resize: a larger invisible hit area | **Done.** |
| Resize: show the current size while dragging | **Not done.** |
| Resize: real measurement | **Not done.** Signposts are ready. |

## 5. Visual and accessibility system

| Recommendation | Status |
|---|---|
| Density: no identical scaffold for every task | **Partial.** The configuration sheet adapts. No broader density pass. |
| Content fit for compact Clock and Checklist (MD-U03) | **Done.** The render confirms "00:12" fits. |
| Units, locale formatting and currency semantics | **Not done** as a sweep. |
| Unit Converter impractical precision (about 11 decimals) | **Not done.** It still shows up to 12 significant digits. |
| Localization groundwork (centralized strings, plurals) | **Not done.** |
| Glass: qualify on real wallpaper, opacity labels, contrast and transparency variants | **Blocked/open** (H3). No code change. |
| Motion: single cancellation contract, Off and Reduce Motion mid-transition | **Done in code** (H4 normalization policy). Desktop acceptance is open. |
| Accessibility: named swatches, selected values, labels, focus contract | **Partial.** Color Picker selected trait; Reminders, App Folder and canvas labels; undo hint; Appearance disclosure label. **No VoiceOver session, focus-contract pass or contrast measurement.** |

## 6. All 35 widget families

Shared changes for every family:
- A typed capability descriptor.
- A registry coverage test.
- A slot in the render matrix (all 35 rendered on 4 October 2026).
- Isolation guards.

| Family | Done | Review recommendation not done |
|---|---|---|
| Stock | Parser bounds; streaming cap; cached readings moved out of the profile | Symbol discovery, trading-interval and last-update clarity |
| Watchlist | Same as Stock | Navigation and per-instrument stale status |
| Calendar | — | Next event and time-until; calendar scope clarity |
| Reminders | Fetch deadline and cancellation; completion button names the reminder | Distinguishing it from Checklist |
| Now Playing | Popout refreshes with the Dock hidden; Automation-denied message | Making the source clearer |
| Weather | Bounded parsing and display; location deadline and fix policy; streaming cap; reading in the cache | Forecast and unit presentation |
| Focus Timer | — | Completion feedback |
| Sticky Note | A rejected or failed save keeps the draft and shows an error | Limit feedback before typing |
| Battery | Popout refresh demand | — |
| Shortcuts | Cancel Run; bounded stderr; cancelled on quit; no arbitrary timeout | — |
| Stripe | Nested item pagination; bounds; tenant binding; provenance footer ("Normalized gross MRR…") | Live-account acceptance |
| Paddle | `metrics.read` copy; bounds; key change clears old figures; provenance | Live/sandbox distinction |
| Shopify | Same-store replacement; page budget and dedup; provenance | Live-account acceptance |
| Clock | Compact width so the time fits | — |
| World Clock | — | Clarifying the primary place and day offset |
| Stopwatch | — | — |
| Countdown | — | Clarifying what Start does to notifications |
| Alarm | — | Editing an existing alarm; next-fire display |
| Time Progress | — | — |
| Hydration | Startup and wake reconciliation (turns reminders off if notifications aren't allowed, like Alarm) | Native acceptance |
| System Activity | Typed refresh demand (popout and editor) | Interpretive units |
| Network Activity | Reset no longer shows a spike; popout demand | — |
| AI Limits | Per-provider bounds; Claude config directory; isolation guards; provenance | — |
| AI Activity | Dedup; distinct sessions; config directory; semantic version; "Local logs, not billing" | — |
| AirDrop | Real Dock face restored (drop, help, AX) | Delivery acceptance (blocked) |
| Trash | Count face restored; honest Finder-wide wording; denied message; isolated in validation runs | Destructive-scope acceptance (blocked) |
| Disk Space | — | Refresh-age display |
| Calculator | — | Keyboard and feedback improvements |
| Quick Checklist | Compact fit; remove and Clear Completed undo | — |
| File Shelf | Locate, Retry, stale bookmark refresh; undo; "original not deleted" | Volume acceptance |
| Text Snippets | Private recoverable drafts with Resume/Discard; undo | Search |
| Quick Links | Drafts; undo | — |
| Unit Converter | — | Practical precision |
| Color Picker | Selected trait on swatches | Apply vs Save Color clarity |
| App Folder | Move and remove buttons named | Selected-copy identity in the UI |

The per-family "acceptance contract" table (every layout in every state, locale, side, light and dark) is **open**. The 4 October render export is a static partial check.

## 7. Data, persistence and local services

| Recommendation | Status |
|---|---|
| Durable success has one meaning | **Done.** Create, duplicate, import, Restore and critical saves are candidate-first. Routine edits are coalesced, and quit waits for disk (MD-A02, MD-E01). |
| Compatibility: unknown future schema refused before decode | **Done** (MD-A01). |
| Numeric domain bounds at trust boundaries | **Done** (MD-A03/A04). |
| Separate user intent, cached readings and interaction state | **Phase 1 done** (PR-13). Readings persist only in `runtime-cache.json`, keyed and identity-tagged, with migration and backup exclusion. Your real state was migrated on 4 October 2026. **Phase 2 not done:** readings are still projected in memory, and edit merging still sees them. |
| Refresh demand follows consumers | **Done** (MD-S05). Dock, popouts, editor and Battery all hold demand. |
| Deadlines and cancellation | **Done** (MD-S01–S04). |
| Provenance in the data contract | **Done for display** (PR-15): source, metric, refresh time, failed/partial/stale. Provider effective time and unit/interval detail per metric are partial. |
| Integration table (Codex, Claude, Grok, Copilot, Stripe, Paddle, Shopify, Alpha Vantage, Open-Meteo) | **Done** for the confirmed findings (dedup, roots, identity, paging, scope, bounds). Copilot and Grok had no confirmed defects, so they are unchanged. Live verification is blocked. |
| Bounded input and work: streaming caps, page budgets, subprocess bounds | **Done** (MD-P04/P08, MD-S01/S02). |

## 8. Architecture

| Investment | Status |
|---|---|
| A fully isolated application environment | **Done in code** (PR-05): `AppRuntimeEnvironment` sets the validation root, memory-only defaults, and guards for native effects, credentials, AI logs, `~/.claude`, the Codex app server, Trash and notifications. **The disposable-user write trace is blocked.** |
| A typed capability registry | **Done** (PR-17): descriptors for all 35 families, proven by a snapshot to leave layouts unchanged. Family-specific payloads that replace the broad configuration are **not done**. Capability flags are not yet consumed. |
| Controller boundaries and narrow invalidation | **Done:** narrow presentation signature (MD-E02); controller split from 1,949 lines into four files. Reveal/auto-hide extraction is **not done**. |
| Engineering governance (decision records, injected clock/transport/storage) | **Partial.** Transport, scheduler, notification-center and writer injection were added where tests needed them. No decision-record practice was introduced. |

## 9. Privacy, lifecycle, release and support

| Recommendation | Status |
|---|---|
| Explain privacy categories in the product | **Done** (PR-20 help section). |
| Diagnostics hold no private content | **Done**: a fixture proves it, plus build/metadata fields. |
| Diagnostics opt-in with a preview before saving | **Not done.** |
| Shared-screen masking | **Deferred.** |
| Threat priorities: streaming caps, bounded work, isolation | **Done.** |
| Login item shows the real SMAppService approval state | **Not done.** |
| Quit keeps failed saves and drafts and cancels work | **Done.** Shortcuts are cancelled and the drafts and cache are flushed. |
| Uninstall/removal guide | **Not done.** |
| Distribution: metadata-bearing artifact, release manifest, CI uploading the right artifact (MD-Q04) | **Not done / blocked.** The Xcode project is now complete. The CI workflow and release script are unchanged, and there is no full Xcode or signing. |
| Focus discovery (MD-Q03) | **Done for guidance:** the app tells CLI builds the truth. **Discovery is blocked.** |
| Truthful documentation (MD-Q05) | **Done.** ARCHITECTURE, PERMISSIONS, ACCEPTANCE_TESTS, PARITY_MATRIX, README, RELEASE_AUDIT, BUILD_BASELINE and IMPLEMENTATION_STATUS were corrected, and history was archived. |
| Help at the point of failure; support triage | **Partial.** In-app failure messages were improved. There is no support reproduction package or triage process. |
| Commercial and licensing decisions | **Not addressed.** These are product decisions. |

## 10. Larger opportunities

OP-01 to OP-07 (workspace start, explainable context switching, working collections, next meeting, audio output, portable exchange, unified system detail) are **all deferred**. Nothing was started; each needs your product decision.

## 11. The 20 packages

| Package | Status |
|---|---|
| PR-01 Compatibility and safe input | **Done** |
| PR-02 Truthful mutations and recoverable edits | **Done.** Persistent undo deferred. |
| PR-03 Native action identity | **Done in code.** H1 blocked. |
| PR-04 Provider correctness | **Done.** Live accounts blocked. |
| PR-05 Safe environments | **Done in code.** Trace blocked. |
| PR-06 Clear modes and first success | **Partial.** Copy done; capture and tutorial deferred. |
| PR-07 Sustained workspace editing | **Partial.** Named actions done; Organize deferred. |
| PR-08 Task-first setup | **Partial.** Sheet and labels done; capability filters, "Add another" and the all-35 check are open. |
| PR-09 One appearance contract | **Partial.** Shared ranges, header and inspector wording done; Settings scope control and per-property overrides not done. |
| PR-10 Targets and spatial interactions | **Partial.** D05, D06 and face routing done; D04 deferred; drag, overflow and popout acceptance open. |
| PR-11 Glanceability and accessibility | **Partial.** Fit and labels done; VoiceOver, locale and precision sweep not done. |
| PR-12 Material and motion | **Partial.** Motion normalization done; material qualification blocked. |
| PR-13 Authored state vs runtime cache | **Phase 1 done.** Phase 2 not done. |
| PR-14 Demand, deadlines, cancellation | **Done** |
| PR-15 Provenance and connection health | **Done** (display). No live health checks, by design. |
| PR-16 Recovery and privacy clarity | **Partial.** Lists, label and undo done; persisted preference and masking deferred. |
| PR-17 Typed capabilities and extraction | **Partial.** Registry and controller split done; family payloads, reveal extraction and capability consumers not done. |
| PR-18 Measured responsiveness | **Partial.** Signposts and synthetic baseline done; real measurements not done. |
| PR-19 Exact-artifact release | **Blocked.** |
| PR-20 Evidence, help and quality loop | **Done** (docs, help, diagnostics review). The task-study baseline and triage process are not done. |

## 12. Validation, gates and decisions

- **Task studies (8 tasks):** not done. They need real users.
- **Measurements (startup, resize, idle, persistence, provider, accessibility, long sessions):**
  - Only the synthetic writer and geometry baseline was recorded, on 4 October 2026. 20 immediate saves of a 2,000-item store took 2,040 ms, against 101 ms when coalesced.
  - Signposts are ready for Instruments. Nothing else was measured.
- **Release gates:**
  - **Trust gate:** code complete with fixtures. Live accounts are blocked.
  - **Native, interaction, usability/accessibility and artifact gates:** **not passed.** Each needs a desktop session, VoiceOver, a spare macOS user or full Xcode with signing.
- **Decisions table** (product identity, default path, Organize, Settings location, inheritance, consolidation, integrations, context rules, sync, updater, OS floor, plug-ins): **none were made.** Each stays at the review's recommended starting position.
- **Missing evidence list:** every item is still missing. The code now supports collecting it: isolation, signposts and accurate guidance.

## 13. Traceability: all 43 audit findings

| Finding | Status | Finding | Status |
|---|---|---|---|
| MD-A01 | Done | MD-P01 | Done |
| MD-A02 | Done | MD-P02 | Done |
| MD-A03 | Done | MD-P03 | Done |
| MD-A04 | Done | MD-P04 | Done |
| MD-A05 | Done | MD-P05 | Done |
| MD-A06 | Done | MD-P06 | Done |
| MD-A07 | Done (session undo) | MD-P07 | Done |
| MD-A08 | Partial (persistence deferred) | MD-P08 | Done |
| MD-A09 | Done | MD-P09 | Done |
| MD-D01 | Done (H1 blocked) | MD-P10 | Done |
| MD-D02 | Done (H1 blocked) | MD-U01 | Done |
| MD-D03 | Done (H1 blocked) | MD-U02 | Done |
| MD-D04 | Deferred | MD-U03 | Done |
| MD-D05 | Done | MD-U04 | Done |
| MD-D06 | Done (wording) | MD-U05 | Done |
| MD-S01 | Done | MD-U06 | Done |
| MD-S02 | Done | MD-E01 | Done |
| MD-S03 | Done | MD-E02 | Done |
| MD-S04 | Done | MD-Q01 | Done in code (trace blocked) |
| MD-S05 | Done | MD-Q02 | Partial (Xcode UI suite blocked) |
| | | MD-Q03 | Done (guidance; discovery blocked) |
| | | MD-Q04 | Blocked |
| | | MD-Q05 | Done |

**Totals:**
- **39 done.** In 7 of these the code is done but native acceptance is blocked (D01–D03, D05, D06, Q01, Q03).
- **2 partial** (A08, Q02).
- **1 deferred** (D04).
- **1 blocked** (Q04).
- **A07** is done for in-session undo; persisted undo is deferred.
- The ledger counts Q01 as partial because its disposable-user trace is blocked, so it shows 38 done.

## What you can do next

1. **Native checks on `build/MyDock.app`:** the 12-item manual list in the coordinator's report, plus the new provenance footers and privacy section in light and dark mode. Use a spare macOS user for permission, preference and Trash tests.
2. **Decide on deferred items:** OP-01–07, onboarding capture and tutorial, Organize view, per-property appearance, persistent privacy preference and undo, shared-screen masking, Finder spatial insertion.
3. **Authorized but unbuilt, if wanted:**
   - PR-13 phase 2.
   - Reveal-monitor extraction.
   - Capability-filter UI in Add Item.
   - "Explore" → "Presets".
   - Unit Converter precision, Alarm editing, Calendar next-event, World Clock day offset.
   - Settings scope control.
   - Login-item state display.
   - Diagnostics preview before save.
   - Uninstall guide.
   - CI artifact selection.
4. **Environment:** install full Xcode and signing identities for PR-19. Set up dedicated test accounts for the provider checks.
