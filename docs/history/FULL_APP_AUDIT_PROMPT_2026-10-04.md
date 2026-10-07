# MYDOCK — COMPLETE APPLICATION AUDIT

Audit the entire MyDock application and produce a precise, evidence-based breakdown of its current quality, defects, risks, unfinished behavior and opportunities for improvement.

This is an AUDIT, not an implementation task.

Do not write application code, redesign screens, implement fixes, commit changes or publish anything. Produce findings and recommendations only. You may create audit reports and disposable validation artifacts.

Do not assume previous work is complete because a report says “implemented,” tests pass or the app builds. Verify what the current source and running application actually do.

The goal is to understand:

1. What works correctly.
2. What is broken or incomplete.
3. What looks or behaves poorly.
4. What is unnecessarily complicated.
5. What could be more useful to users.
6. What should be improved first, and why.
7. What evidence is still missing.

## PROJECT AND WORKING RULES

Repository:

`/Users/jakubjalowiecki/Documents/ChatGPT/dockX`

Read the applicable AGENTS.md instructions before starting.

Continue from the current Sources/MyDock/ working tree. Preserve staged, unstaged and untracked work. Do not reset files, clean the repository or replace source with files from an app bundle.

Read:

- docs/RELEASE_AUDIT.md
- docs/IMPLEMENTATION_STATUS.md
- docs/history/BUILD_BASELINE_2026-10-04.json (the last recorded source fingerprint, dated)
- Relevant reports under docs/history/

Treat those documents as leads and historical evidence, not proof that the current application passes acceptance.

The canonical application is build/MyDock.app.
The canonical build command is ./BuildMyDock.sh.
Use ./TestMyDock.sh for relevant tests.

Generated app bundles, SwiftPM products and DerivedData are not source baselines.

Never overwrite or move a running app bundle. If a build is necessary, quit the target cleanly, preserve drafts and allow MyDock to restore its owned system preferences. If this cannot be done, continue independent audit work and record the blocker.

Disposable validation bundles belong under .build/visual-qa/. Do not create additional named candidate builds under build/.

Do not modify or delete user Application Support data, credentials, saved profiles or integrations. Use isolated temporary state for mutation scenarios.

Do not apply or replace the user’s macOS Dock, grant new permissions, connect accounts, transfer files, send messages or exercise destructive features merely to complete an audit. Use safe fixtures or explicitly isolated scenarios where appropriate.

Do not request real credentials. Audit provider behavior through existing contracts, tests, recorded evidence and safe fixtures unless a live scenario is already authorized.

Write dated audit reports under docs/history/. Keep recommendations separate from implemented behavior.

## EVIDENCE STANDARD

For every important conclusion, identify whether it is supported by:

- Current source inspection.
- Automated tests.
- A current runtime observation.
- A screenshot or render.
- Historical evidence.
- An inference.
- An unverified assumption.

Do not confuse these categories.

A passing build does not prove correct behavior.
A passing unit test does not prove correct native integration.
A bitmap render does not prove actual desktop compositing.
A source implementation does not prove the feature is usable.
A tool failure does not prove an application defect.

If CUA or another inspection tool fails:

- Record the exact failure.
- Continue all independent checks.
- Mark affected runtime scenarios as unverified.
- Provide a concrete manual verification procedure.
- Do not claim those scenarios passed.

Do not invent observations, performance measurements, screenshots, line numbers or test results.

Do not create an arbitrary number of findings. Report all supported findings, including serious issues hidden behind apparently successful features.

## 1. INVENTORY THE ENTIRE APPLICATION

Start by establishing the actual current architecture and feature inventory.

Inspect:

- Sources/MyDock/
- Tests/
- Resources/
- Tools/
- Package.swift
- BuildMyDock.sh
- TestMyDock.sh
- Xcode project and plist configuration
- CI and release workflows
- Relevant documentation

Identify:

