# MyDock

A local-first Dock for macOS with live widgets, saved Dock profiles and an optional replacement for the Apple Dock.

## Highlights

- **Custom Docks and profiles:** apps, files, folders, links, spacers and widgets on any screen edge. Save several Docks and switch from the menu bar, a global shortcut, a trackpad swipe or a Focus filter.
- **36 widget families:** clocks and timers, Calendar and Reminders, System Activity, Weather, markets, Stripe, Paddle and Shopify, AI usage, and everyday tools such as File Shelf and Text Snippets.
- **Replace or sit beside the Apple Dock:** replacement mode hides the Apple Dock while MyDock runs and restores its exact previous preferences when you leave the mode or quit.
- **Native Dock profiles:** save and apply Apple Dock layouts with a snapshot, verification and rollback.
- **Dock essentials:** running apps, minimized windows, a full app menu, drop-to-open and optional window previews on hover.
- **Backups and Dock packages:** versioned backups, layout-only exports and single-Dock packages that never carry credentials.
- **Private by design:** no account and no telemetry. Credentials stay in this Mac's Keychain, and each permission is requested only when you turn on the feature that needs it.

## Requirements

- **Runs on** macOS 13 or later. The Clear and Glass styles use Liquid Glass on macOS 26 and a frosted material on earlier systems.
- **Builds with** Swift 6 and the macOS 26 SDK, from Xcode 26 or Command Line Tools 26. `./BuildMyDock.sh` stops with a clear message on an older SDK.
- **Tests need** Swift Testing, which `./TestMyDock.sh` finds in either the Command Line Tools or the Xcode layout.

## Install and run

Quit any running MyDock first, then build and open the app:

```sh
./BuildMyDock.sh
open build/MyDock.app
```

The script builds a universal (Apple silicon and Intel) app at `build/MyDock.app` and refuses to replace a copy that is running. To keep MyDock, copy the app to `~/Applications` or `/Applications`.

Local builds are ad-hoc signed and not notarized. If Gatekeeper blocks the app you built, use Finder's Open command and approve it in System Settings → Privacy & Security. See [installation and signing](docs/INSTALLATION.md) and [uninstalling](docs/UNINSTALL.md). For Custom Dock clicks, menus and recovery, see [Dock interaction](docs/DOCK_INTERACTION.md); to report a problem, see [support](docs/SUPPORT.md).

## Using MyDock

- **Docks:** Manage Docks opens one window with Docks, Explore and Settings in the sidebar. Select and drag items directly in the Dock preview; changes save automatically and support Undo.
- **Explore:** nine starter Docks (Everyday, Deep focus, Creative space, Build & code, Commerce, Home office, Travel, AI workspace and System monitor). Preview one, swap or remove its apps, then create it. A new Dock goes live only when you choose **Activate** in the editor.
- **Add Item and ⌘K:** Add Item opens the searchable app and widget library, with a size pager for each widget. ⌘K searches commands, saved snippets, links and shelf files.
- **Settings:** General, Dock Setup, Appearance, Behavior, Shortcuts, Integrations and Permissions. Appearance offers five styles (Clear, Glass, Frosted, Solid and Midnight) for every Dock or for one Dock.

### Widgets

Every family in `WidgetRegistry.all`, grouped as Add Item shows them. `Tests/Tooling/test_readme_widgets.py` keeps this table in step with the registry.

| Category | Families |
|---|---|
| Everyday Tools | Calculator, Quick Checklist, File Shelf, Text Snippets, Quick Links, Unit Converter, Color Picker |
| Productivity | Calendar, Reminders, Focus Timer, Sticky Note, Shortcuts, App Folder |
| System | Battery, System Activity, Network Activity, Audio Output, AirDrop, Trash, Disk Space |
| Time | Clock, World Clock, Stopwatch, Countdown, Alarm, Time Progress |
| Personal | Now Playing, Weather, Hydration |
| Business | Stock, Watchlist, Stripe, Paddle, Shopify |
| AI | AI Limits, AI Activity |

