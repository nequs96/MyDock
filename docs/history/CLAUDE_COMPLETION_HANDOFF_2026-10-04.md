# Claude completion handoff — 4 October 2026

Repository: `/Users/jakubjalowiecki/Documents/ChatGPT/dockX`

Use this file to finish the existing authorized work without repeating the completed first wave. Give Claude the **coordinator prompt** below. It can assign the three independent implementation packages, then integrate them once. If using separate Claude sessions, paste the common instructions and one package into each; keep one session as coordinator. A single session can instead execute A, B and C in dependency order.

This is a handoff, not an implementation result. No application or test source was changed while preparing it. The [verified status](VERIFIED_WORK_STATUS_2026-10-04.md) is the starting evidence; recheck the working tree before acting.

Source documents, relative to the repository:

- `AGENTS.md`
- `docs/history/VERIFIED_WORK_STATUS_2026-10-04.md`
- `docs/history/PROFESSIONAL_PRODUCT_REVIEW_2026-10-03.md`
- `docs/history/REVIEW_IMPLEMENTATION_BREAKDOWN_2026-10-04.md`
- `docs/history/EXECUTION_LEDGER_2026-10-03.md`
- `docs/history/COMPLETE_APPLICATION_AUDIT_2026-10-03.md`
- `docs/history/COMPLETE_APPLICATION_COVERAGE_2026-10-03.md`
- `docs/FULL_APP_AUDIT_PROMPT.md`
- `docs/RELEASE_AUDIT.md` and `docs/IMPLEMENTATION_STATUS.md`

## What to finish first

| Package | Work Claude can finish locally | Owns | Dependencies |
|---|---|---|---|
| A — Reliability and isolation | Repair the test syntax; finish AI scope/account/last-good behavior, App Folder identity and default-production network isolation | Shared models, persistence, services, runtime environment, provider/network internals and Reliability tests | Publish stable APIs early; network isolation gates any new renders/runtime validation |
| B — Native contracts and tooling | Finish Alarm scheduling/cancellation, Calendar selection and archive verification; review native/support docs | Alarm/Calendar native services, DockManagement, lifecycle, release tooling and Native/tooling tests | Shared model changes go through A; scheduling/selection contracts consumed by C |
| C — Settings and product completion | Finish explicit appearance scope and diagnostics preview; review/test the existing widget/library edits | UI, CustomDock, Widgets and Product tests, with the exceptions below | A's shared APIs and B's Alarm/Calendar contracts |
| Coordinator — Integration and evidence | Review combined changes, regenerate project, run tests/build, collect safe evidence and reconcile every ledger entry | Generated project, shared ledger, current evidence docs, integration commands | All implementation writers frozen; isolation verified before launch/renders |

Do A/B/C concurrently only with these exclusive ownership boundaries. Run shared tests/builds/render exports sequentially after a source freeze. No worker writes the shared ledger or updates generated project files. This avoids duplicate fixes, conflicting edits and results from a changing tree.

## Paste-ready coordinator prompt

```text
Work in /Users/jakubjalowiecki/Documents/ChatGPT/dockX.

Finish the authorized remaining implementation and integrated validation described
in docs/history/CLAUDE_COMPLETION_HANDOFF_2026-10-04.md. Continue the current dirty
working tree, including untracked source/tests. Do not start from HEAD alone:
that omits the unfinished work. Preserve .claude/worktrees/ and all existing edits.

Read AGENTS.md and VERIFIED_WORK_STATUS_2026-10-04.md completely. Read the professional
review and REVIEW_IMPLEMENTATION_BREAKDOWN_2026-10-04.md as specifications/evidence
leads; verify actual source before each change. Read RELEASE_AUDIT.md and
IMPLEMENTATION_STATUS.md. Use EXECUTION_LEDGER_2026-10-03.md, the complete application
audit/coverage reports and FULL_APP_AUDIT_PROMPT.md for individual acceptance contracts.
Do not copy historical Done claims into current verification.

Use the common instructions and exclusive ownership in this handoff. Delegate A/B/C
if parallel work is available; otherwise execute them in order. One owner handles
all shared models/integration APIs. Only you edit the ledger/current evidence docs
and coordinate project generation, tests, builds, launches and renders. Freeze
source before each integrated validation. Review every worker's diff and handback.

Priority: (1) the existing malformed Reliability test and correctness/isolation
dependencies, (2) finish existing wave-two edits, (3) Settings scope and exact-byte
diagnostics preview, (4) integrated checks/build and safe all-family evidence.
Do not redo verified first-wave features just because the older breakdown says
they were unbuilt. Do not expand this pass into optional features or a broad rewrite.

Do not commit, push or publish. Do not grant permissions, connect accounts, alter
native system preferences, inspect real private logs/credentials, mutate user data
or exercise destructive features for evidence. Use synthetic files, injected
providers/backends and fresh validation roots. Keep native/system/account/release
acceptance open or blocked when the required environment is unavailable.

The deliverable is finished authorized code with actual integrated results and an
updated ledger, not merely a plan. Resolve routine code failures within scope.
If a required native environment is missing, finish independent implementation and
record its exact blocked procedure rather than claiming acceptance.

Before reporting completion reconcile all 43 MD findings, 20 PR packages, 7 OP
opportunities, 41 workflows, 35 widget families, 9 manual headings and 40 procedures.
For each ledger record preserve owner, related IDs, source evidence/status, outcome,
dependencies/components, migration/risk, acceptance, implementation, work performed,
verification/actual results and remaining gaps/procedures. Update after every package.
Report completed, partial, blocked, deferred and unstarted work separately.
```

