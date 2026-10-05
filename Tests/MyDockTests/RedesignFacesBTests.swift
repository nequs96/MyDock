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

    @Test func limitHeroUsesPrimaryUntilWarningAndOnlyDockProvider() throws {
        for value in [Int?.none, 0, 28, 89] { #expect(AIFacePresentation.limitHeroColor(usedPercent: value) == Color.primary) }
        #expect(AIFacePresentation.limitHeroColor(usedPercent: 90) == WidgetPalette.warning)
        #expect(AIFacePresentation.limitHeroColor(usedPercent: 100) == WidgetPalette.critical)
        var c = WidgetConfiguration()
        c.aiLimitsVisibleProviders = [.claude, .copilot]
        c.aiLimitsCompactProvider = .copilot
        c.aiLimitsSnapshot = AILimitsSnapshot(fetchedAt: .now, readings: [
            AIProviderLimitReading(provider: .claude, availability: .available, windows: [.init(name: "Session", usedPercent: 90)]),
            AIProviderLimitReading(provider: .copilot, availability: .available, windows: [.init(name: "Monthly credits", usedPercent: 28)])
        ])
        #expect(AIFacePresentation.primaryReading(configuration: c)?.provider == .copilot)
        c.aiLimitsSnapshot?.readings.removeAll { $0.provider == .copilot }
        #expect(AIFacePresentation.primaryReading(configuration: c) == nil)
        c.aiLimitsVisibleProviders = [.claude]
        #expect(AIFacePresentation.primaryReading(configuration: c)?.provider == .claude)
    }
    @Test func narrowActivityCandidateRoundsWithoutDecimalsAndKeepsPartialMarker() throws {
        var snapshot = try #require(AIActivityPreviewData.item().widgetConfiguration?.aiActivitySnapshot)
        snapshot.totals.totalTokens = 643_900_000
        #expect(AIFacePresentation.narrowActivityValue(snapshot: snapshot, locale: Locale(identifier: "pl_PL")) == "644M")
        snapshot.partial = true
        snapshot.estimated = false
        #expect(AIFacePresentation.narrowActivityValue(snapshot: snapshot) == "644M+")
        snapshot.estimated = true
        #expect(AIFacePresentation.narrowActivityValue(snapshot: snapshot) == "644M")
        snapshot.totals.totalTokens = 999
        #expect(AIFacePresentation.narrowActivityValue(snapshot: snapshot) == "999")
        #expect(AIFacePresentation.narrowActivityValue(snapshot: nil) == "Set up")
    }
    @Test func networkFiltersIdleLinkLocalInterfacesWithoutLosingTraffic() {
        let interfaces: [NetworkInterfaceRate] = [
            .init(name: "en0", receivedBytesPerSecond: 0, sentBytesPerSecond: 0, addresses: ["192.168.1.2", "fe80::1%en0"]),
            .init(name: "utun0", receivedBytesPerSecond: 1, sentBytesPerSecond: nil, addresses: ["fe80::2"]),
            .init(name: "awdl0", receivedBytesPerSecond: 0, sentBytesPerSecond: 0, addresses: ["fe80::3"]),
            .init(name: "bridge0", receivedBytesPerSecond: nil, sentBytesPerSecond: nil, addresses: []),
            .init(name: "en1", receivedBytesPerSecond: nil, sentBytesPerSecond: nil, addresses: ["2001:db8::1"])
        ]
        #expect(NetworkInterfacePresentation.active(interfaces).map(\.name) == ["en0", "utun0", "en1"])
        #expect(NetworkInterfacePresentation.other(interfaces).map(\.name) == ["awdl0", "bridge0"])
        #expect(NetworkInterfacePresentation.addresses(interfaces[0].addresses) == ["192.168.1.2"])
        #expect(NetworkInterfacePresentation.addresses(interfaces[1].addresses).isEmpty)
        #expect(NetworkInterfacePresentation.active([]).isEmpty)
    }
    @Test func networkAddressFilterCoversLinkLocalRangesAndInvalidAddresses() {
        for address in ["fe80::1", "FE80::2%en0", "febf::1", "169.254.1.2", "127.0.0.1", "::1", "::", "0.0.0.0", "ff02::1", "::ffff:169.254.1.2", "invalid"] {
            #expect(!NetworkInterfacePresentation.isRoutable(address), "\(address)")
        }
        for address in ["10.0.0.1", "192.0.2.1", "2001:db8::1", "fd12::1", "::ffff:192.0.2.1"] {
            #expect(NetworkInterfacePresentation.isRoutable(address), "\(address)")
        }
    }
    @Test func changeAndSystemFormattersRespectLocale() {
        let polish = Locale(identifier: "pl_PL")
        let english = Locale(identifier: "en_US")
        #expect(StockFaceFormatting.percentText(1.25, locale: polish).contains("+1,25"))
        #expect(StockFaceFormatting.percentText(-1.25, locale: english) == "-1.25%")
        #expect(StockFaceFormatting.changeText(2.5, percent: 1.25, locale: polish).contains("+2,50"))
        #expect(StockFaceFormatting.percentText(0, locale: english) == "+0.00%")
        let load = SystemLoadAverage(oneMinute: 2.4, fiveMinutes: 1.9, fifteenMinutes: 1.4)
        #expect(SystemActivityFormatting.load(load, locale: polish) == "2,40 · 1,90 · 1,40")
        #expect(SystemActivityFormatting.load(load, locale: english) == "2.40 · 1.90 · 1.40")
        #expect(SystemActivityFormatting.bytes(1_500_000_000, locale: polish).contains("1,5"))
        #expect(SystemActivityFormatting.bytes(1_500_000_000, locale: english).contains("1.5"))
    }
    @Test func businessSetupHasOneAccountFieldAndNoUnconnectedSettings() {
        for policy in [StripeSetupPresentation.showsSettings, PaddleSetupPresentation.showsSettings, ShopifySetupPresentation.showsSettings] {
            #expect(!policy("", false))
            #expect(policy("connected-id", false))
            #expect(policy("", true))
            #expect(policy("connected-id", true))
        }
    }

    #if DEBUG
    @Test func businessPeriodTokensStayCompact() {
        #expect(StripePeriod.allCases.map(\.faceToken) == ["Today", "7d", "30d", "90d"])
        #expect(PaddlePeriod.allCases.map(\.faceToken) == ["Today", "7d", "30d", "90d"])
        #expect(ShopifyPeriod.allCases.map(\.faceToken) == ["Today", "7d", "MTD", "30d"])
    }

    @Test func countMetricsNeverClaimCurrencyUnits() {
        #expect(StripeMetric.payingSubscribers.popoutUnit(currency: "USD") == "subscribers")
        #expect(PaddleMetric.activeSubscribers.popoutUnit(currency: "JPY") == "customers")
        #expect(ShopifyMetric.orders.popoutUnit(currency: "EUR") == "orders")
        #expect(StripeMetric.mrr.popoutUnit(currency: "USD") == "USD")
        #expect(PaddleMetric.arr.popoutUnit(currency: "JPY") == "JPY")
        #expect(ShopifyMetric.averageOrderValue.popoutUnit(currency: "EUR") == "EUR")
    }

    @Test func businessFixturesKeepSelectedAccountIdentity() throws {
        for state in [FacesBQA.State.ready, .stale, .unavailable] {
            let stripe = try #require(FacesBQA.item("Stripe", state: state).widgetConfiguration)
            #expect(stripe.stripeAccountID == stripe.stripeSnapshot?.accountID)
            let paddle = try #require(FacesBQA.item("Paddle", state: state).widgetConfiguration)
            #expect(!paddle.paddleAccountID.isEmpty)
            if let snapshot = paddle.paddleSnapshot { #expect(paddle.paddleAccountID == snapshot.accountID) }
            let shopify = try #require(FacesBQA.item("Shopify", state: state).widgetConfiguration)
            #expect(!shopify.shopifyStoreID.isEmpty)
            if let snapshot = shopify.shopifySnapshot { #expect(shopify.shopifyStoreID == snapshot.storeID) }
        }
    }

    @Test func paddleAccessibilityPreservesDatedValuesForEveryMetric() throws {
        var snapshot = try #require(FacesBQA.item("Paddle").widgetConfiguration?.paddleSnapshot)
        let expected = [PaddleMetric.netRevenue: 120.0, .mrr: 4800.0, .arr: 57600.0, .activeSubscribers: 32.0]
        for metric in PaddleMetric.allCases {
            let series = PaddleChartAccessibility.series(snapshot, metric: metric)
            #expect(series.map(\.date) == snapshot.points.map(\.date))
            #expect(series.first?.value == expected[metric])
            #expect(series.count == 7)
        }
        snapshot.currency = "JPY"
        #expect(PaddleChartAccessibility.series(snapshot, metric: .netRevenue).first?.value == 12000)
        snapshot.points = []
        #expect(PaddleChartAccessibility.series(snapshot, metric: .mrr).isEmpty)
    }

    @Test func shopifyAccessibilityPreservesDatedValuesAndZeroOrderDays() throws {
        var snapshot = try #require(FacesBQA.item("Shopify").widgetConfiguration?.shopifySnapshot)
        let expected = [ShopifyMetric.orderValue: 120.0, .orders: 12.0, .averageOrderValue: 10.0]
        for metric in ShopifyMetric.allCases {
            let series = ShopifyChartAccessibility.series(snapshot, metric: metric)
            #expect(series.map(\.date) == snapshot.dailyPoints.map(\.date))
            #expect(series.first?.value == expected[metric])
            #expect(series.count == 7)
        }
        snapshot.dailyPoints = [ShopifyDailyPoint(date: FacesBQA.now, orderValue: 0, orders: 0)]
        #expect(ShopifyChartAccessibility.series(snapshot, metric: .averageOrderValue).first?.value == 0)
    }

    @Test func chartValueListIncludesEveryDateAndCorrectDayBoundary() {
        let locale = Locale(identifier: "en_US")
        let series = [FacesBDatedChartValue(date: Date(timeIntervalSince1970: 1_791_151_200), value: 120),
                      FacesBDatedChartValue(date: Date(timeIntervalSince1970: 1_791_237_600), value: 280)]
        let utc = FacesBChartAccessibility.valueList(series, timeZone: TimeZone(secondsFromGMT: 0)!, currency: "USD", locale: locale)
        let storeLocal = FacesBChartAccessibility.valueList(series, timeZone: TimeZone(identifier: "Europe/Warsaw")!, currency: nil, locale: locale)
        #expect(utc.contains("October 4") && utc.contains("October 5"))
        #expect(utc.contains("$120.00") && utc.contains("$280.00"))
        #expect(storeLocal.contains("October 5") && storeLocal.contains("October 6"))
        #expect(storeLocal.contains(": 120") && storeLocal.contains(": 280"))
        #expect(FacesBChartAccessibility.valueList([], timeZone: .current, currency: nil).isEmpty)
    }

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
