# MyDock macOS acceptance tests

Status: automated fixture and host-reader tests pass (99 tests); manual desktop acceptance is partial. The rebuilt release app's Settings/Permissions path and Accessibility System Settings deep link were verified. The earlier manager build's explicit selection mode, two-item selection, group-delete count, and clear-selection flow were verified without deleting saved items. The latest manager draft/save/discard and group-move UI compiled and passed model/store tests but could not be clicked through after the Mac locked. Custom Dock gestures, real Dock changes, notifications, and live market data have not been manually exercised. Native Dock automated tests use fakes and do not write the developer machine's preferences. EventKit tests cover configuration and ordering only; they do not read personal calendars or reminders.

## Core vertical slice

1. Launch MyDock and confirm the setup wizard presents the three setup modes.
2. Import the current Dock or leave it empty, choose starter widgets, select edge/display, and finish setup; confirm the created profiles in Manage Docks.
3. Add an installed application, save, and confirm its icon appears in both editor and Custom Dock.
4. Click the item and confirm the app launches; click again while active and confirm normal activation.
5. Enable Show running apps, launch and quit an unpinned app, and verify the transient item appears/disappears; choose Keep in Dock and verify it remains pinned.
6. Change a native and Custom Dock profile color, then quit and relaunch MyDock; confirm profile, ordering, color, and item path restore. Confirm only the Custom Dock surface is tinted.
7. Add a second profile and switch from menu bar; confirm the first profile remains intact.
8. Record distinct shortcuts for two profiles, trigger them from another app, and verify conflict feedback and clearing.
9. Add a folder with nested folders and files; browse, open a file, reveal it in Finder, and close with Escape.
10. Add a Calendar widget. Confirm Date layout works without prompting; switch to an event layout and grant or deny access. Select calendars, toggle all-day events, refresh, and verify ongoing/soon meetings remain ahead of all-day entries. Confirm Zoom, Google Meet, and Teams Join links open.
11. Add a Reminders widget. Grant or deny access on first popout open; choose all lists or one list, add a reminder, complete it, undo the last completion, and verify changes in the Reminders app.
12. Add System Activity; compare aggregate/per-core CPU, memory breakdown and swap with Activity Monitor, check thermal state, 1/5/15-minute load averages, uptime, and startup-volume capacity. Check that pressure says Awaiting event until a public pressure-change notification arrives rather than inventing a current gauge. Hide the Custom Dock and verify sampling pauses. Scan Home, Applications, and Library; confirm their totals remain separate because Home includes Library, progress advances, and the scan continues after closing/reopening the popout. Choose a temporary folder and verify largest-file sorting, Finder reveal, Cancel, Scan Again, and partial/capped disclosure.
13. Add a Network Activity widget; compare aggregate rates and interface addresses with macOS Network settings/Activity Monitor, then auto-hide the Dock and verify its sampling stops.
14. Add one one-time alarm and one weekly alarm; grant/deny Notifications access, verify disabled fallback on denial, remove one alarm, and verify OS alert delivery across sleep/wake. Relaunch after the one-time alert and confirm the tile reconciles it as disabled. Start a Countdown, verify its completion notification across app quit/sleep, then pause/reset/remove another countdown and confirm no stale alert arrives.
15. Add a Weather widget, search for a city without granting Location, choose Current/Conditions/Hourly layout and °C/°F, and verify the 1–6 hour setting. Confirm the translucent/themed backgrounds, manual refresh, ten-minute refresh while open, stale forecast fallback, and backup restoration. Only press “Use Current Location” to exercise the contextual location prompt.
16. Add an AirDrop widget; drop files and an HTTPS link, then choose files from the panel. Confirm the macOS sharing picker receives the selected items, the user can select AirDrop when available, and canceling the picker leaves the app usable.
17. Add a Trash widget, compare its count with the home Trash folder, open Trash, and confirm the Empty action first presents a destructive confirmation. Deny Finder Automation and verify the error leaves Trash untouched; allow it in a disposable test account and verify the action.
18. Add Now Playing and choose Apple Music and Spotify in turn. If the player is already running, allow MyDock under System Settings → Privacy & Security → Automation; verify track metadata and artwork with local-symbol fallback, play/pause, previous/next, seek intervals, Mini/Full layouts, player-not-running state, permission-denied recovery, and saved configuration after relaunch. The visible compact tile should refresh at a slower 15-second cadence after its popout closes, and stop querying when the Dock hides or the widget is removed. Enable Hide tile when the selected player is closed; quit that player and confirm the tile disappears, relaunch it and confirm the tile returns, then verify the choice survives restart and backup restore.
19. Enable Show minimized windows and Click focused app to minimize; grant or deny Accessibility access. Verify focused-app clicks minimize only when that app has the frontmost focused window, other-app clicks activate normally, minimized tiles list window titles and restore windows on their existing Space, per-app window menus work, the panel stops polling when hidden, and denial falls back without disabling app launches. On macOS 14 or later, opt in to Cache window previews and grant Screen Recording. Leave a uniquely titled window visible for a refresh, then minimize it and verify its tile shows a cached thumbnail. Check duplicate-titled and uncapturable windows use the app icon, and hiding the Dock clears cached images. Revoke Screen Recording and confirm window restore still works with app-icon tiles; macOS 13 must leave preview capture unavailable.
20. Add Stock and Watchlist, then save an Alpha Vantage key under Settings → Integrations. Search a ticker, add it to both widgets, verify name/currency, daily chart ranges, hover/drag crosshair values and volume, selected-symbol refresh cadence, stale-data messaging, request-limit handling, and settings after restart. Confirm the API key is absent from backups and remove it from Keychain afterward. Real-time US quotes require a provider plan that permits them; MyDock currently presents daily series.
21. Add a Stripe widget, enter a restricted `rk_test_…` key with only Core → Balance Read and Billing → Subscriptions Read, and connect a named/colorized account. Verify account selection, each metric and currency, Today/7/30/90-day local-time periods, refunds/reversals/fee handling, active and past-due fixed-price MRR, five-minute refresh, manual refresh, stale-data preservation, and disconnect. Confirm denied permissions show a useful error, the key is absent from profile backups, and remove the connection after use. Stripe test-mode credentials are required; live account behavior has not been verified.
22. Add a Paddle widget and connect a named/colorized Billing account with a current sandbox key that has only Metrics → Read. Verify rejected legacy/Classic/client-side keys, live/sandbox URL selection, Net Revenue/MRR/ARR/active subscribers, chart toggle and UTC day ranges, reported primary currency, five-minute refresh, stale-data preservation, expiry/permission errors, disconnect, and key exclusion from profile backups.

