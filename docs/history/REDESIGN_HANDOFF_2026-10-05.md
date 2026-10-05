# MyDock redesign — handoff for the next orchestrator (5 October 2026)

Written by the Claude Opus 5.5 orchestrator when the user's usage limit was close. This is the single entry point for whoever finishes the redesign. The detailed per-package record is [REDESIGN_LEDGER_2026-10-04.md](REDESIGN_LEDGER_2026-10-04.md); the original brief is `.claude/commands/redesign.md` (untracked, local only — copy it if you need it elsewhere).

---

## 0. Read this before starting a cloud session

**A Claude Code cloud session (claude.ai/code) cannot finish this work on its own.**

1. **Nothing from the redesign is on GitHub.**
   - `origin/main` is still `534faf7`, the pre-redesign baseline.
   - All work is on the **local** branch `redesign/integration`, plus a few unmerged local worker branches.
   - Pushing needs the user's explicit permission, which has not been given yet. A cloud session clones `origin`, so it sees none of this unless the user pushes first:

     ```sh
     cd ~/Documents/ChatGPT/dockX
     git push origin redesign/integration
     ```

     Merge FX-06 first (finished, see §3.1). Also push the FX-07 WIP branch if the cloud session should finish it:
     `git push origin redesign/FX-06 worktree-agent-a1de1985da0a04f99:redesign/FX-07-wip`
2. **Cloud sessions run Linux, not macOS.**
   - This app needs the macOS 26 SDK, AppKit/SwiftUI and Liquid Glass.
   - `./TestMyDock.sh`, `./BuildMyDock.sh`, every `MYDOCK_*_QA` render export, and launching `build/MyDock.app` **only work on the user's Mac**.
   - A cloud session can edit code, review diffs and write docs. It cannot verify anything. The "Done = built, tested, rendered, reviewed, recorded" rule (AGENTS.md / brief §3) cannot be met there.
3. **Codex CLI and the local worktrees** (`../MyDock-wt/*`, `.claude/worktrees/*`) exist only on the Mac.

**Recommendation:** finish the remaining steps in a **local** Claude Code session on the Mac (Opus, high effort), started in `~/Documents/ChatGPT/dockX`. If the user insists on cloud:
- push first;
- let cloud do only the code-only items in §4 (marked ☁️);
- run every verification step (§5) locally afterwards.

---

## 1. Where things stand

| | |
|---|---|
| Repository | `~/Documents/ChatGPT/dockX` (main checkout) |
| Integration branch | `redesign/integration`, HEAD `52dbf11` (plus the commit that adds this file). **Never merged to `main`.** FX-06 and FX-07 are **not** merged yet (see §3). |
| Last full verified suite on integration | `./TestMyDock.sh` **649 tests in 80 suites passed, 0 failed** (after the FX-02 merge, commit `fa9971b`). Log: `.build/redesign-fx02-test.log` |
| Canonical app | `build/MyDock.app`. Last rebuilt after RD-09 (commit `087a1a2`, SHA-256 starts `9a75cac4…`) and running. **The FX wave is not in the canonical app yet.** |
| Last full render matrix | `.build/visual-qa/redesign-20261005/integrated/<MODE>/` at `087a1a2`. It predates the whole FX wave and must be redone. |
| CI | Not run since RD-00. Needs a push; see §5.6. |

---

## 2. Finished work (merged into `redesign/integration`, verified locally)

Every row below was reviewed by the orchestrator, merged, and followed by a full unsandboxed `./TestMyDock.sh` on integration. Details, decisions and evidence paths are in the ledger.

