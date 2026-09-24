# MyDock release audit — 24 September 2026

## Build and automated checks

- `./TestMyDock.sh`: 106 tests pass on the macOS 14 host, including the sleep-inclusive Stopwatch clock, persisted timing state, wall-clock change fixtures, defensive elapsed-time display, and opt-in native Dock auto-save isolation. The Swift Testing library supplied with this Command Line Tools installation links for macOS 14; the app itself targets macOS 13.
- `./BuildMyDock.sh`: release arm64 and x86_64 builds combine into `build/MyDock.app`; the bundle has an original icon and a valid ad-hoc signature. Developer ID signing, notarization, and an updater are not configured.
- Automated Dock tests use isolated preference backends. They do not write the machine's real Dock preferences.
- A read-only check of this Mac's Dock preferences found 15 pinned tiles, all with types the auto-save reader recognizes. No Dock preference was changed.
- The Music artwork and Spotify metadata AppleScript snippets compile with `osacompile`; no Apple Event was sent to a player during this audit.

## Source and data review

- No product `TODO`, `FIXME`, `TEMP`, `HACK`, `MOCK`, `STUB`, or `fatalError` markers remain. The two forced Accessibility bridges follow explicit Core Foundation type-ID checks. Tests contain fixed HTTP URL examples.
- Provider keys and access tokens are stored in Keychain and excluded from profile backups. The logging calls found in source report Dock recovery or shortcut registration errors, not credential values. The Now Playing UI no longer repeats raw AppleScript error text.
- Backup input has a 25 MiB cap, profile and item caps, URL policy checks, normalized bounded favicon data, and local-file validation for App Folder members. Import reports missing top-level and nested paths and does not activate imported profiles.
- Storage scans skip hidden files, package descendants, and symlinks; they run in a detached task after a user action, support cancellation, disclose skipped/capped results, and never delete files. Home and Library totals are separate because the locations overlap.
- Site icons are fetched only on an explicit action with bounded HTTPS requests. Spotify artwork uses a bounded credential-free HTTPS request to `i.scdn.co`; window previews and player artwork stay in memory.
- The Custom Dock's system, network, window, and Now Playing monitors stop or pause their recurring work while the Dock is hidden. No idle CPU, multi-display, or long-running memory measurement could be made while the desktop was locked.
- Native Dock auto-save stays off by default. When enabled, it reads pinned apps and spacers every five seconds, observes an initial baseline, ignores MyDock's own successful applies, and saves external changes only to the selected profile. Unsupported Dock tiles pause automatic saving instead of being silently dropped. Its fixture test never touches the real Dock.
- The optional menu-bar profile title is stored in settings, displays the applicable native and/or Custom profile names for each setup mode, truncates long names, and retains full names in the tooltip. Model and migration tests pass; visual layout remains unchecked while the Mac is locked.

## Acceptance still required

1. Unlock the Mac and run [the desktop acceptance checks](ACCEPTANCE_TESTS.md), including first-run UI, permissions, multiple displays/Spaces/fullscreen, popout geometry, VoiceOver, visual comparison, and idle/active performance.
2. Run [the real Dock snapshot/restore plan](REAL_DOCK_TEST_PLAN.md) only after separate user approval. The fixture suite establishes rollback policy but cannot prove behavior against this Mac's Dock preferences.
3. Connect the user's optional market, Stripe, Paddle, Shopify, and AI provider accounts to verify live data paths. Verify Music, Spotify, Calendar, and Reminders after the desktop is unlocked and their contextual permissions can be granted or denied. No sample values are shown as real data.
4. Confirm Focus Filter discovery/invocation with a full Xcode toolchain or on the unlocked desktop. This Command Line Tools installation does not provide the App Intents metadata processor.
5. Accept the documented platform differences: other apps' badge counts have no supported public reader; the initial Activity Monitor memory-pressure gauge is not exposed by the public change-event API; several AI quotas and Cursor account activity lack supported readers; session-only window previews require Screen Recording on macOS 14+.

The project remains **partial** until these checks are complete. See [the parity matrix](PARITY_MATRIX.md) for feature-level status.