## Common instructions for each implementation session

Paste this together with the relevant package prompt when using separate sessions.

```text
Repository: /Users/jakubjalowiecki/Documents/ChatGPT/dockX.
Read AGENTS.md and docs/history/VERIFIED_WORK_STATUS_2026-10-04.md completely.
Read your relevant professional-review/ledger contracts and current source before
editing. Implement only the assigned package and preserve all existing changes.

Your allowlist is exclusive. Request shared API changes from Package A and any
ownership transfer from the coordinator; do not edit another owner's file. Do not
edit generated project files, the shared execution ledger or current evidence docs.
Do not create an ordinary HEAD-only worktree: it would omit uncommitted/untracked
baseline code. Use the agreed shared tree with exclusive files, or a coordinator-
provided snapshot containing the full current tree. Do not clean/reset/stash the
workspace or touch existing .claude/worktrees/.

Prepare meaningful fixtures for changed behavior. Coordinate test execution with
the coordinator; do not independently run shared SwiftPM builds/tests, regenerate
the project, overwrite/launch the canonical app or export renders while others edit.
Stop edits at handoff and report exact files/APIs, IDs, outcome, migration/risk,
commands actually executed, results, pending checks and manual procedures.

No commit/push/publication, permission grants, account connections, system preference
changes, real private-log/credential access, user-data mutation or destructive
validation. No OP-01–OP-07 or other deferred product feature. Fixture success is
not native acceptance. If source already satisfies a requested slice, verify and
retain it rather than recreate it.
```

## Package A prompt — Reliability and isolation

```text
Own Package A: PR-02/03/04/05/13/15, MD-D03/P02/Q01 and W23/W24/W35.

Exclusive application files:
- Sources/MyDock/Core/AppRuntimeEnvironment.swift and runtime-boundary helpers.
- Sources/MyDock/Models/**, Persistence/**, Services/**.
- Sources/MyDock/MyDockApp.swift only for required shared integration.
- SystemServices/AIUsageService.swift, GitHubCopilotService.swift, AIAccountService.swift,
  CodexAccountRPC.swift, WeatherService.swift, MarketDataService.swift,
  StripeDataService.swift, PaddleDataService.swift, ShopifyDataService.swift,
  SiteFaviconFetcher.swift, NowPlayingArtwork.swift, BoundedHTTPFetch.swift.
- Other provider-internal files only after explicit coordinator ownership assignment.
Exclusive existing tests: Reliability*Tests.swift, WidgetRuntimeCacheTests.swift,
ProviderCorrectnessR2Tests.swift. New narrowly named Reliability/isolation tests.
Do not edit UI, CustomDock, Widgets, native Alarm/Calendar services or tooling.

1. Recheck and correct ReliabilityLastGoodLimitsTests.swift line 61: the @Test
   method is missing the func keyword. Preserve its substantive assertions.
2. Finish/review the current AIUsageSourceScope/snapshot/cache/query changes. Prove
   root A to B, normalized aliases, unattributed legacy cache, daily/monthly interval
   changes, timezone and semantic-version boundaries. Old readings must never be
   relabeled as a new root/period. Preserve decoding of old snapshots; recompute
   conservatively. Keep authored profiles/drafts/history/backups free of readings.
3. Audit in-flight refresh attribution as well as projection: a response fetched
   for an old source/account must not be stamped current after configuration changes.
   Use deterministic injected clocks/environment/transport and fixture roots.
4. Finish verified Copilot last-good retention: exact verified identity plus source
   scope, transient errors only, original successful timestamps retained and explicit
   stale/failure presentation metadata. Authentication/setup/unavailable, identity
   mismatch, credential save/delete and missing attribution must invalidate. Codex/
   Claude paths or display labels are not verified account identities. Review existing
   sanitize/partial-success behavior and publish the UI contract to Package C.
5. Finish normalized selected-URL AppFolderApplication identity. Preserve Codable
   name/bundleID/URL, distinct installed copies, aliases and correct removal/duplicate
   handling. Tell C the identity contract; do not edit its App Folder/library views.
6. Close default-production networking in isolated validation. Weather, favicon and
   artwork are confirmed entry gaps; inspect market, billing, update-check and default
   WidgetDataCoordinator loaders too. A configured validation root must stop default
   external requests before DNS/session/transport starts. Native AppLifecycleService
   changes, if needed, are implemented by B against your shared guard contract.
7. Preserve explicit injected fixture transport/provider access. A blanket fetch
   ban that breaks URLProtocol fixtures is insufficient. Test default production
   fail-closed behavior with zero attempted external calls plus successful injected
   fake responses, bounded input, cancellation and ordinary-production compatibility.
   No real external request is needed to establish these cases.

Dependencies: publish stable snapshot/provenance/network/identity APIs early to B/C.
Keep schema and saved appearance formats unchanged unless a necessary migration is
explicitly documented. Review existing migration-failure/atomic-commit protections;
do not regress them while finishing attribution.

Hand back source/fixture evidence and exact APIs. Current checks must be run through
the coordinator's frozen integration. Do not claim live provider or filesystem/
network trace acceptance from pure fixtures.
```

