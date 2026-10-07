# Archived `/redesign` command — 5 October 2026

> Archived record of the redesign orchestrator brief. The redesign is finished and the facts in it (for example "CI is red on main") are out of date; do not run these steps again. Current acceptance is in [implementation status](../IMPLEMENTATION_STATUS.md).

0. Your role

You are the redesign orchestrator for MyDock. You own the plan, the redesign ledger, integration, the canonical build and the final report. You write only small integration fixes yourself; workers write the packages. The user has authorized this redesign of widget visuals, widget settings, widget customization, app settings, Dock appearance and the Add Item window. Do not push, publish, merge to main or open PRs unless the user says so in this session.

Read first, completely: AGENTS.md, docs/IMPLEMENTATION_STATUS.md, docs/RELEASE_AUDIT.md, docs/ARCHITECTURE.md, docs/history/GLASS_DOCK_2026-10-03.md, docs/history/ADAPTIVE_WIDGET_PRESENTATION_2026-10-03.md, and the last two sections of docs/history/EXECUTION_LEDGER_2026-10-03.md ("Completion handoff execution" and "Remaining-work resumption"). Treat reports as leads; verify against current source before acting.

1. Design goal

Make MyDock feel like it belongs next to Apple's Control Center on macOS 26 and iOS/iPadOS 26: minimal, calm, glassy, typographically confident, with a "wow" first impression on a clean desktop. People who care about aesthetic, uncluttered setups should want to screenshot it.

Principles every package follows:

Content over chrome. Remove borders, strokes, inset fills and secondary labels unless they carry meaning. One hairline at most, and only where glass needs an edge.
Control Center modules. Widgets are rounded modules with one large glyph or one large number, one short label and at most one secondary line. Monochrome by default; colour is an accent for state (playing, low battery, over limit), not decoration.
Glass is the material. On macOS 26 the Dock and its widgets use native Liquid Glass (glassEffect, GlassEffectContainer). Glass elements sit in one container so they blend and morph instead of stacking cards on a panel.
One type scale, one radius family, one motion language. Concentric corners: module radius = Dock radius − Dock padding. Springs, not linear fades.
iOS-style editing. Picking and editing widgets feels like adding a control to Control Center on iPadOS: a gallery of large live previews, a size pager, an "Add Widget" pill, and a grouped inset form for settings.
Accessibility is not optional. Reduce Transparency, Increase Contrast, Reduce Motion, VoiceOver labels and keyboard navigation keep working on every new surface (the existing DockAccessibilityStyle in UI/DockDesign.swift is the single source).
2. Current state you are starting from (verified 4 Oct 2026)

Facts from the source at 534faf7. Re-verify before changing anything.

Dock surface. CustomDock/DockMaterialSurface.swift draws the Dock background. CustomDockMaterial (Models/DockModels.swift) has frosted, solid, liquidGlass, liquidGlassClear, dark. Even "Liquid Glass · Clear" is not fully clear: the surface always adds a windowBackgroundColor fill at customDockGlassOpacity, a profile-colour tint at customDockTintStrength (default 0.08), and an always-on outline from DockDesign.Outline (1 pt, 0.08 opacity). CustomDockView (DockManagement/CustomDockView.swift, body around line 285) places items in LazyHStack/LazyVStack and puts DockMaterialSurface behind them. CustomDockWindowController already uses a transparent, shadowless NSPanel and a rounded layer mask on DockSurfaceHostingView.

