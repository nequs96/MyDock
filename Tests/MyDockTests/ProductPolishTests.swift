import Foundation
import Testing
@testable import MyDock

@Suite struct ProductPolishTests {
    @Test func firstLaunchNeverShowsWhatsNew() {
        #expect(!WhatsNew.shouldShow(lastSeenVersion: nil, currentVersion: "1.0.0", onboardingComplete: false))
        #expect(!WhatsNew.shouldShow(settings: AppSettings()))
    }

    @Test func sameVersionIsNotShownAgain() {
        #expect(!WhatsNew.shouldShow(lastSeenVersion: "1.0.0", currentVersion: "1.0.0", onboardingComplete: true))
    }

    @Test func newVersionOrNeverSeenShowsOnce() {
        #expect(WhatsNew.shouldShow(lastSeenVersion: "0.9.0", currentVersion: "1.0.0", onboardingComplete: true))
        #expect(WhatsNew.shouldShow(lastSeenVersion: nil, currentVersion: "1.0.0", onboardingComplete: true))
    }

    @MainActor @Test func completingOnboardingMarksTheVersionSeen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MyDockPolish-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false)
        #expect(!WhatsNew.shouldShow(settings: store.state.settings))
        store.completeOnboarding()
        #expect(store.state.settings.lastSeenWhatsNewVersion == Product.marketingVersion)
        #expect(!WhatsNew.shouldShow(settings: store.state.settings))
    }

    @Test func oldSettingsJSONDecodesWithoutTheField() throws {
        let old = #"{"onboardingComplete":true,"setupMode":"both"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(settings.lastSeenWhatsNewVersion == nil)
        #expect(settings.onboardingComplete)
        #expect(WhatsNew.shouldShow(settings: settings))
        let garbled = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"lastSeenWhatsNewVersion":7}"#.utf8))
        #expect(garbled.lastSeenWhatsNewVersion == nil)
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(AppSettings()))
        #expect(round == AppSettings())
    }

    @Test func whatsNewTableIsShortAndComplete() {
        #expect((4...6).contains(WhatsNew.entries.count))
        #expect(WhatsNew.entries.allSatisfy { !$0.title.isEmpty && !$0.subtitle.isEmpty && !$0.symbol.isEmpty })
    }

    @Test func shortcutListHasNoDuplicateCombos() {
        let keys = KeyboardShortcutCatalog.allKeys
        #expect(!keys.isEmpty)
        #expect(Set(keys).count == keys.count)
        let titles = KeyboardShortcutCatalog.groups.flatMap { $0.entries.map(\.title) }
        #expect(Set(titles).count == titles.count)
    }
}