## Package B prompt — Native contracts and tooling

```text
Own Package B: PR-02/11/14/17/19/20, W03/W18 and related native acceptance procedures.

Exclusive application files:
- Sources/MyDock/SystemServices/AlarmNotificationService.swift,
  CalendarRemindersService.swift, AppLifecycleService.swift and other native services
  only after coordinator assignment. A owns network/provider files listed in A.
- Sources/MyDock/DockManagement/** and UI/AppLifecycleSettingsView.swift.
- Scripts/WriteReleaseManifest.py, ReleaseMyDock.sh, .github/workflows/validate.yml.
Exclusive tests: NativeFollowupTests.swift, Tests/Tooling/test_release_manifest.py
and new bounded native fake-backend tests. Docs: DOCK_INTERACTION.md, SUPPORT.md,
UNINSTALL.md. Generated Xcode project and evidence/ledger belong to the coordinator.
Do not edit shared models, SettingsView, CustomDock widget views or A's network files.

1. Review and finish AlarmNotificationService's existing injectable backend and
   operation-generation changes. Replacement must retire old/legacy requests without
   deleting a newer operation; stale callbacks/cancellation must not mutate its
   successor. Denied authorization, partial repeating-add failure and exact cleanup
   need meaningful fake-client tests. Preserve default isolated permission/effect
   guards. Publish schedule/cancel outcomes to C; durable intent is separate from
   successful registration and actual delivery.
2. Finish Calendar ended-event filtering at endDate <= now, ongoing priority,
   all-day and selected-calendar behavior. Verify deterministic boundary selection
   with fixtures. Publish selection and timing contracts to C. No live EventKit data,
   permission grant or optional next-meeting action.
3. Review the current ZIP declared/streamed-size and Unix-mode checks. Finish/run
   the existing seven tooling cases through coordinated validation; cover archive
   mismatch/budget/mode failures with temporary fixtures and mocked native commands.
   Preserve exact binding of the checked metadata-bearing Xcode product to the
   uploaded artifact and manifest. Do not turn a CLI ad-hoc build into a release claim.
4. Verify login states and existing reveal extraction were not regressed; do not
   rewrite these first-wave-completed features. Wire any default update-client
   network boundary through A's API within AppLifecycleService if needed.
5. Review DOCK_INTERACTION/SUPPORT/UNINSTALL against actual current source. Describe
   click requests, closed-manager access, restoration/conflict/display policy and
   triage truthfully. Documentation of existing behavior does not implement a new
   ownership policy or pass native acceptance.

Keep real Alarm delivery, permission states, motion/display/Spaces, unsaved-app
dialogs, preference restoration, Focus discovery and release qualification open
unless explicitly exercised in an authorized isolated environment. Do not install
Xcode, sign/notarize, mount release images or change system state merely for evidence.
Hand back exact changes, fake-client/tooling results, risks and pending procedures.
```

## Package C prompt — Settings and product completion