## Native Dock safety (fixture-backed automated coverage first)

1. Decode fixture layouts containing multiple apps, a missing app, and both spacer types.
2. Apply to an isolated test preference store and verify exact round-trip order/kinds.
3. Simulate Dock restart failure and interrupted transaction; confirm rollback and recovery.
4. Rapidly request A → B → C; confirm final state is C and no older request overwrites it.
5. Exercise real Dock mutation only after separate user approval, using the snapshot/restore procedure in [REAL_DOCK_TEST_PLAN.md](REAL_DOCK_TEST_PLAN.md).

## Display and window behavior

1. Test one display, then two displays with distinct scale factors.
2. Disconnect/reconnect the selected display and verify safe fallback and restoration.
3. Exercise left, bottom, and right placement, display selection, size slider, drag-resize grip, auto-hide, visible handle, Apple Dock overlap toggle, and desktop mode. Confirm overflow jump chevrons appear only when content exceeds the viewport and jump to each end. With the overlap toggle enabled, reveal the Apple Dock over MyDock and confirm MyDock and its handle stay hidden until it retracts. On a trackpad, swipe perpendicular to the Dock to switch profiles; verify ordinary mouse-wheel input only scrolls overflowing items.
4. Test fullscreen reveal, Mission Control hiding, Space changes, sleep/wake, and primary-display changes.
5. Verify the Custom Dock does not jump to another display after profile switch.

## Editing, items, and widgets

1. Add and reorder items in Dock Manager; use Select Items to select entries, Shift-click a range, move the selected group left and right, and verify group delete. Confirm edits remain staged until Save, Discard restores the persisted profile, and switching profiles asks how to handle a dirty draft.
2. Verify spacer kinds survive save/reload; add folder/file/link items, customize a folder's local color/letter/number and reset it, inspect Quick Look image/video thumbnails and icon fallback, open items, and use Reveal in Finder/Open Containing Folder. Move a saved local item and confirm the missing-target warning appears. Check that HTTP(S) links validate before launch. Edit a saved link's name, destination, and SF Symbol; fetch a favicon from a public HTTPS site and confirm it remains after relaunch/backup import. Verify HTTP origins, embedded credentials, IP literals, local hosts, cross-host redirects, oversized responses, and malformed images fall back without saving an icon.
3. Verify Clock and multi-city World Clock search/day offsets, Focus Timer, Stopwatch, Countdown and its completion notification, Time Progress, Sticky Note, Hydration history/undo and its notification permission flow, Stock, and Watchlist. Confirm unsupported provider capabilities are explicitly labeled unavailable and never display fabricated values.
4. Move an App Folder application, confirm the missing warning, and use Replace to select its new path. Verify each widget's popout toggle, Configure/Duplicate/Remove actions, ⌘W, Escape, screen-edge placement, and persistence.
5. Verify permission denial and offline states retain usable UI without fake values.
6. Verify closing Dock Manager stops preview refresh and hidden Dock reduces update activity.

