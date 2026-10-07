# Dock clicks, recovery and displays

These contracts describe the current source. Native window, permission, Spaces and display acceptance remains open.

## Application clicks

An ordinary app click asks macOS to open the saved installed application URL. MyDock preserves an existing selected copy; bundle-identifier lookup is a relocation fallback when the saved path is unavailable.

| Current app state | Ordinary click |
| --- | --- |
| Not running / no windows | Request opening the selected application. The app decides whether to create a window. |
| One visible window | Request opening/activating that application; the app and macOS decide window focus. |
| Multiple windows | Activate/open the application. A click does not choose a particular window. Use the **Windows…** context-menu command, which discovers the app's windows and lists them for selection. |
| Minimized windows | The app decides ordinary-open behavior. Use the specific window action to request restoration through Accessibility. |
| Files or web addresses dropped on the tile | Open them with that application. Only existing local files and http(s) addresses count; a drop with nothing openable is refused rather than launching the app. |

If **Click focused app to minimize** is enabled, a click first attempts to minimize the focused window of the exact running copy. If that attempt cannot succeed, MyDock makes the ordinary open request. This behavior needs Accessibility; basic opening does not. Multiple processes belonging to one installed copy can be ambiguous, and MyDock refuses identity-dependent actions rather than choosing arbitrarily.

A running app's context menu follows the macOS Dock order: its windows (listed inline when Accessibility is trusted and discovery answers in time, otherwise **Windows…**), **Close Window…**, **Show in Finder**, **Hide** or **Show**, **Quit** and **Force Quit**. The menu discovers windows on demand, independently of optional background minimized-window monitoring. Window actions revalidate the process and sampled native accessibility object. A stale window or another installed copy is not substituted. **Close Window…** lists windows and requests normal closing of the chosen one; **Quit** requests normal application termination, and the app can show an unsaved-document dialog and cancel either request. **Force Quit** always shows a confirmation whose default button is Cancel, revalidates the app after confirmation and then terminates it. MyDock never treats a request as proof of exit.

## Window previews on hover

Off by default (Settings → Behavior → Show window previews). Hovering a running app tile for 0.5 s opens a panel listing its windows; moving to another running app swaps the content, and leaving both the tile and the panel closes it after a short grace. Escape, a click elsewhere, the Dock hiding or the setting turning off also close it. Nothing runs while idle. Without Accessibility the panel says so and offers **Allow…**; hovering never prompts. Thumbnails need Screen Recording on macOS 14 or later: without it the panel shows titles and **Show thumbnails…**, which opens the Permissions page. Thumbnails are captured only while the panel is open and stay in memory.

## Widgets, files and folders

A widget click toggles its tab in the shared popout. Clicking another widget selects its tab. The shared draft behavior protects saved-object and recoverable composition input; keyboard return focus and complete dismissal behavior still need native acceptance. Folder clicks open in Finder; a long press opens supported folder contents. Files and links use the system open request. **Locate…** repairs an unavailable reference; removing a reference does not delete its original file.

## Access with the manager closed

The menu bar item remains the entry point for **Manage Docks…**, **Settings…**, profile selection and **Quit MyDock**. Dock context menus also provide **Settings…**. These commands do not require the manager window to be open.

Settings shows **Restore Previous Dock** when a native layout transaction reports recovery required. That repairs an interrupted native-layout transaction. Replacement-mode visibility restoration is separate: normal quit or leaving replacement mode restores the saved visibility preferences. If restoration fails, quitting is cancelled and its recovery record remains for retry. See [removal instructions](UNINSTALL.md). A successful previous Apply is not automatically reversed on quit.

## Replacement ownership and display fallback

Replacement mode journals the original Apple Dock visibility keys before changing them, verifies the requested change and retains recovery information if rollback/restoration fails. When restoring, it writes the originally captured values for the owned keys. It does not negotiate a conflict with another Dock utility or preserve an external edit to those keys made during the replacement session. Avoid running competing utilities that control the same visibility settings. No new ownership policy or mode default is implied by this documentation.

If the selected display disappears, the custom Dock falls back to the main display (or the first available display) without changing the stored preferred display ID. Reconnecting that display returns placement to it. If no screen exists, the Dock and its reveal handle are hidden and monitoring stops. Menus and resizing retain the Dock; system overview and configured Apple Dock overlap suppression take precedence over ordinary reveal. Hidden-edge reveal uses a 350 ms dwell with 500 ms presentation sampling. Dwell completion samples overview and overlap again before revealing, with the same menu/resize retention precedence.

Multi-display reconnection, fullscreen, Mission Control, Spaces, native focus, unsaved dialogs, pointer acquisition and interrupted motion require controlled desktop acceptance. Public Workspace and Accessibility requests do not establish complete Apple Dock parity.