- Application entry points and lifecycle.
- Main windows, menu bar UI and onboarding.
- Dock controller, render model and window hosting.
- Profile management and edit sessions.
- Settings and profile-specific appearance.
- Widget registry and every registered provider.
- Persistence, backups, history and recovery.
- External integrations and credential storage.
- Native macOS services and permissions.
- Background jobs, monitoring and refresh ownership.
- Build, test and distribution tooling.

Discover the current widget count and feature list from source. Do not assume an earlier count remains accurate.

Produce an architecture map explaining ownership and data flow. Focus on where state originates, changes, persists and reaches the UI.

Identify duplicated ownership, unexpected coupling, circular dependencies and components with too many responsibilities.

## 2. COMPLETE FEATURE AND ACCEPTANCE COVERAGE

Create a coverage matrix for every user-facing feature and widget family.

For each entry, record:

- Entry point.
- Expected behavior.
- Relevant source.
- Existing automated coverage.
- Runtime checks performed.
- Empty/loading/error/offline behavior.
- Permission dependencies.
- Persistence expectations.
- Current status.
- Remaining acceptance.

Use clear statuses:

- Verified.
- Implemented but runtime-unverified.
- Partially implemented.
- Defective.
- Blocked by environment or tooling.
- Not applicable.

Do not label something verified solely because its view or method exists.

Follow each significant feature through the complete path:
user action → state change → service/native operation → persistence → UI feedback → relaunch behavior.

## 3. DOCK FUNCTIONALITY AND MACOS EXPECTATIONS

Audit MyDock as an actual Dock, not only as a collection of views.

Check:

- Launching apps.
- Activating already running apps.
- Restoring minimized windows.
- Window selection when several windows belong to one app.
- Running versus pinned app representation.
- Keep in Dock and Remove from Dock.
- Close Window and Quit App menu discoverability.
- Correct distinction between closing a window and quitting an application.
- Unsaved-document dialogs and cancelled quit requests.
- Stale window descriptors and process identity changes.
- Multiple installed copies of an application.
- Finder and other unusual application lifecycle behavior.
- File, folder and website opening.
- Missing or moved targets and Locate recovery.
- Dragging to reorder.
- Insertion positions, separators, groups and empty areas.
- Dragging from Finder or another application.
- Dragging items outward where supported.
- Overflow scrolling and navigation.
- Long-press, right-click, hover and click-outside behavior.
- Popout focus, dismissal and multiple open popouts.
- Auto-hide, reveal handles and screen-edge activation.
- Fullscreen apps, Spaces and Mission Control.
- Interaction with the Apple Dock.
- Desktop-widget mode.
- Multiple displays and display disconnection.

Compare relevant behavior with the normal macOS Dock where useful. Distinguish:

- A defect.
- An intentional product difference.
- A platform limitation.
- A reasonable future enhancement.

Do not demand private APIs or promise perfect Apple Dock parity where macOS does not support it.

## 4. DOCK RESIZING AND INTERACTION PERFORMANCE

Investigate resizing in detail.

Check:

- Pointer tracking.
- Bottom, left and right positions.
- Minimum and maximum sizes.
- Stable screen-edge anchoring.
- Layout changes during dragging.
- Whether gestures survive view updates.
- Whether the hosting root is unnecessarily replaced.
- Whether monitors restart during resizing.
- Whether persistence or history writes occur per pointer event.
- Icon loading and caching at fractional sizes.
- SwiftUI and AppKit animation interactions.
- Overflow controls appearing or disappearing mid-drag.
- Resize completion, cancellation and interruption.
- Double-click reset.
- Accessibility adjustment.
- Global versus profile-specific size inheritance.

Where runtime tools permit, measure:

- Main-thread work.
- Frame pacing and visible stutter.
- Event-to-presentation latency.
- CPU and memory during continuous resizing.
- Persistence writes during a drag.
- Behavior on the actual display refresh rate.

State the measurement method and environment. Do not describe resizing as “smooth” without observing or measuring it.

## 5. ANIMATIONS AND MOTION

