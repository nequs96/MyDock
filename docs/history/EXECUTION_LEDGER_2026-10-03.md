# MyDock execution ledger — 3 October 2026

Phase: required corrective implementation, authorized after the completed planning deliverable by the user’s “i am authorizing”. Coordinator owns this document. Scope is Batch 1 and its necessary dependencies; broader design proposals and optional opportunities remain deferred pending explicit scope/product decisions. Preserve all pre-existing working-tree changes. No commit or publication is authorized. The planning baseline and its results below remain dated evidence; the implementation journal records subsequent changes separately.

This reconciles [AGENTS.md](../../AGENTS.md), the complete [product review](PROFESSIONAL_PRODUCT_REVIEW_2026-10-03.md), [application audit](COMPLETE_APPLICATION_AUDIT_2026-10-03.md), [coverage matrix](COMPLETE_APPLICATION_COVERAGE_2026-10-03.md), [full audit prompt](../FULL_APP_AUDIT_PROMPT.md), [release evidence](../RELEASE_AUDIT.md) and [implementation status](../IMPLEMENTATION_STATUS.md). All five requested documents were read completely. Reports are specifications and evidence leads, not acceptance certificates.

Navigation: [batches](#batches) · [43 findings](#findings) · [20 packages](#packages) · [7 opportunities](#opportunities) · [41 workflows](#workflows) · [35 widgets](#widgets) · [manual acceptance](#manual) · [results/accounting](#results).

## Ownership, scope and evidence rules

| Specialist | Actual spawn configuration | Primary findings | Primary packages | Opportunities / manual |
|---|---|---|---|---|
| Reliability | `gpt-6.1-sol`, `high` | MD-A01–A04, MD-S01–S05, MD-P01–P10, MD-E01, MD-Q01 | PR-01,02,04,05,13,14,15,16 | OP-06; H8 |
| Native platform | `gpt-6.1-sol`, `high` | MD-D01–D06, MD-U05, MD-E02, MD-Q02–Q04 | PR-03,10,12,18,19 | OP-01,02,05; H1–H4,H7,H9 |
| Product experience | `gpt-6.1-sol`, `medium` | MD-A05–A09, MD-U01–U04, MD-U06, MD-Q05 | PR-06,07,08,09,11,17,20 | OP-03,04,07; all 35 widget workflow records; H5,H6 |

Primary package ownership is accountability; related specialists provide dependencies. Only the coordinator reconciles source integration, builds and this ledger. No investigation here required escalation to xhigh; difficult future investigations should request it explicitly. Routine inventory stays medium.

Implementation and verification are independent fields. **Unstarted** means no proposed corrective/product code was written. **Existing code present / partial** describes the current source only. **Source corroborated** means inspected current paths; it is not native acceptance. **Open** means not exercised. **Blocked** names a missing environment or safety prerequisite. **Deferred** means a deliberate optional/product gate. No product acceptance is marked passed in this phase. No Critical/P0 finding is established; original finding severity/priority remains in the source audit.

Same-day earlier test/fixture/render/UI outcomes below are **historical evidence for this planning phase**, even though current file hashes match. They were not rerun here. The audit records 253 individual default passes, five skips (258 reported), two later safe opt-ins and 175 PNG exports. None proves desktop behavior, VoiceOver, current live accounts, supported OS/Intel or distribution. No new test/build/render/UI/account/native scenario was run. Read-only inspection and inventory/hash checks are the actual results of this phase.

## Current baseline and inventory

HEAD is `24f9c76133d5fc3a27b2b7ace7dadf0e240217c0`, with the existing staged/unstaged/untracked working tree preserved. The 124 source/build/resource inputs and 19 test inputs in BUILD_BASELINE match their recorded hashes. Canonical executable SHA-256 is `fb106c4cecc65c07bd1283e15abc9ed72f75e2a91e96c008a80d8e49ef9d58d1` and matches the recorded baseline. Native specialist also rechecked strict ad-hoc signature (exit 0), x86_64+arm64 architecture, v0.1.0/build 1/macOS 13 target and absence of Metadata.appintents. These are packaging facts, not distribution acceptance. No app was launched, quit, overwritten or moved. No new development baseline was built, so RELEASE_AUDIT/BUILD_BASELINE were not rewritten.

Current [WidgetRegistry](../../Sources/MyDock/Models/DockModels.swift:1229) contains **35** names; the [provider registry](../../Sources/MyDock/CustomDock/WidgetViews.swift:12) contains the same 35, with no missing or extra provider name. Difference from the reports: **zero**. Memory/swap/core/thermal are System Activity details, not a 36th family. Existing semantic layout export at [PremiumVisualQA.swift:352](../../Sources/MyDock/UI/PremiumVisualQA.swift:352) still loops three pages of ten: Text Snippets, Quick Links, Unit Converter, Color Picker and App Folder are omitted there. Four have separate tools renders; that does not satisfy all layouts/states, and App Folder lacks that adaptive matrix.

State flow remains UI/edit session → ProfileStore revisions → serialized writer/state and sanitized library; provider/native service → coordinator/monitor → stored snapshot or face; Dock controller → render model → native panel/shared faces. Preserve atomic ordering, three-way merges, private modes, device-local Keychain, sanitized portable data, coalescing/backoff, notification generation guards, independent layout/icon treatment and native preference recovery journals. Avoid a rewrite.

## Coordinator reconciliation decisions

1. Earlier RELEASE_AUDIT/BUILD_BASELINE CUA startup failure and later same-day successful isolated audit UI refer to different attempts. The earlier failure is historical, not a current blanket tooling blocker. No new CUA check was attempted here; desktop acceptance remains open for its own safety/environment reasons.
2. A build or source-presence label cannot close MD-Q02/Q04 or any widget/native scenario. The documentation's 258 reported tests include five default skips; individual default passes are 253.
3. Shortcuts already has Running/Completed/error status. MD-S01 is cancellation/deadline/lifecycle ownership, with a deliberate interactive-workflow policy rather than an arbitrary short kill timeout.
4. Folder loading already guards changed currentURL; System Activity already has visible-popout demand. Remaining cancellation/generation/scheduler boundaries still need work. Do not remove those protections while adding the missing ones.
5. Calendar already derives Join from event data. Alarm has create/repeat/enable/remove but no existing-alarm edit control was found. App Folder has Add Apps using NSOpenPanel, Reorder/Replace/Remove, rather than a confirmed embedded installed-app search. Widget records use those narrower source facts.
6. Countdown Start/Set directly schedules notifications (WidgetViews:817–838); no separate notification enable toggle found. Inspect and accept that actual action contract. AI cached percentages need provider-specific domains; valid Copilot overage can exceed 100. Sticky Note flushNotes also clears pending drafts before rejected update.
7. Untitled DockWindowDescriptor is transient, not Codable; raw/display identity separation needs cache-key review, not an assumed disk-schema migration. AX Press or terminate request success cannot be reported as observed document closure/process exit or known cancellation.
8. MD-D04 is an intentional append-only product difference. Spatial external insertion stays a decision-gated PR-10 extension. MD-A07/U01/U04/U05 contain confirmed facts plus recovery/usability judgments; their proposed experience is not a measured usability result. MD-D06/S04/P09 remain strong inferences requiring the specified native/account procedures.
9. Supplemental routing leads: live WidgetCompactView routes AirDrop/Trash through LocalWidgetDockFace ([WidgetViews.swift:87](../../Sources/MyDock/CustomDock/WidgetViews.swift:87), [WidgetPrimitives.swift:342](../../Sources/MyDock/CustomDock/WidgetPrimitives.swift:342)); the live controller uses that route at 1330. AirDrop's provider compact onDrop is bypassed and the pinned wrapper accepts internal DockDragPayload only; native file/url intake remains in its popout. Trash's observed count/error/empty provider is bypassed for a generic face; popout behavior remains. Independently corroborated by Product and Native. Track under W25/W26, PR-10/17 and MD-Q02; do not invent a new original MD finding or claim runtime acceptance.
10. Changing Off/style during an in-flight transition may bypass normalization through presentDock's unchanged-visible-state early return. This is a supplemental source inference for H4, not an observed animation defect. Required empirical interruption acceptance decides whether a correction is needed.

<a id="batches"></a>

## Proposed implementation batches

These are authorization proposals, not work orders already executed. Relative scope is Small/Medium/Large; no hour estimates. A narrowly authorized subset does not authorize the rest of a PR package.

| Batch | Coherent package sequence | Intended result / dependencies | Gate |
|---|---|---|---|
| 1A Required corrective: safe validation | PR-05 mutation-capable environment boundary; registry-derived coverage/failure cases from PR-17/20 | Isolated store/defaults/cache/credentials/native backends/notifications and matching quit path enable trustworthy failure validation. Test unsafe harness paths before enabling native/runtime opt-ins. | MD-Q01; H8 isolation trace first; no personal state reads/writes to manufacture evidence. |
| 1B Required corrective: state integrity | PR-01, then PR-02 durable mutation/acknowledgement core | Future envelope guard, cached/provider number bounds, candidate-first import/create and honest Restore/note results. Preserve same-version recovery, old migrations, revision ordering and private drafts. | MD-A01–A05; isolated failure/retry/relaunch criteria, then relevant TestMyDock.sh filters. |
| 1C Required corrective: data/authority | PR-04 identity repairs first, then AI dedup/root/session metric, paging/transport/count/reset/scope fixes; bounded provenance essentials from PR-15 | Same-store replacement works; deliberate tenant changes clear persisted old readings; totals, scopes and rates are defensible. Cache semantic invalidation follows metric changes. | MD-P01–P10; PR-01/02/05 foundations; fixtures before separately authorized account acceptance. |
| 1D Required corrective: native actions | PR-03 default menu discovery/raw identity/path+PID consistency; PR-10 required Shelf repair/Trash scope and routing investigation | Act on intended app/window; retain missing references; accurately describe destructive scope. Keep normal unsaved/cancel semantics. | MD-D01–D03/D05; D06 remains inference until disposable acceptance. H1/H6/H7, no force-quit workaround. |
| 1E Required corrective: lifecycle and consistency | Narrow PR-14 deadline/cancel/generation/Hydration fixes; PR-02 unfinished utility draft protection; PR-16 accurate scope/full retained navigation; PR-08 honest Example labels; PR-09 range reconciliation; PR-11 clipping/minimum target fixes | Pending edits remain safe; no indefinite/stale native work; represented values fit and valid overrides remain round-trippable. | MD-A06/A08/A09/S01–S05/U02/U03/U05/U06; PR-02/05 and isolated lifecycle fixtures. Local undo MD-A07 is a quality scope choice listed below. |
| 1F Required qualification and evidence | PR-18 baseline instrumentation/narrow root key and bounded routine-edit coalescing after PR-02; PR-17 missing matrix/failure coverage; PR-20 claims; PR-19 exact-artifact gates before release | Record real cost and correct current evidence; ship only the accepted metadata-bearing artifact. | MD-E01/E02/Q02–Q05. Routine-control paths may use the existing coalesced writer after truthful outcomes; full async repository/cache restructuring is Batch 2. Critical Save/Restore/quit durability stays explicit. Full Xcode/signing/native gates remain blocked/open. |
| 2A Design / usability | PR-06 mode/status/first-success clarity; PR-07 compact workspace/core named actions; PR-08 task-first setup/examples; PR-09 compact Settings/scope; PR-11 formatting/focus/VoiceOver; PR-02/16 bounded collection undo | Complete discover→configure→use→change→recover→relaunch workflows. Keep existing quiet native language and identity/persistence contracts. | PR-02/03 core first. Baseline task study and all 35 family layouts/states; large Organize/capture/tutorial require explicit selected scope. |
| 2B Architecture / responsiveness | PR-15 stable identity/provenance contract → phased PR-13 runtime cache separation → PR-14 demand tokens → PR-17 typed registry/payload extraction; PR-18 measurements guide controller extraction | Authored data and runtime cache have clear owners, visible consumers stay fresh, absent consumers avoid work, qualification cannot omit families. | PR-01/02/05. PR-15 metadata precedes PR-13 cache keys, breaking apparent sequencing cycle. Deadlines need not wait for cache extraction. Preserve scheduled alarms. |
| 2C Materials and sustained quality | PR-12 wallpaper/motion qualification; PR-19 supported-host/artifact qualification; PR-20 help/privacy/evidence loop | Readable real Dock, coherent interrupted motion, usable native recovery and artifact-specific claims. | PR-09/11/18 plus H1–H9. Qualification may expose targeted fixes; controls present is not acceptance. |
| 3 Optional product decisions | OP-01–OP-07; MD-D04 spatial insertion; PR-06 current-Dock capture/tutorial; PR-07 Organize; PR-09 per-property overrides; PR-16 shared-screen masking; wider calendar/timer workflows | Pilot only a chosen user task after corrective gates, with opt-in defaults and explicit stop criteria. | No automatic implementation. Cloud sync, passive clipboard, executable plug-ins, auto-cleaning, force quit, pricing, support-floor changes and automatic updater are separate decisions, not implied scope. |

Future exclusive file ownership: coordinator owns shared Models/, MyDockApp.swift/environment assembly and cross-component integration APIs; Reliability owns persistence/services/provider internals; Native owns DockManagement/native app-window/display/motion/cache services and release tooling; Product owns workspace/onboarding/library/Settings/configuration and widget presentation views. Split shared UI files into sequential packages if draft/privacy/provider copy changes overlap. PR-17 controller extraction stays Native; registry/model integration stays coordinator. Shared code has one writer at a time. Specialists review dependent APIs before parallel peripheral changes. Only coordinator reviews integrated changes, cleanly quits before ./BuildMyDock.sh, launches canonical build/MyDock.app after authorized changes, runs relevant ./TestMyDock.sh checks with explicit opt-ins, and updates ledger after each package.

<a id="findings"></a>

## Finding ledger — all 43 MD entries

For every finding, the current source condition was rechecked by its primary specialist. The cited runtime/test/render evidence remains the earlier same-day audit result; no new execution is implied. Implementation below refers to the proposed correction, not the presence of the affected feature.

### MD-A01 — Unknown future models bypass downgrade protection

- **Primary owner / related IDs:** Reliability; PR-01.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [ProfileStore.swift:40](../../Sources/MyDock/Persistence/ProfileStore.swift:40), version guard 41, catch 51, move 55. T existing compatible future-version protection does not cover unknown future enum decoding. No real user file was corrupted or downgraded.
- **Intended outcome and current trigger:** An older app opens a future-version state containing an enum case it cannot decode. Expected: leave the future file untouched and disable saves. Actual: full model decoding happens before the schema guard; decode failure moves the original to a recovery file, initializes empty state and leaves saves enabled. The original is preserved, so this is not a claim of irretrievable deletion.
- **Proposed change / components / dependencies:** Read a small schema envelope first; refuse future versions before decoding models. Keep ordinary corruption recovery separate. shared archive schema handling; preserve recovery migration; Small/Medium.
- **Migration / regression risks:** Envelope-first dispatch must retain known old-schema migration and same-version corruption recovery; future file byte identity is mandatory.
- **Acceptance criteria:** isolated future JSON with unknown item/widget/settings cases remains byte-identical, saves disabled, existing same-version corruption recovery still works.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-A02 — Restore reports success after failed persistence

- **Primary owner / related IDs:** Reliability; PR-02.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [ProfileStore.swift:471](../../Sources/MyDock/Persistence/ProfileStore.swift:471); [RevisionedStateWriter.swift:33](../../Sources/MyDock/Persistence/RevisionedStateWriter.swift:33); [SettingsView.swift:924](../../Sources/MyDock/UI/SettingsView.swift:924). `createProfile(kind:)` at 79 also publishes before its nonthrowing commit; the resolved-profile creation path already demonstrates candidate-first persistence. No production restore/write failure was exercised.
- **Intended outcome and current trigger:** Restore an individually valid archive into a store whose combined count exceeds 500 profiles/20,000 items, or make the target unwritable. Expected: reject the combined candidate or report the write failure without a successful restore. Actual: import appends to memory, calls nonthrowing commit, then Settings reports “Restored” and records success regardless of the disk result. Oversized combined state can make subsequent saves fail; relaunch returns to the older disk state.
- **Proposed change / components / dependencies:** Validate and persist the merged candidate before publication; return an explicit result to all success UI. import/create call sites and revision ordering; preserve user drafts; Medium.
- **Migration / regression risks:** No format change required for result contracts; validate combined candidate before publishing and preserve revision ordering/drafts.
- **Acceptance criteria:** combined limits, unwritable fixture, injected atomic-write failure, retry, relaunch and correct diagnostics.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-A03 — Cached AI percentage can trap after a valid JSON import

- **Primary owner / related IDs:** Reliability; PR-01.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [AIUsageService.swift:75](../../Sources/MyDock/SystemServices/AIUsageService.swift:75), [ProfileSemanticValidator.swift:33](../../Sources/MyDock/Models/ProfileSemanticValidator.swift:33). R isolated unchanged-source fixture exited -5; [results](../../.build/visual-qa/full-audit-2026-10-03/source-slice-results.json). This was not a whole-app/live-account crash.
- **Intended outcome and current trigger:** An imported/cached available AI window contains `usedPercent = Int.min`. Expected: reject invalid percentages or display unavailable. Actual: `100 - usedPercent` overflows before clamping. The semantic validator does not validate this cached snapshot. Preconditions are malformed local/imported data; this does not establish credential exposure or remote code execution.
- **Proposed change / components / dependencies:** Validate all cached snapshot collections, bounds, dates and identities at decoding/import and guard arithmetic at presentation. model compatibility and honest unavailable states; Medium.
- **Migration / regression risks:** Validate/recompute malformed runtime caches without discarding authored configuration; old valid snapshots must decode. Copilot permits above-100 usage (GitHubCopilotService:138), so define per-source domains, not a blanket 0…100 cap.
- **Acceptance criteria:** extreme signed integers, missing values, out-of-range values, old valid caches, reimport/relaunch.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-A04 — External numeric parsers are not consistently bounded

- **Primary owner / related IDs:** Reliability; PR-01, PR-04.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [MarketDataService.swift:138](../../Sources/MyDock/SystemServices/MarketDataService.swift:138), StripeDataService 326/362, PaddleDataService 276, WeatherService 83, WidgetPrimitives 242/248/254. R market source slice exited -5 with “Double value cannot be converted to Int64 … greater than Int64.max.” See source-slice manifest/results. No claim that the current providers normally emit such values.
- **Intended outcome and current trigger:** A valid JSON market volume string is `1e30`. Expected: reject the response safely. Actual: direct Double-to-Int64 conversion traps. Other unchecked paths include business interval counts and finite-but-enormous weather temperatures converted to Int in faces.
- **Proposed change / components / dependencies:** Use domain bounds and overflow-safe arithmetic, rejecting malformed snapshots without replacing the last good data. common parsing conventions across providers; preserve partial-data messages; Medium.
- **Migration / regression risks:** Domain-specific parser guards need no authored migration; reject malformed external readings and retain last good snapshots.
- **Acceptance criteria:** huge finite values, negative counts, NaN/infinity where decoding permits, interval multiplication, normal currency/weather fixtures.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-A05 — Sticky Note draft is cleared even when validation rejects it

- **Primary owner / related IDs:** Product experience; PR-02, PR-08.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [WidgetViews.swift:1400](../../Sources/MyDock/CustomDock/WidgetViews.swift:1400), save 1441–1443; [ProfileStore.swift:448](../../Sources/MyDock/Persistence/ProfileStore.swift:448); validator 58. Large paste was not attempted against user content.
- **Intended outcome and current trigger:** Paste more than 1 MiB of text into the unbounded note editor. Expected: retain the draft and explain the limit. Actual: updateWidgetConfiguration rejects it, but saveNote unconditionally calls noteWasSaved; closing invokes the same path. The rejected text can lose its recovery draft.
- **Proposed change / components / dependencies:** Return acceptance/persistence outcome, retain failed draft, show a limit before destructive dismissal. draft acknowledgement semantics; avoid converting debounced editing into per-keystroke synchronous writes; Small/Medium.
- **Migration / regression risks:** Private note draft acknowledgement must follow accepted/durable result; retain rejected Unicode input. WidgetSetupDraftStore:95–101 also clears pending notes before rejected update on flush; cover quit flush as well as saveNote.
- **Acceptance criteria:** boundary-size Unicode text, validation/write failure, close/reopen and retry.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H5/H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-A06 — Closing Snippets configuration silently drops unfinished input

- **Primary owner / related IDs:** Product experience; PR-02, PR-08.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: R current CUA scenario; S [DockUtilityWidgetViews.swift:160](../../Sources/MyDock/CustomDock/DockUtilityWidgetViews.swift:160), explicit save 205; Quick Links 222. Saved snippet persistence has T store-recreation coverage; pending input does not.
- **Intended outcome and current trigger:** Type a new snippet title/body, then press Escape before Save. Expected: retain recoverable input or make discard explicit. Actual: in the isolated native preview, the form closes without warning; reopen shows blank new-entry fields while the previously saved snippet remains. Quick Links uses the same transient @State pattern.
- **Proposed change / components / dependencies:** Keep item-scoped drafts or confirm discard on dismissal, without saving incomplete entries into collections. sheet/popout dismissal and draft cleanup; Medium.
- **Migration / regression risks:** An item/profile-scoped private draft store needs an explicit lifetime and cleanup policy on deletion/explicit discard; no incomplete collection insertion.
- **Acceptance criteria:** new/edit forms, Escape, click outside, profile switch, item deletion and clean relaunch in temporary state.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H5/H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-A07 — Utility removal has no local undo

- **Primary owner / related IDs:** Product experience; PR-02, PR-16.
- **Current source / status:** Confirmed absence of local collection undo; requiring undo is a recovery design judgment, not proof that Remove deletes original files. Source/evidence lead: S DockUtilityWidgetViews remove at 192/264, Shelf clear 98; UtilityWidgetViews checklist mutation around 187; [ProfileSanitizer.swift:8](../../Sources/MyDock/Models/ProfileSanitizer.swift:8). Destructive controls were inspected, not exercised against user state.
- **Intended outcome and current trigger:** Remove a snippet/link or clear File Shelf/checklist content. Expected: a readily available recovery route for accidental removal. Actual: collection mutations persist directly without collection undo; ordinary sanitized history excludes much of this content. File Shelf removal does not delete original files, but its organization/reference can be lost.
- **Proposed change / components / dependencies:** Add small bounded in-memory undo at the collection operation, keeping private-history defaults intact. distinguish reference removal from file deletion; privacy retention; Medium.
- **Migration / regression risks:** Prefer bounded session undo; persisted private undo is a separate retention decision. Avoid identity resurrection or overwriting intervening edits.
- **Acceptance criteria:** remove/clear/undo with intervening edits and duplicate identities.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H5/H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-A08 — History privacy control understates its scope and resets

- **Primary owner / related IDs:** Product experience; PR-16.
- **Current source / status:** Confirmed label and transient preference mismatch. Decision remains whether to persist the opt-in or clearly state session lifetime; do not automatically widen retained content. Source/evidence lead: S [RecoveryCenterView.swift:15](../../Sources/MyDock/UI/RecoveryCenterView.swift:15), [ProfileLibrary.swift:15](../../Sources/MyDock/Persistence/ProfileLibrary.swift:15), ProfileSanitizer 8–10.
- **Intended outcome and current trigger:** Enable “Include Sticky Note text in future history.” Expected: an accurate scope description and intentional retention of the preference. Actual: the same flag also preserves checklist and snippet content; it is a transient published property defaulting false, so relaunch resets it. Links/file references remain excluded independently. Default sanitization is a strength.
- **Proposed change / components / dependencies:** Describe the precise private-content classes and make lifetime explicit; if persisted, require an explicit choice with no retroactive content restoration. privacy migration and history sanitization; Small/Medium.
- **Migration / regression risks:** If lifetime changes, explicit default-false preference migration and precise content scope; no retroactive restoration or opt-in expansion.
- **Acceptance criteria:** default, enable/relaunch, disable, exports and retained snapshots.
- **Implementation / work performed:** Targeted required correction implemented, integrated verification pending; broader package/design scope remains partial. Work: precise session privacy label, all retained list entries, accessible Example labels, compact Clock/Checklist geometry, safe weather display and shared appearance bounds as applicable. See implementation journal for exact scope.
- **Verification / actual results:** Specialist source/diff review completed; three formatter fixtures added but not yet executed. Integrated build/tests and all relevant native acceptance remain open.
- **Remaining gaps / blockers / manual:** H5/H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-A09 — Retained history and presets beyond ten entries are unreachable

- **Primary owner / related IDs:** Product experience; PR-16.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [RecoveryCenterView.swift:18](../../Sources/MyDock/UI/RecoveryCenterView.swift:18); [PersonalPresetPicker.swift:21](../../Sources/MyDock/UI/PersonalPresetPicker.swift:21). R safe preview showed an empty initial history, not this populated scenario.
- **Intended outcome and current trigger:** More than ten retained entries exist; default history keeps up to 25. Expected: all retained entries can be browsed/restored. Actual: Recovery Center and Personal Preset picker use prefix(10) without pagination or Show More.
- **Proposed change / components / dependencies:** A compact list with pagination/search or Show More; preserve existing retention policy. identity-safe selection; Small.
- **Migration / regression risks:** No retention/schema change expected; keep identity-safe selection, existing 25-entry limit and exact restore-as-new.
- **Acceptance criteria:** 0/1/10/25 entries, long names, keyboard selection and exact restore target.
- **Implementation / work performed:** Targeted required correction implemented, integrated verification pending; broader package/design scope remains partial. Work: precise session privacy label, all retained list entries, accessible Example labels, compact Clock/Checklist geometry, safe weather display and shared appearance bounds as applicable. See implementation journal for exact scope.
- **Verification / actual results:** Specialist source/diff review completed; three formatter fixtures added but not yet executed. Integrated build/tests and all relevant native acceptance remain open.
- **Remaining gaps / blockers / manual:** H5/H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-D01 — Windows and Close Window disappear under default behavior settings

- **Primary owner / related IDs:** Native platform; PR-03.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [CustomDockWindowController.swift:579](../../Sources/MyDock/DockManagement/CustomDockWindowController.swift:579) and window-dependent menu at 1491. No permission was granted and no real document/window was closed.
- **Intended outcome and current trigger:** Keep both Show Minimized Windows and Click Focused App to Minimize off, their defaults, even with AX access. Expected: application context menus can discover current windows and offer Close Window independently. Actual: the window monitor is disabled and the menu is omitted when its window array is empty. Quit remains a separate normal terminate operation.
- **Proposed change / components / dependencies:** Fetch current windows on demand for the menu, or give menu discovery independent ownership, with clear denied-permission recovery. async menu freshness, process identity and permissions; Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** default/off combinations, two unsaved TextEdit documents, Close cancel/save, Quit cancel/save, Finder, no AX and revoked AX.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H1/H6/H7 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-D02 — Untitled AX windows cannot resolve using their display fallback

- **Primary owner / related IDs:** Native platform; PR-03.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [WindowAccessibilityService.swift:64](../../Sources/MyDock/SystemServices/WindowAccessibilityService.swift:64), raw candidate title 149 and match 151. T duplicate-title identity tests exist, but this display-fallback mismatch is not covered. No live untitled AX application was used.
- **Intended outcome and current trigger:** An AX window has an empty title and no stable AX identifier. Expected: its descriptor can either resolve safely or explicitly report unsupported identity. Actual: enumeration replaces the empty title with the app name, while resolution compares against the raw empty title; fallback title matching cannot find it.
- **Proposed change / components / dependencies:** Keep raw title/identifier separate from a localized display fallback; never fall back to stale array position alone. Codable descriptor/cache identity; Small/Medium.
- **Migration / regression risks:** Descriptor is transient Hashable/Sendable, not Codable. Separate raw/display title and invalidate affected preview keys; no automatic persisted schema migration.
- **Acceptance criteria:** empty titles, duplicates, renamed/closed windows, reordered AX arrays and reused processes.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H1/H6/H7 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-D03 — Multiple installed app copies use inconsistent identity

- **Primary owner / related IDs:** Native platform; PR-03.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [AppLauncher.swift:38](../../Sources/MyDock/SystemServices/AppLauncher.swift:38), RunningApplications 15–17; Dock controller 1492, minimize 1305, pinned filtering 1735. The installed-app inventory validated bundles, not simultaneous launching of two copies.
- **Intended outcome and current trigger:** Two installed/running copies share a bundle identifier. Expected: the selected path/PID remains authoritative. Actual: AppLauncher resolves the selected bundle URL and Quit uses PID, while runtime deduplication, window menus and some minimize/pinned filtering group by bundle identifier. Another copy's windows can therefore enter the selected item's menu.
- **Proposed change / components / dependencies:** Retain a runtime identity including executable/bundle URL and PID; use bundle ID only for intentional grouping with explicit UI. running-entry IDs, preview cache and migration of stored targets; Medium.
- **Migration / regression risks:** Preserve stored selected URLs and local identities; any runtime/cache identity change must reject stale PID/path associations.
- **Acceptance criteria:** two disposable app copies, each with named windows, restart/PID reuse, pin/quit/activate selection.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H1/H6/H7 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-D04 — Finder insertion is confined to an append target

- **Primary owner / related IDs:** Native platform; PR-10.
- **Current source / status:** Confirmed intentional append-only limitation; spatial insertion is optional and deferred for a product decision. Source/evidence lead: S Dock controller internal drop 1261/1551, external target 1279, append handler 1652. T pasteboard/order tests do not qualify a Finder pointer drop. No external desktop drop was performed.
- **Intended outcome and current trigger:** Drag an external file/app between existing Dock items. Expected: an optional parity enhancement would offer spatial insertion, as the normal macOS Dock does. Actual: MyDock's explicit external target accepts URLs and appends; per-item destinations handle internal payloads. This is a product difference, not an observed wrong insertion bug.
- **Proposed change / components / dependencies:** Reuse validated URL intake with spatial insertion feedback when that improves Dock organization; keep an accessible Add path. drag session identity and exact insertion index; Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** apps/files/folders/links, multi-URL order, separators/groups, empty/end areas and invalid payloads.
- **Implementation / work performed:** Deferred optional proposal; no implementation authorized. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H1/H6/H7 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-D05 — File Shelf cannot repair missing references

- **Primary owner / related IDs:** Native platform; PR-10, PR-16.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [DockUtilityWidgetViews.swift:113](../../Sources/MyDock/CustomDock/DockUtilityWidgetViews.swift:113), menu 120; [DockUtilityModels.swift:10](../../Sources/MyDock/Widgets/DockUtilityModels.swift:10). V tools fixtures include missing-file states. No user file was moved. The app is unsandboxed; this is not a claim that all references require security-scoped access today.
- **Intended outcome and current trigger:** A shelved file moves, its bookmark stops resolving, or a volume is disconnected. Expected: explain unavailability and offer Locate/retry while retaining the shelf entry. Actual: warning text and disabled Open/Copy are present, but its row/menu has no repair action. Minimal bookmarks are resolved without refreshing a stale bookmark.
- **Proposed change / components / dependencies:** Add Locate/retry and bookmark refresh; expose permission recovery only when relevant. reference identity and future sandbox policy; Medium.
- **Migration / regression risks:** Refresh bookmarks atomically on explicit Locate; preserve original entry/URL on failed or duplicate repair; current app is unsandboxed.
- **Acceptance criteria:** fixture rename/move, stale bookmark, eject/reconnect, duplicate repair, share/drag without deleting originals.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H1/H6/H7 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-D06 — Trash summary and Empty Trash have different scope

- **Primary owner / related IDs:** Native platform; PR-10.
- **Current source / status:** Strong inference about home summary versus Finder-wide operation; actual destructive scope remains unverified. Source/evidence lead: S [TrashService.swift:9](../../Sources/MyDock/SystemServices/TrashService.swift:9), open 94/empty 99; TrashWidgetViews confirmation 66. Local Finder.sdef `empty trash` contract inspected read-only. No Trash operation executed.
- **Intended outcome and current trigger:** External-volume Trash contains items while the home Trash widget is used. Expected: the count and confirmation describe the scope actually emptied. Actual: TrashService lists/opens `~/.Trash`, but Empty runs Finder's `empty trash` command, whose Trash is broader than that directory. The confirmation is generic.
- **Proposed change / components / dependencies:** Explain Finder-wide scope, or consistently use a safely supported scoped operation; do not invent a global count. destructive operation must remain opt-in; Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** disposable account/volume with sacrificial fixtures, confirmation/cancel, Automation denial and partial failure.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H1/H6/H7 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-S01 — Running Shortcuts has no cancellation or execution deadline

- **Primary owner / related IDs:** Reliability; PR-14.
- **Current source / status:** Confirmed no cancellation/deadline/lifecycle ownership. Running/Completed status already exists ([ShortcutsService:71](../../Sources/MyDock/SystemServices/ShortcutsService.swift:71)/99; [WidgetViews:321](../../Sources/MyDock/CustomDock/WidgetViews.swift:321)); a claim that run status is missing is corrected. Source/evidence lead: S [ShortcutsService.swift:74](../../Sources/MyDock/SystemServices/ShortcutsService.swift:74), process setup through 99; bounded catalog path is not proof of bounded execution. No shortcut was executed.
- **Intended outcome and current trigger:** A selected shortcut stalls, waits for input indefinitely, or never terminates. Expected: visible running state with a supported cancellation/lifecycle policy. Actual: the run path retains a Process until termination, discards stderr, and has no execution timeout/cancel path. Catalog enumeration is separately bounded.
- **Proposed change / components / dependencies:** Expose running/cancel state and safe app-quit cleanup, with useful bounded diagnostics. User-interactive shortcuts may legitimately run longer than catalog lookup; do not apply an arbitrary short forced timeout. child-process ownership and side effects; Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** successful, failing, interactive, hung and cancelled safe fixture shortcuts.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-S02 — Folder popout enumeration has no useful loading/cancellation boundary

- **Primary owner / related IDs:** Reliability; PR-14.
- **Current source / status:** Confirmed loading/cancellation/budget gap. [FolderContentsPopout:102](../../Sources/MyDock/CustomDock/FolderContentsPopout.swift:102)/106 already rejects a result if currentURL changed; cancellation and A→B→A/dismissal identity still need acceptance. Source/evidence lead: S [FolderContentsReader.swift:11](../../Sources/MyDock/SystemServices/FolderContentsReader.swift:11); [FolderContentsPopout.swift:99](../../Sources/MyDock/CustomDock/FolderContentsPopout.swift:99). No mounted slow-volume performance test was run.
- **Intended outcome and current trigger:** Open a large or slow/network folder, then change target or close the popout. Expected: a distinct loading state and obsolete work cancellation. Actual: the reader enumerates/sorts the full contents without a cancellation/deadline contract; the initial empty state can precede results, and previous rows can remain while a new target loads.
- **Proposed change / components / dependencies:** Show loading/error explicitly, publish only the current request, bound displayed work and cancel where the API permits. filesystem cancellation cannot guarantee an OS call returns instantly; Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** empty/large/error folders, target changes, dismissal and reconnect.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-S03 — Some permission-dependent native waits remain unbounded

- **Primary owner / related IDs:** Reliability; PR-14.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [CurrentLocationService.swift:20](../../Sources/MyDock/SystemServices/CurrentLocationService.swift:20), fix 67–79; [CalendarRemindersService.swift:163](../../Sources/MyDock/SystemServices/CalendarRemindersService.swift:163). Permissions were not requested.
- **Intended outcome and current trigger:** Location never supplies a suitable result, or EventKit Reminders completion does not arrive promptly. Expected: a bounded waiting/error state and cancellation without stale publication. Actual: Location has task cancellation but no overall deadline and accepts fixes without age/accuracy validation; Reminders waits on a continuation without cancelling its fetch token. The later cancellation check cannot end the preceding wait.
- **Proposed change / components / dependencies:** Race against a sensible deadline, cancel the native request/token, validate location age/accuracy, and distinguish denied/unavailable/time-out. continuation single-resume and actor isolation; Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** denied/revoked, no fix, stale fix, cancelled reminder fetch, sleep/wake and repeated requests.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-S04 — Hydration enabled state is not reconciled at app startup

- **Primary owner / related IDs:** Reliability; PR-14.
- **Current source / status:** Strong inference: no equivalent startup Hydration OS reconciliation found. Scheduling/generation guards already exist; notification failure has not been observed. Source/evidence lead: S [HydrationReminderService.swift:26](../../Sources/MyDock/SystemServices/HydrationReminderService.swift:26), cancel 59; [MyDockApp.swift:180](../../Sources/MyDock/MyDockApp.swift:180). T generation tests do not verify OS pending requests across relaunch. No real notifications scheduled.
- **Intended outcome and current trigger:** Saved Hydration reminders say enabled but OS pending requests/permission changed while MyDock was closed. Expected: reconcile configuration with authorization and pending requests or show an actionable mismatch. Actual: scheduling/cancellation generation guards exist, but startup explicitly reconciles Alarm; an equivalent Hydration revalidation path was not found. Stored enabled state alone cannot establish delivery.
- **Proposed change / components / dependencies:** Reconcile enabled configurations on relaunch/wake/permission change, avoiding repeated permission prompts and duplicate requests. notification limits and operation identity; Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** revoke/regrant, deleted pending request, relaunch, item deletion and interval change.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-S05 — A global Dock-visible gate also pauses non-Dock consumers

- **Primary owner / related IDs:** Reliability; PR-14, PR-13.
- **Current source / status:** Confirmed global scheduler gate. System Activity already has a visiblePopouts override ([SystemActivityWidgetViews:71](../../Sources/MyDock/CustomDock/SystemActivityWidgetViews.swift:71)/98), but periodic stream still goes through [RefreshScheduler:49](../../Sources/MyDock/SystemServices/RefreshScheduler.swift:49)/60. Source/evidence lead: S [RefreshScheduler.swift:49](../../Sources/MyDock/SystemServices/RefreshScheduler.swift:49); NowPlayingService 149; SystemActivity/NetworkActivity monitor visibility gates; WidgetDataCoordinator active-profile selection 122.
- **Intended outcome and current trigger:** A configuration/editor or popout needs current CPU/network/media data while the custom Dock is hidden or inactive. Expected: refresh according to all visible subscribers. Actual: RefreshScheduler requires the global Dock-visible flag even with subscribers; CPU/network/media policy also uses Dock visibility. A standalone/editor consumer can therefore hold stale readings. Clock's TimelineView and provider initial fetches have different ownership and should not be generalized into this finding.
- **Proposed change / components / dependencies:** Aggregate typed visible-consumer demand and centralize polling ownership; retain zero-work behavior when all consumers are absent. subscriber lifecycle, not simply higher polling; Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** Dock visible/hidden, editor only, popout only, multiple same-kind widgets, absent widgets and sleep/wake; measure refresh counts and resource use.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-P01 — AI Activity double-counts duplicate logical records

- **Primary owner / related IDs:** Reliability; PR-04, PR-15.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [AIUsageService.swift:626](../../Sources/MyDock/SystemServices/AIUsageService.swift:626), per-file Codex counters 574; R unchanged-source fixture, source-slice-results.json. No provider billing/quota claim is inferred from these local counters, and no real account history was read for the scenario.
- **Intended outcome and current trigger:** A Claude assistant message appears twice in local JSONL, or two Codex rollout files represent the same session and cumulative usage. Expected: count unique logical usage, or flag uncertain duplicates. Actual: fixture output was Claude 260 tokens/2 requests/2 tools for one 130-token message; copied Codex session 260 tokens and one session for 130 unique tokens. Both reported `partial=false`.
- **Proposed change / components / dependencies:** Deduplicate with supported provider/session/message identity and preserve provenance; unknown schemas should not silently become complete totals. local schemas are not an authoritative billing API; avoid undercounting distinct messages; Medium.
- **Migration / regression risks:** Recompute/version corrected metric caches; logical ID dedup must not undercount genuinely distinct equal-usage messages.
- **Acceptance criteria:** repeated messages, copied/resumed sessions, legitimate repeated equal usage, range/DST boundaries and partial file budgets.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-P02 — Claude account/limits and activity resolve different directories

- **Primary owner / related IDs:** Reliability; PR-04, PR-15.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [AIAccountService.swift:29](../../Sources/MyDock/SystemServices/AIAccountService.swift:29); [AIUsageService.swift:463](../../Sources/MyDock/SystemServices/AIUsageService.swift:463). No real configuration was modified.
- **Intended outcome and current trigger:** Claude uses `CLAUDE_CONFIG_DIR`. Expected: account setup, limits bridge and local activity use the same configured installation. Actual: AIAccountService honors that variable; AIActivity always scans home `.claude/projects`. Limits can work while Activity is empty or from another installation.
- **Proposed change / components / dependencies:** One injected directory resolver for all Claude paths. bridge paths and test injection; Small.
- **Migration / regression risks:** One injected root resolver; preserve default path and explicitly supplied custom paths, symlink policy and bridge behavior.
- **Acceptance criteria:** default/custom directory, missing path, symlink policy, isolated test home and relaunch.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-P03 — Shopify Test and Replace rejects the same store

- **Primary owner / related IDs:** Reliability; PR-04, PR-15.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [ShopifyDataService.swift:118](../../Sources/MyDock/SystemServices/ShopifyDataService.swift:118), new store 202; [ConnectionsCenterView.swift:121](../../Sources/MyDock/UI/ConnectionsCenterView.swift:121). No live request or credential replacement was performed.
- **Intended outcome and current trigger:** Replace credentials for an existing Shopify connection, including identical store credentials. Expected: validate the store and preserve the connection's local identity. Actual: connect creates a ShopifyConnectedStore with a new UUID; Connections Center compares it to the existing local ID and throws “different Shopify store.”
- **Proposed change / components / dependencies:** Validate normalized store/provider identity, retain the existing local ID, and keep current concurrent-authority checks. connection directory/Keychain identity; avoid silently replacing another tenant; Small/Medium.
- **Migration / regression risks:** Preserve existing local connection IDs/widget assignment/Keychain authority; compare normalized provider/store identity.
- **Acceptance criteria:** same-store new/identical credentials, different-store rejection, connection removed during validation, token refresh and widgets retaining assignment.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-P04 — Shopify pagination lacks progress and duplicate guards

- **Primary owner / related IDs:** Reliability; PR-04, PR-14.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [ShopifyDataService.swift:226](../../Sources/MyDock/SystemServices/ShopifyDataService.swift:226). T maximum-order coverage is useful but does not prove cursor-progress behavior. No malformed live server scenario was run.
- **Intended outcome and current trigger:** GraphQL returns `hasNextPage=true` with a repeated nonempty cursor and empty/duplicate pages. Expected: bounded failure without a partial or doubled total. Actual: loop bounds only accumulated order count, checks nonempty cursor, and does not limit pages or require cursor advancement. Empty repeated pages can run indefinitely in aggregate despite bounded individual requests; duplicate pages can be counted repeatedly.
- **Proposed change / components / dependencies:** Page/deadline budget, visited cursor detection and order-ID deduplication, rejecting incomplete totals explicitly. GraphQL query ID field, shared refresh permit; Small/Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** empty/repeated cursor, overlapping pages, normal multipage result, cancellation and rate-limit failure.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-P05 — Stripe nested subscription item pagination is ignored

- **Primary owner / related IDs:** Reliability; PR-04, PR-15.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [StripeDataService.swift:300](../../Sources/MyDock/SystemServices/StripeDataService.swift:300). Stripe documents independently paginated item lists in [List subscription items](https://docs.stripe.com/api/subscription_items/list). No live subscription with a partial embedded list was accessed.
- **Intended outcome and current trigger:** A returned subscription's embedded item list is partial. Expected: complete supported item totals or label/refuse incompleteness. Actual: the parser sums only `items.data` and ignores nested `has_more`; the top-level ten-page protection cannot cover it. Supported per-unit gross normalization should not be described as full Stripe dashboard MRR.
- **Proposed change / components / dependencies:** Load all needed items with budgets or explicitly refuse/flag partial input; keep discounts, metered/tiered and tax exclusions honest. request count/rate limits and metric definition; Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** `has_more`, multiple items, transformed quantity/item taxes, zero-decimal currencies and unsupported models.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-P06 — Paddle setup instructions request the wrong permission

- **Primary owner / related IDs:** Reliability; PR-04, PR-15.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [ConnectionsCenterView.swift:84](../../Sources/MyDock/UI/ConnectionsCenterView.swift:84), [PaddleDataService.swift:147](../../Sources/MyDock/SystemServices/PaddleDataService.swift:147), correct error 124. Primary [Paddle MRR contract](https://developer.paddle.com/api-reference/metrics/get-metrics-monthly-recurring-revenue/) specifies the permission, UTC bounds, currency and freshness fields. No live key requested.
- **Intended outcome and current trigger:** Follow Connections Center's instruction to grant transaction/subscription reads. Expected: the key can read the metrics MyDock requests. Actual: three `/metrics/...` endpoints require Metrics Read; the backend error correctly says `metrics.read`, but setup copy does not.
- **Proposed change / components / dependencies:** Use one provider-owned permission explanation and distinguish Billing live/sandbox keys. none requiring data migration; Small.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** mocked missing-permission response, consistent connection/widget instructions, authorized sandbox smoke test later.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-P07 — Network counter reset is displayed as a huge download

- **Primary owner / related IDs:** Reliability; PR-04, PR-14.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [NetworkActivityReader.swift:50](../../Sources/MyDock/SystemServices/NetworkActivityReader.swift:50); R source-slice results. No actual network reset was induced.
- **Intended outcome and current trigger:** An interface counter falls from 1,000,000 to 100 over four seconds after reset/reconnection. Expected: rebaseline/unavailable rate for that interval. Actual: the fixture produced 1,073,491,849 bytes/s, because every decrease is treated as a 32-bit wrap.
- **Proposed change / components / dependencies:** Distinguish plausible wrap from reset and rebaseline; use native width/identity and monotonic time. avoid masking legitimate high throughput; Small/Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** 32/64-bit wrap, interface disappearance/reuse, sleep/wake, reset and stable traffic.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-P08 — Response size checks occur after complete allocation

- **Primary owner / related IDs:** Reliability; PR-04, PR-16.
- **Current source / status:** Confirmed post-allocation limits (Weather lacks equivalent cap); availability hardening, not demonstrated credential exposure. Source/evidence lead: S StripeDataService 123–124, PaddleDataService 99–100, ShopifyDataService 147–148, MarketDataService 58–60; [WeatherService.swift:105](../../Sources/MyDock/SystemServices/WeatherService.swift:105). GitHub Copilot's streaming cap is an existing stronger pattern. No oversized network transfer was attempted.
- **Intended outcome and current trigger:** An allowed provider sends an unexpectedly large response. Expected: transfer/allocation is bounded before it consumes excessive memory. Actual: Stripe/Paddle/Shopify check 5/5/8 MB after `URLSession.data(for:)` returns; market transport similarly checks 5 MB after allocation, and Weather has no equivalent response-size check. Individual request timeouts do not bound bytes already accumulated.
- **Proposed change / components / dependencies:** Bound streaming/delegate accumulation and total request lifetime; preserve host restrictions and sanitized errors. transport abstraction and concurrency limits; Medium. This is availability hardening, not a demonstrated secret leak.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** oversized/chunked/slow fixture server responses, redirects, cancellation and normal payloads.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-P09 — Credential replacement does not bind Stripe/Paddle tenant identity

- **Primary owner / related IDs:** Reliability; PR-04, PR-13, PR-15.
- **Current source / status:** Strong inference for cross-tenant stale persisted snapshots; live replacement outcome unverified. Source/evidence lead: S [ConnectionsCenterView.swift:109](../../Sources/MyDock/UI/ConnectionsCenterView.swift:109), saves 114/118, authority guard 196; [WidgetDataCoordinator.swift:106](../../Sources/MyDock/Services/WidgetDataCoordinator.swift:106). Assign at 172–174 does clear snapshots, illustrating the missing equivalent in replacement. No live cross-tenant replacement tested.
- **Intended outcome and current trigger:** Replace a connection's key with a valid key for another tenant, then the first fresh request fails. Expected: explicitly identify the new account and invalidate old account snapshots. Actual: validation verifies key capabilities, then retains the user-named local connection ID; the replacement guard checks whether the old credentials changed concurrently, not whether the new key represents the same provider tenant. Cached widget snapshots are not cleared by this form; coordinator cache clearing is a separate transient cache. Old figures can retain the connection label until a successful refresh.
- **Proposed change / components / dependencies:** Validate/display provider identity when available, make deliberate tenant change explicit, and clear/relabel persisted snapshots on authority change. provider identity APIs/metadata migration; preserve concurrency protection; Medium.
- **Migration / regression risks:** Optional tenant metadata migration must distinguish unknown identity, verified same tenant and intentional switch; invalidate persisted snapshots on authority change.
- **Acceptance criteria:** same tenant/new key, different tenant, offline replacement, stale response arriving and deleted connection.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-P10 — “Sessions” totals actually count active session-days

- **Primary owner / related IDs:** Reliability; PR-04, PR-15.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [AIUsageService.swift:492](../../Sources/MyDock/SystemServices/AIUsageService.swift:492), total accumulation 503; [AIUsageWidgetViews.swift:370](../../Sources/MyDock/CustomDock/AIUsageWidgetViews.swift:370), metric 542. T [ProfileStoreTests.swift:2284](../../Tests/MyDockTests/ProfileStoreTests.swift:2284) uses one session across two days and expects two at 2311. This passing test confirms the current aggregation rather than resolving the user-facing meaning.
- **Intended outcome and current trigger:** One local session has usage on two calendar days inside a selected multi-day range. Expected: “Sessions” means distinct sessions across that range, or the label explicitly describes active session-days. Actual: the service deduplicates `(session ID, day)` then sums daily counts; a single session can count more than once. The face and popout label it sessions without that qualification.
- **Proposed change / components / dependencies:** Compute distinct session IDs for range totals, or rename/explain session-days consistently; keep daily activity counts if useful. snapshot/cache migration if semantics change, MD-P01 dedup; Small/Medium.
- **Migration / regression risks:** Distinct range sessions versus session-days is a metric decision; recompute/version caches if meaning changes; daily chart counts may stay distinct.
- **Acceptance criteria:** one cross-midnight session, two sessions same day, multiple-day range/DST and face/popout/accessibility labels.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-U01 — Appearance controls precede the widget's useful task

- **Primary owner / related IDs:** Product experience; PR-08.
- **Current source / status:** Confirmed appearance-before-task structure; task-first restructuring is reviewer judgment and needs task validation. Source/evidence lead: R isolated native configuration; V tools renders; S [WidgetConfigurationSheet.swift:32](../../Sources/MyDock/UI/WidgetConfigurationSheet.swift:32), [WidgetAppearance.swift:42](../../Sources/MyDock/CustomDock/WidgetAppearance.swift:42).
- **Intended outcome and current trigger:** Configure Text Snippets or another setup-heavy widget. Expected: the content/setup action is immediately understandable. Actual: the generic preview, layout cards and icon swatches occupy roughly 430 logical points above the functional form; the native snippet Save action required scrolling. Many configuration screens repeat this stack irrespective of widget complexity.
- **Proposed change / components / dependencies:** Put task/setup first or offer a compact Appearance disclosure/tab, preserving the existing preview, typography and rounded card vocabulary. per-widget configuration state and previews; Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** first-use setup, Save reachability, small windows, keyboard focus and independent layout/icon retention.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H5/H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-U02 — Library sample counts look like existing user content

- **Primary owner / related IDs:** Product experience; PR-08.
- **Current source / status:** Confirmed unlabeled illustrative content in product library; production stored content is not fabricated. Source/evidence lead: R current Add Item library; V catalog/tools matrices; S [AddLibrary.swift:195](../../Sources/MyDock/UI/AddLibrary.swift:195), [AppleWidgetCard.swift:37](../../Sources/MyDock/CustomDock/AppleWidgetCard.swift:37). The separate DEBUG gallery has sample copy; the product AddLibrary lacks its equivalent. This does not mean production widgets invent stored content.
- **Intended outcome and current trigger:** Browse unconfigured File Shelf, Snippets or Links. Expected: illustrative values are clearly examples. Actual: cards show “2 files,” “2 snippets,” or sample links without a visible Sample label. The preview's illustrative accessibility text is hidden by its parent; the Appearance settings preview does correctly show sample-data copy.
- **Proposed change / components / dependencies:** A small shared Example label or setup-oriented empty representation; keep semantic preview dimensions. library card labels only; Small.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** first-run empty account, VoiceOver reading, sample versus live preview distinction.
- **Implementation / work performed:** Targeted required correction implemented, integrated verification pending; broader package/design scope remains partial. Work: precise session privacy label, all retained list entries, accessible Example labels, compact Clock/Checklist geometry, safe weather display and shared appearance bounds as applicable. See implementation journal for exact scope.
- **Verification / actual results:** Specialist source/diff review completed; three formatter fixtures added but not yet executed. Integrated build/tests and all relevant native acceptance remain open.
- **Remaining gaps / blockers / manual:** H5/H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-U03 — Compact faces clip useful clock/checklist content

- **Primary owner / related IDs:** Product experience; PR-11.
- **Current source / status:** Current fixed-width composition corroborates earlier same-day clipping render; no new render or actual desktop legibility check performed. Source/evidence lead: V adaptive-layouts page 2 light/dark; S WidgetPrimitives local Clock face around 292/checklist 327 and semantic widths. Standard Clock in the native preview displayed a useful time/date correctly.
- **Intended outcome and current trigger:** Use Compact Clock with an ordinary 24-hour value or a compact checklist metric. Expected: the selected layout conveys its primary value. Actual: adaptive renders truncate the time to “14:…” and checklist content to “3…”. Compact Clock's 84-point allocation also includes emblem/padding; minimum text scaling does not establish readability.
- **Proposed change / components / dependencies:** Allocate width from supported format/content bounds, reduce emblem priority or use a truly compact composition; preserve Dock height and units. width/overflow geometry and layout migration; Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** 12/24-hour, seconds, locales, long metric values, min/max scale and side representations.
- **Implementation / work performed:** Targeted required correction implemented, integrated verification pending; broader package/design scope remains partial. Work: precise session privacy label, all retained list entries, accessible Example labels, compact Clock/Checklist geometry, safe weather display and shared appearance bounds as applicable. See implementation journal for exact scope.
- **Verification / actual results:** Specialist source/diff review completed; three formatter fixtures added but not yet executed. Integrated build/tests and all relevant native acceptance remain open.
- **Remaining gaps / blockers / manual:** H5/H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-U04 — Settings navigation consumes too much small-window height

- **Primary owner / related IDs:** Product experience; PR-09.
- **Current source / status:** Confirmed spacious wrapping header; reduced density is reviewer judgment. Seven pages are reachable in the earlier audit; no demonstrated unreachable category. Source/evidence lead: V [navigation-minimum.png](../../.build/visual-qa/full-audit-2026-10-03/interaction-renders/navigation-minimum.png), R two-row navigation at the inspected workspace width; S [SettingsView.swift:98](../../Sources/MyDock/UI/SettingsView.swift:98), grid 125.
- **Intended outcome and current trigger:** A narrow Settings window wraps seven categories into three rows. Expected: clear category navigation with enough room for the form. Actual: the Settings heading, padded navigation, page heading/caption and preview dominate the initial viewport. Categories remain reachable; this finding does not reinstate the old hidden horizontal-scroll defect.
- **Proposed change / components / dependencies:** Condense header spacing and redundant hierarchy at small sizes, maintaining labeled native buttons and selected state. embedded/standalone parity; Small/Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** minimum native window, all seven pages, Tab/Shift-Tab, scrolling and focus restoration.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H5/H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-U05 — Resize grip becomes a very narrow pointer target

- **Primary owner / related IDs:** Native platform; PR-11, PR-18.
- **Current source / status:** Confirmed minimum geometry of 9.1 logical points; usability improvement is judgment and pointer acceptance is open, not a declared standards violation. Source/evidence lead: S [CustomDockWindowController.swift:1171](../../Sources/MyDock/DockManagement/CustomDockWindowController.swift:1171), adjustment 1203/reset 1209. Pointer dragging on the desktop was not performed; no standards-conformance failure is asserted solely from this number.
- **Intended outcome and current trigger:** Dock size is the minimum 0.65 scale. Expected: the unobtrusive visible grip has a usable hit area. Actual: its thin hit-area dimension scales from 14 to 9.1 logical points. Accessibility adjustment and double-click reset exist, but do not enlarge the pointer target.
- **Proposed change / components / dependencies:** Keep a minimum transparent hit area independent of Dock scale and use a clear cursor/hover affordance. edge reveal hit testing; Small.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** bottom/left/right at minimum scale, precise and imprecise pointing, keyboard/AX adjustment and neighboring item clicks.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H2/H4 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-U06 — Profile spacing controls expose inconsistent ranges

- **Primary owner / related IDs:** Product experience; PR-09.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [DockInspector.swift:38](../../Sources/MyDock/UI/DockInspector.swift:38), [SettingsView.swift:855](../../Sources/MyDock/UI/SettingsView.swift:855), [ProfileAppearance.swift:44](../../Sources/MyDock/Models/ProfileAppearance.swift:44), DockModels 1163. No claim that an actual 30-point override was silently rewritten during this audit.
- **Intended outcome and current trigger:** Set profile-specific spacing below 4 or above 18 points in the profile inspector, then open Appearance Settings for that profile. Expected: both controls represent the same valid saved value. Actual: inspector permits 0–30 and ProfileAppearance validates that range, while Settings' slider permits only 4–18. Valid saved overrides such as 0 or 30 cannot be represented by the Settings slider's range. Global settings decode also uses 4–18; broad appearance validator bounds are not the same as global decoding bounds.
- **Proposed change / components / dependencies:** One explicit supported range or a clearly described scope-specific range that both surfaces can display; migrate existing valid overrides deliberately rather than silently clamp. preserve existing profile geometry; Small/Medium.
- **Migration / regression risks:** Do not clamp existing valid 0…30 profile overrides to the global 4…18 decoder range; explicit common/scope-specific contract and round-trip fixtures.
- **Acceptance criteria:** 0/4/18/30 inspector→Settings→relaunch and global/profile inheritance; imported older values.
- **Implementation / work performed:** Targeted required correction implemented, integrated verification pending; broader package/design scope remains partial. Work: precise session privacy label, all retained list entries, accessible Example labels, compact Clock/Checklist geometry, safe weather display and shared appearance bounds as applicable. See implementation journal for exact scope.
- **Verification / actual results:** Specialist source/diff review completed; three formatter fixtures added but not yet executed. Integrated build/tests and all relevant native acceptance remain open.
- **Remaining gaps / blockers / manual:** H5/H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-E01 — Immediate persistence blocks the MainActor for the whole save

- **Primary owner / related IDs:** Reliability; PR-13, PR-18.
- **Current source / status:** Confirmed synchronous MainActor/writer boundary; earlier measurements are synthetic, not production stall/FPS evidence. Source/evidence lead: S [ProfileStore.swift:499](../../Sources/MyDock/Persistence/ProfileStore.swift:499), [RevisionedStateWriter.swift:29](../../Sources/MyDock/Persistence/RevisionedStateWriter.swift:29). T [synthetic-performance.json](../../.build/visual-qa/full-audit-2026-10-03/synthetic-performance.json). These are synthetic elapsed durations, not measured UI stalls/FPS or ordinary-profile results.
- **Intended outcome and current trigger:** Immediate Settings/profile commits with a large valid store. Expected: responsive controls with ordered durable persistence. Actual: MainActor commit synchronously waits for validation, encoding and atomic writing. In the explicit DEBUG synthetic workload of 50 profiles/2,000 items, one encode/write took 107.42 ms; 20 immediate appearance changes took 2,079.75 ms versus 107.03 ms for coalesced flush.
- **Proposed change / components / dependencies:** Coalesce routine edits off the main thread with explicit lifecycle flush/results; retain candidate-first publication and revision ordering. MD-A02, draft save contracts and history frequency; Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** large valid fixtures, rapid controls, pending async save then immediate save, injected failure, quit/relaunch and observed native main-thread latency.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-E02 — Unrelated settings can invalidate the Dock's whole root

- **Primary owner / related IDs:** Native platform; PR-17, PR-18.
- **Current source / status:** Confirmed broad signature/root assignment. Hosting view retention and active-resize guard exist; visible hitch/gesture damage is unverified. Source/evidence lead: S [CustomDockWindowController.swift:64](../../Sources/MyDock/DockManagement/CustomDockWindowController.swift:64), signature 217/root 226, resize guard 212.
- **Intended outcome and current trigger:** Change a persisted setting such as the last Settings page while the Dock exists. Expected: only relevant Dock presentation changes update its root. Actual: the signature stores full AppSettings; any unequal field can reach `hosting.rootView = root`. The host itself is retained, and an active resize has an early return, so this is not a claim that every pointer event recreates the host or loses the resize gesture.
- **Proposed change / components / dependencies:** A narrow effective presentation signature and clear service/panel/view ownership; extract one responsibility at a time. render model identity and monitor ownership; Medium. No wholesale rewrite recommended.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** instrument root assignments and subscriptions during unrelated navigation, resizing, profile switch and actual appearance changes.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H2/H4 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-Q01 — Preview/test isolation does not cover every global service

- **Primary owner / related IDs:** Reliability; PR-05.
- **Current source / status:** Confirmed conditional source defect; end-to-end/native acceptance open. Source/evidence lead: S [MyDockApp.swift:52](../../Sources/MyDock/MyDockApp.swift:52), render 63–69, termination 201/203/229/231; [WindowPreviewCache.swift:55](../../Sources/MyDock/SystemServices/WindowPreviewCache.swift:55), [WindowAccessibilityService.swift:211](../../Sources/MyDock/SystemServices/WindowAccessibilityService.swift:211), retention removal 226, ProductRuntimeTests custom-Dock opt-in. This audit always used `MYDOCK_VISUAL_PREVIEW=1`; successful bundled scenarios also had preview bundle identities, and the custom-Dock opt-in was not run.
- **Intended outcome and current trigger:** Run DEBUG render mode without the separate visual-preview flag, or run the custom-Dock runtime opt-in with only a temporary ProfileStore. Expected: every write, cleanup, cache and native side effect uses isolated dependencies. Actual: render exports use previewStore, but termination selects the ordinary store unless visualPreview is true and can flush it/reach native preference restoration. WindowAccessibilityMonitor's shared preview cache defaults to the user's cache and retention-off configuration can remove it even when the test store disallows system changes.
- **Proposed change / components / dependencies:** One explicit audit/test mode that injects isolated state, UserDefaults, caches, notifications, credential facades and native preference backends; refuse mutation opt-ins without proven isolation. service injection and lifecycle; Medium/Large. Existing audit artifacts do not prove that every global read is isolated, and real user data was deliberately not opened to manufacture that proof.
- **Migration / regression risks:** No shipping data relocation assumed; inject every mutation-capable dependency, including launch/error/quit paths, with production identities intact.
- **Acceptance criteria:** a disposable user/VM traces writes and native calls for every harness, including failure and termination.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-Q02 — Test/render coverage leaves significant acceptance holes

- **Primary owner / related IDs:** Native platform; PR-17, PR-19, PR-20.
- **Current source / status:** Confirmed coverage omissions; ledger inventory is complete but missing executable/render/native checks are not closed. Source/evidence lead: T tests.log/safe-optins.log; S [PremiumVisualQA.swift:352](../../Sources/MyDock/UI/PremiumVisualQA.swift:352), Tests/MyDockUITests, CI validate.yml. Geometry, symbol availability and frame-policy assertions are useful unit contracts, not native interaction acceptance.
- **Intended outcome and current trigger:** Treat the reported 258-test run or a full gallery export as acceptance. Expected: tests cover meaningful failure contracts and native paths are identified separately. Actual: five opt-ins are skipped, nine Xcode UI methods are unrun, and adaptive export uses three pages of ten for a 35-family registry. The last five families are absent from that semantic matrix; tools renders cover four of them but not App Folder. Numeric extremes, incompatible future models, same-store replacement and untitled raw identity lack relevant regressions.
- **Proposed change / components / dependencies:** Registry-derived matrices, failure fixtures from these findings, safe dependency injection, and a separate reproducible native suite. MD-Q01/full Xcode; avoid brittle sleep-only tests and pixel-golden claims about glass; Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** each registered family/configuration, all finding triggers, explicit skipped ledger, native release bundle path.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H5/H8 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-Q03 — Canonical local bundle cannot evidence advertised Focus discovery

- **Primary owner / related IDs:** Native platform; PR-19.
- **Current source / status:** Confirmed canonical metadata absence; actual Focus discovery remains unverified. Source/evidence lead: R read-only bundle inventory; S [SettingsView.swift:273](../../Sources/MyDock/UI/SettingsView.swift:273), FocusDockFilterIntent.swift, [ReleaseMyDock.sh:32](../../ReleaseMyDock.sh:32), CI metadata gate. Unit tests of intent selection do not establish OS registration.
- **Intended outcome and current trigger:** Follow Settings' instruction to add MyDock's Focus filter using the canonical CLI-built app. Expected: a qualified bundle exposes it. Actual: canonical and disposable CLI Release contain no `Metadata.appintents`. Xcode/release tooling explicitly requires that metadata; actual system discovery was not exercised.
- **Proposed change / components / dependencies:** Give local users an accurate capability explanation and validate a metadata-bearing release bundle; choose CI artifacts accordingly. full Xcode and identity; Small/Medium.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** System Settings Focus discovery, assignment, disable/nil behavior and signed-bundle relaunch.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H9 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-Q04 — Local build evidence is not distribution qualification

- **Primary owner / related IDs:** Native platform; PR-19.
- **Current source / status:** Confirmed qualification gap; existing release tooling is present, its end-to-end acceptance remains blocked. Source/evidence lead: R codesign/lipo/plist read checks; S [ReleaseMyDock.sh:23](../../ReleaseMyDock.sh:23), full release gates 28–56; `.github/workflows/validate.yml` artifact path. A real release pipeline **exists**; it was not executed or verified end-to-end here.
- **Intended outcome and current trigger:** Ship the local validation artifact as a finished release. Expected: Developer ID/hardened runtime/notarization/Gatekeeper plus supported-host execution. Actual: canonical/disposable bundles are universal ad-hoc v0.1.0/build 1 with no signing team. Full Xcode is absent, UI tests and metadata-bearing build were not run, no signed/notarized release was produced, and older supported macOS/Intel execution remains unknown. CI uploads the CLI bundle rather than its metadata-checked Xcode product.
- **Proposed change / components / dependencies:** Run the existing gated release process on an authorized release host and explicitly select the distributable artifact. full Xcode, authorized signing/notary identities, release policy; Medium/Large. No precise time estimate is justified.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** clean install/quarantine/Gatekeeper, entitlements/permissions, login/update/Focus, Intel and macOS 13+ fallbacks, reproducible metadata and checksum.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H9 plus criteria above; isolated fixtures and scenario prerequisites required.

### MD-Q05 — Completion language and historical inventories outpace evidence

- **Primary owner / related IDs:** Product experience; PR-20.
- **Current source / status:** Confirmed documentation/evidence mismatches. This ledger corrects planning claims only; current baseline documents remain unchanged. Source/evidence lead: H docs/history 2026-09-29 through 2026-10-03; S current docs/ARCHITECTURE.md, IMPLEMENTATION_STATUS.md, RELEASE_AUDIT.md and BUILD_BASELINE.json compared with this ledger.
- **Intended outcome and current trigger:** Plan a release or prioritize defects from existing reports alone. Expected: claims identify current source, tests and remaining native acceptance. Actual: historical widget/test counts are stale; architecture's future-schema protection description misses MD-A01; broad “fully implemented” utility/identity descriptions omit current defects. Older tool failures no longer describe all safe UI inspection. Current release documents do preserve many valid gaps and should not be dismissed wholesale.
- **Proposed change / components / dependencies:** Link current acceptance to explicit evidence and keep historical records dated. after corrective work; Small. This audit adds reports and does not rewrite the existing development baseline documents.
- **Migration / regression risks:** No authored schema change assumed; preserve valid profiles, identities and permissions; review cache/lifecycle compatibility.
- **Acceptance criteria:** counts from registry, no native/FPS/glass claim without its ledger, unresolved finding IDs retained.
- **Implementation / work performed:** Unstarted corrective/improvement scope; current affected code remains present. Work: current call-path/hash inspection and planning only.
- **Verification / actual results:** source corroborated; earlier T/R/V evidence not rerun; corrective/native acceptance open.
- **Remaining gaps / blockers / manual:** H5/H8 plus criteria above; isolated fixtures and scenario prerequisites required.

<a id="packages"></a>

## Package ledger — all 20 PR proposals

Package acceptance is not inherited from a related finding or a passing unrelated test. Shared-model/interface changes follow coordinator ownership above.

### PR-01 — Compatibility and safe input

- **Primary owner / related IDs:** Reliability; MD-A01, MD-A03, MD-A04.
- **Current source / status:** [ProfileStore:40](../../Sources/MyDock/Persistence/ProfileStore.swift:40); [BackupManager:79](../../Sources/MyDock/Backup/BackupManager.swift:79); [ProfileSemanticValidator:33](../../Sources/MyDock/Models/ProfileSemanticValidator.swift:33); [AIUsageService:75](../../Sources/MyDock/SystemServices/AIUsageService.swift:75); [MarketDataService:138](../../Sources/MyDock/SystemServices/MarketDataService.swift:138) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Reject incompatible future schemas and unsafe numbers without replacing authored state or trapping.
- **Dependencies / components / migration:** Isolated fixtures; envelope/version dispatch; explicit old-schema migrations. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Unknown enums/future versions remain untouched; extreme values safely reject; valid old files still import. Risk: overly permissive or overly strict decoder. MD-A01/A03/A04.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P1 / Medium.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-02 — Truthful mutations and recoverable edits

- **Primary owner / related IDs:** Reliability; MD-A02, MD-A05, MD-A06, MD-A07.
- **Current source / status:** [ProfileStore:98](../../Sources/MyDock/Persistence/ProfileStore.swift:98); [ProfileStore:442](../../Sources/MyDock/Persistence/ProfileStore.swift:442); [ProfileStore:471](../../Sources/MyDock/Persistence/ProfileStore.swift:471); [WidgetSetupDraftStore:95](../../Sources/MyDock/Services/WidgetSetupDraftStore.swift:95); [ProfileEditSessionCoordinator:75](../../Sources/MyDock/Services/ProfileEditSessionCoordinator.swift:75) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Durable success, retained rejected/unfinished input, consistent save/discard/cancel and local collection undo.
- **Dependencies / components / migration:** Explicit mutation outcomes; private draft lifecycle; preserve profile merge/revision semantics. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Failed Restore never says success; rejected note remains; snippet/link Escape and relaunch preserve or explicitly discard; undo respects later edits. Risk: synchronous editing or content resurrection. MD-A02/A05–A07.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P1 core; P2 extension / Medium–Large.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-03 — Native action identity and capability

- **Primary owner / related IDs:** Native platform; MD-D01, MD-D02, MD-D03.
- **Current source / status:** [AppLauncher:38](../../Sources/MyDock/SystemServices/AppLauncher.swift:38); [WindowAccessibilityService:64](../../Sources/MyDock/SystemServices/WindowAccessibilityService.swift:64); [CustomDockWindowController:579](../../Sources/MyDock/DockManagement/CustomDockWindowController.swift:579); [CustomDockWindowController:1491](../../Sources/MyDock/DockManagement/CustomDockWindowController.swift:1491) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Windows/Close are discoverable; the intended app copy/window receives the action; normal quit cancellation is respected.
- **Dependencies / components / migration:** Public-API action layer, permission classification and native fixtures; identity migration only where persisted. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Default settings expose valid window actions; untitled/stale/relaunched/multi-copy/Finder cases; unsaved Close/Quit/Cancel accepted. Risk: action on wrong process or force-quit substitution. MD-D01–D03.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P1 / Medium–Large.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-04 — Provider correctness repairs

- **Primary owner / related IDs:** Reliability; MD-A04, MD-P01, MD-P02, MD-P03, MD-P04, MD-P05, MD-P06, MD-P07, MD-P08, MD-P09, MD-P10.
- **Current source / status:** [ConnectionsCenterView:109](../../Sources/MyDock/UI/ConnectionsCenterView.swift:109); [ShopifyDataService:118](../../Sources/MyDock/SystemServices/ShopifyDataService.swift:118); [AIUsageService:574](../../Sources/MyDock/SystemServices/AIUsageService.swift:574); [StripeDataService:300](../../Sources/MyDock/SystemServices/StripeDataService.swift:300); [NetworkActivityReader:50](../../Sources/MyDock/SystemServices/NetworkActivityReader.swift:50) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Account replacement, aggregation, pagination and rate readings are credible.
- **Dependencies / components / migration:** Stable verified tenant identity; parser/progress conventions; invalidate corrected metric caches. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Same-store Shopify replacement succeeds; old tenant readings disappear on switch; repeated records/cursors and nested pages behave correctly; network reset produces no false spike. Risk: changed totals and historical cache semantics. MD-P01–P10 as mapped below.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P1 core; P2 narrower fixes / Medium.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-05 — Safe application environments

- **Primary owner / related IDs:** Reliability; MD-Q01.
- **Current source / status:** [MyDockApp:52](../../Sources/MyDock/MyDockApp.swift:52); [MyDockApp:201](../../Sources/MyDock/MyDockApp.swift:201); [WindowAccessibilityService:211](../../Sources/MyDock/SystemServices/WindowAccessibilityService.swift:211); [WindowPreviewCache:55](../../Sources/MyDock/SystemServices/WindowPreviewCache.swift:55) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Validation can exercise failures without touching personal state or native preferences.
- **Dependencies / components / migration:** Inject mutation-capable services first; keep production paths unchanged. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Launch/error/Quit in isolated mode cannot access production store/cache/credentials/preferences; no fake permission enables real operations. Risk: partial injection retaining an unsafe singleton. MD-Q01.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P1 / Medium–Large.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-06 — Clear modes and first success

- **Primary owner / related IDs:** Product experience; no direct original MD finding; product proposal.
- **Current source / status:** [OnboardingView:120](../../Sources/MyDock/UI/OnboardingView.swift:120); [DockProfileStatus:6](../../Sources/MyDock/Models/DockProfileStatus.swift:6); [DockModels:1106](../../Sources/MyDock/Models/DockModels.swift:1106) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Users understand Select/Activate/Apply and start with useful familiar content.
- **Dependencies / components / migration:** PR-02/03; preserve existing mode; optional read-only capture into custom profile. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Newcomers explain active versus editing state and Apple Dock effect; create/use/switch without coaching; tutorial dismisses and returns. Risk: renaming that obscures existing users’ expectations.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P2 / Medium.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-07 — Sustained workspace editing

- **Primary owner / related IDs:** Product experience; no direct original MD finding; product proposal.
- **Current source / status:** [DockManagerView:285](../../Sources/MyDock/UI/DockManagerView.swift:285); [ProfileEditSessionCoordinator:5](../../Sources/MyDock/Services/ProfileEditSessionCoordinator.swift:5); [DockCanvas](../../Sources/MyDock/UI/DockCanvas.swift) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Large profiles can be found, organized and repaired without repeated tiny sheets.
- **Dependencies / components / migration:** PR-02/06; one shared order/selection/draft/undo. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Preview and Organize remain synchronized; long names/missing items clear; named core actions/menu commands reachable; large-profile task study improves. Risk: divergent state or overfilled toolbar.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P2 / Medium–Large.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-08 — Task-first setup and discovery

- **Primary owner / related IDs:** Product experience; MD-A05, MD-A06, MD-U01, MD-U02.
- **Current source / status:** [WidgetConfigurationSheet:32](../../Sources/MyDock/UI/WidgetConfigurationSheet.swift:32); [WidgetAppearance:42](../../Sources/MyDock/CustomDock/WidgetAppearance.swift:42); [AddLibrary:195](../../Sources/MyDock/UI/AddLibrary.swift:195) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Add/configure a useful capability before styling it.
- **Dependencies / components / migration:** PR-02; capability metadata from PR-17 can follow; no family identifier changes. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Content/Save reachable at minimum size; examples labelled; repeated instances obvious; use/configure contracts predictable; all 35 families checked. Risk: hidden drafts or oversimplifying provider forms. MD-U01/U02.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P2 / Medium.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-09 — One appearance/settings contract

- **Primary owner / related IDs:** Product experience; MD-U04, MD-U06.
- **Current source / status:** [DockInspector:38](../../Sources/MyDock/UI/DockInspector.swift:38); [SettingsView:855](../../Sources/MyDock/UI/SettingsView.swift:855); [ProfileAppearance:44](../../Sources/MyDock/Models/ProfileAppearance.swift:44); [DockModels:1163](../../Sources/MyDock/Models/DockModels.swift:1163) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Values, scope and inheritance mean the same thing in every entry point.
- **Dependencies / components / migration:** Shared ranges/resolver; retain full overrides initially; partial overrides need separate migration. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Inspector, Settings and resize round-trip every valid value; reset and inheritance predictable; small-window navigation usable. Risk: silently altering saved appearance. MD-U04/U06.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P2 / Medium.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-10 — Complete target and spatial interactions

- **Primary owner / related IDs:** Native platform; MD-D04, MD-D05, MD-D06.
- **Current source / status:** [CustomDockWindowController:1279](../../Sources/MyDock/DockManagement/CustomDockWindowController.swift:1279); [CustomDockWindowController:1652](../../Sources/MyDock/DockManagement/CustomDockWindowController.swift:1652); [DockUtilityWidgetViews:106](../../Sources/MyDock/CustomDock/DockUtilityWidgetViews.swift:106); [DockUtilityModels:13](../../Sources/MyDock/Widgets/DockUtilityModels.swift:13); [TrashService:99](../../Sources/MyDock/SystemServices/TrashService.swift:99) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Repair missing targets and understand drops, pin/remove, overflow and popout focus.
- **Dependencies / components / migration:** PR-02/03/05; bookmark/reference refresh; retain unavailable targets. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Locate recovers moved files; external insertion is explicit; drag cancel, keyboard reorder, overflow, multiple displays and popout dismissal accepted. Trash scope must match action. Risk: unintended file movement/deletion or orphaned popout. MD-D04–D06.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P2 / Medium.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-11 — Glanceability, formatting and accessibility

- **Primary owner / related IDs:** Product experience; MD-U03, MD-U05.
- **Current source / status:** [WidgetPrimitives:292](../../Sources/MyDock/CustomDock/WidgetPrimitives.swift:292); [WidgetPresentation](../../Sources/MyDock/Models/WidgetPresentation.swift); [DockUtilityWidgetViews](../../Sources/MyDock/CustomDock/DockUtilityWidgetViews.swift); [DockInspector](../../Sources/MyDock/UI/DockInspector.swift) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Read and operate the app at small sizes, by keyboard and assistive technology.
- **Dependencies / components / migration:** Shared semantic components and focus contracts; preserve layout/icon migration; PR-08. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Ordinary time/counts fit; units/precision/locale correct; all major tasks with keyboard/VoiceOver; contrast/text/motion variants accepted. Risk: shrinking content instead of adapting it. MD-U03/U05.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P2 / Medium–Large.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-12 — Qualified material and motion

- **Primary owner / related IDs:** Native platform; no direct original MD finding; product proposal.
- **Current source / status:** [DockMaterialSurface](../../Sources/MyDock/CustomDock/DockMaterialSurface.swift); [CustomDockWindowController:612](../../Sources/MyDock/DockManagement/CustomDockWindowController.swift:612); [SettingsView](../../Sources/MyDock/UI/SettingsView.swift) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** The Dock stays readable and responds coherently through animation changes.
- **Dependencies / components / migration:** Real desktop fixture environment; PR-09/11/18; saved settings remain compatible. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Full opacity/tint range on wallpaper; real corners/halos; Off/Reduce Motion/interruption/reversal/preview accepted; older-OS fallbacks. Risk: previews claiming compositing they cannot show.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P2 / Medium.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-13 — Authored state versus runtime cache

- **Primary owner / related IDs:** Reliability; MD-S05, MD-P09, MD-E01.
- **Current source / status:** [DockModels:384](../../Sources/MyDock/Models/DockModels.swift:384); [WidgetDataCoordinator:215](../../Sources/MyDock/Services/WidgetDataCoordinator.swift:215); [ProfileStore:442](../../Sources/MyDock/Persistence/ProfileStore.swift:442) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Refreshes stay fast and offline readings remain honest without complicating recovery.
- **Dependencies / components / migration:** PR-01/02/05/15; versioned cache migration from embedded snapshots. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Offline relaunch and failed refresh retain correct last-good data; tenant switch/deletion invalidate; backups keep authored content; provider refresh is not an edit/history event. Risk: lost cache/provenance or stale cross-tenant results. MD-E01/P09.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P2 / Large, phased.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-14 — Demand, deadlines and cancellation

- **Primary owner / related IDs:** Reliability; MD-S01, MD-S02, MD-S03, MD-S04, MD-S05, MD-P04, MD-P07.
- **Current source / status:** [RefreshScheduler:49](../../Sources/MyDock/SystemServices/RefreshScheduler.swift:49); [ShortcutsService:74](../../Sources/MyDock/SystemServices/ShortcutsService.swift:74); [CurrentLocationService:20](../../Sources/MyDock/SystemServices/CurrentLocationService.swift:20); [HydrationReminderService:26](../../Sources/MyDock/SystemServices/HydrationReminderService.swift:26) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Visible consumers update; absent widgets cost less; hung work is bounded.
- **Dependencies / components / migration:** PR-05/13; service demand tokens; preserve scheduled timer/alarm semantics. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Dock hidden but popout/editor visible updates; absent widgets release demand; Shortcuts/folder/location work bounded; sleep/wake and cancellation safe; Hydration reconciles. Risk: subscription leaks or disabling useful background behavior. MD-S01–S05.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P2 / Medium–Large.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-15 — Provider provenance and connection health

- **Primary owner / related IDs:** Reliability; MD-P01, MD-P02, MD-P03, MD-P05, MD-P06, MD-P09, MD-P10.
- **Current source / status:** [ConnectionsCenterView:27](../../Sources/MyDock/UI/ConnectionsCenterView.swift:27); [AIActivityPresentation](../../Sources/MyDock/Models/AIActivityPresentation.swift); [WidgetDataCoordinator](../../Sources/MyDock/Services/WidgetDataCoordinator.swift) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Users know which account, source, interval and freshness a number belongs to.
- **Dependencies / components / migration:** PR-04; stable identity, metric semantics and freshness contract; cache semantic versions. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Stored versus tested/valid/offline status distinct; partial/estimated readings labelled; no local tokens shown as quota; disconnect impact clear. Risk: invented health claims or generic labels erasing provider differences. MD-P01/P03/P05/P06/P09/P10.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P2 / Medium–Large.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-16 — Recovery and privacy clarity

- **Primary owner / related IDs:** Reliability; MD-A07, MD-A08, MD-A09, MD-D05, MD-P08.
- **Current source / status:** [RecoveryCenterView:15](../../Sources/MyDock/UI/RecoveryCenterView.swift:15); [ProfileLibrary:15](../../Sources/MyDock/Persistence/ProfileLibrary.swift:15); [ProfileSanitizer:8](../../Sources/MyDock/Models/ProfileSanitizer.swift:8); [PersonalPresetPicker:21](../../Sources/MyDock/UI/PersonalPresetPicker.swift:21) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Restore what is available, undo mistakes and understand retention/export scope.
- **Dependencies / components / migration:** PR-01/02/05; precise private-content preference migration and history policy. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** All retained history/presets reachable; scope and lifetime truthful; no secrets/default private content in portable history; streaming caps and diagnostic review. Risk: privacy over-retention or restoring deliberate deletion. MD-A08/A09/P08.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P2 / Medium.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-17 — Typed capabilities and ownership extraction

- **Primary owner / related IDs:** Product experience; MD-E02, MD-Q02.
- **Current source / status:** [DockModels:1229](../../Sources/MyDock/Models/DockModels.swift:1229); [WidgetViews:12](../../Sources/MyDock/CustomDock/WidgetViews.swift:12); [WidgetPresentation:38](../../Sources/MyDock/Models/WidgetPresentation.swift:38); [PremiumVisualQA:352](../../Sources/MyDock/UI/PremiumVisualQA.swift:352); [CustomDockWindowController:64](../../Sources/MyDock/DockManagement/CustomDockWindowController.swift:64) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** New/refined widgets remain consistent and easier to qualify.
- **Dependencies / components / migration:** PR-01/05/13/14; stable family IDs and fixture migrations; extract boundaries when useful. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Registry matches render/config/service inventory; every advertised layout/state covered; missing exports fail validation; family payload migrations preserve content. Risk: framework complexity or a risky all-at-once conversion. MD-Q02/E02.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P2 / Large, incremental.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-18 — Measured responsiveness

- **Primary owner / related IDs:** Native platform; MD-U05, MD-E01, MD-E02.
- **Current source / status:** [ProfileStore:499](../../Sources/MyDock/Persistence/ProfileStore.swift:499); [RevisionedStateWriter:29](../../Sources/MyDock/Persistence/RevisionedStateWriter.swift:29); [CustomDockWindowController:64](../../Sources/MyDock/DockManagement/CustomDockWindowController.swift:64) Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Launch, reveal, resize and editing remain responsive on real workloads.
- **Dependencies / components / migration:** PR-05; signposts/profiling; PR-13/14 as evidence directs. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Real bottom/side resize, pointer latency, hitches, CPU/memory/writes measured; no per-event durable write; host retention/root updates checked. Risk: optimizing synthetic loops while desktop cost remains. MD-E01/E02/U05.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P2; gate before performance claims / Medium initially.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-19 — Exact-artifact release qualification

- **Primary owner / related IDs:** Native platform; MD-Q02, MD-Q03, MD-Q04.
- **Current source / status:** ReleaseMyDock.sh; [FocusDockFilterIntent](../../Sources/MyDock/Focus/FocusDockFilterIntent.swift); .github/workflows/validate.yml; BuildMyDock.sh Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** The distributed app matches the accepted build and native integrations.
- **Dependencies / components / migration:** Full Xcode/signing/notarization environment; PR-01–05; no user-data mutation for routine CI. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Same metadata-bearing artifact packaged/uploaded; supported OS/Intel, Focus, login, quarantine install, recovery and rollback accepted; manifest recorded. Risk: signed identity/permission differences. MD-Q03/Q04.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P1 before distribution / Medium tooling, Large acceptance.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

### PR-20 — Evidence, help and quality loop

- **Primary owner / related IDs:** Product experience; MD-Q02, MD-Q05.
- **Current source / status:** [DiagnosticsService](../../Sources/MyDock/Services/DiagnosticsService.swift); RELEASE_AUDIT; IMPLEMENTATION_STATUS Proposed scope, with partial existing foundations; linked MD records classify current defects/judgments/inferences.
- **Intended user outcome:** Users recover without developer knowledge; release claims reflect acceptance.
- **Dependencies / components / migration:** Release manifests, sanitized support format and task-study baseline. Single-writer/linked finding obligations apply; preserve existing mode and authored data.
- **Acceptance / regression risks:** Current counts/claims generated or dated; help explains limitations/privacy; opt-in diagnostics reviewed; owner prioritization based on user impact. Risk: telemetry/privacy scope creep. MD-Q02/Q05.
- **Implementation / work performed:** unstarted proposal; work: source/spec/dependency reconciliation only. Priority/effort: P2 / Small–Medium initially.
- **Verification / actual results:** source-only at cited components/findings; no new executed acceptance.
- **Remaining gaps / blockers / manual:** package fixtures and relevant H1–H9 gates; native/provider/release prerequisites open. Batch 3 extensions need a product decision.

<a id="opportunities"></a>

## Opportunity ledger — all 7 OP entries

Every opportunity is deferred pending an explicit product decision, including a minimum scope and a stop condition. Existing primitives do not constitute implementation of the opportunity.

### OP-01 — Explicit project/workspace start

- **Primary owner / related IDs:** Native platform; PR-02, PR-03, PR-07, PR-10.
- **Current source / status:** [AppLauncher:38](../../Sources/MyDock/SystemServices/AppLauncher.swift:38); [DockManagerView](../../Sources/MyDock/UI/DockManagerView.swift); [DockProfileStatus](../../Sources/MyDock/Models/DockProfileStatus.swift). Source primitives inspected; optional proposal, no new family/workflow implemented.
**Intended user outcome / use case:** open the handful of apps, project folders and links needed for a particular task, then activate its useful Dock.

**Minimum useful scope:** a named set of existing validated targets; a preview of what will open; an explicit Start workspace action; per-target outcomes; reasonable duplicate-open avoidance; cancel remaining work. Keep Activate separate from opening everything. Do not automatically quit apps, close documents or promise private window/session restoration.

**Required data and permissions:** saved target references and public Workspace launch/open APIs. Basic opening need not acquire broad new permissions. Window placement/restoration would be a separate feasibility and permission project.

**Components/dependencies:** native target identity, missing-target repair, command outcome model, profile draft/undo and launch acceptance (PR-02/03/07/10).

**Effort / migration / risk:** Large for a coherent workflow; smaller proof of concept possible. **Migration:** optional new workspace-start settings, with no action on old profiles until explicitly configured. **Risk:** unwanted repeated launches and ambiguity between activation and starting.

**Success:** representative users start three real contexts with fewer repeated actions, understand what will open and recover cleanly from missing targets/interruption. **Stop condition:** users prefer ordinary launch targets, or duplicate/unwanted opens outweigh the convenience.

- **Implementation / work performed:** deferred; specifications/source feasibility boundary reviewed and dependencies reconciled only.
- **Verification / actual results:** source inventory/call-path evidence only; no customer-demand study or opportunity acceptance.
- **Remaining gaps / blockers / manual:** product choice first, then isolated fixture pilot and relevant H1–H9/whole-task acceptance. Do not connect accounts or change output/preferences to prove a hypothesis.

### OP-02 — Explainable context switching

- **Primary owner / related IDs:** Native platform; PR-02, PR-03, PR-06, PR-09, PR-14, PR-19.
- **Current source / status:** [FocusDockFilterIntent:69](../../Sources/MyDock/Focus/FocusDockFilterIntent.swift:69); [ProfileEditSessionCoordinator](../../Sources/MyDock/Services/ProfileEditSessionCoordinator.swift); [DockModels](../../Sources/MyDock/Models/DockModels.swift); ReleaseMyDock.sh. Source primitives inspected; optional proposal, no new family/workflow implemented.
**Intended user outcome / use case:** choose a workspace for a Focus or a simple context without repeatedly switching manually.

**Minimum useful scope:** first qualify the existing Focus path, then one deterministic rule type with priority, manual override, dwell/debounce, preview/dry-run and a visible explanation of why a switch occurred. Fall back when the display/profile disappears. Automatic native layout mutation should require a separate explicit policy.

**Required data and permissions:** the specific supported trigger. Focus uses App Intents; foreground-app observation and schedules have different contracts. Do not infer or promise arbitrary system Focus monitoring from unrelated access. [Apple — Focus integration](https://developer.apple.com/documentation/appintents/focus).

**Components/dependencies:** exact release metadata and discovery, switching sessions, effective mode/appearance, demand ownership (PR-02/06/09/14/19).

**Effort / migration / risk:** Large if generalized; begin with a constrained Medium investigation. **Migration:** rules opt-in and disabled by default for existing users. **Risk:** surprising oscillation, conflicting automation and lost drafts.

**Success:** users can explain and override every switch, and no unfinished work is lost. **Stop condition:** a general rule builder becomes harder to understand than manual switching. A reliable shortcut is often enough.

- **Implementation / work performed:** deferred; specifications/source feasibility boundary reviewed and dependencies reconciled only.
- **Verification / actual results:** source inventory/call-path evidence only; no customer-demand study or opportunity acceptance.
- **Remaining gaps / blockers / manual:** product choice first, then isolated fixture pilot and relevant H1–H9/whole-task acceptance. Do not connect accounts or change output/preferences to prove a hypothesis.

### OP-03 — Working collections everywhere

- **Primary owner / related IDs:** Product experience; PR-02, PR-07, PR-08, PR-10, PR-16, PR-17.
- **Current source / status:** [CommandLibrary](../../Sources/MyDock/UI/CommandLibrary.swift); [DockUtilityWidgetViews](../../Sources/MyDock/CustomDock/DockUtilityWidgetViews.swift); [DockUtilityModels](../../Sources/MyDock/Widgets/DockUtilityModels.swift); [WidgetSetupDraftStore](../../Sources/MyDock/Services/WidgetSetupDraftStore.swift). Source primitives inspected; optional proposal, no new family/workflow implemented.
**Intended user outcome / use case:** find and use an explicitly saved snippet, link or shelf item without first locating its widget.

**Minimum useful scope:** command-palette search over existing saved collections; clear copy/open/reveal actions; add/edit/remove/undo; missing-reference repair; deterministic handling of duplicate titles. Preserve collection scope and indicate which profile owns a result.

**Required data and permissions:** existing explicitly saved content. Clipboard reads remain user-triggered. No passive clipboard history, message access or background file import is needed.

**Components/dependencies:** common edit contract, target repair, command search and registry metadata (PR-02/07/08/10/16/17).

**Effort / migration / risk:** Medium/Large. **Migration:** indexes can be rebuilt; authored content must remain unchanged. **Risk:** exposing private text on a shared screen, stale search results or confusion between profile-specific and shared content.

**Success:** a user captures, retrieves, copies/opens and repairs content across relaunch and can undo removal. **Stop condition:** search duplicates the current popout without improving a demonstrated task; begin with small palette results rather than a new collection dashboard.

- **Implementation / work performed:** deferred; specifications/source feasibility boundary reviewed and dependencies reconciled only.
- **Verification / actual results:** source inventory/call-path evidence only; no customer-demand study or opportunity acceptance.
- **Remaining gaps / blockers / manual:** product choice first, then isolated fixture pilot and relevant H1–H9/whole-task acceptance. Do not connect accounts or change output/preferences to prove a hypothesis.

### OP-04 — A dependable next-meeting workflow

- **Primary owner / related IDs:** Product experience; PR-03, PR-08, PR-11, PR-14.
- **Current source / status:** [CalendarRemindersWidgetViews:266](../../Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift:266); [CalendarRemindersService](../../Sources/MyDock/SystemServices/CalendarRemindersService.swift); [WorldClockCityCatalog](../../Sources/MyDock/Models/WorldClockCityCatalog.swift). Source primitives inspected; optional proposal, no new family/workflow implemented.
**Intended user outcome / use case:** know what starts next and reach the actual event’s resources quickly.

**Minimum useful scope:** clear next relevant event, time until start, selected calendar scope, correct zone/day handling and a link/location action only when actual event data supplies one. An optional meeting workspace can use explicitly saved targets.

**Required data and permissions:** Calendar access; existing event URLs/location text. World Clock needs no invented attendees or schedule inference. Launching a URL is not permission to send messages or join on the user’s behalf.

**Components/dependencies:** EventKit recovery, semantic formatting, action validation and existing Calendar/World Clock (PR-03/08/11/14).

**Effort / migration / risk:** Medium for next-event improvement; larger for workspace integration. **Migration:** selected calendars and display preferences, with existing choices retained. **Risk:** all-day/ongoing overlap, ambiguous conference URLs and private calendar information exposed on a visible edge.

**Success:** real fixture events across time zones/DST yield an honest next action, and denied permission leaves unrelated features useful. **Stop condition:** richer meeting orchestration needs unsupported data or becomes a second calendar application.

- **Implementation / work performed:** deferred; specifications/source feasibility boundary reviewed and dependencies reconciled only.
- **Verification / actual results:** source inventory/call-path evidence only; no customer-demand study or opportunity acceptance.
- **Remaining gaps / blockers / manual:** product choice first, then isolated fixture pilot and relevant H1–H9/whole-task acceptance. Do not connect accounts or change output/preferences to prove a hypothesis.

### OP-05 — Audio output utility

- **Primary owner / related IDs:** Native platform; PR-03, PR-11, PR-14, PR-17.
- **Current source / status:** WidgetRegistry is in [DockModels:1229](../../Sources/MyDock/Models/DockModels.swift:1229); there is no Audio Output registered family or claimed qualified device selector. Source primitives inspected; optional proposal, no new family/workflow implemented.
**Intended user outcome / use case:** switch between speakers/headphones without opening Settings.

**Minimum useful scope:** current output, available output devices, explicit selection, hotplug/disconnection feedback and unavailable-device handling. Add volume/mute only where the device supports them.

**Required data and permissions:** feasibility investigation using public Core Audio device/property APIs. No recording capability should be introduced merely to select playback output. The existence of a default-output property is a starting point, not proof that every device is writable. [Apple — Default output device property](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultoutputdevice).

**Components/dependencies:** typed registry, native action outcomes, demand/lifecycle and accessible selector (PR-03/11/14/17).

**Effort / migration / risk:** Medium investigation/implementation, subject to device coverage. **Migration:** stable selected-device preference and fallback policy if needed. **Risk:** aggregate/virtual devices, Bluetooth transitions, unsupported volume and confusion between app output versus system default.

**Success:** changing among representative real devices works with explicit error feedback and keyboard/VoiceOver operation. **Stop condition:** public APIs or supported device behavior cannot give a dependable useful minimum. This is the strongest new-widget hypothesis here, not proven customer demand.

- **Implementation / work performed:** deferred; specifications/source feasibility boundary reviewed and dependencies reconciled only.
- **Verification / actual results:** source inventory/call-path evidence only; no customer-demand study or opportunity acceptance.
- **Remaining gaps / blockers / manual:** product choice first, then isolated fixture pilot and relevant H1–H9/whole-task acceptance. Do not connect accounts or change output/preferences to prove a hypothesis.

### OP-06 — Portable workspace exchange, then optional synchronization

- **Primary owner / related IDs:** Reliability; PR-01, PR-02, PR-05, PR-13, PR-16, PR-17.
- **Current source / status:** [BackupManager:77](../../Sources/MyDock/Backup/BackupManager.swift:77); [ProfileSanitizer:8](../../Sources/MyDock/Models/ProfileSanitizer.swift:8); [ProfileStore:471](../../Sources/MyDock/Persistence/ProfileStore.swift:471); [ProfileLibrary](../../Sources/MyDock/Persistence/ProfileLibrary.swift). Source primitives inspected; optional proposal, no new family/workflow implemented.
**Intended user outcome / use case:** reuse a useful layout on another Mac or share a safe starter with another person.

**Minimum useful scope:** evolve existing exports into a reviewed portable package with content summary, missing-target/connection mapping, version handling and safe import-as-new. Explicitly identify omitted credentials/private content. Templates should contain validated declarative targets, not executable plug-in code.

**Required data and permissions:** existing profile exports and local import. Cloud/account permission is unnecessary for this first stage. Optional sync would be a separate Large project requiring conflict resolution, content-category control, encryption/key recovery, offline edits and deletion semantics.

**Components/dependencies:** migration guard, transactional import, recovery, typed registry and tenant/reference mapping (PR-01/02/13/16/17).

**Effort / migration / risk:** Medium for better portable exchange; Large for sync. **Migration:** versioned package and explicit target reconciliation; never copy device credentials. **Risk:** private content leakage, restoring intentionally deleted data, paths that differ across Macs and account-reference mismatch.

**Success:** a package previews its exact contents, imports without overwriting newer work and explains every unresolved target. **Stop condition:** portable exchange satisfies the need; do not add mandatory cloud infrastructure to a local-first utility.

- **Implementation / work performed:** deferred; specifications/source feasibility boundary reviewed and dependencies reconciled only.
- **Verification / actual results:** source inventory/call-path evidence only; no customer-demand study or opportunity acceptance.
- **Remaining gaps / blockers / manual:** product choice first, then isolated fixture pilot and relevant H1–H9/whole-task acceptance. Do not connect accounts or change output/preferences to prove a hypothesis.

### OP-07 — An optional unified system detail surface

- **Primary owner / related IDs:** Product experience; PR-11, PR-13, PR-14, PR-17, PR-18.
- **Current source / status:** [SystemActivityWidgetViews](../../Sources/MyDock/CustomDock/SystemActivityWidgetViews.swift); [NetworkActivityWidgetViews](../../Sources/MyDock/CustomDock/NetworkActivityWidgetViews.swift); [UtilityWidgetViews](../../Sources/MyDock/CustomDock/UtilityWidgetViews.swift); [RefreshScheduler:49](../../Sources/MyDock/SystemServices/RefreshScheduler.swift:49). Source primitives inspected; optional proposal, no new family/workflow implemented.
**Intended user outcome / use case:** move from a CPU/network/disk glance to related system context without opening three unrelated popouts.

**Minimum useful scope:** one detail surface using existing actual CPU/memory/network/storage data, with units, freshness and selectable sections. Preserve independent Dock faces. Avoid fabricated totals, per-process attribution or process-killing controls.

**Required data and permissions:** current supported local measurements; additional sensors/process attribution need separate feasibility and permission review.

**Components/dependencies:** shared formatting, runtime snapshot separation, demand ownership and sampling/performance acceptance (PR-11/13/14/17/18).

**Effort / migration / risk:** Medium if reusing accepted services; Large if expanded into a system monitor. **Migration:** mainly optional presentation preferences. **Risk:** extra polling, excessive density and scope drift into a different application.

**Success:** related information answers a demonstrated task without increasing absent-widget idle work. **Stop condition:** compact independent popouts are already sufficient. Do not pursue this merely to create a larger dashboard.

- **Implementation / work performed:** deferred; specifications/source feasibility boundary reviewed and dependencies reconciled only.
- **Verification / actual results:** source inventory/call-path evidence only; no customer-demand study or opportunity acceptance.
- **Remaining gaps / blockers / manual:** product choice first, then isolated fixture pilot and relevant H1–H9/whole-task acceptance. Do not connect accounts or change output/preferences to prove a hypothesis.

<a id="workflows"></a>

## Application workflow ledger — all 41 coverage entries

Existing test-lead keys: PS = ProfileStoreTests, PE = ProfileEditingTests, RR = RoadmapRegressionTests, DR = DockAuditRegressionTests, PR = ProductRuntimeTests, WP = WidgetPresentationTests, WU = WidgetUtilityTests, DE = DockUtilityExpansionTests, WS = WeatherServiceTests, AA = AIAccountTests, CP = GitHubCopilotBillingTests, IA = InstalledAppCatalogTests, DG = DiagnosticsServiceTests, SI = SingleInstanceLockTests. These are files under Tests/MyDockTests; PR without a hyphen is a test key, while PR-xx is a work package.

F identifiers are ledger navigation IDs, not new MD findings. Each record retains the source matrix’s complete user path and historical evidence, with separate current planning status. Current file existence/hashes and relevant source paths were corroborated; no new workflow was exercised. Unqualified source filenames are unique under Sources/MyDock; source references in specialist widget rows retain their verified file:line anchors. Existing test citations below are inspected/dated coverage leads, not tests rerun. **F-CHECK:** action→state/service→durability→feedback→recovery→relaunch, with failure and Cancel accepted on the actual artifact.

### F01 — Application lifecycle and status menu

- **Primary owner / related IDs:** Reliability; MD-Q01 PR-02 PR-05 PR-14 PR-19.
- **Entry / intended user outcome:** Launch; status item; Quit. Single instance, workspace/menu status, orderly draft/save/native restoration on quit.
- **Current source / status / missing states:** [MyDockApp](../../Sources/MyDock/MyDockApp.swift); [SingleInstanceLock](../../Sources/MyDock/Core/SingleInstanceLock.swift); [MenuBarProfileTitle](../../Sources/MyDock/UI/MenuBarProfileTitle.swift). Source present; earlier coverage disposition: Implemented but runtime-unverified. Persistence/native restore failure can cancel quit; duplicate-launch path exists.
- **Dependencies / affected components:** No blanket first-launch grants; native mode may own Dock preferences. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** State and drafts flushed on clean quit; crash-window U. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Canonical clean launch/quit/relaunch; menu actions; pending work/native restore; H7/H8. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R isolated preview launch/clean Cmd-Q; canonical not launched. Earlier automated coverage leads: SI; PS:2553; PE save/quit contracts Not rerun here.
- **Remaining gaps / blockers / manual:** H7/H8; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F02 — Onboarding / setup modes

- **Primary owner / related IDs:** Product experience; PR-02 PR-06.
- **Entry / intended user outcome:** First-run wizard; Settings Dock Setup. Choose custom/native/both/main mode and starter content with understandable native consequences.
- **Current source / status / missing states:** [OnboardingView](../../Sources/MyDock/UI/OnboardingView.swift); [ProfileStore:188](../../Sources/MyDock/Persistence/ProfileStore.swift:188)/completeOnboarding; [DockModels](../../Sources/MyDock/Models/DockModels.swift) SetupMode. Source present; earlier coverage disposition: Implemented but runtime-unverified. Failed candidate persistence must not publish partial profiles (T); empty selection path.
- **Dependencies / affected components:** Native mode/application requires explicit system action; no new grants in audit. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Onboarding completion, modes and active IDs in state. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** First-run all branches, failure/retry and relaunch in disposable user; H7/H8. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: V four step renders; no native first-run transition. Earlier automated coverage leads: PS:188; RR failed onboarding; DR status Not rerun here.
- **Remaining gaps / blockers / manual:** H7/H8; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F03 — Create / duplicate / delete profiles

- **Primary owner / related IDs:** Reliability; MD-A02 PR-02.
- **Entry / intended user outcome:** Sidebar New Dock; context menu. Independent IDs and names, selected new profile, reset duplicated runtime notifications.
- **Current source / status / missing states:** [DockManagerView](../../Sources/MyDock/UI/DockManagerView.swift); [ProfileStore](../../Sources/MyDock/Persistence/ProfileStore.swift); [ProfileSanitizer](../../Sources/MyDock/Models/ProfileSanitizer.swift). Source present; earlier coverage disposition: Defective. Empty/duplicate names guarded; kind-create can publish on write failure (MD-A02).
- **Dependencies / affected components:** Native creation may capture/apply only through native action. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Profiles/active IDs persisted; notification references cleaned on removal. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Candidate result contract; create/duplicate/delete, failure, active-profile deletion and relaunch; H8. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: S/V; no destructive native profile deletion. Earlier automated coverage leads: PS duplication/notification identity; PE:68; DR:231 Not rerun here.
- **Remaining gaps / blockers / manual:** H8; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F04 — Rename / profile color

- **Primary owner / related IDs:** Product experience; PR-02 PR-07.
- **Entry / intended user outcome:** Sidebar/context rename; inspector color. Clear in-place rename/color and immediate identity-preserving feedback.
- **Current source / status / missing states:** [DockManagerView](../../Sources/MyDock/UI/DockManagerView.swift); [ProfileStore:299](../../Sources/MyDock/Persistence/ProfileStore.swift:299). Source present; earlier coverage disposition: Implemented but runtime-unverified. Blank name ignored; long name bounded at persistence.
- **Dependencies / affected components:** None. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Name/color in profile; canonical relaunch U. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Color change/native menu labels, failed save, long name and relaunch. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R rename updated sidebar/title with Saving; color S/V. Earlier automated coverage leads: PS store recreation; PE live color merge Not rerun here.
- **Remaining gaps / blockers / manual:** H5/H8; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F05 — Profile search / starter and personal presets

- **Primary owner / related IDs:** Product experience; MD-A09 PR-07 PR-16.
- **Entry / intended user outcome:** Explore; profile search; preset picker. Find profiles and start from available-app templates without private runtime content.
- **Current source / status / missing states:** [DockManagerView](../../Sources/MyDock/UI/DockManagerView.swift); [PersonalPresetPicker](../../Sources/MyDock/UI/PersonalPresetPicker.swift); [ProfileLibrary](../../Sources/MyDock/Persistence/ProfileLibrary.swift); [ProfileSanitizer](../../Sources/MyDock/Models/ProfileSanitizer.swift). Source present; earlier coverage disposition: Defective. No results/empty library messages; only ten personal entries exposed (MD-A09).
- **Dependencies / affected components:** Installed-app catalog read; native apply separately gated. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Personal presets sanitized; copied identities independent. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Browse >10 presets, missing apps, keyboard selection/create and relaunch. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: V Explore/gallery/search/empty; S presets. Earlier automated coverage leads: PS:34; PR libraries sanitize; RR:83 Not rerun here.
- **Remaining gaps / blockers / manual:** H5/H8; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F06 — Profile edit Save / Discard / Cancel and conflicts

- **Primary owner / related IDs:** Reliability; PR-02 PR-06 PR-07.
- **Entry / intended user outcome:** Workspace/inspector edits; switch/quit. Retain dirty draft, merge independent changes, resolve conflicts without resurrecting deletions.
- **Current source / status / missing states:** [ProfileEditSessionCoordinator](../../Sources/MyDock/Services/ProfileEditSessionCoordinator.swift); [ProfileDraftMerge](../../Sources/MyDock/Models/ProfileDraftMerge.swift); [ProfileStore](../../Sources/MyDock/Persistence/ProfileStore.swift). Source present; earlier coverage disposition: Implemented but runtime-unverified. Failed autosave/save retains dirty state; explicit retry/cancel; arrays conflict as units.
- **Dependencies / affected components:** None for model edits; native apply distinct. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** In-memory drafts + debounced saves; crash durability not established. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** All alert branches, concurrent refresh/edit/delete, switch/quit/relaunch; H8. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R saving feedback/navigation only; no native conflict/failed-save alert. Earlier automated coverage leads: PE all merge/save/conflict tests; PS draft tests; RR failed save Not rerun here.
- **Remaining gaps / blockers / manual:** H8; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F07 — Workspace undo / selection / internal reorder

- **Primary owner / related IDs:** Product experience; PR-02 PR-07 PR-10.
- **Entry / intended user outcome:** Tile selection; move actions; Cmd-Z; pointer drag. Stable relative group order and undo preserving unrelated live widget data.
- **Current source / status / missing states:** [DockCanvasDragSurface](../../Sources/MyDock/UI/DockCanvasDragSurface.swift); [DockCanvas](../../Sources/MyDock/UI/DockCanvas.swift); [DockManagerView](../../Sources/MyDock/UI/DockManagerView.swift); [ProfileEditSessionCoordinator](../../Sources/MyDock/Services/ProfileEditSessionCoordinator.swift). Source present; earlier coverage disposition: Implemented but runtime-unverified. Outside/changed-profile cancellation and empty/end/group policies T.
- **Dependencies / affected components:** None. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Accepted order persisted; undo scope in session. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Real pointer drag, separators/groups/empty areas, drag cancel and canonical relaunch; H2/H6. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R AX Move Clock to End then Cmd-Z restored order; actual pointer Dock drag U. Earlier automated coverage leads: DR:121/140/195; PE:178; PS move/group tests Not rerun here.
- **Remaining gaps / blockers / manual:** H2/H6; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F08 — Backup export/import

- **Primary owner / related IDs:** Reliability; MD-A01 MD-A02 MD-A03 PR-01 PR-02 PR-16 OP-06.
- **Entry / intended user outcome:** Settings General Backup. Explicit content scope, bounded independent import, accurate success/error.
- **Current source / status / missing states:** [BackupManager](../../Sources/MyDock/Backup/BackupManager.swift); [SettingsView:916](../../Sources/MyDock/UI/SettingsView.swift:916); [ProfileStore:471](../../Sources/MyDock/Persistence/ProfileStore.swift:471). Source present; earlier coverage disposition: Defective. Malformed/oversize/missing targets reported; combined import/write failure falsely succeeds (MD-A02).
- **Dependencies / affected components:** User-selected file panels only; no secrets included. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Imported new IDs; personal content option; credential references sanitized as defined. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Merged limits/write failure, private-content scopes, old/new schema and restore/relaunch; H8. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: S/V controls; no real data export/import. Earlier automated coverage leads: PS:1394/1419/1436/1448; DE sanitization; diagnostics tests Not rerun here.
- **Remaining gaps / blockers / manual:** H8; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F09 — History / recovery / personal retention

- **Primary owner / related IDs:** Product experience; MD-A07 MD-A08 MD-A09 PR-02 PR-16.
- **Entry / intended user outcome:** Settings General Recovery. Browse all retained layouts, honest private-content scope and safe restore.
- **Current source / status / missing states:** [RecoveryCenterView](../../Sources/MyDock/UI/RecoveryCenterView.swift); [ProfileLibrary](../../Sources/MyDock/Persistence/ProfileLibrary.swift); [ProfileSanitizer](../../Sources/MyDock/Models/ProfileSanitizer.swift). Source present; earlier coverage disposition: Defective. Empty/help exists; first ten only; privacy switch label/lifetime inaccurate (MD-A08/A09).
- **Dependencies / affected components:** None. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** History file separate; default sanitized; includeNotes transient. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** 25-entry fixture browse/restore, label/choice relaunch, retention/error and privacy; H8. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R empty history/default 14 days, 25 entries, 8 MB; no populated restore. Earlier automated coverage leads: PR libraries sanitize; RR layout sanitizer; PS recovery Not rerun here.
- **Remaining gaps / blockers / manual:** H8; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F10 — Corrupt / future state protection

- **Primary owner / related IDs:** Reliability; MD-A01 MD-A03 MD-A04 PR-01.
- **Entry / intended user outcome:** Launch; archive read. Preserve corrupt original; refuse future schema without overwriting.
- **Current source / status / missing states:** [ProfileStore:31](../../Sources/MyDock/Persistence/ProfileStore.swift:31); [BackupManager](../../Sources/MyDock/Backup/BackupManager.swift); [ProfileSemanticValidator](../../Sources/MyDock/Models/ProfileSemanticValidator.swift). Source present; earlier coverage disposition: Defective. Recovery warning and writes-disabled failures exist; unknown future enum bypass (MD-A01).
- **Dependencies / affected components:** Local files only. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Original recovery file kept; replacement writes currently possible for incompatible future model. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Envelope-first version guard, byte equality, numeric snapshot bounds, relaunch; H8. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R isolated arithmetic fixture only; no user state corruption. Earlier automated coverage leads: PS:151/169; DR private state/journal; source-slice limits failure Not rerun here.
- **Remaining gaps / blockers / manual:** H8; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F11 — Persistence retry / termination boundary

- **Primary owner / related IDs:** Reliability; MD-A02 MD-E01 PR-02 PR-13 PR-18.
- **Entry / intended user outcome:** Saving/error banner; Quit alert. Ordered atomic latest state, explicit retry or cancel quit.
- **Current source / status / missing states:** [RevisionedStateWriter](../../Sources/MyDock/Persistence/RevisionedStateWriter.swift); [ProfileStore:489](../../Sources/MyDock/Persistence/ProfileStore.swift:489); [MyDockApp:194](../../Sources/MyDock/MyDockApp.swift:194). Source present; earlier coverage disposition: Implemented but runtime-unverified. Errors retained/retry; synchronous immediate save cost MD-E01.
- **Dependencies / affected components:** None; native restoration also gates quit. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Atomic private state file, revision ordering; drafts not claimed crash-durable. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Disk-full/unwritable/interrupt/retry/quit without saving temporary fixtures; H8. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R ordinary Saving/clean preview quit; real disk failure U. Earlier automated coverage leads: PE retry/debounce; RR failed save; PS failed recovery Not rerun here.
- **Remaining gaps / blockers / manual:** H8; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F12 — Launch / activate selected app

- **Primary owner / related IDs:** Native platform; MD-D03 PR-03.
- **Entry / intended user outcome:** Click pinned/runtime tile; Open menu. Launch chosen app path, activate running selected copy without unnecessary relaunch.
- **Current source / status / missing states:** [AppLauncher](../../Sources/MyDock/SystemServices/AppLauncher.swift); [AppLifecycleService](../../Sources/MyDock/SystemServices/AppLifecycleService.swift); [InstalledAppCatalog](../../Sources/MyDock/SystemServices/InstalledAppCatalog.swift). Source present; earlier coverage disposition: Implemented but runtime-unverified. Missing target offers Locate; unavailable app alert.
- **Dependencies / affected components:** Workspace; no AX required for basic launch. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Pinned executable target retained; runtime entries transient. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Running/new app, Finder, two copies, missing target/Locate, relaunch; H1/H6. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: T safe inventory 118 bundles; no actual app launch via Dock. Earlier automated coverage leads: IA path validation/inventory; PR runtime filter/policy Not rerun here.
- **Remaining gaps / blockers / manual:** H1/H6; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F13 — Minimize / restore / select window

- **Primary owner / related IDs:** Native platform; MD-D02 MD-D03 PR-03.
- **Entry / intended user outcome:** Windows menu; minimized tile; focused click option. Resolve intended live window safely, restore/raise it; explicit fallback.
- **Current source / status / missing states:** [WindowAccessibilityService](../../Sources/MyDock/SystemServices/WindowAccessibilityService.swift); WindowAccessibilityMonitor; Dock controller. Source present; earlier coverage disposition: Defective. No AX/setup/error; untitled fallback and bundle-only grouping defects (MD-D02/D03).
- **Dependencies / affected components:** AX; Screen Recording only for images. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Window descriptors transient; optional preview cache separate. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Untitled/duplicates/stale PID/two copies, minimized restore and window selection; H1. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: S/T only; AX not granted. Earlier automated coverage leads: PR window identity; PS preview matching; DR stale preview tests Not rerun here.
- **Remaining gaps / blockers / manual:** H1; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F14 — Close Window versus Quit App

- **Primary owner / related IDs:** Native platform; MD-D01 MD-D02 MD-D03 PR-03.
- **Entry / intended user outcome:** App context menu. Close one document or normally quit application; respect unsaved/cancel.
- **Current source / status / missing states:** Dock controller:1491; [WindowAccessibilityService](../../Sources/MyDock/SystemServices/WindowAccessibilityService.swift); [AppLauncher:45](../../Sources/MyDock/SystemServices/AppLauncher.swift:45). Source present; earlier coverage disposition: Defective. Close failure alert; normal terminate (not force); default menus may disappear.
- **Dependencies / affected components:** AX for Close; normal app Quit uses Workspace process. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** No document persistence ownership; pinned entry retained. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H1 all Save/Cancel/Don’t Save branches; default and revoked AX; Finder. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: S only; menu visibility default defect (MD-D01). Earlier automated coverage leads: Window identity/unit contracts; no real unsaved-document test. Not rerun here.
- **Remaining gaps / blockers / manual:** H1; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F15 — Pinned/running representation; Keep/Remove

- **Primary owner / related IDs:** Native platform; MD-D03 PR-03 PR-10.
- **Entry / intended user outcome:** Runtime tiles; context Keep in Dock / Remove. Stable pinned entries and appropriate runtime groups without identity collision.
- **Current source / status / missing states:** [DockRenderModel](../../Sources/MyDock/Models/DockRenderModel.swift); [RunningApplications](../../Sources/MyDock/SystemServices/RunningApplications.swift); Dock controller. Source present; earlier coverage disposition: Implemented but runtime-unverified. Terminated/agent filters; multiple-copy bundle dedup limitation.
- **Dependencies / affected components:** Workspace reads; AX only window data. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Pin/remove saved; running-only entries transient; repeated item IDs unique. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Live launch/quit/cancel, keep/remove across profiles and relaunch; H1. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: V render fixtures; no live process pinning. Earlier automated coverage leads: DR:212; PR render model; PS running filter Not rerun here.
- **Remaining gaps / blockers / manual:** H1; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F16 — Files / folders / websites and Locate

- **Primary owner / related IDs:** Native platform; MD-S02 PR-03 PR-10 PR-14.
- **Entry / intended user outcome:** Tile Open; context Locate; inspector. Open safe stored target; explain missing/moved path and recover.
- **Current source / status / missing states:** [AppLauncher](../../Sources/MyDock/SystemServices/AppLauncher.swift); DockLinkPolicy; [FolderContentsPopout](../../Sources/MyDock/CustomDock/FolderContentsPopout.swift); [SiteFaviconFetcher](../../Sources/MyDock/SystemServices/SiteFaviconFetcher.swift). Source present; earlier coverage disposition: Implemented but runtime-unverified. Missing detection/Locate; safe web schemes; favicon errors fallback.
- **Dependencies / affected components:** User file access; browser launch; folder reads; sharing separately. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Target/title/icon/bookmark as defined; favicon cache in item. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Fixture opening/repair, long paths, broken icons, changed volume; H6. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: V missing-item fixtures; no user target opened/moved. Earlier automated coverage leads: PS:1436/1457/1467/1496/1505/1512; folder sorting Not rerun here.
- **Remaining gaps / blockers / manual:** H6; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F17 — External Finder drag / outward drag contracts

- **Primary owner / related IDs:** Native platform; MD-D04 MD-Q02 PR-10 PR-17.
- **Entry / intended user outcome:** External append target; draggable entries/Shelf. Accept validated URL order with explicit supported insertion/drag payload.
- **Current source / status / missing states:** Dock controller:1279/1652; [DockCanvasDragSurface](../../Sources/MyDock/UI/DockCanvasDragSurface.swift); [DockUtilityWidgetViews](../../Sources/MyDock/CustomDock/DockUtilityWidgetViews.swift). Source present; earlier coverage disposition: Partially implemented. Invalid payload rejected; current external intake appends (MD-D04).
- **Dependencies / affected components:** Finder/pasteboard; promises/sharing native. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Accepted items persisted; drag-out should not delete originals. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Real multi-URL/promise/spatial drop and outward contract; H6; spatial insertion optional. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: S/T/V only; no Finder/native outward drag. Earlier automated coverage leads: DR pasteboard/order; DE shelf validation Not rerun here.
- **Remaining gaps / blockers / manual:** H6; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F18 — Overflow scrolling / navigation

- **Primary owner / related IDs:** Native platform; PR-10 PR-18.
- **Entry / intended user outcome:** Long Dock scroll/arrow/jump controls. Reach all items with coherent axis and accurate bounds.
- **Current source / status / missing states:** Dock controller:1083/1216; [DockRenderModel](../../Sources/MyDock/Models/DockRenderModel.swift). Source present; earlier coverage disposition: Implemented but runtime-unverified. Controls only when overflow; resize threshold dynamics unverified.
- **Dependencies / affected components:** None. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Composition stored; scroll position lifetime requires native acceptance. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Wheel/trackpad/keyboard, popout anchoring, overflow mid-resize; H2. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: V bottom/left/right/overflow; live scrolling U. Earlier automated coverage leads: PS:1210; DR geometry Not rerun here.
- **Remaining gaps / blockers / manual:** H2; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F19 — Hover / right-click / long-press / tabbed popouts

- **Primary owner / related IDs:** Native platform; MD-A06 PR-02 PR-10 PR-14.
- **Entry / intended user outcome:** Dock face pointer/menu; popout tabs. Useful popout with stable anchor, focus, Escape/outside dismissal.
- **Current source / status / missing states:** Dock controller; WidgetPopout; DockPopoutTabs. Source present; earlier coverage disposition: Implemented but runtime-unverified. Invalid/deleted tab cleanup; one tabbed host intentional product difference.
- **Dependencies / affected components:** Depends on contained widget action. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Open popout/session focus transient; widget changes stored. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Native hover/long-press/right-click, multi tabs, outside/Escape/focus; H4/H5. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R configuration Escape only; desktop popout interactions U. Earlier automated coverage leads: PS:1216; reveal/popout policies; PR model Not rerun here.
- **Remaining gaps / blockers / manual:** H4/H5; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F20 — Magnification

- **Primary owner / related IDs:** Native platform; PR-12 PR-18.
- **Entry / intended user outcome:** Settings Behavior; hover Dock. Localized restrained wave, honor Reduce Motion.
- **Current source / status / missing states:** Dock controller:1625; DockMagnification policy. Source present; earlier coverage disposition: Implemented but runtime-unverified. Disabled default; no unnecessary glow claimed.
- **Dependencies / affected components:** None. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Global behavior setting. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Live hover/frame pacing, side anchors, resize/popout interaction; H2/H4. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: V fixtures; actual hover U. Earlier automated coverage leads: PS:1200; PR wave identity Not rerun here.
- **Remaining gaps / blockers / manual:** H2/H4; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F21 — Dock resizing / reset / AX adjust

- **Primary owner / related IDs:** Native platform; MD-U05 PR-09 PR-11 PR-18.
- **Entry / intended user outcome:** Grip; double-click; accessibility action. 0.65–1.5 edge-normal resize; no per-event state/history writes; scope inheritance.
- **Current source / status / missing states:** Dock controller:1176; [ProfileStore:275](../../Sources/MyDock/Persistence/ProfileStore.swift:275); [ProfileAppearance](../../Sources/MyDock/Models/ProfileAppearance.swift). Source present; earlier coverage disposition: Implemented but runtime-unverified. Invalid samples rejected; disappearance commits preview; 9.1 pt minimum hit area (MD-U05).
- **Dependencies / affected components:** Pointer/AX control; no system permission required for own UI. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Transient preview then scoped commit+flush; history on completion. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H2 all three edges, cancel/interruption, anchoring, monitor/root/write counts, FPS/latency. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: T geometry/writer; V sizes; actual drag not measured. Earlier automated coverage leads: DR:10/31/244; PR:83; explicit synthetic performance Not rerun here.
- **Remaining gaps / blockers / manual:** H2; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F22 — Animations / Preview / Off / Reduce Motion

- **Primary owner / related IDs:** Native platform; PR-12 PR-18.
- **Entry / intended user outcome:** Settings Appearance/Behavior; reveal/profile switch. Fade/Slide/Gentle Grow with cancellation, Off and reduced motion.
- **Current source / status / missing states:** Dock controller:612; DockPanelMotion; [SettingsView](../../Sources/MyDock/UI/SettingsView.swift). Source present; earlier coverage disposition: Implemented but runtime-unverified. Generation completion guards; repeated preview task cancellation; live stale transforms U.
- **Dependencies / affected components:** System accessibility preference read. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Style/enabled setting stored; profile morph runtime. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H4 Off mid-transition, reversals, repeated previews, hit testing and resize. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R controls selected; no actual animation preview playback. Earlier automated coverage leads: DR:70/83; PS magnification policy Not rerun here.
- **Remaining gaps / blockers / manual:** H4; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F23 — Appearance scope / theme / material / tint / opacity

- **Primary owner / related IDs:** Product experience; MD-U06 PR-09 PR-12.
- **Entry / intended user outcome:** Settings Appearance; profile inspector. Independent global/profile appearance, honest continuous glass controls.
- **Current source / status / missing states:** [ProfileAppearance](../../Sources/MyDock/Models/ProfileAppearance.swift); [DockMaterialSurface](../../Sources/MyDock/CustomDock/DockMaterialSurface.swift); [SettingsView](../../Sources/MyDock/UI/SettingsView.swift). Source present; earlier coverage disposition: Defective. Opaque Reduce Transparency; older ultraThin fallback; wallpaper U.
- **Dependencies / affected components:** Reads system contrast/transparency/motion preferences. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Global defaults or profile override; old raw values migrate; spacing ranges differ (MD-U06). Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H3 wallpaper Clear/Frosted full range/corners, scope/relaunch, old OS; not verified by bitmap. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R control/Clock layout selection; V 0/50/100 glass and corner exports. Earlier automated coverage leads: DR:49; WP migrations; PS:62/2536 Not rerun here.
- **Remaining gaps / blockers / manual:** H3; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F24 — Auto-hide / edge reveal / reveal handle

- **Primary owner / related IDs:** Native platform; PR-10 PR-12 PR-18.
- **Entry / intended user outcome:** Behavior settings; pointer edge. Bounded reveal/dismiss, popout stays reachable, no obsolete reveal.
- **Current source / status / missing states:** Dock controller:373/486; CustomDockVisibilityPolicy. Source present; earlier coverage disposition: Implemented but runtime-unverified. Overview/Apple Dock suppression policies; monitor lifecycle source.
- **Dependencies / affected components:** Workspace/window metadata; AX optional for window features. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Behavior/global setting; ephemeral reveal tasks. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H4/H7 dwell/fast reversals/click outside/fullscreen/Apple Dock overlap. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: V render only; actual edge U. Earlier automated coverage leads: PS:1182/1271/1289; PR queued reveal Not rerun here.
- **Remaining gaps / blockers / manual:** H4/H7; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F25 — Desktop widget mode / Apple Dock coexistence

- **Primary owner / related IDs:** Native platform; PR-03 PR-10 PR-19.
- **Entry / intended user outcome:** Dock Setup mode; Behavior. Window levels/collection behavior appropriate to mode; native prefs restored.
- **Current source / status / missing states:** Dock controller:360; [NativeDockAutoHideController](../../Sources/MyDock/DockManagement/NativeDockAutoHideController.swift); [SystemDockVisibilityService](../../Sources/MyDock/SystemServices/SystemDockVisibilityService.swift). Source present; earlier coverage disposition: Implemented but runtime-unverified. Failure retains recovery record/cancels quit; heuristics are platform-limited.
- **Dependencies / affected components:** Native preferences only through explicitly authorized mode. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Mode/global state; owned keys recovery journal. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H7 disposable user native coexistence, preference restoration and desktop click/focus. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: S/T only; no real mode application. Earlier automated coverage leads: PR desktop visibility policy; PS restoration fixtures; DR rollback Not rerun here.
- **Remaining gaps / blockers / manual:** H7; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F26 — Displays / Spaces / fullscreen / Mission Control

- **Primary owner / related IDs:** Native platform; PR-10 PR-18 PR-19.
- **Entry / intended user outcome:** Settings display; desktop environment. Selected display/fallback and reachability across changes.
- **Current source / status / missing states:** Dock controller:130/269; SystemOverviewPolicy. Source present; earlier coverage disposition: Implemented but runtime-unverified. No-screen/selected-screen fallback; public heuristics.
- **Dependencies / affected components:** Screen metadata; capture permission only for images. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Display selection saved; actual current screens runtime. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H2/H7 connect/remove display, scale/refresh, Spaces/fullscreen/overview. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R read-only one 60 Hz display; multiple displays U. Earlier automated coverage leads: PS secondary-screen geometry; PR overview/visibility Not rerun here.
- **Remaining gaps / blockers / manual:** H2/H7; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F27 — Native Dock capture / apply / restore / auto-save

- **Primary owner / related IDs:** Native platform; PR-02 PR-03 PR-19.
- **Entry / intended user outcome:** Native profile capture/apply; mode; Quit. Serialized transactions, original layout recovery, external-change capture.
- **Current source / status / missing states:** [NativeDockController](../../Sources/MyDock/DockManagement/NativeDockController.swift); [NativeDockAutoHideController](../../Sources/MyDock/DockManagement/NativeDockAutoHideController.swift); [NativeDockAutoSaveMonitor](../../Sources/MyDock/DockManagement/NativeDockAutoSaveMonitor.swift). Source present; earlier coverage disposition: Implemented but runtime-unverified. Journal before write; failure rollback/recovery retained; external change distinction.
- **Dependencies / affected components:** Local native preference ownership; no grant merely for audit. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Native layout, association and recovery journals separate. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H7 disposable-user apply/failure/cancel/interruption/relaunch restore. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: S/mock T only; no Apple Dock mutation. Earlier automated coverage leads: PS:1679–1794,2583+; DR restore/cancel/retry; native opt-in skipped Not rerun here.
- **Remaining gaps / blockers / manual:** H7; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F28 — Focus filter

- **Primary owner / related IDs:** Native platform; MD-Q03 MD-Q04 PR-19 OP-02.
- **Entry / intended user outcome:** System Settings Focus; Settings Shortcuts help. Select intended profile when Focus applies; nil leaves selection alone.
- **Current source / status / missing states:** [FocusDockFilterIntent](../../Sources/MyDock/Focus/FocusDockFilterIntent.swift); [SettingsView:273](../../Sources/MyDock/UI/SettingsView.swift:273); ReleaseMyDock.sh:32. Source present; earlier coverage disposition: Partially implemented. Source intent exists; canonical packaging cannot evidence discoverability (MD-Q03). FocusDockFilterIntent:69–78 activates custom profiles but actually applies native layouts; discovery/activation is not harmless for every profile. Qualify native Apply only in the authorized disposable environment.
- **Dependencies / affected components:** OS App Intents registration; metadata-bearing bundle. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Profile selection persists; intent selection OS-owned. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H9 Xcode metadata, actual Focus discovery/activate/deactivate/relaunch. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R missing Metadata.appintents in CLI bundles; OS discovery U. Earlier automated coverage leads: PS:2436; no OS discovery coverage Not rerun here.
- **Remaining gaps / blockers / manual:** H9; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F29 — Global keyboard shortcuts / profile swipe

- **Primary owner / related IDs:** Native platform; PR-06 PR-11 PR-19 OP-02.
- **Entry / intended user outcome:** Settings Shortcuts; keyboard/trackpad. Conflict-aware shortcuts and intended profile cycle without wheel noise.
- **Current source / status / missing states:** [GlobalShortcutController](../../Sources/MyDock/SystemServices/GlobalShortcutController.swift); [KeyboardShortcutEditor](../../Sources/MyDock/UI/KeyboardShortcutEditor.swift); Dock controller:428. Source present; earlier coverage disposition: Implemented but runtime-unverified. Duplicate bindings rejected; absent profile handling.
- **Dependencies / affected components:** Native hotkey registration; no cloud credentials. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Global settings outside profile backup. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Actual shortcuts at startup/relaunch/other apps, conflicts, gesture cancel; H5/H7. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R shortcut labels/read; global registration not invoked. Earlier automated coverage leads: PS:1368/1302; persistence/duplicate policy Not rerun here.
- **Remaining gaps / blockers / manual:** H5/H7; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F30 — Settings search / category navigation

- **Primary owner / related IDs:** Product experience; MD-U04 MD-E02 PR-09 PR-11 PR-18.
- **Entry / intended user outcome:** Sidebar Settings; search; Cmd-K. Seven visible categories, correct search result/page and focus.
- **Current source / status / missing states:** [SettingsView](../../Sources/MyDock/UI/SettingsView.swift); [SettingsSearchCatalog](../../Sources/MyDock/UI/SettingsSearchCatalog.swift); [CommandLibrary](../../Sources/MyDock/UI/CommandLibrary.swift). Source present; earlier coverage disposition: Implemented but runtime-unverified. No-match guidance; density concern MD-U04, controls not proven unreachable.
- **Dependencies / affected components:** None. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Last page stored; unrelated Dock invalidation MD-E02. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H5 real minimum sizes, standalone parity, keyboard/focus/VO. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R seven wrapping buttons, Cmd-K→Open Settings; V minimum/narrow. Earlier automated coverage leads: RR search; PS:2505; UI suite unrun Not rerun here.
- **Remaining gaps / blockers / manual:** H5; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F31 — Permission overview / recovery

- **Primary owner / related IDs:** Native platform; MD-S03 PR-03 PR-11 PR-14.
- **Entry / intended user outcome:** Settings Permissions; in-context request. Accurate state/help, user-initiated prompt and usable denied fallback.
- **Current source / status / missing states:** [SettingsView](../../Sources/MyDock/UI/SettingsView.swift):permissions; native services; Info.plist. Source present; earlier coverage disposition: Implemented but runtime-unverified. Per-app Automation unknown honest; related widgets show setup/denied.
- **Dependencies / affected components:** AX/Screen Recording/EventKit/Location/Notifications/Automation. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** TCC OS-owned; setup/config persisted separately. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H7 OS-specific denied/revoked/recovery, no repeated prompts, unrelated use. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R denied/not-requested overview; no permission clicked. Earlier automated coverage leads: Display/native policies; no real grant/revoke tests. Not rerun here.
- **Remaining gaps / blockers / manual:** H7; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F32 — Connections / credential assignment / disconnect

- **Primary owner / related IDs:** Reliability; MD-P03 MD-P06 MD-P09 PR-04 PR-15.
- **Entry / intended user outcome:** Settings Integrations; widget connection setup. Read-only validation, safe replacement, explicit disconnect/removal and widget assignment.
- **Current source / status / missing states:** [ConnectionsCenterView](../../Sources/MyDock/UI/ConnectionsCenterView.swift); provider directories/Keychain; [ProfileStore](../../Sources/MyDock/Persistence/ProfileStore.swift) clear refs. Source present; earlier coverage disposition: Defective. Busy/error/offline and preserved prior snapshot; Shopify replacement MD-P03, Paddle scope MD-P06.
- **Dependencies / affected components:** User credentials only if later authorized; Keychain. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Metadata outside portable profiles; no raw secrets exported. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H8 fixtures replacement/tenant/disconnect/races; later authorized account smoke tests. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: S/V only; no accounts/credentials used. Earlier automated coverage leads: PS:884; RR delayed authority; provider request tests Not rerun here.
- **Remaining gaps / blockers / manual:** H8; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F33 — AI account status / Claude bridge setup

- **Primary owner / related IDs:** Reliability; MD-A03 MD-P02 PR-01 PR-04 PR-15.
- **Entry / intended user outcome:** AI connection view; Limits setup. Explain supported local account contracts; preserve existing config; no invented quota.
- **Current source / status / missing states:** [AIAccountService](../../Sources/MyDock/SystemServices/AIAccountService.swift); [AIAccountConnectionView](../../Sources/MyDock/UI/AIAccountConnectionView.swift); [CodexAccountRPC](../../Sources/MyDock/SystemServices/CodexAccountRPC.swift); Claude adapter. Source present; earlier coverage disposition: Implemented but runtime-unverified. Unavailable/setup-required/expired bridge; honest unsupported providers.
- **Dependencies / affected components:** Existing account only if authorized; optional user-installed status bridge. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Status/cache; bridge files opt-in; no actual credentials added. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H8 isolated config path and missing/expired/changed account; current plan variants. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: S/T only; live Codex skip; bridge not installed. Earlier automated coverage leads: AA setup/symlink/RPC tests; PS limits; CP tests Not rerun here.
- **Remaining gaps / blockers / manual:** H8; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F34 — Diagnostics / About

- **Primary owner / related IDs:** Product experience; MD-Q05 PR-16 PR-19 PR-20.
- **Entry / intended user outcome:** General Export Diagnostics; About. Useful redacted status and correct local metadata.
- **Current source / status / missing states:** [DiagnosticsService](../../Sources/MyDock/Services/DiagnosticsService.swift); [AboutView](../../Sources/MyDock/UI/AboutView.swift); [Product](../../Sources/MyDock/Core/Product.swift). Source present; earlier coverage disposition: Implemented but runtime-unverified. Bounded event history; errors do not expose provider response bodies by design.
- **Dependencies / affected components:** User-chosen export file. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Diagnostics separate/local; app version bundle metadata. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Review fixture exported payload/paths; current version/help links; signed metadata. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: V About; no real-user diagnostics export. Earlier automated coverage leads: DG fixed codes/no private content; PR version validation Not rerun here.
- **Remaining gaps / blockers / manual:** H8/H9; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F35 — Login item

- **Primary owner / related IDs:** Native platform; MD-Q04 PR-19.
- **Entry / intended user outcome:** Settings General start at login. Reflect/register/unregister correct signed app and report system status.
- **Current source / status / missing states:** [AppLifecycleService](../../Sources/MyDock/SystemServices/AppLifecycleService.swift); [AppLifecycleSettingsView](../../Sources/MyDock/UI/AppLifecycleSettingsView.swift). Source present; earlier coverage disposition: Implemented but runtime-unverified. SMAppService status/error branches.
- **Dependencies / affected components:** OS login-item authorization/user action. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** OS registration separate from profile backup. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H9 signed install, register/disable/relaunch/login/remove, correct path. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R disabled safe-preview action. Earlier automated coverage leads: Source/policy; no native registration acceptance. Not rerun here.
- **Remaining gaps / blockers / manual:** H9; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F36 — Update check / release links

- **Primary owner / related IDs:** Native platform; MD-Q04 PR-19 PR-20.
- **Entry / intended user outcome:** Settings General Check for Updates. Validated configured repo/version; clear offline/no-config state; user-controlled opening.
- **Current source / status / missing states:** [AppLifecycleService](../../Sources/MyDock/SystemServices/AppLifecycleService.swift); [Product](../../Sources/MyDock/Core/Product.swift). Source present; earlier coverage disposition: Implemented but runtime-unverified. No-config/offline/error; no automatic app replacement claim.
- **Dependencies / affected components:** Network only for configured GitHub repo. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Update config global; no provider secrets needed. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Configured fixture server/repo response, prerelease/version/link validation; signed release flow. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R disabled because repository empty; no update network. Earlier automated coverage leads: PR strict repo/version validation Not rerun here.
- **Remaining gaps / blockers / manual:** H9; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F37 — Local universal build / configuration validation

- **Primary owner / related IDs:** Native platform; MD-Q04 PR-19.
- **Entry / intended user outcome:** ./BuildMyDock.sh --output disposable path. Current source packages arm64+x86_64 with valid local signature/plist.
- **Current source / status / missing states:** BuildMyDock.sh; Package.swift; Xcode plist/project; icon generator. Source present; earlier coverage disposition: Earlier audit verified local packaging narrowly; no new build here. Running target refusal and build failures; no candidate under build/.
- **Dependencies / affected components:** No signing account for ad-hoc build. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Generated output not source; canonical baseline not replaced. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** Verified narrowly for current host local packaging, not app behavior or distribution. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R disposable Release success; canonical hash unchanged. Earlier automated coverage leads: Shell/plist/signature checks; default test suite Not rerun here.
- **Remaining gaps / blockers / manual:** H9; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F38 — Xcode UI / signed release / CI qualification

- **Primary owner / related IDs:** Native platform; MD-Q02 MD-Q03 MD-Q04 PR-17 PR-19.
- **Entry / intended user outcome:** Full Xcode CI; ReleaseMyDock.sh. Metadata-bearing signed/notarized accepted app on supported hosts.
- **Current source / status / missing states:** ReleaseMyDock.sh; validate.yml; Xcode; UI tests. Source present; earlier coverage disposition: Blocked by environment or tooling. Release script refuses missing full Xcode/metadata; pipeline exists.
- **Dependencies / affected components:** Authorized Developer ID/notary host needed later. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Release outputs/checksums; no publishing performed. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H9 full Xcode, current CI, metadata, signing/notary/Gatekeeper, Intel/macOS13+ acceptance. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: R CLT-only xcodebuild error; ad-hoc/no metadata local artifact. Earlier automated coverage leads: Nine UI methods unrun; CI source inspected, not current CI run. Not rerun here.
- **Remaining gaps / blockers / manual:** H9; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F39 — Application badge labels

- **Primary owner / related IDs:** Native platform; MD-D03 PR-03 PR-11.
- **Entry / intended user outcome:** Settings Behavior Show App Badges; app tiles. Show supported current native badge text, hide empty/zero and bound large labels.
- **Current source / status / missing states:** [DockBadgeService](../../Sources/MyDock/SystemServices/DockBadgeService.swift); Dock controller app tile. Source present; earlier coverage disposition: Implemented but runtime-unverified. AX denied/no readable badge yields empty; grouping by bundle identifier.
- **Dependencies / affected components:** AX/native Apple Dock accessibility reads. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Display setting saved; current badge values transient. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H1/H7 live badge change/zero/large value, Apple Dock restart/hidden mode and denied/revoked AX. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: S/T only; no actual Apple Dock AX badge read acceptance. Earlier automated coverage leads: DockBadgePolicyTests text/cap/mapping; source monitor lifecycle Not rerun here.
- **Remaining gaps / blockers / manual:** H1/H7; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F40 — Folder / website icon customization

- **Primary owner / related IDs:** Product experience; PR-03 PR-07 PR-10.
- **Entry / intended user outcome:** Item inspector; link context icon/site image action. Custom folder name/color/letter/number and safe website symbol/favicon with reliable feedback.
- **Current source / status / missing states:** [DockInspector:75](../../Sources/MyDock/UI/DockInspector.swift:75); [FolderIconView](../../Sources/MyDock/CustomDock/FolderIconView.swift); [AppLauncher](../../Sources/MyDock/SystemServices/AppLauncher.swift); [SiteFaviconFetcher](../../Sources/MyDock/SystemServices/SiteFaviconFetcher.swift); Dock controller link menu. Source present; earlier coverage disposition: Implemented but runtime-unverified. Original/missing icon fallback; unsafe origin/image rejected; long labels need acceptance.
- **Dependencies / affected components:** User target access; requested safe favicon HTTPS; no blanket permissions. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Folder display/icon overrides and link icon/data stored in item; migrations tested. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H6 choose/reset/missing/invalid/oversize icon, names, side targets and clean relaunch. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: S/V item inspector/missing fixtures; native picker/network U. Earlier automated coverage leads: PS:1238/1467/1496/1505; link/path validation Not rerun here.
- **Remaining gaps / blockers / manual:** H6; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

### F41 — Freeze desktop during native Dock switch

- **Primary owner / related IDs:** Native platform; PR-03 PR-19.
- **Entry / intended user outcome:** Settings Dock Setup optional Freeze toggle; native Apply. Optional in-memory display snapshot masks restart; native switching works without capture permission.
- **Current source / status / missing states:** [DockSwitchFreezeProvider](../../Sources/MyDock/DockManagement/DockSwitchFreezeProvider.swift); [NativeDockController](../../Sources/MyDock/DockManagement/NativeDockController.swift); [SettingsView:292](../../Sources/MyDock/UI/SettingsView.swift:292). Source present; earlier coverage disposition: Implemented but runtime-unverified. Requires macOS14+ and preflight capture; failure returns nil; per-session window cleanup source.
- **Dependencies / affected components:** Screen Recording explicit toggle; native mutation only in disposable scenario. Source components above; related PR boundaries govern any change.
- **Persistence / migration / regression:** Enabled setting saved; screenshot overlays stay in memory only, not exported. Preserve IDs/authored state/permissions; related MD/PR migrations apply. Risk: durability, identity or lifetime regression on this workflow.
- **Acceptance criteria:** H7 opt-in denied/granted/revoked, apply/cancel/failure cleanup, capture wait and multidisplay changes. F-CHECK whole-task/error/Cancel/relaunch contract applies.
- **Implementation / work performed:** existing foundation; corrections/extensions unstarted. Work: source/coverage/hash reconciliation.
- **Verification / actual results:** current source corroboration only. Earlier audit evidence: S only; no grant, capture or real native apply. Earlier automated coverage leads: Injected freeze/session native transaction tests; no real screen capture. Not rerun here.
- **Remaining gaps / blockers / manual:** H7; whole-feature/native acceptance open; relevant fixture/environment prerequisites apply.

<a id="widgets"></a>

## Widget ledger — every currently registered family

**W-CHECK shared acceptance** applies explicitly to every W record: discover/add (including another instance where supported), task-first configure, use the primary face/popout action, change, recover and relaunch; every advertised semantic layout/icon choice at bottom/left/right and min/max scale; empty/loading/error/offline/denied/long/large values; light/dark/system, locale, focus/Escape/outside dismissal, keyboard and actual VoiceOver. Preview geometry and labeled examples must be honest; layout and icon treatment remain independent. No unknown limits/history/sensors/totals may be invented. Check per-family stored versus transient lifetime. Render/model checks never pass native operations. For layout payload changes preserve stable family names and old layout/icon mappings; authored content is not a cache.

All W records have Product as workflow primary owner, Reliability as persistence/provider/lifecycle dependency and Native as desktop/native-action dependency. Integration/shared-model writer is coordinator. Source registry/provider name equality is verified; individual user workflows remain unaccepted.

### W01 — Stock

- **Primary owner / related IDs:** Product experience; MD-A04 PR-01 PR-04 PR-15; common PR-08/11/17/20.
- **Intended outcome / entry:** Watch one daily market price/change and inspect chart; configure symbol/range/key, open finance link. Entry: Add Item > Widgets > Stock; Configure; Dock face/popout.
- **Current source / status:** Defective due parser, source-verified UI/native U. Add Business; search ticker/name, range/trading-session labels/refresh/volume, selected display name and quote/detail chart/Finance link `StockWidgetViews.swift:78–168,249–262`; live face uses Local `WidgetPrimitives.swift:333–340`; chart adjustable AX:706–721; layouts108/176 `WidgetPresentation.swift:52`.
- **Change / recovery / persistence:** Change ticker retains correct candidate/saved stale quote; query/result @State, authored ticker/range persisted. Improve symbol/readiness and actual daily-series interval/freshness meaning.
- **Dependencies / components / migration / regression risks:** HTTPS Alpha Vantage; optional API key Keychain; browser opening. R MD-A04 market bounds/PR-15 provenance; native external URL. Preserve selected symbol/currency/name/history cache timestamps; no real-time-trading promise. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Search empty/no result/error/limit/offline stale data, sparse/closed market/currency/long quote, chart keyboard dates/volume, relaunch. Source paths inspected; live key/native chart/browser unrun.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:601/616/626/638/661/1669; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W02 — Watchlist

- **Primary owner / related IDs:** Product experience; MD-A04 PR-01 PR-04 PR-15; common PR-08/11/17/20.
- **Intended outcome / entry:** Compare configured stocks and inspect selected charts; distinct multi-symbol need rather than duplicate single Stock. Entry: Add Item > Widgets > Watchlist; Configure; Dock face/popout.
- **Current source / status:** Defective inherited parser/native U. Business; per-symbol search/selection/name/Move Earlier/Later/Remove and shared range/refresh/volume `StockWidgetViews.swift:334–407,450–540`; face selected or first snapshot `WidgetPrimitives.swift:334`; selected AX trait:464–465;108/176.
- **Change / recovery / persistence:** Ordering and selected symbol durable; partial saved quotes retained. Make navigation/failed-symbol status obvious without table face.
- **Dependencies / components / migration / regression risks:** Same market HTTPS/Keychain. R MD-A04/refresh+partial/provenance; preserve ordered identities and selected item when removing; don't use one quote age for all. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Multiple symbols, partial failures, selected removed, duplicate labels, stale/out-of-order callbacks, keyboard reorder and relaunch. Source-only; no account/browser/native run.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS stock/watchlist settings; partial refresh; DR shared failure; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W03 — Calendar

- **Primary owner / related IDs:** Product experience; PR-08 PR-11 PR-14 OP-04; common PR-08/11/17/20.
- **Intended outcome / entry:** Upcoming/ongoing event at Dock scale; popout list/filter/create provides action; meaningful calendar/date choices. Entry: Add Item > Widgets > Calendar; Configure; Dock face/popout.
- **Current source / status:** Implemented UI, native U. Productivity; choose functional layout/calendars/all-day, next/agenda/date-only, actual-event Join `CalendarRemindersWidgetViews.swift:149–267`; selected calendar controls:180–188; face:28;88/154 `WidgetPresentation:51`. Event-data-derived Join already exists at CalendarRemindersWidgetViews:266–267; OP-04 improves a complete workflow rather than introducing the first Join action.
- **Change / recovery / persistence:** Calendar selections durable, current events transient; explicit refresh/error/system recovery. OP-04 improves next event/time-until, **Join already exists**.
- **Dependencies / components / migration / regression risks:** EventKit Calendar; read/full access OS-specific. Native EventKit/URL; R demand/cancel/timezone; preserve selected native IDs, unavailable calendars and private event content. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Decline/revoke/empty/all-day/ongoing7-day/zone/DST, Join only real link, selected scope/accessible selection and relaunch. No permission/event/Join run.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:535/685; date/range config; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W04 — Reminders

- **Primary owner / related IDs:** Product experience; MD-S03 PR-08 PR-11 PR-14; common PR-08/11/17/20.
- **Intended outcome / entry:** See due/list count and complete/create reminder in popout; complements quick local checklist. Entry: Add Item > Widgets > Reminders; Configure; Dock face/popout.
- **Current source / status:** Implemented UI/partial service acceptance U. Productivity; list/layout/count/next, add/complete/Undo completion `CalendarRemindersWidgetViews.swift:438–548`; completion icon has help but no explicit target-specific AX label:536–537 (source gap for PR-11, actual speech U);88/154.
- **Change / recovery / persistence:** Selected list/layout durable; reminders OS-owned, new title/last undo transient. Keep completion Undo; clarify native versus Checklist; name actions+busy/error state.
- **Dependencies / components / migration / regression risks:** EventKit Reminders. Native EventKit writes; R MD-S03 cancel tokens/demand; do not copy/remap OS tasks silently. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Fixture create/complete/undo concurrent callback/list switch, full/denied/revoked access, no duplicates, native data relaunch; actual mutation unrun.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:535; config backup; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W05 — Now Playing

- **Primary owner / related IDs:** Product experience; MD-S05 PR-11 PR-14; common PR-08/11/17/20.
- **Intended outcome / entry:** Current music/position and transport controls; popout adds source selection/artwork. Entry: Add Item > Widgets > Now Playing; Configure; Dock face/popout.
- **Current source / status:** Implemented/refresh acceptance U. Personal; preferred paused source, enabled Music/Spotify, popover content, previous/next/seek/hide controls `NowPlayingWidgetViews.swift:59–174`; track AX:37; face Media primitives:351;112/186.
- **Change / recovery / persistence:** Choices durable, tracks/artwork/runtime errors transient; subscriptions onAppear/disappear:39–40/173; preserve saved control settings and source auto-selection. Improve target/action/denied recovery.
- **Dependencies / components / migration / regression risks:** Automation per Music/Spotify; external player running. Native Automation per source; R MD-S05 visibility/demand/bounded process; no invented listening history. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Stopped/paused/closed/source-change/unsupported/denied/revoked/hung, seek/start/cancel, keyboard/popout focus and relaunch; no playback action.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:1588/1626/1645; bounded capture tests; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W06 — Weather

- **Primary owner / related IDs:** Product experience; MD-A04 MD-S03 PR-01 PR-04 PR-08 PR-14; common PR-08/11/17/20.
- **Intended outcome / entry:** Glance temperature/condition; popout hourly detail; location/unit setup meaningful. Entry: Add Item > Widgets > Weather; Configure; Dock face/popout.
- **Current source / status:** Defective unsafe numeric path; UI source/native U. Personal; manual city or explicit current location, Change/Cancel/Clear, units/popover content/background/hours `WeatherWidgetViews.swift:84–218,264–282`; per-item process draft from SetupDraftStore; compact:13;92/132/184, forecast.
- **Change / recovery / persistence:** Location/units/cache durable, search pending process-only; request IDs/cancel onDisappear:192. Keep manual no-permission path; explain source/time/units and precision.
- **Dependencies / components / migration / regression risks:** Open-Meteo HTTPS; Location only explicit device location. R MD-A04 numeric domain/MD-S03 timeout+fix freshness/MD-S05 demand; Native Location. Preserve chosen location/zone/unit; cancel cannot replace previous valid location. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus City ambiguity/long names/offline/units/date-zone/day-night/no-fix/stale/denied/revoke/cancel/relaunch. No location/search/native weather accepted.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: R safe workspace face/control context; V configs/faces; no live location request. Earlier test leads: WS; PS:1522/1541; unit/cache tests; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W07 — Focus Timer

- **Primary owner / related IDs:** Product experience; PR-02 PR-08 PR-11 PR-14; common PR-08/11/17/20.
- **Intended outcome / entry:** Run/pause/reset chosen focus interval at Dock scale; popout duration/progress. Entry: Add Item > Widgets > Focus Timer; Configure; Dock face/popout.
- **Current source / status:** Implemented source/runtime U. Productivity; duration then Start/Pause/Reset `WidgetViews.swift:1341–1385`; real remaining/running Local face:300–311;88/124.
- **Change / recovery / persistence:** Duration/run state durable; retain continuous/wall fallback lifecycle. Improve clear completion acknowledgement, optional notifications only as explicit new scope.
- **Dependencies / components / migration / regression risks:** None for timing; any notification only if actually offered/opted in. R timer lifecycle/time boundaries; preserve no current notification-delivery promise and no invented sessions/history. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Start/pause/resume/reset hidden/profile switch/sleep/clock/relaunch,0/long values, primary keyboard action and completion; no timer/native run.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: R safe workspace fixture presence; V timer states; no real timed completion. Earlier test leads: PS:332; RR hidden completion; DR hidden timers; PE bounds; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W08 — Sticky Note

- **Primary owner / related IDs:** Product experience; MD-A05 PR-02 PR-08 PR-16; common PR-08/11/17/20.
- **Intended outcome / entry:** Persistent quick editable note with chosen background; useful reading/editing popout. Entry: Add Item > Widgets > Sticky Note; Configure; Dock face/popout.
- **Current source / status:** Defective MD-A05. Productivity; direct private TextEditor/background `WidgetViews.swift:1389–1444`; AX Note text:1405; face excerpt<=500 chars `WidgetPrimitives.swift:295–299`;120/176 and intentionally no icon picker.
- **Change / recovery / persistence:** Debounced300ms + disappear save; rejected draft acknowledged regardless result. Retain rejected pending text+byte-aware feedback, clear durable state/draft recovery.
- **Dependencies / components / migration / regression risks:** No system permission; private content. R PR-02/A05; PR-16 private history scope. Preserve exact authored text/color, no rich text expansion or default-private-history broadening. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Multibyte limit/reject/disk failure/retry/close/switch/relaunch; note visible/spoken private policy; source-only new check.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:800/857; sanitizer/backup tests; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W09 — Battery

- **Primary owner / related IDs:** Product experience; PR-11 PR-14; common PR-08/11/17/20.
- **Intended outcome / entry:** Device battery percentage/charging; popout device list; honest unavailable device. Entry: Add Item > Widgets > Battery; Configure; Dock face/popout.
- **Current source / status:** Implemented source/native U. System; no service setup, live Mac/accessory power details `WidgetViews.swift:1262–1315`; face charge/shape/name/accessory `WidgetPrimitives.swift:196–229`;90/156.
- **Change / recovery / persistence:** Reading transient; presentation durable. Keep unavailable battery/health/time honest, accessory context only when measured.
- **Dependencies / components / migration / regression risks:** Local IOKit/system data; no new permission prompt. Native IOKit/accessory hardware; R sampler ownership; don't infer time remaining or health. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Desktop without internal battery, charging/full/unknown, accessory appearance/removal/long names, correct units/spoken value, side/relaunch. No hardware transition.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:1025; reader values/bounds; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W10 — Shortcuts

- **Primary owner / related IDs:** Product experience; MD-S01 PR-03 PR-14; common PR-08/11/17/20.
- **Intended outcome / entry:** Run selected local macOS shortcut directly; popout selection meaningful. Entry: Add Item > Widgets > Shortcuts; Configure; Dock face/popout.
- **Current source / status:** Partially implemented execution lifecycle. Productivity; choose stored shortcut, missing name retained, Refresh/Open/Run; catalog progress/errors **and existing run status** `WidgetViews.swift:288–353` especially321–325; icon/88 Local face:345.
- **Change / recovery / persistence:** Name durable; catalog/run state service/session. Add Cancel/deadline/lifecycle and useful failures; don't claim status absent.
- **Dependencies / components / migration / regression risks:** User-selected workflow may request its own permissions/mutate systems. R MD-S01; Native selected safe interactive shortcut; never kill arbitrarily short legitimate prompt or imply execution success before completion. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Safe success/fail/input-wait/hung/cancel/quit, missing catalog selected name, run disabled/busy semantics and keyboard; no Shortcut executed.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:1346; bounded catalog subprocess tests; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W11 — Stripe

- **Primary owner / related IDs:** Product experience; MD-A04 MD-P05 MD-P08 MD-P09 PR-01 PR-04 PR-13 PR-15; common PR-08/11/17/20.
- **Intended outcome / entry:** Glance currency-specific balance/revenue/subscription measures; popout periods/history and account setup. Entry: Add Item > Widgets > Stripe; Configure; Dock face/popout.
- **Current source / status:** Defective provider contract, UI source/live U. Business; account/name/currency/metric/period/color, chart and setup rk_ secure key/process draft `StripeWidgetViews.swift:23–210`; saved stale/error explanation:90–110; face Business:13; default88/124.
- **Change / recovery / persistence:** Connection choices/snapshot durable, secure draft process-only; explicit clear/disconnect; improve metric method/period/account/currency/completeness, don't rename calculated run rate generically.
- **Dependencies / components / migration / regression risks:** Restricted read-only rk_ key; HTTPS Stripe. R MD-A04/P05/P09/PR-04/15; Native/live authorized credential matrix. Stable selected account ID/tenant, old cache semantic version; don't preserve old tenant readings after replacement. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Missing setup/invalid/revoked/rate/offline/partial nested pages/mixed currency/unsupported subscriptions, exact key scopes, relaunch and spoken source; no credential actions.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:1794–1906; RR authority checks; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W12 — Paddle

- **Primary owner / related IDs:** Product experience; MD-A04 MD-P06 MD-P08 MD-P09 PR-01 PR-04 PR-13 PR-15; common PR-08/11/17/20.
- **Intended outcome / entry:** Provider revenue/MRR/subscriber metrics with periods/history; distinguish from Stripe normalization. Entry: Add Item > Widgets > Paddle; Configure; Dock face/popout.
- **Current source / status:** Defective help/numeric paths/live U. Business; account/metric/period/color/show chart, API key draft `PaddleWidgetViews.swift:24–177`; stale saved status:81–95; chart UTC-day AX:218; Business face:14;88/124.
- **Change / recovery / persistence:** Saved choices/cache; draft clear/disconnect; fix scope guidance and preserve provider definitions/server freshness/live-vs-sandbox.
- **Dependencies / components / migration / regression risks:** Paddle Billing API key metrics.read; HTTPS live/sandbox. R MD-P06 metrics.read/MD-A04 bounds/P09 tenant; preserve key references, precise minor units andUTC exclusive period. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Correct setup copy versus backend scopes, test/live, large subscribers/ARR, timezone/freshness/offline/revoke, accessible chart; no live account.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:1917–2012; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W13 — Shopify

- **Primary owner / related IDs:** Product experience; MD-P03 MD-P04 MD-P08 PR-04 PR-13 PR-15; common PR-08/11/17/20.
- **Intended outcome / entry:** Recent store orders/revenue/AOV from real orders; store timezone/period/account settings. Entry: Add Item > Widgets > Shopify; Configure; Dock face/popout.
- **Current source / status:** Defective replace/paging/live U. Business; store/metric/period/chart/color, normalized domain/client ID/secret process draft `ShopifyWidgetViews.swift:24–178`; last-good/error/zone:81–95; product/traffic completeness breakdown:236–268; store-local chart AX:232;88/124.
- **Change / recovery / persistence:** References/query/cache durable; credential replacement must keep same verified tenant and invalidate different tenant; meaningful partial data.
- **Dependencies / components / migration / regression risks:** Installed same-organization Shopify app read_orders/client credentials; HTTPS. R MD-P03/P04/P09; preserve authored store labels/settings/client references and exclude secrets from exports. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Same-store replace/remap/delete race, cursor progress/dedup/partial counts,0 orders AOV, currency/store zone/offline/revoke/relaunch. No live credentials.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:2029–2146; RR delayed credentials; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W14 — Clock

- **Primary owner / related IDs:** Product experience; MD-U03 PR-09 PR-11; common PR-08/11/17/20.
- **Intended outcome / entry:** Readable local time/date using system locale; layout/icon appearance meaningful; popout shows larger time/date. Entry: Add Item > Widgets > Clock; Configure; Dock face/popout.
- **Current source / status:** Defective compact fit. Time; local time/date face `WidgetPrimitives.swift:290–294`, popout bigger time/date `WidgetViews.swift:171–178`;84/112. No separate format/seconds setting found; system locale is input.
- **Change / recovery / persistence:** Only presentation durable; system time live; fix ordinary Compact time fit without shrinking all fonts; Standard working historical preview is not Compact acceptance.
- **Dependencies / components / migration / regression risks:** None. PR-11 width/content bounds; preserve layout/icon legacy; correct side face/date/AM-PM. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus 12/24/seconds/current locale/timezone change/min-scale/side, actual spoken time and relaunch choices; no new bitmap/native check.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: R Standard+Mono selected, preview updated and retained after sheet reopen; V compact clipping. Earlier test leads: PS:578; WP; backup/model defaults; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W15 — World Clock

- **Primary owner / related IDs:** Product experience; PR-11 OP-04; common PR-08/11/17/20.
- **Intended outcome / entry:** Compare chosen timezones/day offsets; popout editable searchable city list. Entry: Add Item > Widgets > World Clock; Configure; Dock face/popout.
- **Current source / status:** Implemented source/native U. Time; local city/time-zone search primary/add/remove comparison `WidgetViews.swift:578–646`; face zone and time `WidgetPrimitives.swift:389–407`;88/164.
- **Change / recovery / persistence:** Zone IDs/order durable, query transient; clear primary/day offset/long names.
- **Dependencies / components / migration / regression risks:** None/network not required for local timezone catalog. R local catalog/formatter; no location/network requirement; preserve primary/additional identity, duplicates guarded. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus DST/opposite-day offset/invalid zone fallback/search0/long name/primary removal/keyboard/spoken zones/relaunch; no native time study.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:555/566/578; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W16 — Stopwatch

- **Primary owner / related IDs:** Product experience; PR-02 PR-11 PR-14; common PR-08/11/17/20.
- **Intended outcome / entry:** Elapsed time with start/pause/reset; no invented sessions/history. Entry: Add Item > Widgets > Stopwatch; Configure; Dock face/popout.
- **Current source / status:** Implemented source/native U. Time; elapsed Start/Pause/Reset `WidgetViews.swift:719–747`; Local state face:300–306;88/124.
- **Change / recovery / persistence:** Continuous boot-scoped time with persisted fallback; no implemented laps/history promised. Optional laps separately scoped.
- **Dependencies / components / migration / regression risks:** None. R StopwatchClock/lifecycle; distinguish wall change/reboot from same-boot continuous; preserve paused elapsed. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Sleep/wake/reboot/wall change/rapid pause/reset/long duration/relaunch/primary keyboard+spoken state; no timer executed.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:408/432/447/457; PE timer bounds; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W17 — Countdown

- **Primary owner / related IDs:** Product experience; PR-02 PR-11 PR-14; common PR-08/11/17/20.
- **Intended outcome / entry:** Count to duration/date, pause/reset and optional finish notification; useful deadline glance. Entry: Add Item > Widgets > Countdown; Configure; Dock face/popout.
- **Current source / status:** Implemented source/native U. Time; duration or target DatePicker, Start/Pause/Reset/Set/Clear, scheduling/error messages `WidgetViews.swift:763–883`;88/124. **Start duration schedules a notification directly**:817–838; target copy explicitly:881; no independent notification enable toggle found in this view.
- **Change / recovery / persistence:** Duration/target/running state durable; target draft transient. Clarify armed local timer vs OS notification acceptance; do not say a separate opt-in toggle currently exists.
- **Dependencies / components / migration / regression risks:** Notifications only if explicitly enabled. R notification/lifecycle generations; Native permission/delivery; migration resets imported runtime correctly. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Deny/revoke/past date/target changes/hidden closed sleep DST relaunch, stale schedule/item delete, accessible target+state. No notification request.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:376/401/510/944/961; RR:61; PE:81; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W18 — Alarm

- **Primary owner / related IDs:** Product experience; PR-02 PR-08 PR-11 PR-14; common PR-08/11/17/20.
- **Intended outcome / entry:** Next enabled local alarm; popout create/repeat/enable/remove list. Existing-alarm editing UI was not found and is an optional scope decision. Entry: Add Item > Widgets > Alarm; Configure; Dock face/popout.
- **Current source / status:** Implemented create/repeat/enable/remove; existing-edit UI absent; native U. Time; DatePicker/name/weekdays23pt named+selected/add/no alarms, rows Enabled/remove `AlarmWidgetViews.swift:40–117`; compact next alarm:13; default88/124. Coverage create/edit wording is narrowed to inspected controls.
- **Change / recovery / persistence:** Alarm list durable, compose form transient; existing alarm edit was asserted in coverage but not found. Proposal: explicit edit workflow and clearer next-fire/repeat/armed/denied status after scheduling correctness.
- **Dependencies / components / migration / regression risks:** Notifications explicit enable. R AlarmNotificationService startup reconcile; Native notification; retained IDs/weekdays/titles and default import disabled; no duplicate schedules. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Notification deny/revoke/DST/one-shot/sleep/relaunch/pending mismatch/create remove, UI edit only if implemented, weekday keyboard targets+spoken names; no OS schedule.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:695/719/759/775; generation tests; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W19 — Time Progress

- **Primary owner / related IDs:** Product experience; PR-11; common PR-08/11/17/20.
- **Intended outcome / entry:** Understand remaining day/week/month/year; useful progress proportion with honest local boundaries. Entry: Add Item > Widgets > Time Progress; Configure; Dock face/popout.
- **Current source / status:** Implemented source/native U. Time; period picker and live percent/progress `WidgetViews.swift:1004–1027`, face named period/bar/date `WidgetPrimitives.swift:312–318`; default88/124; intentionally no icon control.
- **Change / recovery / persistence:** Period persisted, fraction local live. Explain elapsed/current calendar boundaries; don't invent targets/history.
- **Dependencies / components / migration / regression risks:** None. R TimeProgressCalculator/Calendar DST; retain period raw values and percentage semantics. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Day/week/month/year/leap/DST/locale first weekday/timezone,0/100 endpoints/side/name+value/relaunch; no runtime boundary run.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:472 DST; model migration; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W20 — Hydration

- **Primary owner / related IDs:** Product experience; MD-S04 PR-02 PR-11 PR-14; common PR-08/11/17/20.
- **Intended outcome / entry:** Track actual drinks/known volume with undo/history; optional reminders; popout logging meaningful. Entry: Add Item > Widgets > Hydration; Configure; Dock face/popout.
- **Current source / status:** Partial startup reconciliation (strong inference), UI source/native U. Personal; actual drinks/volume, I drank water vs Log water, history/amounts/reminders/interval, notification recovery, existing removal **Undo** `WidgetViews.swift:1078–1159`; face count/volume:319–324;88/124.
- **Change / recovery / persistence:** History/default amount/flags durable, reminder permission OS separate; keep unknown amount distinct. Improve startup enabled-vs-pending explanation after R reconciliation.
- **Dependencies / components / migration / regression risks:** Notifications if enabled; no health permission/data source. R MD-S04/HydrationNotification lifecycle; Native notification; no medical target/intake claim; preserve records and unknown values, one-entry Undo. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Midnight/zone/wake/reminder reset/history off existing entries/unknown amount/remove undo/pending mismatch/revoke/relaunch. No drink/notification mutation.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:465/979/1010; validator; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W21 — System Activity

- **Primary owner / related IDs:** Product experience; MD-S05 PR-11 PR-13 PR-14 PR-18 OP-07; common PR-08/11/17/20.
- **Intended outcome / entry:** Actual CPU/memory/swap/load/thermal/per-core/storage; popout details and bounded real CPU microhistory. Entry: Add Item > Widgets > System Activity; Configure; Dock face/popout.
- **Current source / status:** Partial scheduler demand acceptance, source UI. System; actual CPU/memory/core/swap/load/thermal/storage detail, refresh/storage choose/cancel scan `SystemActivityWidgetViews.swift:229–345`; CPU AX value:223–225;86/92/158 and trend secondary `WidgetAppearance.swift:101–105`. visiblePopouts override exists; periodic scheduler still requires Dock-visible. Preserve the existing demand path while repairing scheduler ownership.
- **Change / recovery / persistence:** Configuration durable; bounded CPU readings/history transient. visiblePopouts override already exists in SystemActivityWidgetViews.swift:71,98; periodic stream still global RefreshScheduler gate:49/60. Improve interpretive units and absent-demand behavior; don't say no popout demand.
- **Dependencies / components / migration / regression risks:** Local system APIs; explicit storage scan uses file access. R MD-S05/coherent sample/cache; Native real sampling/volume; OP-07 optional detail reuse. Preserve measured unavailable states; no fabricated sensor temperature. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Hidden Dock+editor/popout visible, cores/thermal absent/CPU compare/bounded actual history/scan cancel/slow volume and Release energy; no profiling/sample run.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:1040/1047/1061/1072/1102/1116; WP bounded history; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W22 — Network Activity

- **Primary owner / related IDs:** Product experience; MD-P07 MD-S05 PR-04 PR-11 PR-14 PR-18 OP-07; common PR-08/11/17/20.
- **Intended outcome / entry:** Current receive/send rates and interfaces; popout addresses/history; metrics dominate icon. Entry: Add Item > Widgets > Network Activity; Configure; Dock face/popout.
- **Current source / status:** Defective counter reset. System; actual download/upload/interfaces/address/history detail `NetworkActivityWidgetViews.swift:117–173`; paired rate face `WidgetPrimitives.swift:158–181`;100/170.
- **Change / recovery / persistence:** Config durable/readings transient; R reset/rebaseline fixes false spike; Product units/interface/receive-transmit and stale unavailable clarity.
- **Dependencies / components / migration / regression risks:** Local interface counters; no packet inspection permission. R MD-P07/MD-S05 demand; preserve64-bit actual counters/identity, don't fabricate total traffic or wrap every reset. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Hotplug/reset/sleep/wake/new interface/known fixture traffic, units/large rates/side/spoken rates; no live traffic measurement.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:1122; WP bounded telemetry; source-slice reset; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W23 — AI Limits

- **Primary owner / related IDs:** Product experience; MD-A03 PR-01 PR-04 PR-15; common PR-08/11/17/20.
- **Intended outcome / entry:** Provider-reported usage windows/freshness, not estimated token-budget conversion; choose supported providers. Entry: Add Item > Widgets > AI Limits; Configure; Dock face/popout.
- **Current source / status:** Defective extreme cache, UI source/live U. AI; provider/window/layout/representation/Dock provider/show/manual Copilot allowance setup/refresh `AIUsageWidgetViews.swift:51–151`; provider unsupported/missing status and bridge copy:202; compact:23;default88/124.
- **Change / recovery / persistence:** Provider choice/order/manual allowance/snapshot durable; secrets outside profile. Label reported windows versus local activity and optional manual allowance exactly; unavailable ≠0.
- **Dependencies / components / migration / regression risks:** Existing authorized local accounts or explicit optional token/bridge; no account used here. R MD-A03/PR-01+15 provider limits identity/bridge; Native authorized account/permission; no quota inferred from tokens. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Missing bridge/auth/API-key-only unsupported plans/extreme percent/expired/offline/multiple buckets/credits/window reset, spoken percent/type/freshness/relaunch; no account read.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:2157–2265/2378; AA; CP; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W24 — AI Activity

- **Primary owner / related IDs:** Product experience; MD-P01 MD-P02 MD-P10 PR-04 PR-13 PR-15; common PR-08/11/17/20.
- **Intended outcome / entry:** Local tokens/sessions/tools over known range with provenance; popout chart/details; distinct from Limits. Entry: Add Item > Widgets > AI Activity; Configure; Dock face/popout.
- **Current source / status:** Defective duplicate/path/session semantics. AI; compact provider/total/secondary AX `AIUsageWidgetViews.swift:326–360`; popout provider/range/chart/status/single recovery `:387–585`;88/126/184, actual bounded sparkline.
- **Change / recovery / persistence:** Provider/range/secondary+cache durable, readings provenance local; R dedup/custom root/session-day correction invalidates semantic cache. Preserve distinction from billing/limits and unsupported empty state.
- **Dependencies / components / migration / regression risks:** Local logs only within configured provider paths; no transcript retained by aggregate. R MD-P01/P02/P10+PR-15; privacy local aggregates no transcript; source identity/range wording; no real user logs inspected. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Copied/resumed/midnight/DST/truncated/missing/custom root/partial+estimated, empty/offline/freshness, spoken chart/totals, relaunch; no native account logs.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:2284–2421; source-slice duplicate data; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W25 — AirDrop

- **Primary owner / related IDs:** Product experience; MD-Q02 PR-03 PR-10 PR-17; common PR-08/11/17/20.
- **Intended outcome / entry:** Select fixture file/link and open native sharing recipient flow; useful transfer entry point. Entry: Add Item > Widgets > AirDrop; Configure; Dock face/popout.
- **Current source / status:** Source dispatch discrepancy, popout implemented/native U. System; icon/88 **actual face Local bypass** `WidgetViews.swift:87–88` → generic face `WidgetPrimitives.swift:343–346`; provider-specific face onDrop/help/AX `AirDropWidgetViews.swift:40–43` is bypassed. Popout selected files/links/drop/share `:144–154`. Supplemental source gap: live compact route bypasses AirDropCompactTile onDrop/help/AX. Popout intake remains; native face drop must be fixed or explicitly scoped before advertising it.
- **Change / recovery / persistence:** Selection/link draft transient, only presentation stored; native handoff ≠ delivery. Trace outer Dock drop before asserting face-drop support; restore provider action surface if intended.
- **Dependencies / components / migration / regression risks:** Native sharing/AirDrop; sending requires explicit receiver authorization. Native owner H6/pasteboard/share/receiver; R bounded dropped loader as needed; no auto-transfer or invented recipients/delivery. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Actual face versus popout drag/start picker, chosen fixture content/cancel/invalid link/promises/multifile ordering/AX; authorized receiver required for transfer; nothing sent.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:1566 link validation; source native sharing contract; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W26 — Trash

- **Primary owner / related IDs:** Product experience; MD-D06 PR-03 PR-10 PR-11 PR-17; common PR-08/11/17/20.
- **Intended outcome / entry:** Inspect home Trash and open Finder; deliberate confirm before empty. Entry: Add Item > Widgets > Trash; Configure; Dock face/popout.
- **Current source / status:** Partial scope; generic face bypass source. System; actual face Local bypass WidgetViews:87–88, so provider count/error/empty face `TrashWidgetViews.swift:13–25` not reached there; popout home-folder scope:42, Open/confirmed Empty:54–79;icon/88. Supplemental source gap: live generic face bypasses TrashCompactWidgetView count/empty/error observation; popout remains. A useful count face is a product/design choice; destructive scope is MD-D06 inference.
- **Change / recovery / persistence:** OS Trash not saved collection. Align Finder-wide destructive wording with home count after native scope acceptance; optional dynamic face glance consistent with service.
- **Dependencies / components / migration / regression risks:** Finder Automation only on Empty; no destructive call run. Native MD-D06/Finder Automation/disposable volume; R Trash watcher; no destructive cleaner/force removal or invented global count. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Sacrificial multi-volume/home/empty/error/cancel/Automation denial/partial failure, actual scope/spoken confirmation; no Trash open/empty.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: PS:1575 counts fixtures; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W27 — Disk Space

- **Primary owner / related IDs:** Product experience; PR-11 PR-14 OP-07; common PR-08/11/17/20.
- **Intended outcome / entry:** Free/startup disk capacity glance; popout capacity details/Refresh; complements deeper System Activity scan. Entry: Add Item > Widgets > Disk Space; Configure; Dock face/popout.
- **Current source / status:** Implemented source/runtime U. System; free/capacity/bar/location/no reading/Refresh `UtilityWidgetViews.swift:24–65`;104/158. Copy says updates each minute while open but stream global scheduler gate:56 dependency.
- **Change / recovery / persistence:** Configuration durable, capacity transient. Honest location/age/unavailable and demand; no cleanup promised.
- **Dependencies / components / migration / regression risks:** Local filesystem resource values. R RefreshScheduler global hidden gate; Native actual volume readings; preserve byte formatter fraction bound. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Startup volume/unavailable/low space/huge units/hidden editor/popout/manual refresh/side/spoken free-total/clean relaunch; no disk mutation/profiling.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: WU disk fraction; DE registry; PS system storage; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W28 — Calculator

- **Primary owner / related IDs:** Product experience; PR-02 PR-08 PR-11; common PR-08/11/17/20.
- **Intended outcome / entry:** Quick arithmetic with result/copy; popout expression input; no need for invented saved history. Entry: Add Item > Widgets > Calculator; Configure; Dock face/popout.
- **Current source / status:** Implemented source, session transient/native U. Everyday Tools; expression256 chars, result/copy, keyboard/keypad/error, three-entry **This session** history `UtilityWidgetViews.swift:76–122`;icon/88 generic face.
- **Change / recovery / persistence:** Expression/history @State intentionally transient, presentation durable. Define dismissal/session lifetime, meaningful error/copy feedback; locale keyboard distinction.
- **Dependencies / components / migration / regression risks:** Clipboard on explicit copy only. R QuickCalculator finite/parser tests; Native clipboard; no saved history claim, copy displays formatted precision. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Precedence/unary/parentheses/percent/div0/overflow/invalid/locale/result exact copy, keyboard and reopen/relaunch expectation; no clipboard operation.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: WU precedence/percent/invalid/bounds; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W29 — Quick Checklist

- **Primary owner / related IDs:** Product experience; MD-A07 MD-U03 PR-02 PR-11 PR-16; common PR-08/11/17/20.
- **Intended outcome / entry:** Private lightweight tasks at Dock scale; add/toggle/remove local rows, distinct from EventKit reminders. Entry: Add Item > Widgets > Quick Checklist; Configure; Dock face/popout.
- **Current source / status:** Defective removal/no undo+compact fit. Everyday Tools; task add/toggle/direct title edit/remove/Clear Completed/empty/full `UtilityWidgetViews.swift:150–204`; labelled toggle/remove:183/188; actual face Local `WidgetPrimitives.swift:327–332` (old provider count view bypassed),88/154.
- **Change / recovery / persistence:** Local entries/complete durable; pending new text transient; private default history excludes. Add bounded undo/draft-safe add and primary metric fit.
- **Dependencies / components / migration / regression risks:** None; private text. R PR-02/A07; PR-11/U03; preserve100-entry IDs/title/completion, distinct from EventKit tasks. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus 0/1/100/task lengths/multibyte/edit/remove/clear/undo/failed save/close pending/relaunch, min/side/keyboard/spoken count; no mutation.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: WU private sanitizer; DE/PS config persistence; validator; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W30 — File Shelf

- **Primary owner / related IDs:** Product experience; MD-A07 MD-D05 PR-02 PR-10 PR-16 OP-03; common PR-08/11/17/20.
- **Intended outcome / entry:** Keep temporary working-file references without moving originals; open/reveal/share/copy/drag popout. Entry: Add Item > Widgets > File Shelf; Configure; Dock face/popout.
- **Current source / status:** Defective no repair/undo; native U. Everyday Tools; provider retains Dock and popout file drop `DockUtilityWidgetViews.swift:37–64`, Add Files/Copy All/Share/Clear:85–103, row open/reveal/copy/remove/drag:106–143; count+latest AX:33;96/164.
- **Change / recovery / persistence:** Saved deduped bookmarks/references, not copies; missing disables Open/Copy and no Locate:113–123. Add Locate/retry/bookmark renewal, bounded remove/clear undo and truthful acceptance/count failures.
- **Dependencies / components / migration / regression risks:** User-selected files/pasteboard/native share; bookmarks are minimal in unsandboxed app. Native MD-D05/H6; R file policy/persistence, PR-02/16; preserve original files/title/entry identity; disconnected ≠ deleted; no sandbox claim. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Duplicates/capacity/rename/move/eject/reconnect/repair/share cancel/Finder copy+drag promises/relaunch, exact original unchanged; no file/clipboard/share actions.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: DE dedup/cap/remote rejection/store recreation/sanitizer; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W31 — Text Snippets

- **Primary owner / related IDs:** Product experience; MD-A06 MD-A07 PR-02 PR-08 PR-16 OP-03; common PR-08/11/17/20.
- **Intended outcome / entry:** Reuse selected text with explicit copy, edit/remove; popout library and meaningful labels. Entry: Add Item > Widgets > Text Snippets; Configure; Dock face/popout.
- **Current source / status:** Defective drafts/undo. Everyday Tools; @State new/edit title/body, explicit Use Clipboard, save/copy/edit/remove/empty/full `DockUtilityWidgetViews.swift:156–215`; text AX:168–170, action names:191–192;96/164.
- **Change / recovery / persistence:** Saved50 entries/body10k chars durable, new/edit draft transient and Escape loses; unconditional reset after void update. Add retained private draft/result/local undo; search optional (no current snippet search field).
- **Dependencies / components / migration / regression risks:** Explicit clipboard writes only; no passive clipboard history. R PR-02/A06/A07; PR-16 history excludes default; preserve exact text/UUIDs/title, no passive clipboard. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Saved/edit/new rejected, Escape/outside/switch/deletion/relaunch, exact clipboard/Unicode/capacity/undo intervening edit; source checked, only historical Save/Escape runtime.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: R Add/Save/row actions; pending input Escape→blank reopen; no Copy/Remove used. Earlier test leads: DE legacy/limits/sanitizer/store recreation/edit; validator; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W32 — Quick Links

- **Primary owner / related IDs:** Product experience; MD-A06 MD-A07 PR-02 PR-08 PR-16 OP-03; common PR-08/11/17/20.
- **Intended outcome / entry:** Organize useful web links with open/copy/edit/remove; complements one pinned website tile. Entry: Add Item > Widgets > Quick Links; Configure; Dock face/popout.
- **Current source / status:** Defective drafts/undo. Everyday Tools; title/address/clipboard/save, HTTP(S)/duplicate errors, existing search/open/copy/edit/remove `DockUtilityWidgetViews.swift:218–287`; AX232/245/261–264;96/164.
- **Change / recovery / persistence:** Saved50 bounded URLs durable; title/address/query transient; failed URL retains input but dismiss loses. Add draft/result/undo consistency; keep explicit URL errors and browser feedback.
- **Dependencies / components / migration / regression risks:** Browser/explicit clipboard; requested favicon network only if configured. R PR-02/validation; Native browser/clipboard; preserve allowed schemes and URL/title IDs/private default omission. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Invalid scheme/oversize/duplicates/hostless/offline/favicon optional/long title/search0/edit/copy/undo/relaunch; no URL opened.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: DE malformed collections/persistence/sanitizer; PS safe URL; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W33 — Unit Converter

- **Primary owner / related IDs:** Product experience; PR-08 PR-11; common PR-08/11/17/20.
- **Intended outcome / entry:** Convert supported dimensions including temperature offsets and decimal/binary data; obvious input/unit controls. Entry: Add Item > Widgets > Unit Converter; Configure; Dock face/popout.
- **Current source / status:** Implemented source, precision reviewer judgment/native U. Everyday Tools; category/value/From/To/swap, live offset conversion/result/copy, decimal separator, US volume and decimal/binary notes `DockUtilityWidgetViews.swift:311–355`; AX330/335;icon/104.
- **Change / recovery / persistence:** Input/category/unit selection session @State, presentation durable.12 significant digits currently:326; improve practical glance precision and optionally copy/detail policy, state transient lifetime.
- **Dependencies / components / migration / regression risks:** Explicit clipboard only; no external rates or money conversion claim. R conversion unit/parser finite; Native clipboard; preserve dimensions/offsets/decimal-vs-binary, no FX/live-rate promise. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Advertised every unit pair/C↔F↔K negative/large invalid/locale/swap/rounding-copy, input session dismissal/relaunch, keyboard units; no clipboard/conversion UI run.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: DE:92 offsets/decimal-binary; bounds/parser; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W34 — Color Picker

- **Primary owner / related IDs:** Product experience; PR-08 PR-11; common PR-08/11/17/20.
- **Intended outcome / entry:** Choose/sample hex color, keep palette and copy format; useful local creative tool. Entry: Add Item > Widgets > Color Picker; Configure; Dock face/popout.
- **Current source / status:** Implemented source, privacy/UX/native U. Everyday Tools; native ColorPicker/explicit screen sampler, HEX Apply/Copy HEX/RGB, saved24 unique palette/context remove `DockUtilityWidgetViews.swift:363–444`; selected color AX:396, named swatches:423 **no selected trait**;icon/104.
- **Change / recovery / persistence:** Palette durable; selected color/hex/message/sampling transient, onAppear picks first palette:434. Clarify Apply versus Save Color and selected state, cancellation; local palette undo proposal alongside A07 is extension, not original finding.
- **Dependencies / components / migration / regression risks:** NSColorSampler native; explicit clipboard; no permission granted here. Native NSColorSampler/clipboard, R hex/palette bounds; preserve sRGB/no-alpha policy and dedup strings; no inferred Screen Recording grant requirement without native evidence. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus HEX3/6 invalid/alpha policy/palette24/dedup/save remove/sample pick/cancel/deny if applicable/exact copy/relaunch, selected spoken; no sampler/clipboard.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V shared sample face; S configuration/popout; T contracts; no live Dock action. Earlier test leads: DE:113 shorthand/invalid; validator palette24/dedup; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

### W35 — App Folder

- **Primary owner / related IDs:** Product experience; MD-D03 MD-Q02 PR-03 PR-10 PR-17; common PR-08/11/17/20.
- **Intended outcome / entry:** Group selected installed applications; popout Add Apps via NSOpenPanel, Reorder, Replace and Remove; actual launch/repair requires native acceptance. Entry: Add Item > Widgets > App Folder; Configure; Dock face/popout.
- **Current source / status:** Implemented curated collection, native U/QA gap. Productivity; name/letters/color/Add Apps/Reorder/up/down/missing Replace/remove/open `WidgetViews.swift:394–482`; colors tooltip-only:421; reorder icon arrows no explicit AX names:457–463; actual Local icon/name:345;icon/88. **No embedded app search field found**, NSOpenPanel picks apps. Do not claim an embedded App Folder installed-app search field.
- **Change / recovery / persistence:** Curated selected app references/order durable, reorder/message transient; distinguish from filesystem folder reader. Improve named selected swatches/move/remove, launch result, copy identity; include all QA.
- **Dependencies / components / migration / regression risks:** Workspace launching; local installed-app reads. Native launch/path copies, R identity/validation; preserve app UUID/order/name/custom letters/color; no silently migrated family or launching wrong copy. Stable family/layout/icon legacy contract and linked MD/PR migrations apply.
- **Acceptance criteria:** W-CHECK plus Missing/moved/multiple installed copies, add/remove/reorder exact path/failed open/relaunch/AX; adaptive loop stops before family35. No app launched.
- **Implementation / work performed:** existing code with stated gaps; proposed fixes/refinements unstarted. Work: current family/dispatch/workflow inspection and inventory reconciliation.
- **Verification / actual results:** source-only. Earlier audit: V default catalog sample; no adaptive semantic page for this family; actual launch U. Earlier test leads: PS:1326/1448; IA validation; generic layouts; WP layout/icon migration/bounds; PR drawable symbol Not rerun.
- **Remaining gaps / blockers / manual:** H5 all-family layout/focus/VoiceOver; H6 utility actions; H7 native permission/lifecycle; H8 data/failure/storage, as relevant; H1 App Folder identity; H2 actual telemetry/desktop cost. Isolated scenario prerequisites first; native/live accounts not exercised.

<a id="manual"></a>

## Native/manual acceptance ledger — H1–H9, all original 35 procedures plus 5 supplemental procedures

These are required open acceptance procedures, not actions performed. Each group is a complete record; every numbered subprocedure must have an actual result before the group closes. Use the separately authorized disposable account/VM and fixtures where preferences/permissions/destruction are involved. Clipboard/share/send/sample/native mutation is not authorized merely by this plan. No production-data corruption or credentials are used. The same build/artifact and environment must be named in results.

### H1 — Close Window, Quit App and identity

- **Primary owner / related IDs:** Native platform; MD-D01 MD-D02 MD-D03 PR-03 PR-10.
- **Current source / status:** [AppLauncher:38](../../Sources/MyDock/SystemServices/AppLauncher.swift:38); [WindowAccessibilityService:64](../../Sources/MyDock/SystemServices/WindowAccessibilityService.swift:64); [CustomDockWindowController:1491](../../Sources/MyDock/DockManagement/CustomDockWindowController.swift:1491); existing code/harnesses are partial foundations only; all procedures below open.
- **Intended user outcome:** dependable close window, quit app and identity on the actual accepted artifact, including failure, interruption and recovery.
- **Dependencies / affected components / regression risks:** AX access only in separately authorized disposable user; two sacrificial unsaved documents; two fixture app copies. Wrong-process/window actions, stale identities and cancelled requests.
- **Migration requirements:** no mutation performed by this ledger; associated package migrations/identity/cache/retention policies must be accepted before procedure execution. Preserve original fixture bytes/keys and rollback evidence.
- **Implementation / work performed:** manual plan reconciled; underlying corrective packages unstarted, existing harness/code not counted as native acceptance.
- **Verification / actual results:** not executed in this phase; no pass, performance number or native outcome inferred.
- **Remaining blockers / procedure:** fixture isolation and explicit scenario authorization first. H9 also lacks full Xcode/release identities/supported-host execution; live-account scenarios require dedicated authorized test accounts. Perform every acceptance criterion below, record actual outcomes/failures/skips against artifact/environment, then reopen linked findings if behavior contradicts source.

1. In the disposable account, activate the fixture Dock, first with Show Minimized Windows and Click Focused App to Minimize **off**. Open TextEdit with two different unsaved documents and grant only the intended AX permission. Right-click its tile. Record whether Windows and Close Window exist under defaults.
2. Choose one document via Windows; minimize it through the app and restore via MyDock. Confirm the same document, not just application activation. Close that document through MyDock; choose Cancel in the unsaved dialog. It must remain open and the app stay running. Repeat with Save/Don't Save using sacrificial text and inspect only the target document.
3. Choose Quit TextEdit; cancel the unsaved request. All relevant windows/application must remain; the running representation must persist. Then allow a normal Quit. Close Window must never force application termination. Repeat with multiple windows, an untitled/no-AX-identifier test window and changed titles.
4. Close/reopen a window while its menu/descriptor is stale; an action must refresh/fail clearly rather than target another. Test two disposable app copies sharing bundle ID and PID changes after restart. Test Finder separately: normal Finder lifecycle may differ from a regular document app; document any intentional platform limitation.
5. Without AX/revoke AX, repeat the menu inspection. Unrelated app launching/files/widgets must work; show precise setup/recovery without repeated prompts. Verify Keep in Dock/Remove, pinned/running representations and selected executable path after relaunch.
6. Observe live badge changes (empty/zero/large/text), Apple Dock restart/hidden mode and AX denial/revocation; pinned/running copy identity and badge attribution must remain correct. Actual badge reading is not accepted by label-policy tests.

### H2 — Resizing, display changes and performance

- **Primary owner / related IDs:** Native platform; MD-U05 MD-E01 MD-E02 PR-09 PR-11 PR-18.
- **Current source / status:** [CustomDockWindowController:1171](../../Sources/MyDock/DockManagement/CustomDockWindowController.swift:1171); [ProfileStore:275](../../Sources/MyDock/Persistence/ProfileStore.swift:275); [RevisionedStateWriter:29](../../Sources/MyDock/Persistence/RevisionedStateWriter.swift:29); [DockRenderModel](../../Sources/MyDock/Models/DockRenderModel.swift); existing code/harnesses are partial foundations only; all procedures below open.
- **Intended user outcome:** dependable resizing, display changes and performance on the actual accepted artifact, including failure, interruption and recovery.
- **Dependencies / affected components / regression risks:** Release fixtures, actual refresh/scale recorded, Instruments/video/write traces and additional displays. Misanchoring, gesture interruption, focus/overflow regressions and per-event writes.
- **Migration requirements:** no mutation performed by this ledger; associated package migrations/identity/cache/retention policies must be accepted before procedure execution. Preserve original fixture bytes/keys and rollback evidence.
- **Implementation / work performed:** manual plan reconciled; underlying corrective packages unstarted, existing harness/code not counted as native acceptance.
- **Verification / actual results:** not executed in this phase; no pass, performance number or native outcome inferred.
- **Remaining blockers / procedure:** fixture isolation and explicit scenario authorization first. H9 also lacks full Xcode/release identities/supported-host execution; live-account scenarios require dedicated authorized test accounts. Perform every acceptance criterion below, record actual outcomes/failures/skips against artifact/environment, then reopen linked findings if behavior contradicts source.

1. Use a Release fixture profile with a short mixture, then a long 30/60-widget mixture including repeated widgets, wide metrics, groups/separators. Record hardware/OS/build/display logical size/backing scale/**actual selected refresh mode**. Turn magnification off, then repeat with it on. Capture baseline visible, hidden and idle CPU/RSS/network/write activity for a stated duration.
2. For bottom, left and right, drag the grip continuously between minimum and maximum for at least 30 seconds. Observe cursor tracking, acquisition, screen-edge anchoring, tile relayout, overflow controls, scroll position and whether the gesture remains active. Record screen video and Instruments main-thread/animation or signpost trace in the isolated account. Measure frame intervals and event-to-presentation using a stated method; report percentile/dropped-frame distributions relative to 60/120 Hz as actually configured, not inferred geometry cost.
3. Observe temporary state-file/history writes during the drag; pointer changes should not each cause writes. Verify exactly bounded completion commits/flush and correct global versus existing profile override. Instrument root assignments and monitor starts/stops separately; changes unrelated to appearance should not restart live work.
4. Release, double-click reset, AX increment/decrement/reset, interrupt by Escape, profile switch, hiding, window/app deactivation and display disconnect. Document whether cancellation retains or restores the last value. Check clean quit/relaunch preserves accepted size and inheritance. Watch CPU/RSS during drag and after settling; repeat only enough to assess growth, not one instant sample.
5. Connect a second display, select it, remove it during a drag/reveal, and test different scale/refresh modes and Spaces/fullscreen. Record fallback screen and handle reachability. Test overflow keyboard/arrow/wheel navigation and smallest target near neighboring tiles.

### H3 — Glass, opacity and rounded corners on wallpaper

- **Primary owner / related IDs:** Native platform; MD-U06 PR-09 PR-11 PR-12 PR-19.
- **Current source / status:** [DockMaterialSurface](../../Sources/MyDock/CustomDock/DockMaterialSurface.swift); [ProfileAppearance](../../Sources/MyDock/Models/ProfileAppearance.swift); [CustomDockWindowController](../../Sources/MyDock/DockManagement/CustomDockWindowController.swift); existing code/harnesses are partial foundations only; all procedures below open.
- **Intended user outcome:** dependable glass, opacity and rounded corners on wallpaper on the actual accepted artifact, including failure, interruption and recovery.
- **Dependencies / affected components / regression risks:** Separately authorized disposable desktop, bright/dark wallpapers and older supported OS hosts. Readability/opacity meaning, halos and scope migration.
- **Migration requirements:** no mutation performed by this ledger; associated package migrations/identity/cache/retention policies must be accepted before procedure execution. Preserve original fixture bytes/keys and rollback evidence.
- **Implementation / work performed:** manual plan reconciled; underlying corrective packages unstarted, existing harness/code not counted as native acceptance.
- **Verification / actual results:** not executed in this phase; no pass, performance number or native outcome inferred.
- **Remaining blockers / procedure:** fixture isolation and explicit scenario authorization first. H9 also lacks full Xcode/release identities/supported-host execution; live-account scenarios require dedicated authorized test accounts. Perform every acceptance criterion below, record actual outcomes/failures/skips against artifact/environment, then reopen linked findings if behavior contradicts source.

1. Activate the actual fixture Dock over a bright detailed wallpaper and a dark detailed wallpaper. For Clear and Frosted, test opacity 0/25/50/75/100 and several intermediate points, with tint 0 and a nonzero tint separately. Change light/dark/system theme and global/profile scope. Compare settings preview with the real surface; sample values must stay labeled.
2. At “Opaque,” verify wallpaper cannot affect the backing in a way contradicting the label; at lower values verify a continuous change and distinguish opacity from tint. Inspect all four rounded corners and outer shadow area against high-contrast wallpaper for rectangular halos. A PNG corner-alpha test alone does not pass this step.
3. Resize, reveal/hide and switch profiles while inspecting edges/backdrop. Toggle Reduce Transparency and increased contrast in the disposable user's settings; verify readable opaque fallback and meaningful border, then restore them. On macOS 13/14/15 verify older-material fallback and no missing API path. Record native screenshots/video with permission explicitly authorized for that environment.

### H4 — Motion and interrupted transitions

- **Primary owner / related IDs:** Native platform; MD-E02 PR-10 PR-12 PR-18.
- **Current source / status:** [CustomDockWindowController:612](../../Sources/MyDock/DockManagement/CustomDockWindowController.swift:612); [DockModels](../../Sources/MyDock/Models/DockModels.swift); [SettingsView](../../Sources/MyDock/UI/SettingsView.swift); existing code/harnesses are partial foundations only; all procedures below open.
- **Intended user outcome:** dependable motion and interrupted transitions on the actual accepted artifact, including failure, interruption and recovery.
- **Dependencies / affected components / regression risks:** Real activated fixture panel; Reduce Motion changes confined to disposable user. Stale alpha/offset/scale, hit regions, focus and obsolete completion.
- **Migration requirements:** no mutation performed by this ledger; associated package migrations/identity/cache/retention policies must be accepted before procedure execution. Preserve original fixture bytes/keys and rollback evidence.
- **Implementation / work performed:** manual plan reconciled; underlying corrective packages unstarted, existing harness/code not counted as native acceptance.
- **Verification / actual results:** not executed in this phase; no pass, performance number or native outcome inferred.
- **Remaining blockers / procedure:** fixture isolation and explicit scenario authorization first. H9 also lacks full Xcode/release identities/supported-host execution; live-account scenarios require dedicated authorized test accounts. Perform every acceptance criterion below, record actual outcomes/failures/skips against artifact/environment, then reopen linked findings if behavior contradicts source.

1. Test initial activation, reveal/dismiss and profile switching for Fade, Slide and Gentle Grow. Select Off and confirm all relevant transitions and previews respect it; repeat under Reduce Motion. Settings selection/persistence is only the first step.
2. Reverse hide/reveal rapidly, click Preview repeatedly, change styles during a transition, then switch Off mid-transition. Resize/magnify/switch profile while active. No stale scale/offset/alpha, delayed hide completion or revived obsolete Dock should remain.
3. Click/hover/keyboard-activate tiles during and after motion, and dismiss/open multiple popout tabs. Verify hit targets match visible content, focus returns sensibly, Escape and click outside close the intended host, and background work tracks visible demand. Record timing/frames; judge restrained useful feedback rather than count effects.

### H5 — Small windows, keyboard and VoiceOver

- **Primary owner / related IDs:** Product experience; MD-U01 MD-U02 MD-U03 MD-U04 MD-U05 MD-U06 PR-08 PR-09 PR-11 PR-17.
- **Current source / status:** [WidgetConfigurationSheet:32](../../Sources/MyDock/UI/WidgetConfigurationSheet.swift:32); [WidgetAppearance:42](../../Sources/MyDock/CustomDock/WidgetAppearance.swift:42); [SettingsView:98](../../Sources/MyDock/UI/SettingsView.swift:98); [WidgetPresentation](../../Sources/MyDock/Models/WidgetPresentation.swift); [DockInspector:38](../../Sources/MyDock/UI/DockInspector.swift:38); existing code/harnesses are partial foundations only; all procedures below open.
- **Intended user outcome:** dependable small windows, keyboard and voiceover on the actual accepted artifact, including failure, interruption and recovery.
- **Dependencies / affected components / regression risks:** All 35 families/layouts and actual keyboard/VoiceOver, text/locale/system accessibility variants. Hidden actions, ambiguous announcements, focus loss and clipping.
- **Migration requirements:** no mutation performed by this ledger; associated package migrations/identity/cache/retention policies must be accepted before procedure execution. Preserve original fixture bytes/keys and rollback evidence.
- **Implementation / work performed:** manual plan reconciled; underlying corrective packages unstarted, existing harness/code not counted as native acceptance.
- **Verification / actual results:** not executed in this phase; no pass, performance number or native outcome inferred.
- **Remaining blockers / procedure:** fixture isolation and explicit scenario authorization first. H9 also lacks full Xcode/release identities/supported-host execution; live-account scenarios require dedicated authorized test accounts. Perform every acceptance criterion below, record actual outcomes/failures/skips against artifact/environment, then reopen linked findings if behavior contradicts source.

1. Open embedded and standalone Settings at their real minimum size, then progressively smaller supported layouts. Navigate all seven pages; reach the lowest controls via scroll/Tab/Shift-Tab. Ensure navigation remains visible, selected category announced, header does not obscure focused controls and no essential action requires ambiguous icon knowledge.
2. Open configuration for all 35 families using the matrix; test long titles, large values, non-English/12–24-hour formats. Verify task/setup/Save and Close are reachable, icon swatches affect only icon treatment, semantic layout dimensions match live faces, and settings survive close/reopen/relaunch.
3. Run VoiceOver explicitly: names/roles/values, selected states, reorder/menu actions, resize adjustments, focus order and restoration after Escape/sheets/popouts, add/search/error recovery. Accessibility identifiers alone are not acceptance.
4. Test light/dark/system, increased contrast, Reduce Transparency/Motion and macOS text-scale options where applicable. Measure problematic text contrast rather than asserting it from a screenshot. Test empty/long/disabled/loading states without tooltips and pointer acquisition at minimum Dock size.

### H6 — Finder, utilities, clipboard, color and sharing

- **Primary owner / related IDs:** Product experience; MD-A05 MD-A06 MD-A07 MD-D04 MD-D05 MD-D06 PR-02 PR-03 PR-10 PR-11.
- **Current source / status:** [DockUtilityWidgetViews](../../Sources/MyDock/CustomDock/DockUtilityWidgetViews.swift); [DockUtilityModels](../../Sources/MyDock/Widgets/DockUtilityModels.swift); [AirDropWidgetViews](../../Sources/MyDock/CustomDock/AirDropWidgetViews.swift); [TrashService](../../Sources/MyDock/SystemServices/TrashService.swift); [QuickCalculator](../../Sources/MyDock/Widgets/QuickCalculator.swift); existing code/harnesses are partial foundations only; all procedures below open.
- **Intended user outcome:** dependable finder, utilities, clipboard, color and sharing on the actual accepted artifact, including failure, interruption and recovery.
- **Dependencies / affected components / regression risks:** Sacrificial files/volume/clipboard; transfers only to explicitly authorized receiver; native specialist owns integration. Original deletion, private clipboard exposure, drafts, wrong drop order and reference loss.
- **Migration requirements:** no mutation performed by this ledger; associated package migrations/identity/cache/retention policies must be accepted before procedure execution. Preserve original fixture bytes/keys and rollback evidence.
- **Implementation / work performed:** manual plan reconciled; underlying corrective packages unstarted, existing harness/code not counted as native acceptance.
- **Verification / actual results:** not executed in this phase; no pass, performance number or native outcome inferred.
- **Remaining blockers / procedure:** fixture isolation and explicit scenario authorization first. H9 also lacks full Xcode/release identities/supported-host execution; live-account scenarios require dedicated authorized test accounts. Perform every acceptance criterion below, record actual outcomes/failures/skips against artifact/environment, then reopen linked findings if behavior contradicts source.

1. Use sacrificial app/file/folder fixtures. Drop externally at start/middle/end/groups/separators/empty Dock; distinguish current append-only limitation from internal reorder. Drag items out only where supported; verify actual URL/file-promise payloads, not just a decoded unit-test string. Open missing targets and use Locate; repair one installed-copy path.
2. Populate File Shelf with duplicates/multiple URLs to capacity, move/rename one file, disconnect a fixture volume, inspect unavailable feedback/Locate, and remove shelf entries without touching originals. Share/drag one fixture only to an explicitly authorized receiver; inspect cancellation/errors before any real transfer. AirDrop must show native recipient choice and cancellation; never send merely to mark a checklist pass.
3. In the disposable account, seed known throwaway clipboard text. Save/copy/edit/remove snippets and links, test empty/oversize/invalid URLs, schemes, dedup rules, capacity and feedback. Close an unfinished form by Escape/click outside/switch profile and test recovery/undo/relaunch. Check Clipboard content against the exact expected fixture, then restore the disposable clipboard policy.
4. Calculator: precedence, unary minus, parentheses, divide by zero, invalid expression and finite output. Converter: C↔F↔K, negative/decimal inputs, decimal/binary storage units and locale formatting. Color: valid/invalid short/long hex, palette capacity/dedup, copy output; sampler pick/cancel and denied/revoked system access where relevant. Do not infer permission solely from the presence of NSColorSampler.
5. In a separately authorized disposable user and sacrificial external volume, create known home/external Trash fixtures. Compare home count and Empty availability/confirmation to actual Finder-wide scope; Cancel must delete nothing. Record Automation denied/revoked and partial failure. Observe both automatic and pinned Trash face status separately. Never empty the everyday user’s Trash.
6. Test the actual AirDrop Dock face versus popout drop route with fixture URLs/files/file promises. The semantic face must expose the intended native handoff and truthful accessibility hint; recipient selection/cancellation does not establish delivery, and no transfer is made without an explicitly authorized receiver.

### H7 — Permissions and native preference restoration

- **Primary owner / related IDs:** Native platform; MD-S03 MD-S04 MD-Q01 PR-03 PR-05 PR-10 PR-14 PR-19.
- **Current source / status:** [MyDockApp](../../Sources/MyDock/MyDockApp.swift); [NativeDockController](../../Sources/MyDock/DockManagement/NativeDockController.swift); [NativeDockAutoHideController](../../Sources/MyDock/DockManagement/NativeDockAutoHideController.swift); [CalendarRemindersService](../../Sources/MyDock/SystemServices/CalendarRemindersService.swift); [CurrentLocationService](../../Sources/MyDock/SystemServices/CurrentLocationService.swift); [HydrationReminderService](../../Sources/MyDock/SystemServices/HydrationReminderService.swift); existing code/harnesses are partial foundations only; all procedures below open.
- **Intended user outcome:** dependable permissions and native preference restoration on the actual accepted artifact, including failure, interruption and recovery.
- **Dependencies / affected components / regression risks:** Separately authorized disposable macOS user/VM; capture originals and absent owned keys; fixture pending requests. Real preferences/permission mutation never on everyday user for evidence; failed recovery must retain journal.
- **Migration requirements:** no mutation performed by this ledger; associated package migrations/identity/cache/retention policies must be accepted before procedure execution. Preserve original fixture bytes/keys and rollback evidence.
- **Implementation / work performed:** manual plan reconciled; underlying corrective packages unstarted, existing harness/code not counted as native acceptance.
- **Verification / actual results:** not executed in this phase; no pass, performance number or native outcome inferred.
- **Remaining blockers / procedure:** fixture isolation and explicit scenario authorization first. H9 also lacks full Xcode/release identities/supported-host execution; live-account scenarios require dedicated authorized test accounts. Perform every acceptance criterion below, record actual outcomes/failures/skips against artifact/environment, then reopen linked findings if behavior contradicts source.

1. In a disposable user/VM, exercise each requested feature with denied, granted and revoked AX, Screen Recording, Automation per Music/Spotify/Finder, Calendar/Reminders, Location and Notifications. Request only on explicit action; verify no prompt loops and unrelated widgets remain usable. Follow displayed System Settings recovery instructions and record OS-specific wording.
2. Test EventKit empty calendars/filter changes/read/write, stale/no location fix, notifications while hidden/closed and enabled pending requests on relaunch. Revoke access while work is pending; stale results must not publish. Sleep/wake and change time zone/date; verify daily hydration, calendar and timer reset boundaries.
3. Capture the disposable user's original Apple Dock pinned layout and all owned preference values including absent keys. Apply a native fixture profile and replacement mode; test success, injected/reproducible failure, Cancel, normal quit, interrupted process/relaunch recovery and external preference changes. Verify exact owned keys restore, unrelated keys remain, recovery journal retained on failure and quit blocked when restoration fails. Never conduct this against the user's live Dock merely for audit.
4. Test fullscreen apps, Spaces/Mission Control, reveal handles/edges, Apple Dock appearance, desktop-widget mode and display disconnection. Public heuristics need empirical bounds; record platform limitations instead of promising private-API parity.
5. Qualify optional freeze overlays and window-preview caches with denied/granted/revoked Screen Recording, protected/minimized/ambiguous windows, apply/cancel/failure/display change and bounded capture cleanup. Images/cache clear/TTL must stay isolated; native switching without capture access must remain useful. Test external native auto-save versus own Apply, association and failed-write recovery.

### H8 — Failure, data and service acceptance

- **Primary owner / related IDs:** Reliability; MD-A01 MD-A02 MD-A03 MD-A04 MD-A05 MD-A06 MD-A07 MD-A08 MD-A09 MD-S01 MD-S02 MD-S03 MD-S04 MD-S05 MD-P01 MD-P02 MD-P03 MD-P04 MD-P05 MD-P06 MD-P07 MD-P08 MD-P09 MD-P10 MD-E01 MD-Q01 PR-01 PR-02 PR-04 PR-05 PR-13 PR-14 PR-15 PR-16 PR-18.
- **Current source / status:** [ProfileStore](../../Sources/MyDock/Persistence/ProfileStore.swift); [RevisionedStateWriter](../../Sources/MyDock/Persistence/RevisionedStateWriter.swift); [ProfileSemanticValidator](../../Sources/MyDock/Models/ProfileSemanticValidator.swift); [WidgetDataCoordinator](../../Sources/MyDock/Services/WidgetDataCoordinator.swift); [AIUsageService](../../Sources/MyDock/SystemServices/AIUsageService.swift); existing code/harnesses are partial foundations only; all procedures below open.
- **Intended user outcome:** dependable failure, data and service acceptance on the actual accepted artifact, including failure, interruption and recovery.
- **Dependencies / affected components / regression risks:** Fully isolated storage, clock, fake credentials/transports/native backends, cancellation fault injection; live accounts require separate authorization. Durability, privacy, partial/cross-tenant data, stale callbacks and resource growth.
- **Migration requirements:** no mutation performed by this ledger; associated package migrations/identity/cache/retention policies must be accepted before procedure execution. Preserve original fixture bytes/keys and rollback evidence.
- **Implementation / work performed:** manual plan reconciled; underlying corrective packages unstarted, existing harness/code not counted as native acceptance.
- **Verification / actual results:** not executed in this phase; no pass, performance number or native outcome inferred.
- **Remaining blockers / procedure:** fixture isolation and explicit scenario authorization first. H9 also lacks full Xcode/release identities/supported-host execution; live-account scenarios require dedicated authorized test accounts. Perform every acceptance criterion below, record actual outcomes/failures/skips against artifact/environment, then reopen linked findings if behavior contradicts source.

1. Temporary storage only: incompatible future schema, duplicate IDs, malformed/extreme cached metrics, combined import limits, unwritable directory/disk-full simulation, interrupted atomic write, concurrent edit/provider update, Save/Discard/Cancel, profile switch/deletion, undo/history and clean quit/relaunch. Compare bytes and user feedback; never corrupt production saved state.
2. Safe mocked transports: offline/timeout/429/revoked permission, response-size streaming, repeated pagination cursors/duplicates/nested pages, partial results, time-zone boundaries, currencies and saved freshness. Provider replacement uses fake credential facades and tenant IDs first. Later live test accounts require separate authorization; do not request real user keys to close this audit.
3. Run local AI fixtures with repeated/resumed/copied messages, truncated/large logs, missing/custom directories and explicit unsupported providers. Distinguish tokens/sessions/tools/estimated activity from billing/limits. Never invent missing totals.
4. Profile production Release startup, reveal, resize/hover, visible/hidden/absent-widget refresh, large profiles, sustained idle and sleep/wake. Record workload/duration, CPU/memory/network/disk/wakeups, cancellation and task/observer lifetime. The short DEBUG idle sample cannot pass energy/leak/startup requirements.

### H9 — Release acceptance

- **Primary owner / related IDs:** Native platform; MD-Q02 MD-Q03 MD-Q04 MD-Q05 PR-17 PR-19 PR-20.
- **Current source / status:** ReleaseMyDock.sh; BuildMyDock.sh; [FocusDockFilterIntent](../../Sources/MyDock/Focus/FocusDockFilterIntent.swift); [AppLifecycleService](../../Sources/MyDock/SystemServices/AppLifecycleService.swift); .github/workflows/validate.yml; existing code/harnesses are partial foundations only; all procedures below open.
- **Intended user outcome:** dependable release acceptance on the actual accepted artifact, including failure, interruption and recovery.
- **Dependencies / affected components / regression risks:** Full Xcode, separately authorized publisher signing/notary identities, supported OS/Intel/arm64 and exact artifact manifest. Metadata/artifact mismatch, TCC/signing continuity, installation/login/upgrade/rollback.
- **Migration requirements:** no mutation performed by this ledger; associated package migrations/identity/cache/retention policies must be accepted before procedure execution. Preserve original fixture bytes/keys and rollback evidence.
- **Implementation / work performed:** manual plan reconciled; underlying corrective packages unstarted, existing harness/code not counted as native acceptance.
- **Verification / actual results:** not executed in this phase; no pass, performance number or native outcome inferred.
- **Remaining blockers / procedure:** fixture isolation and explicit scenario authorization first. H9 also lacks full Xcode/release identities/supported-host execution; live-account scenarios require dedicated authorized test accounts. Perform every acceptance criterion below, record actual outcomes/failures/skips against artifact/environment, then reopen linked findings if behavior contradicts source.

1. On a full-Xcode release host, run unit/fixture checks and nine native UI methods with isolated state. Produce an Xcode metadata-bearing universal app via the existing release workflow; verify deployment targets, App Intents resource and effective entitlement set.
2. With separately authorized Developer ID/notary identity, execute ReleaseMyDock.sh into a fresh authorized output directory. Verify notarized/stapled app and DMG, checksum, Gatekeeper/quarantine launch, install/uninstall, Focus discovery, login item registration and explicit update behavior. Do not confuse CLI CI artifact with the metadata-bearing product.
3. Run supported OS/Intel/Apple Silicon matrix with glass fallback and permission variations. Publish acceptance evidence and unresolved limitations against the exact executable/source fingerprint. No release publication is authorized or performed by this audit.
4. Focus tests distinguish custom Activate from native Apply (FocusDockFilterIntent:69–78); test native selection only in the separately authorized disposable account/VM. Nil/off must follow the current no-op selection contract, missing profiles must report safely, and OS discovery/signing/registration is verified on the exact artifact.

<a id="results"></a>

## Verification log, unresolved gates and completion accounting

The technical audit’s earlier opportunities also reconcile: O1 collection quality maps to PR-02/08/10/16 and the separate OP-03 search extension; O2 audio maps to OP-05; O3 Calendar/timer feedback maps to optional PR-08/11 refinements and OP-04. None is automatically authorized.

All three specialist handoffs were received and reviewed. Overlapping PR-02/16/17/18 scopes have one primary accountable owner and the coordinator-only shared integration writer; report wording contradictions are resolved above. No unresolved factual disagreement is being hidden as a pass.

Actual work in this phase: full requested-document reads; exclusive specialist ownership/spawns; read-only current source/config/test/canonical-metadata inspection; parsed exhaustive IDs and coverage; registry/provider/source-hash reconciliation; evidence/wording conflict resolution; coordinator-authored ledger and dependency batches. No application/test/build mutation, new build/test/UI/native/account/destructive scenario, permission grant, live credential use, commit or publication.

Read-only commands/results: git status/rev-parse and repository file reads; SHA-256 comparison (124 baseline inputs + 19 tests, zero mismatches); registry/provider extraction (35 unique names each, exact equality); canonical metadata/lipo/codesign inspection (universal, valid strict ad-hoc, no metadata/team); xcodebuild -version refusal (full Xcode absent). Native also inspected the [Apple property-mutability API](https://developer.apple.com/documentation/coreaudio/audioobjectispropertysettable%28_%3A_%3A_%3A%29) for OP-05; this supports a feasibility check, not any device-selection pass. Guessed-path/read errors and a planning-generator syntax error were corrected; they are tool/report-authoring errors, not application defects.

Local planning artifacts: `.build/planning/coordinator-initial-state.json`, `specification.json`, `inventory-verification.json`, specialist source handoffs, preservation check and ledger validation. These are disposable validation/planning artifacts, not alternate app baselines. Existing source/test inputs match BUILD_BASELINE; canonical app remains build/MyDock.app. No private Application Support contents or credentials were read to populate this ledger.

Required future test gates: use ./TestMyDock.sh for relevant behavior/failure contracts after authorization. Native mutation, live Codex and custom-Dock runtime opt-ins stay disabled until safe isolation plus separate native/account authorization; synthetic performance must remain explicitly labelled. Installed inventory and synthetic opt-ins were passed only in the earlier audit, not rerun here. Nine Xcode UI methods remain unexecuted; source/parser presence is not UI qualification. Expand tests only for meaningful boundaries and new failures.

Environment/acceptance blockers: full Xcode is absent (CLT-selected xcodebuild refusal rechecked); no authorized signing/notary release execution, connected test accounts, multi-display/supported older-OS/Intel matrix or customer task study. Current production FPS, pointer latency, energy/startup/long-run resource measurements are absent. Native preferences/permissions/accounts/destructive work was deliberately not exercised on the everyday user. Tool failure is not a product failure. Earlier successful isolated CUA does not remove the safety prerequisite or pass the activated Dock.

Measurement procedure: record exact source/executable fingerprint, OS/hardware, actual display refresh/scale, workload/profile size/widget count, network, duration and method; use native Release signposts/Instruments/video plus CPU/RSS/network/write/revision/task counters. Distinguish synthetic geometry/writer cost from presented frame pacing. Record percentile latency/hitches and sustained resource behavior rather than one instant sample. Instrumentation/diagnostics must exclude private content. No unsupported performance threshold is invented in this plan.

Product validation procedures from the review remain open: unassisted first useful Dock; switch with pending input; organize a large profile; add/retrieve/recover a snippet/link; interpret a stale metric; decline/recover a permission; resize/switch on actual displays; relaunch after interruption. Establish a baseline for completion, mistakes, interpretation/recovery and qualitative reasons before setting numeric targets. Larger Organize/onboarding/meeting/system proposals need demonstrated task benefit and their stop conditions.

| Work category | Completed | Partial | Blocked / open | Deferred | Unstarted |
|---|---|---|---|---|---|
| This planning deliverable | Full reading, specialist investigation, source inventory and reconciliation, ownership, ledger and dependency batches | None after final reconciliation | Native/product acceptance was outside performed work | Optional implementation decisions remain | Implementation phase |
| 43 MD findings | Source conditions/evidence classifications reconciled; no corrective acceptance complete | Existing affected features/code; documentation reconciliation improves planning only | All relevant native/account/end-to-end acceptance open; release/isolation prerequisites explicit | MD-D04 spatial insertion optional; judgment-led refinements scope-gated | All proposed corrective/improvement changes |
| 20 PR packages | All specified/owned/dependency-mapped | Existing controls/reliability/release tooling are foundations only | PR-19 exact-artifact release; native/manual criteria throughout | Optional subscopes explicitly separated | All proposed package implementation/qualification work |
| 7 OP opportunities | All specified with dependency/migration/risk/stop criteria | Existing primitives only, not opportunity implementation | Feasibility/customer/device/account acceptance absent as applicable | All 7 pending product decision | All optional feature implementation |
| 35 widget families | Registry/provider equality and complete ledger inventory | All have code; some have confirmed defects/partial lifecycle | All whole-task/native/accessibility/desktop relaunch acceptance remains open | Enhancements beyond required correction decision-gated | Proposed family fixes/refinements |
| 41 application workflows | All retained and assigned | Existing code and earlier narrow checks | Canonical/native/release/whole-task gaps remain | Optional spatial/structured extensions | Proposed corrections/qualification |
| H1–H9 / original 35 + 5 supplements | Original and supplemental procedures/ownership complete | Existing harnesses and earlier isolated observations | Every group open; release tooling/environment blocked | Live/mutation scenarios await separate suitable authorization/environment | All procedures in this phase |

Future ledger update rule: after each authorized package record exact files/behavior changed, source/migration impact, relevant TestMyDock.sh command and actual pass/fail/skip counts, build/artifact hash and clean-quit/canonical launch evidence, and each manual scenario result. Keep implemented and verified independent. Failed/unperformed checks remain open; optional scope stays deferred until specifically approved. Only coordinator edits this ledger and coordinates integration/builds.

Planning completion is supported by the final completeness/preservation check below. This does not declare application completion. Stop here and wait for explicit implementation authorization.


## Final reconciliation and preservation result

Coordinator final check: **155 primary records** (43 MD, 20 PR, 7 OP, 41 F, 35 W, 9 H), with no missing or duplicate required ID. Widget order/names exactly match the current 35-family source registry and 35-provider set. All original 35 manual subprocedures plus five supplemental procedures are recorded (40 total). Every primary record contains owner/related IDs, current source/status, outcome, dependencies/components, migration/regression risk, criteria, separate implementation/work and verification/results fields, and remaining gaps/procedures. All relative artifact/source links resolve locally.

Preservation result: all **223 captured existing repository files** remain byte-identical; HEAD, existing git-status entries and canonical executable hash are unchanged. The only additional nonignored git-status entry is this ledger. Disposable planning scripts/notes/check records live under .build/planning/. Application source/tests/build configuration/current evidence files were not edited; no commit, publication or native/user-data action occurred.

Completed: investigation, reconciliation and planning deliverable. Partial: existing application/control/tooling foundations, with the specific defects and incomplete qualification listed above. Blocked/open: native/manual/provider/accessibility/performance and exact-artifact release acceptance, with concrete prerequisites/procedures retained. Deferred: all seven OPs and listed product-decision extensions. Unstarted: every proposed corrective/design/architectural implementation package. No unverified product behavior is represented as passed.

Stop after this deliverable. Await explicit implementation authorization for a defined batch/subscope; optional opportunities remain separately decision-gated.

## Implementation authorization and package journal

### Authorization — 3 October 2026

Required corrective Batch 1 is authorized. Reliability resumes with persistence safety (PR-01/02); Native resumes with window discovery/identity (PR-03); Product resumes with privacy/recovery/Example labels then compact legibility (PR-08/09/11/16); coordinator owns shared models, runtime isolation, production callers and integration. Each specialist retains the configured model/effort above. Exclusive peripheral ownership was assigned; no specialist edits this ledger or runs integrated builds. Read-only process inventory found no MyDock executable running before source work. Native permission/account/system-preference/destructive validation remains prohibited on the user’s data; isolated fixtures and blocked manual acceptance apply.

Implementation status: in progress; no integrated tests/builds have run yet. Optional OP-01…07 and Batch 2 expansions remain deferred.

### PR-08/09/11/16 — narrow truthful UI and compact presentation

Implemented required subscopes for MD-A08/A09/U02/U03/U06. Product changed RecoveryCenterView, PersonalPresetPicker, AddLibrary, WidgetPrimitives and DockInspector; coordinator centralized spacing/corner/tint bounds and Clock Compact width104. History privacy describes process-session preference and exact retained/always-omitted content; all entries remain reachable through existing scroll hosts; fixtures are labeled Example. Three pure formatter fixtures cover locale/time text and adversarial temperatures. No tests/build/native verification have run yet. Actual scrolling beyond10, VoiceOver,12/24-hour locales/min-scale fit and appearance0/30 roundtrip remain open. No persistent privacy preference, optional redesign or collection undo was added.

## Claude coordinator resumption — 3 October 2026

Coordinator changed from the Codex session to Claude Code (`/orchestrate`). The user re-confirmed authorization for required corrective work (Batch 1) **and** design/architectural improvements (Batch 2); Batch 3/OP-* remain decision-gated. Codex's partial implementation was committed by the user as `6f94afd` ("Baseline before Claude agents"), together with the pre-existing uncommitted working tree from before the audit. The 223 planning-time input hashes (`.build/planning/coordinator-initial-state.json`) separate the two: 170 files are byte-identical to the planning snapshot; **53 pre-existing files changed and 6 files were added by the Codex implementation** (`AppRuntimeEnvironment.swift`, `DockUtilityDraftStore.swift`, `NativeInteractionCorrectionTests`, `ProductWorkflowCorrectionTests`, `RequiredPersistenceCorrectionTests`, `RuntimeIsolationTests`). Those edits were treated as unreviewed work in progress.

### Verification of the Codex work in progress (coordinator, 6ea26e6 + integration fixes)

- **It did not compile.** `ShortcutsCatalog.list()` lost its implicit return after a guard was inserted, and `AppRuntimeEnvironment.defaults` violated Swift 6 global-state isolation. The coordinator fixed both as small integration edits (`return`; `nonisolated(unsafe)` with a thread-safety comment).
- `./TestMyDock.sh` (isolated `MYDOCK_VALIDATION_ROOT`) after those fixes: **286 tests, 278 passed, 5 skipped (the explicit opt-ins), 3 failed with 9 issues.** All 28 new Codex fixtures passed (RequiredPersistence 12, NativeInteraction 7, ProductWorkflow 7, RuntimeIsolation 2). Failures are pre-existing tests whose expectations encode the old behavior: `futureSchemaIsNeverOverwritten` (create is now candidate-first and publishes nothing on refusal), `appSettingsDecodeLegacyShapeAndPersistDesktopMode` (global decode now uses the shared 0–30/0–50/0–0.5 `DockAppearanceBounds`, MD-U06) and `dockSurfaceMetricsMatchRenderedTileGeometry` (Clock Compact 84→104, MD-U03). Logs: `.build/orchestrate/test-baseline-*.log`.
- Integration defects found in review: `DockUtilityDraftStore.discardTargets(notIn:)` is never called (drafts of deleted widgets/profiles are never pruned); an unreadable drafts file sets `readable=false`, so every clean quit reports unsaved changes with no recovery path.

| Entry | Codex implementation status | Verification status now |
|---|---|---|
| MD-A01 / PR-01 | Implemented: envelope-first state/backup version guard, oversized-file protection | Fixtures pass; one stale legacy test pending update; native relaunch open |
| MD-A02 / PR-02 | Implemented: candidate-first kind-create/duplicate/import; Restore, duplicate and visual-QA callers migrated | Fixtures pass; Restore UI failure path not exercised natively |
| MD-A03 | Partial: presentation guard on remaining percent only; no decode/import validation | No fixture yet |
| MD-A04 | Partial: bounded Weather face formatter only; Market/Stripe/Paddle/Weather parsers unchanged | Formatter fixture passes; parser fixtures absent |
| MD-A05 | Implemented: durable note save/flush, retained rejected drafts, Sticky Note error text, quit integration | Fixtures pass; large-paste/quit UI not exercised |
| MD-A06 | Implemented: private item-scoped snippet/link draft store with Resume/Discard, quit flush | Fixture passes; pruning not wired; corrupt-file quit defect open |
| MD-A08/A09/U02/U03/U06 | Implemented narrow subscopes (see journal above) | Formatter fixtures pass; two legacy expectations pending update; scrolling/VoiceOver/locale fit open |
| MD-D01/D02/D03 / PR-03 | Implemented: on-demand window discovery, raw/display title split, installed-copy + PID lifetime identity, v2 preview-cache key | 7 pure fixtures pass; H1 native acceptance blocked (AX/disposable user) |
| MD-Q01 / PR-05 | Partial: `AppRuntimeEnvironment` validation root, memory-only defaults, guards in ~32 files, isolated quit path | Isolation fixtures pass; disposable-user write trace not run |
| Everything else | Unchanged from the planning ledger | — |

### Execution plan (coordinator)

Batch 1 and Batch 2 run in three waves. Each wave runs one worktree-isolated agent per specialist, with exclusive file ownership. The coordinator merges branches one at a time, reruns `./TestMyDock.sh`, builds `build/MyDock.app` and launches it.

- **Wave 1**:
  - R1 Reliability: finish PR-01/02/05 (stale tests, A03 per-provider domains, A04 parser bounds, draft pruning/recovery, isolation gaps).
  - N1 Native: review and finish PR-03, plus MD-U05 and MD-E02.
  - P1 Product: A06 UI verification, A07 bounded undo, U01 task-first configuration, U04 Settings density, AirDrop/Trash face routing, PR-11 accessibility labels.
- **Wave 2**:
  - R2: PR-04/15 provider correctness (MD-P01–P10).
  - N2: PR-10 Shelf Locate/D05, Trash scope/D06, MD-Q03 Focus capability copy.
  - P2: PR-06/07 mode clarity and named workspace actions, plus the PR-09 remainder.
- **Wave 3**:
  - R3: PR-14 deadlines, cancellation and demand (S01–S05), and PR-13/E01 routine-edit coalescing.
  - N3: PR-18 instrumentation and PR-12 motion normalization.
  - P3: PR-17 registry-derived QA matrix (Q02) and PR-20 evidence/docs (Q05).
- **Not implemented, pending a product decision:** OP-01–OP-07, MD-D04 spatial insertion, PR-06 capture/tutorial, PR-07 Organize, PR-09 per-property overrides and PR-16 masking.

### Wave 1 journal

**N1 Native — merged 89a1dbc (branch commit 3f26b4e).** Coordinator review accepted it.

Implemented:
- **Codex PR-03 defects fixed:**
  - A missing `launchDate` disabled Quit, Windows and minimize. It is now optional, still matched on PID, installed copy and bundle ID, and fails closed if only one side has a date.
  - Untitled windows (`.noValue`/unsupported title) aborted discovery. They now get an honest empty title.
  - Window resolution required titles to match, which broke on changing browser tab titles. It now uses unique native-AX-object equality.
- Model and controller share the normalized pinned-URL runtime suppression (`RuntimeDockIdentity`).
- **MD-U05:** the grip keeps a transparent pointer area of at least 14 pt at scales 0.65–1.5, without changing layout length.
- **MD-E02:** `DockPresentationSignature` uses 25 presentation fields (resolved plus global). `lastSettingsPage`, onboarding and native-switch preferences no longer reassign the root.

Verification:
- 5 new pure fixtures (NativeBatch1ReviewTests) pass.
- H1/H2 native acceptance is blocked (AX, a disposable user and pointer measurement are required).
- Open note: the context menu does a main-thread `runningApplications` scan per tile. This is left for PR-18 profiling.

**P1 Product — merged 303b03a (branch commit 2473983).** Coordinator review accepted it.

Implemented:
- **MD-A06:** Codex's draft UI was verified. Saving goes through the throwing durable API and the entry is confirmed before the draft is discarded. No defects found.
- **MD-A07:** bounded in-memory undo for 15 s (`CollectionUndo.swift`). It covers Remove snippet/link, Shelf Remove/Clear and checklist remove/Clear Completed. It only re-inserts absent IDs at a clamped index within capacity. The Shelf copy says originals are not deleted.
- **MD-U01:** the configuration sheet shows the compact preview, then setup and Save, then a collapsed Appearance disclosure.
- **MD-U04:** compact narrow Settings header with all seven categories and their selected trait.
- **AirDrop/Trash:** the provider faces are restored in the live Dock (drop, help and AX; count and error).
- **PR-11 labels:** Reminders completion, App Folder move/remove, Color Picker selected trait.

Verification:
- 5 undo fixtures pass.
- VoiceOver, the live face drop, the Trash count, sheet heights and undo timing need native/manual checks.
- App Folder stays on the shared local face, which is the existing ledger design (W35).
- The `WidgetLibraryTile`/`CommandLibrary` Example labels have not been checked (outside P1's files).

**Integrated test (303b03a):** 296 tests. The only failures are the 3 known stale ProfileStoreTests, which are pending R1.

**R1 Reliability — merged 202580f (branch commits 706a298, 8ab11cf, b5ce21b).** Coordinator review accepted it.

Implemented:
- **Stale tests:** the three legacy expectations now encode the new contracts.
  - Create refused under future schema: nil id, nothing published, bytes unchanged.
  - Shared `DockAppearanceBounds`.
  - Clock Compact 104.
- **MD-A03:** cached AI snapshots are sanitized at decode, not rejected. Bad values become unavailable, so authored configuration is never discarded. Percent domains:
  - 0–100 for fixed-window providers.
  - 0–100,000 for Copilot and Claude. Claude spend-limit windows legitimately exceed 100 (an existing test requires 125).
  - The live Claude reader is bounded too.
- **MD-A04:** domain-bounded, trap-free parsing in Market, Stripe (`interval_count` 1–1000, checked division), Paddle, Shopify and Weather. Out-of-domain responses are rejected and the last good snapshot is kept.
- **Drafts:**
  - An unreadable/oversized utility drafts file is moved to `.recovery-<UUID>` with a one-time notice, so quit is no longer blocked forever.
  - Pruning runs on launch (only when state loaded intact) and on every removal path, scoped to removed IDs.
  - Note drafts for deleted widgets no longer fail the quit flush.
- **MD-Q01:** new guards for the Codex app-server limits adapter, the default-home Claude limits reader, AI activity log scanning, and `ClaudeLimitsSetup` writes to the real `~/.claude`.

Remaining unguarded sites (user-initiated or read-only):
- The `~/.Trash` watcher and open action.
- The Settings notification-settings read.
- Home-directory reads in SystemActivity/Disk widgets.
- Click-driven `NSWorkspace.open` calls.

Verification: `./TestMyDock.sh` passed with **320 tests passed, 0 failed, 5 opt-in skips**.

**N2 Native — merged c95c0f9 (branch commit d8b6119).** Coordinator review accepted it.

Implemented:
- **MD-D05:** File Shelf Locate… (user-initiated panel). It keeps the ID, title and position, and refuses duplicates without changing anything. Retry rechecks availability and refreshes stale bookmarks of resolvable files. Missing entries stay on the shelf.
- **MD-D06:** the count is labelled "home Trash (~/.Trash)". The confirmation reads "Empty the Trash on all volumes?" and states that uncounted items are included. Cancel is the default. The failure copy is honest.
- **MD-Q03:** Settings detects `Contents/Resources/Metadata.appintents` and tells CLI-built bundles that Focus filters need the Xcode-built release app.

Verification:
- 6 fixtures pass.
- No Trash or Finder operation was executed. H6/H9 are open.

**P2 Product — merged f73b675 (branch commit 0c419af).** Coordinator review accepted it. The copy was checked against native behaviour: native Apply persists after quit, and replacement mode restores on quit or mode change.

Implemented:
- **PR-06:** workspace caption and help explain editing vs. on screen vs. Apply. Menu bar sections are renamed. Onboarding states each mode's consequence.
- **PR-07:** the inspector has labelled Move earlier/later, Duplicate, Remove and Replace… controls. The profile menu has Undo/Redo. Names truncate, with the full name in help and VoiceOver.
- **MD-U02:** Example labels in CommandLibrary and the gallery tile.
- **PR-09/U06:** the inspector spacing shows numeric pt and an AX value, the inheritance wording is clear, and the reset button is renamed "Reset to Global". The inspector has no corner or tint sliders, so they needed no change.
- **PR-11:** canvas tile AX label (name, kind, missing) plus Move actions.

Verification: 4 fixtures pass. VoiceOver and minimum-size layout checks are open.

**N3 Native — merged e79aa88 (branch commit e4637ca).** Coordinator review accepted it.

Implemented:
- **H4 / decision #10:** `DockTransitionPolicy`. A style, Off or Reduce Motion change during an in-flight transition cancels it and normalizes alpha, scale and frame to the final state (`orderOut` when hidden).
- **PR-18:** `OSSignposter` signposts (subsystem bundle id, category "performance"):
  - `DockRootAssignment` and `DockPresentationTransition` intervals.
  - Resize begin/end events.
  - A DEBUG root-assignment counter.
- The context-menu process scan is deferred to menu evaluation.
- `AutomationError.permissionDenied`/`.failed` are classified from exit status and stderr (-1743). Trash and Now Playing copy use them.

Verification:
- 7 fixtures pass.
- Window-discovery signpost not added (outside N3's files).
- The live H4 interruption check, Instruments traces and the Automation-denied message are open.

**Coordinator build and launch (f73b675, before the N3 merge):**
- `./TestMyDock.sh`: **324 passed, 0 failed, 5 skipped.**
- `./BuildMyDock.sh` exit 0, canonical `build/MyDock.app`.
- Executable SHA-256 `0901f8c8c1269f1b2b53aff084f5d083d095af036593836eb8a04ac78a07d2dd`.
- Architectures x86_64 + arm64; `codesign --verify --strict` OK (ad-hoc).
- Launched the canonical path (PID 74997); the process is running. No UI interaction or native scenario was performed by the coordinator.
- N3 and later merges will be rebuilt at the next integration point.

### Waves 2–3 journal (continued)

**P3 Product — merged 02becee (branch commit 7bbd686).**

Implemented:
- **PR-17/MD-Q02:** `PremiumVisualQA.semanticLayoutPages` derives export pages from `WidgetRegistry`, so all 35 families are covered (previously the last 5 were omitted). `RegistryQualificationTests` asserts that every registry family has a provider, a presentation option and a QA page slot.
- **MD-Q05:** ARCHITECTURE (envelope-first guard, 35 families, validation isolation section), ACCEPTANCE_TESTS (H1–H9 is the native source, nothing marked passed), PARITY_MATRIX, PERMISSIONS (Paddle metrics.read, Finder-wide Empty Trash, Focus needs the Xcode-built app) and README are corrected.

Verification:
- Coordinator confirmed that `build/MyDock.app/Contents/Resources` has no `Metadata.appintents`.
- Dated test counts inside the docs remain historical.

**R2 Reliability — merged c346baf (branch commit 4400780).** Coordinator review accepted it.

Implemented:
- **P01:** Claude deduplicated by message/request id with incremental counters and per-`tool_use` ids; Codex deduplicated per session cumulative point; unidentified repeats are marked partial.
- **P02:** single `claudeDirectory(home:environment:)` resolver for account, limits and activity.
- **P03:** Shopify `isSameStore` keeps the local ID and rejects a different store.
- **P04:** page budget of 60, visited/advancing cursor checks, order-ID dedup, and `incompletePagination` with no partial total.
- **P05:** `completingItems` makes up to 20 `/v1/subscription_items` expansions; a still-partial subscription is counted as unsupported.
- **P06:** Paddle copy says Metrics → Read.
- **P07:** `plausibleDelta` treats a decrease as a wrap only when it is plausible for a 32-bit counter; otherwise that interval has no rate.
- **P08:** `BoundedHTTPFetch` streaming byte caps (Stripe/Paddle/Market 5 MB, Shopify 8 MB, Weather 2 MB) with a 60 s total limit.
- **P09:** `ConnectionTenantPolicy` plus `clearPersistedSnapshots`. A Stripe `/v1/account` identity comparison clears only when the tenant changes; an unknown tenant or Paddle key change clears; the widget stays assigned.
- **P10:** distinct session IDs across the range (daily points stay per-day); `semanticVersion` 2 forces old cached totals to recompute.

Verification:
- 28 fixtures pass.
- Two legacy ProfileStoreTests expectations were changed for P10 (one session spanning two days = 1).
- Live account smoke tests have not been run (they require dedicated authorized accounts).

**R3 Reliability — merged 8d0870e (branch commit 609e6af).** Coordinator review accepted it.

Implemented:
- **S01:** Cancel Run (SIGTERM, then SIGKILL after grace), no deadline for interactive runs, bounded stderr in failures, `cancelAll` on terminate.
- **S02:** explicit loading and unavailable states, latest-request token, per-entry cancellation, 300-row display cap.
- **S03:** Location has a 45 s deadline and rejects fixes over 10 min old or worse than 5 km accuracy, with typed errors. Reminders go through the `BoundedNativeFetch` single-resume gate (20 s), which cancels the EventKit token.
- **S04:** `HydrationReconcilePlanner` runs at startup and wake. It never prompts, removes duplicate and orphaned requests, and reschedules lost ones. When authorization is not granted it turns the saved enabled flag off. This deliberately matches the existing Alarm startup reconcile, so stored state never claims undeliverable reminders, and re-enabling prompts normally.
- **S05:** `RefreshScheduler` typed demand tokens (`RefreshDemandLedger`). It ticks when the Dock is visible or any token is held, and stays idle otherwise. System Activity, Network and Now Playing popouts hold demand.

Gaps and verification:
- The `.editor` demand kind exists but no consumer is wired. Battery has no popout token.
- One legacy Now Playing policy expectation was updated (hidden Dock plus popout → 5 s).
- H7/H8 native steps are open.

**Coordinator integration fix — Xcode project (ed8ebd6, e7d44cc).** `MyDock.xcodeproj` lists sources explicitly, and 9 sources plus 13 test files added since 24f9c76 (Codex and waves 1–3) were not registered. The Xcode/release build would therefore have failed, although SwiftPM was green. All files are now registered in their sibling group and build phase, and `plutil -lint` passes. **An Xcode build was not run: full Xcode is absent (xcodebuild refuses under CommandLineTools). This remains blocked under H9.**

**Coordinator integration build (e7d44cc):**
- `./TestMyDock.sh`: **398 tests in 47 suites passed, 0 failed, 5 opt-in skips.**
- Clean quit of the running app via a quit Apple Event. The process exited normally, so MyDock's own restore-on-quit path ran.
- `./BuildMyDock.sh` exit 0. Executable SHA-256 `c936b8eca17c9ad49832acdf0ddeaccc48db39e33b80a5d6a64fc7b4fcff7d6c`, universal x86_64 + arm64, strict ad-hoc signature valid.
- Relaunched canonical `build/MyDock.app` (PID 84180).
- No UI or native scenario was exercised by the coordinator.

**N4 Native — merged 7266f3b (branch commit 7eb86be).**
- Implemented:
  - In isolated runs, `TrashStatus` neither watches nor opens the real `~/.Trash`; production behaviour is unchanged.
  - `WindowDiscovery` signpost interval (no content).
- Verification: 2 fixtures pass.

**R4 Reliability — merged 6ead8ca (branch commit 30bdfba).** Coordinator review accepted it.

Implemented:
- **MD-E01:** routine mutations use the existing coalesced async writer (150 ms, revision guard, latest wins). The agent's report lists all call sites, each classified as either async or durable.
- These stay synchronous and durable:
  - `persistCandidate` paths.
  - `flush()`: quit, retry, resize finish and edit-session save.
  - `replaceProfiles`, `replaceProfile` and `replaceItems`, whose callers check the result.
  - Profile deletion, activation and setup-mode changes.
- `hasUnpersistedChanges` is set only after an actual failure.
- The SettingsView notification-status read is skipped in isolated runs.
- Accepted risk: a crash within 150 ms loses the last routine edit. Clean quit still waits for disk.

Verification:
- 5 fixtures pass.
- Two legacy tests now flush before reading disk.
- No latency measurement has been taken.

**Xcode project.** R4 used the repository's canonical `./GenerateXcodeProject.sh` (xcodegen). The coordinator resolved the merge conflict by regenerating from the merged tree; every Swift source and test file is now listed. Correction to the earlier journal: the original gap was **8 sources and 15 test files** added since 24f9c76, not "9 sources plus 13 test files". An Xcode build is still blocked because full Xcode is absent.

**Final coordinator integration (6ead8ca):**
- `./TestMyDock.sh`: **405 tests in 49 suites passed, 0 failed, 5 opt-in skips**. Log: `.build/orchestrate/test-final2.log`.
- MyDock was quit cleanly before the build and process exit was verified. `./BuildMyDock.sh` exit 0.
  - Executable SHA-256: `801e1f6983367cc491c070fe9501313daf82f41826377eb2c26309a4e1b82ca0`.
  - Universal binary; strict ad-hoc signature valid.
- Canonical `build/MyDock.app` relaunched (PID 88725).
- The previous baseline was archived as `history/RELEASE_EVIDENCE_PRE_CORRECTIVE_BATCH_2026-10-03.md` and `history/BUILD_BASELINE_PRE_CORRECTIVE_BATCH_2026-10-03.json`. RELEASE_AUDIT, BUILD_BASELINE (source fingerprint `9a056d5d…77dd6`) and IMPLEMENTATION_STATUS were refreshed.
- No commit was pushed and nothing was published.

## Final reconciliation — Claude coordinator, 3 October 2026

**Status vocabulary.**
- **Implemented** means code is present, coordinator-reviewed and merged.
- **Fixture** means isolated `./TestMyDock.sh` fixtures pass on the final tree.
- **Open** means native, VoiceOver, live-account or whole-task acceptance has not been run.
- **Blocked** names the missing prerequisite.
- **Deferred** means a product decision is needed.

No item below is natively accepted.

### MD findings (43)

| ID | Implementation | Verification | Remaining |
|---|---|---|---|
| A01 | Implemented (envelope-first guard) | Fixture | Open: native relaunch with future file (H8) |
| A02 | Implemented (candidate-first create/duplicate/import/Restore) | Fixture | Open: Restore UI failure on unwritable/limit fixture (H8) |
| A03 | Implemented (per-provider domains at decode) | Fixture | Open: relaunch with imported extreme cache |
| A04 | Implemented (bounded parsers in 5 providers + face formatter) | Fixture | — (live providers blocked) |
| A05 | Implemented (durable note save, retained drafts, quit) | Fixture | Open: >1 MiB paste, close/quit UI (H5/H8) |
| A06 | Implemented (private item-scoped drafts, Resume/Discard, recovery, pruning) | Fixture + review | Open: Escape/outside/profile switch/relaunch (H6) |
| A07 | Implemented (15 s session undo) | Fixture | Deferred: persisted undo (retention decision) |
| A08 | Partial (precise label, session lifetime stated) | Review | Deferred: persist preference (privacy decision) |
| A09 | Implemented (all retained entries listed) | Review | Open: >10/25 entries scrolling, keyboard (H5) |
| D01 | Implemented (on-demand discovery) | Fixture | Blocked: H1 (AX in disposable user) |
| D02 | Implemented (raw/display title, AX-object resolution) | Fixture | Blocked: H1 |
| D03 | Implemented (installed copy + PID/launch identity) | Fixture | Blocked: H1 (two app copies) |
| D04 | Not implemented | — | Deferred (Batch 3 spatial insertion) |
| D05 | Implemented (Locate/Retry/stale refresh) | Fixture | Open: H6 moved/ejected fixtures |
| D06 | Implemented (honest Finder-wide copy) | Fixture | Blocked: H6 disposable volume/account |
| S01 | Implemented (Cancel, stderr, quit cleanup) | Fixture (harmless script) | Open: real shortcuts (H7/H8) |
| S02 | Implemented (loading/cancel/cap) | Fixture | Open: slow/network folder |
| S03 | Implemented (deadlines, fix policy, EventKit cancel) | Fixture | Blocked: H7 permissions |
| S04 | Implemented (startup/wake reconcile; Alarm-consistent disable) | Fixture | Blocked: H7 notifications |
| S05 | Implemented for Dock + popouts; editor demand unwired | Fixture | Open: editor consumer; refresh counts natively |
| P01–P10 | Implemented (see R2) | Fixture | Blocked: live accounts need separate authorization |
| U01 | Implemented (task-first sheet) | Review | Open: H5 all 35 families at min size |
| U02 | Implemented (Example labels: AddLibrary, CommandLibrary, gallery) | Review | Open: VoiceOver |
| U03 | Implemented (Clock 104 pt, checklist fit) | Formatter fixtures | Open: locale/12–24 h/min-scale renders |
| U04 | Implemented (compact header) | Review | Open: H5 minimum window |
| U05 | Implemented (≥14 pt hit area) | Geometry fixture | Open: H2 pointer acquisition |
| U06 | Implemented (shared DockAppearanceBounds) | Decode fixture | Open: inspector→Settings→relaunch 0/30 |
| E01 | Implemented (routine async coalescing) | Fixture | Open: native main-thread latency |
| E02 | Implemented (narrow signature) | Fixture + DEBUG counter | Open: Instruments trace |
| Q01 | Implemented for all mutation-capable services; read-only/user-click sites listed in R1 report | Fixture | Blocked: disposable-user write trace |
| Q02 | Partial (registry coverage test, all-35 QA pages) | Fixture | Blocked: Xcode UI suite; render export not rerun |
| Q03 | Implemented (accurate runtime guidance) | Fixture; bundle lacks metadata confirmed | Blocked: H9 Focus discovery |
| Q04 | Not implemented (tooling exists) | — | Blocked: full Xcode, Developer ID, notarization |
| Q05 | Implemented (docs truthfulness, current evidence docs) | Review | — |

### PR packages (20)

| ID | Status |
|---|---|
| PR-01, PR-02, PR-03, PR-04, PR-14 | Implemented. PR-02's persisted undo is deferred; PR-14's editor demand is unwired. |
| PR-05 | Implemented, partial. Isolation covers all mutation paths. The disposable-user trace is blocked. |
| PR-06 | Implemented, partial: mode, status and first-run consequence copy. Capture and tutorial are deferred (Batch 3). |
| PR-07 | Implemented, partial: named actions, Undo/Redo, truncation. Organize is deferred (Batch 3). |
| PR-08 | Implemented, partial: task-first sheet and Example labels. The all-35 configuration check is open (H5). |
| PR-09 | Implemented, partial: shared bounds, compact header, inspector clarity. Per-property overrides are deferred. |
| PR-10 | Implemented, partial: D05, D06, AirDrop/Trash face routing. D04 is deferred. Drag, overflow and popout acceptance is open (H6). |
| PR-11 | Implemented, partial: compact fit and AX labels. The full VoiceOver, locale and contrast sweep is open. |
| PR-12 | Implemented, partial: transition normalization. Wallpaper, material and older-OS qualification is open (H3/H4). |
| PR-13 | Partial: routine off-main writes and the AI cache semantic version. **Separating the runtime cache from authored state is unstarted** (Large, phased). |
| PR-15 | Partial: tenant binding, partial flags, semantic version. **The connection health and provenance UI is unstarted.** |
| PR-16 | Partial: full lists, precise label, session undo. Persisted privacy preference and masking are deferred. |
| PR-17 | Partial: registry coverage test. **Typed registry, payload extraction and controller extraction are unstarted.** |
| PR-18 | Partial: signposts and root counter. **No measurements have been taken** (H2/H8). |
| PR-19 | Blocked: full Xcode, signing and notary identities. The Xcode project is now complete. |
| PR-20 | Partial: docs and evidence truthfulness. **The in-app help and diagnostics review loop is unstarted.** |

### Opportunities

OP-01 to OP-07 are all **deferred** and await a product decision. Nothing was started. The same applies to MD-D04 spatial insertion, PR-06 capture/tutorial, PR-07 Organize, PR-09 per-property overrides, PR-16 shared-screen masking and the wider calendar/timer workflows.

### Workflows F01–F41

Every F record remains **open for whole-task/native acceptance**. Code changed in this phase for these records:
- F01, F02, F03, F04, F05, F06, F07, F08, F09, F10, F11.
- F13, F14, F15, F16, F19, F21, F22, F23, F24, F28, F30, F32, F33, F35, F38, F39.

F12 changed through the PR-03 identity work. No code changed for F17, F18, F20, F25, F26, F27, F29, F31, F34, F36, F37, F40 or F41, apart from shared isolation guards. F37 local packaging is re-verified narrowly. F38 is blocked.

### Widgets W01–W35

All 35 registry families have a provider, a presentation option and a QA page slot (fixture). Every W-CHECK native/VoiceOver procedure remains **open**.

Families changed in this phase:
- **Providers:** W01 Stock, W02 Watchlist, W06 Weather, W11 Stripe, W12 Paddle, W13 Shopify, W22 Network, W23 AI Limits, W24 AI Activity.
- **Lifecycle:** W03 Calendar (via Reminders and EventKit only: no change), W04 Reminders, W05 Now Playing, W10 Shortcuts, W20 Hydration, W21 System Activity.
- **Product/native:** W08 Sticky Note, W14 Clock, W25 AirDrop, W26 Trash, W29 Checklist, W30 File Shelf, W31 Snippets, W32 Quick Links, W34 Color Picker, W35 App Folder.

No family-specific change: W07, W09, W15–W19, W27, W28, W33. They received shared undo, isolation and QA coverage only.

### Native/manual acceptance H1–H9

**All 40 subprocedures were not executed by the coordinator.** They need a disposable macOS user or VM, explicit authorization for permissions, preferences and destructive actions, dedicated test accounts, and (for H9) full Xcode plus signing identities. The agents' handbacks above list the additional steps their changes introduced, for H1, H2, H4, H6, H7 and H9.

### Accounting

| Category | Completed | Partial | Blocked | Deferred | Unstarted |
|---|---|---|---|---|---|
| MD (43) | 38 implemented with fixtures | A08, Q01, Q02 | Q04; native acceptance for all | D04 | — |
| PR (20) | 5 | 14 | PR-19 | Batch 3 subscopes | PR-13 cache separation; PR-15 health UI; PR-17 extraction; PR-20 help loop |
| OP (7) | — | — | — | 7 | — |
| F (41) / W (35) | Code and fixture work as listed | All | Native acceptance | Batch 3 extensions | — |
| H1–H9 | — | — | 40 procedures | — | — |

Every MD, PR, OP, F, W and H record is accounted for. No unverified behaviour is represented as passed.

## Follow-up wave — 4 October 2026 (user: "go ahead" on the unfinished authorized packages)

**R5 Reliability — merged 7ece4f2 (branch commit 66d555b).**
- Implemented:
  - **PR-17 typed registry:** a `WidgetCapabilities` descriptor for all 35 families covers layouts, default layout, connection, permissions, setup state, private content and refresh demand. `WidgetPresentationCatalog` is now a facade over the registry, and the stored family names are unchanged.
  - Battery popout `.popout` demand.
- Verification:
  - A snapshot test proves presentation output for all 35 families is identical to the pre-refactor values. Provider keys equal registry names.
  - The capability flags were coordinator spot-checked against the sanitizer and services. They are descriptive and not yet consumed by behaviour.

**P4 Product — merged 0a1946d (branch commits 2d6c4f6, a22320a, abea944).**
- Implemented:
  - **PR-15:** a shared `DataSourceProvenance` footer in the Stripe, Paddle, Shopify, AI Limits and AI Activity popouts and in Connections rows. It shows the source, metric definition, last refresh, and stored/failed (sanitized)/partial/stale state, with no live health claims. "Connected" is renamed "Credentials saved".
  - **MD-S05:** `.editor` demand while the configuration sheet is visible.
  - **PR-20:** a privacy and limitations help section on Settings General and Integrations. The diagnostics export gains `buildNumber` and `hasIntentMetadata` (format v2).
- Verification: a fixture proves that seeded private strings never appear in the diagnostics export.

**N5 Native — merged 8aa10e3 (branch commits ad4ece9, 84790c3).**
- Implemented: PR-17 controller extraction.
  - `CustomDockWindowController.swift` went from 1,949 to 671 lines.
  - New files: `CustomDockView.swift` (1,027), `DockPresentationPolicies.swift` (244), `DockItemContextMenus.swift` (17).
- Verification: the coordinator confirmed this is a pure move. Diffing the sorted removed and added lines differs only in imports and two `private` → internal changes.
- Not done: reveal/auto-hide monitoring is left in the controller, because it is interleaved with private state.

**R6 Reliability — merged (branch commits 960b37d, ccbe5b2) plus coordinator fix f1c90b5.**

Implemented (PR-13 phase 1):
- Provider readings are persisted only in `runtime-cache.json`: stock, watchlist quotes, Stripe, Paddle, Shopify, AI Limits, AI Activity and weather forecast.
- The cache is versioned, capped at 4 MiB and 2,000 entries, uses private permissions and coalesced atomic writes, and moves a corrupt file aside.
- Readings are tagged with the identity they were fetched for, so they are hidden on a tenant, symbol or location mismatch.
- Every state write strips readings, and a reading-only refresh never commits or writes `state.json`.
- Backups always exclude readings.
- On launch, a legacy file's embedded readings are merged into the cache (newer wins) and stripped once.
- The schema version is unchanged and the old fields still decode. An older app sees a stripped file as "not refreshed yet".

Deviation: the in-memory `WidgetConfiguration` still carries readings as a projection of the cache, so the roughly 100 view read sites and the edit-session merge are unchanged. Phase 2, which would move views to a cache resolver and remove the embedded fields, is **unstarted**.

Coordinator fix: the launch strip now runs only after a successful cache flush.

Verification:
- 9 fixtures pass.
- Five legacy backup round-trip assertions now expect no readings.
- The canonical app migrated the user's real state on relaunch. Verified by metadata only: the process stayed alive, and `runtime-cache.json` was created with mode 0600 and no recovery or corrupt files. File contents were not read.

**Coordinator integration (f1c90b5).**
- `./TestMyDock.sh`: **428 tests in 52 suites passed, 0 failed, 5 opt-in skips**.
- The Xcode project was regenerated with `./GenerateXcodeProject.sh` after each merge.
- MyDock was quit cleanly and process exit verified. `./BuildMyDock.sh` exit 0. Executable SHA-256 `a35bb831bb9867b89c16478be5f0f78a78e84355ee6b4f83d5ed847becf591bd`, universal, strict ad-hoc signature valid. Relaunched as PID 98053.

**Synthetic performance opt-in** (`MYDOCK_PERFORMANCE_OUTPUT`, SwiftPM Debug test, temp files only) — `.build/orchestrate/perf/synthetic-performance.json`:

| Scenario | Result |
|---|---|
| Geometry, 7 widgets | 0.063 ms median |
| Geometry, 30 widgets | 0.219 ms median |
| Geometry, 60 widgets | 0.406 ms median |
| Encode + atomic write, 50 profiles / 2,000 items | 111 ms |
| 20 immediate appearance writes | 2,040 ms |
| 20 coalesced writes + flush | 101 ms |

These are writer and geometry timings only. They are not UI latency, frame pacing or energy, and H2/H8 Instruments measurements remain open.

**Isolated render export** (DEBUG executable, `MYDOCK_VALIDATION_ROOT` + `MYDOCK_RENDER_QA`): default matrix 75 PNG, adaptive 36 PNG, tools 32 PNG, under `.build/visual-qa/corrective-batch-20261004*`. The coordinator inspected:
- Adaptive layout page 4, which now includes the five previously omitted families.
- The Clock Compact face, which no longer clips ("00:12").
- The task-first Clock configuration sheet with collapsed Appearance.
- The narrow Settings header, with all seven categories and a selected state.

Bitmaps are not native compositor or VoiceOver acceptance.

### Reconciliation update (supersedes the PR rows above where they differ)

| ID | Status now |
|---|---|
| PR-13 | Phase 1 implemented (persisted cache separation, migration, backup exclusion). Phase 2 (view resolver, removing embedded fields, authored-only edit merge) unstarted. |
| PR-15 | Implemented: provenance and freshness UI. Live connection testing is not claimed and live accounts are blocked. |
| PR-17 | Implemented: typed registry with snapshot proof, plus controller extraction. Reveal-monitor extraction is not done. Capability flags are not yet consumed. |
| PR-18 | Partial: signposts, plus synthetic writer/geometry numbers. Native Instruments measurements are open. |
| PR-20 | Implemented: in-app privacy/limitations help and diagnostics privacy fixture. |
| MD-S05 | Implemented, including the editor and Battery consumers. |
| MD-Q02 | Partial: registry coverage test plus a fresh 143-image isolated render export. The Xcode UI suite is blocked. |

Remaining unstarted authorized work:
- PR-13 phase 2.
- Reveal-monitor extraction.
- Consumers for the capability flags.

Everything else in Batches 1–2 is implemented or blocked on environment or native acceptance. OP-* and Batch 3 remain deferred.
