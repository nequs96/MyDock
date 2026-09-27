# MyDock architecture

## Current structure

| Area | Responsibility |
|---|---|
| `Sources/MyDock/Core` | Central product name and bundle identifier. |
| `Sources/MyDock/Models` | Codable profile, item, spacer, setup, widget-catalogue types, and searchable system time-zone city catalog. |
| `Sources/MyDock/Persistence` | Main-actor profile store; atomic, versioned JSON in Application Support. |
| `Sources/MyDock/DockManagement` | Native Dock preference adapter, serializer, serialized transaction gate, layout rollback journal, Apple Dock auto-hide recovery record, and Custom Dock panel. |
| `Sources/MyDock/Focus` | App Intents Focus Filter profile entity/query and profile activation bridge. |
| `Sources/MyDock/SystemServices` | Launch Services, running-app filtering, battery, local notifications, folder enumeration, global shortcuts, EventKit, market/business integrations and Keychain credentials, Weather/location, host CPU/memory/network/system readers, Codex rate limits, and local AI activity counters. |
| `Sources/MyDock/Backup` | Versioned portable profile archive with import validation and missing-reference reporting. |
| `Sources/MyDock/UI` | Menu-bar actions, Dock Manager, settings, and About surface. |
| `Tests/MyDockTests` | Profile persistence, spacer identity, backup, native Dock serializer/transaction fixture tests. |

## State ownership

Profiles and app-wide settings are encoded in `~/Library/Application Support/MyDock/state.json`. Writes are atomic. Before opening this store or starting a Dock controller, production launch checks for an existing MyDock process and acquires an exclusive `instance.lock` in the same directory. A duplicate exits without running Dock restoration. The root model carries a schema version. Invalid state files are preserved under a recovery filename before MyDock starts with an empty store; state from a newer schema is left untouched and writes are disabled. Custom Dock edge, scale, display ID, profile color, material, and desktop placement are saved here; if the selected display disappears, the controller uses the main display and watches for display changes. The Alpha Vantage API key is stored as a device-only Keychain generic-password item; it is not part of profile state or portable backups.

Native Dock profile application is isolated behind `DockPreferencesBackend`, `DockRelaunching`, and `DockTransactionJournal`. The production adapter touches only the `com.apple.dock` `persistent-apps` value. It saves the exact prior property list locally, applies, restarts Dock, rereads, verifies ordered app/spacer identity, and rolls back on failure. A shared serialized gate also protects Apple Dock auto-hide changes from overlapping native-profile restarts. Custom-main mode saves a versioned recovery record before setting `com.apple.dock` `autohide`, restores the exact prior explicit/absent value when leaving or quitting, and retries recovery on next launch. Tests inject fake backends and never write to the real Dock.

The current native Dock preference representation is an undocumented macOS detail. It is based on the public Dockset behavior and read-only shape inspection of this Mac's Dock preferences. Automated tests use fixture stores and never write to real Dock preferences.

## UI/runtime

The app uses a native `NSStatusItem`. First launch presents Manage Docks while setup is incomplete; after finishing setup it changes to accessory activation policy. The Custom Dock is a borderless, non-activating `NSPanel` backed by SwiftUI content. The Dock Manager is a normal native window hosting SwiftUI. `AccessibilityDisplayState` observes NSWorkspace display-option changes and applies Reduce Transparency, Increase Contrast, and Reduce Motion to the Dock; Weather also avoids translucent surfaces when requested. `WindowAccessibilityMonitor` lists/restores minimized windows only while the feature is enabled and the Dock is visible, and uses Accessibility APIs to minimize the focused app when requested. With the optional Screen Recording setting, `WindowPreviewCapturer` samples uniquely matched visible windows into a bounded, in-memory preview cache that is discarded when the Dock hides.

Widget names and compact metadata are centralized in `WidgetRegistry`; rendering uses `DockWidgetProvider` implementations. All 26 requested widget families plus the separately requested Trash tile have provider implementations. Shopify uses a same-organization client-credentials grant and read_orders-only GraphQL query; Stripe and Paddle use read-only APIs and keep credentials in Keychain. AI Limits reads Codex app-server quota data; AI Activity parses only usage fields from local Codex, Claude Code, and Grok records. It does not retain prompt/tool content. Other provider quota/activity sources remain unavailable where no supported reader is present. Widget snapshots may be backed up as profile data, while credentials remain device-local and excluded. Local weather, EventKit, Shortcuts, Now Playing, AirDrop, Trash, battery, window, and system metrics behavior follows the feature matrix. `RefreshScheduler` coalesces transient widget and system polling into one cancellable timer, pauses scheduled work while the Custom Dock is hidden, and leaves static views idle.

## Build and checks

- `./BuildMyDock.sh` compiles macOS 13+ arm64 and x86_64 Release slices, combines them into a universal executable, and creates an ad-hoc signed `build/MyDock.app`.
- `./TestMyDock.sh` currently runs 112 Swift Testing checks for profile persistence/recovery, single-instance locking, Dock transaction and auto-hide recovery, freeze-overlay cleanup, Focus off behavior, widget configuration and backup, AI local-usage parsers/quota windows, Shopify/Stripe/Paddle/market fixtures, timer/hydration/calendar/reminder/weather/shortcut/system/network/window policies, Dock Manager selection/drafts, locale-aware Clock formatting, Trash tile geometry, and privacy/security boundaries. Fake adapters keep tests away from real Dock preferences and external accounts.
- `xcodebuild` and an Xcode project are not available in the current environment because only Command Line Tools are installed.

## Known limitations

- Live checks cover a DEBUG-only isolated preview of all onboarding steps, the Manager, Settings, widget library, bottom/left/right Dock layouts, light/dark appearance, overflow navigation, Clock popouts, and Manager add/save/discard, rename, selection, and group movement. Earlier app builds also verified the Settings/Permissions route and Accessibility deep link. Shift-click range selection, profile persistence across app relaunch, and most desktop-only behavior still need acceptance.
- Real Dock apply/rollback has not been run on the user's actual Dock.
- Custom Dock auto-hide, desktop-level placement, Apple Dock auto-hide recovery, Focus Filter registration, reveal handle, folder browsing, App Folder, per-profile shortcuts, trackpad profile switching, fullscreen edge dwell, optional ScreenCaptureKit desktop freeze, and optional minimized-window preview cache compile and have fixture coverage where applicable, but require desktop acceptance. Overflow navigation and Clock popout placement were visually checked in the isolated preview; real-device scroll, popout, and window behavior remain unverified. App badges and Mission Control polish remain. Apple Dock overlap detection and hide behavior need desktop verification. Live service credentials, the Focus Settings flow, multi-display behavior, and most widget actions remain unverified.
- The production app has only been launched locally; signing/notarization and installation into `/Applications` are not configured.
