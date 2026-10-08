# MyDock implementation and acceptance status

## Full audit — 5–8 October 2026 (current)

Every file was audited; 505 of 527 findings are resolved and 22 are deferred with a plan ([report](history/FULL_AUDIT_2026-10-07.md)). CI at `d2c9500`: **1,104 tests in 119 suites** passed on arm64 and Intel, and the full Xcode Release build succeeded.

**Open:** the 22 deferred findings (mostly large file splits and refactors, plus three checks that need a Mac) and the report's manual checks, together with everything under [Open acceptance](#open-acceptance).

## Redesign — 5 October 2026

The authorized redesign is implemented. It covers widget visuals, widget settings and customization, app settings, Dock appearance and the Add Item window:
- RD-01–RD-11;
- fix waves FX-01–FX-10;
- follow-ups FU-S, FU-G and FU-W;
- T2, Auto accent semantics.

The [redesign ledger](history/REDESIGN_LEDGER_2026-10-04.md) is the per-package record, with implementation status and verification status kept separate.

**Verification:**
- On the Mac, FX-08/FX-09 passed `./TestMyDock.sh` with **685 tests in 84 suites**.
- On the Mac, the build and the 1,366-render matrix were done after FX-07.
- FX-10 and later have CI and static-review evidence only. At `3a0dd69`, CI passed **695 tests in 85 suites** on arm64 and Intel, and the full Xcode Release build succeeded. See [RELEASE_AUDIT.md](RELEASE_AUDIT.md).

**Open:**
- A native rebuild, relaunch and full render matrix for FX-08 onward.
- The redesign's manual checklist:
  - Liquid Glass over wallpapers, in light and dark;
  - hover and morph;
  - reveal and auto-hide;
  - side Docks;
  - multiple displays;
  - Intel and macOS 13–15 fallbacks;
  - keyboard-only flows.
- Everything under [Open acceptance](#open-acceptance).

**Product wave (PX-1–PX-8), 5 October 2026.**
- **Scope:** OP-01–OP-07 are implemented within their ledger scopes, plus Dock essentials, window previews and product polish. See the [product plan](history/PRODUCT_PLAN_2026-10-05.md).
- **CI at `5dfccf1`:** **829 tests in 93 suites** passed on arm64 and Intel, and the full Xcode Release build succeeded.
- **Not yet verified natively:** every new feature still needs a check on a Mac. The window previews, drop-to-open, audio switching, workspace start and automatic switching all act on the real system.

## Open acceptance

None of these is a known code defect. Each needs a Mac, an account or a signing identity that CI does not have. Ticket numbers (T01–T30) refer to the roadmap table in the [dated status record](history/IMPLEMENTATION_STATUS_THROUGH_2026-10-05.md), which also holds the earlier wave records.

**Native rebuild and renders**
- Rebuild and relaunch `build/MyDock.app`, then re-run the full render matrix, including Reduce Transparency and Increase Contrast, for FX-08 onward and the product wave.

**Native desktop (H1–H9)**
- Liquid Glass over several wallpapers in light and dark, and whether widget glass blends with the Dock glass.
- Hover, morph, magnification and reorder feel; reveal, auto-hide and interrupted reveal; frame pacing on high-refresh displays (T13).
- Side Docks, bottom and side overflow and size variants, multiple displays with mixed scale, display changes, Spaces, fullscreen, Mission Control and Apple Dock overlap (T09, T10, T15).
- Keyboard-only and VoiceOver flows for Add Item, Settings, the editor and popouts, with real Reduce Motion, Reduce Transparency and Increase Contrast settings (T24).
- Editor pointer drops from other apps, into an empty or overflowing Dock and for live Dock groups; Escape and auto-scroll during a drag (T11).
- The product wave on the real system: window previews, drop-to-open, Force Quit, audio switching, Start Workspace and automatic switching (PX-1–PX-8).
- Notification delivery across sleep and wake, midnight, time-zone and daylight-saving changes for Countdown, Alarm and Hydration (T03, T23).
- Real minimized windows and changing window titles; Trash, Finder, AirDrop, Music and Spotify actions (T12, T23).
- Missing or moved files, failed launches and a large icon catalog (T21); history inspection and restore, and personal preset import and export (T17, T29).
- The first-run flow on a clean install (T18) and migration of state from older app versions (T06).
- Calendar and Reminders with real EventKit data and calendar colours.

**Native Dock, in a disposable account or VM only**
- Native profile apply, rollback and interrupted-transaction recovery, replacement-mode restoration and external auto-save association (T04, T05, T26). Use the [real Apple Dock test](ACCEPTANCE_TESTS.md#real-apple-dock-test) only with separate approval.

**Supported systems**
- macOS 13–15 runtime and the pre-26 material fallbacks, and an Intel Mac at runtime. CI runs only on macOS 26.

**Live accounts**
- Stripe, Paddle, Shopify, Alpha Vantage, GitHub Copilot and the AI providers: expired or revoked credentials, rate limits, offline use, sparse market history and account remapping on another Mac (T07, T19, T22).

**Performance**
- Instruments-grade CPU, memory, energy and frame pacing for hidden and visible Docks, many widgets and network refresh (T14, T25). Only `ps` samples exist so far.

**Distribution (T27, T30)**
- CI builds and tests on macOS 26 arm64 and Intel, including the full Xcode Release build and its App Intents metadata check. Still open: Developer ID signing and notarization, Focus filter discovery and background invocation, the Xcode test action and the manual Visual QA UI target, the signed Login Items flow, clean install and update, and a real publisher release for update discovery.
- A matched comparison with Dockset is still needed before claiming parity.
