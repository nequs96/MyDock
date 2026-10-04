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
