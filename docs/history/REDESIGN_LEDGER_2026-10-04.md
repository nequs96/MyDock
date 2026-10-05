# MyDock redesign ledger — 4 October 2026

Owner: Claude Opus 5.5 orchestrator (main checkout). Integration branch: `redesign/integration`, based on `main` at `534faf7`. Nothing is pushed, published or merged to `main` without the user.

The user authorized a redesign of widget visuals, widget settings, widget customization, app settings, Dock appearance and the Add Item window. Design goal: Control Center on macOS 26 / iPadOS 26. Minimal, calm, glassy and typographically confident.

Only the orchestrator edits this file, `docs/IMPLEMENTATION_STATUS.md` and `docs/RELEASE_AUDIT.md`. Implementation status and verification status are tracked separately.

## Rules every worker follows

- Read `AGENTS.md` and your package section below first.
- Work only on the files your package owns. If you must touch another file, stop and report why.
- Verify current source before changing it. Keep raw values and persisted keys compatible: `liquidGlass`, `liquidGlassClear`, `cards`, `compact`, every `WidgetLayout`/`WidgetIconAppearance`/`WidgetIconStyle` raw value, and every family name.
- Every Liquid Glass call sits behind `if #available(macOS 26.0, *)` with the existing fallback.
- Respect Reduce Transparency, Increase Contrast and Reduce Motion via `DockAccessibilityStyle` (UI/DockDesign.swift).
- Build a disposable bundle with `./BuildMyDock.sh --output .build/visual-qa/<package>/MyDock.app`. Never write `build/MyDock.app`; never launch the user's app.
- Run `./TestMyDock.sh` (or `./TestMyDock.sh --filter <Suite>` for your files) and add tests for any model change.
- Render your surfaces into `.build/visual-qa/<package>/` with the debug executable produced by the test build:
  `MYDOCK_VALIDATION_ROOT=$(mktemp -d) MYDOCK_VISUAL_PREVIEW=1 MYDOCK_RENDER_QA=$PWD/.build/visual-qa/<package> MYDOCK_<MODE>_QA=1 .build/swiftpm-test/arm64-apple-macosx/debug/MyDock`
- Commit on your branch with one clear message per package. Do not push. Do not edit this ledger or the status docs.
- Final report (short): package id, files changed, build result, tests run with counts, render paths, anything blocked and why.

## Design system contract (from the brief, binding for all packages)

- Content over chrome: no borders, strokes, inset fills or secondary labels unless they carry meaning. At most one hairline, only where glass needs an edge.
- Control Center modules: one large glyph or number, one short label, at most one secondary line. Monochrome by default; colour only for state.
- Glass is the material: `glassEffect` / `GlassEffectContainer` on macOS 26; one container so elements blend and morph.
- One type scale, one radius family (concentric: module radius = Dock radius − Dock padding), one motion language (springs; none under Reduce Motion).
- iOS-style editing: gallery of large live previews, size pager, "Add Widget" pill, grouped inset forms.
- Accessibility: Reduce Transparency → opaque; Increase Contrast → visible edges; Reduce Motion → no springs or morphs; VoiceOver labels; keyboard navigation.

## Wave 0

### RD-00 — Stabilise: CI matrix, worktree gitlinks, test fatalError (orchestrator)

- Goal: green CI baseline before design work.
- Owned: `.gitignore`, `.github/workflows/validate.yml`, the root cause of the CI `fatalError`.
- Acceptance:
  - `.claude/worktrees/` is ignored and the 15 gitlinks are removed from the index (directories on disk untouched).
  - The workflow runs only on SDK 26 runners (`macos-26`, `macos-26-intel`).
  - CI's `error: fatalError` is reproduced from a clean clone and fixed in source without skipping a test.
- Status: see journal.

## Wave 1

### RD-01 — Design system and QA export (Claude `design-system`)

- Goal: one shared vocabulary for every later package.
- Owned: `UI/DockDesign.swift` (extend; keep every existing name working), new `UI/DesignSystem/*`, and a new `MYDOCK_REDESIGN_QA` branch in `UI/PremiumVisualQA.swift` (that one addition only).
- Deliver:
  - `DockDesign.Glass`: one function/modifier that applies `.glassEffect(.clear | .regular, in: shape)`, with optional `.tint(_:)` and `.interactive()`, on macOS 26. Otherwise it falls back to `.ultraThinMaterial`, and to an opaque fill under Reduce Transparency. Increase Contrast adds a visible edge.
  - `DockDesign.Module` (Control Center metrics):
    - `radius(dockRadius:dockPadding:)`, concentric;
    - content insets and glyph sizes;
    - value fonts: SF Pro semibold, `.monospacedDigit()`, 22/18/13;
    - label font: 11–12 pt medium, secondary;
    - at most two text lines.
  - `DockDesign.Motion`: add `hover` (≈1.03 scale + slight brightness), `appear` and `morph` springs, plus a helper that returns nil or no animation under Reduce Motion. The existing `transform`, `reorder` and `disclosure` stay.
  - Components in `UI/DesignSystem/`:
    - `GlassModule`: the widget container shape.
    - `GroupedSection` and `GroupedRow`: an iOS inset grouped form. Rows have a leading glyph in a coloured rounded square, a title, and a trailing value, chevron or toggle; there is also a destructive row style.
    - `PillButton`: `.buttonStyle(.glassProminent)` on macOS 26, with a filled capsule fallback.
    - `SizePager`: horizontal paged live previews with page dots, a size caption, arrow keys and click/swipe. It is generic over the page content.
    - `StyleSwatch`: a selectable mini Dock preview card with a title and a selected ring.
  - `MYDOCK_REDESIGN_QA=1` exports every component in light, dark, Reduce Transparency and Increase Contrast into the render directory. The existing DEBUG `dockAccessibilityPreview` override is used, never system preferences.
- Tests: unit tests for `Module.radius` (concentric, clamped ≥ 0) and the Reduce Motion animation helper.
- Renders: `.build/visual-qa/RD-01/`.

### RD-02 — Appearance model (Codex, high)

- Goal: additive persistence for the redesign. This package is the single owner of `Models/DockModels.swift` and `Models/ProfileAppearance.swift` in wave 1.
- Owned:
  - `Models/DockModels.swift`, `Models/ProfileAppearance.swift`;
  - `Models/ProfileSanitizer.swift`, `Models/ProfileSemanticValidator.swift`, `Models/ProfileDraftMerge.swift` (only if needed);
  - `Backup/BackupManager.swift` and `docs/BACKUP_FORMAT.md` (only if needed);
  - new tests under `Tests/MyDockTests/`.
