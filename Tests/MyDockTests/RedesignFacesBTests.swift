import AppKit
import SwiftUI
import Testing
@testable import MyDock

@MainActor
struct RedesignFacesBTests {
    @Test func negativeChangesCarryStateColour() {
        #expect(StockFaceFormatting.changeColor(-0.01) == WidgetPalette.critical)
        for value in [Double?.none, 0, 1, .nan, .infinity] {
            #expect(StockFaceFormatting.changeColor(value) == Color.secondary)
        }
    }
    @Test func financialValuesFitNarrowFacesWithoutLosingSign() {
        let locale = Locale(identifier: "en_US_POSIX")
        #expect(FacesBFinancialFormatting.compact(2_400, currency: "USD", narrow: true, locale: locale) == "2.4K")
        #expect(FacesBFinancialFormatting.compact(-2_400, currency: "USD", narrow: true, locale: locale) == "-2.4K")
        #expect(FacesBFinancialFormatting.compact(12_000_000, currency: nil, narrow: true, locale: locale) == "12M")
        #expect(FacesBFinancialFormatting.compact(0, currency: "JPY", narrow: true, locale: locale) == "0")
        #expect(FacesBFinancialFormatting.compact(.nan, currency: nil, narrow: true, locale: locale) == "—")
        #expect(FacesBFinancialFormatting.compact(2_400, currency: "USD", narrow: false, locale: locale).contains("2.4K"))
        #expect(FacesBFinancialFormatting.stateColor(-1) == WidgetPalette.critical)
        #expect(FacesBFinancialFormatting.stateColor(1) == Color.primary)
    }
    @Test func limitStateUsesUsedCapacity() {
        #expect(AIFacePresentation.limitColor(usedPercent: nil) == Color.secondary)
        #expect(AIFacePresentation.limitColor(usedPercent: 89) == Color.secondary)
        #expect(AIFacePresentation.limitColor(usedPercent: 90) == WidgetPalette.warning)
        #expect(AIFacePresentation.limitColor(usedPercent: 100) == WidgetPalette.critical)
        #expect(AIFacePresentation.limitColor(usedPercent: 120) == WidgetPalette.critical)
    }
    @Test func hiddenLimitProviderFallsBackInAuthoredOrder() {
        var c = WidgetConfiguration()
        c.aiLimitsVisibleProviders = [.claude, .copilot]
        c.aiLimitsCompactProvider = .codex
        c.aiLimitsProviderOrder = [.copilot, .claude, .codex]
        #expect(AIFacePresentation.selectedProvider(configuration: c) == .copilot)
        c.aiLimitsCompactProvider = .claude
        #expect(AIFacePresentation.selectedProvider(configuration: c) == .claude)
        c.aiLimitsVisibleProviders = []
        #expect(AIFacePresentation.selectedProvider(configuration: c) == nil)
    }
    @Test func unavailableLimitsDoNotClaimSetupOrZero() {
        let reading = AIProviderLimitReading(provider: .copilot, availability: .unavailable, windows: [])
        #expect(AIFacePresentation.limitValue(reading: nil, mode: .remaining) == "Set up")
        #expect(AIFacePresentation.limitValue(reading: reading, mode: .remaining) == "—")
        var available = reading
        available.windows = [AILimitWindow(name: "Session", usedPercent: 28, durationMinutes: 300)]
        #expect(AIFacePresentation.limitValue(reading: available, mode: .remaining) == "72%")
        #expect(AIFacePresentation.limitValue(reading: available, mode: .used) == "28%")
    }
    @Test func partialActivityKeepsItsTruthfulMarker() throws {
        var snapshot = try #require(AIActivityPreviewData.item().widgetConfiguration?.aiActivitySnapshot)
        let value = AIFacePresentation.activityValue(snapshot: snapshot)
        #expect(!value.isEmpty && !value.hasSuffix("+"))
        snapshot.partial = true
        #expect(AIFacePresentation.activityValue(snapshot: snapshot) == value + "+")
        snapshot.estimated = true
        #expect(AIFacePresentation.activityValue(snapshot: snapshot) == value)
        snapshot.available = false
        #expect(AIFacePresentation.activityValue(snapshot: snapshot) == "No data")
        #expect(AIFacePresentation.activityValue(snapshot: nil) == "Set up")
    }

    #if DEBUG
    @Test func activityPopoutFixtureSurvivesRuntimeProjection() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FacesBProjection-\(UUID())/state.json")
        let store = ProfileStore(fileURL: url, allowsSystemChanges: false)
        let id = try store.createProfileAndPersist(kind: .custom, name: "QA projection")
        for state in [FacesBQA.State.ready, .stale, .unavailable] {
            let item = FacesBQA.item("AI Activity", state: state)
            store.add(item, to: id)
            let projected = try #require(store.presentationConfiguration(for: item, in: id).aiActivitySnapshot)
            #expect(projected.available == (state != .unavailable))
            #expect(projected.partial == (state == .stale))
        }
    }

    /// Rasterise actual provider faces, without a container fill that could conceal an empty face.
    /// Covers every advertised layout plus 54 pt side-Dock and hidden labels.
    @Test func allOwnedFamiliesRenderVisibleContent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FacesBTests-\(UUID())/state.json")
        let store = ProfileStore(fileURL: url, allowsSystemChanges: false)
        let profileID = UUID()
        var matrix = WidgetQAMatrix()
        for kind in FacesBQA.families {
            let definition = try #require(WidgetRegistry.definition(named: kind))
            #expect(WidgetCardPreview.accessibilityLabel(kind: kind) == "\(kind), sample preview")
            for option in definition.capabilities.layouts {
                for width in [CGFloat(option.width), 54] {
                    for showsLabel in [true, false] {
                        for state in [FacesBQA.State.ready, .setup] {
                            let renderer = ImageRenderer(content: FacesBQA.face(kind: kind, state: state, layout: option.layout,
                                width: width, store: store, profileID: profileID)
                                .environment(\.widgetShowsLabel, showsLabel).environment(\.colorScheme, .light))
                            let image = try #require(renderer.cgImage, "\(kind) \(option.layout) width \(width)")
                            let data = try #require(image.dataProvider?.data)
                            let bytes = CFDataGetBytePtr(data)!
                            var visiblePixels = 0
                            for y in 0..<image.height {
                                for x in 0..<image.width {
                                    let pixel = y * image.bytesPerRow + x * 4
                                    if bytes[pixel + 3] > 8 { visiblePixels += 1 }
                                }
                            }
                            #expect(visiblePixels > 20, "\(kind) \(option.layout) \(state) width \(width), labels \(showsLabel)")
                        }
                    }
                }
                matrix.record(kind, .layout(option.layout))
            }
            matrix.record(kind, .setup)
        }
        try matrix.validate(registry: WidgetRegistry.all.filter { FacesBQA.families.contains($0.name) })
    }
    #endif
}
