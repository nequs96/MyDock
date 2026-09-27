# MyDock backup format

Backups are UTF-8 JSON files with a `.json` extension. The top-level object currently contains:

```json
{
  "formatVersion": 1,
  "exportedAt": "ISO-8601 timestamp",
  "profiles": []
}
```

Each profile preserves its ID for source identity, name, kind, color, item order, item IDs, URL/path references, link title and selected icon, widget kind and configuration, spacer kind, and creation timestamp. A fetched favicon is normalized to a small PNG and included with the link. Current widget configuration covers world-clock cities; Stopwatch, Countdown, and Focus Timer state; Time Progress period; Sticky Note text/background; Hydration preferences/history; App Folder apps/appearance; Shortcuts selection; Calendar/Reminders selection and layouts; alarm definitions; Now Playing source/layout/seek interval/hide choice; Weather city, units, layout, forecast hours, background, and last saved forecast; Stock/Watchlist symbols, chart preferences, and cached daily series; Stripe/Paddle/Shopify display configuration and cached metric snapshots; and AI Limits/Activity display configuration and usage-counter snapshots. Business account IDs and snapshot values are not credentials. API keys, client secrets, access tokens, and local session records are never exported. A restored Hydration reminder starts disabled, and restored alarms are imported disabled because operating-system notification requests are machine-local and tied to original item IDs. Countdown elapsed state is reset when a profile is duplicated. Restore assigns fresh profile and item IDs, appends imported profiles, and does not activate them. Importing the same archive again intentionally adds another copy.

Countdown configuration includes either a duration or an absolute target date and time. A duplicated date countdown keeps its target; a duplicated duration countdown resets its run state. macOS notification requests stay on the original device and item ID, so a restored or duplicated date target must be set again in its popout to schedule a completion alert for that copy.

The archive excludes active profile selection, setup mode, global keyboard shortcuts, app-wide appearance, permission grants, scheduled notification requests, Keychain data, service credentials, license data, and machine-specific tokens. Files and applications are referenced by local file URL; they are not embedded. Restore reports missing application, file, or folder paths, including applications nested inside App Folder widgets. Now Playing artwork stays in memory. Optional window previews are stored in the macOS Caches directory, outside profile backups, and are never exported.

The reader currently accepts version 1, limits archives to 25 MiB, 500 profiles, and 20,000 total items including App Folder members (at most 2,000 per folder), validates local file URLs for nested applications and HTTP/HTTPS link schemes, and rejects malformed or oversized favicon image data. Favicon bytes are re-encoded as a bounded PNG during backup and restore. Unknown versions and malformed profiles fail without changing the profile store. Future incompatible changes require a version migration.
