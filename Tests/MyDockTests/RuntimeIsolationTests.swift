import Foundation
import Testing
@testable import MyDock

@MainActor
@Suite(.serialized)
struct RuntimeIsolationTests {
    @Test func defaultGraphUsesPrivateFilesAndMemoryPreferences() throws {
        let root = try #require(AppRuntimeEnvironment.validationRoot)
        #expect(AppRuntimeEnvironment.applicationSupportDirectory.path.hasPrefix(root.path + "/"))
        #expect(WindowPreviewDiskCache.defaultDirectory.path.hasPrefix(root.path + "/"))
        let key = "fixture-\(UUID().uuidString)"
        AppRuntimeEnvironment.defaults.set("private", forKey: key)
        #expect(AppRuntimeEnvironment.defaults.string(forKey: key) == "private")
        #expect(UserDefaults.standard.object(forKey: key) == nil)
        AppRuntimeEnvironment.defaults.removeObject(forKey: key)
        #expect(AppRuntimeEnvironment.defaults.object(forKey: key) == nil)
        let store = ProfileStore()
        #expect(!store.allowsSystemChanges)
    }

    @Test func productionAdaptersRefuseNativeAndCredentialEffects() async throws {
        // Stop before touching any adapter if isolation were ever off: the calls below would otherwise
        // write the user's real Keychain and Apple Dock preferences.
        try #require(!AppRuntimeEnvironment.allowsNativeEffects)
        #expect(try MarketAPIKeyStore.read() == nil)
        #expect(throws: ValidationBoundaryError.self) { try MarketAPIKeyStore.write("fixture") }
        #expect(throws: ValidationBoundaryError.self) { try MarketAPIKeyStore.delete() }
        #expect(throws: ValidationBoundaryError.self) { try UserDefaultsDockPreferencesBackend().readCurrentTiles() }
        #expect(throws: ValidationBoundaryError.self) { try UserDefaultsDockPreferencesBackend().writeTiles([]) }
        #expect(throws: ValidationBoundaryError.self) { try UserDefaultsDockAutoHideBackend().readVisibilitySettings() }
        let itemID = UUID(), operationID = UUID()
        CountdownNotificationService.begin(itemID: itemID, operationID: operationID)
        await #expect(throws: ValidationBoundaryError.self) {
            try await CountdownNotificationService.schedule(itemID: itemID, operationID: operationID, fireDate: .now.addingTimeInterval(60))
        }
        CountdownNotificationService.cancel(itemID: itemID)
    }
}
