# Focus handoff — 1 October 2026

## Current coordination state

The user confirmed that another session is still editing this repository. This session stopped competing source edits, builds and native actions. Its latest build session was interrupted normally (exit 130); no app was forcibly terminated or running bundle overwritten. The other session's `.build/visual-qa/focused-interaction/MyDock.app` was observed running and was left untouched.

The earlier 74-layout/accessibility baseline is dated evidence, not proof that the changing current worktree matches its canonical binary. Do not promote a new integrated baseline until a stable-source canonical build, launch and acceptance pass finish.

## Changes left for integrated validation

- `DockCanvas` now carries an ephemeral item/request focus identity. Ending a drag clears the old focus and requests the current cursor after SwiftUI registers its new binding. The task cancels on profile/request changes; persisted models and semantic animation identity are unchanged.
- `DockCanvasDragView` selects a previously unselected single item when a valid drop completes. A successful reorder hands focus back through SwiftUI; cancelled/rejected drags restore the previous native responder. This avoids trying to restore a responder replaced by the reorder.
- The native pointer regression checks selection transfer, group preservation and cancelled-drop selection preservation.
- The rebuilt Xcode UI scenarios include end-drop/range-navigation/Undo. Full Xcode is unavailable; parser validation is not execution. The concurrent Add Library rewrite changes addition behavior, so its UI test must be reconciled before the suite is run.
- The incoming Add Library rewrite was preserved; its duplicated spacer label was corrected to use the model's existing human title.

## Evidence and limits

Native observations reproduced window-level focus after a selected Clock end drop; Undo still worked. Several synchronous focus-reset variants did not reliably restore keyboard routing. The latest native-responder/SwiftUI-task handoff has not passed controlled native acceptance: UI activity, preview restarts and source changes overlapped this pass. Do not claim the focus bug is fixed from compilation or unit checks alone.

The latest default run reports **237 tests in 17 suites passed**, in `.build/product-focus-tests.log`. This includes newly arriving app-discovery tests. It is an intermediate source snapshot; subsequent edits require revalidation. The earlier canonical rebuild succeeded, but the next integrated attempt failed because `AppleWidgetCard.swift` changed during compilation (`.build/product-focus-build-interrupted.log`). A further attempt encountered another SwiftPM build using the same cache and was cancelled (`.build/product-focus-build.log`).

## Resume order

1. Coordinate exclusive editing/build/native-QA ownership after the other session finishes.
2. Inspect the current tree and retain incoming scanner, library, widget and related changes. Resolve the Add Library test/interaction contract against the user's latest intended behavior.
3. Quit the canonical app and any preview being replaced through their normal save/quit paths; verify termination.
4. Run relevant tests, build `build/MyDock.app` with `./BuildMyDock.sh`, launch that same path, and verify the final source/binary association.
5. In an isolated store, test selected and unselected single-item end drops, groups, outside/Escape cancellation, immediate arrows/range navigation/Return/Delete/Undo, and focus metadata. Refine the candidate if any fail.
6. Continue external/empty/overflow drops, real resizing, accessibility/popouts, profile/add motion, then refresh the render matrix and current build evidence.

No profile migration, credential operation or native-Dock mutation test was performed in this handoff.
