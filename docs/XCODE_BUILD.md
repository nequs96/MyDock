# Xcode app build and Focus filter verification

The repository includes `MyDock.xcodeproj` and its XcodeGen specification, `project.yml`. The checked-in project references the same Swift sources and unit-test files as the Swift package, including `FocusDockFilterIntent.swift`, and includes the original `AppIcon.icns`. `GenerateXcodeProject.sh` reads the product name, bundle identifier, and version from `Sources/MyDock/Core/Product.swift` before regenerating the project.

## Build with full Xcode

1. Install a current full Xcode from Apple and select it with `xcode-select`. Command Line Tools alone cannot run `xcodebuild` or Xcode's App Intents metadata processor.
2. If XcodeGen is not installed, run `brew install xcodegen`.
3. Run `./GenerateXcodeProject.sh`, then open `MyDock.xcodeproj` and select the shared **MyDock** scheme.
4. Build the Release configuration. The project starts with an ad-hoc signing identity for local use. Release enables the hardened runtime and includes only the Apple Events entitlement needed to request access to Music, Spotify, and Finder. For distribution, select your Developer ID team and signing identity, then archive, notarize, and staple the app with your Apple credentials. Verify the signed entitlement and Apple Event permission flow on the final build.
5. Run the **MyDock** scheme's Test action to execute the unit-test target. Its Debug-only `MYDOCK_UNIT_TEST_HOST=1` environment flag makes the app host return before loading profiles, taking the single-instance lock, or managing Apple's Dock. The project and scheme are generated here, but Xcode test execution remains unverified until full Xcode is available.
6. Once the Mac is unlocked, run the separate **MyDock Visual QA** scheme. Its UI tests launch only the Debug visual-preview path with a disposable per-process store and retain screenshots of Manager, Settings, bottom/left/right Dock layouts, light/dark appearance, and a long Countdown layout in the test result. Review those captures against matched Dockset references at the same display scale. The UI tests have been syntax-checked and wired into the generated scheme, but have not run here because full Xcode is unavailable. Current manual CUA preview checks are recorded in the implementation ledger.

For ongoing local use, build and launch `build/MyDock.app` with `./BuildMyDock.sh`. Xcode uses the same sources and produces its own development intermediates in DerivedData. The SwiftPM bundle does not establish that a Focus filter is registered because this machine has only Command Line Tools; see [canonical build evidence](RELEASE_AUDIT.md). Older candidate bundles are archived and are not development baselines.

## Focus filter acceptance

Apple documents that App Intents metadata is placed in the app or extension bundle at build time and used by the system to discover and run the intent. The intent can live in the app bundle; Apple's sample uses an App Intents extension for background execution. See [runtime behavior](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents) and the [Focus filter sample](https://developer.apple.com/documentation/AppIntents/defining-your-app-s-focus-filter).

After an Xcode build, quit older MyDock copies and launch the new app. In System Settings → Focus, add a MyDock filter, select a saved Custom Dock profile, and enable that Focus. Confirm the profile changes. Disable the Focus and confirm the last profile remains selected. Repeat with a native profile only under the separately approved real Dock test plan. Inspect the built app's App Intents metadata and Xcode build log if MyDock does not appear in the Focus filter list.

This project file, generated Info.plist, and Apple Events entitlement pass XcodeGen generation and `plutil` validation here. A full Xcode compile, Focus discovery, background invocation, hardened-runtime behavior, Developer ID signature, and notarization remain unverified until the required toolchain, desktop acceptance, and signing identity are available.

Use [the implementation ledger](IMPLEMENTATION_STATUS.md) for the current build and test evidence. `ReleaseMyDock.sh` requires full Xcode and checks extracted App Intents metadata before signing; a SwiftPM app bundle cannot establish Focus metadata discovery.
