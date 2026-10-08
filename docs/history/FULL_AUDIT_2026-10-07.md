# Full audit (5–8 October 2026)

This is the consolidated record of the bottom-to-top audit of MyDock: every source file, test, script, workflow and document, read line by line in 20 slices. It lists each finding, what was done about it and the evidence for that. The machine-readable findings and fix outcomes stayed in the working session; this page is their complete summary.

## Method

- **Find.** One auditor per slice read every assigned file and grounded each finding in `file:line` evidence, with its impact, a proposed fix and a confidence level. P0, P1, medium-confidence and risky P2 findings were then re-checked adversarially before they were accepted.
- **Fix P0/P1.** Every P0 and P1 finding was fixed directly in focused commits with regression tests, then compiled and tested on CI (macOS 26 arm64 and Intel).
- **Review P0/P1.** Lane R, an independent extra-high-effort reviewer, re-read every hunk of the P0/P1 fixes for behaviour, data safety, concurrency and test validity, and fixed what it found.
- **Fix P2/P3.** The remaining findings were split into nine lanes by area (A–I), all run in parallel. In each lane a fixer verified every finding against the current code before changing anything, marking it fixed, already fixed, refuted (with the `file:line` that disproves it) or deferred (with the reason and a plan). An independent extra-high-effort reviewer then checked every hunk of the lane for compile safety, regressions, incomplete fixes, tests and design, fixed what it found and corrected wrong outcomes.
- **Integrate.** The ten lane branches were merged into one branch. Overlapping fixes were reduced to one tested implementation, and the follow-ups the reviewers raised were fixed after the merge.
- **Gate.** The container has no Swift toolchain, so CI is the compile and test gate for every change.

## Totals

| Severity | Findings | Fixed | Already fixed | Deferred |
|---|---:|---:|---:|---:|
| P0 | 3 | 3 | 0 | 0 |
| P1 | 34 | 34 | 0 | 0 |
| P2 | 215 | 203 | 2 | 10 |
| P3 | 275 | 259 | 4 | 12 |
| **All** | **527** | **499** | **6** | **22** |

By category: ux 90, bug 64, code-quality 53, reliability 52, ux-copy 38, design-consistency 37, performance 35, accessibility 28, docs 25, test-quality 21, dead-code 18, privacy 15, energy 15, build 11, persistence 8, test-gap 7, concurrency 4, security 3, ci 3.

### Slices

| Slice | Area | Findings | P0 | P1 | P2 | P3 |
|---|---|---:|---:|---:|---:|---:|
| S01 | Data models, widget models and core | 21 | 0 | 2 | 6 | 13 |
| S02 | Persistence, backup, data services and Focus | 23 | 0 | 1 | 9 | 13 |
| S03 | Provider APIs, networking and credentials | 21 | 0 | 4 | 9 | 8 |
| S04 | AI readers, subprocesses, Calendar and notifications | 24 | 1 | 1 | 10 | 12 |
| S05 | OS integration services | 35 | 0 | 5 | 12 | 18 |
| S06 | Live Dock view, essentials, context menus and presentation policies | 25 | 1 | 1 | 13 | 10 |
| S07 | Dock window, native Dock control, previews, app shell and automatic switching | 27 | 0 | 5 | 13 | 9 |
| S08 | Widget foundation: primitives, appearance, freshness, previews, materials | 24 | 0 | 0 | 8 | 16 |
| S09 | Core widget families: WidgetViews, utilities, Trash, AirDrop | 32 | 0 | 3 | 9 | 20 |
| S10 | Personal widget families: Calendar, Reminders, Alarm, collections, Now Playing, folders | 35 | 0 | 3 | 14 | 18 |
| S11 | Data widget families: Stock, Watchlist, AI, Weather, Audio Output | 28 | 0 | 2 | 9 | 17 |
| S12 | System and business widget families | 24 | 0 | 2 | 6 | 16 |
| S13 | Design system, tokens and Settings | 27 | 0 | 0 | 11 | 16 |
| S14 | Dock manager, canvas, inspectors and command palette | 35 | 0 | 1 | 19 | 15 |
| S15 | Add Item window and widget gallery | 25 | 0 | 1 | 11 | 13 |
| S16 | Sheets and flows: onboarding, widget settings sheet, presets, workspaces, portable Docks, polish, menu bar | 23 | 0 | 1 | 11 | 11 |
| S17 | Render QA code, build, CI, release tooling and repo hygiene | 27 | 0 | 1 | 13 | 13 |
| S18 | Tests: quality, flakiness, isolation and coverage | 25 | 1 | 0 | 8 | 16 |
| S19 | Documentation accuracy and README quality | 23 | 0 | 1 | 12 | 10 |
| S20 | Cross-cutting: dead code, duplication, terminology and repo-wide patterns | 23 | 0 | 0 | 12 | 11 |

## P0 and P1 findings

- **S04-001 (P0, reliability): CodexAccountRPC writes to the app-server's stdin without SIGPIPE protection; a server that exits mid-session terminates MyDock.** `Sources/MyDock/SystemServices/CodexAccountRPC.swift`. Fixed in `d03a994`.
- **S06-001 (P0, bug): Pinning a running or recent app keeps its deterministic runtime ID, which can later crash the Dock body on a duplicate key.** `Sources/MyDock/DockManagement/CustomDockView.swift`. Fixed in `d03a994`.
- **S18-001 (P0, test-quality): Isolation tests perform real Dock-preference and Keychain writes when the env-var isolation is absent.** `Tests/MyDockTests/RuntimeIsolationTests.swift`. Fixed in `ab84109`.
- **S01-001 (P1, reliability): Test isolation is environment-only and fails open; the isolation test itself then writes Apple's Dock prefs and the Keychain.** `Sources/MyDock/Core/AppRuntimeEnvironment.swift`. Fixed in `1b55888`.
- **S01-002 (P1, persistence): One unknown enum value or out-of-range field anywhere sets the whole state.json aside and starts with no Docks; schema version is never bumped.** `Sources/MyDock/Models/DockModels.swift`. Fixed in `2ec0bba`.
- **S02-001 (P1, privacy): Import Dock carries account IDs and embedded provider readings from the source file.** `Sources/MyDock/Backup/PortableDockPackage.swift`. Fixed in `1b55888`.
- **S03-001 (P1, bug): Shopify orders query requests far more than Shopify's 1,000-point single-query cost limit.** `Sources/MyDock/SystemServices/ShopifyDataService.swift`. Fixed in `531d266`.
- **S03-002 (P1, bug): Hardened-runtime release has no Location entitlement, so current-location weather cannot work in the notarized app.** `Xcode/MyDock.entitlements`. Fixed in `1b55888`.
- **S03-003 (P1, bug): Minor-unit conversion ignores three-decimal currencies (and UGX), so Stripe amounts in KWD/BHD/JOD/OMR/TND show 10x too large.** `Sources/MyDock/SystemServices/FinancialCurrencyFormatter.swift`. Fixed in `1b55888`.
- **S03-004 (P1, privacy): Copilot billing (Bearer token) and weather (coordinates) requests use URLSession.shared and its persistent disk URLCache.** `Sources/MyDock/SystemServices/GitHubCopilotService.swift`. Fixed in `1b55888`.
- **S04-002 (P1, bug): Calendar event snapshots of a recurring event share one id, so ForEach gets duplicate identities.** `Sources/MyDock/SystemServices/CalendarRemindersService.swift`. Fixed in `1b55888`.
- **S05-001 (P1, bug): Audio Output face never refreshes when the Dock uses auto-hide or hide-when-Apple-Dock-appears.** `Sources/MyDock/DockManagement/CustomDockWindowController.swift`. Fixed in `1b55888`.
- **S05-002 (P1, bug): Audio Output volume and mute readings go stale: no Core Audio listener for the current device's volume or mute.** `Sources/MyDock/SystemServices/AudioOutputService.swift`. Fixed in `2e1b309`.
- **S05-003 (P1, bug): Spotify track duration is read in milliseconds and treated as seconds.** `Sources/MyDock/SystemServices/NowPlayingService.swift`. Fixed in `1b55888`.
- **S05-004 (P1, bug): Now Playing parsing breaks on locales that use a decimal comma.** `Sources/MyDock/SystemServices/NowPlayingService.swift`. Fixed in `1b55888`.
- **S05-005 (P1, bug): Trash count reads ~/.Trash directly, which macOS protects; without Full Disk Access the widget shows a raw error and disables Empty Trash.** `Sources/MyDock/SystemServices/TrashService.swift`. Fixed in `2e1b309`.
- **S06-002 (P1, security): Live Dock URL drops skip DockLinkPolicy, so links with credentials (user:password@host) are saved.** `Sources/MyDock/DockManagement/CustomDockView.swift`. Fixed in `1b55888`.
- **S07-001 (P1, bug): Auto-hide reveal path never turns Audio Output observation on (or off).** `Sources/MyDock/DockManagement/CustomDockWindowController.swift`. Fixed in `1b55888 (dup S05-001)`.
- **S07-002 (P1, bug): 'Main display' resolves to NSScreen.main, which follows keyboard focus, so the Dock can jump between displays.** `Sources/MyDock/DockManagement/CustomDockWindowController.swift`. Fixed in `2e1b309`.
- **S07-003 (P1, bug): Desktop widget mode puts the Dock at wallpaper level, below Finder's desktop-icon window.** `Sources/MyDock/DockManagement/CustomDockWindowController.swift`. Fixed in `2e1b309`.
- **S07-004 (P1, reliability): Rollback runs inside the cancelled task, so a cancelled apply cannot restore the Dock.** `Sources/MyDock/DockManagement/NativeDockController.swift`. Fixed in `2e1b309`.
- **S07-005 (P1, persistence): Launch-time journal recovery silently restores an arbitrarily old Dock snapshot.** `Sources/MyDock/MyDockApp.swift`. Fixed in `89d165c`.
- **S09-001 (P1, bug): AirDrop popout drop area says it takes links but registers only file URLs, and does not validate the URLs it reads.** `Sources/MyDock/CustomDock/AirDropWidgetViews.swift`. Fixed in `1b55888`.
- **S09-002 (P1, ux): Trash count depends on reading the TCC-protected ~/.Trash with no setup flow; without Full Disk Access the widget is permanently "Unavailable".** `Sources/MyDock/SystemServices/TrashService.swift`. Fixed in `2e1b309`.
- **S09-003 (P1, bug): Trash count includes Finder's .DS_Store, so an empty Trash can read "1 item" and show the filled glyph.** `Sources/MyDock/SystemServices/TrashService.swift`. Fixed in `1b55888`.
- **S10-001 (P1, bug): Folder popout navigates into app bundles and document packages instead of opening them.** `Sources/MyDock/CustomDock/FolderContentsPopout.swift`. Fixed in `6825450`.
- **S10-002 (P1, bug): One-time alarm keeps showing as armed after it has fired.** `Sources/MyDock/CustomDock/AlarmWidgetViews.swift`. Fixed in `6825450`.
- **S10-003 (P1, bug): Date-only reminders count as overdue from midnight of their due day and show a 00:00 time.** `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift`. Fixed in `6825450`.
- **S11-001 (P1, bug): Stock and Watchlist session dates are shown one day early for users west of UTC.** `Sources/MyDock/CustomDock/StockWidgetViews.swift`. Fixed in `ab84109`.
- **S11-002 (P1, reliability): Opening a Stock, Watchlist or AI Limits popout forces a provider refetch and ignores the update interval.** `Sources/MyDock/CustomDock/StockWidgetViews.swift`. Fixed in `ab84109`.
- **S12-001 (P1, bug): Picking 'Saved reading only' in the Account/Store picker deletes the saved reading and disconnects the widget.** `Sources/MyDock/CustomDock/StripeWidgetViews.swift`. Fixed in `6825450`.
- **S12-002 (P1, ux): Stripe forces the currency to USD on connect and account switch, so a non-USD account shows 'No data' until the user changes it by hand.** `Sources/MyDock/CustomDock/StripeWidgetViews.swift`. Fixed in `6825450`.
- **S14-001 (P1, bug): Item inspector overwrites the whole item and reverts a Replace/Locate repair.** `Sources/MyDock/UI/DockInspector.swift`. Fixed in `febe41d`.
- **S15-001 (P1, bug): Return and Command-Return add a result the user never saw highlighted; the first Down arrow skips the first result.** `Sources/MyDock/UI/AddLibrary.swift`. Fixed in `ab84109`.
- **S16-001 (P1, bug): Commerce starter preset uses a non-existent Numbers bundle ID, so Numbers is never added.** `Sources/MyDock/UI/DockStarterPresets.swift`. Fixed in `febe41d`.
- **S17-001 (P1, build): Hardened-runtime release signs without Calendars and Location entitlements.** `Xcode/MyDock.entitlements`. Fixed in `1b55888 (entitlements added with S03-002/ORCH-001)`.
- **S19-001 (P1, docs): Manual Dock recovery docs record and restore only `autohide`, but replacement mode also writes `autohide-delay` (86,400 s) and `no-bouncing`.** `docs/REAL_DOCK_TEST_PLAN.md`. Fixed in `2ce3fbb`.

## Lanes

| Lane | Area | Findings | Fixed | Already fixed | Refuted | Deferred | Pending | Review |
|---|---|---:|---:|---:|---:|---:|---:|---|
| A | Models, persistence, backup and data services | 43 | 39 | 1 | 0 | 3 | 0 | fixed problems (5 found, 5 fixed) |
| B | Provider APIs, AI readers, Calendar and notifications | 40 | 39 | 1 | 0 | 0 | 0 | fixed problems (5 found, 5 fixed) |
| C | OS services, Dock window, native Dock and app shell | 59 | 57 | 0 | 0 | 2 | 0 | fixed problems (5 found, 5 fixed) |
| D | Live Dock view, essentials, context menus and presentation policies | 28 | 26 | 0 | 0 | 2 | 0 | fixed problems (9 found, 7 fixed) |
| E | Widget foundation and core widget families | 53 | 52 | 0 | 0 | 1 | 0 | fixed problems (8 found, 8 fixed) |
| F | Personal, data, system and business widget families | 82 | 78 | 2 | 0 | 2 | 0 | fixed problems (5 found, 5 fixed) |
| G | Design system, tokens and Settings | 31 | 27 | 0 | 0 | 4 | 0 | fixed problems (16 found, 8 fixed) |
| H | Dock manager, Add Item gallery, sheets and flows | 81 | 77 | 1 | 0 | 3 | 0 | fixed problems (10 found, 9 fixed) |
| I | Tooling, CI, tests, docs and repo hygiene | 64 | 58 | 1 | 0 | 5 | 0 | fixed problems (6 found, 6 fixed) |

Lane R reviewed the P0/P1 fixes rather than its own findings. It found 5 problems and fixed 4 in `98afad9`: S12-002 had no effect in the app; S01-002/S02-002 partial load: when a Dock is set aside, stateLoadedIntact stays true; S07-005: when launch recovery finds that the Dock changed after an interrupted change, it leaves health at recoveryRequired; The Stripe empty hero read 'No currency data' with 'Choose a currency reported by this account.' Now that the account's own currency is shown, this state only occurs when the reading has no currencies at all, or before the first reading, so there is nothing to choose. The fifth, that the opt-in live suites could no longer run, needed a decision and was fixed after the merge (see Integration).

## Integration

Each lane worked on its own branch from the P0/P1 head (`2ce3fbb`). The branches were merged in the order R, D, G, A, E, I, B, C, H, F, each as a merge commit, so every lane commit named in this report is still in the history.

Where two lanes fixed the same thing differently, the merge kept one tested implementation:

- **Calendar and Reminders:** request tokens (`CalendarRefreshToken`) and one selection summary replace the older per-view checks. `CalendarRemindersWidgetViews.swift` is gone.
- **Now Playing:** the live position is computed only by `NowPlayingSnapshot.livePosition(at:)`, which ignores non-finite positions and durations.
- **Weather:** staleness uses the shared freshness rule (30 minutes) instead of a family-specific dot.
- **Stock and Watchlist:** a change is red only for a fall of at least half a cent; otherwise it is secondary text, following the neutral-at-rest accent rule.
- **AI Activity:** the `~` (estimated) and `+` (partial) markers come from `AIActivitySnapshot.qualified`.
- **Interrupted native Dock change:** Settings shows one banner with Restore Previous Dock and Keep Current Dock.
- **Smaller merges:** the update check uses the bounded HTTP fetch with typed errors. Trash errors keep `failed` and `automationDenied`. Dock badges keep lane C's scheduler and publish only when they change.

The lane reviewers raised cross-lane follow-ups. They were fixed after the merge:

- **Opt-in live suites:** `MYDOCK_DISPOSABLE_SYSTEM_TESTS` and `MYDOCK_LOCAL_AI_ACCOUNT_TESTS` can run again. A DEBUG-only task-local grant applies only to that test's own task (`4653776`).
- **Magnification:** the Dock no longer reserves room for magnification on macOS 13, where it cannot magnify, and the switch is hidden there (`f005720`).
- **Labels in the docs:** they now match the merged app, for example Switch Dock, Show active Dock names in menu bar, Add Docks from Backup… and Minimized window thumbnails (`60a5246`).
- **System Activity:** the Network and Storage sections start off, following the product rule that anything which samples is turned on in one place (`edf1170`).
- **project.yml:** it declares the Desktop, Documents and Downloads usage strings that the Info.plist already had, so regenerating the Xcode project keeps them (`4b3c510`).
- **Launch at login:** the unavailable footer uses the switch's own name (`b1d8070`).

The lanes left 107 documentation notes. Each was checked against the merged source, and the docs were updated in `50949f8`. An independent reviewer then re-verified every changed sentence against the code (`ad13ddc`). That reviewer also found four small code issues, fixed in `5c738cc`, `b5fcfc1`, `f3f1295` and `46f6ce9`.

## Build and test evidence

The compile and test gate is GitHub Actions `Validate MyDock` on macOS 26, with one arm64 job and one Intel job. Each job runs:

- `./TestMyDock.sh`;
- the Python tooling tests;
- the universal release build, with architecture, signature and Info.plist checks;
- the Xcode Release qualification build.

| Run | Head | Result | Outcome |
|---|---|---|---|
| 32 | `2ce3fbb` P0/P1 pass | arm64 green. Intel tests and the universal build passed, then the Xcode step hit the 30-minute job limit. | The limit was raised to 60 minutes (`101eb90`). |
| 33 | `101eb90` | 6 tests failed on both runners: fixed 10-second waits ran out while other tests held the main actor. | A shared poll budget gives up only after 500 polls **and** 30 seconds (`ea0f165`, later applied to every wait in `4e718e3`). |
| 34 | `ea0f165` | **Green on both runners** (arm64 14 min, Intel 23 min). | Baseline for the lane merges. |
| 35 | `889c84d` lanes R and D | arm64 green. Intel tests and the universal build passed; the Xcode step was cancelled by the next push. | |
| 36 | `f005720` nine lanes | The compiler crashed (ClosureLifetimeFixup) on `ProfileLibrary.persist`. | `Result { try … }` closures replaced by a do/catch helper (`fe7de01`). |
| 37 | `fe7de01` | `error: fatalError` on both runners; the cause was outside the visible log tail. | A failure-only step now prints compiler errors and crash context last, and as annotations (`d2507bb`). |
| 38 | `d2507bb` | Two cross-lane compile errors: a spacing token one lane removed and another used, and an Undo handler whose return type changed in one lane. | Fixed in `887d236`. |
| 39 | `887d236` | Cancelled by the next push. | |
| 40 | `4b3c510` docs, project.yml | The app target compiled (arm64; the Intel job was cancelled by the next push). Two test-target errors: SwiftUI's `WidgetConfiguration` made a return type ambiguous, and `authorizedWhenInUse` is unavailable on macOS. | Fixed in `17a9b98`. |
| 41 | `17a9b98` | Both runners: six `#expect(x.mutatingMethod())` checks did not compile: the macro calls the method on an immutable copy. The errors print as `macro expansion #expect:L:C: error:`, which the failure step did not match. | Mutating calls moved out of `#expect` (`e26bcf6`). The failure step now reports macro-expansion and unlocated errors (`a494b46`). |
| 42 | `a494b46` | Everything compiled; then every test started and none finished until the 60-minute job limit on both runners. | A watchdog now samples the stalled test process (`d03a571`). |
| 43 | `d03a571` | The samples showed three synchronous subprocess captures waiting for pipe readers queued on the saturated global dispatch pool, which stalled the whole process. This is a real deadlock risk in the app too. | Pipe readers run on dedicated threads (`79ca965`). |
| 44 | `79ca965` | The suite ran to the end: 1,104 tests, 6 failing. The saved-Dock library discarded the whole file for one invalid entry (a product bug), two tests expected error types an earlier fix had deliberately changed, and three tests used short wall-clock waits. | `9d6e0a8`, `ae86107`, `e94f718`, `d2c9500`. |
| 45 | `d2c9500` | **Green on both runners, end to end:** 1,104 tests in 119 suites passed (arm64 30 s, Intel 33 s); Python tooling 25 OK; universal release build and bundle checks; full Xcode Release build. Run `37739188704`. | Baseline. |

## Deferred findings

Each deferral names its reason. Native-only checks that need a Mac are listed separately below.

