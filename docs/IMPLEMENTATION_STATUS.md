# MyDock implementation and acceptance status

**Updated:** 1 October 2026 (Europe/Warsaw). **Scope:** the 30-ticket roadmap in [the repository review](history/REPOSITORY_REVIEW_2026-09-29.md).

This is the canonical current status. The original audit records the pre-implementation findings. The original implementation pass preserved uncommitted work and did not mutate the user's Apple Dock. Later user-authorized replacement-mode checks verified native visibility preference application and restoration. No commit, push, publication or live account connection was performed. The repository cleanup preserves a complete source snapshot and earlier local artifacts outside the repository; see [the archive index](history/README.md).

“Implemented” below means the code is present and has passed the listed local checks. It does not claim a live macOS, provider, or distribution scenario has passed when that scenario has not been run.

## Product-design rebuild

The current source replaces the configuration dashboard with a Dock workspace: one sidebar, direct canvas selection/reorder, contextual inspectors, searchable Add Library, Command-K, native Undo and merge-safe autosave. Settings shares the shell. Shared semantic identities and material connect the editor and actual custom Dock. Existing profiles, widget configurations, permissions, integrations and recovery formats are preserved without a schema migration. Native layouts now use mode-aware Applied status and the creation sheet exposes custom versus macOS layout.

The canonical universal `build/MyDock.app` builds and strict signature/plist/project checks pass. The current widget follow-up reports **242 tests in 18 suites passed** and **76 final dark/light renders**. Shared surfaces, per-widget icon styles, bounded System Activity and three local utility widgets are implemented. Final canonical process launch was verified; CUA window lookup failed, leaving native widget interactions and popover frame/arrow acceptance open. The prior 116-installed-app audit and focused browser interactions are dated historical evidence. The preceding 74-layout broad accessibility matrix and panel runtime checks are dated historical evidence, not rerun on this final source.

## Widget presentation, icon styles and utilities

All 30 widget popovers share a native-matched surface and direct per-widget appearance controls. Live/Color/Soft/Mono styles persist per item and render in the Dock and manager. System Activity now fits the common width, stacks memory/health/storage sections, and samples while its popover remains visible. AI Activity retains provider data/recovery behavior with the shared header and inset totals.

Disk Space, Calculator and Quick Checklist are registered in Add Item. Checklist data round-trips through profiles and follows existing private-note sanitization. New model defaults preserve old profiles. Current build/test/render evidence and native limitations are recorded in [the widget report](history/WIDGET_PRESENTATION_AND_UTILITIES_2026-10-01.md) and [RELEASE_AUDIT.md](RELEASE_AUDIT.md).

## Historical Add Item and AI Activity follow-up

Installed-app discovery now validates actual current bundles, executable availability/architecture, metadata and canonical identities off the main actor. Remnant Adobe directories are excluded by validation, not name filters. Add Item uses category navigation, grouped real widget/system previews, compact app rows, visible Added state and deliberate duplicate behavior. Reopening/refresh/activation/volume notifications rebuild inventory; app insertion revalidates the selected path.

AI Activity now has a compact metric-led popover, readable daily chart, subdued provenance/partial states, one setup recovery action and saved-data retention during refresh. Its shared Dock-scale renderer provides provider identity, readable compact totals and short setup/error states. Existing integrations and profile formats were preserved.

That follow-up’s detailed evidence/limits are in the [preceding release audit](history/RELEASE_EVIDENCE_PRE_WIDGET_REDESIGN_2026-10-01.md) and the [focused report](history/FOCUSED_ITEM_BROWSER_AND_AI_ACTIVITY_2026-10-01.md). Full Xcode UI/VoiceOver, actual install/move/volume events, click-outside dismissal and final live refresh AX role remain unverified. At that follow-up’s close, CUA prevented an isolated-preview quit and the canonical app had launched. That runtime status is superseded by the current widget report. The preserved concurrent drag/focus changes still need controlled native acceptance per [the handoff](history/FOCUS_HANDOFF_2026-10-01.md).

The [workspace feature inventory](history/DOCK_WORKSPACE_REBUILD_2026-10-01.md) and [product-design acceptance ledger](history/PRODUCT_DESIGN_ACCEPTANCE_2026-10-01.md) remain earlier rebuild evidence.
## Roadmap ledger

