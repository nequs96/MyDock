import Foundation
import Testing
@testable import MyDock

struct DockUtilityExpansionTests {
    @Test func legacyProfilesDefaultToEmptyCollectionsAndNewDataRoundTrips() throws {
        var config = try JSONDecoder().decode(WidgetConfiguration.self, from: Data("{}".utf8))
        #expect(config.shelfFiles.isEmpty && config.textSnippets.isEmpty && config.quickLinks.isEmpty && config.savedColors.isEmpty)
        config.shelfFiles = [ShelfFile(url: URL(fileURLWithPath: "/tmp/example.pdf"))]
        config.textSnippets = [TextSnippet(title: "Reply", text: "Hello 🌍\nThanks!")]
        config.quickLinks = [QuickLink(title: "Project", url: URL(string: "https://example.com/project")!)]
        config.savedColors = ["#5EA3A8"]
        try ProfileSemanticValidator.validate(config)
        #expect(try JSONDecoder().decode(WidgetConfiguration.self, from: JSONEncoder().encode(config)) == config)
    }

    @Test func shelfDeduplicatesRejectsWebURLsAndCapsWithoutChangingOriginals() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("original.txt")
        let contents = Data("Original content".utf8)
        try contents.write(to: file)
        let entries = FileShelfPolicy.adding([file, file, URL(string: "https://example.com")!], to: [])
        #expect(entries.count == 1)
        #expect(entries[0].resolvedURL.standardizedFileURL == file.standardizedFileURL)
        #expect(FileShelfPolicy.adding([file], to: entries) == entries)
        #expect(try Data(contentsOf: file) == contents)
        let filled = FileShelfPolicy.adding((0..<60).map { directory.appendingPathComponent("file\($0)") }, to: entries)
        #expect(filled.count == FileShelfPolicy.capacity)
        #expect(filled.first?.id == entries.first?.id)
        #expect(try Data(contentsOf: file) == contents)
    }

    @Test func exportedPresetsDoNotLeakFileReferencesLinksOrSnippets() {
        var item = DockItem.widget("File Shelf")
        item.widgetConfiguration?.shelfFiles = [ShelfFile(url: URL(fileURLWithPath: "/private/example.pdf"))]
        item.widgetConfiguration?.textSnippets = [TextSnippet(title: "Private", text: "Secret")]
        item.widgetConfiguration?.quickLinks = [QuickLink(title: "Private", url: URL(string: "https://example.com/?token=secret")!)]
        let profile = DockProfile(name: "Utility", kind: .custom, items: [item])
        let publicConfig = ProfileSanitizer.sanitize(profile).items[0].widgetConfiguration
        #expect(publicConfig?.shelfFiles.isEmpty == true)
        #expect(publicConfig?.textSnippets.isEmpty == true)
        #expect(publicConfig?.quickLinks.isEmpty == true)
        let withNotes = ProfileSanitizer.sanitize(profile, includeNotes: true).items[0].widgetConfiguration
        #expect(withNotes?.textSnippets.count == 1)
        #expect(withNotes?.shelfFiles.isEmpty == true && withNotes?.quickLinks.isEmpty == true)
    }

    @Test @MainActor func savedCollectionsSurviveStoreRelaunchAndEditing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let item = DockItem.widget("File Shelf")
        let id = try store.createProfile(DockProfile(name: "Tools", kind: .custom, items: [item]))
        store.updateWidgetConfiguration(itemID: item.id, in: id) {
            $0.shelfFiles = FileShelfPolicy.adding([URL(fileURLWithPath: "/tmp/later.pdf")], to: $0.shelfFiles)
            $0.textSnippets = [TextSnippet(title: "Reply", text: "Thank you")]
            $0.quickLinks = [QuickLink(title: "Project", url: URL(string: "https://example.com")!)]
            $0.savedColors = ["#33AAFF"]
        }
        store.flush()
        let restored = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let config = try #require(restored.state.profiles.first { $0.id == id }?.items.first?.widgetConfiguration)
        #expect(config.shelfFiles.count == 1 && config.textSnippets.first?.text == "Thank you")
        #expect(config.quickLinks.count == 1 && config.savedColors == ["#33AAFF"])
        restored.updateWidgetConfiguration(itemID: item.id, in: id) { $0.shelfFiles = []; $0.textSnippets[0].text = "Updated" }
        restored.flush()
        let updated = ProfileStore(fileURL: file, allowsSystemChanges: false).state.profiles.first { $0.id == id }?.items.first?.widgetConfiguration
        #expect(updated?.shelfFiles.isEmpty == true && updated?.textSnippets.first?.text == "Updated")
    }

    @Test func malformedCollectionsAreRejected() {
        var config = WidgetConfiguration()
        config.quickLinks = [QuickLink(title: "Unsafe", url: URL(string: "javascript:alert(1)")!)]
        #expect(throws: (any Error).self) { try ProfileSemanticValidator.validate(config) }
        config.quickLinks = []
        config.textSnippets = [TextSnippet(title: "A", text: "B")]
        config.textSnippets.append(config.textSnippets[0])
        #expect(throws: (any Error).self) { try ProfileSemanticValidator.validate(config) }
        config.textSnippets = []
        config.savedColors = ["#FFFFFF", "#FFFFFF"]
        #expect(throws: (any Error).self) { try ProfileSemanticValidator.validate(config) }
        config.savedColors = ["not a color"]
        #expect(throws: (any Error).self) { try ProfileSemanticValidator.validate(config) }
        config.savedColors = []
        config.shelfFiles = [ShelfFile(url: URL(string: "https://example.com")!)]
        #expect(throws: (any Error).self) { try ProfileSemanticValidator.validate(config) }
    }

    @Test func conversionHandlesOffsetsAndDecimalVersusBinaryData() throws {
        func converted(_ value: Double, _ category: ConversionCategory, _ from: String, _ to: String) throws -> Double {
            let source = try #require(category.units.first { $0.symbol == from })
            let target = try #require(category.units.first { $0.symbol == to })
            return try #require(ConversionUnit.convert(value, from: source, to: target))
        }
        #expect(abs(try converted(0, .temperature, "°C", "°F") - 32) < 0.000001)
        #expect(abs(try converted(212, .temperature, "°F", "°C") - 100) < 0.000001)
        #expect(abs(try converted(-40, .temperature, "°F", "°C") + 40) < 0.000001)
        #expect(try converted(1, .length, "mi", "m") == 1_609.344)
        #expect(try converted(1, .data, "MB", "B") == 1_000_000)
        #expect(try converted(1, .data, "MiB", "B") == 1_048_576)
        #expect(abs(try converted(60, .speed, "mph", "km/h") - 96.56064) < 0.000001)
        for category in ConversionCategory.allCases {
            let a = category.units[0], b = category.units[1]
            let converted = try #require(ConversionUnit.convert(123.45, from: a, to: b))
            #expect(abs((ConversionUnit.convert(converted, from: b, to: a) ?? 0) - 123.45) < 0.000001)
            #expect(ConversionUnit.convert(.infinity, from: a, to: b) == nil)
        }
    }

    @Test func hexColorSupportsShortNotationAndRejectsMalformedInput() throws {
        let c = try #require(HexColor.components(" #3Af "))
        #expect(HexColor.string(red: c.red, green: c.green, blue: c.blue) == "#33AAFF")
        #expect(HexColor.string(red: .nan, green: 2, blue: -1) == "#00FF00")
        for invalid in ["", "#", "#12", "#12345", "#FFGG00", "#12345678", "＃FFFFFF"] { #expect(HexColor.components(invalid) == nil) }
    }

    @Test @MainActor func expandedLibraryHasRealProvidersAndSemanticLayouts() {
        for kind in ["File Shelf", "Text Snippets", "Quick Links", "Unit Converter", "Color Picker"] {
            #expect(WidgetRegistry.all.contains { $0.name == kind })
            #expect(!String(describing: type(of: WidgetProviderRegistry.provider(for: kind))).contains("Placeholder"))
            #expect(!WidgetPresentationCatalog.options(for: kind).isEmpty)
        }
        #expect(WidgetRegistry.all.count == 36)
    }
}
