# Product plan: the best Dock replacement, kept simple (5 October 2026)

The user asked for the best possible Dock replacement that stays simple to use, with a professional finish, implementing OP-01–OP-07, and new features and changes chosen across the whole product. Orchestration: Opus 5.5. Workers: Sonnet 5.5 at high effort, plus Opus 5.5 for persistence and complex native work. Haiku is not used.

## Principles (every package)

1. **The Dock first.** A feature earns its place only if it makes everyday launching, switching or finding things faster. Nothing new appears on the Dock unless the user adds it.
2. **Simple by default.**
   - Anything that adds chrome, polls, or acts on the system is **off by default**. It is enabled in one place, with a one-line explanation.
   - No new settings page when an existing section fits.
3. **Apple-like and minimal.**
   - Use the existing design system only:
     - `DockDesign` tokens;
     - `GroupedSection`/`GroupedRow`;
     - `GlassModule`;
     - `PillButton`;
     - `WidgetPopoutHero`;
     - the popout settings disclosure;
     - SF Symbols.
   - No new colours.
   - The T2 rule applies: colour only for state.
   - One short line of copy, or none.
   - Keep to Reduce Motion, Reduce Transparency, Increase Contrast, VoiceOver and keyboard support.
4. **Honest and safe.**
   - Never claim a permission or result that was not observed.
   - Never quit apps, close documents or overwrite user data without an explicit action.
   - Credentials are never exported.
   - Runtime data stays runtime-only.
5. **Compatible.**
   - Old `state.json` decodes unchanged. New fields are optional or defaulted, and decoded leniently.
   - Every new family goes through the registry, the gallery and the capability matrix.

## Gaps found against a best-in-class Dock replacement

- **App context menu:** offers only Windows…, Close Window… and Quit.
  - The macOS Dock also offers the open windows inline, Show in Finder, Hide/Show and Force Quit.
- **Dropping files onto an app tile:** does not open the files with that app. This is a core Dock behaviour.
- **Window previews on hover:** there are none. This is the most-requested Dock-replacement feature category.
  - The minimized-window preview cache and the window service already exist.
- **Recent apps:** there is no section for recently used, unpinned apps. macOS calls this "Show suggested and recent apps".
- **First-run and help polish:** there is no What's New sheet after an update, and no Help menu with a keyboard-shortcut reference.

## Packages

| ID | Package | Owner (model) | Scope |
|---|---|---|---|
| PX-1 | Dock essentials | `native-platform` (Sonnet, high) | Drop files on an app tile to open them with it. Richer app menu: windows inline, Show in Finder, Hide/Show, Force Quit with confirmation. Optional "Show recent apps" section, off by default. |
| PX-2 | Window previews | `dock-surface` (Opus) | Opt-in hover previews for running apps. A glass strip of window thumbnails, with a titles-only fallback without Screen Recording. Click focuses a window. |
| PX-3 | OP-03 + OP-04 | `product-experience` (Sonnet, high) | ⌘K search over saved snippets, links and shelf items. A dependable next-meeting row with a Join or location action only when the event provides one. |
| PX-4 | OP-05 | `native-platform` (Sonnet, high) | Audio Output widget: current device, a device list, and volume and mute where supported. Public Core Audio APIs only. |
| PX-5 | OP-01 + OP-06 | `reliability` (Opus) | Workspace start: open a Dock's saved apps, folders and links with a preview and per-target outcomes. A portable Dock package with preview, credential-free export and import-as-new. |
| PX-6 | OP-02 | `native-platform` (Sonnet, high) | Explainable automatic switching: one rule type (an app becoming frontmost, or a time window), with priority, debounce, manual override and a visible "Switched because…" note. Off by default. |
| PX-7 | OP-07 | `widget-visuals` (Opus) | One System detail popout combining CPU, memory, network and storage, with selectable sections. Faces stay independent, and nothing polls while closed. |
| PX-8 | Product polish | `product-experience` (Sonnet, high) | A What's New sheet, once per version and dismissible. A Help menu with a Keyboard Shortcuts reference. Consistent empty states. |

Packages are recorded in [the redesign ledger](REDESIGN_LEDGER_2026-10-04.md). There is no Swift toolchain in the cloud session, so CI on macOS 26 (arm64 and Intel) is the compile and test gate. An Opus reviewer checks each merge batch. A native rebuild, renders and the manual checklist on the Mac remain required.
