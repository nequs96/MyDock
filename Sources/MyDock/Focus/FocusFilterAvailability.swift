import Foundation

/// Focus filter discovery needs the App Intents metadata that only an Xcode-built app bundle contains.
enum FocusFilterAvailability {
    static func hasIntentMetadata(bundleURL: URL = Bundle.main.bundleURL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        let metadata = bundleURL.appendingPathComponent("Contents/Resources/Metadata.appintents", isDirectory: true)
        return fileManager.fileExists(atPath: metadata.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static let availableGuidance = "In System Settings → Focus, choose a Focus, select Add Filter, then choose MyDock and a saved Dock profile. When that Focus turns off, MyDock leaves the last applied Dock selected."
    static let unavailableGuidance = "This copy of MyDock can't offer Focus filters. Install the release version of MyDock to choose a Dock for each Focus."

    static func guidance(bundleURL: URL = Bundle.main.bundleURL, fileManager: FileManager = .default) -> String {
        hasIntentMetadata(bundleURL: bundleURL, fileManager: fileManager) ? availableGuidance : unavailableGuidance
    }
}