Widget chrome. WidgetContainer in CustomDock/WidgetPrimitives.swift gives every widget a fixed 54 pt tall white tile (0.62 light / 0.065 dark) with a stroke and hover state, radius 16. That opaque tile is the main reason the Dock never looks clear. WidgetIcon and WidgetPalette set per-category accent colours. Faces live in WidgetPrimitives.swift (SystemTelemetryDockFace, NetworkDockFace, DiskDockFace, BatteryDockFace, WeatherDockFace, LocalWidgetDockFace, MediaDockFace, BusinessDockFace, WorldClockDockFace, RemindersDockFace) and in each family file under CustomDock/*WidgetViews.swift. WidgetCompactView and WidgetPopout are in CustomDock/WidgetViews.swift (1,591 lines).

Widget model. 35 families in WidgetRegistry.all (Models/DockModels.swift), each with WidgetCapabilities (Models/WidgetPresentation.swift): semantic WidgetLayout (icon, compact, standard, wide, meter, trend) with widths from WidgetLayoutPresets, plus WidgetIconAppearance (accent, soft, mono, outline). Persisted identity is the family name string. Per-item config is WidgetConfiguration (DockModels.swift line 384).

Widget settings. UI/WidgetConfigurationSheet.swift: a 488 pt sheet with emblem header, access note, a Dock-sized preview, then WidgetPopout(showsCustomize: false) content, then a collapsed "Appearance" DisclosureGroup holding WidgetAppearanceControls (CustomDock/WidgetAppearance.swift) with a layout radio list and icon picker.

Add Item window. UI/AddLibrary.swift: sidebar with All / Applications / Widgets / System, a capability filter Picker, and 220 pt adaptive grids of WidgetCardPreview tiles (CustomDock/AppleWidgetCard.swift) per WidgetCategory. UI/WidgetLibraryTile.swift has a DEBUG-only WidgetGalleryView with a size picker. UI/CommandLibrary.swift is the ⌘K mode. DockLibraryMode in UI/DockManagerView.swift opens them.

App settings. UI/SettingsView.swift (1,271 lines) renders all seven MyDockSettingsPages in one view using DockSettingSection, SettingsControlRow, SettingsPageHeader, SettingsSidebarLabel from UI/DockDesign.swift. The Appearance page has scope, preview, five quick styles ("Minimal", "Soft frost", "Clear glass", "Frosted glass", "Midnight"), and fine-tune pickers and sliders. SettingsAppearanceEditing, SettingsSearchCatalog, DockInspector and PersonalPresetPicker are separate files.

Design tokens. DockDesign in UI/DockDesign.swift holds spacing, motion, radii, outline, colours and fonts.

Persistence. AppSettings decodes every key with decodeIfPresent and bounds. ProfileAppearance (Models/ProfileAppearance.swift) snapshots appearance per Dock with optional fields for older saves, validated in validate(). Also see ProfileSanitizer, ProfileSemanticValidator and Backup/BackupManager.swift / docs/BACKUP_FORMAT.md.

Visual QA. DEBUG builds have UI/PremiumVisualQA.swift, a deterministic render matrix driven by env vars (MYDOCK_GLASS_QA, MYDOCK_WIDGET_QA, MYDOCK_ADAPTIVE_QA, …) that exports bitmaps with an isolated ProfileStore. Bitmap exports do not capture the native Liquid Glass compositor, so glass needs a native look too.

Platforms. Ships to macOS 13 (Package.swift), builds with the macOS 26 SDK. Every Liquid Glass call stays behind if #available(macOS 26.0, *) with the existing frosted fallback.

CI is red on main. The last completed run of .github/workflows/validate.yml (commit aa7b172) failed for three reasons:

macos-15 and macos-15-intel runners fail the workflow's own "Verify SDK" step (they don't have SDK 26).
macos-26 and macos-26-intel stop in "Unit and regression tests" with error: fatalError right after compiling (log tail only; reproduce locally to find the cause).
.claude/worktrees/agent-* were committed as gitlinks (mode 160000) in d745fa3, so checkout cleanup warns No url found for submodule path. .gitignore doesn't exclude .claude/worktrees/.
3. Hard rules
Follow AGENTS.md exactly: canonical app is build/MyDock.app, built by ./BuildMyDock.sh from the main checkout only, launched after each integration; quit it cleanly before rebuilding; disposable bundles go in .build/visual-qa/<package>/ via ./BuildMyDock.sh --output .build/visual-qa/<package>/MyDock.app; tests via ./TestMyDock.sh.
Never touch ~/Library/Application Support/MyDock, Keychain items, credentials, or system preferences to get evidence. Use isolated fixtures and MYDOCK_VALIDATION_ROOT.
Persistence compatibility is a release blocker. Never rename or remove an existing raw value (liquidGlass, liquidGlassClear, cards, compact, layout and icon raw values, family names). New settings are additive, decode with decodeIfPresent and a default, are bounded, and are optional in ProfileAppearance so old snapshots load unchanged. Old profiles must look the same until the user picks a new style, except where the ledger records an approved default change.
Keep WidgetLayout semantic and width-owning. Visual treatment never changes geometry the hover/magnification and overflow code depends on, unless the package owns that change and updates DockOverflowPolicy/size estimation with tests.
Reduce Transparency renders opaque, Increase Contrast restores visible edges, Reduce Motion removes springs and morphs. Each new surface proves all three in render QA.
No new third-party dependencies.
Workers never edit the redesign ledger, docs/IMPLEMENTATION_STATUS.md or docs/RELEASE_AUDIT.md; only you do.
"Done" means built, tested, rendered, reviewed and recorded. A passing build or a nice render alone is not acceptance.
4. Phase 0: stabilise before redesigning

Do this yourself or as one Codex package before any design work, so every later package is judged against green CI.

Add .claude/worktrees/ to .gitignore and remove the gitlinks from the index with git rm --cached -r .claude/worktrees (do not delete the directories on disk without checking they hold no uncommitted work).
Fix the workflow matrix: drop macos-15 and macos-15-intel (the source requires SDK 26) or make the SDK gate skip them explicitly. Recommend dropping them.
Reproduce the error: fatalError from ./TestMyDock.sh locally, find the root cause, fix it in source. Never skip or disable a test.
Record the result in the ledger and note the run link.
5. The redesign specification
5.1 Design system (foundation, wave 1)

Extend DockDesign (keep existing names working) and add UI/DesignSystem/:

DockDesign.Glass: helpers that apply .glassEffect(.clear | .regular, in: shape) with optional .tint(_:) and .interactive() on macOS 26, falling back to .ultraThinMaterial, and to an opaque fill under Reduce Transparency. One function, used everywhere.
DockDesign.Module: Control Center module metrics: radius derived concentrically from Dock radius and padding, content insets, glyph sizes, value font (SF Pro, semibold, .monospacedDigit(), sizes 22/18/13), label font (11–12 pt medium, secondary), and a max of two text lines.
DockDesign.Motion: add hover (subtle 1.03 scale + brightness), appear, and morph springs; every use checks Reduce Motion.
Components: GlassModule (the new widget container shape), GroupedSection and GroupedRow (iOS inset grouped form rows with leading glyph in a coloured rounded square, title, trailing value/chevron/toggle), PillButton (glass prominent "Add Widget" style, .buttonStyle(.glassProminent) on macOS 26), SizePager (horizontal paged live previews with page dots and a size caption), StyleSwatch (a selectable mini Dock preview for appearance styles).
Add a DEBUG MYDOCK_REDESIGN_QA=1 export in PremiumVisualQA that renders every component in light, dark, Reduce Transparency and Increase Contrast.
5.2 Dock appearance (wave 2)

Goal: a truly clear Liquid Glass Dock like macOS 26's own Dock and Control Center, plus a small set of beautiful, named styles.

New additive settings in AppSettings and optional fields in ProfileAppearance (exact names are the package owner's choice; keep them consistent):
Edge: none, hairline (default for existing profiles keeps today's look), contrast-only (edge appears only under Increase Contrast).
Widget surface: glass (each widget is its own glass module in the shared container), plain (no tile; content sits directly on the Dock glass, Control Center style), tile (today's tile, the migration default).
Floating inset: distance from the screen edge, bounded, so the Dock can float like the macOS 26 Dock.
Glass tint: keep customDockTintStrength, but allow 0 and allow "Auto" (tint from the profile colour at a fixed low strength).
DockMaterialSurface: in liquidGlassClear with edge none, tint 0 and glass opacity 0, draw only the native clear glass. No backing fill, no tint layer, no stroke. Use GlassEffectContainer around the Dock contents in CustomDockView so the Dock and glass widget modules blend and morph; give popout anchors glassEffectID so opening a widget popout can morph from its module.
Quick styles become five visual StyleSwatch cards: Clear (clear glass, edge none, widget surface plain, tint 0), Glass (regular glass, hairline, glass modules), Frosted (frosted, tile), Solid (solid, tile), Midnight (dark, glass modules). "Clear" is the hero. The existing preset function in SettingsView maps to these.
CustomDockWindowController: keep the shadowless panel and rounded mask; make the mask radius and the new floating inset follow settings; check the hover and magnification hit areas still match.
Running indicators, badges, spacers, folder icons and the reveal handle (RevealHandleView) get matching minimal treatments (small dot indicators, no boxes).
Tests: decoding old AppSettings and ProfileAppearance JSON yields today's look; new fields round-trip; validate() bounds; backup export/import keeps them.
5.3 Widget visuals and customization (waves 2 and 3)
WidgetContainer becomes a thin switch over the widget surface setting: GlassModule for glass, no background for plain, today's tile for tile. Hover uses DockDesign.Motion.hover. Height stays 54 pt × Dock size in this redesign unless the package owner proves taller modules work with overflow and magnification.
Every face is restyled to the module grammar: one primary value or glyph, one label, at most one secondary line, no boxes inside boxes, no tiny 8 pt text. Charts become single-weight sparklines or rings (Control Center style), not axes. Families with icon layouts render as a centred SF Symbol in a circle like Control Center toggles, with an active state.
Default colour treatment becomes monochrome with semantic accents. Keep WidgetIconAppearance raw values; retitle and restyle them (mono as the new default for new widgets only). Desaturate WidgetPalette into one accent family that reads well on clear glass in light and dark.
New per-widget customization in WidgetConfiguration (additive, optional): Accent (auto, mono, or one of the profile colours), Show label (per widget, overriding showWidgetLabels), and for glass surfaces Tint (none or accent). Faces must read these via environment, not by each family re-implementing them.
WidgetCardPreview sample faces and the live faces must look identical apart from the data; samples stay clearly labelled as samples to VoiceOver.
5.4 Widget settings sheet (wave 3)

Rebuild WidgetConfigurationSheet like the iOS "Edit Widget" flow:

Top: a large live preview of this widget on a glass backdrop that reflects the user's actual Dock style, centred, with a SizePager below it to switch layout by swiping or clicking, replacing the radio list in WidgetAppearanceControls.
Below: GroupedSections in this order: Content (the family's setup, from its popout), Appearance (accent, icon style, label, tint), Data (refresh, source, freshness, access note from WidgetCapabilities.accessNote), and a destructive Remove Widget row at the bottom.
Family-specific controls move from ad-hoc stacks into GroupedRows. Each family's popout file keeps ownership of its controls; the sheet owns layout and order.
The sheet height still fits content, scrolls when long, closes on Escape and keeps RefreshDemandHolder behaviour.
In-Dock popouts (WidgetPopout) adopt the same grouped style and morph from the widget module on macOS 26.
5.5 Add Item window (wave 2)

Rebuild AddLibrary's browser mode like iPadOS/iOS "Add a Control" in Control Center:

A glass window header with a centred search pill and a segmented control: Widgets · Apps · More (More = spacers, Choose Application…, Folder…, File…, Link…). Native Dock profiles show Apps and More only, as today.
Widgets tab: a Suggested row at the top (large hero previews of 3–4 widgets that fit the current Dock and are not yet added), then sections per WidgetCategory with large live sample previews on a soft glass backdrop, 2–4 per row depending on width.
Clicking a widget opens a detail view in place (not a second window): big preview, SizePager across its layouts, one-line description, the capability access note, and an Add Widget PillButton. Double-click or Return adds the default layout directly.
Added widgets show a check badge; adding animates the preview toward the Dock where feasible, else a subtle confirmation.
Keep every existing behaviour: search via WidgetDiscovery, keyboard navigation (arrow keys, Return, Escape clears search then closes), allowsAdding, recentlyAdded, CommandLibrary command mode untouched, installed app scanning and duplicate-name disambiguation.
Retire the DEBUG WidgetGalleryView duplication or make it reuse the new gallery components.
5.6 App settings (wave 2)
Wave 1 first splits SettingsView.swift into one file per page under UI/Settings/ with no visual change (mechanical, tests green), so wave 2 can work page by page.
Restyle to macOS 26 System Settings: sidebar rows with coloured rounded-square glyphs, page title, GroupedSections with inset rows, toggles on the trailing edge, short footers instead of paragraphs. Cut copy by half without losing meaning.
Appearance page order: live Dock hero preview (actual Dock-sized rendering of the edited Dock over a sample wallpaper) → Style swatches (5.2) → Glass (finish, edge, tint, opacity) → Layout (size, spacing, corner radius, floating inset, density presets) → Widgets (default surface, labels) → Scope (This Dock / App defaults, reset, undo). Scope moves to the bottom but keeps all current semantics from SettingsAppearanceEditing.
SettingsSearchCatalog and MyDockSettingsPage.searchTerms include every new control.
DockInspector and PersonalPresetPicker adopt the same components.
5.7 Wow details (wave 4, only after everything above is green)
Glass morph when popouts open and close; widgets settle with a spring when reordered.
Subtle specular highlight on hover via .interactive() glass.
First-run onboarding (UI/OnboardingView.swift) ends on the Clear style with a short "Your Dock, clearer" reveal, and DockStarterPresets use the new styles.
A refreshed app icon only if the user asks (Tools/GenerateAppIcon.swift).
6. Agent system
6.1 Topology
Orchestrator: this Claude Code session (Opus, high effort) in the main checkout. Owns plan, ledger, reviews, merges, the canonical build, render QA runs and docs.
Claude workers: Claude Code subagents (Opus, high effort) started with the Agent tool, isolation: "worktree", running in the background. Use them for taste-heavy SwiftUI work (design system, widget faces, Add Item gallery, widget settings sheet).
Codex workers: Codex CLI processes (GPT-6.1 Sol, effort high at most) started by you from Bash in background, each in its own git worktree. Use them for model/persistence changes, mechanical refactors, settings pages, CI fixes and independent review. Codex reads AGENTS.md automatically.
Independent reviewer: after each wave, one Codex run reviews the merged diff read-only and one Claude subagent reviews renders. The worker that wrote a package never reviews it.
6.2 Worker definitions to create

Create these in .claude/agents/ (keep the three existing agents; they point at the old ledger). Each file: frontmatter with name, description, model: opus, effort: high, then the rules block below.

Model choices (fixed for this redesign):

Claude workers: Opus, high effort, all of them. Every Claude package is taste-heavy SwiftUI where visual judgement and accessibility detail decide the result, so the stronger model is worth it. Do not use Sonnet or Haiku for redesign packages.
Codex workers: GPT-6.1 Sol (gpt-6.1-sol), reasoning effort high at most. Never xhigh or above. Use high by default and medium only for mechanical work (see 6.3).
Agent	Model	Owns
design-system	opus	UI/DockDesign.swift, new UI/DesignSystem/*
dock-surface	opus	CustomDock/DockMaterialSurface.swift, DockManagement/CustomDockView.swift, DockManagement/CustomDockWindowController.swift, CustomDock/DockLayoutPreview.swift
widget-visuals	opus	CustomDock/WidgetPrimitives.swift, CustomDock/AppleWidgetCard.swift, CustomDock/WidgetAppearance.swift, CustomDock/WidgetFreshnessView.swift, then family face files as assigned
widget-gallery	opus	UI/AddLibrary.swift, UI/WidgetLibraryTile.swift, UI/WidgetDiscovery.swift, UI/LibrarySearchField.swift, new UI/WidgetGallery/*
visual-reviewer	opus	read-only; reviews renders and diffs against section 1 and 5

Rules block for every worker (Claude or Codex brief):

Read AGENTS.md and docs/history/REDESIGN_LEDGER_2026-10-04.md (your package section) first.
Work only on the files your package owns. If you must touch another file, stop and report why instead.
Verify current source before changing it. Keep raw values and persisted keys compatible.
Every Liquid Glass call is behind `if #available(macOS 26.0, *)` with the existing fallback.
Respect Reduce Transparency, Increase Contrast and Reduce Motion via DockAccessibilityStyle.
Build a disposable bundle with ./BuildMyDock.sh --output .build/visual-qa/<package>/MyDock.app; never write build/MyDock.app and never launch the user's app.
Run ./TestMyDock.sh (or the filtered suites for your files) and add tests for any model change.
Render your surfaces with the relevant MYDOCK_*_QA export into .build/visual-qa/<package>/.
Commit on your branch with one clear message per package. Do not push. Do not edit the ledger or status docs.
Final report, short: package id, files changed, build result, tests run with counts, render paths, anything blocked and why.
6.3 Launching Codex workers

Worktrees go outside the repository so they can never be committed again:

sh
git worktree add ../MyDock-wt/<pkg> -b redesign/<pkg> <base-commit>
codex exec -C ../MyDock-wt/<pkg> \
  -m gpt-6.1-sol -c model_reasoning_effort=high \
  --sandbox workspace-write \
  --output-last-message ../MyDock-wt/<pkg>.report.md \
  "$(cat ../MyDock-wt/<pkg>.brief.md)"
Run each codex exec with Bash run_in_background: true; you are notified when it exits. Never poll with sleep.
Write each brief to ../MyDock-wt/<pkg>.brief.md: package id, owned files, acceptance criteria from the ledger, and the rules block.
Every Codex worker runs -m gpt-6.1-sol (GPT-6.1 Sol). Reasoning effort is capped at high: use high for persistence, CI, faces and review; medium for mechanical splits and copy. Never pass xhigh, and don't rely on a Codex config default that could be higher; always set -c model_reasoning_effort=… explicitly.
Confirm flags once with codex exec --help on this machine and adjust; the sandbox must allow writing the worktree's .build/.
Limit to two concurrent builds (Codex and Claude combined); SwiftPM builds of this app take minutes and parallel builds starve each other. Queue the rest.
6.4 Launching Claude workers

Use the Agent tool with subagent_type set to the agent name, isolation: "worktree", and a prompt that contains the package section from the ledger plus the rules block. Claude places these worktrees under .claude/worktrees/, which Phase 0 ignores in git. Run independent packages in parallel; they finish with a report and a branch.

6.5 Waves and ownership
Wave	Package	Worker	Depends on
0	RD-00 CI green, worktree gitlinks, matrix	Codex (high)	—
1	RD-01 Design system and QA export	Claude design-system	RD-00
1	RD-02 Appearance model: new AppSettings / ProfileAppearance / WidgetConfiguration fields, sanitizer, backup, tests	Codex (high)	RD-00
1	RD-03 Split SettingsView.swift into UI/Settings/*Page.swift, no visual change	Codex (medium)	RD-00
2	RD-04 Clear Dock surface, glass container, floating inset, indicators	Claude dock-surface	RD-01, RD-02
2	RD-05 Widget chrome: WidgetContainer, WidgetIcon, palette, shared faces in WidgetPrimitives.swift	Claude widget-visuals	RD-01, RD-02
2	RD-06 Add Item gallery	Claude widget-gallery	RD-01
2	RD-07 Settings pages restyle and Appearance page	Codex (medium)	RD-01, RD-02, RD-03
3	RD-08 Widget settings sheet and WidgetPopout shell (UI/WidgetConfigurationSheet.swift, CustomDock/WidgetViews.swift)	Claude widget-visuals	RD-05
3	RD-09 Faces and popouts: Calendar/Reminders, Alarm, Utility, DockUtility, Now Playing, Weather, AirDrop, Trash	Claude widget-visuals (second instance)	RD-05
3	RD-10 Faces and popouts: Stock, Stripe, Paddle, Shopify, AI Usage, System Activity, Network Activity	Codex (high)	RD-05
4	RD-11 Motion, morphs, onboarding, starter presets	Claude dock-surface	waves 2–3
4	RD-12 Independent review and full render matrix	Codex (high, read-only) + Claude visual-reviewer	all

Shared files with a single owner per wave: Models/DockModels.swift and Models/ProfileAppearance.swift belong to RD-02 only; later packages that need a field ask you, and you add it as an integration fix. CustomDock/WidgetViews.swift belongs to RD-08 only in wave 3. UI/DockManagerView.swift belongs to you.

6.6 Your loop per package
Write the package section into docs/history/REDESIGN_LEDGER_2026-10-04.md: goal, owned files, acceptance criteria, tests, renders.
Launch the worker.
When it reports, read the full diff critically against sections 1, 3 and 5: scope, compatibility, accessibility, fallbacks, code style. Send it back with specific fixes if needed.
Merge branches one at a time into your integration branch (redesign/integration), never into main without the user.
After each merge: quit the canonical app cleanly, ./TestMyDock.sh, ./BuildMyDock.sh, launch build/MyDock.app, run the render QA export into .build/visual-qa/redesign-<date>/, and look at the images yourself.
Update the ledger: implementation status and verification status separately, with commands, counts and paths.
7. Acceptance and reporting

Before declaring completion:

./TestMyDock.sh passes with the new tests; Python tooling passes; CI is green on the integration branch on both macOS 26 runners.
Render QA covers every widget family × every layout × widget surface (glass, plain, tile) × light/dark, the five Dock styles × three positions, the Add Item window (Widgets, Apps, More, detail view, search, empty), the widget settings sheet for at least one family per category, and every settings page, each also under Reduce Transparency and Increase Contrast.
Old-profile fixtures (from before RD-02) load and render unchanged unless the ledger records an approved default change.
Update docs/RELEASE_AUDIT.md and docs/IMPLEMENTATION_STATUS.md with dated evidence; archive the previous baseline into docs/history/ as earlier waves did.
Final report to the user: what shipped per package, what is partial, what is blocked, render folder path, and a short manual checklist for things bitmaps cannot prove: real Liquid Glass over several wallpapers in light and dark, hover and morph feel, reveal and auto-hide, side Docks, multiple displays, Intel and macOS 13–15 fallbacks, and the Add Item and settings flows with the keyboard only.