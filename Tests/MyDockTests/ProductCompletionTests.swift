import Foundation
import Testing
@testable import MyDock

@MainActor
struct ProductCompletionTests {
    private enum FixtureFailure: Error { case write }

    @Test func appearanceDefaultsPreserveFullOverridesColorsAndBehavior() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let id = try store.createProfileAndPersist(kind: .custom, name: "Fixture")
        SettingsAppearanceEditing.update(in: store, profileID: id) {
            $0.customDockSize = 1.3; $0.customDockTintStrength = 0.2; $0.customDockCornerRadius = 22
        }
        store.setProfileColor(id, to: .blue)
        let before = try #require(store.customProfiles.first { $0.id == id })
        let behavior = store.state.settings.automaticallyHideCustomDock
        let undo = try #require(SettingsAppearanceEditing.capture(in: store, profileID: nil))
        SettingsAppearanceEditing.update(in: store, profileID: nil) { $0.customDockSize = 0.8; $0.customDockMaterial = .solid }
        #expect(store.customProfiles.first { $0.id == id } == before)
        #expect(store.state.settings.automaticallyHideCustomDock == behavior)
        #expect(store.effectiveSettings(profileID: id).customDockSize == 1.3)
        undo.restore(in: store, editingProfileID: nil)
        #expect(store.state.settings.customDockSize == undo.settings.customDockSize)
        #expect(store.customProfiles.first { $0.id == id } == before)
    }

    @Test func dockEditingCreatesFullOverrideAndResetUndoRestoresIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let id = try store.createProfileAndPersist(kind: .custom, name: "Fixture")
        let globals = store.state.settings
        SettingsAppearanceEditing.update(in: store, profileID: id) { $0.customDockTintStrength = 0.3 }
        let override = try #require(store.customProfiles.first { $0.id == id }?.appearance)
        #expect(override.size == globals.customDockSize)
        #expect(override.widgetStyle == globals.customDockWidgetStyle)
        #expect(override.tintStrength == 0.3)
        #expect(store.state.settings == globals)
        let undo = try #require(SettingsAppearanceEditing.capture(in: store, profileID: id))
        store.setAppearance(nil, for: id)
        #expect(store.effectiveSettings(profileID: id).customDockTintStrength == globals.customDockTintStrength)
        undo.restore(in: store, editingProfileID: id)
        #expect(store.customProfiles.first { $0.id == id }?.appearance == override)
    }

    @Test func missingDockNeverFallsThroughToAppDefaults() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let before = store.state
        #expect(SettingsAppearanceEditing.capture(in: store, profileID: UUID()) == nil)
        #expect(!SettingsAppearanceEditing.update(in: store, profileID: UUID()) { $0.customDockSize = 1.5 })
        #expect(store.state == before)
    }

    @Test func diagnosticsSaveUsesExactReviewedBytesAfterSourceChanges() throws {
        var state = PersistentState()
        state.profiles = [DockProfile(name: "PRIVATE_PROFILE", kind: .custom,
                                      items: [.widget("Sticky Note"), .widget("Stripe"), .link(URL(string: "https://private.example/secret")!, title: "PRIVATE_LINK")])]
        state.profiles[0].items[0].widgetConfiguration?.noteText = "PRIVATE_NOTE"
        state.profiles[0].items[1].widgetConfiguration?.stripeAccountID = "PRIVATE_ACCOUNT"
        let data = try DiagnosticReport.makeData(state: state, hasUnpersistedChanges: false,
            persistenceWarningPresent: false, storageWritable: true, events: [], now: Date(timeIntervalSince1970: 100),
            buildNumber: "fixture", hasIntentMetadata: false)
        let payload = DiagnosticsPreviewPayload(data: data)
        state.profiles.removeAll()
        var written: Data?
        #expect(try payload.save(to: URL(fileURLWithPath: "/fixture/report.json")) { bytes, _ in written = bytes })
        #expect(written == data)
        #expect(payload.data == data)
        for secret in ["PRIVATE_PROFILE", "PRIVATE_NOTE", "PRIVATE_ACCOUNT", "PRIVATE_LINK", "private.example"] {
            #expect(!payload.text.contains(secret))
        }
    }

    @Test func diagnosticsCancellationAndWriteFailureKeepReviewRecoverable() throws {
        let payload = DiagnosticsPreviewPayload(data: Data("immutable fixture".utf8))
        var attempts = 0
        #expect(try !payload.save(to: nil) { _, _ in attempts += 1 })
        #expect(attempts == 0)
        let url = URL(fileURLWithPath: "/fixture/report.json")
        do {
            try payload.save(to: url) { _, _ in attempts += 1; throw FixtureFailure.write }
            Issue.record("Expected injected write failure")
        } catch FixtureFailure.write {}
        var retry: Data?
        #expect(try payload.save(to: url) { bytes, _ in attempts += 1; retry = bytes })
        #expect(attempts == 2)
        #expect(retry == payload.data)
    }

    @Test func alarmEditingRetainsIdentityAndRejectsRemovedOrChangedCandidates() throws {
        let existing = DockAlarm(title: "Old", hour: 8, minute: 30, repeatWeekdays: [2], isEnabled: false)
        let candidate = try #require(AlarmEditorCandidate.make(editingID: existing.id, alarms: [existing],
            title: "  New  ", hour: 9, minute: 15, repeatWeekdays: [3, 2]))
        #expect(candidate.id == existing.id)
        #expect(candidate.title == "New")
        #expect(candidate.repeatWeekdays == [2, 3])
        #expect(!candidate.isEnabled)
        #expect(AlarmEditorCandidate.make(editingID: existing.id, alarms: [], title: "New", hour: 9, minute: 15, repeatWeekdays: []) == nil)
        #expect(!AlarmEditorCandidate.stillMatches(candidate, alarms: [existing]))
        #expect(!AlarmEditorCandidate.stillMatches(candidate, alarms: []))
        #expect(AlarmEditorCandidate.stillMatches(candidate, alarms: [candidate]))
        #expect(AlarmEditorCandidate.make(editingID: nil, alarms: [], title: "New", hour: 24, minute: 15, repeatWeekdays: []) == nil)
    }

    @Test func savedSnippetSearchLeavesRetainedEditingIdentityAndBodyUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let drafts = DockUtilityDraftStore(fileURL: root.appendingPathComponent("drafts.json"))
        let profileID = UUID(), itemID = UUID()
        let entry = TextSnippet(title: "Reply", text: "Thanks for the update")
        let draft = DockUtilityFormDraft(editingID: entry.id, title: "Unfinished reply", body: "unsaved private text")
        try drafts.update(draft, itemID: itemID, in: profileID, kind: .snippet)
        #expect(SavedSnippetSearch.results([entry], query: " THANKS ") == [entry])
        #expect(SavedSnippetSearch.results([entry], query: "unsaved private text").isEmpty)
        #expect(SavedSnippetSearch.results([entry], query: "").map(\.id) == [entry.id])
        #expect(drafts.draft(itemID: itemID, in: profileID, kind: .snippet) == draft)
    }

    @Test func timingBoundariesDistinguishEndedOngoingAndAllDay() {
        let now = Date(timeIntervalSince1970: 1_000)
        var event = CalendarEventSnapshot(id: "fixture", title: "Fixture", startDate: now.addingTimeInterval(-60),
            endDate: now, isAllDay: false, calendarID: "fixture", calendarTitle: "Fixture")
        #expect(WidgetTimingPresentation.eventStatus(event, now: now) == "Ended")
        event.endDate = now.addingTimeInterval(60)
        #expect(WidgetTimingPresentation.eventStatus(event, now: now).contains("Ongoing"))
        event.startDate = now.addingTimeInterval(1)
        #expect(WidgetTimingPresentation.eventStatus(event, now: now).contains("Starts"))
        event.isAllDay = true
        #expect(WidgetTimingPresentation.eventStatus(event, now: now) == "All day")
        #expect(!WidgetTimingPresentation.isStale(fetchedAt: now, now: now.addingTimeInterval(120), maximumAge: 120))
        #expect(WidgetTimingPresentation.isStale(fetchedAt: now, now: now.addingTimeInterval(121), maximumAge: 120))
    }

    @Test func installedCopyDuplicatePolicyMatchesNormalizedURL() {
        let first = DockItem.application(at: URL(fileURLWithPath: "/fixture/A/Example.app"))
        let alias = DockItem.application(at: URL(fileURLWithPath: "/fixture/A/nested/../Example.app"))
        let other = DockItem.application(at: URL(fileURLWithPath: "/fixture/B/Example.app"))
        #expect(WidgetDiscovery.containsApplication(alias, in: [first]))
        #expect(!WidgetDiscovery.containsApplication(other, in: [first]))
        #expect(!WidgetDiscovery.canAdd(alias, alreadyAdded: true))
        #expect(WidgetDiscovery.canAdd(other, alreadyAdded: false))
        #expect(WidgetDiscovery.canAdd(.widget("Clock"), alreadyAdded: true))
    }

    @Test func dayRelationAndReadingStatusStayHonest() {
        #expect(WidgetTimingPresentation.dayRelation(offset: 0, reference: "this Mac") == "Same date as this Mac")
        #expect(WidgetTimingPresentation.dayRelation(offset: 1, reference: "this Mac") == "1 day ahead of this Mac")
        #expect(WidgetTimingPresentation.dayRelation(offset: -2, reference: "this Mac") == "2 days behind this Mac")
        let then = Date(timeIntervalSince1970: 0)
        #expect(WidgetTimingPresentation.readingStatus(fetchedAt: then, now: then.addingTimeInterval(500), maximumAge: 120).hasPrefix("Saved reading"))
        #expect(WidgetTimingPresentation.readingStatus(fetchedAt: then, now: then.addingTimeInterval(60), maximumAge: 120).hasPrefix("Updated"))
    }

    @Test func staleAILimitsMessageNamesOriginalSuccessAndError() {
        let when = Date(timeIntervalSince1970: 1_000)
        let text = AILimitsStalePresentation.message(updatedAt: when, error: "Network unavailable")
        #expect(text.hasPrefix("Stale"))
        #expect(text.contains(when.formatted(date: .abbreviated, time: .shortened)))
        #expect(text.hasSuffix("Refresh failed: Network unavailable"))
        #expect(AILimitsStalePresentation.message(updatedAt: nil, error: "x").contains("time unknown"))
    }
}