Audit every Dock animation and related setting.

Check:

- On/off behavior.
- Fade, Slide and Gentle Grow, or whichever styles currently exist.
- Preview controls.
- Initial activation.
- Auto-hide reveal and dismissal.
- Profile switching.
- Interrupted and rapidly reversed transitions.
- Repeated preview requests.
- Frame changes versus composited transforms.
- Unexpected layout reflow during animation.
- Stale transforms after style changes.
- Hit testing during or after animations.
- Animation ownership and cancellation.
- Reduce Motion.
- Interaction with resizing and magnification.

Assess whether motion is restrained, useful and native in character.

Recommend additional effects only if they improve understanding or feedback. Do not propose decorative motion merely to increase the number of options.

## 6. VISUAL DESIGN OF THE ENTIRE APP

Inspect every major screen, sheet, popover, menu and empty state.

Audit:

- Main Dock workspace.
- Profile sidebar and profile editor.
- Add Item/library.
- Widget configuration.
- Standalone and embedded Settings.
- Onboarding.
- Connections.
- Permissions.
- Backup, history and recovery.
- Error and confirmation dialogs.
- The activated Dock itself.

Evaluate:

- Information hierarchy.
- Density and spacing.
- Alignment and consistency.
- Typography and text scaling.
- Contrast and muted text.
- Materials, borders and shadows.
- Corner geometry.
- Control sizing.
- Selection and focus states.
- Label clarity.
- Discoverability.
- Scrolling behavior.
- Small-window layouts.
- Long names and large values.
- Light, dark and system appearance.
- Appropriate use of native macOS controls.

Identify concrete examples of generic or artificial-looking UI:

- Oversized empty cards.
- Repetitive identical rectangles.
- Large centered decorative icons.
- Excessive padding.
- Unnecessary gradients or glows.
- Weak hierarchy.
- Controls that look decorative rather than interactive.
- Important actions hidden behind ambiguous symbols.

For each visual finding, explain:

- What the user sees.
- Why it harms clarity or usability.
- What a better arrangement would accomplish.
- How it can preserve MyDock’s existing visual language.

Avoid vague recommendations such as “make it modern” or “improve polish.”

## 7. MATERIALS AND LIQUID GLASS

Inspect the real activated Dock and its configuration previews separately.

Check:

- Clear and Frosted finishes.
- Continuous glass-opacity behavior across its entire range.
- Whether opacity and tint are independent.
- Global and profile-specific appearance.
- Saved appearance and migration.
- Light/dark/system behavior.
- Wallpaper-dependent readability.
- Reduce Transparency and increased contrast.
- Fallbacks on older supported macOS versions.
- Native glass compositing versus bitmap-render limitations.
- Transparent window backing.
- Rounded corner masks.
- Shadows or rectangular halos outside the Dock.
- Material behavior while resizing, revealing or changing profiles.
- Consistency between the settings preview and actual Dock.

Verify the user-facing meaning of values and labels. For example, a control labeled “Opaque” should produce the behavior that label promises.

Do not mistake a static preview for evidence of actual wallpaper blur or refraction.

## 8. ADAPTIVE WIDGET PRESENTATION

Audit every widget’s Dock face and configuration screen.

Verify that:

- Layout and icon appearance are independent.
- Widgets offer meaningful variants appropriate to their data.
- Width adapts to content while Dock height remains coherent.
- Different information types have different compositions.
- Metrics dominate decorative icons.
- Units read as part of their metric.
- Secondary information justifies occupied width.
- Micro visualizations are useful and restrained.
- Side-Dock representations remain readable.
- Hover does not introduce excessive scaling or glow.
- Configuration previews update correctly.
- Layout choices represent their real dimensions.
- Icon swatches change only icon treatment.
- Legacy configuration values migrate safely.

Specifically inspect:

- AI Activity and AI Limits.
- CPU/system activity.
- Memory, network, disk and battery where available.
- Weather.
- Media.
- Clock/calendar/reminders.
- Timers, alarms and local productivity tools.
- Business and market widgets.
- Every newly added utility widget.

