# Installing a local MyDock build

MyDock currently ships as an ad-hoc signed development bundle. It is not Developer ID signed or notarized, and there is no updater.

## Build and launch

On macOS 13 or later with Swift 6 and Apple's Command Line Tools available. The build script compiles arm64 and x86_64 slices and combines them into a universal app bundle:

```sh
./BuildMyDock.sh
open build/MyDock.app
```

The built app is `build/MyDock.app` in the repository, with a minimum system version of macOS 13. To install it for the current user, copy that bundle to `~/Applications`; to install it for all users, copy it to `/Applications` using Finder. Launch it from Applications or with `open ~/Applications/MyDock.app`.

The verified September 27 release is also saved as `build/MyDock-Release.app` and `build/MyDock-Release.zip`. To build a separate bundle while another copy is open, run `./BuildMyDock.sh --output build/MyDock-Release.app`. The script refuses to overwrite a bundle that is running. Quit the older copy before opening the new release; if an older MyDock is still active, the new copy exits without opening the shared profile store or managing Apple's Dock.

The local bundle is ad-hoc signed and not notarized. If Gatekeeper blocks this locally built app, use Finder's Open action and approve it in Privacy & Security. Do not remove quarantine from an app build you did not create or inspect.

## Updates and removal

Quit the copy you are replacing, then rebuild its bundle to update. Profile data is stored separately in `~/Library/Application Support/MyDock/state.json`; removing the app does not delete that data. To remove saved profiles too, quit MyDock and delete the `MyDock` folder from Application Support.

## Signing for wider distribution

For distribution outside this machine, sign the app with an Apple Developer ID certificate and notarize it. The ad-hoc signature produced by the build script is only for local development. The Xcode project's Release configuration enables the hardened runtime and includes an Apple Events entitlement; it still needs a full Xcode build, Developer ID signing, notarization, and final behavior checks. There is no updater.

The repository also includes [an Xcode project and Focus filter build guide](XCODE_BUILD.md) for a full Xcode toolchain and Developer ID signing.

See [permissions and data handling](PERMISSIONS.md) before enabling features that require additional system access.