- New types and fields (exact names fixed here so later packages can rely on them):
  - `enum DockEdgeStyle: String, Codable, CaseIterable { case none, hairline, contrastOnly }`. `AppSettings.customDockEdgeStyle` defaults to `.hairline`, today's look.
  - `enum DockWidgetSurface: String, Codable, CaseIterable { case glass, plain, tile }`. `AppSettings.customDockWidgetSurface` defaults to `.tile`, today's look.
  - `AppSettings.customDockFloatingInset: Double` defaults to `0` (today's placement), bounded by `DockAppearanceBounds.floatingInset = 0...24`.
  - `AppSettings.customDockTintMode`: `enum DockTintMode: String, Codable { case custom, auto }`, default `.custom`. Auto means the profile colour at the fixed `DockAppearanceBounds.autoTintStrength = 0.06`. `customDockTintStrength` keeps its range; 0 is allowed.
  - `ProfileAppearance`: the optional fields `edgeStyle`, `widgetSurface`, `floatingInset` and `tintMode`. `nil` maps to the defaults above in `applying(to:)`. `init(settings:)` captures them, and `validate()` bounds `floatingInset`.
  - `WidgetConfiguration`:
    - `widgetAccent: WidgetAccent?`, where `enum WidgetAccent: Codable, Hashable { case auto, mono, profile(DockProfileColor) }` with a stable, explicit Codable representation (string `"auto"`, `"mono"`, `"profile.<raw>"`);
    - `showsLabel: Bool?` (nil = follow `showWidgetLabels`);
    - `glassTint: WidgetGlassTint?`, where `enum WidgetGlassTint: String, Codable { case none, accent }`.
    - All are decoded with `decodeIfPresent`, merged field-level in `ProfileDraftMerge` like the other authored fields, and kept by backup export/import and presets.
- Acceptance:
  - Old `AppSettings` / `ProfileAppearance` / `WidgetConfiguration` JSON (fixtures captured from the current encoder before this change) decodes to today's values, and re-encodes without dropping unknown-free keys.
  - The new fields round-trip.
  - Out-of-range or non-finite inset is clamped in `AppSettings` and rejected by `ProfileAppearance.validate()`.
  - Backup export → import keeps the fields.
  - An unknown future raw value of a new enum decodes to the default instead of failing the whole profile.
- Tests: the above as Swift Testing tests in a new `RedesignAppearanceModelTests.swift`.
- No UI changes.

### RD-03 — Split SettingsView.swift (Codex, medium)

- Goal: one file per settings page under `UI/Settings/`, with **no visual or behavioural change**.
- Owned: `UI/SettingsView.swift`, new `UI/Settings/*Page.swift`, `project.yml` / `MyDock.xcodeproj` regeneration via `./GenerateXcodeProject.sh` if the project lists files.
- Acceptance:
  - `SettingsView.swift` keeps the shell (sidebar, routing, search). Each `MyDockSettingsPage` body moves to `UI/Settings/<Page>SettingsPage.swift`, with shared private helpers moved to `UI/Settings/SettingsShared.swift`.
  - Access levels are widened only as needed (`private` → `fileprivate`/internal).
  - The suite is green, with no change to strings, order, bindings or search terms.
  - Existing SURFACES/INTERACTION render exports of Settings pages are pixel-comparable before and after: report any differing files.

## Wave 2 (starts after wave 1 is merged and verified)

### RD-04 — Clear Dock surface, glass container, floating inset, indicators (Claude `dock-surface`)

- Owned:
  - `CustomDock/DockMaterialSurface.swift`, `CustomDock/DockLayoutPreview.swift`;
  - `DockManagement/CustomDockView.swift`, `DockManagement/CustomDockWindowController.swift`;
  - the reveal handle view and the indicator/badge/spacer/folder views inside those files.
- Acceptance:
  - `liquidGlassClear` + edge `none` + tint 0 + opacity 0 draws only the native clear glass: no backing fill, no tint layer, no stroke.
  - Edge: `hairline` keeps today's stroke; `contrastOnly` shows the stroke only under Increase Contrast. Increase Contrast always shows an edge.
  - Tint `auto` uses the profile colour at `autoTintStrength`.
  - On macOS 26 a `GlassEffectContainer` wraps the Dock contents so the Dock and glass widget modules blend. Popout anchors get `glassEffectID`.
  - The floating inset moves the panel away from the screen edge. The window controller's frame, mask radius, hover/magnification hit areas and reveal edge follow it. Existing geometry tests still pass, and new tests cover the inset in frame computation.
  - Running indicators become small dots; badges, spacers, folder icons and the reveal handle get minimal, box-free treatments.
- Renders: five styles × three positions × light/dark, with Reduce Transparency and Increase Contrast variants. The transparent-corner alpha check in the existing GLASS export still passes.

### RD-05 — Widget chrome (Claude `widget-visuals`)

- Owned: `CustomDock/WidgetPrimitives.swift`, `CustomDock/AppleWidgetCard.swift`, `CustomDock/WidgetAppearance.swift`, `CustomDock/WidgetFreshnessView.swift`.
- Acceptance:
  - `WidgetContainer` is a thin switch over the widget surface, read from the environment:
    - `glass` → `GlassModule`;
    - `plain` → no background;
    - `tile` → today's tile.
  - Hover uses `DockDesign.Motion.hover`. Height stays 54 × Dock size.
  - The shared faces in `WidgetPrimitives.swift` follow the module grammar, with no text below 10 pt.
  - `WidgetPalette` becomes one desaturated accent family. Icon layouts render a centred SF Symbol in a circle with an active state.
  - Per-widget accent, label and tint reach faces through the environment.
  - `WidgetCardPreview` samples and live faces are identical apart from data, and samples are labelled for VoiceOver.

### RD-06 — Add Item gallery (Claude `widget-gallery`)

- Owned: `UI/AddLibrary.swift`, `UI/WidgetLibraryTile.swift`, `UI/WidgetDiscovery.swift`, `UI/LibrarySearchField.swift`, new `UI/WidgetGallery/*`.
- Acceptance: as in brief section 5.5, including:
  - a glass header with a search pill and a Widgets · Apps · More segmented control;
  - Suggested heroes;
  - category sections;
  - an in-place detail view with a SizePager and an Add Widget pill;
  - added check badges;
  - every existing behaviour kept (WidgetDiscovery search, keyboard, allowsAdding, recentlyAdded, CommandLibrary untouched, app scanning and disambiguation);
  - the DEBUG `WidgetGalleryView` reusing the new components.

### RD-07 — Settings pages restyle and Appearance page (Codex, medium)

- Owned: `UI/Settings/*`, `UI/SettingsView.swift`, `UI/SettingsSearchCatalog.swift`, `UI/DockInspector.swift`, `UI/PersonalPresetPicker.swift`.
- Acceptance: as in brief section 5.6.
  - Appearance page order: hero → Style swatches → Glass → Layout → Widgets → Scope.
  - The five quick styles map exactly to brief 5.2:
    - Clear = `liquidGlassClear`, edge none, surface plain, tint 0;
    - Glass = `liquidGlass`, hairline, glass;
    - Frosted = `frosted`, tile;
    - Solid = `solid`, tile;
    - Midnight = `dark`, glass.
  - Search covers every new control.

## Wave 3

### RD-08 — Widget settings sheet and popout shell (Claude `widget-visuals`)

- Owned: `UI/WidgetConfigurationSheet.swift`, `CustomDock/WidgetViews.swift` (sole owner in wave 3).
- Acceptance: as in brief section 5.4.

### RD-09 — Faces and popouts A (Claude `widget-visuals`, second instance)

- Families: Calendar/Reminders, Alarm, Utility, DockUtility, Now Playing, Weather, AirDrop, Trash.

### RD-10 — Faces and popouts B (Codex, high)

- Families: Stock, Stripe, Paddle, Shopify, AI Usage, System Activity, Network Activity.

## Wave 4

### RD-11 — Motion, morphs, onboarding, starter presets (Claude `dock-surface`)

### RD-12 — Independent review and full render matrix (Codex read-only + Claude `visual-reviewer`)

## Journal

### RD-00 — 4 October 2026

- Branch `redesign/integration` created from `534faf7`.
- `.gitignore`:
  - deduplicated `__pycache__/`;
  - added `.claude/worktrees/`.
- `git rm --cached -r .claude/worktrees` removed 15 gitlinks (mode 160000) from the index; the worktree directories on disk are unchanged.
- The committed `Tests/Tooling/__pycache__/*.pyc` (flagged in the previous ledger) was untracked.
- Workflow matrix reduced to `macos-26`, `macos-26-intel`. The source requires the macOS 26 SDK, so the macOS 15 runners could only fail the SDK gate.
- **CI `fatalError` — not reproducible locally.**
  - A clean clone of `534faf7` (no untracked or ignored files), run with `./TestMyDock.sh`, passed **516 tests in 66 suites, exit 0** (scratchpad `cleanclone-test.log`).
  - There are only two `fatalError`/`precondition` sites, and neither is reachable from tests: `DockCanvasDragSurface.init(coder:)` and a DEBUG render-QA precondition.
  - The repository is private and `gh` is not installed, so the CI log could not be read.
  - **Leading hypothesis (unconfirmed):** CI runners use full Xcode, but `TestMyDock.sh` hard-coded the Command Line Tools location of `Testing.framework` (`$DEVELOPER_DIR/Library/Developer/Frameworks`) for `-F` and the rpaths. In Xcode it lives in `Platforms/MacOSX.platform/Developer/Library/Frameworks`. A test bundle that cannot load Swift Testing is reported by SwiftPM as `error: fatalError` after compiling.
  - **Fix:** `TestMyDock.sh` uses whichever layout contains `Testing.framework`, and fails with a clear message if neither does. The workflow's SDK step prints `sw_vers`, `xcode-select -p`, `swift --version` and the SDK version for the next run.
  - **Verification:** local `./TestMyDock.sh` on the main checkout: 516 tests in 66 suites passed (`.build/redesign-rd00-test.log`). **CI not run:** pushing needs the user's permission. Status: implemented; CI verification open.

### Wave 1 launch — 4 October 2026

- **RD-02** (Codex `gpt-6.1-sol`, effort high):
  - Worktree `../MyDock-wt/RD-02`, branch `redesign/RD-02` at `be690ce`.
  - Sandbox `workspace-write` plus `--add-dir` for the main `.git`, because commits from an external worktree write there.
  - Brief: `../MyDock-wt/RD-02.brief.md`.
- **RD-01** (Claude Opus, high): Claude Code loads agent definitions only at session start, so the new `.claude/agents/design-system.md` was not yet available as a subagent type. RD-01 runs as `general-purpose` with `model: opus`, the definition's role text and the full package brief, in an isolated worktree that is told to reset to `be690ce`. Later sessions can use the named agents directly.
- **RD-03** (Codex, effort medium): queued behind the two-concurrent-builds limit. Brief: `../MyDock-wt/RD-03.brief.md`.

### RD-02 — merged `f5500c2` (branch commit `18c971f`)

- **Implementation:** implemented as specified.
  - New types: `DockEdgeStyle`, `DockWidgetSurface`, `DockTintMode`, `WidgetAccent` (string-encoded `auto` / `mono` / `profile.<raw>`) and `WidgetGlassTint`.
  - New `AppSettings` fields: `customDockEdgeStyle` (`.hairline`), `customDockWidgetSurface` (`.tile`), `customDockFloatingInset` (0, bounds 0…24) and `customDockTintMode` (`.custom`).
  - `ProfileAppearance` gets the optional fields `edgeStyle`, `widgetSurface`, `floatingInset` and `tintMode`. nil maps to today's look, and `validate()` bounds the inset.
  - `WidgetConfiguration` gets the optional fields `widgetAccent`, `showsLabel` and `glassTint`.
  - New enums decode an unknown raw value to the default (`try?`). Decoding of existing enums is unchanged.
- **Orchestrator review:**
  - `WidgetConfiguration` encoding is synthesized from its CodingKeys, so the new keys are written.
  - Draft merge is JSON field-level (`JSONDraftMerge`), so the new widget fields merge independently with no code change. A test covers independent merges and real conflicts.
  - The sanitizer and backup do not enumerate fields.
- **Worker verification:**
  - The new `RedesignAppearanceModelTests` pass: 9 tests covering old-JSON fixtures from the pre-change encoder, round-trips, clamping and rejection, unknown-enum fallback, backup, personal presets and merge.
  - The disposable build passed.
  - The full suite stalled in the Codex sandbox: LaunchServices waits in `AIActivityDedupeTests` and a subprocess wait in `BoundedSubprocessCaptureTests`. Environment only; no test was changed.
- **Unsandboxed full suite on integration:** queued (build-slot limit). See the next journal entry.

### RD-01 — merged `a3f96c0` (branch commit `66ee21b`)

- **Implementation:** implemented. Added:
  - `DockDesign.Motion` (`hover`, `appear`, `morph`, `animation(_:reduceMotion:)`, `perform`), `DockDesign.Module`, `DockDesign.Glass` and `DockDesign.Grouped`;
  - `DockAccessibilityStyle.reduceMotion` and a DEBUG preview override;
  - `dockGlass(_:in:tint:interactive:)`, `DockGlassGroup` (a `GlassEffectContainer`) and `dockHover`;
  - the components `GlassModule`, `ModuleValueLabel`, `GroupedSection`/`GroupedRow` (value, toggle, button, destructive, custom), `PillButton`, `SizePager` and `StyleSwatch`/`DockSwatchLook`;
  - the DEBUG `MYDOCK_REDESIGN_QA` export.
- **Orchestrator review:**
  - All changes are additive, and every glass call is behind `#available(macOS 26.0, *)`.
  - Reduce Transparency is opaque. Increase Contrast adds an edge on every path. Reduce Motion returns a nil animation or an instant transaction.
  - Exports draw the fallback, because native glass blanks `cacheDisplay` bitmaps; the worker found this and documented it.
  - **Noted risk:** on macOS 13–14, `GroupedSection` falls back to `_VariadicView` (underscored SwiftUI API). macOS 15+ uses `Group(subviews:)`. That fallback is not rendered here.
- **Renders:** 42 PNGs (7 specimens × light/dark × standard/RT/IC) in the worker's `.build/visual-qa/RD-01/` and on integration in `.build/visual-qa/redesign-20261004/wave1/`. The orchestrator viewed the sheet specimen (light), the swatches (dark) and the grouped form (dark, Increase Contrast). The "on" switches render grey in offscreen captures, which is an `NSSwitch` capture artifact.

### RD-03 — merged `a58261c` (branch commit `e0c685b`)

- **Implementation:** `SettingsView.swift` keeps the shell, and seven `UI/Settings/<Page>SettingsPage.swift` extensions plus `SettingsShared.swift` hold the pages.
- **Orchestrator review:** a normalized line comparison (access modifiers stripped) shows that apart from `private` removal the only differences are the seven new page accessors and their call sites. No other line was removed or added.
- **Worker verification:**
  - 516 tests pass before and after.
  - Nine Settings PNG pairs are byte-identical.
  - Six differ only in live clock content and diagnostics timestamps (0.04–1.3 % of pixels). See `../MyDock-wt/RD-03/.build/visual-qa/RD-03/settings-comparison.txt`.
- The `project.pbxproj` merge conflict with RD-01 was resolved by regenerating with `./GenerateXcodeProject.sh`.

### Wave 1 integrated verification — 4 October 2026

- `./TestMyDock.sh` on `redesign/integration` (`a58261c`): **531 tests in 68 suites passed, 0 failed** (516 + 9 RD-02 + 6 RD-01). Log: `.build/redesign-w1b-test.log`.
- `MYDOCK_REDESIGN_QA=1` export on integration: 42 PNGs, exit 0.
- Canonical app:
  - The previous instance (PID 87859) was quit with a normal quit Apple Event and its absence verified.
  - `./BuildMyDock.sh` exited 0. Executable SHA-256 `2c1fc310ffdd412cbc8a4b7b4fcf3899c8a9294cac85baa8af2ca19c59026ec3`.
  - `build/MyDock.app` relaunched (PID 2773).
- There is no visual change to the shipping UI in wave 1, by design.

### Integration fix before wave 2 — shared presentation environment

`UI/DesignSystem/DockPresentationEnvironment.swift` (orchestrator) defines the contract between the Dock and widget packages:
- `dockWidgetSurface` (default `.tile`);
- `dockModuleRadius` (default `Module.defaultRadius` 16);
- `widgetAccent` (`.auto`);
- `widgetShowsLabel` (true);
- `widgetGlassTint` (`.none`).

### Wave 2 ownership refinements (binding)

- **RD-04** also owns `DockManagement/DockPresentationPolicies.swift`. `DockPresentationSettings` must include the new appearance fields so the panel updates when they change; the floating inset changes geometry. RD-04 injects `dockModuleRadius` (concentric with its own Dock padding) in `CustomDockView` and `DockLayoutPreview`. It wraps Dock contents in `DockGlassGroup` when the material is glass.
- **RD-05** may edit only the body of `WidgetCompactView` in `CustomDock/WidgetViews.swift`, to inject the per-widget values:
  - `dockWidgetSurface` from the effective settings;
  - `widgetAccent` from `configuration.widgetAccent ?? .auto`;
  - `widgetShowsLabel` from `configuration.showsLabel ?? settings.showWidgetLabels`;
  - `widgetGlassTint` from `configuration.glassTint ?? .none`.

  The rest of that file stays untouched until RD-08.

### Wave 2 launch — 4 October 2026 (base `e8ce88b`)

- **RD-04:** `dock-surface` agent (Opus), isolated worktree. Render mode `MYDOCK_DOCKSTYLE_QA`, in a new file `UI/RedesignQA/DockStyleQA.swift` with one dispatch line.
- **RD-05:** `widget-visuals` agent (Opus), isolated worktree. Render mode `MYDOCK_WIDGETSURFACE_QA`, in `UI/RedesignQA/WidgetSurfaceQA.swift` with one dispatch line.
- **RD-06 and RD-07:** queued behind the two-build limit.

**Approved default change (recorded per brief §3):** the module-grammar faces, the type scale and the harmonised `WidgetPalette` apply to every widget surface, including the `.tile` migration default. This is the redesign the user authorized: brief §5.3 restyles every face. Each existing profile keeps:
- its Dock material;
- its edge (hairline);
- its tint;
- its tile container;
- each widget's saved icon appearance.

Mono becomes the default icon appearance for **newly created** widgets only. The orchestrator sets it at the creation site after RD-05 reports it.

### RD-04 — merged (branch commit `6f240f2`), with integration fix `116eac9`

**Implementation:** implemented.

- **Surface (`DockSurfaceLayers` resolver):**
  - The backing fill, the tint and the edge each exist only when they contribute.
  - Clear + edge none + tint 0 + opacity 0 draws only the native clear glass.
  - Edge: `.hairline` is today's 1 pt outline. `.contrastOnly` and `.none` draw nothing unless Increase Contrast is on, which always draws a 2 pt edge.
  - Tint `.auto` uses 0.06 of the profile colour.
- **Geometry (`DockPanelGeometry`):** pure functions for the panel frame, the reveal strip at the screen edge and the keep-visible area across the floating gap. `DockPresentationSettings` carries the four new fields.
- **Glass container and IDs:** `DockGlassGroup(spacing: 0)` wraps the item stack for glass materials. `dockModuleRadius` is injected, (radius − padding) ÷ scale. `glassEffectID` is set on widget and folder popout anchors.
- **Indicators and chrome:**
  - New running dots: none existed before.
  - Red badge with no stroke (white edge under Increase Contrast).
  - Invisible spacers.
  - Boxless folder glyph (`FolderIconView.swift`, under the folder-icon allowance).
  - Slim reveal handle.

**Orchestrator review:**

- **Old profiles:** an old profile (hairline, custom 0.08) resolves to today's layers (test). The worker reports that the frosted, solid and dark GLASS corner captures are byte-identical to before.
- **Defect fixed by the orchestrator:** `runningPinnedItemIDs` called `AppLauncher.resolvedURL` from the view body. That is a disk stat, and possibly an `NSWorkspace` lookup plus an Info.plist read, for every idle pinned app on every hover or magnification re-render. `DockRunningIndicatorPolicy` now consults it only when an app with the item's bundle identifier is running. A new test proves idle apps never resolve.
- **Product note:** running dots are a new always-on indicator, which matches the brief's "small dot indicators".
- **Follow-up for RD-11:** the Dock surface is drawn behind and outside the `GlassEffectContainer`, so it is unproven whether widget glass blends with the Dock glass natively. Move the surface into the container if native inspection shows separate layers.

**Renders:** 89 PNGs in the worker's `.build/visual-qa/RD-04/`, all with transparent corners on the transparent-host captures. The orchestrator viewed:
- `dockstyle-clear-bottom-light`: no edge or tint, dots, a badge, a gap and a boxless folder. Widgets still use tiles until RD-05.
- `dockstyle-floating-inset`: insets 0 and 24 at each position, with the reveal strip at the edge.

**Verification on integration:**

- `./TestMyDock.sh`: **546 tests in 69 suites passed** (`.build/redesign-rd04-test.log`).
- Canonical rebuild:
  - The previous instance was quit normally. `./BuildMyDock.sh` exited 0, and the SHA-256 starts `83ff34e4a9f89ad7`.
  - `build/MyDock.app` relaunched (PID 9228).

**Native Liquid Glass compositing is unverified.** Exports draw the material fallback.

### RD-06 launched (`widget-gallery` agent, Opus), base `116eac9`

Render mode `MYDOCK_GALLERY_QA`.

### RD-05 — merged `0119b19` (branch commit `1808359`), plus integration change

**Implementation:** implemented.

- `WidgetContainer` is a switch over the widget surface:
  - tile: unchanged code;
  - glass: `GlassModule`, at the concentric radius, with an optional accent tint;
  - plain: no background, with an edge under Increase Contrast.
- The palette is harmonised. `WidgetPalette.resolved(kind:accent:)` resolves accents, and `WidgetIcon` reads `widgetAccent`.
- The icon layout is a Control Center toggle circle.
- The shared faces follow the module grammar: one value, an 11–12 pt label, and no text under 10 pt.
- Samples carry the label "<Family>, sample preview". Freshness is shown as a dot.
- `WidgetPresentationValues` injects the per-widget values in `WidgetCompactView`.
- `render(...)` in `PremiumVisualQA` is no longer private, so QA extensions can call it.

**Integration changes:**
- The `PremiumVisualQA` dispatch conflict with RD-04 was resolved by keeping both lines. The project was regenerated.
- `DockItem.widget(_:)` now starts new widgets as Mono. `WidgetConfiguration()` and decoding are unchanged, so saved widgets keep their icons. A test covers this.
- The automatic Trash is built at render time and is not saved, so it is also Mono now. This is recorded as part of the approved default change.

**Open, routed to RD-09/RD-10:** family faces in their own files still use 7–9 pt text and their own layouts:
- AI Usage, Alarm, Calendar, AirDrop, Trash;
- `SavedCollectionDockFace`.

**Verification:**
- The worker reports 540 tests and 66 renders; the orchestrator viewed system/plain/dark, time/glass/light and ai/tile/dark.
- On integration:
  - `./TestMyDock.sh` passed **556 tests in 71 suites** (`.build/redesign-rd05-test.log`).
  - Canonical app: quit normally, `./BuildMyDock.sh` exited 0 (SHA-256 starting `119b84fd2331c58f`), relaunched as PID 11187.
  - Integration renders in `.build/visual-qa/redesign-20261004/wave2a/`: DOCKSTYLE 88 PNGs and WIDGETSURFACE 66, both exit 0. Not yet viewed.

### Session pause — 4 October 2026

The user's usage limit was reached.
- **RD-06** (Add Item gallery, `widget-gallery` agent) was stopped mid-work. Any partial work is in its `.claude/worktrees/agent-a237fc9bf51278e31` worktree, uncommitted. Relaunch it from base `116eac9` or later.
- **Not started:** RD-07 (brief template `../MyDock-wt/RD-07.brief.tmpl`; replace `BASE_COMMIT`), RD-08–RD-12.
- **CI:** still unverified; pushing needs the user's permission.

### Resumption — 4 October 2026 (user: "continue")

**Integration renders viewed** (`wave2a/DOCKSTYLE`, first images combining RD-04 and RD-05):

| Render | What it shows |
|---|---|
| `dockstyle-clear-bottom-dark` | Clear Dock. Widgets sit directly on the glass (plain), with no tiles or edge. |
| `dockstyle-glass-bottom-light` | Hairline Dock with soft glass modules. |
| `dockstyle-clear-bottom-light-increase-contrast` | Dock and module edges, plus stronger dots. |

Running dots, the badge and the boxless folder are consistent across all three.

**Workers resumed or launched:**
- **RD-06** (`widget-gallery` agent): resumed from its uncommitted partial work, which is about 800 lines in `UI/WidgetGallery/`, not yet wired into `AddLibrary` and not compiling at the pause. It was told to rebase onto `cbcb481` and finish.
- **RD-07** (Codex `gpt-6.1-sol`, medium): launched in `../MyDock-wt/RD-07`, branch `redesign/RD-07` at `cbcb481`.

### RD-06 — merged (branch commit `1fac9c3`, rebased by the worker onto `cbcb481`)

**Implementation:** implemented.

- **Header:**
  - a centred search pill and a Widgets · Apps · More segmented control (⌘1–⌘3);
  - the capability filter as a header menu;
  - native profiles show only Apps and More.
- **Widgets tab:**
  - a deterministic Suggested row of 3–4 picks, which skips families already on the Dock and is hidden for native profiles and when adding is not allowed;
  - category sections in 2–4 columns.
- **Detail view:** opens in place, with a `SizePager` over the family's layouts, a description, the access note and an Add Widget `PillButton`.
- **Adding:** double-click or Return adds the default layout. Added items show a spring check badge, instant under Reduce Motion.
- **Kept:** search, keyboard, app scan and disambiguation, the error message, every More entry, the source-compatible initializer and an untouched `CommandLibrary`.
- **DEBUG catalog:** the DEBUG `WidgetGalleryView` reuses the new parts.

**Behaviour changes, accepted by the orchestrator:**
- `allowsAdding` is now enforced in browse mode. `DockManagerView` passes `selectedProfile != nil`, so with no Dock selected the window says "Choose a Dock to add items". That is a fix.
- The minimum width is now 680 (was 740).

**Orchestrator review:** viewed `gallery-widgets-920-light`, `gallery-detail-weather-920-dark` and `gallery-apps-700-dark`. Minor follow-up for RD-09: the Text Snippets sample reads a bare "2" with no unit.

**Verification:**
- The worker ran 567 tests and exported 85 renders.
- Integration:
  - `./TestMyDock.sh` **567 tests in 72 suites passed** (`.build/redesign-rd06-test.log`).
  - The canonical app was quit normally and rebuilt (`./BuildMyDock.sh` exit 0, SHA-256 starts `5ddae502d64f4eda`), then relaunched as PID 22866.

### Wave 3 contract (binding for RD-08, RD-09, RD-10)

- **Provider API:** `DockWidgetProvider.popoutView` keeps its signature.

**Families (RD-09, RD-10) own:**
- their faces;
- their popout *content*:
  - settings-like controls become `GroupedSection`/`GroupedRow`;
  - interactive tools (calculator, checklist, file shelf, player) keep their interaction and restyle inside the module/grouped vocabulary.

  Content draws no outer background, card, header or outer padding. The shell provides those.

**RD-08 owns:**
- the `WidgetPopout` shell (header, surface, padding, width, scrolling, Data section);
- `WidgetConfigurationSheet`;
- the providers that live in `WidgetViews.swift`: Clock, Focus Timer, World Clock, Stopwatch, Countdown, Time Progress, Hydration, Battery, App Folder, Shortcuts and Sticky Note.

**Ownership split:**
- **RD-09:** `CalendarRemindersWidgetViews`, `AlarmWidgetViews`, `UtilityWidgetViews`, `DockUtilityWidgetViews`, `NowPlayingWidgetViews`, `WeatherWidgetViews`, `AirDropWidgetViews` and `TrashWidgetViews`. RD-09 also owns their samples in `AppleWidgetCard.swift`, so that sample and live faces match.
- **RD-10:** `StockWidgetViews`, `StripeWidgetViews`, `PaddleWidgetViews`, `ShopifyWidgetViews`, `AIUsageWidgetViews`, `SystemActivityWidgetViews` and `NetworkActivityWidgetViews`.
- **AppleWidgetCard.swift edits:** RD-10 edits only its families' sample cases. Conflicts there are resolved by the orchestrator.

### RD-07 — merged (branch commit `4d84790`), plus integration commit `e7fd022`

**Implementation:** implemented.

- **Settings shell:** the sidebar shows white glyphs on coloured rounded squares. Every page uses `GroupedSection`/`GroupedRow` with trailing toggles and short footers.
- **Appearance page order:** hero (`DockLayoutPreview` over a wallpaper), then Style (five `StyleSwatch`es), Glass, Layout, Widgets and Scope.
- **Quick styles:** `DockQuickStyle` maps exactly to the ledger. `apply` goes through the existing scope-aware `updateAppearance` path. `matches` drives the selected ring; no match means "Custom".
- **Other surfaces:** `DockInspector` and `PersonalPresetPicker` use grouped rows. The settings-specific helpers in `DockDesign.swift` are restyled.
- **Search:** `SettingsSearchCatalog` covers the new controls. The orchestrator added the matching `MyDockSettingsPage.appearance.searchTerms`, because RD-07 did not own the model file.

**Orchestrator review:**
- Viewed `settings-appearance-light-wide`, `settings-appearance-section-glass-dark` and `settings-behavior-dark-wide`. They read as macOS 26 System Settings.
- **Defects for the fix wave:**
  1. The Glass section has both a "Finish" picker (which includes both Liquid Glass finishes) and a separate "Glass finish" Clear/Frosted segmented control. That is redundant: keep one control, or show the segmented control only for glass materials and drop the glass entries from Finish.
  2. Some footers are still long, e.g. Behavior's window-preview footnote.
  3. The window shows "Settings" twice: once in the toolbar title and once in the sidebar header.

**Verification:**
- The worker ran 560 tests and exported 74 renders.
- Integration: `./TestMyDock.sh` passed **571 tests in 73 suites** (`.build/redesign-rd07-test.log`).
- The canonical app was rebuilt (SHA-256 starts `185acbbe84effab0`) and relaunched as PID 26220.

### Wave 3 launches

- **RD-08** (`widget-visuals` agent): base `92cc970`.
- **RD-10** (Codex, effort high): `../MyDock-wt/RD-10`, base `e7fd022`.
- **RD-09** (`widget-visuals`, second instance): queued for the next build slot.

### RD-08 — merged `1f420c4` (branch commit `2355025`)

**Implementation:** implemented.

**Sheet (504 pt wide).** Top to bottom:
- a header with the title and a "Done" glass pill (Escape closes);
- a live `WidgetCompactView`, scaled up on this profile's `DockMaterialSurface` strip over a wallpaper;
- a `SizePager` over the family's layouts;
- Content: the provider's popout content;
- Appearance:
  - Accent: Auto, Mono, or a profile colour;
  - Icon: Color, Soft, Mono or Outline;
  - Label: Auto (nil), On or Off;
  - Glass tint: shown only on the glass surface;
- Data: omitted when empty;
- Remove Widget: confirmed, then removed through the profile edit session with undo.

Unchanged: preference-key height measuring, the 640 pt cap and `RefreshDemandHolder`.

**Popout shell.**
- A Module-label header with a freshness line, on `dockGlass(.regular)` with radius 28 (concentric with the grouped sections).
- New `showsData` parameter, defaulting to true.
- Every parameter and call site is kept, and `CustomDockView` is untouched.

**Families restyled** (the ones in `WidgetViews.swift`): Clock, timers, World Clock, Time Progress, Hydration, Battery, App Folder (now a launch grid with edit rows), Shortcuts and Sticky Note.
- A DEBUG `BatteryQAFixture` was added.
- Shared views: `WidgetPopoutHero`, `WidgetRoundButtonStyle`, `WidgetStepperRow` and `WidgetCircleButtonStyle`.

**Orchestrator review.**
- Viewed `widgetsheet-surface-glass-dark` (reads as iOS 26 Edit Widget) and `widgetpopout-countdown-light` (iOS timer pattern).
- Minor issue for the fix wave: the Clock sheet's Content repeats the big time and date directly under the preview. For families whose Content is only a hero, the sheet should omit the hero.

**Verification.**
- Worker: 574 tests passed and 56 renders were produced.
- Integration:
  - `./TestMyDock.sh` passed **578 tests in 74 suites** (`.build/redesign-rd08-test.log`).
  - Canonical app quit normally and rebuilt; SHA-256 starts `f8c0339f9df15874`; relaunched as PID 33749.

### RD-09 launched

`widget-visuals` agent, base `1f420c4`. Its brief includes RD-08's content-shaping guidance. RD-10 (Codex) started from `e7fd022`, which does not include RD-08's shared popout views; its content may be reconciled at merge.

### RD-10 — merged `7e1b74a` (branch commit `59bcf9d`)

- **Implementation:** implemented. The faces for Stock and Watchlist, Stripe, Paddle, Shopify, AI Limits and AI Activity, System Activity and Network Activity follow the module grammar. Their samples match, and their popout content uses grouped rows.
- **Orchestrator review:**
  - Viewed `contact-faces-glass-dark`. The faces are consistent: one value plus a label, honest setup/unavailable/stale states, and red only for state.
  - **Defect for the fix wave:** the AI Limits popout (`facesb-popout-ai-limits-ready-light`) puts the settings first and the usage reading last. It also still draws its own Refresh row and freshness lines. RD-10 started from `e7fd022`, before RD-08's shell. The fix: lead with the reading via `WidgetPopoutHero`, move the provider list and display options into a settings group, and drop the duplicate freshness. The other RD-10 popouts need the same check against the RD-08 shell.
- **Verification:**
  - Worker: `RedesignFacesBTests` passed 8 of 8, with 110 renders. The full suite stalled in the Codex sandbox (LaunchServices).
  - Integration, unsandboxed: `./TestMyDock.sh` passed **586 tests in 75 suites** (`.build/redesign-rd10-test.log`).
- Canonical app after RD-10:
  - The previous instance was quit normally.
  - The app was rebuilt; its SHA-256 starts `6655e2322ef2e911`.
  - It was relaunched as PID 35331.

### RD-11 launched (`dock-surface` agent, base `19d9d39`)

The popout morph is scoped down:
- Popouts are SwiftUI `.popover`, which is an `NSPopover` in a separate window. A true `glassEffectID` morph from the Dock module across windows is not possible.
- Replacing the popover with a custom panel is out of scope because of the focus, keyboard and hit-testing risk.
- RD-11 instead delivers an appear spring and an active anchor state. The `glassEffectID` wiring is kept for a future in-panel presentation.

Other changes in RD-11:
- `DockStarterPreset` moves out of `DockManagerView.swift` into `UI/DockStarterPresets.swift` (orchestrator-approved, mechanical).
- Starter presets gain quick styles.

### RD-11 — merged `32b5046` (branch commit `b9a93b7`)

Both RD-09 and RD-11 were interrupted by an API session limit. They were resumed from their transcripts, with their uncommitted work intact.

**Implementation:**
- **Popout appear spring:** popouts open on a 0.96 → 1 spring from the Dock-facing edge. The anchor shows an active state (0.97 scale and slightly brighter, render-only). Both are instant under Reduce Motion.
- **Reorder settle:** dropped or pinned items settle on `Motion.morph` in the live Dock. The existing springs now go through `DockMotionPolicy`.
- **Interactive glass:** `.interactive()` glass on glass modules. A test shows clicks still register. Drag and context menu are natively unverified.
- **First-run onboarding:**
  - Applies Clear through `DockQuickStyle.clear`, persisted before completion is written, with rollback on failure.
  - Then shows a "Your Dock, clearer" reveal, which morphs the hero preview into Clear.
  - Replay Setup keeps the existing look.
- **Starter presets:** `DockStarterPreset` moved to `UI/DockStarterPresets.swift`. Each preset applies a quick style as a `ProfileAppearance` snapshot:

| Quick style | Presets |
|---|---|
| Clear | Everyday, Travel |
| Glass | Creative, Build & code, AI |
| Solid | Deep focus |
| Frosted | Commerce, Home office, System monitor |

**Not done, accepted:**
- **One glass container for the Dock surface and modules.** `GlassEffectContainer` fuses shapes within its spacing. Modules sit inside the surface, so they would melt into the Dock glass. Lifting the container above the scroll view would escape the `DockScrollClip` mask. The decision is captured as a tested pure helper, `DockGlassComposition`.
- **Native popout morph.** Recorded at launch: NSPopover lives in a separate window.

**Orchestrator review:**
- Accepted the out-of-list one-line call-site change in `DockManagerView`'s preset sheet: `profile.appearance = preset.appearance(basedOn:)`. The orchestrator owns that file.
- Viewed `motion-onboarding-reveal-dark` and `motion-starter-presets-light`.
- **Defect for the fix wave:** a trailing separator is drawn at the end of every Dock even when nothing follows it. This is visible in every preset preview.
- **Follow-up:** editor canvas keyboard moves (`UI/DockCanvas.swift`) use `Motion.transform`, not `reorder`.

**Verification:**
- Worker: 597 tests passed; 25 renders were produced.
- Integration: `./TestMyDock.sh` **597 tests in 76 suites** (`.build/redesign-rd11-test.log`).
- Canonical app: rebuilt (SHA-256 starts `da1188e5286b1210`) and relaunched as PID 57634.

### RD-09 — merged `087a1a2` (branch commit `21c5847`)

**Implementation:** implemented.

- **Faces:** pure module-grammar faces: `CalendarDockFace`, `RemindersModuleFace`, `AlarmDockFace`, `TrashDockFace`, `AirDropDockFace`, plus a rebuilt `SavedCollectionDockFace`.
- **Popouts:** grouped, using RD-08's shared views. Every interaction is kept.
- **New rows:** "Open Privacy & Security" rows for the Calendar, Reminders and Now Playing errors.
- **Samples:** Text Snippets now reads "2 snippets".
- **DEBUG fixtures:** for Reminders, Now Playing and Trash.

**Merge conflicts in `AppleWidgetCard.swift`**, resolved by package ownership:
- RD-09 owns the Reminders, Calendar, Trash and AirDrop sample cases.
- RD-10 owns Stripe, Paddle, Shopify and AI Limits.
- Both dispatch lines were kept.

**Integration:** `./TestMyDock.sh` **609 tests in 77 suites passed** (`.build/redesign-rd09-test.log`). The canonical app was rebuilt (SHA-256 `9a75cac47027da69…`) and relaunched as PID 58771.

**Orchestrator review:** viewed `facesa-states-dark` and `facesa-popout-calendar-ongoing-light`. Both are good.

**Known leftovers for the fix wave:**
- `RemindersDockFace` in `WidgetPrimitives.swift` is now unused.
- `DiskDockFace` truncates its value at compact width (e.g. "120,62…").
- `MediaDockFace` truncates titles at 112 pt.
- The SURFACES "surface-alarm-edit" fixed click point is stale.

### Integrated render matrix — 5 October 2026 (`087a1a2`, one debug build)

Output: `.build/visual-qa/redesign-20261005/integrated/<MODE>/`. Every mode exits 0 except WIDGET:

| Mode | PNGs |
|---|---|
| REDESIGN | 42 |
| DOCKSTYLE | 88 |
| WIDGETSURFACE | 66 |
| GALLERY | 85 |
| SETTINGS | 74 |
| WIDGETSHEET | 56 |
| FACESA | 86 |
| FACESB | 110 |
| MOTION | 25 |
| GLASS | 17 |
| SURFACES | 44 |
| WIDGET | 25 before crash |

**Regression found (blocker):** the pre-existing `MYDOCK_WIDGET_QA` export (130 PNGs at baseline) now crashes with SIGTRAP while rendering the **Trash** popout, which comes after AirDrop in registry order.
- Crash report `~/Library/Logs/DiagnosticReports/MyDock-2026-10-05-025958.ips`: `NSGenericException` (reason redacted in the unified log), thrown from `-[NSWindow updateConstraintsIfNeeded]` → `_NSViewUpdateConstraints`. This is the AppKit "too many Update Constraints passes" layout-loop pattern.
- In isolation `TrashStatus` holds the static `isolatedMessage` and never publishes, so the leading hypothesis is a SwiftUI/AppKit layout feedback loop at this width with this text. RD-09's own export used a fixture message and did not crash.
- The live popover could hit the same loop with a real error string. Assigned to **FX-01**.

### Review and fix wave launch — 5 October 2026 (base `1071b86`)

- **FX-01** (`widget-visuals` agent): root-cause and fix the Trash popout layout loop, with a regression test, and rerun the WIDGET, FACESA, FACESB and WIDGETSHEET exports.
- **RD-12 code review** (Codex `gpt-6.1-sol`, effort high): read-only in a detached worktree `../MyDock-wt/RD-12`, with no `.git` write access. It reviews the full diff `534faf7..1071b86` for compatibility, correctness, accessibility, platform safety, hot-path performance, scope and tests.
- **RD-12 visual review** (`visual-reviewer` agent): read-only, over the integrated render matrix.

The fix wave, FX-02 onwards, will bundle the reviewers' findings with the defects already recorded:
- the duplicate Finish / Glass finish controls;
- long footers;
- the duplicate "Settings" title;
- the Clock sheet hero repeated under its preview;
- AI Limits popout order and duplicate freshness;
- the RD-10 popouts against the RD-08 shell;
- the trailing Dock separator;
- unused `RemindersDockFace`;
- Disk and Media face truncation;
- the stale SURFACES click point;
- `DockCanvas` keyboard moves using `transform`.

### RD-12 code review — Codex `gpt-6.1-sol` (high), read-only, at `1071b86`

Report: `../MyDock-wt/RD-12.report.md`. The worktree stayed unchanged.

**Findings**, all routed to the fix wave:

1. **Blocker:** the Trash popout render crash, reproduced independently with a second crash report. Already assigned to FX-01.
2. **Major:** a failed Remove Widget save leaves the item removed from a dirty draft. The sheet dismisses anyway, and undo is never registered, so a retry returns false (`WidgetConfigurationSheet.swift:192`).
3. **Major:** gallery widget tiles are gesture-only. A keyboard-only user can add the default layout but cannot open the detail size pager (`WidgetGalleryTile.swift:83`, `AddLibrary.swift:503`).
4. **Major:** Paddle and Shopify popout charts became a `MicroSparkline` with a static label. VoiceOver loses the dated values that Swift Charts exposed (`PaddleWidgetViews.swift:204`, `ShopifyWidgetViews.swift:222`).
5. **Minor:** the Stripe, Paddle and Shopify Color pickers still persist their colour fields, but rendering no longer reads them. Fix: wire them to the accent system, or remove the pickers (keeping the keys).
6. **Minor:** "Restore appearance defaults" omits edge, widget surface, inset and tint mode (`AppearanceSettingsPage.swift:213`). Verified by the orchestrator.
7. **Minor:** running-indicator matching still calls `InstalledApplicationIdentity.normalizedURL`, i.e. `resolvingSymlinksInPath`, which touches the file system per path component. It does this for every running and pinned app on every body evaluation, including hover. Verified. The fix is to cache matches when application or profile state changes. The orchestrator's earlier fix only removed the resolver fallback.
8. **Minor:** gallery previews render with `.soft` icons, while new widgets are created `.mono`. Previews should use the creation configuration.

**Verified OK by the reviewer:**
- persistence compatibility;
- appearance scope and undo;
- quick styles;
- floating and reveal geometry;
- `allowsAdding`;
- untouched `CommandLibrary`;
- refresh demand;
- availability guards;
- DEBUG-only seams;
- RT, RM and IC handling in code.

The reviewer also ran **609 tests** unsandboxed (plus 93 focused redesign tests) and a universal Release build, with no warnings in redesign files.

### RD-12 visual review — `visual-reviewer` agent, read-only, at `1071b86`

The reviewer viewed about 75 integrated renders across every mode.

**Verdict:** "Not yet screenshot-worthy, but close." The Dock itself photographs best. Three things break the illusion:
- the popout is a card inside an opaque slab;
- previews truncate their own sample text;
- packages do not share one chrome vocabulary.

The orchestrator verified D1 in source: `CustomDockView.swift:827-829` adds `.padding(20).background(WidgetDesign.surface)` (opaque `windowBackgroundColor`) around the `WidgetPopout` glass shell. It also viewed `MOTION/motion-popout-end-light.png`.

**Defects:**

| ID | Defect |
|---|---|
| D1 | The popout is a card inside an opaque slab. |
| D2 | Gallery samples are Soft while new widgets are Mono (same as Codex #8). |
| D3 | The Sticky Note face truncates "Make somethin…" on the hero, presets and sheet. |
| D4 | Badge clipped in the vertical Dock. |
| D5 | AI Activity Standard/Activity faces overflow 54 pt with three lines. |
| D6 | Paddle/Shopify Standard trailing period truncates ("30 da…"). |
| D7 | Timer Start buttons fail contrast in light (about 2:1). |
| D8 | Weather forecast shows day glyphs at night; hours read as a bare "03". |
| D9 | RD-10 popouts use `.caption2`/`.tertiary`; Stock setup shows a disabled Refresh row; Stripe states contradict ("Not connected" while showing a value), with duplicate Refresh, two freshness lines and long legal footers; System Activity's hero is not `WidgetPopoutHero`, and FacesBQA does not render inside the real shell. |
| D10 | Settings General/Integrations are not on the grouped grammar (`AppLifecycleSettingsView`, `RecoveryCenterView`, `PrivacyHelpSection`, Integrations account rows). |
| D11 | In narrow Settings, the window header and sidebar header/footer push the selected page below the fold. |
| D12 | The sheet repeats the hero for every hero family; the Trash caption is duplicated by its footer; the Alarm hero duplicates its first row in another time format. |
| D13 | Six different close/Done controls and five header styles. |
| D14 | The popout Customize panel duplicates the sheet's Appearance with a different size control; three colour palettes (App Folder uses saturated system colours). |
| D15 | Label-over-value order is inconsistent (System Activity Compact and the side Dock); with labels off, alignment varies. |
| D16 | Permissions rows show lowercase sentence fragments. |
| D17 | Smaller issues (detailed below). |
| D18 | To verify natively: soft upscaled gallery and sheet previews; the Settings hero follows the system scheme while the swatches follow the window scheme. |

D17 covers:
- the gallery Apps added check and the add plus look alike;
- the spacer descriptions are duplicated;
- the Dock inspector sliders are misaligned;
- Now Playing uses plain `gobackward`/`goforward`;
- the Weather "Next Hours" columns crowd the left;
- the presets "Remove" button is not destructive;
- the Checklist "Add" button is invisible under Increase Contrast;
- dead 8–9 pt provider compact views remain in `WidgetViews.swift`;
- starter preset previews overflow, and their thumbnails shrink text to about 5 pt.

**Taste suggestions:**

| ID | Suggestion |
|---|---|
| T1 | Popouts carry settings; Control Center would show the reading and primary actions only. |
| T2 | Auto accent tints every glyph; make Auto ≈ Mono except for active state. |
| T3 | Gallery tiles nest a stroked tile around the module. |
| T4 | Long footers everywhere. |
| T5 | The sheet preview strip adds a third nested rectangle. |
| T6 | Calendar rows: three lines with a full date. |
| T7 | Detail page copy is three secondary lines. |

### Fix wave plan (binding ownership; base after FX-01 where noted)

**Shared rule (D13):**
- Every sheet, inspector and window closes with `Button("Done").buttonStyle(GalleryGlassButtonStyle()).keyboardShortcut(.cancelAction)`, trailing.
- Popovers keep the circle icon buttons.
- Sheets use a centred title; popouts use a leading Module-label header.
- Footers use `GroupedSection(footer:)` at 11 pt `.secondary`: one short sentence or none.
- Nothing uses `.caption2` or `.tertiary` text.

**FX-02 (Claude `dock-surface`): Dock and the editor.** Owns:
- `CustomDockView` except the popover host lines;
- `DockPresentationPolicies`;
- `CustomDockWindowController`;
- `DockCanvas`;
- `StyleSwatch`;
- `DockLayoutPreview`.

Fixes:
- Codex #7: cache running-indicator matches;
- D4: vertical badge clip;
- the trailing separator;
- D18: StyleSwatch scheme source;
- `DockCanvas` keyboard reorder motion.

**FX-03 (Claude `widget-visuals`, after FX-01): widget shell, sheet and shared faces.** Owns:
- `WidgetViews.swift`;
- `WidgetConfigurationSheet.swift`;
- `WidgetPrimitives.swift`;
- `AppleWidgetCard.swift`;
- `WidgetAppearance.swift`;
- the popover host lines in `CustomDockView` (around 826–832) only.

Fixes:
- D1: one surface per popout;
- Codex #2: Remove failure and retry;
- D3: Sticky Note;
- D6: period tokens;
- D7: Start contrast;
- D12: no hero in embedded mode;
- D14: Customize reuses the sheet's Appearance and SizePager, and the App Folder palette comes from `WidgetPalette`;
- D15: label over value and labels-off alignment;
- the Disk and Media truncation;
- removing dead `RemindersDockFace` and the dead provider compact views;
- the Clock hero.

**FX-04 (Claude `widget-visuals`, after FX-01 and FX-03): RD-09 family files.** Fixes:
- D8: Weather night glyphs and hour labels;
- D12: the Trash footer and the Alarm time format;
- D17: Now Playing seek symbols, Weather Next Hours layout, Checklist IC Add;
- T1: move settings rows behind Customize where a family puts more than about 3 settings rows in the popout body.

**FX-05 (Codex, high): RD-10 family files plus `FacesBQA`.** Fixes:
- D9;
- the AI Limits order and duplicate freshness;
- D5: AI Activity two lines;
- Codex #4: accessible chart values;
- Codex #5: remove the dead colour pickers from the UI while keeping their persisted keys;
- `FacesBQA` renders inside the real `WidgetPopout` shell;
- T1 for its families.

**FX-06 (Codex, medium): Settings.** Owns:
- `UI/Settings/*`, `SettingsView`;
- `AppLifecycleSettingsView`, `RecoveryCenterView`, `PrivacyHelpSection`;
- `DockInspector`, `PersonalPresetPicker`;
- the settings helpers in `DockDesign`.

Fixes:
- D10, D11 (and the duplicate "Settings" title), D16;
- Codex #6: Restore defaults;
- the Finish / Glass finish redundancy;
- long footers;
- D17: inspector slider alignment and the presets Remove button;
- D13 for the inspectors.

**FX-07 (Claude `widget-gallery`): gallery.** Fixes:
- Codex #3: keyboard route to the detail view;
- D2 and Codex #8: previews use the creation configuration (`DockItem.widget(kind)`);
- D17: Apps check vs plus, spacer descriptions;
- T3: no stroked tile;
- T7: shorter detail copy.

**Deferred, recorded:** T2 (accent semantics: product decision) and T5 (sheet preview strip).

### FX-01 — merged (branch commit `808ecb5`) plus project regeneration `b71840c`

**Root cause.** It was not text wrapping, as hypothesised: it was the popout shell. `WidgetPopout` fixed its width with `.frame(width:)` but left its height compressible. Family content scales to fit: `WidgetPopoutHero` uses `minimumScaleFactor(0.5)`. As a result:
- The hosting view reported a window content minimum height below its maximum (Trash: 373…396).
- The fractional measured height (from a 0.5 pt separator) rounded the window down 1 pt per pass until AppKit threw `NSGenericException`: "…more Update Constraints in Window passes than there are views in the window." The worker observed this reason by temporarily swizzling `_crashOnException:`.

**Scope.**
- Almost every popout had min < max. Unit Converter crashed the same way once Trash was bypassed.
- The live popover wraps the shell in a real `ScrollView`, which hands the shell its natural height. The worker reasoned from code that the live path is not exposed. This is not natively verified.

**Fix.** `.fixedSize(horizontal: false, vertical: true)` on the shell at `WidgetViews.swift:~152`, with an explanatory comment.

**Test.** `PopoutLayoutLoopTests` (2 tests):
- Trash, across every error shape;
- every registry family: the popout is vertically rigid (min == max) and settles in a window at 460×680.

Both tests fail with the fix commented out.

**Verification.**
- Worker: the WIDGET export now completes with 130 PNGs, exit 0. The FACESA, FACESB and WIDGETSHEET exports are unchanged apart from time-driven pixels.
- Integration: `./TestMyDock.sh` **611 tests in 78 suites** (`.build/redesign-fx01-test.log`).

### Fix wave launches

- FX-05 (Codex) runs from `090ff19`.
- FX-03 (`widget-visuals`) runs from `b71840c`.
- Queued: FX-02, FX-06, FX-07, then FX-04 after FX-03.

### Interruptions and FX-05 relaunch — 5 October 2026

- **FX-03** was interrupted by an API session limit while working on the Sticky Note face. It was resumed from its transcript; its uncommitted edits were intact.
- **FX-05's first Codex run never started work.** `codex exec` printed "Reading additional input from stdin..." and then waited on an open stdin for about 4 h. The worktree had no changes.
  - The orchestrator stopped its own stuck process (exit 144) and relaunched with `< /dev/null`. The model then started normally.
  - Every later `codex exec` launch closes stdin. Earlier runs only got past this by chance.

### FX-03 — merged `062b2a0` (branch commit `d8c233f`)

**D1 decision (accepted):** the `NSPopover`'s own material is the single surface.
- The shell no longer draws `dockGlass`, and the host adds no padding or opaque slab.
- `WidgetPopoverSurface` fills opaque under Reduce Transparency.
- Rationale: NSPopover always draws its material and arrow, so a glass card inside it always reads as card-in-slab. The native material gives macOS 26 Liquid Glass and system Reduce Transparency/Increase Contrast handling.
- `WidgetDesign.surface` is now `DockDesign.page`. In production it is only used for the Reduce Transparency fill.

**Codex #2 (Remove Widget):**
- Draft rollback when the store was untouched.
- A pending removal that retries when the write failed after the store applied it.
- Undo is registered only after success.
- The sheet shows the error and a "Retry Remove Widget" action, and does not dismiss.

**D3:** Sticky Note is one flowing text, two lines, word-wrapped. The sample note is "Call Mia about the trip".

**D6:** `WidgetPeriodToken` adds "Today", "7d", "30d" and "Month". `ModuleLabel` drops the trailing text via `ViewThatFits`.

**D7:** role-based `WidgetRoundButtonStyle`, measured at about 5.3:1 and 7–7.6:1 under Increase Contrast.

**D12:**
- The `widgetPopoutShowsHero` flag and `WidgetSheetHeroPolicy` stop the hero repeating in the sheet. Clock has no Content section.
- `WidgetPopoutHeroGroup` hides a hero together with its decoration.

**D14:** `WidgetCustomizePanel` reuses the sheet's pager and Appearance controls. App Folder colours come from `WidgetPalette.profile`.

**D15:**
- Label over value in System Activity Compact.
- `ModuleAlignmentPolicy` centres every face when labels are off.

**Truncation:**
- `DiskSpaceFaceText` uses three significant digits, locale-aware ("121 GB").
- `MediaDockFace` never breaks a word.

**Dead code removed:** `RemindersDockFace`, `BusinessDockFace` and seven provider compact views. All were verified as unreferenced.

**D13:** already compliant.

**Hand-offs:**
- To FX-04: Weather and Trash hero decoration in the sheet.
- To FX-02: MotionQA still emulates the old 20 pt host padding.

**Verification:**
- The worker ran 623 tests (FX03Tests has 12, including contrast ratios). Exports: WIDGET 130, WIDGETSHEET 62, WIDGETSURFACE 68, MOTION 25, SETTINGS 74.
- The orchestrator viewed `motion-popout-end-light` (single surface) and `widgetpopout-countdown-light` (white Start on solid green).
- Integration: `./TestMyDock.sh` **623 tests in 79 suites** (`.build/redesign-fx03-test.log`).

### FX-04 launched

`widget-visuals` agent, base `062b2a0`.

### FX-05 — merged (branch commit `65442e6`), plus integration fix `80ecbe0`

**Implementation:** the RD-10 families follow the review fixes. Each item below lists its source file:
- **FacesBQA:** renders inside the real `WidgetPopout` host and the sheet (`FacesBQA.swift:164`).
- **Type scale:** no `.caption2`, `.tertiary` or 10 pt text remains in its files. Footers are one line.
- **Reading first:** AI provider readings now lead the popout (`AIUsageWidgetViews.swift:207`).
- **Freshness:** duplicate family timestamps are removed.
- **Stock setup:** the setup screen has no Refresh row.
- **Stripe:** the account contradiction is fixed, with a truthful saved-account fallback (`StripeWidgetViews.swift:98`).
- **System Activity:** the hero is centred, the stray "Updated 0:00" (a midnight QA fixture) is fixed, and memory text is larger.
- **AI Activity faces:** limited to two lines via `ViewThatFits` (`:367`).
- **Accessible dated charts:** Paddle and Shopify charts expose VoiceOver value lists with tested series helpers (Paddle `:157`, Shopify `:175`).
- **Colour pickers:** the dead pickers are removed. Their persisted fields are untouched.
- **Period tokens:** compact tokens in the business families.

**Worker verification:**
- `RedesignFacesBTests`: 14 passed.
- 426 renders; the worker inspected all 108 shipping popouts.
- The full suite stalled in the Codex sandbox, in LaunchServices and subprocess waits.

**Integration:** a clean merge with FX-03. Unsandboxed `./TestMyDock.sh`: **629 tests in 79 suites** (`.build/redesign-fx05-test.log`).

**Orchestrator review:**
- Viewed `facesb-popout-ai-limits-ready-light` and `facesb-popout-stripe-ready-dark`. Both now lead with the reading, then grouped settings, then one footer.
- **Integration fix `80ecbe0`:** the shared freshness line always labelled its manual refresh "Retry", even beside a green "Updated 1 minute ago". It now says "Retry" only for a stale or failed reading, and "Refresh" otherwise (`WidgetFreshnessView.swift`).

**Open note:** the inherited Claude connection note in `AIAccountConnectionView` is unowned. It goes to FX-06 if it is in Settings, or stays as a follow-up otherwise.

### FX-02 launched

`dock-surface` agent, base `80ecbe0`.

### FX-04 — merged (branch commit `3735eb4`), plus integration fix `0ac58f6`

**Implementation:** implemented.

- **Hero decoration:** the Weather condition card and the Trash glyph now hide together with the hero in the sheet, via `WidgetPopoutHeroGroup`.
- **Duplicate copy removed:**
  - Trash: the hero caption is "item"/"items", and the scope appears once, in the footer.
  - Alarm: one formatter (`AlarmFacePresentation.timeText`). The hero alarm is not repeated in the list.
- **Weather day/night per hour:** `WeatherDaylight` computes it from solar elevation at the city's coordinates, with the provider's −0.833° horizon. It needs no new request and no persistence change. Tests cover Warsaw, the equator, Tromsø polar night and midnight sun.
- **Hour labels:** `WeatherHourLabel` gives "3 AM" or "03:00" depending on the locale.
- **Now Playing:** the seek buttons use numbered symbols (`gobackward.N`) with a fallback.
- **Weather Next Hours:** the column is evenly distributed via `ViewThatFits`.
- **Add button:** the disabled state is visible (`WidgetRowTextButtonStyle`), with an edge under Increase Contrast.
- **Reading first:** the Calendar, Now Playing, Weather and Alarm popouts show the reading first. Their settings sit in a collapsed "Settings" disclosure (`WidgetPopoutSettingsDisclosure`) that is accessible and has no animation under Reduce Motion. In the sheet the settings are shown in full.
- **Footers:** one short sentence each; the detail is in `.help`.

**Integration fix `0ac58f6`:** the Dock weather face (`WidgetPrimitives.swift:776`, outside FX-04's ownership) now uses `WeatherDaylight.isDay` per forecast hour.

**Verification:**
- Worker: 631 tests passed; FACESA produced 87 renders and WIDGET 130.
- Integration: `./TestMyDock.sh` **637 tests in 79 suites** (`.build/redesign-fx04-test.log`).

### FX-06 launched

Codex, effort medium, base `0ac58f6`. Launched with stdin closed.

### FX-02 — merged (branch commit `47578a1`), plus integration fix `fa9971b`

**Codex #7: `DockRunningAppMatches` and `DockRunningAppCache`.**
- The cache lives in `@State` and is recomputed only when the running apps or the profile's app items change. A hover re-render costs one equality check.
- The render model receives the already-matched apps (`DockRenderModel(... unpinnedRunningApplications:)`). Building the model no longer normalizes URLs or calls the resolver.
- Tests use a counting normalizer: 50 re-evaluations cause no further normalization.

**D4: `DockBadgePlacement`.**
- Badges sit inside the tile in left/right Docks; bottom Docks keep the outward offset.
- The DOCKSTYLE export asserts that badges "3", "24" and "99+" fit the column at sizes 0.65, 1 and 1.5.

**Trailing separator: `DockSeparatorPolicy`.**
- The stray line was the pinned-end `.insertion` entry. A separator now draws only between content.
- The live resize grip stays as a target; its line shows only between content or on hover.
- Previews also collapse the empty end slots. Live geometry is unchanged. The orchestrator accepted this.

**D18: `DockColorSchemePolicy`.** One scheme source (Dock theme, then the Midnight material, then the system appearance) is shared by `CustomDockView`, `DockCanvas` and `DockSwatchPreview`. A new `dockSwatchTheme` environment value carries it.

**Editor reorder.** `DockCanvas` uses `DockMotionPolicy.reorderAnimation` and a settle spring. There is no motion under Reduce Motion or with animations off.

**D17 previews.**
- `DockLayoutPreview(fitsByScale:)` is used in `MotionQA`. The `MotionQA` popout emulation now matches FX-03's single surface.
- Orchestrator fix `fa9971b`: the real "Preview your new Dock" sheet (`DockManagerView.swift:795`) passes `fitsByScale: true`.

**Hand-offs.**
- To FX-06, or the orchestrator after FX-06 merges: `AppearanceSettingsPage` must set `.environment(\.dockSwatchTheme, appearanceSettings.customDockTheme)` on the Style section.
- To FX-07: text-free `PresetLibraryTile` thumbnails.
- Noted, not changed: `AppLauncher.isMissingTarget` still stats the file system per tile per body evaluation. Caching it needs an invalidation rule; this is recorded as a follow-up.

**Verification.**
- Worker: 641 tests passed. Exports: DOCKSTYLE 88 (badge check passed), MOTION 25, SETTINGS 75, GLASS 17 (corner alpha passed).
- Integration: `./TestMyDock.sh` **649 tests in 80 suites** (`.build/redesign-fx02-test.log`).

### FX-07 launched

`widget-gallery` agent, base `fa9971b`.