Do not invent limits, totals, temperatures, sessions, history or other metrics that the application does not know.

## 9. WIDGET USEFULNESS AND COMPLETENESS

For every widget, assess:

- The actual user problem it solves.
- Whether it is useful at Dock scale.
- Whether its primary action is obvious.
- Whether its popout provides useful additional capability.
- Whether configuration is meaningful.
- Whether it duplicates another widget unnecessarily.
- Whether its empty state helps the user begin.
- Whether permissions or setup requirements are clearly explained.
- Whether it behaves correctly with stale or unavailable data.
- Whether its stored content survives relaunch.

For File Shelf, snippets, links, conversion, color and similar tools, inspect:

- Input validation.
- Editing and deletion.
- Clipboard behavior.
- File references and security-scoped bookmarks where applicable.
- Deduplication.
- Collection limits.
- Missing-file handling.
- Sharing and drag/drop contracts.
- Accurate conversions and formatting.
- Clear user feedback.

Suggest useful new widgets only after assessing gaps in the existing inventory. For each suggestion, provide a specific use case, minimum useful scope, required data/permissions and likely implementation cost.

## 10. STATE, PERSISTENCE AND MIGRATION

Audit:

- Codable models and default values.
- Schema compatibility.
- Legacy widget and appearance decoding.
- Import validation.
- Finite and bounded numeric values.
- Duplicate identifiers.
- Stale references.
- Atomic writes and writer serialization.
- Debouncing and write frequency.
- Ordering of asynchronous writes.
- Error reporting and retry.
- Draft survival.
- Save/Discard/Cancel flows.
- Undo and history.
- Profile switching during unsaved edits.
- Concurrent changes and merge conflicts.
- App termination and relaunch.
- Recovery after interrupted or failed writes.
- Backup sanitization and restoration.
- Future-version data handling.

Look for paths that can:

- Lose edits.
- Overwrite newer state.
- Silently reset configuration.
- Corrupt saved profiles.
- Restore deleted content.
- Save incomplete data.
- Expose private data in exports or logs.

Do not test corruption or recovery against the user’s actual saved state.

## 11. SERVICES, BACKGROUND WORK AND CONCURRENCY

Treat local services as the application’s backend.

Inspect:

- Refresh coordination and ownership.
- Polling intervals.
- Visible versus hidden Dock behavior.
- Duplicate work.
- Task cancellation.
- Stale callback protection.
- Main-actor isolation.
- Thread safety.
- Observer lifecycle.
- Timer lifecycle.
- Subprocess deadlines and output bounds.
- Hung external applications.
- Network request deadlines.
- Retry and backoff.
- Cache freshness and invalidation.
- Resource cleanup.
- Sleep/wake behavior.
- Time-zone and date changes.

Identify services that continue expensive work when the Dock is hidden or the relevant widget is absent.

## 12. EXTERNAL PROVIDERS AND DATA CORRECTNESS

Audit each provider integration independently.

Check:

- Authentication and credential replacement.
- Credential storage.
- Token refresh.
- Revocation and disconnection.
- Request construction.
- Response parsing.
- Pagination where applicable.
- Rate limits.
- Partial results.
- Offline behavior.
- Stale saved data.
- Time ranges and boundaries.
- Time zones.
- Currency and unit handling.
- Usage aggregation and double counting.
- Provenance and freshness indicators.
- Whether displayed claims match actual available data.

Verify AI usage and limit calculations carefully. Identify differences between local history, provider billing, token totals and actual usage limits.

If live provider validation is unavailable, state exactly which contracts were inspected and which account-dependent scenarios remain open.

## 13. NATIVE MACOS INTEGRATIONS AND PERMISSIONS

Inspect:

- Accessibility.
- Automation.
- Screen Recording.
- Calendar and Reminders.
- Location.
- Notifications.
- Login items.
- Finder, AirDrop and sharing services.
- Music/Spotify or other media controls.
- Native window management.
- Apple Dock preference ownership and restoration.

Check:

- When permission is requested.
- Whether the explanation is understandable.
- Behavior when access is denied or revoked.
- Whether unrelated features remain usable.
- Whether repeated requests are avoided.
- Whether recovery instructions are accurate.
- Whether native operations are bounded and off the main thread where appropriate.

For system-preference changes, examine transaction boundaries, recovery records, interruption handling and restoration on quit.

## 14. SECURITY AND PRIVACY

Perform a threat-oriented review appropriate to a local macOS utility.

Inspect:

- Keychain usage.
- Credentials in files, logs, exports or diagnostics.
- Network destinations.
- Unexpected telemetry.
- Backup contents.
- Clipboard access.
- File bookmarks and references.
- URL and path validation.
- Imported data size limits.
- Subprocess arguments and command injection.
- Temporary files.
- Permissions and entitlements.
- Dependency provenance.
- Update-download validation.
- Error messages exposing sensitive content.

Distinguish confirmed vulnerabilities from hardening suggestions and hypothetical risks.

For each material security finding, provide the actual entry point, preconditions, impact and evidence.

## 15. ACCESSIBILITY AND INPUT METHODS

Audit:

- Accessibility names, roles and values.
- Selected-state announcements.
- Keyboard navigation.
- Focus order.
- Focus restoration after sheets/popouts close.
- Escape behavior.
- Reachability of controls in small windows.
- VoiceOver where available.
- Contrast.
- Reduce Motion.
- Reduce Transparency.
- Increased contrast.
- Text truncation and scaling.
- Pointer target sizes.
- Discoverability without tooltips.
- Consistent shortcuts and menu actions.

Do not claim VoiceOver acceptance from accessibility identifiers alone.

## 16. RELIABILITY AND EDGE CASES

Check representative scenarios involving:

- Empty profiles.
- Very large profiles.
- Repeated items.
- Many widgets.
- Missing applications and files.
- Multiple app versions.
- Long titles and large metrics.
- No network.
- Provider errors.
- Denied permissions.
- Sleep/wake.
- Display changes.
- Fullscreen/Spaces.
- Quit during pending work.
- Relaunch after interruption.
- Draft conflicts.
- Failed persistence.
- Rapid repeated interactions.

For each scenario, explain expected behavior and how it was checked.

## 17. PERFORMANCE AND RESOURCE USE

Assess:

- Startup time.
- Main-window responsiveness.
- Dock reveal latency.
- Resize and hover frame pacing.
- Memory growth.
- CPU while visible, hidden and idle.
- Background network activity.
- Disk write frequency.
- Icon and preview caches.
- Large-profile scaling.
- Provider refresh concurrency.
- Energy impact.
- Observer, task and timer leaks.

Use reproducible measurements where tools permit. Record hardware, OS, display refresh rate, workload, duration and measurement method.

Do not substitute a synthetic geometry test for production FPS or energy evidence.

## 18. TEST QUALITY AND RELEASE READINESS

Audit the tests themselves.

Identify:

- Meaningful behavioral coverage.
- Tests that merely repeat implementation details.
- Missing failure-path tests.
- Missing integration/native UI coverage.
- Flaky timing assumptions.
- Test isolation problems.
- Skipped opt-ins and what they leave unverified.
- Whether documented claims exceed test evidence.

Inspect:

- Supported OS targets.
- Universal architecture configuration.
- SDK and deployment settings.
- App identity and bundle metadata.
- Code signing.
- Entitlements.
- CI.
- Release packaging.
- Notarization and distribution readiness.
- Update and login-item behavior.
- Documentation accuracy.

Separate “local development build passes” from “ready for distribution.”

## 19. IMPROVEMENT OPPORTUNITIES

After completing the audit, recommend improvements in these categories:

- Correctness and reliability.
- Native Dock functionality.
- Performance.
- Design and information architecture.
- Accessibility.
- Widget usefulness.
- Provider/data accuracy.
- Architecture and maintainability.
- Security/privacy.
- Testing and release readiness.

Do not recommend a wholesale rewrite without concrete evidence that targeted changes are inadequate.

For each recommendation, explain:

- The user benefit.
- The current problem.
- The smallest coherent change.
- Affected components.
- Dependencies.
- Migration requirements.
- Regression risk.
- How success should be verified.
- Relative effort.

Separate required fixes from optional product enhancements.

## 20. REQUIRED FINAL REPORT

Produce a complete report with the following structure.

### A. Executive assessment

- Current quality and readiness.
- Most important confirmed problems.
- Most important unverified areas.
- Strengths worth preserving.
- Whether current documentation overstates completion.

### B. Architecture and feature inventory

- Component ownership and data flow.
- Complete feature/widget coverage matrix.

### C. Detailed findings

Group by audit area. Give every finding a stable identifier.

For every finding include:

- ID and concise title.
- Category.
- Severity: Critical / High / Medium / Low.
- Priority: P0 / P1 / P2 / P3.
- Confidence: Confirmed / Strong inference / Needs verification.
- User impact.
- Relevant file and verified line number, where applicable.
- Reproduction steps or triggering conditions.
- Expected behavior.
- Actual observed behavior.
- Supporting evidence.
- Likely cause, clearly separated from observation.
- Recommended direction.
- Verification needed after a future fix.
- Dependencies or regression risks.

Do not assign Critical or P0 casually:

- P0: immediate serious failure, data loss or material security exposure.
- P1: important broken behavior or major usability/performance problem.
- P2: meaningful improvement or narrower defect.
- P3: lower-impact refinement or optional enhancement.

### D. Design breakdown

For each major screen and the activated Dock:

- Specific problems.
- Visual hierarchy and density assessment.
- Discoverability problems.
- Material/typography/spacing issues.
- Recommended design direction.
- What should remain consistent with the existing app.
- Relevant current screenshots/renders, if available.

### E. Backend and native-integration breakdown

- State/persistence.
- Concurrency/background services.
- Providers and data accuracy.
- Permissions/native APIs.
- Security/privacy.
- Failure and recovery paths.

### F. Prioritized improvement plan

Provide a table containing:

- Finding IDs.
- Proposed work package.
- User outcome.
- Priority.
- Relative effort: Small / Medium / Large.
- Dependencies.
- Acceptance criteria.

Arrange the plan into:

1. Immediate corrective work.
2. Next quality/reliability pass.
3. Design and usability improvements.
4. Longer-term product opportunities.

Do not give precise hour estimates without sufficient evidence.

### G. Verification ledger

List:

- Commands executed and outcomes.
- Tests passed/failed/skipped.
- Runtime scenarios actually checked.
- Renders/screenshots inspected.
- Tool failures.
- Historical evidence used.
- Scenarios not checked.
- Explicit reasons for each important gap.

### H. Manual acceptance checklist

Provide precise steps for the remaining native scenarios, especially:

- Close Window and Quit App with unsaved content.
- Smooth resizing on bottom/left/right Docks.
- Glass opacity and rounded corners over real wallpaper.
- Animation selection, Off and interrupted transitions.
- Settings navigation in small windows.
- Finder/AirDrop/clipboard/color sampling.
- Accessibility and permission recovery.

### I. Final completeness statement

State exactly what was audited and what remains unknown.

Do not conclude “everything is complete” unless the evidence supports that claim.

## FINAL EXPECTATION

I want a rigorous review of the real application, not a generic software checklist, a cosmetic critique or a report that simply repeats existing documentation.

Be precise, skeptical and fair.

Explain concrete problems in language a product owner can understand, while providing enough source and runtime evidence for a developer to act on them.

Finish the entire audit that can be completed safely. If an area is blocked, explain the specific blocker and still complete the other areas.

Do not implement the recommendations.
