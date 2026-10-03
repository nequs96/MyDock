# Everyday Tools widgets — 3 October 2026

The working tree adds five complete widgets to Add Item, bringing the library to 35 families. A new **Everyday Tools** section appears first in the library, alongside the existing Calculator and Quick Checklist. Existing widget identities, adaptive layouts, appearance choices, profiles, integrations and other concurrent source changes are preserved.

## Features

- **File Shelf:** drop files onto the live Dock face or popout, or choose files/folders; keep up to 50 references with best-effort macOS bookmarks across restarts; copy individual files or all available files for Finder paste; drag available rows out; open/reveal through the row menu; share with the native sharing picker, including AirDrop. Missing originals remain visible with disabled copy/open actions. Removing entries or clearing the shelf does not change originals. References are not backup copies.
- **Text Snippets:** save, name, edit, remove and copy up to 50 reusable pieces of text. “Use Clipboard” explicitly reads text on request; no clipboard monitoring or background collection. Each snippet supports up to 10,000 characters.
- **Quick Links:** save, name, edit, search, copy, open and remove up to 50 websites. Complete HTTP/HTTPS URLs only, without embedded username/password; duplicates are reported. Links open in the default browser.
- **Unit Converter:** live conversion across length, mass, temperature, volume, speed and data; swap units and copy results; local decimal input/output; honest US volume and decimal/binary data labels. Finite-number and overflow handling prevents invalid output.
- **Color Picker:** native color well and screen sampler; 3-/6-digit HEX input; HEX and RGB copying; save, select, copy and remove a local 24-color palette. Screen sampler completion updates SwiftUI state on the main actor.

File Shelf, Snippets and Links offer 96-point compact and 164-point wide faces. Converter and Color Picker offer a 54-point icon and 104-point compact face. All retain the 54-point base height, narrow side-Dock geometry and independent Accent/Soft/Mono/Outline choices. Previews use clearly isolated sample data; live empty collections display real zero counts.

## Persistence and privacy

New configuration fields default to empty when decoding old profiles. File references/bookmarks, snippets, links and colors use the existing validated ProfileStore writer. Collections, identifiers, strings and bookmark payloads are bounded. Export sanitization removes file references and links; snippets follow the existing explicit Include Notes choice. Ordinary profile persistence and backups retain the collections.

No live user clipboard read/write, file transfer, screen sampling, account connection, native-Dock opt-in or synthetic/runtime opt-in was exercised by validation. Test files and state were isolated; originals in the shelf policy test remain byte-for-byte intact.

## Verification

- `./TestMyDock.sh`: **258 reported tests in 20 suites passed**, five explicit opt-ins skipped; `.build/utility-expansion-tests.log`. Eight new tests cover legacy decoding/round trips, store relaunch and editing, shelf deduplication/capacity/file preservation, sanitized exports, malformed collections, unit conversion/temperature offsets/binary data, HEX validation and provider discoverability. An existing resize regression now compares floating-point results with a small tolerance instead of literal equality; its publication and persistence assertions remain intact.
- **32 isolated light/dark renders:** `.build/visual-qa/tools-20261003/`; `.build/utility-expansion-render.log`. Coverage includes Add Item, semantic layouts, all five configuration sheets and full popouts, three empty collections, and 54-point side faces. Library, populated popouts, side faces and representative configuration/empty-state images inspected. Configuration sheets intentionally scroll when appearance controls and editors exceed their viewport.
- XcodeGen regenerated the native project to include both new source files and the new test file. Project/plist lint, shell syntax and whitespace checks pass.
- Universal validation build: **passed** for arm64 (102.67s) and x86_64 (119.52s), macOS 13.0 minimum / SDK 26.4; strict ad-hoc signature and bundle plist checks pass. Output: `.build/visual-qa/tools-validation/MyDock.app`; log `.build/utility-expansion-build.log`. An earlier compile correctly stopped when a concurrent Settings source edit changed during compilation; the successful build uses the updated stable source tree. [Machine-readable validation evidence](EVERYDAY_TOOLS_VALIDATION_2026-10-03.json) records hashes and limits.

## Initial installation blocker — resolved later

**At the initial validation, canonical replacement was pending.** `build/MyDock.app` remains the previous build and is still running as PID 24062 after two normal termination requests. CUA inventory and app binding both fail with `Sky Computer Use native pipe startup failed`. The user has been asked to quit normally and save pending drafts if prompted. The running bundle has not been overwritten or force-terminated. A disposable build under `.build/visual-qa/tools-validation/` is for build validation only.

Once the canonical app exits cleanly, run `./BuildMyDock.sh`, launch that same `build/MyDock.app` and update the canonical fingerprints/launch evidence. Actual Finder drop/paste, AirDrop service/delivery, native screen sampling, keyboard-only and VoiceOver interaction remain open acceptance; bitmap exports and model tests do not prove those native interactions.

## Canonical installation follow-up — 3 October 2026

The user confirmed a normal quit; absence of the canonical process was verified before rebuilding. `./BuildMyDock.sh` installs the complete unchanged validated source into `build/MyDock.app` (cached arm64/x86_64 steps: 0.20s each). Strict signature and plist checks pass; both slices retain macOS 13.0 minimum and SDK 26.4. Source inputs predate the executable, and source/test hashes match the 258-test interaction validation. The canonical app launched and its executable path is verified (PID 28207). Log `.build/dock-interaction-canonical-build.log`; current hashes in [BUILD_BASELINE.json](../BUILD_BASELINE.json). The previous installation blocker is resolved. Final CUA binding still fails with `Sky Computer Use native pipe startup failed`; native acceptance limits above remain open.

## Latest canonical launch confirmation — 3 October 2026

After the user's “closed” reply, process absence was verified and `./BuildMyDock.sh` rebuilt the same canonical bundle (cached 0.29s arm64 / 0.28s x86_64). Strict signature and plist verification pass. The source and test hashes are unchanged since validation; the canonical executable SHA-256 matches the validated universal executable. Launch from `build/MyDock.app` and its exact executable path were verified (PID 28856). Log `.build/utility-expansion-canonical-build.log`; [updated evidence](EVERYDAY_TOOLS_VALIDATION_2026-10-03.json) records successful installation and clears the earlier blocker. Native transfer/sampling and accessibility acceptance limits remain open.