## Backup and privacy

1. Export profiles with widget settings, inspect archive schema, and confirm no keys, tokens, permissions, machine IDs, or shortcuts are present.
2. Import into a clean store; confirm import adds profiles, does not auto-activate, and reports missing App Folder member paths alongside top-level missing items.
3. Import the same backup twice and confirm duplicate profiles are allowed.
4. Search logs and backup contents for secret values and personal note text; expect none.

## Accessibility

1. Verify VoiceOver labels and keyboard navigation for menu bar, manager, settings, picker, and popouts.
2. Select Frosted, Dark, and Liquid Glass (macOS 26+) materials; verify the pre-26 fallback, then enable Reduce Motion, Reduce Transparency, and Increase Contrast and verify adapted visuals/animations.
3. Enable Dock magnification and confirm enlargement stays localized around the pointer, app icons grow more than widgets, and Reduce Motion suppresses the effect.
## Shopify

- Create a Shopify Dev Dashboard app, install it on a store in the same organization, and grant only `read_orders`.
- Connect with the store's `myshopify.com` domain, client ID, and client secret. Confirm the account name, color, shop timezone, and currency appear.
- Verify Today, Last 7 days, Month to date, and Last 30 days around a daylight-saving transition against the store's order list.
- Compare order value with current totals for paid, unpaid, partially returned, fully returned, test, and canceled orders; test/canceled orders must be excluded, while unpaid/fully returned orders remain counted.
- Compare AOV, daily chart, product current-unit counts, and available first/last-visit traffic sources. Confirm no customer or referral URLs are retained.
- Verify manual and five-minute refresh, saved last-successful data on network/API errors, Keychain removal on disconnect, and that profile backup contains no app secret/access token.
- With an injected fixture over 10,000 records, confirm refresh displays an error and never publishes partial totals.
- Live store click-through remains blocked until a Shopify store/app credential is available.

## AI Limits and AI Activity

- Add AI Limits, select providers and ordering, choose Numbers/Rings/Bars and Remaining/Used, and select a compact provider. Confirm each provider-reported window, percentage, reset time, and unavailable/unlimited state. Codex reads from the local app-server; no prompts, tasks, or model requests should be started by refresh.
- Add AI Activity and check Codex and Claude Code Today/L7/L30/MTD totals, chart styles, sessions, token/request counts, cached input, and tool calls against local usage records. Confirm the view states that it excludes provider usage outside the local CLI/session logs.
- Check Grok activity is labeled estimated and partial, and that an updated old session is grouped by file-update day. Select Cursor/Gemini/Copilot/Antigravity and confirm unsupported readers remain explicitly unavailable without fabricated percentages or totals.
- Confirm changing providers/date ranges refreshes the correct snapshot, popout close stops its refresh loop, and backups contain only calculated counters and configuration, never prompts, tool output, or credentials.

## Focus Filters and Custom-main Dock

- In System Settings → Focus, add MyDock to one Focus, select a Custom profile, activate the Focus, and confirm it applies without quitting apps. Turn the Focus off and confirm the applied profile remains selected.
- Repeat with a native profile and confirm the transactional Dock writer applies it. Remove a selected profile and confirm the Focus filter reports a clear stale-profile state on the next activation.
- On a disposable user account, record the Apple Dock's original auto-hide state. Select Custom Dock as main and confirm Apple Dock auto-hides; switch to Both or quit MyDock and confirm the prior value returns.
- Simulate an interrupted custom-main session using the fake preferences tests. On next launch, confirm MyDock preserves the recorded prior state while it remains in Custom-main, and restores it when leaving the mode.

## Optional smooth native switching

- On macOS 14 or later, opt in to “Freeze desktop during Dock restart” and grant Screen Recording when prompted. Switch a native Dock profile on one display and on a multi-display setup; confirm the captured frame remains in memory only for the transaction and disappears after success or rollback.
- Deny or revoke Screen Recording and repeat the switch. The Dock must still switch normally without the freeze. macOS 13 must keep the effect unavailable while native profile switching continues.
- Enable desktop-widget placement and confirm the Custom Dock stays behind app windows, does not overlay fullscreen, and temporarily ignores the auto-hide toggle. Test regular mode again afterward.