| Package | Worker | What it delivered | Merge |
|---|---|---|---|
| RD-00 | orchestrator | `.claude/worktrees/` ignored; 15 gitlinks and a `.pyc` untracked; CI matrix reduced to `macos-26` and `macos-26-intel`; `TestMyDock.sh` finds Swift Testing in both the CLT and full-Xcode layouts (the CI `fatalError` hypothesis, **unconfirmed**) | `be690ce` |
| RD-01 | Claude design-system | `DockDesign.Glass/Module/Motion/Grouped`, `dockGlass`, `DockGlassGroup`, `dockHover`, `GlassModule`, `GroupedSection/Row`, `PillButton`, `SizePager`, `StyleSwatch`, `MYDOCK_REDESIGN_QA` | `a3f96c0` |
| RD-02 | Codex (high) | Additive model:<br>• `DockEdgeStyle`, `DockWidgetSurface`, `customDockFloatingInset`, `DockTintMode`<br>• optional `ProfileAppearance` fields<br>• `WidgetConfiguration.widgetAccent/showsLabel/glassTint`<br>• old-JSON compatibility tests | `f5500c2` |
| RD-03 | Codex (medium) | `SettingsView` split into `UI/Settings/*Page.swift` (mechanical) | `a58261c` |
| RD-04 | Claude dock-surface | `DockSurfaceLayers` (truly clear glass), edge/tint/inset, `DockPanelGeometry`, running dots, minimal badges, spacers and folder | merged, plus fix `116eac9` |
| RD-05 | Claude widget-visuals | `WidgetContainer` surface switch (glass/plain/tile), module-grammar shared faces, harmonised palette, per-widget environment | `0119b19`, plus Mono-default fix |
| RD-06 | Claude widget-gallery | Add Item gallery: Widgets · Apps · More, Suggested, in-place detail with `SizePager` | merged at `cbcb481`+ |
| RD-07 | Codex (medium) | System Settings–style pages; Appearance page with five `DockQuickStyle` swatches | merged, plus `e7fd022` |
| RD-08 | Claude widget-visuals | iOS-style widget settings sheet and grouped popout shell | `1f420c4` |
| RD-09 | Claude widget-visuals | Faces and popouts for Calendar/Reminders, Alarm, utilities, Now Playing, Weather, AirDrop, Trash | `087a1a2` |
| RD-10 | Codex (high) | Faces and popouts for Stock, Stripe, Paddle, Shopify, AI, System, Network | `7e1b74a` |
| RD-11 | Claude dock-surface | Popout appear spring, reorder settle, interactive glass, Clear onboarding reveal, styled starter presets | `32b5046` |
| RD-12 | Codex read-only and Claude visual-reviewer | Independent code review (8 findings) and visual review (D1–D18, T1–T7) | ledger only |
| FX-01 | Claude | Root cause of the AppKit update-constraints crash: the popout shell height was compressible. Fixed with `.fixedSize(vertical)`; `PopoutLayoutLoopTests` | `b71840c` |
| FX-03 | Claude | Single-surface popouts (the NSPopover material); safe Remove Widget retry; no repeated sheet hero; one customise surface; label-over-value; contrast and truncation fixes; dead code removed | `062b2a0` |
| FX-05 | Codex (high) | RD-10 family fixes: reading-first, grouped type scale, accessible charts, dead colour pickers removed | merged, plus `80ecbe0` |
| FX-04 | Claude | RD-09 family fixes: per-hour Weather daylight, hour labels, no duplicate copy, collapsed settings disclosure | merged, plus `0ac58f6` |
| FX-02 | Claude | Cached running-indicator matches (no file I/O on hover); vertical badges; no trailing separator; one colour-scheme source; editor reorder settle; preset previews fit | merged, plus `fa9971b` |

Orchestrator integration fixes along the way:
- running-dot bundle gate;
- shared `DockPresentationEnvironment.swift`;
- `DockItem.widget` creates Mono widgets;
- appearance search terms;
- freshness "Retry" vs "Refresh";
- Weather face per-hour daylight;
- the preset sheet `fitsByScale`.

---

## 3. In flight when this file was written

