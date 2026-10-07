# Installing a local MyDock build

MyDock currently ships as an ad-hoc signed development bundle. It is not Developer ID signed or notarized. Manual release discovery and **Launch at login** are implemented; their installed/signed acceptance is pending.

## Build and launch

MyDock **runs on** macOS 13 or later; the Liquid Glass styles need macOS 26 and fall back to a frosted material on earlier systems. It **builds with** Swift 6 and the macOS 26 SDK, which comes with Xcode 26 or Command Line Tools 26 (these need a Mac that supports them); `./BuildMyDock.sh` stops with a clear message on an older SDK. `./TestMyDock.sh` also needs Swift Testing, which it finds in either the Command Line Tools or the Xcode layout. The build script compiles arm64 and x86_64 slices and combines them into a universal app bundle:

```sh
./BuildMyDock.sh
open build/MyDock.app
```

The built app is `build/MyDock.app` in the repository, with a minimum system version of macOS 13. To install it for the current user, copy that bundle to `~/Applications`; to install it for all users, copy it to `/Applications` using Finder. Launch it from Applications or with `open ~/Applications/MyDock.app`.

Use **`build/MyDock.app`** for all ongoing local development. It contains the latest redesign, audit and replacement/gallery fixes. Quit MyDock before rebuilding, then reopen the same path. The script refuses to overwrite a running bundle; launching a second copy exits before it opens the shared profile store or manages Apple's Dock. Do not create separately named candidate apps under `build/`. Isolated validation bundles can use `--output .build/visual-qa/MyDock.app` when needed. Older bundles are recoverably archived outside the repository; see [the archive index](history/README.md). Exact build checks are recorded in [canonical build evidence](RELEASE_AUDIT.md) and remaining acceptance in [the implementation status](IMPLEMENTATION_STATUS.md).

The local bundle is ad-hoc signed and not notarized. If Gatekeeper blocks this locally built app, use Finder's Open action and approve it in Privacy & Security. Do not remove quarantine from an app build you did not create or inspect.

## Updates and removal

Quit the copy you are replacing, then rebuild its bundle to update. Profile data is stored separately in `~/Library/Application Support/MyDock/state.json`; removing the app does not delete that data. To remove saved profiles too, quit MyDock and delete the `MyDock` folder from Application Support.

## Signing for wider distribution

For distribution outside this machine, sign the app with an Apple Developer ID certificate and notarize it. The ad-hoc signature produced by the build script is only for local development. The Xcode project's Release configuration enables the hardened runtime and includes an Apple Events entitlement; it still needs a full Xcode build, Developer ID signing, notarization, and final behavior checks. The manual update checker opens a validated publisher release page; it does not download or replace the app executable.

The repository also includes [an Xcode project and Focus filter build guide](XCODE_BUILD.md) for a full Xcode toolchain and Developer ID signing.

See [permissions and data handling](PERMISSIONS.md) before enabling features that require additional system access.

## Publisher distribution pipeline

With full Xcode selected and XcodeGen available, run:

```sh
./ReleaseMyDock.sh "Developer ID Application: Publisher (TEAMID)" notary-keychain-profile ../MyDock-releases/0.1.0
```

Use a fresh distribution output directory outside the repository; keep `build/` for the canonical development app. The script builds with full Xcode, requires extracted App Intents metadata, checks both architectures, signs with the hardened runtime and Apple Events entitlement, verifies the signature, submits/staples the app and DMG, assesses Gatekeeper and writes a SHA-256 checksum. A named notarization credential must already be stored in Keychain. No signing identity, account credentials or notarization success is supplied by this repository.

Settings → General → Application → **Launch at login** can register the installed app with Login Items and open approval settings when needed. Put the app in a stable Applications location before testing this. Update discovery requires the actual publisher's HTTPS GitHub repository URL and runs only on request. No release repository is configured by default. Open acceptance is in [the implementation status](IMPLEMENTATION_STATUS.md).
