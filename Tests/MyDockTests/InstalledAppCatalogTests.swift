import Foundation
import Testing
@testable import MyDock

struct InstalledAppCatalogTests {
    private func makeApp(_ root: URL, name: String, identifier: String = "test.app", version: String = "1", extra: [String: Any] = [:]) throws -> URL {
        let app = root.appendingPathComponent(name + ".app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleName": name, "CFBundlePackageType": "APPL", "CFBundleExecutable": "Run", "CFBundleShortVersionString": version]
        info.merge(extra) { _, value in value }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: app.appendingPathComponent("Contents/MacOS/Run"))
        return app
    }
    @Test func remnantsInvalidExecutablesHelpersAndNestedPackagesAreExcluded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = try makeApp(root, name: "Usable")
        let removed = try makeApp(root, name: "Removed")
        try FileManager.default.removeItem(at: removed.appendingPathComponent("Contents/Info.plist"))
        let noExecutable = try makeApp(root, name: "Remnant")
        try FileManager.default.removeItem(at: noExecutable.appendingPathComponent("Contents/MacOS/Run"))
        _ = try makeApp(root, name: "Agent", extra: ["LSUIElement": true])
        _ = try makeApp(root, name: "Background", extra: ["LSBackgroundOnly": "YES"])
        _ = try makeApp(root, name: "Invalid", extra: ["CFBundlePackageType": "XPC!"])
        let fake = try makeApp(root, name: "Command")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: fake.appendingPathComponent("Contents/MacOS/Run"))
        let nested = try makeApp(valid.appendingPathComponent("Contents/Helpers"), name: "Helper")
        #expect(InstalledAppCatalog.validatedApplication(at: nested) == nil)
        #expect(InstalledAppCatalog.validatedApplication(at: root.appendingPathComponent("Missing.app")) == nil)
        let scan = InstalledAppCatalog.discover(roots: [root], additionalURLs: [nested])
        #expect(scan.applications.map(\.name) == ["Usable"])
    }
    @Test func canonicalCopiesDeduplicateButVersionsAndDistinctIdentifiersRemain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try makeApp(root, name: "One")
        _ = try makeApp(root, name: "Copy")
        _ = try makeApp(root, name: "Version Two", version: "2")
        _ = try makeApp(root, name: "Other Product", identifier: "test.other")
        let alias = root.appendingPathComponent("Alias.app")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: first)
        let scan = InstalledAppCatalog.discover(roots: [root, root], additionalURLs: [first, first])
        #expect(scan.applications.count == 3)
        #expect(Set(scan.applications.map(\.id)).count == 3)
        #expect(scan.applications.contains { $0.version == "2" })
    }
    @Test func refreshReadsMetadataAgainAndDropsMovedOrRemovedApps() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root, name: "Current")
        #expect(InstalledAppCatalog.discover(roots: [root]).applications.count == 1)
        try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/MacOS/Run"))
        #expect(InstalledAppCatalog.discover(roots: [root], additionalURLs: [app]).applications.isEmpty)
    }
    @Test func humanReadableCountersCoverDockScaleAndChartScale() {
        #expect(AIActivityFormatting.tokens(643_868_378) == Double(643.868378).formatted(.number.precision(.fractionLength(0...1))) + "M")
        #expect(AIActivityFormatting.tokens(643_868_378, fractionDigits: 0) == "644M")
        #expect(AIActivityFormatting.tokens(4_000_000_000) == "4B")
        #expect(AIActivityFormatting.tokens(124_000) == "124K")
        #expect(AIActivityFormatting.tokens(0) == "0")
        #expect(AIActivityFormatting.tokens(-1) == "0")
    }
    @Test @MainActor func savedAppVersionWinsOverDefaultBundleRegistration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try makeApp(root, name: "Selected Copy", identifier: "com.apple.finder")
        let item = DockItem.application(at: url)
        #expect(AppLauncher.resolvedURL(for: item) == url)
    }
    @Test func unreadableHistoryRefreshKeepsPreviouslyLoadedActivity() {
        var configuration = AIActivityPreviewData.item().widgetConfiguration!
        configuration.aiActivitySnapshot?.sourceScope = AIUsageSourceScope.activity(provider: configuration.aiActivityProvider, range: configuration.aiActivityRange)
        let previous = configuration.aiActivitySnapshot!
        var unreadable = previous
        unreadable.available = false; unreadable.partial = true
        let failedValue = WidgetDataValue.activity(unreadable)
        #expect(failedValue.partialError != nil)
        failedValue.apply(to: &configuration)
        #expect(configuration.aiActivitySnapshot == previous)
        unreadable.partial = false
        WidgetDataValue.activity(unreadable).apply(to: &configuration)
        #expect(configuration.aiActivitySnapshot?.available == false)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MYDOCK_INSTALLED_APP_AUDIT"] == "1"))
    func currentMacInventoryContainsOnlyValidatedBundles() async throws {
        let scan = await InstalledAppCatalog.scan()
        #expect(!scan.applications.isEmpty)
        for app in scan.applications {
            #expect(InstalledAppCatalog.validatedApplication(at: app.url) != nil)
            #expect(FileManager.default.fileExists(atPath: app.url.path))
        }
        print("INSTALLED APP AUDIT: \(scan.applications.count) current readable executable bundles; \(scan.unreadableLocations) unreadable roots.")
    }
}
