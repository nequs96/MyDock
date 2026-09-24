# Real Apple Dock test plan

This test changes the current user's Apple Dock layout and restarts Dock. Run it only after explicit approval, with the Mac unlocked and the user present. Automated tests use fake preferences and do not replace this plan.

## Before applying a profile

1. Close MyDock and confirm no other Dock customization is in progress.
2. In MyDock, use **Create from Current Dock** to save a native profile named `Before MyDock Dock Test`. Save it and inspect the captured app/spacer order.
3. Record the current `com.apple.dock` `persistent-apps` and `autohide` values, including whether either key is absent. Keep that snapshot until restoration is verified.
4. Create a temporary native profile with a few already-installed apps, one regular spacer, and one small spacer. Do not add, remove, or move apps outside this temporary profile.

## Exercise native apply and restore

1. Apply the temporary profile once. Dock will restart and its pinned items/spacers will change temporarily.
2. Confirm the visible order and both spacer sizes. Launch one app from the Dock, then return to MyDock.
3. Apply `Before MyDock Dock Test` to restore the original Dock layout.
4. Compare the resulting `persistent-apps` value and visible Dock order with the pre-test snapshot. Stop if they differ.

## Exercise Custom-main auto-hide recovery

1. Select a temporary Custom Dock profile and enable Custom-main mode.
2. Confirm Apple's Dock auto-hides while MyDock is active.
3. Turn Custom-main mode off. Confirm the original `autohide` value and key-presence state are restored.
4. If approved as part of the same run, repeat with MyDock quitting while Custom-main is active; relaunch MyDock and confirm its recovery record restores the prior setting.

## Rollback

- If an apply fails, let MyDock complete its transactional rollback and compare the preference snapshot before continuing.
- If the Dock layout is still different, reapply `Before MyDock Dock Test`. If that does not restore the exact `persistent-apps` value, restore only the saved Dock preference values and restart Dock while MyDock is closed.
- If `autohide` is still different, use the saved value; if the key was originally absent, remove the key rather than writing `false`.
- Stop further tests and keep the snapshot if either setting cannot be restored exactly.

## Approval scope

Approval should cover the temporary profile apply/reapply and, separately, the Custom-main auto-hide/quit recovery steps. No live provider credentials, screen capture, or changes to unrelated Dock preferences are part of this test.
