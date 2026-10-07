# MyDock macOS acceptance tests

Manual checks for a Mac, grouped by area. Nothing here is marked passed: record each result with its date in [RELEASE_AUDIT.md](RELEASE_AUDIT.md), which holds the current build and test evidence. The native acceptance procedures H1–H9 are defined in [the execution ledger](history/EXECUTION_LEDGER_2026-10-03.md), the Visual QA UI scheme in [XCODE_BUILD.md](XCODE_BUILD.md), and earlier dated results in [the acceptance evidence through 1 October 2026](history/ACCEPTANCE_EVIDENCE_THROUGH_2026-10-01.md).

## Core vertical slice

1. Launch MyDock and confirm the setup wizard presents the three setup modes.
2. Import the current Dock or leave it empty, choose starter widgets, select edge/display, and finish setup; confirm the created profiles in Manage Docks.
3. Add an installed application, save, and confirm its icon appears in both editor and Custom Dock.
4. Click the item and confirm the app launches; click again while active and confirm normal activation.
5. Enable Show running apps, launch and quit an unpinned app, and verify the transient item appears/disappears; choose Keep in Dock and verify it remains pinned.
6. Change a native and Custom Dock profile color, then quit and relaunch MyDock; confirm profile, ordering, color, and item path restore. Confirm only the Custom Dock surface is tinted.
7. Add a second profile and switch from menu bar; confirm the first profile remains intact. Right-click the Custom Dock background, an app/widget tile, and a minimized-window tile; use Switch Dock to change a Custom profile and, after the approved real Dock test begins, a native profile. Turn on Show active Dock names in menu bar, check Native, Custom-main, and Both modes, and verify long names truncate beside the icon while the full names remain in its tooltip. Turn it off and confirm the icon returns to compact size.
8. Record distinct shortcuts for two profiles, trigger them from another app, and verify conflict feedback and clearing.
9. Add a folder with nested folders and files; browse, open a file, reveal it in Finder, and close with Escape.
10. Add a Calendar widget. Confirm Date layout works without prompting; switch to an event layout and grant or deny access. Select calendars, toggle all-day events, refresh, and verify ongoing/soon meetings remain ahead of all-day entries. Edit an event in Calendar while the compact tile is visible; confirm it refreshes without opening the popout. Rapidly change selected calendars, then revoke access in System Settings and return to MyDock; old event titles must clear and the error state must appear. Repeat after sleep/wake. Confirm Zoom, Google Meet, and Teams Join links open.
11. On macOS 14 or later, enable app badges and grant Accessibility access. Confirm badge labels appear for representative pinned and running apps, disappear when labels clear or access is revoked, and stop refreshing while the Custom Dock is hidden. Confirm MyDock does not read notification contents.
12. Add a Reminders widget. Grant or deny access on first popout open; choose all lists or one list, add a reminder, complete it, undo the last completion, and verify changes in the Reminders app. Edit a reminder externally while its compact tile is visible; confirm the count refreshes. Rapidly switch lists and revoke access in System Settings; old titles and counts must clear, and a failed fetch must show Unavailable rather than a successful zero. Repeat after sleep/wake.
13. Add System Activity; compare aggregate/per-core CPU, memory breakdown and swap with Activity Monitor, check thermal state, 1/5/15-minute load averages, uptime, and startup-volume capacity. Check that pressure says Awaiting event until a public pressure-change notification arrives rather than inventing a current gauge. Hide the Custom Dock and verify sampling pauses. Scan Home, Applications, and Library; confirm their totals remain separate because Home includes Library, progress advances, and the scan continues after closing/reopening the popout. Choose a temporary folder and verify largest-file sorting, Finder reveal, Cancel, Scan Again, and partial/capped disclosure. In the popout's settings, turn the Network and Storage sections on and off: each appears below CPU and memory, samples only while the popout is open (close it and confirm the rates stop updating), and Storage replaces the startup-volume summary rather than adding a second one. Add Network Activity and Disk Space to the same Dock, open each popout and use **Show in System Activity** to open the System Activity popout.
14. Add a Network Activity widget; compare aggregate rates and interface addresses with macOS Network settings/Activity Monitor, then auto-hide the Dock and verify its sampling stops.
15. Add one one-time alarm and one weekly alarm; grant/deny Notifications access, verify disabled fallback on denial, remove one alarm, and verify OS alert delivery across sleep/wake. Relaunch after the one-time alert and confirm the tile reconciles it as disabled. Start a Countdown, verify its completion notification across app quit/sleep, then pause/reset/remove another countdown and confirm no stale alert arrives.
16. Add a Weather widget, search for a city without granting Location, choose Current/Conditions/Hourly layout and °C/°F, and verify the 1–6 hour setting. Change the query while results are shown and confirm old cities disappear; repeat the same search rapidly and confirm the latest response wins. Start search or Current Location, then cancel/change location or remove the widget before completion and confirm no stale selection or draft returns. Dismiss the popout while the Location permission prompt is pending, reopen it, and confirm a second Current Location attempt can start. Confirm the translucent/themed backgrounds, manual refresh, ten-minute refresh while open, stale forecast fallback, and backup restoration. Only press “Use Current Location” to exercise the contextual location prompt.
17. Add an AirDrop widget; drop files and an HTTPS link, then choose files from the panel. Confirm the macOS sharing picker receives the selected items, the user can select AirDrop when available, and canceling the picker leaves the app usable.
18. Add a Trash widget, compare its count with the home Trash folder, open Trash, and confirm the Empty action first presents a destructive confirmation. Deny Finder Automation and verify the error leaves Trash untouched; allow it in a disposable test account and verify the action.
19. Add Now Playing and enable both Apple Music and Spotify. Verify each open/closed status, active playback arbitration, optional controls, Mini/Full compact layouts, long artist/album accessibility, permission-denied recovery, and saved configuration after relaunch. Confirm hide-when-closed considers every enabled player and polling stops when the Dock hides or the widget is removed.
20. Enable Show minimized windows and Click focused app to minimize; grant or deny Accessibility access. Verify focused-app clicks minimize only when that app has the frontmost focused window, other-app clicks activate normally, minimized tiles list window titles and restore windows on their existing Space, per-app window menus work, the panel stops polling when hidden, and denial falls back without disabling app launches. On macOS 14 or later, opt in to Minimized window thumbnails and grant Screen Recording. Leave a uniquely titled window visible for a refresh, then minimize it and verify its tile shows a cached thumbnail. Check duplicate-titled and uncapturable windows use the app icon, hiding clears active previews, and a matching unique minimized window can reuse its local preview after relaunch. Confirm cache files have restrictive permissions, expire after 24 hours, stay under the size/count caps, and are deleted when caching is disabled. Revoke Screen Recording and confirm cached images clear while window restore still works with app-icon tiles; macOS 13 must leave preview capture unavailable.
21. Add Stock and Watchlist, then save an Alpha Vantage key under Settings → Integrations. Search a ticker, change the query while matches are visible, and confirm old results and old errors disappear; repeat rapid searches and selections with delayed responses. Add a ticker to both widgets, edit display names, reorder Watchlist tabs, open Yahoo Finance links, verify name/currency and that switching currency for the same Stock ticker clears an old quote, daily chart ranges, hover/drag and keyboard-accessible crosshair values, volume, selected-symbol refresh cadence, stale-data messaging, request-limit handling, and settings after restart. Confirm the API key is absent from backups and remove it from Keychain afterward. Real-time US quotes require a provider plan that permits them; MyDock currently presents daily series.
22. Add a Stripe widget, open its popout, enter a restricted `rk_test_…` key with only Core → Balance Read and Billing → Subscriptions Read, and connect a named/colorized account. Verify account selection, each metric and currency, Today/7/30/90-day local-time periods, refunds/reversals/fee handling, active and past-due fixed-price MRR, five-minute refresh, manual refresh, stale-data preservation, and disconnect. Confirm denied permissions show a useful error, the key is absent from profile backups, and remove the connection after use. Stripe test-mode credentials are required; live account behavior has not been verified.
23. Add a Paddle widget, open its popout and connect a named/colorized Billing account with a current sandbox key that has only Metrics → Read. Verify rejected legacy/Classic/client-side keys, live/sandbox URL selection, Net Revenue/MRR/ARR/active subscribers, chart toggle and UTC day ranges, reported primary currency, five-minute refresh, stale-data preservation, expiry/permission errors, disconnect, and key exclusion from profile backups.
24. With delayed test transports for Stripe, Paddle, and Shopify, start Connect, remove the originating widget before validation completes, then release the response. Confirm no connection or credential is saved. For Shopify, delay a snapshot, disconnect or remove the widget, then release the response and confirm the credential is not rewritten.
25. Select the same saved Stripe, Paddle, or Shopify account in widgets on two profiles, then disconnect it from one widget. Confirm both widgets become disconnected, their saved snapshots clear, an unrelated connection stays selected, and the result survives relaunch.