| Ticket | Code status | Implementation / evidence | Acceptance still required |
| --- | --- | --- | --- |
| T01 Draft merge safety | Implemented | Field-level three-way item/configuration merge, conflict preservation, concurrent additions/deletions/order handling; edit-session regression tests | Broader concurrent UI matrix |
| T02 Unified quit/save policy | Implemented | Drafts survive profile/workspace navigation; shared Save/Discard/Cancel for window close and Quit; failed save keeps draft and supports retry; CUA navigation/exit checks | Xcode UI suite, all exit branches on shipping bundle |
| T03 Countdown deadline | Implemented | Resumed alerts use start plus remaining duration; generation ordering retained; deadline regression test | Delivered notification, sleep/wake and DST on a disposable system |
| T04 Recovery health gate | Implemented | Published native transaction health, journal cannot be overwritten, failed recovery blocks new apply; restore UI and fake-backend regression | Real interruption/relaunch and recovery |
| T05 Applied native association | Implemented | Association records only successful apply; create/delete do not invent a selected native layout; activation paths updated | Real apply and external auto-save association |
| T06 Semantic validation | Implemented | Bounded timer/date/history/configuration/appearance values, duplicate identity checks, bounded load/import, non-trapping timer formatting | Migration samples from older app versions |
| T07 Shared widget freshness | Implemented | Visible compact refresh; shared query/symbol cache, four concurrent provider jobs, cancellation, backoff, partial watchlist failures, refresh/error/saved-data UI; coalescing regression | Live expired/revoked credentials, rate limits and offline provider matrix |
| T08 Bounded external calls | Implemented | Background/coalesced AX with messaging deadlines; async bounded Music/Spotify/Finder processes; bounded AI history scanning; process tests | Hung third-party apps and permission recovery in the real desktop |
| T09 Unified render geometry | Implemented | One ordered render model for pinned/running/media/windows/Trash/insertion targets; renderer/controller/preview use shared metrics; geometry tests | Mixed display scale and production panel placement |
| T10 Visibility state machine | Implemented | Hidden dwell separated from visible retention; stationary-pointer policy sampling; overview suppression and handle policy | Mission Control heuristic, Spaces, fullscreen and Apple Dock overlap |
| T11 Typed complete drag model | Implemented | Declared custom transfer type; spacer/group/end/empty targets, running-app pin/unpin, combined internal/URL destination; keyboard start/end/left/right; one-step draft Undo | Editor end/group/spacer/cancel pointer checks pass after native tracking fix; live Dock group and cross-app/empty/overflow drops remain open |
| T12 Runtime identity/order | Implemented | Deterministic running-app/Trash IDs; final automatic Trash; unique identifier/title window restore with safe failure; unit tests | Real minimized windows and changing window titles |
| T13 Motion and magnification | Implemented | Continuous cosine proximity, reserved hover bounds, anchored scaling, interruptible fade/slide and Reduce Motion handling; math tests | Production frame pacing, interrupted reveal and high-refresh displays |
| T14 Narrow updates/writer | Implemented | One panel update owner; presentation signature skips data-only resizing; serial revision writer, coalesced runtime writes and lifecycle flush; stale-write test | Energy and main-thread profiling under realistic load |
| T15 Real manager preview | Implemented | Shared inert renderer with sample data, natural width, live geometry and appearance; scrolling-axis clipping fix; launch/edit/resize/native actions disabled | Left-side clipping and jump-to-start/end passed during the design follow-up; broader bottom/side overflow and size/theme variants remain |
| T16 Profile appearance scope | Implemented | Global inheritance or profile snapshot; separate finish/theme/density/card controls, correct selected-profile color, Undo; scope tests | Broader inheritance/Undo variants; selected profile override and Undo passed in CUA |
| T17 Atomic preset flow | Implemented | Nine preset families, one-time installed-app resolution with fallback notes, preview/name/remove/substitute/add apps, single persistent creation; failure test | Substitute/remove/add-app and persistence-failure UI variants; Cancel/Create passed in CUA |
| T18 Onboarding completion | Implemented | Mode-specific summary, optional installed starter apps, persistence before completion publication; failed-write test | First-run flow on clean installed app |
| T19 Connections center | Implemented | Stripe/Paddle/Shopify test/connect/replace/disconnect/remap, minimal scopes and shared cleanup; delayed Shopify refresh cannot restore deleted/replaced credentials; Keychain-only | Live provider credentials and account remapping on another Mac |
| T20 Popout design system | Implemented | Native-matched shared surface/header, direct per-widget icon choices, 420-point System/Network layout, freshness/retry, native controls and Escape; 76 current renders | Native frame/arrow, style clicks, keyboard focus and short-display overflow; CUA window lookup blocked |
| T21 Reference repair/icons | Implemented | Bundle-ID app relocation, reported launch failures, Locate in manager and live Dock, globe link fallback, bounded icon cache and common profile palette | Missing/moved files, actual failed launch dialogs and large icon catalog |
| T22 Market history contract | Implemented | Honest 5/22/66/100-session labels, real date axes, actual history count and daily-change explanation | Live sparse-market/history scenarios |
| T23 Widget lifecycle sweep | Implemented | Store-owned hidden timer completion and rescheduling; hydration midnight/time-zone/wake updates; Trash rewatch; bounded automation and robust media separator; lifecycle/parser tests | Midnight, notification delivery, Trash/Finder, AirDrop and Music/Spotify actions |
| T24 Accessibility/search | Implemented | Setting/control-level search, named controls/status, keyboard groups, sample-mode safety and reduced-motion feedback; shared contrast outlines/opaque material with 18 additional render variants; obsolete UI tests rewritten for current flows (parser only, not executed) | VoiceOver, contrast/transparency, keyboard-only and small-screen matrix |
| T25 Performance baseline | Baseline implemented | Repeatable 7/30/60-widget geometry and 50-profile/2,000-item writer scenarios; [recorded JSON](history/PERFORMANCE_BASELINE_2026-09-30.json) | Production CPU, memory, energy, animation FPS, hidden/visible and network profiling |
| T26 Live system acceptance | Harness implemented; acceptance pending | Explicitly opted-in apply/restore/journal test and manual acceptance plan; disabled on the user's host | Disposable macOS account/VM and complete Spaces/displays/notification matrix |
| T27 Distribution pipeline | Tooling implemented; qualification pending | Universal local build; scheduled Intel/arm64 CI; full-Xcode metadata gate; Developer ID/hardened runtime/notary/staple/DMG/checksum script | Full Xcode, publisher identity/notary profile, CI execution, clean install/update and supported OS runtimes |
| T28 Canonical docs | Implemented | Canonical ledger, current matrices/architecture/acceptance, final bundle hashes and machine-readable evidence; prior audits marked historical | Update evidence when external qualification runs |
| T29 Recovery/history center | Implemented | Inspect/restore-as-new history with 25 entries/14-day retention/8 MiB cap; default note and sensitive snapshot stripping; library tests | History inspect/restore UI and failed-library recovery |
| T30 Login/update/user presets | Implemented | SMAppService login status/approval, manual validated GitHub release discovery, bounded response, sanitized personal preset library/import/export; URL/version/library tests | Installed signed login item and real publisher release; updater repository is unset until a publisher supplies it |

