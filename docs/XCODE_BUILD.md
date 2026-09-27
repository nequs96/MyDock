# Xcode app build and Focus filter verification

The repository includes `MyDock.xcodeproj` and its XcodeGen specification, `project.yml`. The checked-in project references the same Swift sources as the Swift package, including `FocusDockFilterIntent.swift`, and includes the original `AppIcon.icns`. `GenerateXcodeProject.sh` reads the product name, bundle identifier, and version from `Sources/MyDock/Core/Product.swift` before regenerating the project.

## Build with full Xcode

1. Install a current full Xcode from Apple and select it with `xcode-select`. Command Line Tools alone cannot run `xcodebuild` or Xcode's App Intents metadata processor.
2. If XcodeGen is not installed, run `brew install xcodegen`.
3. Run `./GenerateXcodeProject.sh`, then open `MyDock.xcodeproj` and select the shared **MyDock** scheme.
4. Build the Release configuration. The project starts with an ad-hoc signing identity for local use. Release enables the hardened runtime and includes only the Apple Events entitlement needed to request access to Music, Spotify, and Finder. For distribution, select your Developer ID team and signing identity, then archive, notarize, and staple the app with your Apple credentials. Verify the signed entitlement and Apple Event permission flow on the final build.

The existing `./BuildMyDock.sh --output build/MyDock-Release.app` path remains the verified local universal build. It does not establish that a Focus filter is registered because this machine has only Command Line Tools.

## Focus filter acceptance

Apple documents that App Intents metadata is placed in the app or extension bundle at build time and used by the system to discover and run the intent. The intent can live in the app bundle; Apple's sample uses an App Intents extension for background execution. See [runtime behavior](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents) and the [Focus filter sample](https://developer.apple.com/documentation/AppIntents/defining-your-app-s-focus-filter).

After an Xcode build, quit older MyDock copies and launch the new app. In System Settings → Focus, add a MyDock filter, select a saved Custom Dock profile, and enable that Focus. Confirm the profile changes. Disable the Focus and confirm the last profile remains selected. Repeat with a native profile only under the separately approved real Dock test plan. Inspect the built app's App Intents metadata and Xcode build log if MyDock does not appear in the Focus filter list.

This project file, generated Info.plist, and Apple Events entitlement pass XcodeGen generation and `plutil` validation here. A full Xcode compile, Focus discovery, background invocation, hardened-runtime behavior, Developer ID signature, and notarization remain unverified until the required toolchain, desktop acceptance, and signing identity are available.
