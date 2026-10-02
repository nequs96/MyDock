# Dock workspace product rebuild — 1 October 2026

This report covers the direct-manipulation rebuild from the existing working tree. It does not replace earlier dated verification.

## Audit inventory and disposition

| Feature | Decision | Connection in rebuilt product |
| --- | --- | --- |
| Custom and native profiles, color, naming, copying, deletion | Keep domain; rebuild presentation | Single Dock sidebar, inline name, context menus, overflow |
| Per-profile/global appearance inheritance | Keep | Dock inspector creates an explicit profile appearance; Use App Defaults restores inheritance |
| Atomic/versioned persistence, draft merge conflicts, failed-save retention | Keep | Debounced autosave through the existing edit-session coordinator, recoverable failed drafts |
| Profile history, personal presets, curated presets | Keep/rework | Explore opens preview/resolve/create; personal preset actions remain contextual |
| Native Dock import/apply/verification/rollback/recovery | Keep | Native profiles retain explicit Apply and current-layout replacement; recovery UI remains in settings |
| App discovery, file/folder/link picking, favicon and reference repair | Rework | Searchable Add Library, Browse actions, contextual Replace/Locate |
| Typed reorder payloads, multi-select, group ordering, spacers | Rework | Direct canvas dragging, Command/Shift selection, insertion cue, accessible move actions, keyboard movement |
| Widget registry and 27 miniature providers | Keep shared renderers; unify placement | Editor and live panel share widget views; Add Library offers miniature previews |
| Widget configuration, card widths, account setup, provider errors | Keep | Item Configure opens the bounded native widget editor |
| Folder icon/name/label options | Rework | Item inspector retains every folder option |
| App Settings, permissions, accounts, shortcuts, backups/diagnostics | Keep capabilities; rebuild chrome/groups | Same shell, category picker, simple separated sections and native controls |
| Menu bar, Focus filter, global shortcuts | Keep | Existing runtime architecture and activation routes |
| Running apps, media visibility, minimized windows, Trash, badge reads | Keep | Live Dock render model and service lifecycles preserved |
| Panel placement, auto-hide, edge dwell, overview/Spaces heuristics | Keep | Existing controller and preference restoration remain intact |
| Hover magnification, resizing, live drop/launch/popup behavior | Keep | Existing live Dock behavior; shared material surface reconnects editor appearance |
| Onboarding with optional starters and persistence gate | Keep foundation | Existing four-step mode/starter/placement/review flow; new semantic tokens apply |
| Light/dark/system interface appearance | Keep | Intentionally adaptive neutral palette; Dock theme remains independently scoped |
| Redundant top navigation, permanent item card grid, Save/Discard footer | Remove | One navigation shell, Dock canvas, contextual inspector, autosave |
| Permanent profile count/search/empty categories, reorder arrows | Remove | Search appears only above eight profiles; keyboard/accessibility actions replace arrows |

## Architecture

`DockWorkspaceView` owns top-level navigation and sidebar visibility. `DockManagerView` continues to own selected profile and existing safe draft/domain flows. New `DockCanvas`, `DockCanvasItem`, `DockAppearanceInspector`, `DockItemInspector`, `AddLibrary`, `InstalledAppCatalog`, and `DockMaterialSurface` separate presentation responsibilities. The live Dock and editor share material rendering and compact widget content.

No persistence schema migration is required. Profile and item identities, widget configurations, provider snapshots, credentials, profile drafts, and system recovery records retain their existing formats and storage locations.

## Interaction design

Shared apps use semantic matched geometry, disambiguated for repeated items. Reordering uses a damped spring with an insertion position; adding selects the new item. Structural motion respects Reduce Motion. Clicks in the editor select instead of launching. Right-click exposes configuration, replacement, duplication, and removal. Native Undo tracks profile edits. Command-K opens searchable profiles/actions/apps/widgets; Command-N creates a Dock; Command-comma opens Settings.

## Verification

Evidence is recorded in `docs/RELEASE_AUDIT.md` after final build/visual verification. Default tests avoid native Dock mutation. Disposable rendering is explicitly isolated. Existing live-account, multi-display/Spaces, distribution-signing, older-OS/Intel-execution, and pointer-frame-pacing qualifications remain applicable.


## Additional acceptance fixes

Native UI checks exposed and fixed three presentation issues: Command-K opened the Add surface instead of commands, a first Configure action could produce an empty sheet, and immediate duplication could reuse the preceding name field. Presentations now carry typed targets, and profile title fields have profile-scoped identity. A later word-boundary check found that trimming persisted names could alter active text entry; the inline editor now keeps its own buffer while autosave writes the normalized name.

The editor's direct native drag was exercised against the disposable store. Clock moved from the first position to before Sticky Note, and the persisted item order matched. Native tile snapshots replace a separately rendered drag preview. Item providers carry the same JSON group payload as the live Dock and also accept file/browser URLs. The end destination is wider and includes a hit-testable fill. Broader group/end/external-drop pointer acceptance remains pending.

