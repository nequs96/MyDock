import CoreLocation
import EventKit
import Foundation
import Testing
import UserNotifications
@testable import MyDock

@Suite struct AuditLaneGTests {
    // S13-001: the sidebar and the results pane come from one source, and every page's
    // vocabulary is answered by a result on that page.
    @Test func everySearchTermFindsAResultOnItsPage() {
        for page in MyDockSettingsPage.allCases {
            for word in page.searchTerms.split(separator: " ").map(String.init) {
                #expect(SettingsSearchCatalog.results(word).contains { $0.page == page }, "\(page.rawValue): \(word)")
                #expect(SettingsSearchCatalog.pages(matching: word).contains(page), "\(page.rawValue): \(word)")
            }
        }
    }

    @Test(arguments: ["focus", "freeze", "diagnostics", "claude", "codex", "menu bar", "widget labels", "dock color",
                      "privacy", "integrations", "no-such-control-123"])
    func sidebarPagesMatchResultPages(query: String) {
        let resultPages = Set(SettingsSearchCatalog.results(query).map(\.page))
        #expect(Set(SettingsSearchCatalog.pages(matching: query)) == resultPages)
    }

    @Test func previouslyUnsearchableControlsAreFound() {
        #expect(SettingsSearchCatalog.results("focus").contains { $0.page == .dock && $0.section == "Focus filters" })
        #expect(SettingsSearchCatalog.results("freeze").contains { $0.page == .dock && $0.section == "macOS Dock switching" })
        #expect(SettingsSearchCatalog.results("diagnostics").contains { $0.page == .general && $0.section == "Diagnostics" })
        #expect(SettingsSearchCatalog.results("claude").contains { $0.page == .integrations && $0.section == "AI accounts on this Mac" })
        #expect(SettingsSearchCatalog.results("codex").contains { $0.page == .integrations })
    }

    @Test func pageTitleOnlyMatchListsThePage() {
        let results = SettingsSearchCatalog.results("integrations")
        #expect(results.contains { $0.page == .integrations && $0.section.isEmpty && $0.title == "Integrations" })
        #expect(SettingsSearchCatalog.results("   ").isEmpty)
        #expect(SettingsSearchCatalog.pages(matching: "   ") == MyDockSettingsPage.allCases)
    }

    // S13-005: the Appearance preview sample keeps its identities between renders.
    @MainActor @Test func appearancePreviewSampleIsStable() {
        let first = DockProfile.appearancePreviewSample
        let second = DockProfile.appearancePreviewSample
        #expect(first.id == second.id)
        #expect(first.items.map(\.id) == second.items.map(\.id))
        #expect(first.items.map(\.widgetKind) == ["Clock", "Weather", "Sticky Note"])
        #expect(Set(first.items.map(\.id)).count == 3)
    }

    // S13-004: the app-wide factory reset names how many Docks will change.
    @Test func factoryResetMessageCountsInheritingDocks() {
        #expect(SettingsAppearanceDefaults.factoryResetMessage(inheritingDocks: 0).hasPrefix("No Dock uses app defaults"))
        #expect(SettingsAppearanceDefaults.factoryResetMessage(inheritingDocks: 1).hasPrefix("1 Dock uses app defaults"))
        #expect(SettingsAppearanceDefaults.factoryResetMessage(inheritingDocks: 3).hasPrefix("3 Docks use app defaults"))
    }

    // S13-002: a backup is previewed before its Docks are added, and names already in use are flagged.
    @Test func backupRestorePreviewFlagsExistingNamesAndCountsDocks() {
        let report = BackupImportReport(importedProfiles: [DockProfile(name: "Work", kind: .custom),
                                                           DockProfile(name: "Travel", kind: .native)],
                                        missingItems: ["Work: Notes (/missing)"])
        let preview = BackupRestorePreview(report: report, existingNames: ["Work", "Home"])
        #expect(preview.duplicateNames == ["Work"])
        #expect(preview.addTitle == "Add 2 Docks")
        #expect(BackupRestorePreview.docksPhrase(1) == "1 Dock")
        #expect(BackupRestorePreview.docksPhrase(0) == "0 Docks")
    }