```text
Own Package C: PR-08/09/11/15/20 and product-side wave-two widget work.

Exclusive application files:
- Sources/MyDock/UI/** except AppLifecycleSettingsView.swift (B).
- Sources/MyDock/CustomDock/** and Widgets/**.
- New UI/DiagnosticsPreviewSheet.swift or equivalent UI-only export helper.
Exclusive tests: ProductFollowupTests.swift, ProductRuntimeTests.swift and new
meaningful Product/Settings/diagnostics-preview tests. No shared Models/Persistence/
Services changes: ask A. No Alarm/Calendar native service, tooling, ledger/evidence
or generated-project edits. Coordinate any render-fixture edits before validation.

1. Finish explicit Settings appearance scope using the EXISTING architecture.
   Source already has an Appearance scope section, Apply appearance to picker,
   Global default/profile choices, appearanceProfileID, an inheritance toggle,
   effectiveSettings and scoped update/undo paths. The earlier status's description
   of a global-only panel is incomplete; do not rebuild or duplicate this machinery.
   Make Editing: This Dock / App defaults and the selected Dock clear. Preserve
   full saved overrides, shared ranges, inherited values, reset and undo. Resolve
   no-custom-Dock/deleted-selection states safely. Audit every control/preview so
   the displayed scope matches the object changed, including profile color; an
   app-defaults operation must not silently change a selected profile's own fields.
   No per-property-override migration or new standalone Settings window in this pass.
2. Add an explicit diagnostics preview BEFORE showing the save panel/writing.
   Generate one immutable redacted Data payload, show its contents and scope, then
   save exactly those reviewed bytes. Cancel/close makes no export; don't regenerate
   on Save and silently change timestamp/state/content. Do not add automatic upload
   or expand the existing diagnostics schema/private-data collection. Keep failed
   writes recoverable. Test payload identity, cancellation and seeded-private-data
   exclusion with fixtures. DiagnosticsService remains A-owned if an API is needed.
3. Review/finish the existing Alarm edit UI against B's contract: retain UUID/input,
   commit intent before schedule/cancel, stale-result guards, failure disables only
   the correct candidate, save failure keeps input and no false delivery claim.
4. Review/finish Calendar scope/ongoing/all-day/time-until copy and WidgetTimingPresentation
   against B's selection contract. Finish World Clock Mac/place/day-offset clarity,
   Countdown/Focus feedback, Disk successful-sample age, Stock/Watchlist effective
   versus fetch time, Weather timezones/units, Reminders versus Checklist distinction,
   Now Playing source, System Activity units and Sticky Note limit feedback.
5. Verify saved-snippet search doesn't disturb recoverable drafts/editing IDs;
   Color Apply changes preview while Save changes palette; calculator Return/focus/
   percent/session feedback is accurate. Keep completed converter precision intact.
6. Finish App Folder/AddLibrary/CommandLibrary copy identity and duplicate guards
   against A's normalized-URL contract, including keyboard selection of disabled
   app results. Repeated widgets remain valid independent instances. Preserve
   capability filters/task search/Presets and every existing provider projection.
7. Check all 35 registered families for Use versus Configure, focus/invalid-field
   behavior, minimum-window/side layout, real empty/loading/failure/stale/sample
   states and locale/long-content risks. Record each result/evidence gap. Correct
   regressions and bounded unfinished slices; do not turn this into a new broad
   design system, localization architecture or typed-payload rewrite. Bitmaps and
   accessibility labels do not pass actual keyboard/VoiceOver workflows.

Dependencies: consume A's provenance/cache/identity and B's scheduling/selection APIs;
don't invent parallel shared models. Author focused tests for consequential behavior,
not tests that merely assert literal copy. Freeze at handoff and state exactly which
families/surfaces were checked and which actual-native procedures remain open.
```

## Integration procedure for the coordinator

1. Capture current git status and hashes before work. The status report's recorded HEAD was `180f508c92881bfd8d5271c5c8b25e31cd04695c`; do not assume it is still current. Preserve tracked edits, untracked source/tests and existing worktrees. No reset/cleanup/commit is needed.
2. A publishes shared contracts; B/C consume them. A alone changes shared model/storage/integration APIs. Any file ownership transfer must be explicit and remove it from the former owner's allowlist before edits begin.
3. Receive source-frozen handbacks. Review combined changes for authored/runtime separation, migration fallback, account/root attribution, durable outcomes, stale callbacks, privacy, appearance scope and diagnostics byte identity. Resolve failures with the file owner; do not overwrite another package's changes.
4. Regenerate with `./GenerateXcodeProject.sh` and verify new source/test inclusion, particularly `WidgetTimingPresentation.swift`, source-scope/last-good tests and new preview/isolation fixtures. The coordinator owns generated `MyDock.xcodeproj/**` changes.
5. Run the relevant checks on that frozen tree and retain complete logs/exit codes. Standard integrated commands are:

   ```sh
   ./TestMyDock.sh
   python3 -m unittest discover -s Tests/Tooling -p 'test_*.py'
   git diff --check
   ```

   Keep native/synthetic/runtime opt-ins explicit and off unless separately authorized. A syntax-only parser check can catch the known typo early; it is not test execution. Correct failures, then rerun affected/integrated checks as justified. Counts are outputs, not targets to achieve by deleting/skipping meaningful tests.