Close controls in the library and inspectors now have semantic 30-point hit targets. The old gallery is restricted to DEBUG comparison renders. Appearance Undo is shown when a reversible appearance edit exists. Subprocess wall-clock tests are serialized within their stress suite; no timeout expectation or production deadline was relaxed.

The latest local default run reports 228 tests in 16 suites passing. Isolated native panel acceptance passed separately across all edges and presentation transitions. The 56-layout render matrix includes the minimum 780-point settings width. Canonical evidence is refreshed after final bundle inspection; current native rename-buffer and Settings-shortcut retests are pending because the UI tool returns `cgWindowNotFound` for new preview windows.

Native layout status is now mode-aware: remembered custom profiles are inactive in native-only mode, and native layouts are shown as Applied (with hidden-state explanation in replacement mode). Regression assertions cover default workspace selection and menu status. Creation exposes custom versus macOS layout in the same small sheet; current-Dock import creates one complete profile atomically. Native Add Library omits widgets and unsupported external drops explain their limitation. The final universal build and signature/plist/project checks pass; final native launch acceptance is still open after CUA timed out.

The external drop loader now collects native providers into one ordered batch. Delayed provider callbacks cannot scramble Finder order; malformed typed payloads are ignored, and manager callbacks verify their captured destination profile before applying edits. A regression uses a delayed group payload, malformed JSON and two URL providers; it passes in the 228-test run. Native external-drop pointer acceptance remains open.

## Native access resumed and keyboard acceptance

Native automation became available again in the resumed goal turn. Both old previews were quit cleanly. The canonical app launched from `build/MyDock.app`, showing the existing five profiles and real provider/widget content. An updated isolated preview verified: buffered `Build ` then `& Code` rename across autosave; native layout creation with correct type/source choices; native Add Library limited to Apps/System; Terminal search/Return insertion; first Settings shortcut sheet targeted Native Layout; and Command-K from Settings returning to the custom workspace.

Keyboard QA exposed a real gap: Shift-arrow movement collapsed selection. Navigation now has an explicit cursor, named Shift-left/right commands, safe first/last entry, selection reset, and focus synchronized to the active endpoint. Native Shift-right extended Clock/Weather, further extension and contraction retained the range, and Command-right moved both together ahead of Sticky Note without changing their relative order. VoiceOver focus metadata followed Weather rather than remaining on the old anchor. Default regressions now report 229 tests in 16 suites passing, including removed-item cursor recovery.

Group/endpoint pointer attempts did not change item order. Temporary DEBUG instrumentation logged a source drag but no destination entry or performed drop; delayed native tracking/quit responses were observed. The preview ultimately quit cleanly. The trace was removed from source. This does not certify a working pointer flow or identify the app versus automation as the cause. Group/endpoint/external pointer acceptance and production motion remain open.


## Physical-mouse drag fix

The user confirmed that end drops failed with their mouse, making this a real editor bug. The old SwiftUI onDrag/onDrop delegates and asynchronous provider loader were replaced with `DockCanvasDragView`. It tracks internal pointer movement and mouse-up directly, lifts a native tile snapshot, dims the moved group, animates one insertion position, preserves group order and cancels outside/profile-changed/Escape drops. Native pasteboard registration handles external URLs; the empty canvas now also exposes a destination.

Isolated CUA acceptance delivered Clock to the end and restored it with one Undo, moved Clock/Weather to start and end in order, dragged the narrow spacer between widgets, cancelled an outside release and opened the right-click menu. Final-source end drop and added-spacer focus transfer passed. Multi-selection no longer exposes Configure for an arbitrary first item; macOS layouts no longer expose custom appearance controls. Default regressions report 230 tests in 16 suites, including isolated NSView event delivery/cancellation/profile switching and native pasteboard URL ordering. This event test opens no window or production store and sends no desktop events.

The exact canonical bundle rebuilt after a clean quit, passed universal/signature/plist/project checks and started. The final 56-layout render matrix exported and key empty/native/selection layouts were reviewed. CUA subsequently returned cgWindowNotFound, so final canonical interaction and external/empty/overflow drag acceptance remain open. The running canonical app, preview and pointer probe were preserved for a future clean quit; no running bundle was overwritten.

## Accessibility and final-source launch refinement

Shared contrast-aware outline tokens now cover editor controls, search, widget surfaces, presets and the live/editor Dock. The material owns one Dock boundary, removing duplicate strokes. Release reads real system contrast/transparency; DEBUG-only render overrides do not change OS preferences. Eighteen additional dark/light/opaque/contrast variants extend the matrix to 74 layouts, using the actual Settings shell. Their contact sheet and selected full-size renders were reviewed. The light Midnight preset now uses readable white miniature icons.

Default tests pass 230 in 16 suites; the current-source isolated panel opt-in passed in 18.380 seconds without native Dock mutation. The canonical universal app rebuilt after clean quits, passed signature/plist/architecture/project/whitespace checks and opened through Manage Docks with five existing profiles and live widgets preserved. Command-K and Escape passed. Later CUA access again returned cgWindowNotFound, so broader drag/focus/resize acceptance remains open. Current hashes and evidence are in RELEASE_AUDIT.md and BUILD_BASELINE.json.