    // S13-006: app activation re-runs account detection at most once a minute.
    @Test func accountActivationRecheckIsThrottled() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(AIAccountActivationPolicy.shouldRecheck(lastChecked: nil, now: now))
        #expect(!AIAccountActivationPolicy.shouldRecheck(lastChecked: now.addingTimeInterval(-10), now: now))
        #expect(AIAccountActivationPolicy.shouldRecheck(lastChecked: now.addingTimeInterval(-60), now: now))
        // A clock that moved backwards does not suppress checks.
        #expect(AIAccountActivationPolicy.shouldRecheck(lastChecked: now.addingTimeInterval(120), now: now))
    }

    // S13-015: tile size has one bounds constant shared by decoding and the slider.
    @Test func tileSizeBoundsAreShared() {
        #expect(DockAppearanceBounds.size == 0.65...1.5)
        #expect(DockAppearanceBounds.clamped(3, default: 1, to: DockAppearanceBounds.size) == 1.5)
    }

    // S13-020, S19-019: permission rows carry an explicit state; the summary never depends on copy.
    @Test func permissionRowsDeriveSummaryFromState() {
        #expect(PermissionOverviewRow.accessibility(trusted: true).summary == "Granted")
        #expect(PermissionOverviewRow.accessibility(trusted: false).summary == "Not granted")
        #expect(PermissionOverviewRow.accessibility(trusted: false).explanation.contains("previews"))
        #expect(PermissionOverviewRow.screenRecording(allowed: false).explanation.contains("Previews"))
        #expect(PermissionOverviewRow.screenRecording(allowed: true).state == .granted)
        #expect(PermissionOverviewRow.notifications(nil).state == .unavailable)
        #expect(PermissionOverviewRow.notifications(.notDetermined).summary == "Not requested")
        #expect(PermissionOverviewRow.notifications(.denied).summary == "Not granted")
        #expect(PermissionOverviewRow.notifications(.authorized).granted)
        #expect(PermissionOverviewRow.events(.event, status: .notDetermined).state == .notRequested)
        #expect(PermissionOverviewRow.events(.reminder, status: .denied).state == .denied)
        #expect(PermissionOverviewRow.events(.reminder, status: .denied).name == "Reminders")
        if #available(macOS 14.0, *) {
            #expect(PermissionOverviewRow.events(.event, status: .fullAccess).granted)
            #expect(PermissionOverviewRow.events(.event, status: .writeOnly).state == .denied)
        }
        #expect(PermissionOverviewRow.location(.authorizedWhenInUse).granted)
        #expect(PermissionOverviewRow.location(.restricted).summary == "Not granted")
        #expect(PermissionOverviewRow.automation.summary == "Per-app")
        #expect(PermissionOverviewRow.events(.event, status: .denied).pane == .calendars)
        #expect(PermissionOverviewRow.events(.reminder, status: .denied).pane == .reminders)
    }

    // S20-017: every System Settings pane is written once and parses as a URL.
    @Test func systemSettingsPanesAreUniqueURLs() {
        let addresses = SystemSettingsPane.allCases.map(\.address)
        #expect(Set(addresses).count == addresses.count)
        for pane in SystemSettingsPane.allCases {
            #expect(pane.url?.scheme == "x-apple.systempreferences", "\(pane)")
        }
    }

    // S13-020: connection kinds are exhaustive and map to their widget kind and reference.
    @Test func connectionKindsMapToWidgetKindsAndReferences() {
        #expect(ConnectionKind.allCases.map(\.rawValue) == ["Stripe", "Paddle", "Shopify"])
        for kind in ConnectionKind.allCases {
            let reference = kind.reference("id-\(kind.rawValue)")
            #expect(reference.identifier == "id-\(kind.rawValue)")
            switch (kind, reference) {
            case (.stripe, .stripe), (.paddle, .paddle), (.shopify, .shopify): break
            default: Issue.record("\(kind) maps to the wrong reference")
            }
        }
        #expect(ConnectionError.differentShopifyStore.errorDescription?.contains("Shopify") == true)
        #expect(ConnectionError.changedWhileTesting.errorDescription != nil)
    }

    // S13-022: rules that can never match say why.
    @Test func automaticSwitchRuleProblemsAreReported() {
        #expect(AutomaticSwitchRuleText.problem(AutomaticSwitchRule(kind: .appFrontmost)) != nil)
        #expect(AutomaticSwitchRuleText.problem(AutomaticSwitchRule(kind: .appFrontmost, bundleIdentifier: "com.apple.Notes")) == nil)
        #expect(AutomaticSwitchRuleText.problem(AutomaticSwitchRule(kind: .timeWindow)) == nil)
        #expect(AutomaticSwitchRuleText.problem(AutomaticSwitchRule(kind: .timeWindow, weekdays: []))?.contains("No days") == true)
        #expect(AutomaticSwitchRuleText.problem(AutomaticSwitchRule(kind: .timeWindow, startMinute: 600, endMinute: 600))?.contains("same") == true)
    }

    // S13-022: a deleted rule comes back at its old priority, once.
    @Test func deletedAutomaticSwitchRuleIsRestoredInPlace() {
        var settings = AutomaticSwitchingSettings()
        let first = settings.addRule(.timeWindow, defaultProfileID: nil)
        let second = settings.addRule(.appFrontmost, defaultProfileID: nil)
        let third = settings.addRule(.timeWindow, defaultProfileID: nil)
        let removed = settings.rules[1]
        settings.removeRule(removed.id)
        #expect(settings.restoreRule(removed, at: 1))
        #expect(settings.rules.map(\.id) == [first, second, third].compactMap { $0 })
        #expect(!settings.restoreRule(removed, at: 0))
        #expect(settings.rules.count == 3)
        settings.removeRule(removed.id)
        #expect(settings.restoreRule(removed, at: 99))
        #expect(settings.rules.last?.id == removed.id)
    }

    @Test func restoringARuleRespectsTheCap() {
        var settings = AutomaticSwitchingSettings()
        for _ in 0..<AutomaticSwitchingSettings.maximumRules { settings.addRule(.timeWindow, defaultProfileID: nil) }
        #expect(!settings.restoreRule(AutomaticSwitchRule(kind: .timeWindow), at: 0))
        #expect(settings.rules.count == AutomaticSwitchingSettings.maximumRules)
    }

    // S13-021, S13-023, S13-024: search lands on the card that holds the control, in Dock terms.
    @Test func searchEntriesPointAtTheRightCards() {
        #expect(SettingsSearchCatalog.results("auto-save").contains { $0.page == .dock && $0.section == "macOS Dock switching" })
        #expect(SettingsSearchCatalog.results("thumbnails").contains { $0.page == .behavior && $0.section == "Apps and windows" })
        #expect(SettingsSearchCatalog.results("shortcuts").contains { $0.page == .shortcuts && $0.section == "Global Dock shortcuts" })
        #expect(!SettingsSearchCatalog.entries.contains { $0.title.localizedCaseInsensitiveContains("profile") })
    }
}