Each widget has its own layout and icon style. A popout shows the reading first, with settings behind one disclosure. Widgets never show made-up values: without data they say why.

### Dock essentials and workspace tools

- **App tiles:** drop files or web addresses on an app tile to open them with that app. A running app's menu lists its windows, then Show in Finder, Hide/Show, Quit and Force Quit, which always asks first (Cancel is the default).
- **Recent apps** (off by default): up to three recently used apps that are not in the Dock. Runtime only; never saved or exported.
- **Window previews on hover** (off by default): hover a running app to list its windows. Titles need Accessibility; thumbnails also need Screen Recording, are captured only while the panel is open and stay in memory.
- **Audio Output widget:** switch the Mac's output device and its volume. Alerts follow the new device only when they already followed the old one.
- **Start Workspace:** opens a Dock's apps, folders, files and links in order. It never quits or closes anything, and switching to that Dock is a separate opt-in.
- **Portable Dock packages:** export one Dock; import always creates a new Dock and never carries credentials or account IDs.
- **Automatic switching** (off by default): simple app or time rules that switch between Custom Docks, with a manual override.
- **Next meeting:** Calendar shows the next relevant event, skipping events marked Free, with Join only for recognised https meeting links.
- **System Activity** can add Network and Storage detail sections to its popout (off by default; turn them on in the popout's settings).

## Privacy and permissions

| Access | Used for | When it is requested |
|---|---|---|
| Accessibility | Window lists, minimize and restore, window previews, app badges | Only when you turn on one of those features |
| Screen Recording | Window thumbnails and the optional desktop freeze during native Dock switches | Only when you turn on Minimized window thumbnails or the desktop freeze; hover previews never ask and show titles without it |
| Calendar, Reminders, Location | Events, reminders and current-location weather | When the widget first needs them; city search needs no Location |
| Desktop, Documents and Downloads folders | Storage scans in System Activity | Asked by macOS only when Scan Folders reads those folders |
| Automation | Music and Spotify in Now Playing; Finder for Empty Trash | When a player is queried, or after you confirm Empty Trash |
| Network | Weather, market and business data, GitHub Copilot usage, site icons | Only for the widget or action named; nothing about your Docks is uploaded |

Backups and Dock packages never contain credentials, and diagnostics exports are redacted. See the [permissions guide](docs/PERMISSIONS.md) and the [backup format](docs/BACKUP_FORMAT.md).

## Development

- The source of truth is `Sources/MyDock/`; the one canonical local app is `build/MyDock.app`. Quit MyDock, rebuild with `./BuildMyDock.sh` and reopen that same path after each change. Temporary validation bundles belong under `.build/visual-qa/`.
- Run the tests with `./TestMyDock.sh`; extra arguments go to `swift test`, for example `--filter <Suite>`. Tests use fake Dock preferences and never touch your Dock, Keychain or files; the live native-Dock and performance suites are explicit opt-ins.
- `./GenerateXcodeProject.sh` generates `MyDock.xcodeproj` (not checked in) for the Xcode build and Focus filter metadata; see [Xcode build](docs/XCODE_BUILD.md).
- The app icon is the checked-in `Resources/AppIcon.icns`; after changing `Tools/GenerateAppIcon.swift`, run `Scripts/RegenerateAppIcon.sh` and commit the result.
- VS Code's default build task runs the same build script; other tasks open the app and run the tests.
- Contributor rules for this repository are in [AGENTS.md](AGENTS.md).

## Status

Current build and test evidence is in [RELEASE_AUDIT.md](docs/RELEASE_AUDIT.md); open native and release acceptance is in [IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md).

## Documentation

The [documentation index](docs/README.md) lists every guide, from architecture and the backup format to the manual acceptance checks. Dated reports are in [docs/history](docs/history/README.md).

## Background and license

MyDock is an independent app written with native macOS frameworks. Its feature set was first planned against Dockset's public documentation; it uses no Dockset code, assets or branding. The [feature matrix](docs/reference/FEATURE_MATRIX.md) records that comparison.

No license has been chosen yet, so all rights are reserved by the author until a license file is added.
