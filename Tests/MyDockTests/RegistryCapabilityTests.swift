import Foundation
import Testing
@testable import MyDock

@MainActor
struct RegistryCapabilityTests {
    /// Captured from the pre-descriptor WidgetPresentationCatalog switch statements.
    /// Format: name#defaultLayout#layout|width|title|detail;...
    private static let legacySnapshot: [String] = [
        "Stock#compact#compact|108|Compact|Ticker and price;trend|176|Trend|Price and market history",
        "Watchlist#compact#compact|108|Compact|Ticker and price;trend|176|Trend|Price and market history",
        "Calendar#compact#compact|88|Compact|At a glance;wide|154|Wide|Next item and count",
        "Reminders#compact#compact|88|Compact|At a glance;wide|154|Wide|Next item and count",
        "Now Playing#wide#compact|112|Compact|Artwork and track;wide|186|Track|Track and artist",
        "Weather#standard#compact|92|Compact|Temperature and condition;standard|132|Standard|Place and current weather;wide|184|Forecast|Upcoming hours",
        "Focus Timer#compact#compact|88|Compact|Timer and state;standard|124|Standard|Time and progress",
        "Sticky Note#standard#standard|120|Standard|A short note;wide|176|Wide|More of your note",
        "Battery#compact#compact|90|Compact|Charge and battery shape;wide|156|Wide|Mac and available accessories",
        "Shortcuts#icon#icon|54|Icon|Quick action;compact|88|Compact|Action and identity",
        "Stripe#compact#compact|88|Compact|Essential information;standard|124|Standard|More context",
        "Paddle#compact#compact|88|Compact|Essential information;standard|124|Standard|More context",
        "Shopify#compact#compact|88|Compact|Essential information;standard|124|Standard|More context",
        "Clock#compact#compact|104|Compact|Local time;standard|112|Standard|Time and date",
        "World Clock#compact#compact|88|Compact|Primary city;wide|164|Wide|City and time zone",
        "Stopwatch#compact#compact|88|Compact|Timer and state;standard|124|Standard|Time and progress",
        "Countdown#compact#compact|88|Compact|Timer and state;standard|124|Standard|Time and progress",
        "Alarm#compact#compact|88|Compact|Essential information;standard|124|Standard|More context",
        "Time Progress#compact#compact|88|Compact|Essential information;standard|124|Standard|More context",
        "Hydration#compact#compact|88|Compact|Essential information;standard|124|Standard|More context",
        "System Activity#compact#compact|86|Compact|CPU and live history;meter|92|Meter|CPU with a small meter;trend|158|Trend|History and one secondary reading",
        "Network Activity#compact#compact|100|Compact|Download and upload;trend|170|Trend|Rates and download history",
        "AI Limits#compact#compact|88|Compact|Essential information;standard|124|Standard|More context",
        "AI Activity#standard#compact|88|Compact|Usage total;standard|126|Standard|Total and session metadata;trend|184|Activity|History without chart axes",
        "AirDrop#icon#icon|54|Icon|Quick action;compact|88|Compact|Action and identity",
        "Trash#icon#icon|54|Icon|Quick action;compact|88|Compact|Action and identity",
        "Disk Space#compact#compact|104|Compact|Free space and capacity bar;wide|158|Wide|Available and total capacity",
        "Calculator#icon#icon|54|Icon|Quick action;compact|88|Compact|Action and identity",
        "Quick Checklist#compact#compact|88|Compact|At a glance;wide|154|Wide|Next item and count",
        "File Shelf#compact#compact|96|Compact|Saved item count;wide|164|Wide|Count and most recent item",
        "Text Snippets#compact#compact|96|Compact|Saved item count;wide|164|Wide|Count and most recent item",
        "Quick Links#compact#compact|96|Compact|Saved item count;wide|164|Wide|Count and most recent item",
        "Unit Converter#icon#icon|54|Icon|Quick tool;compact|104|Compact|Tool and identity",
        "Color Picker#icon#icon|54|Icon|Quick tool;compact|104|Compact|Tool and identity",
        "App Folder#icon#icon|54|Icon|Quick action;compact|88|Compact|Action and identity"
    ]

