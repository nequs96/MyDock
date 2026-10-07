import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MyDock

/// PX-7 (OP-07): System Activity is the one System detail surface, with optional Network and Storage
/// sections. New widgets start with both on; widgets saved before PX-7 keep today's popout.
@MainActor
struct SystemDetailSurfaceTests {
    // A System Activity item as saved before PX-7: no section keys.
    private static let oldSystemActivityItem = #"""
    {"id":"6F1B7C1E-0F7B-4C55-9E52-6A1C1D2B3A40","type":"widget","title":"System Activity","widgetKind":"System Activity",
     "widgetConfiguration":{"cardWidth":"standard","iconStyle":"live","iconAppearance":"soft","systemSecondaryMetric":"memory"}}
    """#

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: Section defaults

    @Test func newSystemActivityWidgetsShowBothSections() throws {
        let configuration = try #require(DockItem.widget("System Activity").widgetConfiguration)
        #expect(configuration.systemShowsNetwork == true)
        #expect(configuration.systemShowsStorage == true)
        #expect(SystemDetailSections.showsNetwork(configuration))
        #expect(SystemDetailSections.showsStorage(configuration))
    }

    @Test func otherFamiliesAndTheBareDefaultCarryNoSectionKeys() throws {
        for kind in ["Network Activity", "Disk Space", "Clock"] {
            let configuration = try #require(DockItem.widget(kind).widgetConfiguration)
            #expect(configuration.systemShowsNetwork == nil, "\(kind)")
            #expect(configuration.systemShowsStorage == nil, "\(kind)")
        }
        let bare = WidgetConfiguration()
        #expect(bare.systemShowsNetwork == nil && bare.systemShowsStorage == nil)
        #expect(!SystemDetailSections.showsNetwork(bare))
        #expect(!SystemDetailSections.showsStorage(bare))
    }

    @Test func savedWidgetsWithoutTheKeysShowNoNewSections() throws {
        let item = try decode(DockItem.self, Self.oldSystemActivityItem)
        let configuration = try #require(item.widgetConfiguration)
        #expect(configuration.systemShowsNetwork == nil)
        #expect(configuration.systemShowsStorage == nil)
        #expect(!SystemDetailSections.showsNetwork(configuration))
        #expect(!SystemDetailSections.showsStorage(configuration))
        #expect(configuration.systemSecondaryMetric == .memory)

        // Re-encoding an untouched old widget adds no keys.
        let encoded = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        #expect(!encoded.contains("systemShowsNetwork"))
        #expect(!encoded.contains("systemShowsStorage"))
        #expect(try decode(DockItem.self, encoded) == item)
    }

    @Test func aChosenSectionRoundTripsIncludingOff() throws {
        for network in [true, false] {
            for storage in [true, false] {
                var configuration = WidgetConfiguration()
                configuration.systemShowsNetwork = network
                configuration.systemShowsStorage = storage
                let decoded = try JSONDecoder().decode(WidgetConfiguration.self, from: JSONEncoder().encode(configuration))
                #expect(decoded == configuration)
                #expect(SystemDetailSections.showsNetwork(decoded) == network)
                #expect(SystemDetailSections.showsStorage(decoded) == storage)
            }
        }
    }

    @Test func malformedSectionValuesDecodeLenientlyAsAbsent() throws {
        let configuration = try decode(WidgetConfiguration.self,
                                       #"{"systemShowsNetwork":"yes","systemShowsStorage":1,"systemSecondaryMetric":"memory"}"#)
        #expect(configuration.systemShowsNetwork == nil)
        #expect(configuration.systemShowsStorage == nil)
        #expect(configuration.systemSecondaryMetric == .memory)
    }

    // MARK: Link from the independent families

    @Test func theLinkTargetsThisDocksSystemActivityWidgetOnly() {
        let network = DockItem.widget("Network Activity")
        let disk = DockItem.widget("Disk Space")
        let system = DockItem.widget("System Activity")
        let lookalike = DockItem(type: .application, title: "System Activity")
        #expect(SystemDetailSections.systemActivityItemID(in: [network, disk, system]) == system.id)
        #expect(SystemDetailSections.systemActivityItemID(in: [network, disk, lookalike]) == nil)
        #expect(SystemDetailSections.systemActivityItemID(in: []) == nil)
    }

    // MARK: Row formatting

    @Test func ratesUseFileByteUnitsPerSecond() {
        #expect(SystemDetailFormatting.rate(2_400_000) == ByteCountFormatter.string(fromByteCount: 2_400_000, countStyle: .file) + "/s")
        #expect(SystemDetailFormatting.rate(0) == ByteCountFormatter.string(fromByteCount: 0, countStyle: .file) + "/s")
        for invalid: Double? in [nil, -1, .nan, .infinity] {
            #expect(SystemDetailFormatting.rate(invalid) == nil)
        }
        // Enormous finite readings clamp instead of trapping.
        #expect(SystemDetailFormatting.rate(1e30)?.hasSuffix("/s") == true)
        #expect(SystemDetailFormatting.rate(Double(Int64.max))?.hasSuffix("/s") == true)

        #expect(SystemDetailFormatting.rateValue(nil, hasCompletedSample: false) == "Warming up")
        #expect(SystemDetailFormatting.rateValue(nil, hasCompletedSample: true) == "Unavailable")
        #expect(SystemDetailFormatting.rateValue(148_000, hasCompletedSample: true) == SystemDetailFormatting.rate(148_000))
    }

    @Test func storageRowsShowAvailableAndRoundedUse() {
        let snapshot = DiskSpaceSnapshot(name: "Macintosh HD", totalBytes: 500_000_000_000, availableBytes: 128_000_000_000)
        #expect(SystemDetailFormatting.usedPercent(snapshot) == 74)
        #expect(SystemDetailFormatting.storageAvailable(snapshot) == "\(snapshot.availableText) available")
        #expect(SystemDetailFormatting.storageUsed(snapshot) == "74% of \(snapshot.totalText) used")
        #expect(SystemDetailFormatting.usedPercent(DiskSpaceSnapshot(name: "D", totalBytes: 0, availableBytes: 0)) == 0)
        #expect(SystemDetailFormatting.usedPercent(DiskSpaceSnapshot(name: "D", totalBytes: 100, availableBytes: -5)) == 100)
        #expect(SystemDetailFormatting.usedPercent(DiskSpaceSnapshot(name: "D", totalBytes: 100, availableBytes: 500)) == 0)
    }

    @Test func freshnessFollowsTheSharedRule() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let network = SystemDetailSections.networkMaximumAge
        let storage = SystemDetailSections.storageMaximumAge
        #expect(SystemDetailFormatting.freshness(updatedAt: nil, failed: false, now: now, maximumAge: network) == "Waiting for a reading")
        #expect(SystemDetailFormatting.freshness(updatedAt: nil, failed: true, now: now, maximumAge: storage) == "Reading unavailable")
        #expect(SystemDetailFormatting.freshness(updatedAt: now, failed: false, now: now, maximumAge: network) == "Updated just now")
        #expect(SystemDetailFormatting.freshness(updatedAt: now.addingTimeInterval(-4), failed: false, now: now, maximumAge: network) == "Updated just now")
        // Past three network samples the reading is stale, never "Updated".
        // A stale reading under a minute old counts seconds instead of saying "just now".
        let staleNetwork = SystemDetailFormatting.freshness(updatedAt: now.addingTimeInterval(-30), failed: false, now: now, maximumAge: network)
        #expect(staleNetwork.hasPrefix("Last reading ") && !staleNetwork.contains("just now") && staleNetwork.contains("30"))
        let older = SystemDetailFormatting.freshness(updatedAt: now.addingTimeInterval(-90), failed: false, now: now, maximumAge: storage)
        #expect(older.hasPrefix("Updated ") && older != "Updated just now")
        #expect(SystemDetailFormatting.freshness(updatedAt: now.addingTimeInterval(-300), failed: false, now: now, maximumAge: storage).hasPrefix("Last reading "))
        // A failed refresh keeps the last reading and says how old it is.
        let failedRecent = SystemDetailFormatting.freshness(updatedAt: now.addingTimeInterval(-10), failed: true, now: now, maximumAge: storage)
        #expect(failedRecent.hasPrefix("Last reading ") && !failedRecent.contains("just now") && failedRecent.contains("10"))
        #expect(SystemDetailSections.storageInterval == 60)
    }

    // MARK: Height

    private func expectRigid(_ view: some View, _ label: String) {
        let measure = NSHostingController(rootView: AnyView(view.environment(\.colorScheme, .dark).environment(\.dockSnapshotRendering, true)))
        let width: CGFloat = 460
        let squeezed = measure.sizeThatFits(in: CGSize(width: width, height: 1)).height
        let roomy = measure.sizeThatFits(in: CGSize(width: width, height: 20_000)).height
        #expect(abs(squeezed - roomy) < 0.5, "\(label): popout height \(squeezed) when squeezed vs \(roomy) with room")
    }

    @Test func popoutsWithTheNewSectionsAndLinkStayRigid() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let id = try store.createProfileAndPersist(kind: .custom, name: "System detail")
        let system = DockItem.widget("System Activity")
        let network = DockItem.widget("Network Activity")
        let disk = DockItem.widget("Disk Space")
        for item in [system, network, disk] { store.add(item, to: id) }
        let opener = WidgetPopoutOpener(open: { _ in })
        for item in [system, network, disk] {
            let popout = WidgetPopout(store: store, item: item, profileID: id).padding(20)
                .environment(\.widgetPopoutOpener, opener)
            expectRigid(popout, item.title)
        }
        // Existing System Activity widgets (keys absent) keep the previous popout.
        store.updateWidgetConfiguration(itemID: system.id, in: id) {
            $0.systemShowsNetwork = nil
            $0.systemShowsStorage = nil
        }
        expectRigid(WidgetPopout(store: store, item: system, profileID: id).padding(20), "System Activity, sections absent")
    }
}
