# Widget gallery and disappearing Custom Dock fixes

30 September 2026. This follow-up addresses the reported blurry Add Widget previews, unstable pointer sizing and Custom Dock disappearing shortly after a mode change. It preserves the existing profile library, widget providers and native Dock management.

## Repairs

- **False overview detection:** the presentation loop checks every 500 ms. Its window reader previously accepted every visible Apple Dock-owned window, including large desktop/background surfaces. Those could be interpreted as Mission Control and suppress the Custom Dock even with auto-hide disabled. The reader now excludes desktop elements and negative window layers, invisible windows and invalid bounds. Genuine foreground overview surfaces retain the existing suppression behavior.
- **Stale reveal callbacks:** mouse events and delayed reveal work now check that a Custom Dock mode and an active custom profile still exist before showing the panel. Changing to macOS Dock only cannot resurrect it through a queued callback.
- **Preview sharpness:** gallery and preset previews now lay out their fonts, symbols, spacing, strokes and surfaces at their displayed dimensions. The previous post-render scale transforms have been removed.
- **Pointer sizing:** a dedicated gallery button style changes pressed opacity only. Hover changes border/accent contrast, with constant preview geometry, caption height and action bounds. Added confirmation uses the same geometry.
- **Gallery layout:** bounded adaptive columns, consistent preview baselines, a usable 480-point minimum height, deterministic widget ordering, trimmed search queries and scroll reset when changing category/search.
- **Sample quality:** compact samples no longer squeeze full-width labels into tiny cards. Clock, network, AI, business and progress samples are more legible. Alarm, AirDrop, App Folder, Shortcuts and Trash have specific previews. Standard sample labels fit their available space.
- **Missing AirDrop icon:** the nonexistent `airdrop` SF Symbol was replaced by a supported symbol, shared by the registry, gallery and live Dock tile. A regression checks that all registered widget symbols are drawable.

## Verification

- `./TestMyDock.sh`: **210 tests in 14 suites reported passing**. The normal run skips three opt-in cases: native Dock mutation, synthetic performance capture and the real-panel test below.
- `MYDOCK_CUSTOM_DOCK_RUNTIME_TESTS=1 ./TestMyDock.sh --filter customDockRemainsVisibleAcrossPresentationTicksAndModeChanges`: passes separately. An isolated real AppKit panel exercises the actual polling loop and transition animations at the bottom, left and right edges. Each position runs both Custom Dock modes, macOS Dock only, then returns to both mode, sampling visibility six times over 1.2 seconds per mode. The final run took 17.123 seconds. This test does not start the native Dock auto-hide controller or change Apple's Dock preferences.
- `./BuildMyDock.sh --output build/MyDockFixed.app`: universal arm64/x86_64 release succeeds, targeting macOS 13. Ad-hoc signature verification passes.
- DEBUG render matrix: **47 native SwiftUI/AppKit layout images**, including gallery widths 760/960/1200, 480-point minimum height and all **81 variants of the 27 widgets**. The gallery and complete widget catalog were inspected at full size; the complete matrix was reviewed as a contact sheet. The AirDrop icon and truncated samples were corrected after the first visual pass, then rendered again.
- `git diff --check`: passes. Existing uncommitted changes were preserved.

## Desktop acceptance

The running release was inspected at the beginning of this follow-up, confirming the enlarged, soft gallery previews. The Mac subsequently locked, and computer-use tools could not unlock it. The final desktop pointer, keyboard, category scrolling and user-profile mode-switch checks remain pending. Offscreen renders and the AppKit panel-state test do not establish visible desktop behavior, Mission Control acceptance or multi-display behavior.

The older `build/MyDockAudited.app` remains the running copy. Quit that copy and open **`build/MyDockFixed.app`** to use the repairs. No production profile changes were made during this follow-up.

## Evidence

- `.build/gallery-visibility-tests.log`
- `.build/gallery-visibility-runtime-tests.log`
- `.build/gallery-visibility-build.log`
- `.build/gallery-visibility-render-bundle.log`
- `.build/gallery-visibility-visual-qa/`
- `.build/gallery-visibility-contact-sheet.jpg`
- `docs/GALLERY_AND_DOCK_VERIFICATION_2026-09-30.json`

An initial render launched outside an application bundle stopped at the notification permission page because UserNotifications requires a valid app bundle. The final render ran inside the signed isolated preview bundle and completed successfully.