| Package | Worker | Branch / worktree | State | What to do |
|---|---|---|---|---|
| **FX-06** Settings fixes | Codex `gpt-6.1-sol`, effort medium | `redesign/FX-06` in `../MyDock-wt/FX-06`, base `0ac58f6`. Brief `../MyDock-wt/FX-06.brief.md`; report `../MyDock-wt/FX-06.report.md`; full report `../MyDock-wt/FX-06/.build/visual-qa/FX-06/REPORT.md` | **Finished, committed `b6c14d1`, NOT merged, NOT reviewed by the orchestrator** | Review the diff, merge (§3.2), run the unsandboxed suite. See §3.1 |
| **FX-07** gallery fixes | Claude `widget-gallery` subagent | branch `worktree-agent-a1de1985da0a04f99` in `.claude/worktrees/agent-a1de1985da0a04f99`, base `fa9971b` | **Interrupted by a usage limit. Partial work saved as WIP commit `d226a3d`. It has not compiled, built or been tested** | Finish it (§3.3), then review and merge |

### 3.1 FX-06 result (Codex exited 0)

Commit `b6c14d1` on `redesign/FX-06`, 18 files, +323/−166. Worker-reported, **not yet verified by the orchestrator**:

| Fix | Where (paths under `Sources/MyDock/UI/`) |
|---|---|
| D10 General and Integrations on grouped rows | `AppLifecycleSettingsView.swift:22`, `RecoveryCenterView.swift:12`, `PrivacyHelpSection.swift:8` |
| D11 single "Settings" title; every sidebar row visible at 780×600 | `SettingsView.swift:117` |
| One Finish control that still reaches every material | `Settings/AppearanceSettingsPage.swift:104`, `SettingsSearchCatalog.swift:32` |
| Codex #6: complete Restore defaults, both scopes, with undo | `Settings/AppearanceSettingsPage.swift:49` |
| D16 sentence-case permission rows | `Settings/SettingsShared.swift:48` |
| Short footers, with detail moved to `.help` | `Settings/BehaviorSettingsPage.swift:29`, `Settings/GeneralSettingsPage.swift:16` |
| D17 aligned inspector sliders; destructive preset Remove | `DockInspector.swift:13`, `PersonalPresetPicker.swift:24` |
| D13 centred inspector headers with the glass "Done" | `DockInspector.swift:26,93`, `RecoveryCenterView.swift:35` |
| Account presentation, which also covers the §4.2 "Claude connection note" | `AIAccountConnectionView.swift:77`, `ConnectionsCenterView.swift:58` |

Worker validation:
- focused `RedesignSettingsTests`: 8 tests, 41 cases;
- full suite 641 tests in 79 suites, run on its own base; this ran unsandboxed after approval;
- universal build plus signature check;
- 92 renders in `../MyDock-wt/FX-06/.build/visual-qa/FX-06/`, with 74 "before" images in `before/`.

One reveal-monitor timing test failed once and then passed on rerun. **Watch it:** if it flakes again, investigate; never skip it.

**Not done by FX-06:** the swatch theme line (§4.1). `grep dockSwatchTheme` finds nothing in its tree.

### 3.3 FX-07: what the WIP commit `d226a3d` contains and what is left

FX-07's brief is in the ledger, "Fix wave plan" FX-07 line. The full Agent prompt is reproduced in this list. The work touches `UI/WidgetGallery/{Apps,Chrome,Detail,Model,Tile}.swift`, +260/−27.

