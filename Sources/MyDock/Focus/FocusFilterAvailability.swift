import Foundation

/// Focus filter discovery needs the App Intents metadata that only an Xcode-built app bundle contains.
enum FocusFilterAvailability {
    static func hasIntentMetadata(bundleURL: URL = Bundle.main.bundleURL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        let metadata = bundleURL.appendingPathComponent("Contents/Resources/Metadata.appintents", isDirectory: true)
        return fileManager.fileExists(atPath: metadata.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static let availableGuidance = "In System Settings → Focus, choose a Focus, select Add Filter, then choose MyDock and a saved Dock profile. When that Focus turns off, MyDock leaves the last applied Dock selected."
    static let unavailableGuidance = "Focus filters are not available from this build of MyDock because it does not include App Intents metadata. They require the Xcode-built release app."

    static func guidance(bundleURL: URL = Bundle.main.bundleURL, fileManager: FileManager = .default) -> String {
        hasIntentMetadata(bundleURL: bundleURL, fileManager: fileManager) ? availableGuidance : unavailableGuidance
    }
}
