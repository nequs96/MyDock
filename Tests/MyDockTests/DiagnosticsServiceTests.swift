import Foundation
import Testing
@testable import MyDock

struct DiagnosticsServiceTests {
    @Test func widgetAndIntegrationFailuresUseFixedExportCodes() {
        #expect(DiagnosticEventCode.weatherSearchFailed.category == .widgets)
        #expect(DiagnosticEventCode.weatherLocationFailed.category == .widgets)
        #expect(DiagnosticEventCode.weatherRefreshFailed.category == .widgets)
        #expect(DiagnosticEventCode.stripeRefreshFailed.category == .integrations)
        #expect(DiagnosticEventCode.paddleConnectionFailed.category == .integrations)
        #expect(DiagnosticEventCode.shopifyDisconnectionFailed.category == .integrations)
        #expect(DiagnosticEventCode.customDockDisplayFallback.category == .windowManagement)
        #expect(DiagnosticEventCode.customDockDisplayRestored.category == .windowManagement)
        #expect(DiagnosticEventCode.customDockScreenUnavailable.category == .windowManagement)
    }

    @Test func reportContainsStatusButNoPrivateProfileContent() throws {
        var note = DockItem.widget("Sticky Note")
        note.widgetConfiguration?.noteText = "private-note-sentinel"
        let file = DockItem.file(at: URL(fileURLWithPath: "/tmp/private-file-sentinel"))
        let profile = DockProfile(name: "private-profile-sentinel", kind: .custom,
                                  items: [note, file])
        var state = PersistentState()
        state.profiles = [profile]
        state.settings.activeCustomProfileID = profile.id
        state.settings.customDockMaterial = .dark
        let event = DiagnosticEvent(at: Date(timeIntervalSince1970: 1_800_000_000),
                                    category: .persistence, code: .stateSaveFailed)

        let data = try DiagnosticReport.makeData(state: state, hasUnpersistedChanges: true,
                                                 persistenceWarningPresent: false,
                                                 storageWritable: true, events: [event],
                                                 now: Date(timeIntervalSince1970: 1_800_000_100),
                                                 osVersion: OperatingSystemVersion(majorVersion: 26,
                                                                                   minorVersion: 5,
                                                                                   patchVersion: 1))
        let text = String(decoding: data, as: UTF8.self)
        for privateValue in ["private-note-sentinel", "private-file-sentinel",
                             "private-profile-sentinel", profile.id.uuidString, note.id.uuidString] {
            #expect(!text.contains(privateValue))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(DiagnosticReport.self, from: data)
        #expect(report.counts.customProfiles == 1)
        #expect(report.counts.widgets == 1)
        #expect(report.counts.files == 1)
        #expect(report.status.hasUnpersistedChanges)
        #expect(report.appearance.dockMaterial == .dark)
        #expect(report.recentEvents.map(\.code) == [.stateSaveFailed])
    }

    @Test func seededPrivateStringsNeverAppearInExportAndBuildFieldsArePresent() throws {
        var widget = DockItem.widget("Stripe")
        widget.widgetConfiguration?.stripeDisplayName = "acct-name-sentinel"
        widget.widgetConfiguration?.shopifyDisplayName = "shop-name-sentinel"
        widget.widgetConfiguration?.textSnippets = [TextSnippet(title: "snippet-title-sentinel", text: "snippet-text-sentinel")]
        widget.widgetConfiguration?.quickLinks = [QuickLink(title: "quick-sentinel", url: URL(string: "https://quick-sentinel.example/token=rk_live_secret")!)]
        widget.widgetConfiguration?.checklistEntries = [QuickChecklistEntry(title: "checklist-sentinel")]
        let link = DockItem.link(URL(string: "https://url-sentinel.example/path")!, title: "link-title-sentinel")
        let profile = DockProfile(name: "profile-sentinel", kind: .custom, items: [widget, link])
        var state = PersistentState()
        state.profiles = [profile]

        let data = try DiagnosticReport.makeData(state: state, hasUnpersistedChanges: false, persistenceWarningPresent: false,
                                                 storageWritable: true, events: [], buildNumber: "42", hasIntentMetadata: true)
        let text = String(decoding: data, as: UTF8.self)
        for sentinel in ["acct-name-sentinel", "shop-name-sentinel", "snippet-title-sentinel", "snippet-text-sentinel",
                         "quick-sentinel", "rk_live_secret", "checklist-sentinel", "url-sentinel", "link-title-sentinel", "profile-sentinel"] {
            #expect(!text.contains(sentinel), "\(sentinel) leaked")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(DiagnosticReport.self, from: data)
        #expect(report.buildNumber == "42")
        #expect(report.hasIntentMetadata)
        #expect(report.appVersion == Product.marketingVersion)
        #expect(DiagnosticReport.currentBuildNumber(bundle: Bundle(for: DiagnosticsServiceBundleToken.self)) != "")
    }
}

private final class DiagnosticsServiceBundleToken {}