    private static func snapshotLine(_ name: String) -> String {
        let options = WidgetPresentationCatalog.options(for: name)
            .map { "\($0.layout.rawValue)|\(Int($0.width))|\($0.title)|\($0.detail)" }.joined(separator: ";")
        return "\(name)#\(WidgetPresentationCatalog.defaultLayout(for: name).rawValue)#\(options)"
    }

    @Test func presentationOutputIsIdenticalToLegacyCatalogForAllFamilies() {
        #expect(Self.legacySnapshot.count == 35)
        #expect(WidgetRegistry.all.map(\.name) == Self.legacySnapshot.map { String($0.split(separator: "#", maxSplits: 1)[0]) })
        for line in Self.legacySnapshot {
            let name = String(line.split(separator: "#", maxSplits: 1)[0])
            #expect(Self.snapshotLine(name) == line, "\(name) presentation changed")
        }
    }

    @Test func unknownKindKeepsGenericFallback() {
        #expect(WidgetPresentationCatalog.options(for: "Nope").map(\.layout) == [.compact, .standard])
        #expect(WidgetPresentationCatalog.defaultLayout(for: "Nope") == .compact)
    }

    @Test func everyDescriptorIsComplete() {
        for definition in WidgetRegistry.all {
            let capabilities = definition.capabilities
            #expect(!capabilities.layouts.isEmpty, "\(definition.name) has no layouts")
            #expect(capabilities.layouts.contains { $0.layout == capabilities.defaultLayout }, "\(definition.name) default layout is not offered")
            #expect(Set(capabilities.layouts.map(\.layout)).count == capabilities.layouts.count)
            #expect(capabilities.layouts.allSatisfy { $0.width > 0 && !$0.title.isEmpty && !$0.detail.isEmpty })
            #expect(!definition.symbol.isEmpty && !definition.description.isEmpty)
            if capabilities.needsConnection { #expect(capabilities.hasSetupState, "\(definition.name) needs a connection but has no setup state") }
        }
    }

    @Test func capabilityFlagsMatchKnownFamilies() {
        func caps(_ name: String) -> WidgetCapabilities { WidgetRegistry.definition(named: name)!.capabilities }
        #expect(caps("Stripe").needsConnection && caps("Paddle").needsConnection && caps("Shopify").needsConnection)
        #expect(caps("Stripe").holdsPrivateContent)
        #expect(caps("Calendar").permissions == [.calendars])
        #expect(caps("Reminders").permissions == [.reminders])
        #expect(caps("Weather").permissions == [.location])
        #expect(caps("Battery").permissions.isEmpty && !caps("Battery").needsConnection)
        #expect(caps("Battery").refreshDemand == .localSampling)
        #expect(caps("Sticky Note").holdsPrivateContent && caps("Quick Checklist").holdsPrivateContent)
        #expect(!caps("Clock").holdsPrivateContent)
    }

    @Test func providerDictionaryKeysEqualRegistryNames() {
        #expect(WidgetProviderRegistry.registeredKinds == Set(WidgetRegistry.all.map(\.name)))
    }

    @Test func batteryPopoutHoldsDemandOnlyWhileVisible() {
        let scheduler = RefreshScheduler.makeForTesting(dockVisible: false)
        let monitor = BatteryMonitor(scheduler: scheduler)
        #expect(!scheduler.isActive && !monitor.holdsPopoutDemand && !monitor.isSampling)
        let face = UUID(), popout = UUID()
        monitor.subscribe(face)
        #expect(!scheduler.isActive, "dock face alone must not refresh with the Dock hidden")
        monitor.subscribe(popout, popout: true)
        #expect(scheduler.isActive && monitor.holdsPopoutDemand)
        monitor.unsubscribe(popout)
        #expect(!scheduler.isActive && !monitor.holdsPopoutDemand)
        monitor.unsubscribe(face)
        #expect(!monitor.isSampling)
        monitor.subscribe(popout, popout: true)
        monitor.subscribe(popout, popout: true)
        monitor.unsubscribe(popout)
        #expect(!scheduler.isActive && !monitor.isSampling)
    }
}