Started in the WIP, unverified:
- Fix 1 (Codex #3), partial: tiles are `focusable` and show a 3 pt accent focus ring (`galleryFocusable`, `GalleryTileBackdrop`). There is a DEBUG `focusedTile` override for renders.
- T3: tiles have no stroke or fill. The live preview floats, and hover, selection and focus are drawn by `GalleryTileBackdrop`.
- D17: "added" apps show `GalleryAddedCheck`, a plain green check with no circle. Small and Regular spacers have distinct `spacerDetail(_:)` descriptions.
- D2 / Codex #8: previews built from the creation configuration (`DockItem.widget(kind)`), so Mono. Check that every gallery preview call site uses it.
- The detail pill reads "Add Another" once a widget is added.

**Left to do**, all in FX-07's owned files: `AddLibrary.swift`, `UI/WidgetGallery/*`, `WidgetLibraryTile.swift`, `WidgetDiscovery.swift`, `LibrarySearchField.swift`, `RedesignQA/GalleryQA.swift`, `Tests/MyDockTests/RedesignGalleryTests.swift`.

1. Get it compiling. It was stopped while rewriting the **detail view body** (`WidgetGalleryDetail.swift`).
2. Fix 1, key handling:
   - Return or Space on a focused tile opens the detail view.
   - Keep a direct-add shortcut, ⌘Return or today's search-result Return.
   - Escape in the detail view returns focus to the tile, and the Escape order is unchanged: detail, then search, then close.
   - VoiceOver actions are "Show Sizes" and "Add".
   - Write the keymap in the tile's help text.
   - Put the key-to-action mapping in a pure helper and test both routes.
3. Fix 4: text-free `PresetLibraryTile` thumbnails (`WidgetLibraryTile.swift`). Today they use `WidgetCardPreview(width: 92, displayScale: 0.6)`, which gives about 5 pt text. Use glyph-only module chips or a `DockSwatchPreview`-style mini Dock.
4. Fix 6 (T7): fold the layout caption into the `SizePager` caption, so there are at most two secondary lines.
5. Fix 7 (D13): Back on the leading edge, Done on the trailing edge, both `GalleryGlassButtonStyle`.
6. Tests in `RedesignGalleryTests`:
   - key mapping;
   - preview appearance equals creation appearance for every family;
   - spacer descriptions are distinct;
   - the added check state.
7. `MYDOCK_GALLERY_QA=1` renders, compared before and after: widgets tab at 920 and 700, detail, Apps, More, a focused tile, RT and IC, preset thumbnails. Then `./BuildMyDock.sh --output .build/visual-qa/FX-07/MyDock.app` and the full `./TestMyDock.sh`.
8. Squash it with the WIP into one commit: "FX-07: …" (message in the ledger plan).

If you resume with a fresh agent instead, give it this section and tell it to `git reset --hard d226a3d` in its worktree, or to check out that commit. **The Agent tool usually branches from `534faf7`.**

### 3.2 Merge procedure (both packages)

```sh
cd ~/Documents/ChatGPT/dockX            # on redesign/integration
git merge --no-ff <branch> -m "Merge FX-0x …"
# Conflicts are expected in:
# - MyDock.xcodeproj/project.pbxproj: take ours, then ./GenerateXcodeProject.sh (xcodegen is installed)
# - UI/PremiumVisualQA.swift: keep BOTH dispatch lines
./TestMyDock.sh > .build/redesign-<pkg>-test.log 2>&1   # must pass, unsandboxed
```

Review each diff against the package brief before merging; earlier waves found real defects this way.

---

## 4. Remaining work after FX-06 and FX-07 (precise)

☁️ means a code-only edit, possible in the cloud but verified on the Mac. Everything else needs the Mac.

1. ☁️ **Swatch theme hand-off (FX-02 → Settings). Still open; FX-06 did not do it.** After merging FX-06, in `Sources/MyDock/UI/Settings/AppearanceSettingsPage.swift`, on the Style section that shows the five `StyleSwatch`es, add `.environment(\.dockSwatchTheme, <effective settings>.customDockTheme)`. Use the effective-settings variable that the hero preview in that file uses.
2. **`AIAccountConnectionView` "Claude connection note".** FX-06 changed `AIAccountConnectionView.swift:77`. Verify in its renders that the note is now one short line. If it is, mark this resolved; if not, fix it as a one-liner.
3. ☁️ **Stale QA click point.**
   - The `MYDOCK_SURFACES_QA` export "surface-alarm-edit" in `UI/PremiumVisualQA.swift` clicks a fixed point (373, 357) aimed at the old Alarm pencil, which moved in RD-09/FX-04.
   - Find the new edit control and update the point, or switch to a non-coordinate trigger.
4. ☁️ **Performance follow-up.**
   - `AppLauncher.isMissingTarget` still stats the file system once per tile on every `CustomDockView` body evaluation, including hover.
   - Cache it alongside FX-02's `DockRunningAppCache` (`DockManagement/DockPresentationPolicies.swift`).
   - Invalidate on profile item changes, on app launch/terminate notifications, and on a timer of about 30 s or on Dock reveal.
   - Add a counting-stat test like FX-02's.
5. ☁️ **Accepted taste items, optional.** These are recorded but not product-approved:
   - **T2 (needs a user decision):** "Auto" accent becomes Mono except for an active state.
   - **T5:** the sheet preview drops the Dock strip, so the bare module sits on the wallpaper.
   - **T6:** Calendar rows read "3:42 · Work" with a calendar-colour bar.

   Do not do T2 without asking the user.
6. **Final verification wave (Mac)**, done by the orchestrator itself (see §5).
7. **Docs (Mac or cloud, after §5 evidence exists)**, done by the orchestrator only (see §6).
8. **Ask the user** about the push and CI, and about merging to `main` (never do either without explicit permission).

---

## 5. Final verification (Mac only; the orchestrator runs these itself)

1. **Tests.** `./TestMyDock.sh > .build/redesign-final-test.log 2>&1` must pass with 0 failures; record the count. Also `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests/Tooling -p 'test_*.py'` (11 passed at baseline). Then `git diff --check`.
2. **Full render matrix** from one debug build, the one `TestMyDock.sh` builds:

   ```sh
   R=$PWD/.build/visual-qa/redesign-<date>/final; mkdir -p $R
   for M in REDESIGN DOCKSTYLE WIDGETSURFACE GALLERY SETTINGS WIDGETSHEET FACESA FACESB MOTION GLASS WIDGET SURFACES ADAPTIVE TOOLS INTERACTION FOCUSED; do
     mkdir -p $R/$M
     env MYDOCK_VALIDATION_ROOT=$(mktemp -d "$PWD/.build/isolated-render.XXXXXX") MYDOCK_VISUAL_PREVIEW=1 \
         MYDOCK_RENDER_QA=$R/$M MYDOCK_${M}_QA=1 .build/swiftpm-test/arm64-apple-macosx/debug/MyDock > $R/$M.log 2>&1
     echo "$M exit $? $(find $R/$M -name '*.png' | wc -l)"
   done
   ```

   - Every mode must exit 0. WIDGET must produce 130 PNGs; DOCKSTYLE asserts badge fit; GLASS asserts corner alpha.
   - A crash shows up as exit 133 with a report in `~/Library/Logs/DiagnosticReports/MyDock-*.ips`. FX-01 shows how to get the exception reason.
   - The baseline mode with no `MYDOCK_*_QA` flag also exists.
3. **Look at the images yourself.** At minimum check that every RD-12 visual finding D1–D18 is resolved. A second read-only `visual-reviewer` pass over `final/` is recommended (see §7).
4. **Canonical app.**

   ```sh
   osascript -e 'tell application id "app.mydock.MyDock" to quit'   # wait until pgrep shows it gone
   ./BuildMyDock.sh > .build/redesign-final-build.log 2>&1
   shasum -a 256 build/MyDock.app/Contents/MacOS/MyDock
   lipo -archs build/MyDock.app/Contents/MacOS/MyDock
   codesign --verify --deep --strict build/MyDock.app
   open build/MyDock.app
   ```

   Never overwrite a running bundle. Never touch `~/Library/Application Support/MyDock`.
5. **Isolated launch sample** (as in previous baselines): a fresh `MYDOCK_VALIDATION_ROOT`, about 60 s of `ps` sampling, then a normal quit Apple Event.
6. **CI.** Only after the user allows `git push origin redesign/integration`. Watch `.github/workflows/validate.yml` on `macos-26` and `macos-26-intel`.
   - The RD-00 change to `TestMyDock.sh` (the full-Xcode Testing.framework path) is the hypothesis for the earlier `error: fatalError`.
   - If CI still fails, get the full log of the "Unit and regression tests" step; `gh` is not installed locally.
7. **Old-profile check.** The RD-02 tests decode pre-redesign JSON, which proves this in tests. Optionally render the baseline (no-flag) export with an old `state.json` fixture and confirm the tile, hairline and frosted look.

---

## 6. Docs to update (orchestrator only; workers never edit these)

1. Archive the current baselines (follow the pattern in `docs/history/`):
   - `docs/RELEASE_AUDIT.md` → `docs/history/RELEASE_EVIDENCE_PRE_REDESIGN_2026-10-05.md`
   - `docs/BUILD_BASELINE.json` → `docs/history/BUILD_BASELINE_PRE_REDESIGN_2026-10-05.json`
2. Rewrite `docs/RELEASE_AUDIT.md` for the redesign baseline:
   - what changed;
   - the test count;
   - the render matrix counts and paths;
   - the canonical SHA, archs, signature and launch sample;
   - "Not verified": native Liquid Glass compositing, the live NSPopover material, hover specular, native morphs, side Docks, multiple displays, Intel and macOS 13–15, keyboard-only flows, VoiceOver, CI.
3. Add a dated "Redesign — 5 October 2026 (current)" section at the top of `docs/IMPLEMENTATION_STATUS.md`. Mark the older top sections as dated.
4. Update `docs/BUILD_BASELINE.json` with the new hashes and fingerprint.
5. In `docs/history/REDESIGN_LEDGER_2026-10-04.md`, add "Final reconciliation":
   - per package, implementation status and verification status, kept separate;
   - every RD-12 finding with its disposition: fixed in FX-x, deferred, or needs a user decision;
   - the open items.
6. `docs/ARCHITECTURE.md`: a short paragraph on the design system (`UI/DesignSystem/*`), the presentation environment, the popout shell contract (Wave 3 contract) and the `DockPresentationPolicies` caches.
7. **Final report to the user** (brief §7):
   - what shipped per package;
   - what is partial;
   - what is blocked;
   - the render folder path;
   - a manual checklist: real Liquid Glass over several wallpapers in light and dark; hover, specular and popout feel; reveal and auto-hide with the floating inset; side Docks; multiple displays; Intel and macOS 13–15 fallbacks; Add Item, the widget sheet and Settings using the keyboard only; VoiceOver on new controls.

---

## 7. Recommended agent setup for the rest

The remaining work is mostly **integration, verification and documentation**, so it needs few workers.

| Role | Model / effort | Why |
|---|---|---|
| **Orchestrator** | Claude Opus, high effort, **local session on the Mac** in the main checkout | It owns merges, the unsandboxed test runs, the render matrix, the canonical build, the ledger and the docs. Judging diffs and renders is the critical skill here. |
| **Fix worker(s)** for §4.1–4.4 | Usually the orchestrator does them inline: they are small, one-file edits. If delegated: the Claude `widget-visuals` / `dock-surface` / `widget-gallery` agents (Opus, high) with `isolation: worktree` | Each touches one or two files. Spawning costs more than doing it. |
| **Final visual review** | Claude `visual-reviewer` agent (Opus, high), read-only, over `.build/visual-qa/redesign-<date>/final/` | It found most of the real defects last time. Ask it to verify D1–D18 resolution specifically and to call new regressions. |
| **Final code review** (optional) | Codex `gpt-6.1-sol`, `-c model_reasoning_effort=high`, read-only in a detached worktree **without** `--add-dir .git` | An independent second model caught the removal/undo and accessibility bugs. Review `git diff 1071b86..HEAD` (the fix wave) only. |

Rules learned this session:
- **Codex launch:** always use `codex exec … "$(cat brief.md)" < /dev/null > log 2>&1`.
  - Without `< /dev/null`, Codex blocks forever on "Reading additional input from stdin…". FX-05 lost about 4 h this way.
  - Writers need `--sandbox workspace-write --add-dir <repo>/.git`, because commits from external worktrees write there.
  - Never use effort `xhigh`.
- **The Codex sandbox stalls the full suite** (LaunchServices waits in `AIActivityDedupeTests`, `BoundedSubprocessCaptureTests`, `AIAccountTests`). Accept focused-suite evidence from Codex and always re-run the full suite unsandboxed in the orchestrator.
- **Stale worktree base:** the Agent tool often branches worktrees from `534faf7` (`origin/main`). Every brief must say "if HEAD ≠ <base>, `git reset --hard <base>` first". New agent definitions in `.claude/agents/` only load in a new session; they exist now (design-system, dock-surface, widget-visuals, widget-gallery, visual-reviewer).
- **API usage-limit interruptions:** subagents keep their uncommitted work. Resume them with `SendMessage(to: <agentId>)` and do not relaunch.
- **At most two concurrent builds** (SwiftPM builds take minutes).
- **Glass in exports:** native Liquid Glass and `.glassProminent` blank offscreen `cacheDisplay` captures. Exports draw the fallback whenever `dockSnapshotRendering` is set, so never judge glass from bitmaps.
- **File ownership:** one owner per file per wave. Shared QA dispatch lives in `UI/PremiumVisualQA.swift`: one line per package, with exports in `UI/RedesignQA/*QA.swift`. Conflicts there and in `project.pbxproj` are routine; regenerate the project with `./GenerateXcodeProject.sh`.
- **Hard rules (AGENTS.md):**
  - Quit the canonical app cleanly before rebuilding.
  - Disposable bundles go only to `.build/visual-qa/<pkg>/`.
  - Never touch `~/Library/Application Support/MyDock`, Keychain or credentials.
  - Persisted raw values and keys must never change.
  - No push, PR or merge to `main` without the user.

---

## 8. Exact order of work for the next session

1. `git switch redesign/integration`, then `git log --oneline -1`. Expect the commit that adds this file, on top of `52dbf11`.
2. **FX-06:**
   - Review `git diff 0ac58f6..b6c14d1`.
   - Look at its before/after renders: General, Integrations, Permissions narrow, the Appearance Glass section, the inspectors.
   - Merge using §3.2.
   - Run the unsandboxed `./TestMyDock.sh`. Expect 649 + about 8 new tests (FX-06 counted 641 because its base was older).
3. **§4.1:** add the swatch theme line. Run a focused test and the SETTINGS render.
4. **FX-07:** finish it per §3.3, in its worktree or a fresh `widget-gallery` agent based on `d226a3d`. Review, merge, then run the full suite.
5. **§4.2–4.4:** each inline, with a test.
6. **§5:** final verification. That means the full suite, Python tooling, `git diff --check`, the full render matrix (all modes exit 0, WIDGET = 130), your own review of the images, a canonical rebuild and relaunch, and the isolated launch sample. Optionally add one read-only `visual-reviewer` pass and one read-only Codex review of `1071b86..HEAD`, then fix any blockers they find.
7. **§6:** archive the baselines, rewrite RELEASE_AUDIT and IMPLEMENTATION_STATUS, update BUILD_BASELINE.json and ARCHITECTURE, and write the ledger "Final reconciliation".
8. **Final report to the user (§6.7).** Ask the user about:
   - pushing for CI;
   - T2;
   - merging to `main`.

## 9. Kickoff prompt for the next orchestrator (paste as the first message)

> You are the MyDock redesign orchestrator, continuing a previous session. First read, completely: `AGENTS.md`, `docs/history/REDESIGN_HANDOFF_2026-10-05.md` (your plan, sections 0–8), `docs/history/REDESIGN_LEDGER_2026-10-04.md` (design contract, wave 3 contract, RD-12 reviews, fix wave plan, every FX entry) and `.claude/commands/redesign.md` (the original brief and hard rules). Work on the local branch `redesign/integration` in `~/Documents/ChatGPT/dockX`. Follow the handoff's §8 order exactly.
>
> You own merges, unsandboxed test runs, renders, the canonical build and every doc. Only you edit the ledger, IMPLEMENTATION_STATUS.md and RELEASE_AUDIT.md.
>
> Small fixes you do inline. FX-07 you finish with the `widget-gallery` agent (Opus, high, `isolation: worktree`, told to `git reset --hard d226a3d` first) or inline. Final review: the `visual-reviewer` agent, read-only, plus optionally Codex `gpt-6.1-sol` at effort high, read-only, launched with `< /dev/null`.
>
> Never push, open PRs or merge to `main` without asking me. Never touch `~/Library/Application Support/MyDock` or credentials. Done means built, tested, rendered, reviewed and recorded.