## Current snapshot

Code and tooling exist for all 30 tickets. Twenty-seven rows are implemented features/documentation; T25 has a recorded synthetic baseline, T26 has an opt-in live-system harness, and T27 has distribution tooling. These last three rows still require broader qualification. This is an implementation build, not a claim that every definition of done or Dockset comparison has passed.

The current widget universal build, 242-test run and 76-layout render export have finished. The installed-app audit belongs to the prior focused baseline. Current evidence distinguishes isolated bitmap renders and final process launch from the CUA-blocked widget interaction checks. Broader editor/Dock focus/drop, production motion, provider and platform qualifications remain as listed below.
## Verification evidence before the design rebuild

- Before implementation: 161 registered Swift Testing tests in eight suites. The initial roadmap suite reported **190 registered tests in 13 suites**, passed. Default execution explicitly skips the synthetic performance and live native-Dock opt-ins. Performance was also run separately; the live-system opt-in was never enabled on this host.
- Host: Apple Silicon, macOS 26.5.1 (25F80), Swift 6.3, macOS SDK 26.4. Tests target macOS 14 for the bundled Swift Testing runtime. Shipping slices declare macOS 13.0; this does not prove older-OS runtime acceptance.
- Final universal Release bundle: `build/MyDockImplementationReview.app`; packaged as `build/MyDockImplementationReview.zip`. Both arm64 and x86_64 slices pass architecture inspection and report macOS 13.0 minimum/SDK 26.4. Signature and plist validation, archive integrity and archived executable identity pass. The signature is **ad-hoc**, with no Developer ID or notarization claim. The production bundle was not launched against the user's live profile store or Apple Dock.
- XcodeGen includes all 96 app Swift files and 13 unit-test files. Project/plist/entitlement syntax, UI-test parser, shell scripts, CI YAML and whitespace checks pass. Both build paths declare `app.mydock.items`; regeneration now preserves it. The local architecture verification also exposed and fixed `lipo` argument ordering in the release script and CI.
- [Machine-readable verification](history/IMPLEMENTATION_VERIFICATION_2026-09-30.json) records commands, host, source fingerprint, hashes, opt-ins, UI observations and limitations. Build/test logs are retained locally in `.build/implementation-verification-20260930/`.
- The [synthetic baseline](history/PERFORMANCE_BASELINE_2026-09-30.json) records median geometry times of 0.049/0.180/0.294 ms for 7/30/60 widgets and 97.98 ms for encoding/atomically writing 50 profiles with 2,000 items. This Debug CPU/disk benchmark measures no production frame rate, memory, energy, network or superiority over Dockset. Critical saves still wait for disk completion.

