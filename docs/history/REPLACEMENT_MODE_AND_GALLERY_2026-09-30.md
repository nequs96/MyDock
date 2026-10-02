# Replacement mode, Dock resizing and widget gallery

30 September 2026. Follow-up to the native Dock reappearing at the bottom edge, the misleading top-right resize control, and excess space caused by displaying three sizes of every widget.

## Replacement behavior

Ordinary auto-hide deliberately reveals Apple's Dock at the screen edge, as described in [Apple's Dock settings guide](https://support.apple.com/en-za/guide/mac-help/-mchlp1119/mac). The previous Custom-main mode only enabled auto-hide, so the reported reveal was expected from that implementation.

The mode is now labeled **Replace macOS Dock**. It sets `autohide = true`, a finite `autohide-delay = 86400` and `no-bouncing = true`, then restarts the Dock once and verifies the preferences. The delay prevents ordinary pointer reveal, and attention bouncing is suppressed. The underlying system Dock process continues running. This is preference-based suppression while MyDock runs; it is not removal of the macOS Dock process or a guarantee against an explicit keyboard command or another application overriding Dock preferences. The delay preference is also represented in the primary [nix-darwin implementation](https://raw.githubusercontent.com/nix-darwin/nix-darwin/master/modules/system/defaults/dock.nix).

Before mutation, a versioned recovery record stores all three original values, preserving absent keys. Leaving replacement mode or quitting restores those values. The previous auto-hide-only journal remains compatible and migrates before the additional preferences change. Failed application rolls back all three preferences; re-enabling never replaces the earlier session's original snapshot. Existing Dock layout writing and the operation gate are preserved.

## Resize control

The former expand-arrows icon was a resize handle, not a fullscreen action. The floating panel remains a native borderless, nonactivating panel. A small diagonal grip now communicates resizing, has a native resize cursor, compact hover feedback and a tooltip. Drag direction follows the screen edge: up enlarges a bottom Dock, right enlarges a left Dock, and left enlarges a right Dock. Size stays within the existing 65–150% limits. Double-click resets to 100%; VoiceOver supports increment, decrement and reset. Existing persistence and coalesced history are retained.

## Add Widget

- One card per widget, with a compact native Size menu beside Done. Compact, Standard and Wide update previews in place and set the configuration used when adding.
- Bounded adaptive columns with consistent preview, caption and description heights. Wide previews fit within the minimum column width.
- Previews retain the prior native layout scaling fix; pointer feedback changes contrast, with constant geometry. No post-render enlargement or hover zoom is introduced.
- Short, legible size labels and an untruncated media sample. The Size label remains on one line at minimum width.
- Existing categories, search, clear-search behavior, category scroll reset and quiet Added feedback remain functional. Sample previews use no connected services.

## Verification

- `./TestMyDock.sh`: **215 tests in 14 suites reported passing**, with three opt-in cases skipped. Five additional regressions cover full preference restoration, old journal migration/restoration, rollback after restart failure and edge-based resizing. DEBUG compilation retains the macOS 13-compatible `onChange` overload, which produces two deprecation warnings under the macOS 14 test target.
- Opt-in isolated real-panel test passes separately in **16.809 seconds**. Bottom, left and right edges exercise both Custom Dock modes, macOS Dock only and return to both mode, with six visibility samples over 1.2 seconds per mode. It does not mutate native Dock preferences.
- `./BuildMyDock.sh --output build/MyDockReplacement.app`: universal arm64/x86_64 release targeting macOS 13 succeeds; strict ad-hoc signature verification passes.
- **49 native layout renders**, including all 81 size variants of the 27 widgets, gallery sizes 760/960/1200, 760 × 480 minimum, Compact and Wide galleries, settings, onboarding, editor and Dock layouts. The changed gallery layouts were inspected at full size and the complete matrix as a contact sheet. The final narrow Size label and media sample corrections were rendered again.
- Native desktop gallery: size selection, Wide addition and subsequent configuration, search/no-results/clear, category navigation and scroll reset pass in an isolated preview profile. The final release gallery was also opened and inspected, including Compact size selection. No production widget or profile content was added or removed.
- Native release resize: accessibility increment/decrement changed 105% → 110% → 105%; pointer dragging changed 105% → 125% → 105%. The original production size was restored.
- Native release replacement: read-only checks of the three owned system preferences confirm replacement values on launch; exact original values return when changing to both mode and when quitting. Relaunch reapplies replacement. The updated release is left running in replacement mode.
- `git diff --check`: passes. Prior uncommitted redesign/audit work is preserved.

## Practical verification limits

The Mac was unlocked for this follow-up. Computer-use tools can inspect MyDock windows, but could not bind the system Dock process and cannot send pointer input to Finder's Desktop surface. Therefore a direct visual bottom-edge reveal comparison remains unverified. Native preference application/restoration and actual MyDock resizing were verified separately. Multi-display, Mission Control, explicit system Dock keyboard reveal and OS versions other than the current host still require desktop acceptance; the real-panel test does not establish those behaviors.

## Evidence

- `.build/replacement-gallery-tests.log`
- `.build/replacement-gallery-runtime.log`
- `.build/replacement-gallery-build.log`
- `.build/replacement-gallery-render.log`
- `.build/replacement-gallery-visual-qa/`
- `.build/replacement-gallery-contact-sheet.jpg`
- `.build/replacement-{original,enabled,restored,quit-restored}-visibility.json`
- `docs/REPLACEMENT_MODE_AND_GALLERY_VERIFICATION_2026-09-30.json`

The earlier gallery/disappearance report remains historical evidence. `build/MyDockReplacement.app` includes those fixes and the current follow-up.
