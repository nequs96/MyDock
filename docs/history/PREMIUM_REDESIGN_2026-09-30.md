# MyDock premium macOS redesign

30 September 2026. Implemented in the existing SwiftUI/AppKit application. Native on-screen acceptance is pending because computer-use inspection found the Mac locked.

The subsequent [code, performance and bug audit](BUG_AUDIT_2026-09-30.md) contains the newer repairs, test results and audited build. This document and its verification manifest retain the evidence for the earlier redesign build.

## Surface audit and implementation

| Surface | Presentation |
| --- | --- |
| Workspace and window chrome | One native unified compact toolbar, workspace segment, sidebar toggle, transparent titlebar, native window corners/shadow, 900 × 600 minimum window. |
| Profile navigation | 252-point charcoal sidebar, search, custom/native profile sections, active/draft indicators, presets, compact creation menu and context actions. |
| Dock editor | Editable profile heading, one blue Use Profile action, compact profile menu, larger floating Dock preview, adaptive item collection, staged Save/Discard/Undo. |
| Item interaction | Consistent thumbnail/label baselines, contextual configuration, duplicate/remove/locate/folder controls, typed reordering, compact destination marker and floating drag preview. |
| Widget gallery | Search and category sidebar; individually headed widget sections; compact, standard, and wide variants using the real card-width setting; adaptive columns, subtle hover and quiet Added state. Multiple widgets can be added before closing. |
| Settings navigation/search | Shared sidebar treatment, seven preference pages, search results and section anchors. |
| General | Interface appearance (Dark, Light, System), login/update controls, history, backup/restore, diagnostics. |
| Dock Setup | Native mode/profile/display choices, segmented position selector, Focus instructions, native switching options. |
| Appearance | Existing profile/global scope, live geometry preview, quiet finish selectors, native theme/material/card controls, density/sliders and advanced controls. |
| Behavior | Compact aligned native switches grouped by visibility, apps/windows, items, and interaction; helper text below controls. |
| Shortcuts | Profile labels, trailing shortcut keycaps and compact Change action; themed native recorder sheet. |
| Integrations | Native account rows with Manage menus, credential disclosure sections, real connected states; existing validation and Keychain handling preserved. |
| Permissions | SF Symbols, concise grant state, helper text, aligned Open Settings actions and refresh. |
| Secondary flows | Preset review/create, link editor/favicon fetch, folder customization, profile rename/duplicate/delete/activation, recovery inspection, About, four-step onboarding, widget popouts/configuration, native menus and alerts. |
| Light appearance | Equivalent adaptive neutral surfaces. Floating Dock System theme follows macOS independently of the editor's chosen appearance. |

`DockDesign.swift` owns color/surface tokens, spacing/radii, typography, buttons, fields, sidebar rows and Settings groups. Provider/persistence/model code was preserved. Provider view changes apply shared field/button/scroll presentation; business-service implementations were not rewritten.

## Verification

- Regression run: 191 tests in 13 suites pass. The existing live native-Dock and performance captures remain opt-in and skipped.
- Release build targets macOS 13 and includes arm64 and x86_64 slices.
- Xcode project regenerated to include the development render utility.
- Development render matrix covers editor at 900/1160/1440 widths; gallery at 760/960/1200; all seven Settings pages at both 900 and 1160 widths; dark/light layouts; onboarding steps; gallery search/empty state; editor empty state; About; and Clock, Focus Timer and Sticky Note popout content.
- Rendered layouts were inspected and refined for gallery density, consistent item baselines, section/control alignment and viewport fitting.

The DEBUG render utility uses an isolated store, sample widget cards and configuration content. It flattens scroll viewports for native view caching because AppKit scroll compositor output is unavailable offscreen. These images verify layout and content treatment, **not** native scroll, toolbar/window compositing, keyboard/VoiceOver or pointer interaction acceptance. The utility is excluded from the shipping release.

## Local artifacts

- `build/MyDockPremium.app` — local universal release build.
- `build/MyDockPremiumPreview.app` — isolated DEBUG preview; no production profile or Apple Dock changes. Requires macOS 14.
- `.build/premium-visual-qa/` — development layout renders.
- `.build/premium-redesign-baseline/` — preexisting UI source preserved before this task.

## Pending native acceptance

Unlock the Mac, then inspect the actual preview window, all Settings pages and scrolled sections, gallery category/search/add flows, preset/link/configuration sheets, profile actions and confirmations. Verify minimum/medium/large window chrome, native focus/tab/VoiceOver, hover/pressed states and drag/drop behavior. The implementation is buildable, but the requested on-screen visual QA cannot be signed off while the Mac remains locked.