### Manual preview evidence

CUA used a Debug preview with private per-process state/history/preset directories and native changes disabled. Verified interactions include staged rename, dirty sidebar, preservation through Settings navigation, Save/Discard, Cancel Quit/Cancel Close, natural-width light/dark bottom samples, nine preset families, missing-app fallback notes, Cancel without creation, and Create of one complete selected profile. Group one-step movement and Command–Home/End preserve relative order; returning to the original order clears the dirty marker. Magnification search opens its exact Behavior section. Profile inheritance/override controls and appearance Undo restore the prior values.

The side preview exposed tiles painting outside the scrolling viewport. Axis clipping was fixed in the shared renderer and the suite/build passed. The Mac initially locked before that preview could be rechecked. The design follow-up later verified left-side clipping and jump-to-start/end. Broader bottom/side overflow variants remain pending. Pointer group/end drag was also blocked by CUA `windowNotFoundAtPosition` error -10005; this is not a recorded app failure or a passing drag check. The new design observations are recorded in the design report above.

### Historical implementation-build fingerprints

- App-source fingerprint: `0eefdb6d0e411fe509eaf568544df3a8eac19551a52d7a031cddc8c519459abb`.
- Universal executable SHA-256: `ada6d20c9c3991601ff377baf8640106d973af76f2e2e3fb2ce8545e26c9b9e8`.
- ZIP SHA-256: `bdb8cd798daf61bf0ae2f1ccd8ea7020853945b1cc92aa464d0b6d065ce5c9b2`.

## Remaining execution order

1. Complete the broader side/bottom overflow and size variants, external/empty/overflow pointer drops and live Dock group moves, history inspection/restoration and personal-preset import/export. Complete the broader keyboard/VoiceOver/appearance/popout UI matrix. Use the isolated preview first.
2. Record production CPU, memory, energy and frame pacing under hidden/visible, many-widget, interrupted-animation and high-refresh-display workloads (T25).
3. Run T26 only in a disposable macOS account/VM: native apply/rollback/recovery, replacement-mode restoration, real notification delivery, permissions, Spaces/fullscreen and display changes. Do not enable its opt-in on the user's everyday Dock.
4. With full Xcode and publisher signing/notary credentials, execute T27: Xcode unit/UI tests, extracted Focus metadata/discovery, supported macOS and Intel runtime matrix, signed/notarized install/update/login acceptance and CI execution.
5. Exercise live provider expiry/revocation/offline/rate-limit/remapping scenarios with dedicated accounts. Configure manual update discovery only with the actual publisher's release repository, then validate a real release.

There is no configured Git remote, full Xcode installation, publisher signing/notary identity, or connected test account available here. The final two stages cannot be certified from this workspace. A matched Dockset comparison remains required before claiming the product is better.

CI runner labels follow [GitHub's hosted-runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). The workflow is present locally; no CI run is claimed.