- **S06-011 (P2)** The live Dock has no keyboard path: tiles cannot be focused, launched or opened from the keyboard. Keyboard access to the Dock needs a key-capable panel (borderless .nonactivatingPanel cannot become key today), a global "Focus Dock" shortcut in Settings and a focus model; it cannot be verified without a Mac. Plan: (1) CustomDockPanel subclass overriding canBecomeKey when focus was requested; (2) "Focus Dock" shortcut, off by default, registered with the existing global shortcut service; (3) @FocusState over tile IDs with .focusable(), .onMoveCommand along the Dock axis, Return/Space performing the tile action or toggling its popout, Escape returning focus to the previously active app; (4) system focus ring and a manual VoiceOver/keyboard acceptance pass.
- **S10-011 (P2)** Calendar app tile likely never shows today's date. Needs native verification: there is no way to tell from code whether NSRunningApplication.icon reflects Calendar's live date tile, and drawing over the icon blind risks overlapping the baked-in digits. Plan: run the manual check; if the date is static, overlay weekday and day in DockApplicationIconView (DockDesign fonts, schedule aligned to midnight) or drop the TimelineView and label.
- **S12-005 (P2)** No reconnection path in the popout: a revoked or rotated credential can only be fixed by Disconnect, which clears every widget's reading, and the dialog does not say so. Partial. The three disconnect dialogs now say saved figures are removed. Deferred: the in-popout Replace Key row, which needs ConnectionsCenterView.connect's replacement flow (ConnectionTenantPolicy, validateReplacement, snapshot clearing) and is too large to duplicate three times safely. Plan: extract that flow into a shared BusinessConnectionReplacement.replace(service:id:name:secret:domain:clientID:store:) and show a 'Replace Key…' row when store.widgetData.errors[query] != nil.
- **S13-011 (P2)** SettingsView is a 35-property state object shared by every page extension. Not purely mechanical: the page extensions share about 30 @State properties and several private helpers across files, and moving them to structs changes access control and sheet ownership. Without a compiler that is too risky in this pass. The unused accessibility property is removed (S13-014). Plan: (1) IntegrationsSettingsPage struct(store) owning the market/copilot drafts, messages, expansion and pendingCredentialRemoval; (2) DockSettingsPage struct(store) owning the native switch state and screenCaptureMessage; (3) BehaviorSettingsPage owning windowPreviewMessage; (4) GeneralSettingsPage owning backup, export, import, restore preview, diagnostics state and their three sheets; (5) AppearanceSettingsPage owning appearanceProfileID, undo and the confirm flag, initialised from store.activeCustomProfile, with SettingsQA updated to construct it; (6) SettingsView keeps routing, search, banners and the shortcut sheet. Do one page per commit and build on CI after each.
- **S14-018 (P2)** DockManagerView is a 1,131-line view with ~40 @State properties; proposed split. Not a mechanical split: the shell, sidebar, editor, inspector and three sheets share ~40 private @State values and private helpers (updateDraft, saveDraftOutcome, selection, afterLibrary). Plan: (1) extract @MainActor DockEditorModel (ObservableObject) owning selection/anchor/cursor, rename, updateDraft/registerUndo/saveDraftOutcome, insertDroppedURLs, move/remove/duplicate, with Swift Testing coverage; (2) DockSidebarView, DockEditorView and DockSelectionInspector taking the model; (3) DockCreationSheet (DockCreationSource), DockLinkEditorSheet owning favicon state/task, DockPresetPickerSheet with substitute/add app; (4) enum DockItemPanels for the NSOpenPanel pickers; DockManagerView keeps sheet routing and alerts. This part already removed the string-typed routing (S14-019) and the deferred sheet handoff (S14-020) that the split depends on.
- **S17-009 (P2)** CI never runs on the OS versions the app claims, never builds the UI tests, never runs render QA. Not done blind: it needs new runners and steps that cannot be tried from a lane, and a failure would block the merge. The UI target is written for Swift 6, and XCUIApplication is main-actor in the 26 SDK, so the target probably needs a @MainActor pass before it compiles. Plan: (1) add a continue-on-error job that runs xcodebuild build-for-testing -scheme 'MyDock Visual QA', fix the target until the job is green, then make it required. (2) Add a runtime-smoke job on macos-15 that selects Xcode 26 and runs the DEBUG render QA headless, after the S17-002 exit fix lands, and uploads the PNGs. The gap is now recorded in RELEASE_AUDIT.md under Not verified.
- **S17-013 (P2)** Render QA infrastructure is copy-pasted across eight files and the copies disagree. This is a large refactor that touches product code owned by other lanes (CustomDockView's popover shell), and merging the render hosts would change existing captures: DockStyleQA.render deliberately omits DockButtonStyle and the tint. Plan: add UI/RedesignQA/QAKit.swift (#if DEBUG) containing QARender.capture (one host with a buttonStyles flag), QARender.transparentDock (6x6 block corner check), QAWallpaper, QACaption, slug(_:), ColorScheme.qaName and AppSettings.with(surface:). Move the eight exporters onto it in one mechanical pass. Then extract CustomDockView.swift:870-897 into an internal DockPopoverContent view used by CustomDockView and every QA popover host. Step 1 started here: one clip check is shared by both hosts.
- **S20-004 (P2)** Spacing and radius tokens are almost unused; layout is driven by hundreds of magic numbers. A literal-to-token migration across about 1,000 call sites (and a cornerRadius-literal regression test that would fail until every one is migrated) is too large and too visual for an uncompiled pass, and it spans Dock, widget and onboarding files owned by other lanes. This pass removes dead tokens (Radius.floating, Module.compactInsets, Glyph.small, S13-014) and adopts tokens where touched (Radius.preview continuous on the hero, Grouped paddings in GroupedNote and SettingsExpansionRow, sectionTitle/caption fonts in PillButton, SizePager and StyleSwatch). The folder label clamp (CustomDockView.swift:675, 8 * size with minimumScaleFactor 0.65) is also left: at size 0.65 a 10 pt label plus the 26 pt icon overflows the 54 * size tile, so the clamp needs a matching icon size change in the Dock lane. Plan: (1) Dock lane: font max(DockDesign.Module.minimumTextSize, 8 * size) with the icon reduced to fit, and drop minimumScaleFactor; (2) per directory, replace cornerRadius 8/12/16 with Radius.row/group/Module.defaultRadius and always pass style: .continuous; (3) replace spacing and padding 6/8/12/16/24 with Space.*; (4) add the RedesignWidgetChromeTests grep guard last; (5) delete Space tokens still unused.
- **S20-011 (P2)** Widget kinds are stringly typed display names repeated across the codebase. This is a cross-cutting refactor of about 150 literals in roughly 20 files across every lane, and it cannot be compile-checked without a toolchain. Plan: add enum WidgetKind: String, CaseIterable, Codable with raw values equal to today's names, and DockItem.kind computed as widgetKind.flatMap(WidgetKind.init). Then migrate the switches one file per commit, starting with WidgetDataQuery.make and WidgetDataCoordinator, then WidgetCoordinatorFreshness, WidgetCardPreview and WidgetProviderRegistry. Add a test that every WidgetRegistry.all name maps to a case.
- **S20-012 (P2)** WidgetConfiguration is a 105-property union of every widget's settings, rebuilt 60 times as a fallback. Splitting the 105-field union into per-family structs with flat-key Codable is a large persisted-format refactor that cannot be safely compile-checked here, and the 60 fallback sites span other lanes' view files. Plan: first add extension DockItem { var resolvedWidgetConfiguration: WidgetConfiguration } and replace the fallbacks lane by lane. Then move WidgetConfiguration to Models/WidgetConfiguration.swift and introduce nested family structs behind computed flat accessors, keeping today's coding keys, with a round-trip test on the full state.json fixture.
- **S01-018 (P3)** DockModels.swift is a 1,398-line catch-all and WidgetConfiguration persists every family's fields for every widget. Deferred. Splitting DockModels.swift while other lanes edit it in parallel would cause merge conflicts or silently lost edits. Plan, after all lanes merge: move WidgetConfiguration and its private CodingKeys/init(from:) to Models/WidgetConfiguration.swift, the timer mutators to WidgetConfiguration+Timers.swift, AppSettings to Models/AppSettings.swift and WidgetRegistry to Models/WidgetRegistry.swift. These are mechanical moves with no access-control changes. Then add an encodeIfDifferent helper so a widget encodes only non-default keys; the RedesignAppearanceModelTests JSON fixture must be updated to match.
- **S05-034 (P3)** Network rates use 32-bit interface counters. Plan: in NetworkInterfaceReader.read, call sysctl [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0] into a byte buffer and walk the messages by ifm_msglen with loadUnaligned. For RTM_IFINFO2, read if_msghdr2.ifm_data (if_data64) ifi_ibytes, ifi_obytes and ifi_type, mapping ifm_index to a name with if_indextoname. Keep getifaddrs for addresses only, then let plausibleDelta treat any decrease as a reset. Deferred because the layouts of if_msghdr2 and if_data64 and their Swift import cannot be checked here without a compiler, and a compile error blocks the whole merge. The impact is limited to links above about 4 Gbit/s.
- **S05-035 (P3)** Audio Output reads all devices synchronously on the main actor. Done now: bursts of listener callbacks are coalesced into one refresh (scheduleHardwareRefresh). Deferred: moving AudioOutputCatalog.devices, defaultOutputDeviceID and controlState off the main actor. Plan: make AudioOutputHardware Sendable, with CoreAudioOutputHardware stateless and the test fake @unchecked Sendable. Make the listener path read in Task.detached(priority: .userInitiated) and publish on the main actor with a generation check, keeping explicit refresh()/select() synchronous for user actions. That changes isolation across the protocol, the fake and about 20 synchronous tests, which is too large to land safely without a compiler.
- **S09-032 (P3)** WidgetViews.swift (1,959 lines) mixes the popout shell, shared controls and eleven families; popout vocabulary is misfiled in UtilityWidgetViews. The split is mechanical but needs access-control changes, because private helpers are shared across families: timerText (Countdown and Focus Timer), batterySymbol, noteColor, appFolderTint and the provider structs. WidgetViews.swift is also a high-traffic file other lanes may touch in this merge, so moving ~2,000 lines now risks unresolvable conflicts and an uncompiled merge. Plan, as a dedicated commit after the lanes merge, with no behaviour change: (1) WidgetPopoutShell.swift: DockWidgetProvider, WidgetProviderRegistry, WidgetCompactView, WidgetPopout, metrics, environment keys, hero and policies. (2) WidgetPopoutVocabulary.swift: the round/circle button styles, WidgetStepperRow and UtilityWidgetViews.swift:31-218. (3) TimeWidgetViews.swift: Clock, World Clock, Stopwatch, Countdown (+ CountdownCopy and CountdownHeroPresentation), Time Progress, Focus Timer, with timerText made fileprivate there. (4) HydrationWidgetViews.swift. (5) BatteryWidgetViews.swift, with BatteryMonitor moved to SystemServices/BatteryReader.swift. (6) AppFolderWidgetViews.swift. (7) ShortcutsWidgetViews.swift. (8) StickyNoteWidgetViews.swift. Keep each provider private to its new file and the registry referencing them through internal types, then run ./TestMyDock.sh on both architectures.
- **S13-025 (P3)** GroupedSection clips its rows, which can cut off keyboard focus rings of full-width rows. This needs a native check, and there is no safe blind fix. Dropping .clipShape(shape) would let the full-width hover/press highlight of the first and last rows bleed past the rounded corners, and a custom focus ring could double the system ring. Plan: run the manual Tab-through check on macOS 13, 14, 15 and 26. If the ring is clipped, remove the container clip and clip GroupedRowButtonBody's highlight to an inset RoundedRectangle (radius DockDesign.Grouped.radius - 2), or draw an inset ring from @Environment(\.isFocused).
- **S13-027 (P3)** Each Settings sidebar click mutates ProfileStore state. AppSettings.lastSettingsPage is also the navigation channel: MyDockApp.showSettings(page:) and PremiumVisualQA write it, and SettingsView.onChange(of: lastSettingsPage) follows it. Moving it to @AppStorage alone would break deep links to the page already stored. Lanes C, E and I are editing those files now, including C's hunk next to showSettings. Plan, after the merge: add @Published settingsPage to DockWorkspaceNavigation for navigation requests and keep the last page in @AppStorage("app.mydock.settings.last-page", store: AppRuntimeEnvironment.defaults), migrating once from lastSettingsPage. Keep the AppSettings field decodable but stop writing it, and point PremiumVisualQA at initialPage or the navigation model.
- **S14-033 (P3)** Window shortcuts are invisible in the menu bar and ⌘, is duplicated. The dead hidden Cmd-, button (shadowed by the Settings… menu item, which does the same and also raises the window) is removed. Moving Cmd-K/N/D into the menu bar needs a request channel from MyDockApp (cross-lane) to the private manager state, since the workspace is an AppKit-hosted window without a SwiftUI WindowGroup: plan is a DockWorkspaceNavigation.request published value set by CommandGroup(replacing: .newItem) / a Dock CommandMenu and consumed by DockManagerView via onReceive, then deleting the hidden buttons; needs a native check that the commands disable when the manager is not key.
- **S15-015 (P3)** AddLibrary is a 614-line view with string-typed browse actions. The string-typed browse route was already replaced in lane H part 1 (S14-019: DockBrowseAction enum used by WidgetGalleryMoreEntry, AddLibrary, CommandLibrary and an exhaustive DockManagerView switch). Splitting AddLibrary into extension files is not purely mechanical: its 20 @State/@FocusState members are private and would have to be widened to internal. Plan: move keyboard/focus handlers into an AddLibraryKeyboard helper struct taking bindings, then split appsContent/widgetsContent once state access is explicit.
- **S18-014 (P3)** Duplicated fixtures and inconsistent polling helpers across test files. Partly done: the silent-timeout polling helpers in ReliabilityDemandCancellationTests, RoutineCommitCoalescingTests and ProfileEditingTests now record or require the timeout at the caller (SourceLocation). Consolidating fakes, stores and render probes across about 40 files is deferred because every lane edits these test files and it would cause wide merge conflicts. Plan: after the merge, add Tests/MyDockTests/Support/TestSupport.swift (@MainActor waitUntil ending in #require, TemporaryStore.make(writer:) with allowsSystemChanges:false and scoped removal, shared Fake Dock backend/relauncher/journal/auto-hide, SwitchableStateWriter, PopoutRigidity.expect, RenderProbe.visiblePixels drawing into a known RGBA context), then migrate one file per commit.
- **S18-017 (P3)** Absence checks after a fixed sleep can pass without proving anything. Real drain points need production API changes in persistence and edit sessions (RevisionedStateWriter.waitUntilIdle or a writes stream, an injectable autosave scheduler in ProfileEditSessionCoordinator, and NativeFollowupTests' waitForDwell is already injectable). Those files belong to the persistence and Dock lanes. Plan: add RevisionedStateWriter.waitUntilIdle() (queue.sync barrier) and replace the 400/220 ms sleeps with it; add an autosave clock parameter so discardCancelsPendingAutosave advances virtual time; give the NativeFollowupTests 400 ms cases a dwell stream like completeRevealDwell.
- **S18-018 (P3)** ProfileStoreTests.swift is a 2,934-line catch-all and other test files are named after milestones. Splitting the 2,900-line ProfileStoreTests and renaming the milestone-named files is not purely mechanical: shared private helpers and fakes at ProfileStoreTests.swift:2811+ would need new access levels. It would also conflict with every lane that adds or edits tests in these files during this merge. Plan, after the merge: move the fakes into TestSupport (S18-014), then split by feature into NativeDockControllerTests, IntegrationParserTests, AIUsageTests, TimerWidgetTests, SystemReadersTests and ProfileStorePersistenceTests, and rename FX02/FX03/FX09/N2-N4/PX1/PX2/PX5/ReliabilityWave1 by feature, one git mv per commit.
- **S20-015 (P3)** Largest files and functions need splitting along existing seams. Mechanical splits across lanes A, E, F, H and C files would collide with concurrent lanes. Plan: CustomDockView.itemView -> Equatable DockItemTile (label) + DockItemContextMenu (DockItemContextMenus.swift) + DockItemDragDrop ViewModifier; popover -> DockPopoutHost; runtime state -> DockLiveRuntime ObservableObject; chrome views -> DockTileChrome.swift. WidgetViews.swift -> WidgetProviderRegistry.swift, WidgetPopoutChrome.swift and per-family *WidgetViews.swift with their faces moved out of WidgetPrimitives.swift; DockModels.swift -> WidgetConfiguration.swift, AppSettings.swift, WidgetRegistry.swift; MyDockApp: #if DEBUG bootstrapVisualPreview(). Do it after the lane merge, one file per commit, with internal access for moved private types.

## Manual checks on a Mac

These fixes touch behaviour that only a real Mac session can confirm (window levels, Dock preferences, permissions, materials). Run them during release acceptance.

- [ ] S02-004: run ReliabilityDurableWriteTests, then use Instruments File Activity to confirm that every state commit issues F_FULLFSYNC (fcntl 51) and an fsync of the Application Support folder after the rename, and that editor autosave latency stays acceptable. (lane A)
- [ ] S01-010: launch with MYDOCK_VALIDATION_ROOT, change Interface appearance in App settings and confirm that DockDesign-driven @AppStorage views elsewhere (for example AppLifecycleSettingsView) update immediately. (lane A)
- [ ] S02-007: with a locked or slow login keychain, refresh Stripe, Paddle, Shopify and Stock widgets and confirm that Dock hover and animation do not stall. (lane A)
- [ ] S01-011: switch System Settings > General > Date & Time > 24-hour time while the Clock face is visible and confirm that the face follows the change on its next tick. (lane A)
- [ ] S01-019: launch build/MyDock.app; ~/Library/Application Support/MyDock/instance.lock exists and a second launch is refused; in an isolated run with MYDOCK_VALIDATION_ROOT, the lock is at <root>/ApplicationSupport/instance.lock. (lane A)
- [ ] S02-019: after editing a Dock, recording history, saving a preset, leaving an unfinished snippet draft and refreshing a provider widget, check that state.json, history.json, presets.json, utility-drafts/drafts.json and runtime-cache.json are mode 0600 in 0700 folders, with no .mydock-state-*.tmp files left. (lane A)
- [ ] S02-017: Settings > Recovery & history > Restore as New adds the Dock without switching the on-screen Custom Dock, and without turning it on in macOS-Dock-only mode. (lane A)
- [ ] S01-020: the Stock popout range picker shows 1W, 1M, 3M and 5M; saved Stock widgets keep their range. (lane A)
- [ ] S19-009: in Add Item, the Permissions filter no longer lists Focus Timer, and its tile no longer says 'May request permission'. (lane A)
- [ ] S02-023: with 2 Docks' drafts open, one in conflict, choose Quit > Save Changes; the clean Dock saves and the alert names only the conflicting Dock. (lane A)
- [ ] S04-008: on a Mac run printf '{"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":1900000000}},"x":null}' > /tmp/i.json; /usr/bin/plutil -extract rate_limits json -o - /tmp/i.json; echo $? to see whether plutil rejects null (the bridge now falls back to osascript JavaScript either way). Then Enable Limits, use Claude Code once and confirm mydock-rate-limits.json updates. (lane B)
- [ ] S04-009: with an existing Claude Code status line, Enable Limits, then Turn Off in Settings → AI accounts; confirm ~/.claude/settings.json has the original statusLine command, mydock-rate-limits.json is gone and the terminal shows the original status line. Repeat with no status line: nothing is shown while enabled and statusLine is removed on Turn Off. With a v1 bridge installed, Enable Limits once and confirm it is upgraded to v2 without nesting. (lane B)
- [ ] S04-011: schedule 70 distinct repeating UNCalendarNotificationTrigger requests from a test build and read pendingNotificationRequests().count to confirm the per-app cap on macOS; if confirmed, add the tooManyAlerts guard and a reconcile message (left for follow-up). Check that an every-day alarm fires daily from its single request. (lane B)
- [ ] S04-012: create a shortcut that waits 30 s and then shows a notification, run it from the Shortcuts widget, press Cancel Run and check whether the notification still arrives; the status now reads 'Stopped waiting (may still run)' either way. (lane B)
- [ ] S04-006: with several AI widgets and a slow or missing Codex, confirm Claude and Copilot limits appear without waiting for Codex, and that closing a popout mid-check leaves no codex app-server process running (Activity Monitor). (lane B)
- [ ] S04-010: with Claude Code installed only through nvm, Volta, Bun, pnpm or the local installer and MyDock launched from Finder, confirm Find Account detects it. (lane B)
- [ ] S20-008: refresh a Weather widget, then confirm ~/Library/Caches/<bundle id>/Cache.db has no open-meteo entries; fetch a site favicon and Spotify artwork and confirm they still load (redirect policies apply through the task delegate). (lane B)
- [ ] S03-012: add a link item for a site whose favicon.ico lists 16 px first (for example a large news site) and confirm the Dock tile is sharp at large sizes. (lane B)
- [ ] S03-013: after rebuilding the ad-hoc signed app, confirm saved Stripe, Paddle, Shopify, Alpha Vantage and Copilot credentials still read (same service and account names). (lane B)
- [ ] S03-008/S03-009: with a real restricted Stripe key, confirm revenue, net, MRR and balance still match the Stripe dashboard under the pinned API version, and that an account with more than 1,000 subscriptions still shows its balance. (lane B)
- [ ] S03-020: switch Location Services off in System Settings, then choose Use Current Location in the Weather widget. The Location Services message should appear at once, not after 45 s, and with no main-thread hang warning. (lane B)
- [ ] S03-020: make two current-location requests at once. The second should say 'A location request is already in progress.' (lane B)
- [ ] S03-017: add a link item for a normal https site and confirm its favicon still loads. ICO, PNG and AVIF favicons should all load, and URLSessionTaskMetrics should reach the task delegate before the body completes. (lane B)
- [ ] S04-015: create a shortcut named '-Morning' and run it from the Shortcuts widget. Confirm /usr/bin/shortcuts accepts 'run -- <name>'. (lane B)
- [ ] S04-016: run an interactive shortcut that waits for input. In Activity Monitor, MyDock's idle wakeups should be about 2/s rather than 20/s, and Cancel should still stop waiting promptly. (lane B)
- [ ] S04-017: with notifications set to Deliver Quietly (provisional), Alarm and Countdown alerts should schedule. (lane B)
- [ ] S04-022: on a real calendar with an all-morning event marked Free, and a busy all-morning block followed by a Zoom call in 10 minutes, the compact Calendar face should show the call. (lane B)
- [ ] S04-023: point ~/.claude/settings.json at a dotfiles symlink. Enable Limits should show the link message and leave the linked file unchanged. Without a link, the rewritten settings.json should contain unescaped '/' paths. (lane B)
- [ ] S05-016: on macOS 14, 15 and 26, with another app frontmost, choose a background app's window from the Dock 'Windows…' menu and from a minimized-window tile; the app must come forward with no 'Window unavailable' alert. Start Workspace on a running app must bring it forward. (lane C)
- [ ] S07-006: enable Smooth switches, switch between two native Docks from the status menu, and confirm the overlay stays until the relaunched Dock has drawn; then make the target layout include an app the Dock drops and confirm the switch reports 'did not show the expected layout … previous layout was restored'. (lane C)
- [ ] S07-008: on a Retina display, check that the switch-freeze overlay is sharp, and that it disappears within about 3 s when killall fails or the switch is slow. (lane C)
- [ ] S07-011 / S05-006: with a Custom Dock and live widgets visible, let the displays sleep (or switch user) and confirm in Activity Monitor or Instruments (Energy) that MyDock has no periodic wake-ups until wake; check that reveal and widgets resume after wake. (lane C)
- [ ] S07-012: launch and quit an app while the Custom Dock is visible and confirm in Instruments (Hangs) that the resize causes no main-thread block. (lane C)
- [ ] S07-014: with auto-hide off, enter a full-screen app and confirm the Custom Dock does not cover it; with auto-hide on, confirm it still reveals at the edge in full screen. (lane C)
- [ ] S07-018: open and close Settings and the Manager while widgets update, and confirm in Instruments (SwiftUI) that no body evaluations remain for the closed windows; reopen both and check that they rebuild correctly. (lane C)
- [ ] S05-012: on a fresh account, empty the Trash and use a Now Playing control the first time, and wait more than 8 s at the Automation consent prompt; the action must still complete. (lane C)
- [ ] S05-017: with a VPN connected, compare the Network face with Activity Monitor's Network totals; they must not be doubled. (lane C)
- [ ] S20-019: on macOS 14 and 26, with Terminal frontmost, choose Settings… and Manage Docks… from the MyDock status menu; the window comes to the front. Trigger a native Dock switch failure; the alert comes forward. (lane C)
- [ ] S07-022: with an auto-hidden Custom Dock, open a Picker in Settings and then the MyDock status menu; the Dock stays hidden. Right-click a Dock tile and open a picker in a widget popout; the Dock stays shown while the menu is open. With VoiceOver, open a tile's context menu (VO-Shift-M); the Dock stays shown. (lane C)
- [ ] S07-019: open the status menu after renaming a Dock, switching Docks and changing an automatic switching rule; it shows the current state, the checkmark and the 'Switched by rule' line. Drag the Dock size slider; the menu bar item does not flicker. Finish onboarding; MyDock becomes an accessory app. (lane C)
- [ ] S07-025: hover a running app with window previews on, then let the auto-hidden Dock hide; hovering again recaptures the thumbnails. Previews still show on quick re-hover while the Dock stays visible. (lane C)
- [ ] S07-026: move and resize the workspace window, quit and relaunch MyDock; the window reopens at the same frame. Open About and What's New; each opens once with its content. (lane C)
- [ ] S07-024: make Application Support read-only, edit a Dock and quit; choose Retry Save twice and check that the alert comes back each time with the reason; Quit Without Saving quits and Cancel Quit cancels. (lane C)
- [ ] S05-030: play a track in Music with the Now Playing popout open; the elapsed time and progress advance every second and pause with playback. (lane C)
- [ ] S05-029: press Play/Pause and Next in the popout repeatedly; the state updates right after each command. (lane C)
- [ ] S05-033: add a folder that contains a symlink to another folder; the link sorts with the folders, shows a chevron and opens its contents. (lane C)
- [ ] S05-028: compare the System Activity memory and disk readings with Activity Monitor (Memory Used) and Finder (available). (lane C)
- [ ] S05-020: with app badges on, Mail badge counts still appear and update; they stop while the displays sleep. (lane C)
- [ ] S05-032: open Add Item twice within a minute; the second open shows apps immediately. Install an app into /Applications and reopen; it appears. (lane C)
- [ ] S05-019: with window previews off, ~/Library/Caches/<bundle id>/WindowPreviews is not created on launch. (lane C)
- [ ] S07-023: with the system set to a 12-hour clock, a time-window rule reads like '9:00 AM–5:00 PM' in Settings and the status menu. (lane C)
- [ ] S06-004: Instruments SwiftUI + Time Profiler while moving the pointer across a 30-item Dock and while idle with badges on; body evaluations and main-thread time should drop versus 2ce3fbb. (lane D)
- [ ] S06-005: add a PerformanceSignposts interval around RunningApplicationMenuSection.inlineWindows; confirm it fires only when a tile menu opens and stays under 0.35 s for an app with more than 30 windows. (lane D)
- [ ] S06-007: log onAppear in DockFileThumbnailView, open and close a widget popout, confirm no thumbnail reloads; confirm drags are still refused while a popout is open. (lane D)
- [ ] S06-008: Midnight material, System theme, light Mac appearance: open a Weather popout and confirm popover chrome and text are both dark. (lane D)
- [ ] S06-009/S06-010: VoiceOver on the popout tab bar (selected tab announced, close button reachable) and on Dock tiles (Running, Badge, Saved location unavailable, folder/link names, selected anchor). (lane D)
- [ ] S06-012/S06-022: right-click app, folder, link and widget tiles; check order, dividers and native checkmarks for Switch Profile, Icon Color and Choose Icon. (lane D)
- [ ] S06-013/S20-010: with Safari frontmost, right-click a Dock link > Rename Link… and type immediately; text lands in the field. Repeat for Add Web Link…, Force Quit… and a Window unavailable alert. (lane D)
- [ ] S06-014: on macOS 13 magnification stays off with no clipped tiles; on macOS 14+ magnified tiles still grow past the scroll viewport. (lane D)
- [ ] S06-023: open widgets A and B as tabs anchored on A, close tab A, confirm B stays open on its own tile. (lane D)
- [ ] S06-019: Increase Contrast and Reduce Transparency on: check separators, resize grip, jump buttons, reveal handle and minimized-window tiles. (lane D)
- [ ] S08-001: in Dark Mode, check that the glyphs on active toggles (Now Playing playing, Stopwatch running, a quick tool) and every Color-style icon are dark on the pale family fill; check the Auto accent swatch 'A'; check that the Orange profile accent shows a dark glyph. (lane E)
- [ ] S08-004: with the Tile/Glass Dock visible, a running Stopwatch/Focus Timer ticks each second, a target Countdown more than 1 h away updates each minute and shows seconds in its last hour, a finished timer stops ticking, and a Sticky Note/Calculator face causes no periodic redraws (Instruments: SwiftUI view body counts). (lane E)
- [ ] S08-005/S08-020: with VoiceOver, check that icon-only quick tools read their names, timers/weather/disk/world clock read 'name, value', and removing a checklist item announces 'Undo available' and keeps Undo for about 30 s. (lane E)
- [ ] S08-006: with a city set, go offline for more than 3 h (or set the clock forward): the Weather face greys the temperature and shows the orange dot; a new widget shows 'Loading' before its first forecast. (lane E)
- [ ] S08-008: on the Tile surface, check that module corners follow the Dock corner-radius setting (concentric), hover lifts slightly (no lift with Reduce Motion), and the Reduce Transparency fill and Increase Contrast edge match the other surfaces. (lane E)
- [ ] S09-006: drop a file on the AirDrop tile: the sharing picker opens anchored on the tile, with no 'Modifying state during view update' runtime warning. (lane E)
- [ ] S09-007: on a Mac with purgeable data, check that the Disk Space hero matches Finder > Get Info 'Available' for the home volume. (lane E)
- [ ] S09-010/S09-011: in the World Clock, Shortcuts, Countdown and Focus Timer popouts, check that settings open from the single disclosure; leave a 1-minute Countdown/Focus session running with the popout open and confirm it stops at 0:00, shows Complete and disables Pause. (lane E)
- [ ] S08-019: check that the Appearance settings and Onboarding Dock previews still size correctly. (lane E)
- [ ] S08-021: with VoiceOver on, hover a Dock app with window previews while windows load. VoiceOver should say 'Loading windows', not a generic progress indicator. (lane E)
- [ ] S08-024: set system Light, Dock theme Dark and material Solid, then turn on Reduce Transparency. The Dock surface should be dark, and widget accents (for example a running timer glyph) should use the dark variants. Repeat with system Dark and Dock theme Light. If the accents are wrong, set panel.appearance from DockColorSchemePolicy in CustomDockWindowController. (lane E)
- [ ] S09-015/S09-016: on a MacBook, check the Battery popout and face VoiceOver on battery ('On battery'), plugged in and charging ('Charging'), and plugged in but held by Optimized Battery Charging or full ('Not charging' or 'Charged'). (lane E)
- [ ] S09-025: with Finder automation denied for MyDock, choose Empty Trash… and confirm. The alert should offer 'Open Automation Settings' and open Privacy & Security → Automation. With items only in an external drive's Trash, Empty Trash should be enabled. (lane E)
- [ ] S09-026/S09-027: queue a file and a link in the AirDrop popout. 'Send with AirDrop' should open the AirDrop sheet, and 'More…' should open the sharing picker anchored to the button. Drop a file on the Dock tile: the AirDrop sheet should open. Drop a mailto: link: the Mac should beep and nothing open. (lane E)
- [ ] S10-011: with Calendar.app running and not running, on a day that differs from the icon artwork, compare the MyDock Calendar tile with the Apple Dock tile. (lane F)
- [ ] S10-016: play a 3:30 track in Spotify and check the Now Playing popout shows 3:30 and a moving bar; set Region to Germany and check Music still parses. (lane F)
- [ ] S10-006: during an iCloud calendar sync, check one Calendar/Reminders refresh per burst (Console/Instruments), none while the Dock is hidden with no popout open, and one after showing the Dock. (lane F)
- [ ] S10-014: in an isolated validation session, check the folder popout Open/Reveal and Now Playing Open player do nothing; on a Mac without Spotify, check the popout says Spotify is not installed. (lane F)
- [ ] S10-012: with VoiceOver, check the folder popout header reads Back, Open in Finder and Close Folder, and Command-[ goes up a level. (lane F)
- [ ] S10-009: magnify the Dock over file tiles and check that thumbnails stay sharp and no per-frame stat shows in Instruments. (lane F)
- [ ] S12-007: run Scan Folders and check that the Home, Applications and Library totals are disjoint and that Home reaches Movies, Music and Pictures. (lane F)
- [ ] S12-008: on clean macOS 14 and 15 user accounts, click System Activity > Scan Folders; record each Desktop/Documents/Downloads prompt and confirm it shows the new purpose text; deny one and confirm the result lists it as skipped. (lane F)
- [ ] S10-017: play a track and a podcast over an hour in Music and Spotify; the Now Playing popout time advances every second, stops on pause, shows h:mm:ss, and resyncs after a seek. (lane F)
- [ ] S10-018: with Calendar access not yet requested (tccutil reset Calendar), a Calendar module in the wide layout reads 'Calendar / Allow access', not 'Unavailable'. (lane F)
- [ ] S10-021/S10-034: complete a reminder and remove an alarm; each Undo disappears after about 15 seconds; undoing an alarm removal reschedules its notification (check with a near-future alarm). (lane F)
- [ ] S10-024: with saving disabled, change a Calendar/Reminders/Now Playing setting and confirm the control keeps the saved value and a warning caption explains why; drop a file on a full File Shelf and confirm the drop is refused. (lane F)
- [ ] S10-029: click and press Return on a File Shelf row; the file opens; a missing file's row is dimmed and Locate… still works. (lane F)
- [ ] S10-035: open a Dock folder; check the circle buttons, Back with Command-[, VoiceOver labels, scrolling a large folder without hitches, and Increase Contrast. (lane F)
- [ ] S11-017: open the AI Activity popout with and without Customize; the header shows freshness and one refresh circle. (lane F)
- [ ] S11-019: open the Yahoo Finance link for TSCO.LON, SHOP.TRT and RELIANCE.BSE in a browser and confirm the quote pages resolve. (lane F)
- [ ] Audio Output: open the popout, Tab to the volume slider, press the arrow keys, then press the hardware volume keys; the slider must follow the hardware volume. Repeat with VoiceOver VO-Up/VO-Down. (lane F)
- [ ] Audio Output: open Customize in the Dock popout; device list, volume, mute and any error stay visible, only the hero disappears. (lane F)
- [ ] System Activity popout on a healthy Mac: Memory pressure reads 'Normal' immediately instead of 'Awaiting event'. (lane F)
- [ ] System Activity with the Network section: auto-hide the Dock during sampling and show it again; the first rate reads 'Warming up', and the footer turns to 'Last reading N seconds ago' if samples stop. (lane F)
- [ ] Watchlist: with VoiceOver on a ticker tab, the Actions rotor offers Move Earlier, Move Later and Remove; the settings Remove row works by keyboard. (lane F)
- [ ] Weather: switch Units to °F with the Conditions layout; wind shows mph and precipitation inches. (lane F)
- [ ] Business faces in de_DE and en_US: a negative value reads '-$2.4K' (en_US) and '2,4K €' (de_DE). (lane F)
- [ ] Shopify popout: product and traffic breakdowns render as grouped rows matching Stripe and Paddle. (lane F)
- [ ] Settings search: type focus, freeze, diagnostics, claude and integrations. The sidebar and the results list show the same pages, and choosing a result scrolls to its section (a page-only result opens the page at the top). (lane G)
- [ ] General: Add Docks from Backup… opens the preview sheet with Dock names, Name in use flags and missing items. Cancel adds nothing, and Add N Docks adds copies with the message Added N Docks. (lane G)
- [ ] Appearance: the Editing scope sits under the preview. In App defaults, Restore Factory Defaults for All Docks shows a confirmation naming the inheriting Dock count. Restore Factory Appearance on a Dock gives it its own factory appearance, and Undo restores it. (lane G)
- [ ] Appearance: drag a slider in App defaults with no Docks. The preview widgets do not flicker or reset. (lane G)
- [ ] VoiceOver: the appearance sliders read the visible percentage or points. Disclosure rows (Diagnostics, Update source, Manage API key, Privacy) read Expanded or Collapsed with a hint, and the chevron rotates (instantly with Reduce Motion). (lane G)
- [ ] Integrations: with Claude Code and Codex installed, switching apps repeatedly launches no claude or codex process more than once a minute (Activity Monitor), and leaving the page cancels an in-flight check. (lane G)
- [ ] Integrations: Remove Key… and Remove Credentials… ask for confirmation. Opening the page shows Connected without a Keychain password prompt for the secret. Collapsing Manage API key clears the typed key. (lane G)
- [ ] General: with an empty Update source, Check for Updates is enabled, opens Update source and shows the URL message without network access. (lane G)
- [ ] Dock Setup and Behavior: notes, warnings, Retry and Accessibility Settings… buttons line up with the 12 pt row inset in Light, Dark and Increase Contrast. (lane G)
- [ ] Settings banners (recovery and unsaved changes) look identical apart from their text, and the Midnight swatch matches the Midnight Dock. (lane G)
- [ ] S13-021/S20-022: in Settings search, choose 'Finish', 'Edge', 'Tint strength', 'auto-save' and 'thumbnails' on macOS 13, 14, 15 and 26. Each should scroll to its row or card on the first try, including the first open after launch, and land on Native Dock switching for auto-save. (lane G)
- [ ] S13-025: turn on Keyboard navigation, Tab through Settings > General (Back Up…, Add Docks from Backup…, Export Dock…) and a toggle row on macOS 13, 14, 15 and 26, and check that the focus ring is fully visible and not clipped by the rounded GroupedSection. (lane G)
- [ ] S13-018: with Accessibility off, open Settings > Behavior and check that one warning note shows. Grant access in System Settings and switch back to MyDock: the note should disappear and Permissions should show Granted without pressing anything. (lane G)
- [ ] S13-017/S13-016: with VoiceOver, check that picker rows (Mode, Reveal effect) read the title once, the AI account row says Signed in, and Voice Control 'Click Find Account' and 'Click Change' work. (lane G)
- [ ] S13-026: the Remove Key… and Remove Credentials… buttons in Integrations should be red, with a red outline under Increase Contrast. (lane G)
- [ ] S20-017: in an isolated validation session, Permissions rows and Hydration's Open Notification Settings must not launch System Settings. (lane G)
- [ ] S14-008: select an item, double-click the Dock title, type, press Cmd-Left, Shift-Left and Return: the caret/selection changes in the field, items do not move and no Configure sheet opens. (lane H)
- [ ] S14-009: double-click the title and confirm the field is focused; Escape keeps the old name; rename then click the canvas (or another control) and confirm the name commits as one Undo step; rename then pick another Dock in the sidebar and confirm the new name is saved. (lane H)
- [ ] S14-020: from Cmd-K choose Create New Dock, Link... and Start Workspace: X five times each, and from Add Item choose Choose Application... and Folder..., on macOS 13 and 26: the target sheet or open panel appears every time after the library closes. (lane H)
- [ ] S14-014 / S15-009: with VoiceOver on, press Down/Up in the Cmd-K and Add Item search fields and hear each highlighted result; open a widget detail with Return and confirm VoiceOver lands on its title; add it and hear 'Added' on the badge. (lane H)
- [ ] S15-008: add Small Spacer from More; the tile shows the added badge briefly (no animation under Reduce Motion) and VoiceOver says 'Small Spacer added'. (lane H)
- [ ] S15-004: with Add Item open on Apps, Command-Tab away and back within 30 s (no rescan, list and highlight stay) and after 30 s (Refresh shows progress, list stays). (lane H)
- [ ] S14-015: Return confirms and Escape cancels in Create Dock, Add/Edit Link and the preset preview. (lane H)
- [ ] S14-016: in native-only mode create a custom Dock from the sheet and from a preset: the live Dock and setup mode do not change until Activate. (lane H)
- [ ] S15-006: check the app-row added check (accent) against light, dark and Increase Contrast. (lane H)
- [ ] S15-010: In Add Item > Widgets, Tab from search to a tile, click back into the search field, press Space then Return: Space types a space, Return adds the highlighted result. (lane H)
- [ ] S15-011: Open Add Item at minimum window height, Tab onto a tile and hold Down through every section: focus stays on a tile and the grid scrolls with it (Reduce Motion on and off). (lane H)
- [ ] S15-012: Add Item > More > Link… opens the link editor every time, with Reduce Motion on and off. (lane H)
- [ ] S14-022: Apply a macOS Dock: Apply and the sidebar item are disabled until the Dock relaunch finishes, no success alert appears, the status pill shows Applied and VoiceOver announces it; a failure still alerts. (lane H)
- [ ] S14-027: In the link editor, start Fetch Site Icon then Cancel or press Escape: the spinner reads 'Fetching site icon' to VoiceOver, no error shows before typing, and reopening the editor starts clean. (lane H)
- [ ] S14-028 / S16-010: Accessibility Inspector on the Dock canvas shows a container with each tile keeping its own label; Voice Control 'Click Done' works in the Dock inspector; VoiceOver reads onboarding steps (Current/Done) and selected starter widgets. (lane H)
- [ ] S16-006: In Keyboard Shortcut, Record then press Escape: the existing shortcut stays; Cancel stops recording without closing the sheet; Delete clears. (lane H)
- [ ] S16-005: Record ⌃⌥→, ⌃⌥F5 and ⇧⌃1: they display as ⌃⌥→, ⌃⌥F5 and ⌃⇧1 (no blank glyph, no '!'). (lane H)
- [ ] S16-011: Visual pass over Keyboard Shortcut, Review Diagnostics, Start Workspace (switch row), Export/Import Dock, Create Dock, Link and Presets sheets in light/dark and Increase Contrast. (lane H)
- [ ] S14-031: Cmd-K a missing File Shelf entry, Locate… a file already on that shelf: an alert explains nothing changed. (lane H)
- [ ] S15-019: System Settings > Appearance > Show scroll bars: Always; open Add Item at 680 pt and 1040 pt wide and confirm the last tile column keeps the 24 pt trailing inset; toggle the setting while open. (lane H)
- [ ] S15-020: Keyboard navigation on; open Add Item, Tab through header, tiles and the detail: no invisible stop; Return/Space on a focused tile, Cmd-Return and Left/Right in the detail still work with the .hidden() shortcut buttons. (lane H)
- [ ] S15-018: Tab to a tile far down the Widgets list, press Return, then Escape: focus returns to that tile (scrolled into view) and the search field does not take focus; then open a detail with the mouse and press Back: the search field focuses. (lane H)
- [ ] S15-013: in the detail, with nothing focused, Left/Right change size (GalleryPagerKeys); if SizePager's onMoveCommand alone handles it, GalleryPagerKeys can be removed. (lane H)
- [ ] S15-021: a single click on a widget tile opens the detail immediately; double-click no longer adds. (lane H)
- [ ] S16-018: Start Workspace with Also switch on for a custom and for a macOS Dock: the outcome line appears in the sheet; Escape closes a finished run. (lane H)
- [ ] S16-019: Export a Dock from the Docks window: the 'Exported <name>.' alert appears after the sheet closes; a failed save then a retry clears the error. (lane H)
- [ ] S16-022: VoiceOver on, open a Dock's keyboard shortcut editor and start recording: focus announces 'Shortcut recorder' and the recorder receives the next key. (lane H)
- [ ] S14-034: lift an item on the canvas and press Escape: the drag cancels. (lane H)
- [ ] S14-033: with the Docks window key, Cmd-, opens Settings via the menu item. (lane H)
- [ ] S16-020: About window shows the app icon in the built bundle. (lane H)
- [ ] S16-021: replay setup with a saved external display unplugged: the Display picker shows 'Disconnected display'. (lane H)
- [ ] Run ./BuildMyDock.sh on a Mac: confirm build/MyDock.app is replaced only at the end, Info.plist has CFBundleDevelopmentRegion en, CFBundleVersion equals `git rev-list --count HEAD`, CFBundleSupportedPlatforms [MacOSX], and codesign --verify --deep --strict passes. Interrupt a run during icon generation and confirm the previous app still launches. (lane I)
- [ ] Run ./GenerateXcodeProject.sh, then git status: MyDock.xcodeproj is ignored and Xcode/MyDock-Info.plist is unchanged. Build in Xcode and confirm CFBundleShortVersionString and CFBundleVersion expand. (lane I)
- [ ] MYDOCK_RENDER_QA with MYDOCK_FACESA_QA=1 and MYDOCK_WIDGETSURFACE_QA=1: open facesa-faces-a-glass-light.png and widgetsurface-matrix-*-glass-light.png, confirm the last row is fully visible, and check stderr for 'may be clipped' warnings. (lane I)
- [ ] MYDOCK_FACESB_QA=1: compare facesb-popout-* (shipping-height cap, scrollable) with facesb-popout-content-* (full height); they should now differ for tall families. (lane I)
- [ ] MYDOCK_DOCKSTYLE_QA=1: confirm the Glass, Frosted, Solid and Midnight renders show the hairline edge and tint the Appearance page applies. (lane I)
- [ ] Run the MyDock Visual QA scheme once on an unlocked Mac (it probably needs @MainActor on the test class under Swift 6), fix stale labels and record the dated result in docs/RELEASE_AUDIT.md. (lane I)
- [ ] Release dry run: ReleaseMyDock.sh refuses a dirty tree, an untracked file under Sources and a missing v<version> tag. (lane I)
- [ ] On a Mac, run Scripts/RegenerateAppIcon.sh, compare the new sRGB Resources/AppIcon.icns with the old one in Finder and the Dock, then commit it, so the checked-in icon matches the updated generator. (lane I)
- [ ] Run ./BuildMyDock.sh: it should pass the SDK check on SDK 26, copy Resources/AppIcon.icns into build/MyDock.app, and the app should show the same icon as the Xcode build. (lane I)
- [ ] Run ./TestMyDock.sh: afterwards no .build/isolated-tests.* directory is left. With MYDOCK_KEEP_VALIDATION_ROOT=1 the root is kept and its path printed. (lane I)
- [ ] Run the render exports MYDOCK_SETTINGS_QA, MYDOCK_FOCUSED_QA, MYDOCK_GALLERY_QA, MYDOCK_GLASS_QA and MYDOCK_WIDGETSURFACE_QA. Check the settings-appearance-section-* PNGs each show one live section, the Add Item renders list the fixed system apps, no installed-apps.json is written, and glass-contrast-opaque.png exists. (lane I)
- [ ] Set two MYDOCK_*_QA flags with MYDOCK_RENDER_QA and confirm the export prints 'MyDock render failed: Set one render mode at a time…' and quits. (lane I)
- [x] On the first CI run after merge, check that the 'Report compiler warnings' step annotates the known warnings and that the pinned actions resolve. (lane I). Done: CI runs 40–45 resolved the pinned actions and annotated warnings (step now reports test totals too).
- [x] Run ./TestMyDock.sh on CI or a Mac: confirm the typed #expect(throws:) cases, the serialized PopoutLayoutLoopTests and the NativeFollowupTests time limit all pass on arm64 and Intel (lane I). Done: CI run 45 (`d2c9500`): 1,104 tests passed on arm64 and Intel.
- [x] Run python3 -m unittest discover -s Tests/Tooling on macOS (24 tests) (lane I). Done: CI run 45: 25 tooling tests OK.

## Tests added by the lanes

- Tests/MyDockTests/AuditLaneATests.swift: newWorldClockStartsOnAnotherPlaceInsteadOfAFixedCity (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: calculatorAcceptsTheLocaleDecimalComma (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: calculatorPercentWorksLikeAHandheldCalculator (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: timerValuesShowHoursFromOneHour (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: privacyCopyMatchesWhatBackupsContain (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: savedSearchResolvesOnlyTheShownShelfFiles (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: marketWidgetsNeedAnAPIKeyConnection (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: tokenCountsRoundBeforeChoosingTheUnit (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: hydrationHistoryPrunesOldAndExcessEntries (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: libraryDropsOnlyInvalidEntriesAndSetsUnreadableFilesAside (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: aFailedLibraryWriteDoesNotStopLaterSnapshots (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: abandonedStateTemporariesAreRemovedOnlyWhenOld (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: importPreviewDerivesPersonalDataFromTheContent (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: presentationFollowsItemsAddedAfterAnEarlierLookup (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: timerFinishesWhenTheWallClockLagsTheSleep (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: failuresNeverRetrySoonerThanTheNormalCadence (lane A)
- Tests/MyDockTests/AuditLaneATests.swift: watchlistStoppedByTheProviderLimitSaysSo (lane A)
- AuditLaneATests.privateTextExclusionAlsoReplacesAlarmTitles (lane A)
- AuditLaneATests.sanitizerClassifiesEveryWidgetField (lane A)
- AuditLaneATests.oversizedTextAndIconsLoadBoundedButAreRejectedOnWrite (lane A)
- AuditLaneATests.lockFailuresReportTheRealPOSIXError (lane A)
- AuditLaneATests.stockRangesUseFamiliarLabelsAndKeepStoredValues (lane A)
- AuditLaneATests.snippetPopoutAndPaletteFindTheSameSnippets (lane A)
- AuditLaneATests.onboardingShowsTheActualSaveError (lane A)
- AuditLaneATests.duplicatesAndRestoresGetUniqueNames (lane A)
- AuditLaneATests.restoreDuplicateAndRecoveryShareOneNewIdentityRule (lane A)
- AuditLaneATests.rejectedProfileEditsLeaveHistoryUntouched (lane A)
- AuditLaneATests.restoringFromRecoveryKeepsTheCurrentDock (lane A)
- AuditLaneATests.privateFilesAreWrittenWithPrivatePermissionsAndNoLeftovers (lane A)
- AuditLaneATests.theDraftCountLimitSaysSo (lane A)
- AuditLaneATests.oneConflictingDraftDoesNotHoldBackTheOthers (lane A)
- AuditLaneATests.libraryRetentionCapsAndPresetChecks (lane A)
- AuditLaneATests.onlyWidgetsThatScheduleNotificationsDeclareThePermission (lane A)
- AuditLaneBStripeTests.subscriptionsOverBudgetLeaveBalanceAndRevenuePublished (lane B)
- AuditLaneBStripeTests.balanceTransactionsAreRequestedPerRevenueTypeWithAPinnedVersion (lane B)
- AuditLaneBStripeTests.snapshotsSavedBeforeUnavailableMetricsDecodeAsFullyAvailable (lane B)
- AuditLaneBTransferTests.deadlineThatPassesMidStreamStopsTheTransfer (lane B)
- AuditLaneBFaviconTests.largestFrameIsUsedWhenTheSmallestIsListedFirst (lane B)
- AuditLaneBConnectionDirectoryTests.directoryInsertsReplacesUpdatesAndRemovesByIdentifier (lane B)
- AuditLaneBActivityTests.oversizedClaudeLogIsReadFromItsNewestRecords (lane B)
- AuditLaneBActivityTests.oversizedCodexLogUsesItsFirstReadCounterAsABaseline (lane B)
- AuditLaneBActivityTests.possiblyOverstatedTotalsAreMarkedAsApproximateNotAsALowerBound (lane B)
- AuditLaneBActivityTests.timestampsParseWithAndWithoutFractionalSeconds (lane B)
- AuditLaneBCodexTests.serverThatExitsBeforeReplyingIsReportedAsUnsupported (lane B)
- AuditLaneBCodexTests.missingMethodIsUnsupportedAndAnAuthenticationErrorStillAsksToSignIn (lane B)
- AuditLaneBCodexTests.cancellingABackgroundRequestStopsWaitingForTheServer (lane B)
- AuditLaneBCodexTests.unsupportedCodexIsShownAsUnavailableRatherThanSetup (lane B)
- AuditLaneBCodexTests.slowReaderDoesNotHoldBackTheOthers (lane B)
- AuditLaneBClaudeLimitsTests.turnOffRestoresTheWrappedStatusLineAndRemovesTheSnapshot (lane B)
- AuditLaneBClaudeLimitsTests.aStatusLineMyDockAddedStaysEmptyAndIsRemovedOnTurnOff (lane B)
- AuditLaneBClaudeLimitsTests.firstVersionBridgesAreReadAndUpgradedAroundTheCommandTheyWrap (lane B)
- AuditLaneBDiscoveryTests.versionManagerAndInstallerLocationsAreSearchedNewestNodeFirst (lane B)
- AuditLaneBAlarmTests.everyDayAlarmUsesOneDailyRequest (lane B)
- AuditLaneBAlarmTests.everyDayAlarmScheduledPerWeekdayStillCountsAsScheduled (lane B)
- AuditLaneBCalendarTests.selectionNeverWidensToEveryCalendar (lane B)
- AuditLaneBCalendarTests.refreshTokenTakenBeforeASelectionChangeIsNotCurrent (lane B)
- AuditLaneBCalendarTests.summaryNamesSelectedCalendarsAndCountsMissingOnes (lane B)
- AuditLaneBAppFolderTests.identityFollowsTheURLAndEqualityIgnoresTheDerivedPath (lane B)
- ProfileStoreTests.aiLimitsCollectorCancellationReachesInFlightReaders (replaces aiLimitsCollectorStopsStartingReadersAfterCancellation) (lane B)
- AuditLaneBFaviconTests.formatsOutsideTheIconAllowlistAreRefused (lane B)
- AuditLaneBFaviconTests.connectedAddressLiteralsArePublicOnlyWhenRoutable (lane B)
- AuditLaneBFaviconTests.responseChecksAreSharedByBothTransports (lane B)
- AuditLaneBProviderCopyTests.keychainFailuresNameTheOperationThatFailed (lane B)
- AuditLaneBProviderCopyTests.transferFailuresAreNotReportedAsUnreadableData (lane B)
- AuditLaneBProviderCopyTests.weatherThrottlingAndUndecodableDataHaveTheirOwnErrors (lane B)
- AuditLaneBProviderCopyTests.copilotBodyOverTheLimitIsReportedAsTooLarge (lane B)
- AuditLaneBProviderCopyTests.unchangedShopifyCredentialStillRefusesARemovedConnection (lane B)
- AuditLaneBWeatherTests.nullHourlyValuesSkipOnlyThoseHours (lane B)
- AuditLaneBAIPart2Tests.windowTitlesAgreeAcrossProviders (lane B)
- AuditLaneBAIPart2Tests.tokenSumsSaturateInsteadOfTrapping (lane B)
- AuditLaneBAIPart2Tests.serverRequestWithOurIdIsNotTakenAsTheReplyAndClosedStderrIsIgnored (lane B)
- AuditLaneBAIPart2Tests.symlinkedClaudeSettingsAreExplainedAndRewritesKeepSlashes (lane B)
- AuditLaneBNotificationTests.oneTimeAlarmInASkippedHourKeepsItsHourTheNextDay (lane B)
- AuditLaneBNotificationTests.provisionalDeliveryCountsAsAuthorizedEverywhere (lane B)
- AuditLaneBNotificationTests.alarmSchedulesUnderProvisionalAuthorization (lane B)
- AuditLaneBNotificationTests.endingAnItemForgetsItsOperation (lane B)
- AuditLaneBNotificationTests.hydrationIntervalIsClampedToTheSupportedRangeOnDecode (lane B)
- AuditLaneBShortcutTests.shortcutNameStartingWithADashIsPassedAfterTheOptionTerminator (lane B)
- AuditLaneBShortcutTests.catalogFailureDetailIsBoundedToTwoShortLines (lane B)
- AuditLaneBNextMeetingTests.imminentMeetingBeatsALongBlockThatStartedEarlier (lane B)
- AuditLaneBNextMeetingTests.freeEventsAreNeverTheNextMeeting (lane B)
- AIAccountTests.codexAccountDiscoveryUsesStructuredAccountState (API-key case added) (lane B)
- AuditLaneCTests.nearlyDueSubscriptionsShareAWakeUp (lane C)
- AuditLaneCTests.anAwaySessionStopsTicksUntilItReturns (lane C)
- AuditLaneCTests.pointerBurstsRunOneRevealSample (lane C)
- AuditLaneCTests.revealSamplingPausesWhileTheSessionIsAway (lane C)
- AuditLaneCTests.partialWindowSamplesKeepTheSlowAppsWindows (lane C)
- AuditLaneCTests.theMonitorKeepsMinimizedTilesThroughAPartialSample (lane C)
- AuditLaneCTests.windowIDsSurviveReorderingAndRetitling (lane C)
- AuditLaneCTests.collidingWindowHashesStillGiveUniqueIDs (lane C)
- AuditLaneCTests.sameTitledWindowsOverTimeNeverShareADiskPreview (lane C)
- AuditLaneCTests.turningPreviewRetentionOffPurgesDiskAndMemory (lane C)
- AuditLaneCTests.losingScreenRecordingPurgesTheDiskCache (lane C)
- AuditLaneCTests.replacingTheWatchedTrashDetachesTheWatcher (lane C)
- AuditLaneCTests.timeoutsGetTheirOwnPlainMessage (lane C)
- AuditLaneCTests.artworkHexDecodesOverBytes (lane C)
- AuditLaneCTests.vpnTunnelTrafficIsNotCountedTwice (lane C)
- AuditLaneCTests.aLatePanelEnterWhileIdleDoesNotHoldTheNextPreviewOpen (lane C)
- AuditLaneCTests.onlyAnAutoHidingDockJoinsFullScreenSpaces (lane C)
- AuditLaneCTests.failedApplyAndFailedRollbackKeepTheJournalForRecovery (lane C)
- AuditLaneCTests.recoveringAnInterruptedChangeRestoresTheSnapshot (lane C)
- AuditLaneCTests.aDockThatDropsTheLayoutIsRestoredAndSaysSo (lane C)
- AuditLaneCTests.quickSuccessiveMenuPicksWriteOnlyTheNewestDock (lane C)
- AuditLaneCTests.newAppTilesNeverInheritAnotherAppsMetadata (lane C)
- AuditLaneCTests.appsAlreadyInTheDockKeepTheirOwnTile (lane C)
- AuditLaneCTests.aPendingJournalAtLaunchRequiresRecovery (lane C)
- AuditLaneCTests.thePreviewCacheCreatesNoDirectoryUntilItStores (lane C)
- AuditLaneCTests.linkItemsOpenOnlyWebAddresses (lane C)
- AuditLaneCTests.oneUnreadableShortcutDropsOnlyItself (lane C)
- AuditLaneCTests.memoryAndDiskReadingsMatchActivityMonitorAndFinder (lane C)
- AuditLaneCTests.aPlayingTrackAdvancesBetweenReads (lane C)
- AuditLaneCTests.cancellingWhileTheLastTargetOpensStillFinishes (lane C)
- AuditLaneCTests.aCancelledStartTaskStopsTheRemainingTargets (lane C)
- AuditLaneCTests.installedAppScansAreReusedOnlyWhileRecentAndUnchanged (lane C)
- AuditLaneCTests.symlinkedFoldersSortAndBrowseLikeFolders (lane C)
- AuditLaneCTests.editsThatChangeNothingVisibleLeaveTheStatusButtonAlone (lane C)
- AuditLaneCTests.onlyTheDocksOwnMenusKeepItShown (lane C)
- AuditLaneCTests.expiredThumbnailsArePrunedWithoutATouch (lane C)
- AuditLaneCTests.interruptedRecoveryFailuresAreDiagnosed (lane C)
- AudioOutputTests.devicesPluggedInElsewhereAppearAfterTheChangeNotification (lane C)
- AudioOutputTests.changesAfterTheDockHidesAreIgnored (lane C)
- AudioOutputTests.hardwareErrorsClearTheListAndSayWhy (lane C)
- AudioOutputTests.aRefusedSwitchKeepsItsErrorAfterTheReadBack (lane C)
- AutomaticSwitchingTests.aClockChangeReArmsTheTimerAtTheNewBoundary (lane C)
- AutomaticSwitchingTests.stoppingClearsTheTimerTheStatusAndEveryFeed (lane C)
- AutomaticSwitchingTests.aManualSwitchIsSeenThroughTheStoreWithoutAnExplicitReevaluate (lane C)
- AuditLaneDTests.recentAppsShowTheirRunningStateWhenTheRunningSectionIsHidden (lane D)
- AuditLaneDTests.pinnedAppsUseTheMatchedRunningCopiesAndRunningEntriesAreRunning (lane D)
- AuditLaneDTests.tileValueReadsRunningMissingAndBadgeState (lane D)
- AuditLaneDTests.typedDropsMoveUnpinAndPinRuntimeApps (lane D)
- AuditLaneDTests.bundleOnlyPayloadsPinOnlyAnUnambiguousCopy (lane D)
- AuditLaneDTests.externalDropsAddExistingFilesAndSafeLinksOnly (lane D)
- AuditLaneDTests.externalDropsAreBounded (lane D)
- AuditLaneDTests.openWithDropsRejectAddressesCarryingCredentials (lane D)
- AuditLaneDTests.recentsRecordRegularAppsOtherThanMyDockAndPruneMissingBundles (lane D)
- AuditLaneDTests.accessibilityMessagingNeverWaitsPastTheDeadline (lane D)
- AuditLaneDTests.dockSizeBoundsAreSharedByLayoutAndResizing (lane D)
- AuditLaneDTests.boundaryEntriesKeepTheirStableIDs (lane D)
- AuditLaneDTests.magnificationRunsWhereTheScrollViewDoesNotClipIt (lane D)
- AuditLaneDTests.increaseContrastStrengthensDockSeparators (lane D)
- ProfileStoreTests.dockSurfaceMetricsMatchRenderedTileGeometry (rewritten against DockRenderModel.contentLength) (lane D)
- Tests/MyDockTests/AuditLaneETests.swift: filledGlyphsKeepThreeToOneContrastInBothAppearances, localFacesTickOnlyAsOftenAsTheirTextChanges, weatherFaceMarksOldOrFutureForecastsAndLoadsBeforeFailing, futureTimestampsAreNeverFreshOrDescribedAsComingUp, aWatchlistWithANeverLoadedTickerHasNoCompleteReading, faceNumbersFollowTheLocaleDecimalSeparator, undoOfferIsMeasuredFromRemovalAndLastsLongerWithVoiceOver, countdownHeroReadsStatesAsStatusAndNumbersWithContext, hydrationOffersOneActionThatMatchesItsSettings, savingAnUnchangedNoteWritesNothing (lane E)
- AuditLaneETests.anUnchangedMarketPriceIsNotColouredAsAGain (lane E)
- AuditLaneETests.batteryStatusUsesTheWordsMacOSUses (lane E)
- AuditLaneETests.batteryPopoutLeadsWithTheMacAndColoursOnlyLowCharge (lane E)
- AuditLaneETests.worldClockRowsUseAPluralisedShortDayOffset (lane E)
- AuditLaneETests.percentagesAndVolumesFollowTheLocale (lane E)
- AuditLaneETests.stickyNoteLimitIsOneShortLineInByteUnits (lane E)
- AuditLaneETests.usageBarsShareOneMeterAtTwoHeights (lane E)
- AuditLaneETests.emptyTrashCoversEveryVolumeAndOffersAutomationOnDenial (lane E)
- AuditLaneETests.airDropDropsKeepOnlyShareableItems (lane E)
- AuditLaneETests.aDarkDockDrawsTheDarkWindowBackgroundWhateverTheSystemAppearance (lane E)
- Tests/MyDockTests/AuditLaneFTests.swift: deletedSelectionIsNotReportedAsAPermissionProblem, eventKitSignalsCoalesceIntoOneRefresh, eventKitSignalWaitsWhileNothingIsVisible, unnamedSnippetTextNeverReachesTheDockFace, shelfAvailabilityResolvesEachEntryOnce, thumbnailBucketsChangeOnlyAtResolutionSteps, calendarIconPolicyTrustsTheSavedIdentifier, alarmChipsFollowTheLocaleWeekAndStayDistinct, marketFaceChangeUsesTheTestedFormat, weatherStalenessMatchesThePopoutRule, weatherForecastPublishesAsARuntimeReading, estimatedTokenTotalsAreMarked, retainedLimitReadingShowsItsOwnSuccessTime, unconnectedBusinessWidgetOffersSavedConnections, storageScanSkipsSubtreesCountedAsTheirOwnLocation (lane F)
- AuditLaneFTests.networkRatesShareOneClampAndNeverTrap (lane F)
- AuditLaneFTests.nowPlayingTicksAndShowsHours (lane F)
- AuditLaneFTests.calendarModuleAsksForAccessBeforeItWasRequested (lane F)
- AuditLaneFTests.ongoingMultiDayEventsNameTheirEndDay (lane F)
- AuditLaneFTests.calendarHeroEventLeadsTheRows (lane F)
- AuditLaneFTests.calendarReadScopeChangesOnlyForWhatIsRead (lane F)
- AuditLaneFTests.remindersModuleNamesItsList (lane F)
- AuditLaneFTests.rejectedConfigurationChangesAreReported (lane F)
- AuditLaneFTests.calendarFixtureAllDayEventSpansWholeDays (lane F)
- AuditLaneFTests.remindersFixtureStatesMatchTheirNames (lane F)
- AuditLaneFTests.savedCollectionNamesAreClampedByBytes (lane F)
- AuditLaneFTests.shelfReportsFilesItDidNotAdd (lane F)
- AuditLaneFTests.removedAlarmRestoresInPlace (lane F)
- AuditLaneFTests.narrowTokenValuesPromoteAtScaleBoundaries (lane F)
- AuditLaneFTests.limitWindowTitlesAreWholeWords (lane F)
- AuditLaneFTests.marketHeroLabelsItsCloseAndColoursByRange (lane F)
- AuditLaneFTests.yahooLinksUseYahooExchangeSuffixes (lane F)
- AuditLaneFTests.decodedPickerValuesAlwaysHaveAMatchingOption (lane F)
- AuditLaneFTests.weatherConditionsUseTheTemperatureUnitsSystem (lane F)
- AuditLaneFTests.cachedWeatherHourFormattersKeepTheirPlace (lane F)
- AuditLaneFTests.memoryPressureSeedsFromTheKernelLevel (lane F)
- AuditLaneFTests.systemFaceAndHeroShareStateColourAndSpeakTheSecondaryMetric (lane F)
- AuditLaneFTests.uptimeAndFileCountsFollowTheLocale (lane F)
- AuditLaneFTests.staleNetworkFooterNeverSaysJustNow (lane F)
- AuditLaneFTests.compactCurrencyFollowsTheLocaleAndPromotesAfterRounding (lane F)
- AuditLaneFTests.pointInTimeMetricsDoNotClaimAPeriod (lane F)
- AuditLaneFTests.claudeLimitsBridgeUsesPlutil (lane F)
- Tests/MyDockTests/AuditLaneGTests.swift: everySearchTermFindsAResultOnItsPage (lane G)
- Tests/MyDockTests/AuditLaneGTests.swift: sidebarPagesMatchResultPages (lane G)
- Tests/MyDockTests/AuditLaneGTests.swift: previouslyUnsearchableControlsAreFound (lane G)
- Tests/MyDockTests/AuditLaneGTests.swift: pageTitleOnlyMatchListsThePage (lane G)
- Tests/MyDockTests/AuditLaneGTests.swift: appearancePreviewSampleIsStable (lane G)
- Tests/MyDockTests/AuditLaneGTests.swift: factoryResetMessageCountsInheritingDocks (lane G)
- Tests/MyDockTests/AuditLaneGTests.swift: backupRestorePreviewFlagsExistingNamesAndCountsDocks (lane G)
- Tests/MyDockTests/AuditLaneGTests.swift: accountActivationRecheckIsThrottled (lane G)
- Tests/MyDockTests/AuditLaneGTests.swift: tileSizeBoundsAreShared (lane G)
- AuditLaneGTests.permissionRowsDeriveSummaryFromState (lane G)
- AuditLaneGTests.systemSettingsPanesAreUniqueURLs (lane G)
- AuditLaneGTests.connectionKindsMapToWidgetKindsAndReferences (lane G)
- AuditLaneGTests.automaticSwitchRuleProblemsAreReported (lane G)
- AuditLaneGTests.deletedAutomaticSwitchRuleIsRestoredInPlace (lane G)
- AuditLaneGTests.restoringARuleRespectsTheCap (lane G)
- AuditLaneGTests.searchEntriesPointAtTheRightCards (lane G)
- Tests/MyDockTests/AuditLaneHTests.swift: anEmptyDockNameIsASaveFailureNotAMergeConflict, saveFeedbackCopyComesFromItsState, browseActionsFollowTheDockKind, creatingADockWithoutActivationLeavesTheLiveDockAlone, folderCustomizationIsNormalisedTheSameWayEverywhere, gridRowsStartANewRowForSuggestedAndEverySection, arrowKeysFollowTheRowsAsDrawn, addedIdentitiesMatchThePerItemCheck (lane H)
- AuditLaneHTests.aSetupSaveThatThrowsIsReportedEvenWhenSetupWasCompletedBefore (lane H)
- AuditLaneHTests.aReplacementDockStartsWithTrash (lane H)
- AuditLaneHTests.shortcutLabelsNameSpecialKeysAndIgnoreShift (lane H)
- AuditLaneHTests.presetsShareTheDockExportFormatAndStillReadOldPresets (lane H)
- AuditLaneHTests.savingAPresetReportsALibraryThatCannotBeWritten (lane H)
- AuditLaneHTests.locateReportsEveryRepairThatChangedNothing (lane H)
- AuditLaneHTests.droppedURLsAreClassifiedBySchemeAndDockKind (lane H)
- AuditLaneHTests.tileSizeBoundsAreShared (lane H)
- AuditLaneHTests.settingsCopyCallsASavedArrangementADock (lane H)
- AuditLaneHTests.appsAndMoreMatchEveryQueryWordLikeWidgets (lane H)
- AuditLaneHTests.duplicateAppsWithoutAVersionShowOnlyTheirFolder (lane H)
- AuditLaneHTests.galleryPreviewsFallBackInsteadOfIndexingAnEmptyFamily (lane H)
- AuditLaneHTests.galleryCopyMatchesSingleClickOpeningAndOneNoDockLine (lane H)
- AuditLaneHTests.starterPresetFallbackNotesNameEveryPreferredApp (lane H)
- AuditLaneHTests.shortcutCatalogListsTheGalleryKeys (lane H)
- ProductPolishTests.patchReleaseWithTheSameTableIsNotShownAgain (lane H)
- Tests/MyDockTests/AuditLaneITests.swift: AuditLaneIGate helper and gateReleasedBeforeHoldDoesNotBlock (lane I)
- Tests/Tooling/test_info_plist_parity.py: plist matches project.yml, usage descriptions match, BuildMyDock.sh fills every placeholder (lane I)
- Tests/Tooling/test_readme_widgets.py: README widget table equals WidgetRegistry.all by category (lane I)
- Tests/Tooling/test_release_manifest.py: test_ci_records_untracked_sources, test_release_refuses_untracked_sources_and_tracked_changes (lane I)
- Strengthened: BoundedSubprocessCaptureTests.cancellingTheAsyncRunnerTerminatesItsChild (PID reaped), AIAccountTests.invalidAndSymlinkedClaudeSettingsAreNeverOverwritten (valid-JSON symlink), RoadmapRegressionTests.cancelledRefreshWaiterDoesNotBlockFollowingWork (queued waiter) (lane I)
- Tests/MyDockTests/AuditLaneITests.swift: renderModeIsUniqueAndTwoFlagsAreRefused (lane I)
- Tests/MyDockTests/AuditLaneITests.swift: widgetQAMatrixNarrowsByStateRatherThanItsDescription (lane I)
- Tests/MyDockTests/AuditLaneITests.swift: renderFixtureAppsAreFixedSystemApps (lane I)
- Tests/Tooling/test_release_manifest.py: test_failing_required_command_reports_its_output (lane I)
- PX1DockEssentialsTests.recentsTrackingNeverRunsUnderIsolation now asserts !isObserving (lane I)
- FolderContentsReaderTests.cancellingTheAsyncLoadReachesTheEnumeration (deterministic, injected work) (lane I)
- N2UtilityRepairTests.staleBookmarksRegenerateOnlyWhenFileResolves (injected stale resolution) (lane I)
- RedesignWidgetChromeTests.everyFamilyWidthLookupMatchesItsOptions (lane I)
- test_release_manifest: test_dmg_matching_app_is_recorded_and_detached, test_dmg_mismatch_refuses_output_and_still_detaches, test_other_archive_types_are_refused, test_zip_missing_app_file_refuses_output, test_zip_macosx_bookkeeping_is_accepted, test_missing_deployment_target_refuses_output (lane I)

## Every finding

| ID | Sev | Category | Finding | File | Outcome | Commit |
|---|---|---|---|---|---|---|
| S04-001 | P0 | reliability | CodexAccountRPC writes to the app-server's stdin without SIGPIPE protection; a server that exits mid-session terminates MyDock | `Sources/MyDock/SystemServices/CodexAccountRPC.swift` | Fixed | d03a994 |
| S06-001 | P0 | bug | Pinning a running or recent app keeps its deterministic runtime ID, which can later crash the Dock body on a duplicate key | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | d03a994 |
| S18-001 | P0 | test-quality | Isolation tests perform real Dock-preference and Keychain writes when the env-var isolation is absent | `Tests/MyDockTests/RuntimeIsolationTests.swift` | Fixed | ab84109 |
| S01-001 | P1 | reliability | Test isolation is environment-only and fails open; the isolation test itself then writes Apple's Dock prefs and the Keychain | `Sources/MyDock/Core/AppRuntimeEnvironment.swift` | Fixed | 1b55888 |
| S01-002 | P1 | persistence | One unknown enum value or out-of-range field anywhere sets the whole state.json aside and starts with no Docks; schema version is never bumped | `Sources/MyDock/Models/DockModels.swift` | Fixed | 2ec0bba |
| S02-001 | P1 | privacy | Import Dock carries account IDs and embedded provider readings from the source file | `Sources/MyDock/Backup/PortableDockPackage.swift` | Fixed | 1b55888 |
| S03-001 | P1 | bug | Shopify orders query requests far more than Shopify's 1,000-point single-query cost limit | `Sources/MyDock/SystemServices/ShopifyDataService.swift` | Fixed | 531d266 |
| S03-002 | P1 | bug | Hardened-runtime release has no Location entitlement, so current-location weather cannot work in the notarized app | `Xcode/MyDock.entitlements` | Fixed | 1b55888 |
| S03-003 | P1 | bug | Minor-unit conversion ignores three-decimal currencies (and UGX), so Stripe amounts in KWD/BHD/JOD/OMR/TND show 10x too large | `Sources/MyDock/SystemServices/FinancialCurrencyFormatter.swift` | Fixed | 1b55888 |
| S03-004 | P1 | privacy | Copilot billing (Bearer token) and weather (coordinates) requests use URLSession.shared and its persistent disk URLCache | `Sources/MyDock/SystemServices/GitHubCopilotService.swift` | Fixed | 1b55888 |
| S04-002 | P1 | bug | Calendar event snapshots of a recurring event share one id, so ForEach gets duplicate identities | `Sources/MyDock/SystemServices/CalendarRemindersService.swift` | Fixed | 1b55888 |
| S05-001 | P1 | bug | Audio Output face never refreshes when the Dock uses auto-hide or hide-when-Apple-Dock-appears | `Sources/MyDock/DockManagement/CustomDockWindowController.swift` | Fixed | 1b55888 |
| S05-002 | P1 | bug | Audio Output volume and mute readings go stale: no Core Audio listener for the current device's volume or mute | `Sources/MyDock/SystemServices/AudioOutputService.swift` | Fixed | 2e1b309 |
| S05-003 | P1 | bug | Spotify track duration is read in milliseconds and treated as seconds | `Sources/MyDock/SystemServices/NowPlayingService.swift` | Fixed | 1b55888 |
| S05-004 | P1 | bug | Now Playing parsing breaks on locales that use a decimal comma | `Sources/MyDock/SystemServices/NowPlayingService.swift` | Fixed | 1b55888 |
| S05-005 | P1 | bug | Trash count reads ~/.Trash directly, which macOS protects; without Full Disk Access the widget shows a raw error and disables Empty Trash | `Sources/MyDock/SystemServices/TrashService.swift` | Fixed | 2e1b309 |
| S06-002 | P1 | security | Live Dock URL drops skip DockLinkPolicy, so links with credentials (user:password@host) are saved | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 1b55888 |
| S07-001 | P1 | bug | Auto-hide reveal path never turns Audio Output observation on (or off) | `Sources/MyDock/DockManagement/CustomDockWindowController.swift` | Fixed | 1b55888 |
| S07-002 | P1 | bug | 'Main display' resolves to NSScreen.main, which follows keyboard focus, so the Dock can jump between displays | `Sources/MyDock/DockManagement/CustomDockWindowController.swift` | Fixed | 2e1b309 |
| S07-003 | P1 | bug | Desktop widget mode puts the Dock at wallpaper level, below Finder's desktop-icon window | `Sources/MyDock/DockManagement/CustomDockWindowController.swift` | Fixed | 2e1b309 |
| S07-004 | P1 | reliability | Rollback runs inside the cancelled task, so a cancelled apply cannot restore the Dock | `Sources/MyDock/DockManagement/NativeDockController.swift` | Fixed | 2e1b309 |
| S07-005 | P1 | persistence | Launch-time journal recovery silently restores an arbitrarily old Dock snapshot | `Sources/MyDock/MyDockApp.swift` | Fixed | 89d165c |
| S09-001 | P1 | bug | AirDrop popout drop area says it takes links but registers only file URLs, and does not validate the URLs it reads | `Sources/MyDock/CustomDock/AirDropWidgetViews.swift` | Fixed | 1b55888 |
| S09-002 | P1 | ux | Trash count depends on reading the TCC-protected ~/.Trash with no setup flow; without Full Disk Access the widget is permanently "Unavailable" | `Sources/MyDock/SystemServices/TrashService.swift` | Fixed | 2e1b309 |
| S09-003 | P1 | bug | Trash count includes Finder's .DS_Store, so an empty Trash can read "1 item" and show the filled glyph | `Sources/MyDock/SystemServices/TrashService.swift` | Fixed | 1b55888 |
| S10-001 | P1 | bug | Folder popout navigates into app bundles and document packages instead of opening them | `Sources/MyDock/CustomDock/FolderContentsPopout.swift` | Fixed | 6825450 |
| S10-002 | P1 | bug | One-time alarm keeps showing as armed after it has fired | `Sources/MyDock/CustomDock/AlarmWidgetViews.swift` | Fixed | 6825450 |
| S10-003 | P1 | bug | Date-only reminders count as overdue from midnight of their due day and show a 00:00 time | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | 6825450 |
| S11-001 | P1 | bug | Stock and Watchlist session dates are shown one day early for users west of UTC | `Sources/MyDock/CustomDock/StockWidgetViews.swift` | Fixed | ab84109 |
| S11-002 | P1 | reliability | Opening a Stock, Watchlist or AI Limits popout forces a provider refetch and ignores the update interval | `Sources/MyDock/CustomDock/StockWidgetViews.swift` | Fixed | ab84109 |
| S12-001 | P1 | bug | Picking 'Saved reading only' in the Account/Store picker deletes the saved reading and disconnects the widget | `Sources/MyDock/CustomDock/StripeWidgetViews.swift` | Fixed | 6825450 |
| S12-002 | P1 | ux | Stripe forces the currency to USD on connect and account switch, so a non-USD account shows 'No data' until the user changes it by hand | `Sources/MyDock/CustomDock/StripeWidgetViews.swift` | Fixed | 6825450 |
| S14-001 | P1 | bug | Item inspector overwrites the whole item and reverts a Replace/Locate repair | `Sources/MyDock/UI/DockInspector.swift` | Fixed | febe41d |
| S15-001 | P1 | bug | Return and Command-Return add a result the user never saw highlighted; the first Down arrow skips the first result | `Sources/MyDock/UI/AddLibrary.swift` | Fixed | ab84109 |
| S16-001 | P1 | bug | Commerce starter preset uses a non-existent Numbers bundle ID, so Numbers is never added | `Sources/MyDock/UI/DockStarterPresets.swift` | Fixed | febe41d |
| S17-001 | P1 | build | Hardened-runtime release signs without Calendars and Location entitlements | `Xcode/MyDock.entitlements` | Fixed | 1b55888 |
| S19-001 | P1 | docs | Manual Dock recovery docs record and restore only `autohide`, but replacement mode also writes `autohide-delay` (86,400 s) and `no-bouncing` | `docs/REAL_DOCK_TEST_PLAN.md` | Fixed | 2ce3fbb |
| S01-003 | P2 | ux | Every new World Clock defaults to Europe/Warsaw, including the onboarding starter set | `Sources/MyDock/Models/DockModels.swift` | Fixed | e9b27a9 |
| S01-004 | P2 | ux | Calculator rejects the locale decimal comma but shows results with it | `Sources/MyDock/Widgets/QuickCalculator.swift` | Fixed | e9b27a9 |
| S01-005 | P2 | ux | Focus and Countdown timers have no hours: 24 h shows as 1440:00 | `Sources/MyDock/Models/ProfileSemanticValidator.swift` | Fixed | e9b27a9 |
| S01-006 | P2 | ux-copy | Privacy help says personal backups add cached readings, but backups always strip them | `Sources/MyDock/Models/PrivacyHelpCopy.swift` | Fixed | e9b27a9 |
| S01-007 | P2 | performance | Command palette search resolves every File Shelf bookmark in every Dock on each evaluation | `Sources/MyDock/Widgets/SavedCollectionSearch.swift` | Fixed | e9b27a9 |
| S01-008 | P2 | design-consistency | Stock and Watchlist need an API key but the registry says they need no connection | `Sources/MyDock/Models/DockModels.swift` | Fixed | e9b27a9 |
| S02-002 | P2 | persistence | One invalid profile or widget throws away the whole state at launch, and the preserved file cannot be restored in the app | `Sources/MyDock/Persistence/ProfileStore.swift` | Fixed | 2ec0bba |
| S02-003 | P2 | reliability | ProfileLibrary turns history and presets off for good after a single read or write failure | `Sources/MyDock/Persistence/ProfileLibrary.swift` | Fixed | e9b27a9 |
| S02-004 | P2 | reliability | The state writer's crash-safe commit uses fsync with no F_FULLFSYNC and no directory sync | `Sources/MyDock/Persistence/RevisionedStateWriter.swift` | Fixed | e9b27a9 |
| S02-005 | P2 | privacy | Import preview trusts the package's own includesPersonalData flag | `Sources/MyDock/Backup/PortableDockPackage.swift` | Fixed | e9b27a9 |
| S02-006 | P2 | concurrency | CI warning: non-Sendable WidgetRuntimeCache.Entry is captured in a @Sendable writer closure | `Sources/MyDock/Persistence/WidgetRuntimeCache.swift` | Fixed | 5d7fabd |
| S02-007 | P2 | performance | Provider loads, including Keychain reads, run on the main actor | `Sources/MyDock/Services/WidgetDataCoordinator.swift` | Fixed | e9b27a9 |
| S02-008 | P2 | performance | presentationItem scans every profile and re-sanitizes readings on each SwiftUI body access | `Sources/MyDock/Persistence/ProfileStore.swift` | Fixed | e9b27a9 |
| S02-009 | P2 | reliability | A lifecycle timer that wakes before its wall-clock deadline is never rescheduled | `Sources/MyDock/Services/WidgetLifecycleCoordinator.swift` | Fixed | e9b27a9 |
| S02-010 | P2 | performance | Autosave and other routine commits write and sync the whole state, plus the history library, on the main thread | `Sources/MyDock/Persistence/ProfileStore.swift` | Fixed | e9b27a9 |
| S03-005 | P2 | reliability | Failure backoff retries sooner than the normal 5-minute cadence, and no client honours Retry-After on 429 | `Sources/MyDock/Services/WidgetDataCoordinator.swift` | Fixed | e9b27a9 |
| S03-006 | P2 | bug | Shopify GraphQL throttling (HTTP 200 with THROTTLED) is reported as a raw provider error, not as rate limiting | `Sources/MyDock/SystemServices/ShopifyDataService.swift` | Fixed | 531d266 |
| S03-007 | P2 | reliability | Watchlist keeps calling Alpha Vantage for every remaining symbol after the provider limit is reached, with no backoff | `Sources/MyDock/Services/WidgetDataCoordinator.swift` | Fixed | e9b27a9 |
| S03-008 | P2 | reliability | Stripe requests do not pin Stripe-Version, so response shapes depend on each account's default API version | `Sources/MyDock/SystemServices/StripeDataService.swift` | Fixed | 533f58d |
| S03-009 | P2 | ux | Stripe's 1,000-row page budget fails the whole widget for modest businesses, because balance transactions are fetched unfiltered | `Sources/MyDock/SystemServices/StripeDataService.swift` | Fixed | 533f58d |
| S03-010 | P2 | performance | BoundedHTTPFetch.collect reads the clock and checks cancellation on every byte, making the periodic check redundant | `Sources/MyDock/SystemServices/BoundedHTTPFetch.swift` | Fixed | 533f58d |
| S03-011 | P2 | performance | Date formatters and CharacterSets are allocated per parsed value in provider parsers | `Sources/MyDock/SystemServices/ShopifyDataService.swift` | Fixed | 533f58d |
| S03-012 | P2 | ux | Favicon normalisation keeps the first frame of an ICO (usually 16x16), so link icons look blurry | `Sources/MyDock/SystemServices/SiteFaviconFetcher.swift` | Fixed | 533f58d |
| S03-013 | P2 | code-quality | Five copy-pasted Keychain stores (and three identical connection directories) whose 'ThisDeviceOnly' attribute is ignored on the macOS file keychain | `Sources/MyDock/SystemServices/StripeDataService.swift` | Fixed | 533f58d |
| S04-003 | P2 | ux-copy | One `partial` flag covers both undercounts and possible overcounts, so the UI states the wrong bound | `Sources/MyDock/SystemServices/AIUsageService.swift` | Fixed | 533f58d |
| S04-004 | P2 | reliability | Session logs over 32 MB are read from the start and dropped at the cap, so the newest (in-range) usage is lost | `Sources/MyDock/SystemServices/AIUsageService.swift` | Fixed | 533f58d |
| S04-005 | P2 | performance | The activity log parser allocates two ISO8601DateFormatters per row and front-trims Data per line | `Sources/MyDock/SystemServices/AIUsageService.swift` | Fixed | 533f58d |
| S04-006 | P2 | concurrency | Synchronous subprocess and log reads block Swift-concurrency pool threads, ignore cancellation and serialise providers | `Sources/MyDock/SystemServices/AIUsageService.swift` | Fixed | 533f58d |
| S04-007 | P2 | ux-copy | Every Codex app-server failure is reported as 'sign in with your ChatGPT account' | `Sources/MyDock/SystemServices/CodexAccountRPC.swift` | Fixed | 533f58d |
| S04-008 | P2 | reliability | The Claude limits bridge parses the whole status-line JSON with plutil, which may reject JSON null | `Sources/MyDock/SystemServices/AIAccountService.swift` | Fixed | 9ccf69b |
| S04-009 | P2 | ux | Enable Limits rewrites Claude Code settings with no way to turn it off, and adds a 'Claude Code' status line where there was none | `Sources/MyDock/SystemServices/AIAccountService.swift` | Fixed | 533f58d |
| S04-010 | P2 | reliability | CLI discovery misses common Claude Code and Codex install locations for a GUI app's PATH | `Sources/MyDock/SystemServices/AIAccountService.swift` | Fixed | 533f58d |
| S04-011 | P2 | reliability | Repeating alarms use one pending request per weekday, which can exceed the per-app pending-notification cap; startup reconcile then switches alarms off silently | `Sources/MyDock/SystemServices/AlarmNotificationService.swift` | Fixed | 533f58d |
| S04-012 | P2 | bug | Cancelling a shortcut kills only the `shortcuts` CLI client, but the UI reports 'Cancelled' | `Sources/MyDock/SystemServices/ShortcutsService.swift` | Fixed | 533f58d |
| S05-006 | P2 | energy | RefreshScheduler arms zero-tolerance timers per subscription phase and keeps ticking during display sleep or a switched-out session | `Sources/MyDock/SystemServices/RefreshScheduler.swift` | Fixed | 9db1455 |
| S05-007 | P2 | energy | 'Click focused app to minimize' alone starts a full Accessibility window scan of every app every 4 seconds | `Sources/MyDock/DockManagement/CustomDockWindowController.swift` | Fixed | 9db1455 |
| S05-008 | P2 | reliability | Window sampling publishes partial snapshots, so minimized-window tiles disappear and reappear | `Sources/MyDock/SystemServices/WindowAccessibilityService.swift` | Fixed | 9db1455 |
| S05-009 | P2 | reliability | Window identity depends on Accessibility z-order index and title | `Sources/MyDock/SystemServices/WindowAccessibilityService.swift` | Fixed | 9db1455 |
| S05-010 | P2 | privacy | Disk preview cache is keyed by app and title, so a minimized window can show another window's day-old screenshot | `Sources/MyDock/SystemServices/WindowPreviewCache.swift` | Fixed | 9db1455 |
| S05-011 | P2 | reliability | Trash watcher reads DispatchSource.data outside its event handler, so delete/rename re-arming never triggers | `Sources/MyDock/SystemServices/TrashService.swift` | Fixed | 9db1455 |
| S05-012 | P2 | ux | Automation calls time out after 8 s, so the first-run consent prompt and large Trash empties report generic failures | `Sources/MyDock/SystemServices/NowPlayingService.swift` | Fixed | 9db1455 |
| S05-013 | P2 | reliability | Now Playing read script can relaunch a player that is quitting | `Sources/MyDock/SystemServices/NowPlayingService.swift` | Fixed | 9db1455 |
| S05-014 | P2 | performance | Music artwork is hex-decoded and thumbnailed on the main actor | `Sources/MyDock/SystemServices/NowPlayingService.swift` | Fixed | 9db1455 |
| S05-015 | P2 | performance | AppLauncher.icon and isMissingTarget do filesystem and Launch Services work on every SwiftUI body evaluation | `Sources/MyDock/SystemServices/AppLauncher.swift` | Fixed | 9db1455 |
| S05-016 | P2 | bug | Window and app activation relies on .activateIgnoringOtherApps, which macOS 14+ ignores | `Sources/MyDock/SystemServices/WindowAccessibilityService.swift` | Fixed | 9db1455 |
| S05-017 | P2 | bug | Network totals double-count VPN tunnels, bridges and peer-to-peer interfaces | `Sources/MyDock/SystemServices/NetworkActivityReader.swift` | Fixed | 9db1455 |
| S06-003 | P2 | performance | `profile` and `settings` are recomputed on every access, giving O(N²) work in each body pass | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-004 | P2 | energy | Root-level hover state and broad ObservableObject observation re-render the whole Dock and rebuild the render model several times per pass | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | a53e3e0 |
| S06-005 | P2 | performance | Context-menu window discovery runs synchronously on the main thread and can exceed its stated 0.35 s bound | `Sources/MyDock/DockManagement/DockItemContextMenus.swift` | Fixed | 0470e4f |
| S06-006 | P2 | bug | A running app in the recent-apps section shows no running dot when Show running apps is off | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-007 | P2 | reliability | Opening or closing any popout changes every tile's structural identity, rebuilding tiles and re-hosting the popover | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-008 | P2 | design-consistency | The popout colour scheme ignores the Midnight material that DockColorSchemePolicy applies to the Dock | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-009 | P2 | accessibility | The popout tab bar shows the selected tab only by tint, uses new colours, and has an 8 pt close target | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-010 | P2 | accessibility | VoiceOver gets no running state, no open-popout state, and no name for default folder or favicon tiles | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-011 | P2 | accessibility | The live Dock has no keyboard path: tiles cannot be focused, launched or opened from the keyboard | `Sources/MyDock/DockManagement/CustomDockView.swift` | Deferred | 0470e4f |
| S06-012 | P2 | ux | Every tile menu starts with global actions, and Remove from Dock sits directly under Force Quit… | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-013 | P2 | ux | Modal alerts and open panels from the Dock run without activating the accessory app | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-014 | P2 | bug | On macOS 13, magnified tiles are clipped by the ScrollView | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-015 | P2 | code-quality | CustomDockView mixes rendering, prompts, drop routing, popouts and runtime monitoring in one 1.1k-line struct | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S07-006 | P2 | reliability | Verification only re-reads the preferences just written; the freeze ends before the Dock relaunches | `Sources/MyDock/DockManagement/NativeDockController.swift` | Fixed | 9db1455 |
| S07-007 | P2 | ux-copy | Error copy claims 'The previous layout was restored' when restoration failed, and mislabels relaunch failures | `Sources/MyDock/DockManagement/NativeDockController.swift` | Fixed | 9db1455 |
| S07-008 | P2 | ux | Switch-freeze overlay has no time limit and captures Retina displays at 1x | `Sources/MyDock/DockManagement/DockSwitchFreezeProvider.swift` | Fixed | 9db1455 |
| S07-009 | P2 | bug | Hover machine keeps a stale pointerInPanel, which can leave the preview panel stuck open | `Sources/MyDock/DockManagement/DockWindowPreviewPolicy.swift` | Fixed | 9db1455 |
| S07-010 | P2 | performance | update(state:) is uncoalesced, recomputes the render model twice and recreates the reveal hosting view | `Sources/MyDock/DockManagement/CustomDockWindowController.swift` | Fixed | 9db1455 |
| S07-011 | P2 | energy | Reveal sampling polls at 2 Hz forever (even with displays asleep) and spawns a Task per global mouse event | `Sources/MyDock/DockManagement/DockRevealMonitor.swift` | Fixed | 9db1455 |
| S07-012 | P2 | performance | Blocking NSWindow setFrame(_:display:animate:) used for live geometry changes | `Sources/MyDock/DockManagement/CustomDockWindowController.swift` | Fixed | 9db1455 |
| S07-013 | P2 | ux | Keyboard Shortcuts and What's New are only in the main-menu Help menu, which accessory mode never shows | `Sources/MyDock/MyDockApp.swift` | Fixed | 9db1455 |
| S07-014 | P2 | ux | An always-visible Custom Dock covers full-screen apps permanently | `Sources/MyDock/DockManagement/CustomDockWindowController.swift` | Fixed | 9db1455 |
| S07-015 | P2 | code-quality | Duplicated teardown blocks in update(state:) bypass transition state | `Sources/MyDock/DockManagement/CustomDockWindowController.swift` | Fixed | 9db1455 |
| S07-016 | P2 | ux | Native profile switches are queued, not coalesced, and failure alerts may appear behind other apps | `Sources/MyDock/MyDockApp.swift` | Fixed | 9db1455 |
| S07-017 | P2 | reliability | New app tiles inherit another app's tile-data from the snapshot template | `Sources/MyDock/DockManagement/NativeDockController.swift` | Fixed | 9db1455 |
| S07-018 | P2 | energy | Closed windows keep their SwiftUI hosting views alive for the app lifetime | `Sources/MyDock/MyDockApp.swift` | Fixed | 9db1455 |
| S08-001 | P2 | accessibility | White glyph on dark-appearance family fills is below 3:1 contrast (active toggles, Color icon style, Auto swatch) | `Sources/MyDock/CustomDock/WidgetPrimitives.swift` | Fixed | b27a974 |
| S08-002 | P2 | bug | Clock and World Clock faces can show the previous minute for up to 30 seconds | `Sources/MyDock/CustomDock/WidgetPrimitives.swift` | Fixed | 5d7fabd |
| S08-003 | P2 | bug | Target-date Countdown ring divides by the unrelated duration setting, so it is always full | `Sources/MyDock/CustomDock/WidgetPrimitives.swift` | Fixed | 5d7fabd |
| S08-004 | P2 | energy | Local faces re-render every second for target-date countdowns and every 30 s for static faces | `Sources/MyDock/CustomDock/WidgetPrimitives.swift` | Fixed | a2d8a8d |
| S08-005 | P2 | accessibility | Several Dock faces expose no name or ambiguous text to VoiceOver | `Sources/MyDock/CustomDock/WidgetPrimitives.swift` | Fixed | a2d8a8d |
| S08-006 | P2 | reliability | Weather face presents a cached forecast of any age as current, with no stale signal | `Sources/MyDock/CustomDock/WidgetPrimitives.swift` | Fixed | a2d8a8d |
| S08-007 | P2 | reliability | Undo restarts its 15 s window on re-appearance and drops failed or partial restores silently | `Sources/MyDock/CustomDock/CollectionUndo.swift` | Fixed | b27a974 |
| S08-008 | P2 | design-consistency | Default Tile surface hard-codes radius, fills and outline instead of Dock tokens | `Sources/MyDock/CustomDock/WidgetPrimitives.swift` | Fixed | b27a974 |
| S09-004 | P2 | energy | Clock and World Clock popouts redraw every second (and allocate DateFormatters each tick) for minute-precision text | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | b27a974 |
| S09-005 | P2 | performance | Sticky Note writes the whole profile file synchronously on the main thread on every popout open and close, even without edits | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | b27a974 |
| S09-006 | P2 | reliability | AirDrop Dock tile mutates @State from makeNSView/updateNSView on every update | `Sources/MyDock/CustomDock/AirDropWidgetViews.swift` | Fixed | b27a974 |
| S09-007 | P2 | bug | Disk Space reports free space without purgeable storage, unlike Finder and System Settings, and can raise false low-space warnings | `Sources/MyDock/CustomDock/UtilityWidgetViews.swift` | Fixed | b27a974 |
| S09-008 | P2 | ux | Hydration shows two adjacent log buttons that record the same entry, one in gallery chrome, and "I Drank Water" silently logs nothing when history is off | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | b27a974 |
| S09-009 | P2 | design-consistency | Countdown hand-rolls its hero: status words render at 40 pt with no caption, contrary to WidgetPopoutHeroStyle | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | b27a974 |
| S09-010 | P2 | design-consistency | Settings disclosure is applied to only some families; World Clock, Shortcuts, Countdown and Focus Timer show setup inline | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | b27a974 |
| S09-011 | P2 | ux | Countdown (duration) and Focus Timer controls do not update at completion: the 1 Hz timeline keeps running and Start becomes a no-op | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | b27a974 |
| S09-012 | P2 | performance | App Folder popout does filesystem and icon I/O in body for every app on every store publish | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | b27a974 |
| S10-004 | P2 | ux | A deleted selected calendar or list is shown as a permission problem and the calendar choices are cleared | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | afeb997 |
| S10-005 | P2 | ux | Calendar and Reminders popouts replace the reading with a loading row on every refresh | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | afeb997 |
| S10-006 | P2 | energy | EventKit widgets refetch on every activation, wake and store-change burst with unstructured, uncoalesced tasks | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | afeb997 |
| S10-007 | P2 | privacy | An unnamed Text Snippet puts the start of its text on the Dock face | `Sources/MyDock/CustomDock/DockUtilityWidgetViews.swift` | Fixed | afeb997 |
| S10-008 | P2 | performance | File Shelf body resolves every bookmark and stats every file several times per render on the main thread | `Sources/MyDock/CustomDock/DockUtilityWidgetViews.swift` | Fixed | afeb997 |
| S10-009 | P2 | performance | File thumbnails restart their task and stat the file on every magnification frame | `Sources/MyDock/CustomDock/FileThumbnailView.swift` | Fixed | afeb997 |
| S10-010 | P2 | performance | Every application tile runs Bundle(url:) and a running-app lookup on each render | `Sources/MyDock/CustomDock/FileThumbnailView.swift` | Fixed | afeb997 |
| S10-011 | P2 | ux | Calendar app tile likely never shows today's date | `Sources/MyDock/CustomDock/FileThumbnailView.swift` | Deferred | afeb997 |
| S10-012 | P2 | accessibility | Folder popout icon buttons have no accessibility labels and Back has no keyboard shortcut | `Sources/MyDock/CustomDock/FolderContentsPopout.swift` | Fixed | afeb997 |
| S10-013 | P2 | ux-copy | Folder popout "Open in Finder" opens files in their default app | `Sources/MyDock/CustomDock/FolderContentsPopout.swift` | Fixed | afeb997 |
| S10-014 | P2 | reliability | Folder popout and Now Playing launch apps and open files without the isolated-session guard | `Sources/MyDock/CustomDock/FolderContentsPopout.swift` | Fixed | afeb997 |
| S10-015 | P2 | bug | Alarm repeat chips use ambiguous or identical first letters and ignore the locale's first weekday | `Sources/MyDock/CustomDock/AlarmWidgetViews.swift` | Fixed | afeb997 |
| S10-016 | P2 | bug | Now Playing timing likely wrong for Spotify (milliseconds) and in comma-decimal locales | `Sources/MyDock/CustomDock/NowPlayingWidgetViews.swift` | Already fixed | afeb997 |
| S10-027 | P2 | ux | Text Snippets popout leads with the editor while Quick Links leads with the saved list | `Sources/MyDock/CustomDock/DockUtilityWidgetViews.swift` | Fixed | afeb997 |
| S11-003 | P2 | ux | Stock popout never names its ticker, and the Display name setting is never read | `Sources/MyDock/CustomDock/StockWidgetViews.swift` | Fixed | afeb997 |
| S11-004 | P2 | reliability | Weather writes forecasts through the authored update path, so they are silently dropped when saving is disabled | `Sources/MyDock/CustomDock/WeatherWidgetViews.swift` | Fixed | afeb997 |
| S11-005 | P2 | ux-copy | Estimated AI Activity token totals look exact on the face and in the popout reading | `Sources/MyDock/CustomDock/AIUsageWidgetViews.swift` | Fixed | afeb997 |
| S11-006 | P2 | ux | AI Limits says "Choose a provider in Settings" while loading or when the chosen provider has no reading | `Sources/MyDock/CustomDock/AIUsageWidgetViews.swift` | Fixed | afeb997 |
| S11-007 | P2 | ux | Retained (stale) AI limit readings do not show their success time; the stale presenter exists only for tests | `Sources/MyDock/CustomDock/AIUsageWidgetViews.swift` | Fixed | afeb997 |
| S11-008 | P2 | performance | AIActivitySummary rebuilds its data query, including filesystem symlink resolution and SHA-256, several times per render, behind a force unwrap | `Sources/MyDock/CustomDock/AIUsageWidgetViews.swift` | Fixed | afeb997 |
| S11-009 | P2 | code-quality | StockPopoutView and WatchlistPopoutView duplicate about 150 lines, and their local isRefreshing duplicates coordinator state | `Sources/MyDock/CustomDock/StockWidgetViews.swift` | Fixed | afeb997 |
| S11-010 | P2 | design-consistency | Market Dock face ignores the tested StockFaceFormatting: unlocalized percent and a different change colour | `Sources/MyDock/CustomDock/StockWidgetViews.swift` | Fixed | afeb997 |
| S11-015 | P2 | ux | A stale Weather forecast looks current on the Dock face, and an old forecast leaves an empty Next Hours section | `Sources/MyDock/CustomDock/WeatherWidgetViews.swift` | Fixed | afeb997 |
| S12-003 | P2 | ux | The popout setup cannot reuse an existing connection: an unconnected widget only offers the credential form, so users re-enter secrets and create duplicate Key… | `Sources/MyDock/CustomDock/StripeWidgetViews.swift` | Fixed | afeb997 |
| S12-004 | P2 | performance | Business popouts force an API refresh on every open and on every keystroke in the name field | `Sources/MyDock/CustomDock/ShopifyWidgetViews.swift` | Fixed | afeb997 |
| S12-005 | P2 | ux | No reconnection path in the popout: a revoked or rotated credential can only be fixed by Disconnect, which clears every widget's reading, and the dialog does n… | `Sources/MyDock/CustomDock/StripeWidgetViews.swift` | Deferred | afeb997 |
| S12-006 | P2 | code-quality | Dead refresh state and three near-duplicate business popouts (about 70% shared code) | `Sources/MyDock/CustomDock/StripeWidgetViews.swift` | Fixed | afeb997 |
| S12-007 | P2 | performance | The default storage scan walks ~/Library twice and lets Library use up Home's 100,000-entry budget | `Sources/MyDock/CustomDock/SystemActivityWidgetViews.swift` | Fixed | afeb997 |
| S12-008 | P2 | ux | 'Scan Folders' enumerates Home with no folder-access purpose strings, so the user can get a series of unexplained TCC prompts | `Sources/MyDock/CustomDock/SystemActivityWidgetViews.swift` | Fixed | abd0ad8 |
| S13-001 | P2 | ux | Settings search: sidebar and results disagree, and many controls have no catalog entry | `Sources/MyDock/UI/SettingsSearchCatalog.swift` | Fixed | d300ec1 |
| S13-002 | P2 | ux | "Restore…" silently appends copies of every Dock in the backup, with no preview | `Sources/MyDock/UI/Settings/GeneralSettingsPage.swift` | Fixed | a639ff1 |
| S13-003 | P2 | ux | Appearance scope selector sits at the bottom of the page, below every control it governs | `Sources/MyDock/UI/Settings/AppearanceSettingsPage.swift` | Fixed | a639ff1 |
| S13-004 | P2 | ux | Three overlapping, similarly named appearance reset controls; app-wide reset has no confirmation | `Sources/MyDock/UI/Settings/AppearanceSettingsPage.swift` | Fixed | a639ff1 |
| S13-005 | P2 | performance | Appearance hero builds a new sample profile with fresh UUIDs on every render | `Sources/MyDock/UI/Settings/AppearanceSettingsPage.swift` | Fixed | d300ec1 |
| S13-006 | P2 | energy | AI account cards spawn CLI subprocesses on every app activation through uncancelled Tasks | `Sources/MyDock/UI/AIAccountConnectionView.swift` | Fixed | d300ec1 |
| S13-007 | P2 | ux | Removing the Alpha Vantage key or the Copilot credentials is immediate, while Disconnect confirms | `Sources/MyDock/UI/Settings/IntegrationsSettingsPage.swift` | Fixed | d300ec1 |
| S13-008 | P2 | ux | "Check for Updates" is disabled by default with no visible reason | `Sources/MyDock/UI/AppLifecycleSettingsView.swift` | Fixed | d300ec1 |
| S13-009 | P2 | accessibility | SettingsExpansionRow is not a proper disclosure: static chevron, "Hide" value and conflicting accessibility values | `Sources/MyDock/UI/Settings/SettingsShared.swift` | Fixed | d300ec1 |
| S13-010 | P2 | accessibility | Appearance sliders expose raw values to VoiceOver that differ from the visible % / pt labels | `Sources/MyDock/UI/Settings/AppearanceSettingsPage.swift` | Fixed | d300ec1 |
| S13-011 | P2 | code-quality | SettingsView is a 35-property state object shared by every page extension | `Sources/MyDock/UI/SettingsView.swift` | Deferred | d300ec1 |
| S14-002 | P2 | bug | Appearance inspector edits from a stale draft appearance while the Dock draft is dirty | `Sources/MyDock/UI/DockInspector.swift` | Fixed | 6df69f5 |
| S14-003 | P2 | bug | An empty Dock name is reported as a merge conflict and opens the draft-review alert | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | 0e140eb |
| S14-004 | P2 | ux | Failed save on profile switch stacks a second 'Unsaved Dock Changes' dialog on top of the failure UI | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | 0e140eb |
| S14-005 | P2 | bug | Deleting another Dock from the sidebar moves the selection to the first Dock | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | 0e140eb |
| S14-006 | P2 | bug | Sidebar search keeps filtering after the search field disappears | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | 0e140eb |
| S14-007 | P2 | bug | Hidden ⌘D shortcut duplicates the whole Dock from Settings and only the first item of a multi-selection | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | 0e140eb |
| S14-008 | P2 | bug | Editor key shortcuts stay active while renaming; ⌘←/⌘→ reorder items instead of moving the text cursor | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | 0e140eb |
| S14-009 | P2 | ux | Inline rename has no cancel, no commit on focus loss, and records an Undo and autosave per keystroke | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | 6df69f5 |
| S14-010 | P2 | bug | Widget Layout picker in the selection inspector does nothing when the item has no stored configuration | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | 0e140eb |
| S14-011 | P2 | persistence | Folder name, letter and number from the item inspector are stored un-normalized, unlike the live Dock editor | `Sources/MyDock/UI/DockInspector.swift` | Fixed | 0e140eb |
| S14-012 | P2 | performance | Dock canvas runs missing-target file and LaunchServices checks several times per tile on every render | `Sources/MyDock/UI/DockCanvas.swift` | Fixed | 0e140eb |
| S14-013 | P2 | performance | ⌘K command list is rebuilt several times per keystroke with O(apps × items) symlink resolution | `Sources/MyDock/UI/CommandLibrary.swift` | Fixed | 0e140eb |
| S14-014 | P2 | accessibility | ⌘K highlighted result is not exposed to VoiceOver | `Sources/MyDock/UI/CommandLibrary.swift` | Fixed | 0e140eb |
| S14-015 | P2 | accessibility | Create Dock, Link and Preset sheets have no Return/Escape default and cancel actions | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | 0e140eb |
| S14-016 | P2 | design-consistency | Creating a Dock silently activates it (and leaves native-only mode) while duplicate and import do not | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | 0e140eb |
| S14-017 | P2 | ux | Persistence failures are shown up to three times, and the modal alert re-opens on every edit while storage is read-only | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | 0e140eb |
| S14-018 | P2 | code-quality | DockManagerView is a 1,131-line view with ~40 @State properties; proposed split | `Sources/MyDock/UI/DockManagerView.swift` | Deferred | 0e140eb |
| S14-019 | P2 | code-quality | Stringly-typed actions: browse names, creation source, categories and save status are matched by UI copy | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | 0e140eb |
| S14-020 | P2 | reliability | ⌘K actions dismiss the library sheet and present another sheet or dialog in the same update | `Sources/MyDock/UI/CommandLibrary.swift` | Fixed | 0e140eb |
| S15-002 | P2 | bug | Arrow-key focus assumes one uniform grid, but the Suggested row and every section start new rows with different column counts | `Sources/MyDock/UI/AddLibrary.swift` | Fixed | 6df69f5 |
| S15-003 | P2 | performance | Body re-derives the filtered app list for every row and resolves symlinks for every profile item in every tile, on the main thread | `Sources/MyDock/UI/AddLibrary.swift` | Fixed | 0e140eb |
| S15-004 | P2 | energy | Every app activation throws the app list away and rescans every application bundle | `Sources/MyDock/UI/AddLibrary.swift` | Fixed | 0e140eb |
| S15-005 | P2 | ux-copy | Apps tab footer talks about widgets on custom Docks | `Sources/MyDock/UI/AddLibrary.swift` | Fixed | 0e140eb |
| S15-006 | P2 | design-consistency | New literal colours and two different 'Added' marks in one window | `Sources/MyDock/UI/WidgetGallery/WidgetGalleryChrome.swift` | Fixed | 0e140eb |
| S15-007 | P2 | ux | The 'no longer available' error never clears and VoiceOver never announces it | `Sources/MyDock/UI/AddLibrary.swift` | Fixed | 0e140eb |
| S15-008 | P2 | ux | Adding a spacer from More gives no feedback | `Sources/MyDock/UI/AddLibrary.swift` | Fixed | 0e140eb |
| S15-009 | P2 | accessibility | VoiceOver gets no feedback for the search highlight, for opening the detail, or for the detail's Added state | `Sources/MyDock/UI/AddLibrary.swift` | Fixed | 0e140eb |
| S15-010 | P2 | bug | Hidden unmodified Space and Return shortcuts can capture keys meant for the search field | `Sources/MyDock/UI/WidgetGallery/WidgetGalleryDetail.swift` | Fixed | e2a872c |
| S15-011 | P2 | accessibility | Arrowing to a tile that LazyVGrid has not built yet can drop keyboard focus | `Sources/MyDock/UI/AddLibrary.swift` | Fixed | e2a872c |
| S15-012 | P2 | bug | More > Link… closes this sheet and presents the link editor sheet in the same update | `Sources/MyDock/UI/AddLibrary.swift` | Already fixed | e2a872c |
| S16-002 | P2 | ux | "Import my current macOS Dock" is silently ignored when any macOS Dock profile already exists, but a failed import still blocks setup | `Sources/MyDock/UI/OnboardingView.swift` | Fixed | e2a872c |
| S16-003 | P2 | reliability | Onboarding infers save success from store flags, while finishOnboarding swallows its own error | `Sources/MyDock/UI/OnboardingView.swift` | Fixed | e2a872c |
| S16-004 | P2 | dead-code | MenuBarView is unused and would not work if used | `Sources/MyDock/UI/MenuBarView.swift` | Fixed | e2a872c |
| S16-005 | P2 | bug | Shortcut recorder stores unreadable labels for arrow and function keys, and the shifted character for Shift combos | `Sources/MyDock/UI/KeyboardShortcutEditor.swift` | Fixed | e2a872c |
| S16-006 | P2 | ux | Escape in the shortcut recorder deletes the existing shortcut, and Cancel closes the whole sheet | `Sources/MyDock/UI/KeyboardShortcutEditor.swift` | Fixed | e2a872c |
| S16-007 | P2 | bug | Personal presets: a stale success message permanently hides later library errors | `Sources/MyDock/UI/PersonalPresetPicker.swift` | Fixed | e2a872c |
| S16-008 | P2 | ux | Removing a personal preset is immediate, with no confirmation and no undo | `Sources/MyDock/UI/PersonalPresetPicker.swift` | Fixed | e2a872c |
| S16-009 | P2 | ux | Two incompatible .json sharing formats in the same Docks flow: a personal preset and a portable Dock package | `Sources/MyDock/UI/PersonalPresetPicker.swift` | Fixed | e2a872c |
| S16-010 | P2 | accessibility | Onboarding: starter-widget cards and the step list do not expose selection or current-step state to VoiceOver | `Sources/MyDock/UI/OnboardingView.swift` | Fixed | e2a872c |
| S16-011 | P2 | design-consistency | Sheets in this slice each invent their own header, footer, fonts and colours instead of shared design-system primitives | `Sources/MyDock/UI/KeyboardShortcutEditor.swift` | Fixed | e2a872c |
| S16-012 | P2 | ux | Replace-mode onboarding gives the new Custom Dock no Trash, although Apple's Dock (and its Trash) is hidden | `Sources/MyDock/UI/OnboardingView.swift` | Fixed | e2a872c |
| S17-002 | P2 | test-quality | Render QA export exits 0 even when validation fails | `Sources/MyDock/MyDockApp.swift` | Fixed | 9db1455 |
| S17-003 | P2 | test-quality | Faces B export renders the same full-height popout twice; the shipping-cap popout is never captured | `Sources/MyDock/UI/RedesignQA/FacesBQA.swift` | Fixed | c428929 |
| S17-004 | P2 | test-quality | Dock-style QA renders its own style table, which no longer matches the shipped quick styles | `Sources/MyDock/UI/RedesignQA/DockStyleQA.swift` | Fixed | c428929 |
| S17-005 | P2 | build | Committed MyDock.xcodeproj is stale and misses 27 Swift files | `MyDock.xcodeproj/project.pbxproj` | Fixed | c428929 |
| S17-006 | P2 | reliability | BuildMyDock.sh updates the canonical app in place; a failed late step leaves a broken bundle | `BuildMyDock.sh` | Fixed | c428929 |
| S17-007 | P2 | build | BuildMyDock.sh trusts sed-scraped product identity and lacks pipefail | `BuildMyDock.sh` | Fixed | c428929 |
| S17-008 | P2 | build | Info.plist is defined three times (BuildMyDock heredoc, project.yml, Xcode/MyDock-Info.plist) | `BuildMyDock.sh` | Fixed | c428929 |
| S17-009 | P2 | ci | CI never runs on the OS versions the app claims, never builds the UI tests, never runs render QA | `.github/workflows/validate.yml` | Deferred | c428929 |
| S17-010 | P2 | privacy | history.md at the repo root is an 881 KB pasted Claude Code transcript with the user's home path | `history.md` | Fixed | cae7326 |
| S17-011 | P2 | docs | .claude agents and commands describe two finished campaigns and contradict each other | `.claude/agents/reliability.md` | Fixed | c428929 |
| S17-012 | P2 | test-quality | Fixed render canvases plus the title-bar safe area clip exports silently | `Sources/MyDock/UI/PremiumVisualQA.swift` | Fixed | c428929 |
| S17-013 | P2 | code-quality | Render QA infrastructure is copy-pasted across eight files and the copies disagree | `Sources/MyDock/UI/RedesignQA/DockStyleQA.swift` | Deferred | c428929 |
| S17-014 | P2 | build | Release flow is not reproducible: dirty trees, reused DerivedData and untracked files are accepted | `ReleaseMyDock.sh` | Fixed | c428929 |
| S18-002 | P2 | reliability | Fixed sleeps are used as synchronization before expectations (known flake class) | `Tests/MyDockTests/ProductRuntimeTests.swift` | Fixed | 6325b9e |
| S18-003 | P2 | test-quality | Subprocess tests assert wall-clock upper bounds and their cancellation cases can pass without exercising termination | `Tests/MyDockTests/BoundedSubprocessCaptureTests.swift` | Fixed | c428929 |
| S18-004 | P2 | test-quality | Symlinked Claude settings test cannot detect a missing symlink guard | `Tests/MyDockTests/AIAccountTests.swift` | Fixed | c428929 |
| S18-005 | P2 | privacy | Tests create real preference domains in the user's ~/Library/Preferences | `Tests/MyDockTests/DockAuditRegressionTests.swift` | Fixed | c428929 |
| S18-006 | P2 | ci | UI tests have never run and are not part of CI | `Tests/MyDockUITests/MyDockVisualPreviewUITests.swift` | Fixed | c428929 |
| S18-007 | P2 | test-gap | Native Dock rollback failure, successful recovery and launch health are untested by default | `Sources/MyDock/DockManagement/NativeDockController.swift` | Fixed | 9db1455 |
| S18-008 | P2 | test-gap | Window preview cache purge paths (privacy) are untested | `Sources/MyDock/SystemServices/WindowAccessibilityService.swift` | Fixed | 9db1455 |
| S18-009 | P2 | test-gap | Calendar selection guarantees live in EventKit and private view code with no tests | `Sources/MyDock/SystemServices/CalendarRemindersService.swift` | Fixed | 533f58d |
| S19-002 | P2 | docs | PERMISSIONS.md does not cover the product-wave features that use or affect permissions: hover window previews, Login Items, Audio Output, Color Picker and the… | `docs/PERMISSIONS.md` | Fixed | c428929 |
| S19-003 | P2 | docs | Widget count is wrong everywhere: docs say 35, or 26, but WidgetRegistry has 36 families; the README's family list omits nine | `README.md` | Fixed | c428929 |
| S19-004 | P2 | docs | Appearance style and material names in the docs do not exist in the app | `README.md` | Fixed | c428929 |
| S19-005 | P2 | docs | Docs and acceptance steps describe a Compact/Standard/Wide widget-width context menu and Add Widget Size menu that the product no longer has | `README.md` | Fixed | c428929 |
| S19-006 | P2 | docs | The PX-1–PX-8 product wave appears only in RELEASE_AUDIT and BACKUP_FORMAT; DOCK_INTERACTION still says MyDock never force quits | `docs/DOCK_INTERACTION.md` | Fixed | c428929 |
| S19-007 | P2 | docs | The Claude Code limits setup is documented two contradictory ways: a jq command copied from the popout, and Enable Limits using plutil | `docs/reference/FEATURE_MATRIX.md` | Fixed | c428929 |
| S19-010 | P2 | docs | IMPLEMENTATION_STATUS.md mixes current and dated sections, and undated headings make contradictory 'current' claims | `docs/IMPLEMENTATION_STATUS.md` | Fixed | 8ad8df6 |
| S19-011 | P2 | docs | Several docs call stale 30 September–1 October evidence 'current' and say full Xcode was never built, contradicting RELEASE_AUDIT | `docs/XCODE_BUILD.md` | Fixed | 8ad8df6 |
| S19-012 | P2 | docs | The README is a wall of internal history, not a product README; proposed structure below | `README.md` | Fixed | 8ad8df6 |
| S19-013 | P2 | docs | Build requirements are wrong or incomplete: the docs say 'macOS 13 or later' for building, but the source needs the macOS 26 SDK; INSTALLATION omits the SDK en… | `docs/INSTALLATION.md` | Fixed | 8ad8df6 |
| S19-014 | P2 | privacy | A committed 881 KB session transcript at the repo root exposes the developer's local username and folder layout | `history.md` | Fixed | cae7326 |
| S19-021 | P2 | docs | Overlapping status matrices and dated Dockset research sit beside current guides; consolidation plan | `docs/PARITY_MATRIX.md` | Fixed | 8ad8df6 |
| S20-001 | P2 | privacy | Live Dock web-link drop bypasses DockLinkPolicy and stores URLs with embedded user:password | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S20-002 | P2 | test-quality | Tests assert test-only policies while production uses different code paths | `Sources/MyDock/DockManagement/DockPresentationPolicies.swift` | Fixed | 0470e4f |
| S20-003 | P2 | ux-copy | One concept has five names: Dock, Dock profile, profile, layout and preset; Apple's Dock has four | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | 6df69f5 |
| S20-004 | P2 | design-consistency | Spacing and radius tokens are almost unused; layout is driven by hundreds of magic numbers | `Sources/MyDock/UI/DockDesign.swift` | Deferred | d300ec1 |
| S20-005 | P2 | reliability | Three network-rate formatters; the popout one traps for rates at or above 2^63 bytes/s | `Sources/MyDock/CustomDock/NetworkActivityWidgetViews.swift` | Fixed | abd0ad8 |
| S20-006 | P2 | performance | ISO 8601 parser duplicated three times and allocates two formatters per call, per JSONL line in AI usage scans | `Sources/MyDock/SystemServices/AIUsageService.swift` | Fixed | 533f58d |
| S20-007 | P2 | performance | WidgetDataQuery.make does file-system symlink resolution and SHA-256 in view bodies | `Sources/MyDock/SystemServices/AIUsageService.swift` | Fixed | 533f58d |
| S20-008 | P2 | privacy | Weather uses URLSession.shared while other network clients are ephemeral; three clients hand-roll BoundedHTTPFetch | `Sources/MyDock/SystemServices/WeatherService.swift` | Fixed | 533f58d |
| S20-009 | P2 | ux | After onboarding the app is an accessory, so the Help menu (Keyboard Shortcuts, What's New) is unreachable | `Sources/MyDock/MyDockApp.swift` | Fixed | 9db1455 |
| S20-010 | P2 | ux | Modal NSAlerts are run from the non-activating Dock panel and services without activating MyDock | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S20-011 | P2 | code-quality | Widget kinds are stringly typed display names repeated across the codebase | `Sources/MyDock/Services/WidgetDataCoordinator.swift` | Deferred | e9b27a9 |
| S20-012 | P2 | code-quality | WidgetConfiguration is a 105-property union of every widget's settings, rebuilt 60 times as a fallback | `Sources/MyDock/Models/DockModels.swift` | Deferred | e9b27a9 |
| S01-009 | P3 | build | CI warning: redundant @unchecked Sendable on a UserDefaults subclass | `Sources/MyDock/Core/AppRuntimeEnvironment.swift` | Fixed | 5d7fabd |
| S01-010 | P3 | test-quality | ValidationDefaults emits no KVO or change notifications and merges registered defaults into stored values | `Sources/MyDock/Core/AppRuntimeEnvironment.swift` | Fixed | e9b27a9 |
| S01-011 | P3 | energy | LocalClockFormatter allocates a new DateFormatter on every call from per-second clock bodies | `Sources/MyDock/Models/LocalClockFormatter.swift` | Fixed | e9b27a9 |
| S01-012 | P3 | bug | AI token formatter shows "1,000K" near a million and silently ignores fractionDigits above 1 | `Sources/MyDock/Models/AIActivityPresentation.swift` | Fixed | e9b27a9 |
| S01-013 | P3 | ux | Calculator percent is always value/100, so 50+10% gives 50.1 | `Sources/MyDock/Widgets/QuickCalculator.swift` | Fixed | e9b27a9 |
| S01-014 | P3 | persistence | Hydration history grows without pruning toward a hard cap that blocks every save | `Sources/MyDock/Models/DockModels.swift` | Fixed | e9b27a9 |
| S01-015 | P3 | privacy | Sanitized history and presets keep alarm titles while other private text is stripped | `Sources/MyDock/Models/ProfileSanitizer.swift` | Fixed | d631449 |
| S01-016 | P3 | code-quality | Semantic validator bounds profile names but not item text, favicon data or several collections | `Sources/MyDock/Models/ProfileSemanticValidator.swift` | Fixed | d631449 |
| S01-017 | P3 | dead-code | Unused helpers kept alive only by tests | `Sources/MyDock/Widgets/WidgetTimingPresentation.swift` | Fixed | d631449 |
| S01-018 | P3 | code-quality | DockModels.swift is a 1,398-line catch-all and WidgetConfiguration persists every family's fields for every widget | `Sources/MyDock/Models/DockModels.swift` | Deferred | d631449 |
| S01-019 | P3 | code-quality | SingleInstanceLock derives its folder indirectly and discards the real directory error | `Sources/MyDock/Core/SingleInstanceLock.swift` | Fixed | d631449 |
| S01-020 | P3 | ux-copy | Stock range labels 22D/66D/100D and a .year case that is only 100 trading days | `Sources/MyDock/Models/DockModels.swift` | Fixed | d631449 |
| S01-021 | P3 | design-consistency | Snippet search matches substrings in the widget but word prefixes in the command palette | `Sources/MyDock/Widgets/ProductWidgetEditing.swift` | Fixed | d631449 |
| S02-011 | P3 | build | CI warning: `var snapshot` in the activity case is never mutated | `Sources/MyDock/Services/WidgetDataCoordinator.swift` | Fixed | 5d7fabd |
| S02-012 | P3 | code-quality | finishOnboarding swallows its persistence error | `Sources/MyDock/Persistence/ProfileStore.swift` | Fixed | d631449 |
| S02-013 | P3 | design-consistency | Duplicate and Restore do not give the new profile a unique name, unlike every other creation path | `Sources/MyDock/Persistence/ProfileStore.swift` | Fixed | ad1e899 |
| S02-014 | P3 | code-quality | Restore duplicates the copy-for-new-identity rules and drifts from duplication | `Sources/MyDock/Backup/BackupManager.swift` | Fixed | d631449 |
| S02-015 | P3 | ux | Validation rejections appear in the global 'MyDock data' persistence alert | `Sources/MyDock/Persistence/ProfileStore.swift` | Fixed | d631449 |
| S02-016 | P3 | bug | replaceProfiles records history before validating | `Sources/MyDock/Persistence/ProfileStore.swift` | Fixed | d631449 |
| S02-017 | P3 | ux | Restore as New from Recovery and history switches the visible Custom Dock | `Sources/MyDock/Persistence/ProfileStore.swift` | Fixed | d631449 |
| S02-018 | P3 | dead-code | Unused API surface across the persistence slice | `Sources/MyDock/Persistence/ProfileStore.swift` | Fixed | d631449 |
| S02-019 | P3 | code-quality | Four separate private-file writers with different durability and permission guarantees | `Sources/MyDock/Persistence/ProfileLibrary.swift` | Fixed | ad1e899 |
| S02-020 | P3 | docs | BACKUP_FORMAT.md contradicts itself and the code on account IDs and drafts | `docs/BACKUP_FORMAT.md` | Fixed | 8ad8df6 |
| S02-021 | P3 | ux-copy | Misleading copy: Focus filter subtitle with no profile, and the utility-draft count limit | `Sources/MyDock/Focus/FocusDockFilterIntent.swift` | Fixed | d631449 |
| S02-022 | P3 | privacy | Persistence and cache failures write Foundation error text to the unified log as public | `Sources/MyDock/Persistence/ProfileStore.swift` | Fixed | d631449 |
| S02-023 | P3 | ux | One conflicting draft blocks saving every other draft at quit | `Sources/MyDock/Services/ProfileEditSessionCoordinator.swift` | Fixed | ad1e899 |
| S03-014 | P3 | ux-copy | Keychain read failures say 'could not be saved', and a corrupt Shopify Keychain entry is reported as a bad Shopify response | `Sources/MyDock/SystemServices/ShopifyDataService.swift` | Fixed | f08e9bd |
| S03-015 | P3 | ux-copy | Several error mappings give misleading messages (timeouts as unreadable data, HTTP 429 or decode as 'check your connection', a busy location request as weather… | `Sources/MyDock/SystemServices/WeatherService.swift` | Fixed | f08e9bd |
| S03-016 | P3 | energy | Every Shopify refresh rewrites the Keychain item even when the token did not change | `Sources/MyDock/SystemServices/ShopifyDataService.swift` | Fixed | f08e9bd |
| S03-017 | P3 | security | Favicon fetcher's public-address check is a time-of-check/time-of-use DNS lookup, and ImageIO decodes any image type | `Sources/MyDock/SystemServices/SiteFaviconFetcher.swift` | Fixed | f08e9bd |
| S03-018 | P3 | code-quality | Copilot and favicon fetchers duplicate BoundedHTTPFetch's bounded-body loop without its deadline | `Sources/MyDock/SystemServices/GitHubCopilotService.swift` | Fixed | f08e9bd |
| S03-019 | P3 | reliability | One null value in Open-Meteo's hourly arrays fails the whole forecast | `Sources/MyDock/SystemServices/WeatherService.swift` | Fixed | f08e9bd |
| S03-020 | P3 | ux | With Location Services switched off system-wide, the current-location request waits 45 s before failing | `Sources/MyDock/SystemServices/CurrentLocationService.swift` | Fixed | f08e9bd |
| S03-021 | P3 | code-quality | Misleading names, redundant guards and unreachable code in provider clients | `Sources/MyDock/SystemServices/StripeDataService.swift` | Fixed | f08e9bd |
| S04-013 | P3 | dead-code | Dead or contradictory code in the AI services: jq status-line command, Codex `login status` branch, unused titles, tokensText, cost field | `Sources/MyDock/SystemServices/AIUsageService.swift` | Fixed | f08e9bd |
| S04-014 | P3 | bug | One-time alarms at a time inside a DST gap move permanently to the shifted hour | `Sources/MyDock/SystemServices/AlarmNotificationService.swift` | Fixed | f08e9bd |
| S04-015 | P3 | bug | Shortcut names are passed to the CLI without `--`, and catalog errors show raw, unbounded stderr | `Sources/MyDock/SystemServices/ShortcutsService.swift` | Fixed | f08e9bd |
| S04-016 | P3 | energy | Pipe readers wake every 100 ms for the whole life of an unbounded shortcut run | `Sources/MyDock/SystemServices/BoundedSubprocessCapture.swift` | Fixed | f08e9bd |
| S04-017 | P3 | design-consistency | The three notification services each implement authorization and generation tracking differently | `Sources/MyDock/SystemServices/HydrationReminderService.swift` | Fixed | f08e9bd |
| S04-018 | P3 | reliability | Alarm schedules are reconciled only at launch, while Hydration also reconciles on wake | `Sources/MyDock/SystemServices/AlarmNotificationService.swift` | Already fixed | f08e9bd |
| S04-019 | P3 | persistence | The Hydration interval domain differs between the validator (1-1440), the service clamp (30-240) and the UI | `Sources/MyDock/SystemServices/HydrationReminderService.swift` | Fixed | f08e9bd |
| S04-020 | P3 | code-quality | CodexAccountRPC framing edge cases: server-initiated requests can match our ids, and a stderr HUP can spin | `Sources/MyDock/SystemServices/CodexAccountRPC.swift` | Fixed | f08e9bd |
| S04-021 | P3 | reliability | Activity totals use trapping Int64 addition on counters from local logs, and the Grok parser throws a Codex error | `Sources/MyDock/SystemServices/AIUsageService.swift` | Fixed | f08e9bd |
| S04-022 | P3 | ux | A long ongoing timed block hides the imminent joinable meeting in the compact Calendar face | `Sources/MyDock/SystemServices/NextMeeting.swift` | Fixed | f08e9bd |
| S04-023 | P3 | ux | Enable Limits rejects symlinked settings.json with a generic message, and the rewrite escapes slashes | `Sources/MyDock/SystemServices/AIAccountService.swift` | Fixed | f08e9bd |
| S04-024 | P3 | ux-copy | The same weekly quota window is titled 'Weekly' for Codex and '7 days' for Claude | `Sources/MyDock/SystemServices/AIUsageService.swift` | Fixed | f08e9bd |
| S05-018 | P3 | reliability | Some Accessibility calls run without a messaging timeout (default 6 s) | `Sources/MyDock/SystemServices/WindowAccessibilityService.swift` | Fixed | 9db1455 |
| S05-019 | P3 | energy | Preview housekeeping does disk and ScreenCaptureKit work when nothing can be captured | `Sources/MyDock/SystemServices/WindowAccessibilityService.swift` | Fixed | 461cb48 |
| S05-020 | P3 | code-quality | DockBadgeReader bypasses the native-effects boundary and the shared scheduler | `Sources/MyDock/SystemServices/DockBadgeService.swift` | Fixed | 57f5c0a |
| S05-021 | P3 | ux | Text badges are cut mid-word without an ellipsis | `Sources/MyDock/SystemServices/DockBadgeService.swift` | Fixed | 57f5c0a |
| S05-022 | P3 | ux-copy | AppLauncher shows 'Could not open item' for quit, hide and force-quit failures | `Sources/MyDock/SystemServices/AppLauncher.swift` | Fixed | 57f5c0a |
| S05-023 | P3 | ux-copy | Raw status codes and Swift error descriptions reach the UI | `Sources/MyDock/SystemServices/AudioOutputService.swift` | Fixed | 57f5c0a |
| S05-024 | P3 | dead-code | Production-unused helpers kept alive only by tests | `Sources/MyDock/SystemServices/WindowAccessibilityService.swift` | Fixed | 57f5c0a |
| S05-025 | P3 | security | Dock link items are opened without re-validating the URL scheme | `Sources/MyDock/SystemServices/AppLauncher.swift` | Fixed | 57f5c0a |
| S05-026 | P3 | persistence | One undecodable shortcut drops every stored shortcut, which the next save then overwrites | `Sources/MyDock/SystemServices/GlobalShortcutController.swift` | Fixed | 57f5c0a |
| S05-027 | P3 | code-quality | Hot-key handler ignores the EventHotKeyID signature | `Sources/MyDock/SystemServices/GlobalShortcutController.swift` | Fixed | 57f5c0a |
| S05-028 | P3 | bug | Memory 'used' and startup-volume 'available' disagree with Activity Monitor and Finder | `Sources/MyDock/SystemServices/SystemActivityReader.swift` | Fixed | 57f5c0a |
| S05-029 | P3 | reliability | The refresh after a playback command is dropped while a periodic read is in flight | `Sources/MyDock/SystemServices/NowPlayingService.swift` | Fixed | 461cb48 |
| S05-030 | P3 | ux | Now Playing position only advances every 5 s; updatedAt is never used to extrapolate | `Sources/MyDock/SystemServices/NowPlayingService.swift` | Fixed | 57f5c0a |
| S05-031 | P3 | bug | Start Workspace reports 'Stopped' when Cancel is pressed during the last target, and ignores Task cancellation | `Sources/MyDock/SystemServices/WorkspaceStarter.swift` | Fixed | 57f5c0a |
| S05-032 | P3 | performance | App icon loader validates the bundle before checking its cache; catalog scans are not reused | `Sources/MyDock/SystemServices/InstalledAppCatalog.swift` | Fixed | 57f5c0a |
| S05-033 | P3 | bug | Folder popout treats symlinked folders as files | `Sources/MyDock/SystemServices/FolderContentsReader.swift` | Fixed | 57f5c0a |
| S05-034 | P3 | reliability | Network rates use 32-bit interface counters | `Sources/MyDock/SystemServices/NetworkActivityReader.swift` | Deferred | 57f5c0a |
| S05-035 | P3 | performance | Audio Output reads all devices synchronously on the main actor | `Sources/MyDock/SystemServices/AudioOutputService.swift` | Deferred | 57f5c0a |
| S06-016 | P3 | dead-code | Production policies used only by tests, or superseded, plus dead branches in the view | `Sources/MyDock/DockManagement/DockPresentationPolicies.swift` | Fixed | 0470e4f |
| S06-017 | P3 | code-quality | Size bounds, padding and screen selection are duplicated as magic numbers | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-018 | P3 | design-consistency | Motion literals bypass DockDesign.Motion, and the Reduce Motion source is inconsistent | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-019 | P3 | design-consistency | Ad-hoc colours, materials and opacities outside DockDesign | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-020 | P3 | ux-copy | Conflicting help and labels, mixed Finder wording, and a modal alert for success | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-021 | P3 | bug | The system Trash menu offers Duplicate Widget, which does nothing | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-022 | P3 | accessibility | Menu selection shows a checkmark image instead of a native checked state | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-023 | P3 | reliability | The popover binding setter dismisses every tab no matter which tile's popover closed | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-024 | P3 | code-quality | Section boundaries are identified by magic strings | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S06-025 | P3 | test-quality | Recent-apps and menu tests check constants or no-ops, and drop routing has no tests | `Sources/MyDock/DockManagement/DockEssentials.swift` | Fixed | 0470e4f |
| S07-019 | P3 | performance | Status menu and activation policy rebuilt on every store state publication | `Sources/MyDock/MyDockApp.swift` | Fixed | 57f5c0a |
| S07-020 | P3 | dead-code | Unused SwiftUI MenuBarView duplicates the AppKit status menu | `Sources/MyDock/UI/MenuBarView.swift` | Fixed | e2a872c |
| S07-021 | P3 | ux | Escape-to-dismiss for window previews cannot fire while another app is frontmost | `Sources/MyDock/DockManagement/DockWindowPreviewController.swift` | Fixed | 57f5c0a |
| S07-022 | P3 | ux | Any MyDock menu, including Settings pop-ups, reveals the auto-hidden Dock | `Sources/MyDock/DockManagement/DockRevealMonitor.swift` | Fixed | 57f5c0a |
| S07-023 | P3 | ux-copy | Rule times always show in 24-hour format regardless of locale | `Sources/MyDock/Services/AutomaticSwitching.swift` | Fixed | 57f5c0a |
| S07-024 | P3 | ux | A second failed 'Retry Save' at quit cancels the quit silently | `Sources/MyDock/MyDockApp.swift` | Fixed | 57f5c0a |
| S07-025 | P3 | privacy | Window thumbnails stay in memory after the preview closes | `Sources/MyDock/DockManagement/DockWindowPreviewController.swift` | Fixed | 57f5c0a |
| S07-026 | P3 | code-quality | showWindow builds the hosting view twice for new windows; workspace frame is not remembered | `Sources/MyDock/MyDockApp.swift` | Fixed | 57f5c0a |
| S07-027 | P3 | code-quality | Transaction journal path is derived indirectly and escapes the validation ApplicationSupport folder | `Sources/MyDock/DockManagement/NativeDockController.swift` | Fixed | 57f5c0a |
| S08-009 | P3 | design-consistency | Increase Contrast outlines use four different opacities instead of DockDesign.Outline | `Sources/MyDock/CustomDock/WidgetPrimitives.swift` | Fixed | b27a974 |
| S08-010 | P3 | dead-code | Unused compatibility primitives and a misleading WidgetDesign.surface comment | `Sources/MyDock/CustomDock/WidgetAppearance.swift` | Fixed | b27a974 |
| S08-011 | P3 | ux | Icon style is hidden for Sticky Note and Time Progress although their faces draw the family icon | `Sources/MyDock/CustomDock/WidgetAppearance.swift` | Fixed | b27a974 |
| S08-012 | P3 | code-quality | ModuleStack.keepsLeading is documented as leading alignment but alignment ignores it | `Sources/MyDock/CustomDock/WidgetPrimitives.swift` | Fixed | b27a974 |
| S08-013 | P3 | design-consistency | Hard-coded system fonts bypass DockDesign type tokens across faces, appearance controls, freshness line and window previews | `Sources/MyDock/CustomDock/DockWindowPreviewPanel.swift` | Fixed | b27a974 |
| S08-014 | P3 | design-consistency | Dark material colour literal duplicated three times and colour-scheme rule duplicated inline | `Sources/MyDock/CustomDock/DockMaterialSurface.swift` | Fixed | b27a974 |
| S08-015 | P3 | code-quality | Module height 54 is a magic number repeated across the widget foundation | `Sources/MyDock/CustomDock/WidgetPrimitives.swift` | Fixed | b27a974 |
| S08-016 | P3 | bug | Face numbers use String(format:) and ignore the locale's decimal separator | `Sources/MyDock/CustomDock/WidgetPrimitives.swift` | Fixed | b27a974 |
| S08-017 | P3 | ux-copy | Inconsistent or awkward copy in appearance controls and faces | `Sources/MyDock/CustomDock/WidgetAppearance.swift` | Fixed | b27a974 |
| S08-018 | P3 | reliability | Freshness edge cases: future timestamps read as fresh "Updated in N minutes"; Watchlist ignores never-loaded tickers | `Sources/MyDock/CustomDock/WidgetFreshnessView.swift` | Fixed | b27a974 |
| S08-019 | P3 | performance | DockLayoutPreview observes live monitors and rebuilds a second render model even when live data is off | `Sources/MyDock/CustomDock/DockLayoutPreview.swift` | Fixed | b27a974 |
| S08-020 | P3 | accessibility | Undo notice is not announced and disappears on a fixed 15 s timer | `Sources/MyDock/CustomDock/CollectionUndo.swift` | Fixed | b27a974 |
| S08-021 | P3 | accessibility | Window preview loading label is attached to a non-element container | `Sources/MyDock/CustomDock/DockWindowPreviewPanel.swift` | Fixed | e8f486b |
| S08-022 | P3 | bug | Battery face ForEach can receive duplicate IDs for same-named accessories | `Sources/MyDock/CustomDock/WidgetPrimitives.swift` | Fixed | e8f486b |
| S08-023 | P3 | ux | Unchanged market price is coloured as a gain | `Sources/MyDock/CustomDock/WidgetPrimitives.swift` | Fixed | e8f486b |
| S08-024 | P3 | reliability | Dock theme override relies on SwiftUI colorScheme resolving dynamic NSColors | `Sources/MyDock/CustomDock/DockMaterialSurface.swift` | Fixed | e8f486b |
| S09-013 | P3 | accessibility | Trash Dock face VoiceOver value says "1 items in home Trash" | `Sources/MyDock/CustomDock/TrashWidgetViews.swift` | Fixed | e8f486b |
| S09-014 | P3 | accessibility | Battery Dock face VoiceOver value uses the raw IOKit name instead of the display name | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | e8f486b |
| S09-015 | P3 | ux-copy | Battery says "Not charging" whenever the Mac runs on battery; power-source state is never read | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | e8f486b |
| S09-016 | P3 | design-consistency | Battery popout has no hero and colours the normal state green, unlike the other reading families | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | e8f486b |
| S09-017 | P3 | design-consistency | Disk Space popout ignores the widget's configured accent that its Dock face uses | `Sources/MyDock/CustomDock/UtilityWidgetViews.swift` | Fixed | e8f486b |
| S09-018 | P3 | ux | Disk Space conflates loading with failure, never shows refresh progress, and labels the home volume "Startup Disk" | `Sources/MyDock/CustomDock/UtilityWidgetViews.swift` | Fixed | a2d8a8d |
| S09-019 | P3 | code-quality | WidgetCompactView keeps a hard-coded kind list that duplicates the provider registry | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | e8f486b |
| S09-020 | P3 | dead-code | Unused properties, an untested-only helper and stray blank lines in WidgetViews.swift | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | e8f486b |
| S09-021 | P3 | ux-copy | World Clock city rows say "+2 day" and disagree with the hero's shared day-relation wording | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | e8f486b |
| S09-022 | P3 | ux-copy | Percentages, volumes and byte limits are built by string interpolation instead of locale-aware formatting | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | e8f486b |
| S09-023 | P3 | ux | Shortcuts popout flashes "(not found)" while loading, styles an empty catalog as an error, and adds its own refresh row | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | e8f486b |
| S09-024 | P3 | ux-copy | Quick Checklist empty state stacks three lines of copy | `Sources/MyDock/CustomDock/UtilityWidgetViews.swift` | Fixed | e8f486b |
| S09-025 | P3 | ux | Trash "Empty Trash on All Volumes" is gated on the home-Trash count, and its failure alert has no path to the Automation setting | `Sources/MyDock/CustomDock/TrashWidgetViews.swift` | Fixed | e8f486b |
| S09-026 | P3 | design-consistency | AirDrop popout mixes AppKit and ad-hoc controls and routes through the generic sharing picker | `Sources/MyDock/CustomDock/AirDropWidgetViews.swift` | Fixed | e8f486b |
| S09-027 | P3 | reliability | AirDrop Dock-tile drops that fail to load or validate are silently accepted | `Sources/MyDock/CustomDock/AirDropWidgetViews.swift` | Fixed | e8f486b |
| S09-028 | P3 | code-quality | Shared singletons are held with @StateObject | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | e8f486b |
| S09-029 | P3 | code-quality | Hydration opens Notification settings directly, bypassing the isolated-validation gate | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | e8f486b |
| S09-030 | P3 | design-consistency | Popout hero and control typography are hard-coded and duplicated instead of DockDesign tokens | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | e8f486b |
| S09-031 | P3 | accessibility | Placeholder face has no accessibility label | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | e8f486b |
| S09-032 | P3 | code-quality | WidgetViews.swift (1,959 lines) mixes the popout shell, shared controls and eleven families; popout vocabulary is misfiled in UtilityWidgetViews | `Sources/MyDock/CustomDock/WidgetViews.swift` | Deferred | e8f486b |
| S10-017 | P3 | ux | Now Playing progress jumps every 5 seconds and long tracks show minutes over 60 | `Sources/MyDock/CustomDock/NowPlayingWidgetViews.swift` | Fixed | abd0ad8 |
| S10-018 | P3 | ux-copy | Calendar module says "Unavailable" before access was ever requested; one empty state is unreachable | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | abd0ad8 |
| S10-019 | P3 | ux | Reminders wide face always says "Selected reminders" instead of the list name | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | abd0ad8 |
| S10-020 | P3 | ux-copy | Reminders settings footer claims the pickers change Reminders lists | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | abd0ad8 |
| S10-021 | P3 | ux | Reminders undo banner never expires and the add field stays active when access is denied | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | abd0ad8 |
| S10-022 | P3 | bug | Ongoing multi-day events show an end time without its day, and the face and row use different words | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | abd0ad8 |
| S10-023 | P3 | energy | Popouts mirror configuration into @State and write it back on appear, causing extra store writes and duplicate loads | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | abd0ad8 |
| S10-024 | P3 | reliability | Rejected configuration updates are ignored, and drops on a full shelf are accepted silently | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | abd0ad8 |
| S10-025 | P3 | design-consistency | Gallery header button style used for in-popout actions | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | abd0ad8 |
| S10-026 | P3 | design-consistency | Raw system colours instead of WidgetPalette and DockProfileColor tokens | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | abd0ad8 |
| S10-028 | P3 | ux-copy | Collection and alarm popouts carry several permanent captions and long status messages | `Sources/MyDock/CustomDock/DockUtilityWidgetViews.swift` | Fixed | abd0ad8 |
| S10-029 | P3 | ux | File Shelf rows cannot be opened by click or Return; copy controls differ between Snippets and Links | `Sources/MyDock/CustomDock/DockUtilityWidgetViews.swift` | Fixed | abd0ad8 |
| S10-030 | P3 | ux | Snippet and link size limits are enforced only by a generic save error | `Sources/MyDock/CustomDock/DockUtilityWidgetViews.swift` | Fixed | abd0ad8 |
| S10-031 | P3 | code-quality | CalendarRemindersWidgetViews.swift duplicates the lookup, staleness and refresh-trigger code four times | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | abd0ad8 |
| S10-032 | P3 | test-quality | Calendar QA fixtures bypass selection and all-day filtering and depend on the time of day | `Sources/MyDock/CustomDock/CalendarQAFixture.swift` | Fixed | abd0ad8 |
| S10-033 | P3 | design-consistency | Calendar hero event is repeated as the only row in the Next Event layout | `Sources/MyDock/CustomDock/CalendarRemindersWidgetViews.swift` | Fixed | abd0ad8 |
| S10-034 | P3 | ux | Alarm offers no snooze or stop action and removes alarms without undo | `Sources/MyDock/CustomDock/AlarmWidgetViews.swift` | Fixed | abd0ad8 |
| S10-035 | P3 | design-consistency | Folder popout uses its own chrome instead of the popout design system | `Sources/MyDock/CustomDock/FolderContentsPopout.swift` | Fixed | abd0ad8 |
| S11-011 | P3 | dead-code | Unused types, properties, state and an unreachable status-line block in the slice | `Sources/MyDock/CustomDock/AIUsageWidgetViews.swift` | Fixed | abd0ad8 |
| S11-012 | P3 | bug | Narrow AI Activity value shows "1,000K" or "1,000M" at scale boundaries | `Sources/MyDock/CustomDock/AIUsageWidgetViews.swift` | Fixed | abd0ad8 |
| S11-013 | P3 | ux | AI Limits face window title cuts names mid-word and shows sub-day windows in minutes | `Sources/MyDock/CustomDock/AIUsageWidgetViews.swift` | Fixed | abd0ad8 |
| S11-014 | P3 | ux-copy | Weather forecast length reads "1 hours" | `Sources/MyDock/CustomDock/WeatherWidgetViews.swift` | Fixed | abd0ad8 |
| S11-016 | P3 | design-consistency | Raw colours and fonts instead of DockDesign/WidgetPalette tokens, and inconsistent error styling across these families | `Sources/MyDock/CustomDock/AIUsageWidgetViews.swift` | Fixed | abd0ad8 |
| S11-017 | P3 | design-consistency | AI Activity draws its own freshness line and refresh button in the body instead of using the shell header | `Sources/MyDock/CustomDock/AIUsageWidgetViews.swift` | Fixed | abd0ad8 |
| S11-018 | P3 | ux-copy | Market hero does not label its one-session change or end-of-day close, and Stock and Watchlist heroes differ | `Sources/MyDock/CustomDock/StockWidgetViews.swift` | Fixed | abd0ad8 |
| S11-019 | P3 | bug | "Open on Yahoo Finance" opens the wrong page for non-US Alpha Vantage symbols | `Sources/MyDock/CustomDock/StockWidgetViews.swift` | Fixed | abd0ad8 |
| S11-020 | P3 | persistence | Pickers have no tag for values that decoding accepts, so they render blank | `Sources/MyDock/CustomDock/StockWidgetViews.swift` | Fixed | d807b42 |
| S11-021 | P3 | accessibility | The volume slider's draft value may never clear after keyboard or VoiceOver changes | `Sources/MyDock/CustomDock/AudioOutputWidgetViews.swift` | Fixed | d807b42 |
| S11-022 | P3 | ux | Audio Output popout hides its device list, volume, mute and errors while Customize is open | `Sources/MyDock/CustomDock/AudioOutputWidgetViews.swift` | Fixed | d807b42 |
| S11-023 | P3 | bug | Watchlist popout shows no chart when the saved selection is not in the list, though the face falls back to the first stock | `Sources/MyDock/CustomDock/StockWidgetViews.swift` | Fixed | d807b42 |
| S11-024 | P3 | performance | WeatherHourLabel builds a DateFormatter and resolves two templates per hour label per render | `Sources/MyDock/CustomDock/WeatherWidgetViews.swift` | Fixed | d807b42 |
| S11-025 | P3 | code-quality | Weather popout mirrors four settings into @State with two-way onChange syncing | `Sources/MyDock/CustomDock/WeatherWidgetViews.swift` | Fixed | d807b42 |
| S11-026 | P3 | ux | Weather wind and precipitation stay km/h and mm when the user picks °F | `Sources/MyDock/CustomDock/WeatherWidgetViews.swift` | Fixed | d807b42 |
| S11-027 | P3 | accessibility | Watchlist reorder and remove exist only in a context menu, with no accessibility actions | `Sources/MyDock/CustomDock/StockWidgetViews.swift` | Fixed | d807b42 |
| S11-028 | P3 | code-quality | @StateObject wraps the AudioOutputService singleton | `Sources/MyDock/CustomDock/AudioOutputWidgetViews.swift` | Fixed | d807b42 |
| S12-009 | P3 | reliability | The Network popout's private rateText can trap on a huge rate; it is one of three diverging copies of the same formatter | `Sources/MyDock/CustomDock/NetworkActivityWidgetViews.swift` | Already fixed | d807b42 |
| S12-010 | P3 | concurrency | NetworkActivityMonitor.sample writes state after sampling has stopped and hides read failures behind a frozen 'Updated just now' | `Sources/MyDock/CustomDock/NetworkActivityWidgetViews.swift` | Fixed | d807b42 |
| S12-011 | P3 | ux | Memory pressure usually reads 'Awaiting event' for the whole session | `Sources/MyDock/CustomDock/SystemActivityWidgetViews.swift` | Fixed | d807b42 |
| S12-012 | P3 | ux-copy | The sampling interval is described two or three times, the copy sits above the reading, and the Network settings disclosure contains no settings | `Sources/MyDock/CustomDock/NetworkActivityWidgetViews.swift` | Fixed | d807b42 |
| S12-013 | P3 | ux-copy | The Explore storage tooltip explains CPU, load and memory, and the re-scan button is labelled 'Again' | `Sources/MyDock/CustomDock/SystemActivityWidgetViews.swift` | Fixed | d807b42 |
| S12-014 | P3 | design-consistency | Raw .orange and hand-built rows are used instead of design-system tokens and primitives | `Sources/MyDock/CustomDock/SystemActivityWidgetViews.swift` | Fixed | d807b42 |
| S12-015 | P3 | design-consistency | State colours are inconsistent between Dock faces and popout heroes | `Sources/MyDock/CustomDock/SystemActivityWidgetViews.swift` | Fixed | d807b42 |
| S12-016 | P3 | accessibility | VoiceOver gets less than the screen shows, and reads arrow glyphs | `Sources/MyDock/CustomDock/SystemActivityWidgetViews.swift` | Fixed | d807b42 |
| S12-017 | P3 | ux | Locale and number formatting gaps in uptime, file counts and compact currency | `Sources/MyDock/CustomDock/StripeWidgetViews.swift` | Fixed | d807b42 |
| S12-018 | P3 | ux-copy | The Network freshness footer can say 'Last reading just now' for a stale reading | `Sources/MyDock/CustomDock/SystemDetailSections.swift` | Fixed | d807b42 |
| S12-019 | P3 | dead-code | SystemActivityMonitor publishes lastUpdated but nothing reads it; Shopify and Paddle charts wrap one view in a ZStack | `Sources/MyDock/CustomDock/SystemActivityWidgetViews.swift` | Fixed | d807b42 |
| S12-020 | P3 | code-quality | Force-unwrapped TimeZone in chart accessibility | `Sources/MyDock/CustomDock/ShopifyWidgetViews.swift` | Fixed | d807b42 |
| S12-021 | P3 | ux-copy | Point-in-time metrics are shown with a period, and Shopify's average order value with no orders shows 'No data' in large text | `Sources/MyDock/CustomDock/StripeWidgetViews.swift` | Fixed | d807b42 |
| S12-022 | P3 | reliability | Popout connect and disconnect skip widgetData.connectionsDidChange(), unlike the Connections Center | `Sources/MyDock/CustomDock/ShopifyWidgetViews.swift` | Fixed | d807b42 |
| S12-023 | P3 | code-quality | SystemActivityPopoutWidgetView.body is about 145 lines and mixes four features | `Sources/MyDock/CustomDock/SystemActivityWidgetViews.swift` | Fixed | d807b42 |
| S12-024 | P3 | docs | The acceptance script does not cover the new System detail sections and still says to scroll to setup controls | `docs/ACCEPTANCE_TESTS.md` | Fixed | 8ad8df6 |
| S13-012 | P3 | privacy | Secret drafts linger in view state, and Integrations reads the full secrets just to show a status | `Sources/MyDock/UI/Settings/IntegrationsSettingsPage.swift` | Fixed | a639ff1 |
| S13-013 | P3 | design-consistency | Ad-hoc caption rows are copy-pasted 16 times and several have no row padding | `Sources/MyDock/UI/Settings/DockSettingsPage.swift` | Fixed | d300ec1 |
| S13-014 | P3 | dead-code | Unused design components, tokens and unreachable branches | `Sources/MyDock/UI/DockDesign.swift` | Fixed | d300ec1 |
| S13-015 | P3 | design-consistency | Hard-coded colours, ranges, radii and fonts bypass DockDesign tokens | `Sources/MyDock/UI/DesignSystem/StyleSwatch.swift` | Fixed | a639ff1 |
| S13-016 | P3 | accessibility | Accessibility labels do not start with the visible button text (breaks Voice Control) | `Sources/MyDock/UI/Settings/SettingsShared.swift` | Fixed | 924916d |
| S13-017 | P3 | accessibility | Custom-accessory rows repeat the title, and status glyphs have no label | `Sources/MyDock/UI/DesignSystem/GroupedForm.swift` | Fixed | a639ff1 |
| S13-018 | P3 | ux | Accessibility and permission status in Settings goes stale and repeats | `Sources/MyDock/UI/Settings/BehaviorSettingsPage.swift` | Fixed | a639ff1 |
| S13-019 | P3 | performance | ConnectionsCenterView decodes directories and scans every profile repeatedly per render | `Sources/MyDock/UI/ConnectionsCenterView.swift` | Fixed | 924916d |
| S13-020 | P3 | code-quality | Stringly typed providers and permission states, and a borrowed error type | `Sources/MyDock/UI/ConnectionsCenterView.swift` | Fixed | 924916d |
| S13-021 | P3 | reliability | Search-result navigation relies on a 100 ms sleep, and one entry points at the wrong card | `Sources/MyDock/UI/SettingsView.swift` | Fixed | a639ff1 |
| S13-022 | P3 | ux | Automatic switching: rule delete has no undo, and never-matching rules get no warning | `Sources/MyDock/UI/Settings/AutomaticSwitchingSettingsSection.swift` | Fixed | 924916d |
| S13-023 | P3 | ux-copy | Inconsistent terminology and weak copy across Settings | `Sources/MyDock/UI/Settings/GeneralSettingsPage.swift` | Fixed | a639ff1 |
| S13-024 | P3 | ux | "Cache window previews" is gated by a misnamed OS check and an unexplained dependency | `Sources/MyDock/UI/Settings/BehaviorSettingsPage.swift` | Fixed | 924916d |
| S13-025 | P3 | accessibility | GroupedSection clips its rows, which can cut off keyboard focus rings of full-width rows | `Sources/MyDock/UI/DesignSystem/GroupedForm.swift` | Deferred | 924916d |
| S13-026 | P3 | design-consistency | DockButtonStyle ignores button roles, so destructive buttons look like ordinary ones | `Sources/MyDock/UI/DockDesign.swift` | Fixed | 924916d |
| S13-027 | P3 | performance | Each Settings sidebar click mutates ProfileStore state | `Sources/MyDock/UI/SettingsView.swift` | Deferred | 924916d |
| S14-021 | P3 | dead-code | Unused parameters, state and command-mode branches | `Sources/MyDock/UI/CommandLibrary.swift` | Fixed | e2a872c |
| S14-022 | P3 | ux | Native apply reports success in a modal alert and can be triggered repeatedly while running | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | e2a872c |
| S14-023 | P3 | bug | Dropped URLs are classified by a case-sensitive .app path extension, including web URLs | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | e2a872c |
| S14-024 | P3 | ux | Creating a Dock from Presets does not leave Settings | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | e2a872c |
| S14-025 | P3 | design-consistency | Sheet titles, hint text and colours bypass DockDesign tokens; a second empty-state component | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | e2a872c |
| S14-026 | P3 | ux-copy | Mixed 'profile'/'Dock' terminology and misleading action labels | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | e2a872c |
| S14-027 | P3 | ux | Link editor: error shown before typing, two-sentence copy, Cancel keeps the favicon request running, unlabeled spinner | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | e2a872c |
| S14-028 | P3 | accessibility | Accessibility labels: Done renamed for VoiceOver, duplicate value reading, container label, context-free buttons | `Sources/MyDock/UI/DockInspector.swift` | Fixed | e2a872c |
| S14-029 | P3 | code-quality | Tile size range 0.65...1.5 is a magic literal repeated in six places | `Sources/MyDock/UI/DockInspector.swift` | Fixed | e2a872c |
| S14-030 | P3 | code-quality | Starter-preset profile construction duplicated in DEBUG QA | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | e2a872c |
| S14-031 | P3 | ux | Silent failures in ⌘K saved results and Save as Personal Preset | `Sources/MyDock/UI/CommandLibrary.swift` | Fixed | e2a872c |
| S14-032 | P3 | ux | ⌘K ordering: Saved results always sink below every app and command | `Sources/MyDock/UI/CommandLibrary.swift` | Fixed | f32adeb |
| S14-033 | P3 | ux | Window shortcuts are invisible in the menu bar and ⌘, is duplicated | `Sources/MyDock/UI/DockManagerView.swift` | Deferred | f32adeb |
| S14-034 | P3 | code-quality | Drag view handles Escape twice via a magic key code | `Sources/MyDock/UI/DockCanvasDragSurface.swift` | Fixed | f32adeb |
| S14-035 | P3 | test-quality | DockCanvas motion test greps source text | `Tests/MyDockTests/FX02Tests.swift` | Fixed | 8ad8df6 |
| S15-013 | P3 | dead-code | Unused helpers, unreachable branches and stale comments in the gallery | `Sources/MyDock/UI/WidgetDiscovery.swift` | Fixed | f32adeb |
| S15-014 | P3 | code-quality | WidgetLibraryTile.swift mixes a DEBUG-only variant catalog with shipping preset-tile code | `Sources/MyDock/UI/WidgetLibraryTile.swift` | Fixed | f32adeb |
| S15-015 | P3 | code-quality | AddLibrary is a 614-line view with string-typed browse actions | `Sources/MyDock/UI/AddLibrary.swift` | Deferred | f32adeb |
| S15-016 | P3 | ux | App and More search match the whole phrase, but widget search matches each word | `Sources/MyDock/UI/WidgetGallery/WidgetGalleryModel.swift` | Fixed | f32adeb |
| S15-017 | P3 | bug | Same-named apps without a version show 'Version · Folder' | `Sources/MyDock/UI/WidgetGallery/WidgetGalleryModel.swift` | Fixed | f32adeb |
| S15-018 | P3 | reliability | Returning focus to the tile depends on a 50 ms timer | `Sources/MyDock/UI/AddLibrary.swift` | Fixed | f32adeb |
| S15-019 | P3 | design-consistency | Grid width ignores always-visible scroll bars | `Sources/MyDock/UI/WidgetGallery/WidgetGalleryChrome.swift` | Fixed | f32adeb |
| S15-020 | P3 | accessibility | Invisible zero-size shortcut buttons may become Full Keyboard Access tab stops | `Sources/MyDock/UI/WidgetGallery/WidgetGalleryDetail.swift` | Fixed | f32adeb |
| S15-021 | P3 | ux | A single click on a tile waits for the double-click interval before opening the detail | `Sources/MyDock/UI/WidgetGallery/WidgetGalleryTile.swift` | Fixed | 6df69f5 |
| S15-022 | P3 | ux-copy | Copy and symbols vary between empty states, hints and notes | `Sources/MyDock/UI/AddLibrary.swift` | Fixed | f32adeb |
| S15-023 | P3 | code-quality | Force unwraps and index-0 access on catalog data in the render path | `Sources/MyDock/UI/WidgetGallery/WidgetGalleryTile.swift` | Fixed | f32adeb |
| S15-024 | P3 | test-quality | Gallery tests check helpers the views do not use, and none checks the AddLibrary keyboard wiring | `Tests/MyDockTests/RedesignGalleryTests.swift` | Fixed | 8ad8df6 |
| S15-025 | P3 | docs | IMPLEMENTATION_STATUS gives the wrong number of Add Item families | `docs/IMPLEMENTATION_STATUS.md` | Fixed | 8ad8df6 |
| S16-013 | P3 | ux-copy | Onboarding review copy is inaccurate and long; placement summary says "widget(s)" | `Sources/MyDock/UI/OnboardingView.swift` | Fixed | f32adeb |
| S16-014 | P3 | docs | Keyboard Shortcuts catalog claims to be read from code but is hand-maintained and incomplete | `Sources/MyDock/UI/ProductPolish.swift` | Fixed | f32adeb |
| S16-015 | P3 | code-quality | What's New is keyed only to the marketing version, not to the table it shows | `Sources/MyDock/UI/ProductPolish.swift` | Fixed | f32adeb |
| S16-016 | P3 | ux-copy | Starter preset fallback notes derive app names from bundle IDs ("finder", "mail", "ActivityMonitor") | `Sources/MyDock/UI/DockStarterPresets.swift` | Fixed | f32adeb |
| S16-017 | P3 | ux | Error rows are truncated to two lines, and the Recovery error colour is overridden | `Sources/MyDock/UI/RecoveryCenterView.swift` | Fixed | f32adeb |
| S16-018 | P3 | ux | Start Workspace: Escape does nothing after the run, and an "Also switch" failure is reported behind the sheet | `Sources/MyDock/UI/WorkspaceViews.swift` | Fixed | f32adeb |
| S16-019 | P3 | ux | Exporting a Dock from the Docks window gives no confirmation, and an old export error stays visible | `Sources/MyDock/UI/PortableDockSheets.swift` | Fixed | f32adeb |
| S16-020 | P3 | performance | AboutView reads AppIcon.icns from disk on every body evaluation | `Sources/MyDock/UI/AboutView.swift` | Fixed | f32adeb |
| S16-021 | P3 | bug | Onboarding Display picker has no tag for a saved display that is disconnected, and enumerates screens on every render | `Sources/MyDock/UI/OnboardingView.swift` | Fixed | f32adeb |
| S16-022 | P3 | accessibility | Shortcut capture view is invisible to VoiceOver and claims first responder twice | `Sources/MyDock/UI/KeyboardShortcutEditor.swift` | Fixed | f32adeb |
| S16-023 | P3 | ux | Widget settings sheet hides the save-failure notice for hero-only families (Clock, Audio Output) | `Sources/MyDock/UI/WidgetConfigurationSheet.swift` | Fixed | f32adeb |
| S17-015 | P3 | dead-code | render(fixtureClick:) synthetic click path is unused | `Sources/MyDock/UI/PremiumVisualQA.swift` | Fixed | 8ad8df6 |
| S17-016 | P3 | code-quality | PremiumVisualQA.export is a 17-branch env if-chain over a 738-line file; render() reads an env flag | `Sources/MyDock/UI/PremiumVisualQA.swift` | Fixed | 8ad8df6 |
| S17-017 | P3 | privacy | Focused and gallery QA exports read and write the developer's real installed-app inventory | `Sources/MyDock/UI/PremiumVisualQA.swift` | Fixed | 8ad8df6 |
| S17-018 | P3 | code-quality | SettingsQASectionView reads @State-backed sections of a SettingsView that is never installed | `Sources/MyDock/UI/RedesignQA/SettingsQA.swift` | Fixed | 8ad8df6 |
| S17-019 | P3 | concurrency | exportFocusedUI starts an unstructured refresh Task that is never awaited or cancelled | `Sources/MyDock/UI/PremiumVisualQA.swift` | Fixed | 8ad8df6 |
| S17-020 | P3 | code-quality | QA package names leak into shipping types and fixture seams are interleaved per property | `Sources/MyDock/CustomDock/StripeWidgetViews.swift` | Fixed | d807b42 |
| S17-021 | P3 | build | Two app-icon sources: SwiftPM regenerates the icon every build, Xcode ships a checked-in .icns | `BuildMyDock.sh` | Fixed | 8ad8df6 |
| S17-022 | P3 | build | TestMyDock.sh leaves a validation root behind on every run | `TestMyDock.sh` | Fixed | 8ad8df6 |
| S17-023 | P3 | build | .gitignore gaps and a stale tracked .vscode configuration | `.gitignore` | Fixed | 8ad8df6 |
| S17-024 | P3 | docs | Build docs describe a toolchain and entitlement set that no longer match | `docs/XCODE_BUILD.md` | Fixed | 8ad8df6 |
| S17-025 | P3 | ci | Workflow hygiene: unpinned actions, no warning budget, duplicate push and PR runs | `.github/workflows/validate.yml` | Fixed | 8ad8df6 |
| S17-026 | P3 | test-quality | Small QA inaccuracies: mislabeled export, redundant cases, string-matched coverage filter | `Sources/MyDock/UI/PremiumVisualQA.swift` | Fixed | 8ad8df6 |
| S17-027 | P3 | reliability | WriteReleaseManifest hides the failing tool's output | `Scripts/WriteReleaseManifest.py` | Fixed | 8ad8df6 |
| S18-010 | P3 | test-quality | Several tests cannot fail for the behaviour their names claim | `Tests/MyDockTests/PX1DockEssentialsTests.swift` | Fixed | b3b5868 |
| S18-011 | P3 | test-quality | Brittle source-scanning tests assert on raw Swift text | `Tests/MyDockTests/FX02Tests.swift` | Fixed | b3b5868 |
| S18-012 | P3 | code-quality | MainActor isolation warnings in tests (CI warnings) | `Tests/MyDockTests/RedesignFacesATests.swift` | Already fixed | b3b5868 |
| S18-013 | P3 | test-quality | Process-wide singletons and static overrides are mutated by parallel tests | `Tests/MyDockTests/PopoutLayoutLoopTests.swift` | Fixed | b3b5868 |
| S18-014 | P3 | code-quality | Duplicated fixtures and inconsistent polling helpers across test files | `Tests/MyDockTests/DockAuditRegressionTests.swift` | Deferred | b3b5868 |
| S18-015 | P3 | test-quality | Two independent golden tables of widget widths must be edited for every width change | `Tests/MyDockTests/RedesignWidgetChromeTests.swift` | Fixed | b3b5868 |
| S18-016 | P3 | reliability | Unbounded waits can hang the whole test run until the 30-minute CI timeout | `Tests/MyDockTests/ProfileStoreTests.swift` | Fixed | b3b5868 |
| S18-017 | P3 | test-quality | Absence checks after a fixed sleep can pass without proving anything | `Tests/MyDockTests/RoutineCommitCoalescingTests.swift` | Deferred | b3b5868 |
| S18-018 | P3 | code-quality | ProfileStoreTests.swift is a 2,934-line catch-all and other test files are named after milestones | `Tests/MyDockTests/ProfileStoreTests.swift` | Deferred | b3b5868 |
| S18-019 | P3 | test-quality | Several tests leak temporary directories | `Tests/MyDockTests/ReliabilityDemandCancellationTests.swift` | Fixed | b3b5868 |
| S18-020 | P3 | test-gap | Audio Output change-notification and hardware-error paths are untested | `Sources/MyDock/SystemServices/AudioOutputService.swift` | Fixed | 57f5c0a |
| S18-021 | P3 | test-gap | AutomaticSwitchingController stop, clock-change and store-observation paths are untested | `Sources/MyDock/Services/AutomaticSwitchingController.swift` | Fixed | 57f5c0a |
| S18-022 | P3 | test-gap | ProfileLibrary bounds and corrupt-file protection are untested; remove/clear lack the load-error guard | `Sources/MyDock/Persistence/ProfileLibrary.swift` | Fixed | d631449 |
| S18-023 | P3 | test-gap | Release-manifest DMG verification has no tests and one Python test is misnamed | `Tests/Tooling/test_release_manifest.py` | Fixed | b3b5868 |
| S18-024 | P3 | dead-code | Opt-in installed-app audit hard-codes one developer's Adobe install paths | `Tests/MyDockTests/InstalledAppCatalogTests.swift` | Fixed | b3b5868 |
| S18-025 | P3 | test-quality | Untyped error expectations accept any failure | `Tests/MyDockTests/WidgetUtilityTests.swift` | Fixed | b3b5868 |
| S19-008 | P3 | dead-code | The jq "Copy statusLine value" UI can never render, but a test still covers its command | `Sources/MyDock/CustomDock/AIUsageWidgetViews.swift` | Fixed | d807b42 |
| S19-009 | P3 | ux | Focus Timer declares the Notifications permission and Add Item shows "May request permission", but it never requests one | `Sources/MyDock/Models/DockModels.swift` | Fixed | d631449 |
| S19-015 | P3 | docs | Agent prompt and stale undated build baseline sit in docs/ beside the user guides | `docs/FULL_APP_AUDIT_PROMPT.md` | Fixed | 6325b9e |
| S19-016 | P3 | docs | The documentation index omits several current guides | `docs/README.md` | Fixed | b3b5868 |
| S19-017 | P3 | docs | Three of the five opt-in test gates are undocumented, and the performance opt-in writes into docs/ root against the dated-history rule | `docs/ACCEPTANCE_TESTS.md` | Fixed | b3b5868 |
| S19-018 | P3 | docs | FEATURE_MATRIX and PARITY_MATRIX contradict the current code on repair and on the Permissions tab | `docs/reference/FEATURE_MATRIX.md` | Fixed | b3b5868 |
| S19-019 | P3 | ux-copy | Permissions page status copy ignores window previews and badges, yet the hover panel's "Show thumbnails…" sends users there | `Sources/MyDock/UI/Settings/PermissionsSettingsPage.swift` | Fixed | 924916d |
| S19-020 | P3 | docs | Broken bold markup in RELEASE_AUDIT | `docs/RELEASE_AUDIT.md` | Fixed | b3b5868 |
| S19-022 | P3 | docs | Install and uninstall guides use stale labels and an old project name, and omit two credential types | `docs/UNINSTALL.md` | Fixed | b3b5868 |
| S19-023 | P3 | docs | BACKUP_FORMAT's list of what widget configuration covers predates the Everyday Tools, and it does not say personal data is included by default | `docs/BACKUP_FORMAT.md` | Fixed | b3b5868 |
| S20-013 | P3 | dead-code | Unused views, helpers and tokens compiled into Release, including the legacy MenuBarView | `Sources/MyDock/UI/MenuBarView.swift` | Fixed | f32adeb |
| S20-014 | P3 | ux-copy | Menu and button titles mix title and sentence case and name one action several ways | `Sources/MyDock/DockManagement/CustomDockView.swift` | Fixed | 0470e4f |
| S20-015 | P3 | code-quality | Largest files and functions need splitting along existing seams | `Sources/MyDock/DockManagement/CustomDockView.swift` | Deferred | 0470e4f |
| S20-016 | P3 | design-consistency | Status colours bypass the semantic palette; red and orange both mean error; decorative orange | `Sources/MyDock/UI/DockManagerView.swift` | Fixed | f32adeb |
| S20-017 | P3 | reliability | System Settings deep links are duplicated and most skip the isolated-session guard | `Sources/MyDock/UI/Settings/BehaviorSettingsPage.swift` | Fixed | a639ff1 |
| S20-018 | P3 | reliability | Logging is split between NSLog, os.Logger and DiagnosticsService; recovery failure is not recorded | `Sources/MyDock/MyDockApp.swift` | Fixed | 57f5c0a |
| S20-019 | P3 | reliability | Deprecated activation APIs: ignoringOtherApps has no effect on macOS 14+ | `Sources/MyDock/SystemServices/WindowAccessibilityService.swift` | Fixed | 57f5c0a |
| S20-020 | P3 | code-quality | Date, duration and percent text are formatted by several divergent helpers | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | e8f486b |
| S20-021 | P3 | design-consistency | Duplicate meter bars; the Time Progress popout asks for 6 pt but draws 3 pt | `Sources/MyDock/CustomDock/WidgetViews.swift` | Fixed | e8f486b |
| S20-022 | P3 | reliability | Fixed sleeps used to wait for SwiftUI layout and focus | `Sources/MyDock/UI/SettingsView.swift` | Fixed | 924916d |
| S20-023 | P3 | build | Compiler warnings in Sources at HEAD | `Sources/MyDock/Core/AppRuntimeEnvironment.swift` | Already fixed | d631449 |