6. Verify the production-default graph fails closed in isolated validation before any new app/render run. Use fake transports/backends and controlled temporary roots; do not prove network isolation by making a real request or treating absence of an observed request as complete tracing evidence.
7. Follow AGENTS.md for the canonical artifact. Quit `build/MyDock.app` normally and verify process exit before `./BuildMyDock.sh`; preserve drafts and owned-preference restoration. Never overwrite a running bundle. If normal quit cannot complete safely, stop the rebuild and record the blocker. Use `build/MyDock.app` as the only canonical app; disposable bundles belong in `.build/visual-qa/`.
8. Record the build exit code, executable SHA-256, both architectures/minimum-OS declarations, signature class/verification, plist and metadata presence plus exact source/build/test fingerprint. A full Xcode/metadata/release gate remains separate from CLI build success.
9. Launch the exact canonical executable only with a fresh explicit `MYDOCK_VALIDATION_ROOT`, after isolation has been verified; use normal termination and verify exit. Record the precise environment and limitations. Do not read the user's Application Support or credentials for validation. Follow current scripts/source rather than inventing obsolete preview flags.
10. Collect a bounded fresh synthetic 35-family render matrix through the existing `Sources/MyDock/UI/PremiumVisualQA.swift` machinery, after safe graph verification. Include relevant changed Settings/diagnostics/widget surfaces, light/dark/side/narrow cases and honest empty/stale/failure states. Record inspected files and defects; PNG presence alone is not a visual pass. No fixed PNG count is required. Native compositor/keyboard/VoiceOver/permissions and real provider workflows remain separate.
11. Only the coordinator updates `docs/history/EXECUTION_LEDGER_2026-10-03.md`, `docs/IMPLEMENTATION_STATUS.md`, `docs/RELEASE_AUDIT.md` and `docs/BUILD_BASELINE.json`. Preserve older dated evidence. Fresh records must bind logs/results to the exact tested source/artifact, label skips and partial checks, and keep implementation distinct from verification. Do not edit the verified-status snapshot to erase earlier failures.
12. Reconcile every MD/PR/OP/F/W/H record and all 40 native/manual procedures. Discover the registry/provider inventory again: the last check had the same 35 names in both, with no report difference. Preserve each acceptance requirement, its actual result and remaining manual procedure. Finish with separate completed/partial/blocked/deferred/unstarted lists and no commit/publication.

## Worker handback template

```text
Package and related MD/PR/W/F/H IDs:
Owned files changed; ownership transfers:
User outcome and current source evidence:
Shared APIs/dependencies consumed or supplied:
Migration requirements and regression risks:
Acceptance criteria:
Implementation: complete / partial / unstarted, with exact work performed:
Verification: commands, artifact/input identity, actual results, skips:
Remaining gaps/blockers and native/manual procedure:
Source frozen: yes/no:
```

## What this handoff does not authorize or magically complete

- **Deferred:** OP-01–OP-07, Organize, spatial external drop (MD-D04), capture/tutorial, per-property appearance overrides, persistent privacy/undo, shared-screen masking and unmade commercial/default/mode/OS choices.
- **Separate remaining review work:** task studies with real users, full localization/contrast/accessibility/density sweep, typed family payload architecture and real long-session/energy/Instruments measurement. Inventory/report these; don't automatically add them to the bounded implementation pass.
- **Native/manual acceptance remains open:** H1–H9 and their 40 procedures require appropriate controlled environments. Real window/Spaces/display interactions, wallpaper materials, notifications, permissions, Finder/sharing/destructive scope and native preference recovery cannot be accepted through an unrelated test or static render.
- **Release/environment blockers:** full Xcode, publisher signing/notarization, actual CI/distribution execution, Focus discovery, supported OS/Intel runtime qualification and dedicated provider test accounts. Record prerequisites and procedures; no install/account/signing/system mutation is requested merely to obtain evidence.

The first-wave reference is **445 individual passes, 5 explicit skips, 5 Python fixtures** and executable SHA-256 `67810611f8cb9431f4025d0174a3cc647a99ec8afcb3e16e6f1d642f177fd8c0`. It establishes the earlier frozen baseline only. The current wave-two tree must earn its own results.
