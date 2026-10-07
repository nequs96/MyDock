import Foundation
import Testing
@testable import MyDock

struct ProductWorkflowCorrectionTests {
    @Test @MainActor func privateUtilityDraftsSurviveReopenAndRemainScopedToProfileItemAndKind() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("utility-drafts/drafts.json")
        let itemID = UUID(), profileID = UUID(), otherProfileID = UUID()
        let draft = DockUtilityFormDraft(editingID: UUID(), title: "Reply", body: "Unfinished private text")
        let store = DockUtilityDraftStore(fileURL: file)
        try store.update(draft, itemID: itemID, in: profileID, kind: .snippet)
        #expect(store.flush())
        let reopened = DockUtilityDraftStore(fileURL: file)
        #expect(reopened.draft(itemID: itemID, in: profileID, kind: .snippet) == draft)
        #expect(reopened.draft(itemID: itemID, in: otherProfileID, kind: .snippet) == nil)
        #expect(reopened.draft(itemID: itemID, in: profileID, kind: .link) == nil)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test @MainActor func utilityDraftPruningDoesNotRemoveSurvivingTargetOrOversizedReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("utility-drafts/drafts.json")
        let item = DockItem.widget("Text Snippets")
        let profile = DockProfile(name: "Fixture", kind: .custom, items: [item])
        let deletedItemID = UUID()
        let draft = DockUtilityFormDraft(editingID: nil, title: "Pending", body: "Keep this")
        let store = DockUtilityDraftStore(fileURL: file)
        try store.update(draft, itemID: item.id, in: profile.id, kind: .snippet)
        try store.update(draft, itemID: deletedItemID, in: profile.id, kind: .snippet)
        #expect(throws: DockUtilityDraftError.tooLarge) {
            try store.update(DockUtilityFormDraft(editingID: nil, title: "Pending", body: String(repeating: "x", count: 10_001)),
                             itemID: item.id, in: profile.id, kind: .snippet)
        }
        #expect(store.discardTargets(notIn: [profile]))
        let reopened = DockUtilityDraftStore(fileURL: file)
        #expect(reopened.draft(itemID: item.id, in: profile.id, kind: .snippet) == draft)
        #expect(reopened.draft(itemID: deletedItemID, in: profile.id, kind: .snippet) == nil)
    }

    @Test @MainActor func failedCollectionSaveRetainsPrivateDraftAndSuccessfulSaveCanAcknowledgeIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let initial = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let item = DockItem.widget("Text Snippets")
        let profileID = try initial.createProfile(DockProfile(name: "Fixture", kind: .custom, items: [item]))
        let draft = DockUtilityFormDraft(editingID: nil, title: "Reply", body: "Still unfinished")
        try initial.utilityDrafts.update(draft, itemID: item.id, in: profileID, kind: .snippet)
        #expect(initial.utilityDrafts.flush())
        let failed = ProfileStore(fileURL: file, allowsSystemChanges: false,
                                  stateWriter: RevisionedStateWriter { _, _ in throw CocoaError(.fileWriteNoPermission) })
        #expect(throws: CocoaError.self) {
            try failed.updateWidgetConfigurationAndPersist(itemID: item.id, in: profileID) {
                $0.textSnippets.append(TextSnippet(title: draft.title, text: draft.body))
            }
        }
        let retry = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(retry.utilityDrafts.draft(itemID: item.id, in: profileID, kind: .snippet) == draft)
        #expect(retry.state.profiles.first?.items.first?.widgetConfiguration?.textSnippets.isEmpty == true)
        try retry.updateWidgetConfigurationAndPersist(itemID: item.id, in: profileID) {
            $0.textSnippets.append(TextSnippet(title: draft.title, text: draft.body))
        }
        #expect(retry.utilityDrafts.discard(itemID: item.id, in: profileID, kind: .snippet))
        let reopened = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(reopened.utilityDrafts.draft(itemID: item.id, in: profileID, kind: .snippet) == nil)
        #expect(reopened.state.profiles.first?.items.first?.widgetConfiguration?.textSnippets.first?.text == draft.body)
    }

    @Test @MainActor func draftWriteFailureKeepsInputForRetryAndDoesNotReportSuccessfulDiscard() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("utility-drafts/drafts.json")
        let itemID = UUID(), profileID = UUID()
        let draft = DockUtilityFormDraft(editingID: nil, title: "Reply", body: "Retained in memory")
        let failed = DockUtilityDraftStore(fileURL: file, write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        try failed.update(draft, itemID: itemID, in: profileID, kind: .snippet)
        #expect(!failed.flush())
        #expect(failed.errorMessage != nil)
        #expect(failed.draft(itemID: itemID, in: profileID, kind: .snippet) == draft)
        #expect(!failed.discard(itemID: itemID, in: profileID, kind: .snippet))
        #expect(failed.draft(itemID: itemID, in: profileID, kind: .snippet) == draft)
    }

    @Test func narrowClockPreservesTimeAndLocalizedDayPeriod() {
        #expect(ClockDockTextFormatter.text("14:59", narrow: true) == "14:59")
        #expect(ClockDockTextFormatter.text("2:59\u{202F}PM", narrow: true) == "2:59\nPM")
        #expect(ClockDockTextFormatter.text("오후 2:59", narrow: true) == "오후\n2:59")
        #expect(ClockDockTextFormatter.text("2:59\u{202F}PM", narrow: false) == "2:59\u{202F}PM")
    }

    @Test func cachedWeatherExtremesDisplayUnavailableWithoutIntegerConversion() {
        for unit in WeatherTemperatureUnit.allCases {
            for temperature in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 1e30, -1e30] {
                #expect(WeatherDockTemperatureFormatter.text(temperature, unit: unit) == "—")
            }
        }
    }

    @Test func weatherDisplayRetainsSignsRoundingAndConfiguredUnitBounds() {
        #expect(WeatherDockTemperatureFormatter.text(-12.6, unit: .celsius) == "-13°")
        #expect(WeatherDockTemperatureFormatter.text(21.4, unit: .celsius) == "21°")
        #expect(WeatherDockTemperatureFormatter.text(70.6, unit: .fahrenheit) == "71°")
        #expect(WeatherDockTemperatureFormatter.text(200, unit: .celsius) == "—")
        #expect(WeatherDockTemperatureFormatter.text(200, unit: .fahrenheit) == "200°")
        #expect(WeatherDockTemperatureFormatter.text(-150, unit: .celsius) == "-150°")
        #expect(WeatherDockTemperatureFormatter.text(-238, unit: .fahrenheit) == "-238°")
        #expect(WeatherDockTemperatureFormatter.text(302, unit: .fahrenheit) == "302°")
        #expect(WeatherDockTemperatureFormatter.text(302.1, unit: .fahrenheit) == "—")
    }
}
