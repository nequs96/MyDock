# MyDock Apple-style design rebuild

**Date:** 30 September 2026. **Status:** implemented locally; distribution and production-system acceptance remain separate gates.

The design follows the content-first widget presentation and simple appearance choices shown on [Dockset's widget page](https://dockset.app/#included-title) and [appearance guide](https://dockset.app/manual/appearance). The implementation uses native SwiftUI/AppKit, system typography, SF Symbols, and original code. It does not establish pixel-for-pixel parity or a measured claim that MyDock is better than Dockset.

## Implemented

| Area | Result |
| --- | --- |
| Shared visual system | System fonts replace the large serif headings. Smaller headers, system accent color, restrained borders, rounded grouped cards, and native controls carry through the main windows. |
| Settings | Seven pages have clear headings and colored sidebar icons. Choices and switches align at the trailing edge. Dock position, theme, and density use segmented controls. Behavior is split into visibility, apps/windows, items, and interaction groups. |
| Appearance | A layout preview sits above visual finish swatches. Global/profile scope and Undo remain available. Size and spacing stay visible; corner radius and tint sit under Advanced appearance. Search opens the advanced controls when appropriate. |
| Widget cards | Calendar emphasizes its date and next event; Reminders emphasizes the count; Weather presents temperature/conditions or a compact hourly forecast; notes show their text; timers show the value and progress. Battery rings, actual market sparklines, media artwork/title, CPU/memory readings, network rates/history, world time, and time progress get layouts suited to their content. |
| Widget gallery | A two-column gallery offers visual samples, search, a category picker, and clear add actions. Sample data is explicitly identified and never written into live provider snapshots. |
| Manager | A compact system-font profile header, quieter action rows, the shared Dock layout preview, and widget thumbnails replace the oversized widget glyphs. Staged Save/Discard/Undo remain intact. |
| Presets | Nine preset families have visual widget samples. Personal presets remain available. Selection still resolves installed apps once, opens a review, permits substitutions/removal, and creates the profile with one save. |
| Onboarding and About | Onboarding uses short step-specific headings and native selection cards. About uses the bundled app icon and a compact system layout; the app menu opens this same window. |
| Popouts | The shared wrapper uses system typography, native aligned switches, a Customize action, freshness/retry information, and Escape close. Individual provider workflows and connection handling are preserved. |

The changes cover 16 app source files, including two new shared view files, plus a settings-search regression in the existing test suite. A design-only patch is saved at `.build/design-baseline-20260930/apple-design.patch`. Preexisting work remains preserved in the design baseline and the earlier implementation baseline.

## Fixes found during the rebuild

- Timer samples now fit the standard card without clipping the value.
- Six-hour weather rows use flexible narrow columns instead of overflowing a standard card.
- Compact cards keep compact provider geometry; large provider layouts are used only at standard/wide widths.
- Countdown cards retain the unset-date and completed-date states.
- Search results and sidebar filtering agree, including control names absent from page keywords.
- Search anchors follow the new behavior groups. Advanced appearance expands when selected from search.
- Aligned switches expose one accessible label rather than repeating the label.
- About reads the bundled icon directly rather than depending on a launch-time application-icon cache.

## Verification

`./TestMyDock.sh` passes the 191-test, 13-suite run. Two opt-in tests are skipped by default: live native-Dock transactions and performance capture. A new regression covers settings pages remaining visible when a matching control is found. Existing draft, persistence, notification, geometry, runtime, provider, and recovery checks remain in the suite.

Native visual/interaction checks used the disposable DEBUG preview on macOS 26.5.1. Its store is isolated, system changes are disabled, and the normal native-Dock controllers are not started. Checks covered the Manager, grouped Settings, appearance swatches, light/dark Dock cards, timer fitting, widget search/add/discard, preset review/create, onboarding, About, and side-preview clipping with working jump-to-start/end controls. Settings search opens the advanced section and retains its matching sidebar page. Full VoiceOver navigation was not performed.

The generated Xcode project includes the new views. The local universal app contains arm64 and x86_64 slices targeting macOS 13. The standalone preview uses the DEBUG test binary and requires macOS 14. Signature, plist, archive, fingerprint, and artifact hashes are recorded in [the verification manifest](APPLE_DESIGN_VERIFICATION_2026-09-30.json).

## Review and use

- `build/MyDockAppleDesignPreview.app`: disposable design review with sample widgets; it does not change the user's Apple Dock or saved production profiles.
- `build/MyDockAppleDesign.app`: current local app bundle with the redesign.
- `build/MyDockAppleDesign.zip`: the same app packaged for local transfer.

The local bundles are ad-hoc signed, not notarized distribution releases. The earlier `MyDockImplementationReview.app` and its verification record remain historical artifacts from before this redesign.

## Acceptance still pending

The local design implementation is complete. Shipping acceptance still requires the broader all-widget popout/keyboard/VoiceOver matrix, complete long-Dock/resize/contrast/motion variants, and runtime checks on supported macOS versions and Intel hardware. Production animation frame pacing and energy measurements remain pending.

Native apply/recovery/replacement mode, delivered notifications, permissions, Spaces/fullscreen, and display changes need a disposable macOS account or VM. Live provider expiry/offline/remapping needs dedicated accounts. Xcode UI tests, Focus metadata discovery, signed/notarized installation/update/login acceptance, and CI need full Xcode, publisher credentials, and a release repository. These requirements are tracked in [the implementation ledger](../IMPLEMENTATION_STATUS.md).
