# Permissions guide

MyDock's first-run profile editor and basic Custom Dock do not need optional privacy permissions. MyDock should request each permission only when the user opens a feature that requires it.

Fetching a link's site icon is an explicit action in the link editor. It makes a direct HTTPS request to the link host's `/favicon.ico` endpoint using an ephemeral session without cookies or credentials; it rejects local/private DNS results and cross-host redirects, limits response size, normalizes the image, and stores the small PNG in the profile. This does not request a macOS privacy permission.

When the Now Playing popout reads Spotify artwork, MyDock requests the selected cover from Spotify's `i.scdn.co` image host over HTTPS. The request uses an ephemeral session without cookies or credentials, rejects redirects, caps the image at 2 MB, and keeps only a small thumbnail in memory. Apple Music artwork comes from local Apple Events; missing artwork shows a symbol.

| Permission | Used for | Status |
|---|---|---|
| Accessibility | List window titles, restore/minimize app windows, optionally hide the focused app's window, and read badge labels exposed by Dock application items. | Requested only when enabling Show app badges, Show minimized windows, Show window previews, or Click focused app to minimize, or when choosing **Allow…** in the window preview panel. Hovering an app never prompts; without access the panel says so. Badge labels are best-effort on macOS 14+ and may not be exposed by every app. The Custom Dock remains usable when access is denied; a direct System Settings button is available. MyDock reads no notification contents. |
| Screen Recording | Optional one-frame-per-display freeze during native Dock profile switches, cached minimized-window thumbnails, and window preview thumbnails on macOS 14+. | Not requested by default. Window previews on hover never request it: without access the panel shows titles only, and **Show thumbnails…** opens the Permissions page so access is granted in System Settings. Hover thumbnails are captured only while the panel is open, kept in a small memory cache that drops them after 5 minutes and is cleared when the Dock hides or the setting is turned off, and never written to disk. It is requested only after enabling “Freeze desktop during Dock restart” or “Minimized window thumbnails.” Freeze images exist only until the Dock transaction/rollback completes. With Minimized window thumbnails on, uniquely matched thumbnails are stored in a private macOS Caches directory, created only when the first one is kept, for at most 24 hours, never backed up or uploaded, and cleared when the setting is disabled or access is revoked. Each belongs to one window in one run of its app, so none survives that app's relaunch. Hiding the Custom Dock clears active memory images but keeps the opted-in disk cache for a later reveal. Without permission, minimized windows use app icons. On macOS 13 both capture features remain unavailable. |
| Calendar | Read selected calendars and events; identify supported meeting links. | Requested only when an event-based Calendar popout opens. Date-only and compact previews do not request access. Date-only view remains available after denial. |
| Reminders | Read selected lists, add reminders, and mark them complete. | Requested only when the Reminders popout opens. The widget explains denial and does not access reminder data from compact previews before permission is granted. |
| Location | Use current location for weather; city search should work without it. | Requested only after choosing “Use Current Location” in the Weather widget. Manual city search does not request location access. |
| Automation / Apple Events | Read/control Apple Music or Spotify while a Now Playing tile or popout is visible; ask Finder to empty the Trash after confirmation. Empty Trash is Finder-wide through Automation, not limited to MyDock items or the home-folder Trash. | Player access is requested only after a visible Now Playing tile or popout queries a running player. Finder Apple Events are used only after choosing Empty Trash and confirming the destructive action; if Finder automation is denied, the Trash widget offers **Open Automation Settings**. |
| Login Items | Launch MyDock at login (Settings → General). | Registered with `SMAppService` when **Launch at login** is turned on; there is no privacy prompt. macOS may ask for approval in System Settings → General → Login Items, which MyDock opens from **Approve in Login Items…**. Turning the setting off unregisters it. |
| Desktop, Documents and Downloads folders | Measure file sizes for a System Activity storage scan. | Asked by macOS only when **Scan Folders** reads those folders. Nothing is uploaded or deleted. |
| Notifications | Hydration reminders, local alarm alerts, and Countdown completion alerts. | Hydration asks when Water reminders is enabled; turning it off cancels pending reminders. Alarms ask when adding or enabling; denial saves an alarm disabled. Countdown asks when started; denial leaves the countdown usable and explains that no completion alert can be delivered. Pause, reset, and removal cancel the scheduled countdown alert. |

The Permissions tab displays current Accessibility, Screen Recording, Notifications, Calendar, Reminders, Location, and Automation status, with System Settings links; statuses are read again whenever MyDock becomes active. The optional Apple Dock overlap setting reads only visible Dock process IDs and window bounds through Core Graphics; it does not capture window content or request Screen Recording. macOS does not expose a single readable Automation grant state, so MyDock describes the per-app prompt behavior. Denied hydration/alarm notifications leave the rest of MyDock usable and show a permission explanation. EventKit denial produces an in-widget explanation. Screen Recording is requested only from the optional native Dock switch effect or the Minimized window thumbnails setting; each feature falls back when access is unavailable.

## No permission, but acts on the system

These features need no privacy permission, so macOS shows no prompt. Each acts only after an explicit choice:

- **Audio Output** changes the Mac's default output device, volume and mute. When system alerts were following the previous output, they follow the new one; a separate alert device chosen in Sound settings is left alone.
- **Force Quit** in a running app's menu always asks first, with Cancel as the default button.
- **Dropping files or web addresses on an app tile** opens them with that app.
- **Color Picker** uses the system color sampler (`NSColorSampler`), which needs no Screen Recording access.

## Network destinations

MyDock contacts these hosts only for the feature named, and sends no profile content, notes or usage records. Credentials stay in this Mac's Keychain and are never part of backups or Dock packages.

| Host | When | Credential |
|---|---|---|
| The link's own host (`/favicon.ico`) | **Fetch site icon** in the link editor | None |
| `i.scdn.co` | Now Playing shows Spotify artwork | None |
| `geocoding-api.open-meteo.com`, `api.open-meteo.com` | Weather city search and forecasts | None |
| `www.alphavantage.co` | Stock and Watchlist refresh | Alpha Vantage API key |
| `api.stripe.com` | Stripe widget refresh and connection tests | Restricted API key |
| `api.paddle.com` (`sandbox-api.paddle.com` for sandbox keys) | Paddle widget refresh and connection tests | API key with Metrics Read |
| `<store>.myshopify.com` | Shopify token exchange and order queries | Client secret and access token |
| `api.github.com` | GitHub Copilot usage (opt-in), and **Check for Updates** when a release repository is configured | Fine-grained token for Copilot; none for updates |

Codex and Claude Code limits and AI Activity are read from local tools and files; MyDock itself makes no network request for them.

## Connected-service and Focus notes

- Paddle requires an API key with the Metrics Read permission; keys without it cannot load Paddle metrics. Keys stay in the Keychain.
- Focus filters require the Xcode-built app, which carries `Metadata.appintents`; the script-built `build/MyDock.app` does not expose the filter.

## Current app bundle usage strings

The generated Info.plist includes full-access and compatibility usage descriptions for Calendar and Reminders, plus Location, Apple Events and Desktop, Documents and Downloads folder descriptions. The folder descriptions appear only when Scan Folders reads those folders. Calendar and Reminders access is requested only from the corresponding popout. Location access is requested only from the Weather current-location action. Music/Spotify automation is used only while a Now Playing tile or popout is visible, and Finder automation is invoked only after the user confirms Empty Trash.
