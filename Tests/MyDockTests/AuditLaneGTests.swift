import Foundation
import Testing
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
        #expect(SettingsSearchCatalog.results("freeze").contains { $0.page == .dock && $0.section == "Native Dock switching" })
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
}
