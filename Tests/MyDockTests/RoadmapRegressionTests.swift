import Foundation
import Testing
@testable import MyDock

@MainActor
struct RoadmapRegressionTests {
    @Test func settingsSearchKeepsPagesWithMatchingControlsVisible() {
        #expect(SettingsSearchCatalog.pages(matching: "corner").contains(.appearance))
        #expect(SettingsSearchCatalog.pages(matching: "window previews").contains(.behavior))
        #expect(SettingsSearchCatalog.pages(matching: "  ") == MyDockSettingsPage.allCases)
        #expect(SettingsSearchCatalog.pages(matching: "no-such-control-123").isEmpty)
    }
    @Test func delayedCredentialRefreshCannotResurrectOrReplaceAnAccount() {
        let original = ShopifyCredential(clientID: "app", clientSecret: "secret", accessToken: "old", tokenExpiresAt: .now)
        var renewed = original; renewed.accessToken = "already-renewed"
        #expect(ShopifyCredentialUpdatePolicy.mayRefresh(original: original, current: renewed, registered: true, cancelled: false))
        #expect(!ShopifyCredentialUpdatePolicy.mayRefresh(original: original, current: nil, registered: false, cancelled: false))
        var replacement = original; replacement.clientSecret = "replacement"
        #expect(!ShopifyCredentialUpdatePolicy.mayRefresh(original: original, current: replacement, registered: true, cancelled: false))
        #expect(!ShopifyCredentialUpdatePolicy.mayRefresh(original: original, current: original, registered: true, cancelled: true))
    }
    @Test func failedSaveKeepsDraftAndCanRetryWithoutAnotherEdit() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file)
        let id = try store.createProfileAndPersist(kind: .custom, name: "Original")
        var draft = DockProfileDraft(profile: try #require(store.activeCustomProfile))
        draft.update { $0.name = "Saved after retry" }
        store.editSessions.set(draft, for: id)
        try FileManager.default.removeItem(at: folder)
        try Data("blocked".utf8).write(to: folder)
        #expect(throws: EditSessionSaveError.self) { try store.editSessions.save(id) }
        #expect(store.editSessions.hasUnsavedChanges)
        #expect(store.hasUnpersistedChanges)
        try FileManager.default.removeItem(at: folder)
        try store.editSessions.save(id)
        #expect(!store.editSessions.hasUnsavedChanges)
        #expect(!store.hasUnpersistedChanges)
        #expect(ProfileStore(fileURL: file).activeCustomProfile?.name == "Saved after retry")
    }

    @Test func failedPresetAndOnboardingDoNotPublishPartialProfiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("blocked".utf8).write(to: folder)
        let store = ProfileStore(fileURL: folder.appendingPathComponent("state.json"))
        let original = store.state
        #expect(throws: (any Error).self) {
            try store.createProfile(DockProfile(name: "Preset", kind: .custom, items: [.widget("Clock")]))
        }
        #expect(store.state.profiles == original.profiles)
        #expect(store.state.settings == original.settings)
        #expect(throws: (any Error).self) {
            try store.finishOnboarding(setupMode: .customMain, customDockPosition: .bottom,
                                       customDockDisplayID: nil, importedNativeItems: [], starterWidgets: ["Clock"])
        }
        #expect(!store.state.settings.onboardingComplete)
        #expect(store.state.profiles.isEmpty)
        #expect(store.persistenceError != nil)
    }

    @Test func hiddenTimerCompletesAndDurationEditsRescheduleIt() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProfileStore(fileURL: folder.appendingPathComponent("state.json"))
        _ = store.widgetLifecycle
        let hiddenID = try store.createProfileAndPersist(kind: .custom)
        var item = DockItem.widget("Focus Timer")
        item.widgetConfiguration?.focusDurationSeconds = 600
        item.widgetConfiguration?.startFocusTimer(at: .now.addingTimeInterval(-2))
        store.add(item, to: hiddenID)
        _ = store.createProfile(kind: .custom, name: "Visible")
        try await Task.sleep(for: .milliseconds(30))
        store.updateWidgetConfiguration(itemID: item.id, in: hiddenID) { $0.focusDurationSeconds = 1 }
        try await pollUntil {
            store.state.profiles.first(where: { $0.id == hiddenID })?.items.first?.widgetConfiguration?.focusStartedAt == nil
        }
        let c = try #require(store.state.profiles.first(where: { $0.id == hiddenID })?.items.first?.widgetConfiguration)
        #expect(c.focusStartedAt == nil)
        #expect(c.focusElapsedBeforeStart == 1)
        store.flush()
    }

    @Test func layoutSanitizerRemovesUndoHistoryAndMacSpecificSelections() {
        var profile = DockProfile(name: "Private", kind: .custom, items: [.widget("Hydration")])
        var c = WidgetConfiguration()
        c.logHydrationDrink(amountML: 250)
        c.hydrationLastRemovedEntry = c.hydrationEntries.first
        c.selectedCalendarIDs = ["private-calendar"]
        c.selectedReminderCalendarID = "private-reminders"
        c.selectedShortcutName = "Private shortcut"
        c.countdownTargetDate = .now
        profile.items[0].widgetConfiguration = c
        let sanitized = ProfileSanitizer.sanitize(profile).items[0].widgetConfiguration
        #expect(sanitized?.hydrationEntries.isEmpty == true)
        #expect(sanitized?.hydrationLastRemovedEntry == nil)
        #expect(sanitized?.selectedCalendarIDs.isEmpty == true)
        #expect(sanitized?.selectedReminderCalendarID == "")
        #expect(sanitized?.selectedShortcutName == "")
        #expect(sanitized?.countdownTargetDate == nil)
    }

    @Test func queriesShareAccountWorkAndRespectRefreshMinutes() throws {
        var first = WidgetConfiguration(); first.stripeAccountID = "same-account"
        var second = first; second.stripeDisplayName = "A different tile label"
        #expect(WidgetDataQuery.make(kind: "Stripe", configuration: first) == WidgetDataQuery.make(kind: "Stripe", configuration: second))
        first.stockRefreshIntervalMinutes = 5
        first.stockSymbol = "AAPL"
        let query = try #require(WidgetDataQuery.make(kind: "Stock", configuration: first))
        #expect(WidgetDataCoordinator.interval(query, configuration: first) == 300)
    }

    @Test func cancelledRefreshWaiterDoesNotBlockFollowingWork() async throws {
        let limiter = WidgetRefreshLimiter(maximumConcurrent: 1)
        try await limiter.acquire()
        let cancelled = Task { try await limiter.acquire() }
        // Cancel only once the waiter is queued, so the test exercises the queued-waiter path.
        var budget = PollBudget()
        while await limiter.waiterCount == 0, try await budget.wait() {}
        #expect(await limiter.waiterCount == 1)
        cancelled.cancel()
        do { try await cancelled.value; Issue.record("Cancelled refresh acquired a permit") }
        catch { #expect(error is CancellationError) }
        await limiter.release()
        try await limiter.acquire()
        await limiter.release()
    }
}