## Native Dock safety (fixture-backed automated coverage first)

1. Decode fixture layouts containing multiple apps, a missing app, and both spacer types.
2. Apply to an isolated test preference store and verify exact round-trip order/kinds.
3. Simulate Dock restart failure and interrupted transaction; confirm rollback and recovery.
4. Rapidly request A → B → C; confirm final state is C and no older request overwrites it.
5. In the isolated backend, enable Automatically save Dock changes and confirm an external pinned-app or spacer edit updates only the selected profile without writing Dock preferences. Confirm an app-driven switch, unsupported tile, and disabled setting do not overwrite that profile. On the unlocked desktop, check the same setting with a reversible manual Dock edit.
6. Exercise real Dock mutation only after separate user approval, using the snapshot and restore procedure in the [real Apple Dock test](#real-apple-dock-test) below.

### Real Apple Dock test

This test changes the current user's Apple Dock layout and restarts Dock. Run it only after explicit approval, with the Mac unlocked and the user present. Automated tests use fake preferences and do not replace this plan.

#### Before applying a profile

1. Close MyDock and confirm no other Dock customization is in progress.
2. In MyDock, use **Create from Current Dock** to save a native profile named `Before MyDock Dock Test`. Save it and inspect the captured app/spacer order.
3. Record every `com.apple.dock` value MyDock may change: `persistent-apps`, plus the visibility keys Custom-main mode owns, `autohide`, `autohide-delay` and `no-bouncing`. Note which keys are absent: `defaults read com.apple.dock autohide-delay` prints an error for an absent key. Keep that snapshot until restoration is verified.
4. Create a temporary native profile with a few already-installed apps, one regular spacer, and one small spacer. Do not add, remove, or move apps outside this temporary profile.

#### Exercise native apply and restore

1. Apply the temporary profile once. Dock will restart and its pinned items/spacers will change temporarily.
2. Confirm the visible order and both spacer sizes. Launch one app from the Dock, then return to MyDock.
3. Apply `Before MyDock Dock Test` to restore the original Dock layout.
4. Compare the resulting `persistent-apps` value and visible Dock order with the pre-test snapshot. Stop if they differ.

#### Exercise Custom-main auto-hide recovery

1. Select a temporary Custom Dock profile and enable Custom-main mode.
2. Confirm Apple's Dock auto-hides while MyDock is active.
3. Turn Custom-main mode off. Confirm `autohide`, `autohide-delay` and `no-bouncing` match the snapshot, including keys that were absent.
4. If approved as part of the same run, repeat with MyDock quitting while Custom-main is active; relaunch MyDock and confirm its recovery record restores all three values.

#### Rollback

- If an apply fails, let MyDock complete its transactional rollback and compare the preference snapshot before continuing.
- If the Dock layout is still different, reapply `Before MyDock Dock Test`. If that does not restore the exact `persistent-apps` value, restore only the saved Dock preference values and restart Dock while MyDock is closed.
- If `autohide`, `autohide-delay` or `no-bouncing` still differ, quit MyDock and restore each saved value (for example `defaults write com.apple.dock autohide-delay -float 0.5`). Remove a key that was originally absent (`defaults delete com.apple.dock autohide-delay`) rather than writing a value, then run `killall Dock`. Restoring only `autohide` leaves a 24-hour reveal delay, so an auto-hidden Dock would never reappear.
- Stop further tests and keep the snapshot if any setting cannot be restored exactly.

#### Approval scope

Approval should cover the temporary profile apply/reapply and, separately, the Custom-main auto-hide/quit recovery steps. No live provider credentials, screen capture, or changes to unrelated Dock preferences are part of this test.

## Display and window behavior

1. Test one display, then two displays with distinct scale factors.
2. Disconnect/reconnect the selected display. While disconnected, verify the Dock moves to the main display, Settings keeps the unavailable selection and explains the fallback, and choosing Main display makes that choice permanent. Leave the unavailable display selected in a second run and confirm the Dock returns there on reconnection. The diagnostic export should contain fixed display-fallback and display-restored codes without display names or IDs.
3. Exercise left, bottom, and right placement, display selection, Compact/Balanced/Comfortable density presets, size and spacing sliders, drag-resize grip, appearance Reset, auto-hide, visible handle, Apple Dock overlap toggle, and desktop mode. On a bottom Dock, right-click each widget family and choose every option in **Widget layout**; confirm the tile width and overflow navigation update, and each choice survives relaunch and backup restore. Confirm side Docks stay compact. Verify each density preset changes the tile geometry, manual adjustment displays Custom, Reset restores the default geometry, and compact tiles remain readable on all three edges. Confirm overflow jump chevrons appear only when content exceeds the viewport and jump to each end. With the overlap toggle enabled, reveal the Apple Dock over MyDock and confirm MyDock and its handle stay hidden until it retracts. On a trackpad, swipe perpendicular to the Dock to switch profiles; verify ordinary mouse-wheel input only scrolls overflowing items.
4. Test fullscreen reveal, Mission Control hiding, Space changes, sleep/wake, and primary-display changes.
5. Verify the Custom Dock does not jump to another display after profile switch.

## Editing, items, and widgets

1. Add and drag items directly in the Dock workspace; Command-click entries, Shift-click a range, move the selected group with ⌘←/⌘→, and verify Delete and native Undo. Confirm edits autosave, survive navigation/restart, and retain a failed draft with Retry. Conflicting drafts must still offer review before switching profiles.
2. Verify spacer kinds survive save/reload; add folder/file/link items, customize a folder's local color/letter/number and reset it, inspect Quick Look image/video thumbnails and icon fallback, open items, and use Reveal in Finder/Open Containing Folder. Change Dock size from minimum to maximum while the same file tile remains visible; its thumbnail should refresh at the larger resolution instead of staying blurry. Move a saved local item and confirm the missing-target warning appears. Check that HTTP(S) links validate before launch. Edit a saved link's name, destination, and SF Symbol; fetch a favicon from a public HTTPS site and confirm it remains after relaunch/backup import. Verify HTTP origins, embedded credentials, IP literals, local hosts, cross-host redirects, oversized responses, and malformed images fall back without saving an icon.
3. Verify Clock and multi-city World Clock search/day offsets, Focus Timer, Stopwatch, Countdown and its completion notification, Time Progress, Sticky Note, Hydration history/undo, Show older drinks, and its notification permission flow, Stock, and Watchlist. For Stopwatch, check pause/resume/reset, a quit/relaunch, and sleep/wake; verify a manual wall-clock change does not alter elapsed time during the same boot. For Alarm, remove or disable one while notification permission is pending and confirm no alert survives; verify a complete repeating alarm remains enabled after relaunch. For Sticky Note, inspect every background in light and dark appearance, including text selection and caret visibility on black and white. Confirm unsupported provider capabilities are explicitly labeled unavailable and never display fabricated values.
4. Move an App Folder application, confirm the missing warning, and use Replace to select its new path. Verify each widget's popout toggle, Configure/Duplicate/Remove actions, ⌘W, Escape, screen-edge placement, and persistence. In a long Custom Dock profile, add a widget near the end of the picker and confirm the picker closes, the new tile is selected for configuration, then verify autosave and the on-screen Dock. For Sticky Note, type text and quit before its 300 ms save delay, then relaunch and confirm the latest text appears. Make the profile store unwritable, edit the note, and verify quit offers Retry Save, Cancel Quit, and Quit Without Saving; restore write access and verify Retry Save persists the edit.
5. Verify permission denial and offline states retain usable UI without fake values.
6. Verify closing Dock Manager stops preview refresh and hidden Dock reduces update activity.
7. In Countdown, switch from Duration to Date & Time, set a future target, and confirm the compact and expanded values change across minute and day boundaries. Change the target rapidly while the notification permission prompt is open; only the newest target may notify. Verify the target persists after relaunch and backup import, the deadline reaches Complete, Clear Target cancels a pending alert, and an imported or duplicated target requires setting it again before this Mac schedules an alert. Switch back to Duration and confirm Start/Pause/Reset still work.

## Backup and privacy

1. Export profiles with widget settings, inspect archive schema, and confirm no keys, tokens, permissions, machine IDs, or shortcuts are present.
2. Import into a clean store; confirm import adds profiles, does not auto-activate, and reports missing App Folder member paths alongside top-level missing items.
3. Import the same backup twice and confirm duplicate profiles are allowed.
4. Select a JSON file larger than 25 MiB and confirm import reports the size limit promptly without changing saved profiles. Select a directory or other nonregular path if the file picker permits it; import must reject it. Restore a valid archive below the limit through the file-read path.
5. Search logs for secret values and personal note text; expect none. Inspect the exported archive: saved Sticky Note text and widget snapshots should be present so they restore, while credentials and other secret values must be absent. Confirm Settings discloses this before export.
6. In Settings → General, choose Export Diagnostics, save the JSON, and inspect its version, aggregate counts, save status, appearance choices, and recent event codes. Create a disposable profile and note with distinctive text and a file path; none of that content, profile/item IDs, URLs, credentials, calendar titles, or images may appear in the diagnostic export. Exercise a failed save and a failed native Dock fixture path, then confirm only typed failure codes appear. Verify the export remains usable in a narrow Settings window and delete the disposable report afterward.

## Accessibility

1. Verify VoiceOver labels and keyboard navigation for menu bar, manager, settings, picker, and popouts.
2. On an acceptance account, select each Appearance style (Clear, Glass, Frosted, Solid, Midnight); on macOS 13–15 verify the frosted fallback for the Liquid Glass styles. Enable Reduce Motion, Reduce Transparency and Increase Contrast separately and together. Verify shared Dock/control/widget boundaries, opaque surfaces and interrupted profile transformations in dark and light modes. The DEBUG-only 18-variant render matrix covers app-owned drawing without changing system settings; it does not replace this real preference/VoiceOver check.
3. Enable Dock magnification and confirm enlargement stays localized around the pointer, app icons grow more than widgets, and Reduce Motion suppresses the effect.
## Shopify

- Create a Shopify Dev Dashboard app, install it on a store in the same organization, and grant only `read_orders`.
- Open the widget's popout, then connect with the store's `myshopify.com` domain, client ID, and client secret. Confirm the account name, color, shop timezone, and currency appear.
- Verify Today, Last 7 days, Month to date, and Last 30 days around a daylight-saving transition against the store's order list.
- Compare order value with current totals for paid, unpaid, partially returned, fully returned, test, and canceled orders; test/canceled orders must be excluded, while unpaid/fully returned orders remain counted.
- Compare AOV, daily chart, product current-unit counts, and available first/last-visit traffic sources. Confirm no customer or referral URLs are retained.
- Verify manual and five-minute refresh, saved last-successful data on network/API errors, Keychain removal on disconnect, and that profile backup contains no app secret/access token.
- With an injected fixture over 10,000 records, confirm refresh displays an error and never publishes partial totals.
- Live store click-through remains blocked until a Shopify store/app credential is available.

## AI Limits and AI Activity

- Add AI Limits, select providers and ordering, choose Numbers/Rings/Bars and Remaining/Used, and select a compact provider. Scroll its popout from the controls to the final provider guidance on a short display. Confirm each provider-reported window, percentage, reset time, and unavailable/unlimited state. Codex reads from the local app-server; no prompts, tasks, or model requests should be started by refresh.
- For Claude Code Pro/Max, choose **Find Account**, then **Enable Limits**. Run Claude Code once and verify the 5-hour and 7-day windows appear, an existing terminal status line still shows, and a `settings.before-mydock-*.json` backup exists. Confirm a sample older than 30 minutes becomes unavailable. Afterwards restore `statusLine` from that backup and remove the local snapshot. See [the setup steps](CLAUDE_CODE_LIMITS.md).
- Add AI Activity and check Codex and Claude Code Today/L7/L30/MTD totals, chart styles, sessions, token/request counts, cached input, and tool calls against local usage records. Confirm the view states that it excludes provider usage outside the local CLI/session logs.
- Scroll the AI Activity popout to its final explanation after choosing the longest available provider/date-range content.
- Check Grok activity is labeled estimated and partial, and that an updated old session is grouped by file-update day. Confirm Cursor/Gemini CLI/Antigravity remain explicitly unavailable without fabricated values. If testing Copilot, use a personal account, a fine-grained token with Plan: read, and an allowance matching the GitHub billing page; verify organization-billed usage is excluded and the secret stays out of backups.
- Confirm changing providers/date ranges refreshes the correct snapshot, popout close stops its refresh loop, and backups contain only calculated counters and configuration, never prompts, tool output, or credentials.

## Focus Filters and replacement Dock

- In System Settings → Focus, add MyDock to one Focus, select a Custom profile, activate the Focus, and confirm it applies without quitting apps. Turn the Focus off and confirm the applied profile remains selected.
- Repeat with a native profile and confirm the transactional Dock writer applies it. Remove a selected profile and confirm the Focus filter reports a clear stale-profile state on the next activation.
- Record the Apple Dock's original `autohide`, `autohide-delay` and `no-bouncing` values, including absent keys. Select Replace macOS Dock and confirm Apple Dock stays hidden when the pointer reaches its screen edge. Switch to macOS Dock + Custom Dock or quit MyDock and confirm all three original values return. Relaunch in replacement mode and check the suppression applies again.
- Simulate an interrupted replacement session using the fake preferences tests. On next launch, confirm MyDock preserves the recorded prior state while replacement remains enabled, and restores it when leaving the mode. Check migration from the previous auto-hide-only recovery record, and rollback after a failed Dock restart.
- Drag the bottom Dock's resize grip up to enlarge and down to reduce. On the left edge, drag right to enlarge; on the right edge, drag left. Check size limits, double-click reset, VoiceOver increment/decrement and original-size restoration after the check.
- In Add Item, open a widget's detail and page through its sizes with the size pager. Confirm the preview and the widget **Add Widget** creates match the selected size, and hover/press do not change tile geometry. Check search clearing, category scroll reset and the window's minimum size.

## Dock essentials and workspace tools

1. With a fresh profile, confirm Show recent apps, Show window previews, automatic switching and the System Activity Network and Storage sections are all off.
2. Drop Finder files and a web address on an app tile; confirm they open with that app, and that a drop with nothing openable is refused.
3. Open a running app's menu: windows, Show in Finder, Hide/Show, Quit, Force Quit. Choose Force Quit, press Return and confirm Cancel is the default and nothing quits; repeat and confirm Force Quit ends the app.
4. Turn on Show window previews. Without Accessibility, confirm the panel offers to allow it and hovering never prompts; with Accessibility, confirm titles after the show delay and that Escape or a click elsewhere closes it. Grant Screen Recording and confirm thumbnails, then close the panel and confirm none are written to disk.
5. In Audio Output, switch to another output device; when alerts followed the previous output, confirm they follow the new one, and when Sound settings sends alerts elsewhere, confirm that choice is kept. Change volume and mute.
6. Turn on automatic switching, add an app rule and a time rule, and confirm the Custom Dock switches after the dwell, a manual switch overrides it, and a Dock with an open unsaved draft is not switched away.
7. Start Workspace from a Dock: confirm targets open in order, running apps come forward instead of relaunching, nothing quits or closes, and the Dock switches only when that option is chosen.
8. Export one Dock as a package and import it: confirm a new Dock is created every time, the original is unchanged, and no credentials or account IDs are carried.
9. With Calendar access, confirm Next meeting shows the next relevant event and offers Join only for a recognised https meeting link.

## Optional smooth native switching

- On macOS 14 or later, opt in to “Freeze desktop during Dock restart” and grant Screen Recording when prompted. Switch a native Dock profile on one display and on a multi-display setup; confirm the captured frame remains in memory only for the transaction and disappears after success or rollback.
- Deny or revoke Screen Recording and repeat the switch. The Dock must still switch normally without the freeze. macOS 13 must keep the effect unavailable while native profile switching continues.
- Enable desktop-widget placement and confirm the Custom Dock stays behind app windows, does not overlay fullscreen, and temporarily ignores the auto-hide toggle. Test regular mode again afterward.

## Roadmap regression acceptance

1. Start a disposable Debug visual preview. Rename a profile, visit Settings, return, and verify the name autosaves and survives restart. Duplicate immediately after inline rename: the copy must retain its distinct name and edit target. Inject a failed state write: the draft stays dirty; Cancel Quit/Close retains it, and Retry after repair succeeds without another edit. Configure a newly added item on the first attempt and verify the correct sheet.
2. In a preview, select a group and drag directly to a gap, the start, and the end; use Command-left/right and the named accessibility start/end actions. Preserve relative order, test spacer and final/empty typed drop targets, then Undo. In overflowing side and bottom previews, tiles must remain clipped along the scrolling direction; jump controls must reveal the actual first and last items without content painting outside the Dock. The sample renderer may scroll and jump overflow, but must not launch apps, edit live profiles, resize the live Dock, or apply native changes.
3. Preview a preset, inspect missing-app fallback notes, substitute/remove/add apps, then Cancel. No profile is created. Create must persist one complete profile before selecting it. Repeat with failed persistence and an invalid name.
4. Compare inherited versus profile-specific material/theme/size/spacing/cards and Undo, including bottom/left/right, maximum scale, many widgets and short displays. Preview surface width/height must follow the render model rather than fill unused editor space.
5. Search for a specific control, follow its result, and verify its section is visible. Navigate manager, Connections, appearance, history and popouts using keyboard and VoiceOver. Test Reduce Motion, Reduce Transparency and Increase Contrast.
6. Hide a profile with running Focus/Countdown timers; completion must not depend on mounting its compact view/popout. Change a running duration and verify rescheduling. Keep Hydration open through midnight, time-zone changes and wake. Compare alert delivery with in-app remaining time.
7. Create duplicate account/symbol queries and observe one shared request, maximum four provider jobs, changed-account cancellation, partial watchlist success, error retention and fastest requested interval. Exercise disconnected account remapping and both backup export choices.
8. Inspect history before an edit/deletion, restore as a new profile, and verify current IDs/data are unchanged. Export/import a personal preset: notes, hydration undo/history, cached metrics and connection assignments must be absent by default; local app/file/link references remain disclosed.

## Opt-in suites

`./TestMyDock.sh` skips these suites unless their variable is set. Set one at a time, only where the table says it is safe. A suite that reaches the real system lifts the test isolation only for its own test task, through `AppRuntimeEnvironment.withLiveSystemAccess(enabledBy:)`, and only while its variable is `1`; every other test in the run stays isolated.

| Variable | What it touches | Where it is safe |
| --- | --- | --- |
| `MYDOCK_PERFORMANCE_OUTPUT=<path>` | Synthetic performance fixtures; writes a JSON baseline to the path | Any Mac. Write the file to `docs/history/` with a date |
| `MYDOCK_CUSTOM_DOCK_RUNTIME_TESTS=1` | Shows an isolated live Custom Dock panel for about 20 seconds; never changes Apple’s Dock | A Mac where a briefly visible test panel is acceptable |
| `MYDOCK_LOCAL_AI_ACCOUNT_TESTS=1` | Reads the signed-in local Codex account's quota (read-only; starts no task) | A Mac whose Codex sign-in you own |
| `MYDOCK_INSTALLED_APP_AUDIT=1` | Scans installed applications and prints their count | Any Mac; the log lists no app names |
| `MYDOCK_DISPOSABLE_SYSTEM_TESTS=1` | Applies and restores a real Apple Dock layout | Only a throwaway macOS account or VM (see below) |

Run the synthetic baseline without changing native Dock preferences:

```sh
MYDOCK_PERFORMANCE_OUTPUT="$PWD/docs/history/PERFORMANCE_BASELINE_$(date +%F).json" ./TestMyDock.sh
```

For the live test, first prepare a separate throwaway macOS account or VM, save an independent copy of its Dock preferences, close other MyDock copies, and confirm that this environment can be reset. The test adds a spacer, verifies apply, records/restores the original layout through the journal, and verifies recovery. It must never be enabled on the user's everyday Dock:

```sh
MYDOCK_DISPOSABLE_SYSTEM_TESTS=1 ./TestMyDock.sh
```

If restore fails, the test leaves its journal at the reported temporary location; inspect/recover it before deleting the disposable environment. This harness covers one live transaction and recovery path. It does not replace the manual Spaces/display/fullscreen, replacement-mode, permissions or notification matrix. macOS 13/14, Intel runtime, full-Xcode Focus discovery, signed Login Items, install/update and publisher notarization remain separate gates.

Keyboard range regression: select the first Dock item, press Shift-Right twice then Shift-Left. Two items remain selected and focus follows the endpoint. Command-Right moves the group while preserving relative order; closing the inspector clears the anchor/cursor and an ordinary arrow starts a fresh selection.


Current canvas pointer regression: in an isolated preview, drag Clock to the trailing material, then Undo once; the original order returns. Select Clock/Weather and move the group to both ends without changing relative order. Add a small spacer and drag it between widgets. Release a dragged item outside the material, or press Escape during a drag; no edit is committed. Verify keyboard focus/navigation and the context menu after each move. Finder/browser multi-URL drops must preserve source order at a gap and in an empty Dock. Verify drag auto-scroll in an overflowing Dock. Native end/group/spacer/outside/Undo/context-menu and newly-added-item focus checks passed in the 1 October native-pointer build; Escape/post-drag keyboard/external/empty/auto-scroll acceptance remains open.
