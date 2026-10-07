import SwiftUI

// MARK: - PX-7 (OP-07): one System detail surface

/// The System Activity popout is the one System detail surface. Below its CPU and memory content it can
/// show a compact Network section (the shared `NetworkActivityMonitor`) and a Storage section (the Disk
/// Space reader). Both read only while the popout is visible; the Dock faces stay independent.
/// Like every optional surface that samples, both start off; the popout's settings turn them on.
enum SystemDetailSections {
    /// Whether the popout shows Network. Absent (a new widget, or one saved before PX-7) means off.
    static func showsNetwork(_ configuration: WidgetConfiguration) -> Bool { configuration.systemShowsNetwork ?? false }

    /// Whether the popout shows Storage. Absent (a new widget, or one saved before PX-7) means off.
    static func showsStorage(_ configuration: WidgetConfiguration) -> Bool { configuration.systemShowsStorage ?? false }

    /// The System Activity widget on this Dock that a Network Activity or Disk Space popout links to.
    static func systemActivityItemID(in items: [DockItem]) -> UUID? {
        items.first { $0.type == .widget && $0.widgetKind == "System Activity" }?.id
    }

    /// Network rates sample every 4 seconds; a reading older than three samples reads as stale.
    static let networkMaximumAge: TimeInterval = 12
    /// Storage samples on the Disk Space family's own interval and staleness rule.
    static let storageInterval: TimeInterval = 60
    static let storageMaximumAge: TimeInterval = 120
}

/// Units and freshness for the related rows. Pure, so tests cover them without a monitor.
enum SystemDetailFormatting {
    /// A transfer rate in file-style byte units per second, or nil for a missing or invalid reading.
    static func rate(_ bytesPerSecond: Double?) -> String? {
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return nil }
        // Double(Int64.max) rounds up to 2^63, which Int64 cannot hold: clamp below it.
        let bytes = bytesPerSecond < 9.0e18 ? Int64(bytesPerSecond) : Int64.max
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + "/s"
    }

    /// The row value: the rate, or why there is none yet.
    static func rateValue(_ bytesPerSecond: Double?, hasCompletedSample: Bool) -> String {
        if let text = rate(bytesPerSecond) { return text }
        return hasCompletedSample ? "Unavailable" : "Warming up"
    }

    static func usedPercent(_ snapshot: DiskSpaceSnapshot) -> Int {
        let fraction = snapshot.usedFraction
        guard fraction.isFinite else { return 0 }
        return Int((min(1, max(0, fraction)) * 100).rounded())
    }

    /// "128 GB available"
    static func storageAvailable(_ snapshot: DiskSpaceSnapshot) -> String { "\(snapshot.availableText) available" }

    /// "74% of 500 GB used"
    static func storageUsed(_ snapshot: DiskSpaceSnapshot) -> String { "\(usedPercent(snapshot))% of \(snapshot.totalText) used" }

    /// The section footer: when the reading was taken, following the shared freshness rule.
    static func freshness(updatedAt: Date?, failed: Bool, now: Date, maximumAge: TimeInterval) -> String {
        let state = WidgetFreshnessPresentation.state(isRefreshing: false, updatedAt: updatedAt, failed: failed,
                                                      now: now, maximumAge: maximumAge)
        func relative(_ date: Date, stale: Bool) -> String {
            let age = now.timeIntervalSince(date)
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            formatter.dateTimeStyle = .numeric
            guard abs(age) < 60 else { return formatter.localizedString(for: date, relativeTo: now) }
            // A stale reading never says "just now": under a minute it counts the seconds.
            return stale ? formatter.localizedString(fromTimeInterval: -max(1, age.rounded())) : "just now"
        }
        switch state {
        case .fresh: return "Updated " + (updatedAt.map { relative($0, stale: false) } ?? "just now")
        case .stale: return updatedAt.map { "Last reading " + relative($0, stale: true) } ?? "Reading unavailable"
        case .updating, .empty: return "Waiting for a reading"
        }
    }
}

// MARK: - Network

/// Download and upload with a tiny history line. Subscribes to the shared monitor only while shown.
struct SystemDetailNetworkSection: View {
    @StateObject private var monitor = NetworkActivityMonitor.shared
    @State private var subscriptionID = UUID()
    @DockAccessibilityStyle() private var accessibility
    #if DEBUG
    @Environment(\.networkActivityFixture) private var fixture
    #endif

    init() {}

    /// Every field comes from one reading: the live monitor, or (DEBUG render QA) a fixture.
    private var readings: NetworkActivityReadings {
        #if DEBUG
        if let fixture { return fixture }
        #endif
        return NetworkActivityReadings(monitor)
    }
    private var isFixture: Bool {
        #if DEBUG
        return fixture != nil
        #else
        return false
        #endif
    }

    var body: some View {
        // The footer's age stays current when samples stop arriving, so a frozen reading turns stale.
        let reading = readings
        TimelineView(.periodic(from: .now, by: 4)) { context in
            GroupedSection("Network", footer: SystemDetailFormatting.freshness(updatedAt: reading.updatedAt, failed: reading.lastReadFailed,
                                                                               now: context.date, maximumAge: SystemDetailSections.networkMaximumAge)) {
                rateRow("Download", symbol: "arrow.down", rate: reading.aggregateDownloadRate, history: reading.downloadHistory,
                        hasCompletedSample: reading.hasCompletedRateSample)
                rateRow("Upload", symbol: "arrow.up", rate: reading.aggregateUploadRate, history: reading.uploadHistory,
                        hasCompletedSample: reading.hasCompletedRateSample)
            }
        }
        .onAppear {
            guard !isFixture else { return }
            monitor.subscribe(subscriptionID, popout: true)
        }
        .onDisappear { monitor.unsubscribe(subscriptionID) }
    }

    private func rateRow(_ title: String, symbol: String, rate: Double?, history: [Double], hasCompletedSample: Bool) -> some View {
        let value = SystemDetailFormatting.rateValue(rate, hasCompletedSample: hasCompletedSample)
        let lineColor: Color = accessibility.contrast == .increased ? .primary : .secondary
        return GroupedRow(title, symbol: symbol, accessory: {
            HStack(spacing: 10) {
                NetworkRateSparkline(values: history, color: lineColor)
                    .frame(width: 56, height: 16)
                    .accessibilityHidden(true)
                Text(value).font(DockDesign.Grouped.titleFont.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

// MARK: - Storage

/// Available space and a single usage bar from the Disk Space reader, sampled while shown.
struct SystemDetailStorageSection: View {
    @State private var snapshot: DiskSpaceSnapshot?
    @State private var sampledAt: Date?
    @State private var refreshFailed = false
    #if DEBUG
    @Environment(\.systemActivityFixture) private var fixture
    #endif

    init() {}

    private var isFixture: Bool {
        #if DEBUG
        return fixture != nil
        #else
        return false
        #endif
    }
    private var shownSnapshot: DiskSpaceSnapshot? {
        #if DEBUG
        if let fixture {
            return fixture.startupVolume.map {
                DiskSpaceSnapshot(name: $0.name, totalBytes: Int64(clamping: $0.totalBytes), availableBytes: Int64(clamping: $0.availableBytes))
            }
        }
        #endif
        return snapshot
    }
    private var shownSampledAt: Date? {
        #if DEBUG
        if let fixture { return fixture.storageSampledAt }
        #endif
        return sampledAt
    }

    var body: some View {
        // The footer's relative time stays current between samples (only while the popout is open).
        TimelineView(.periodic(from: .now, by: 30)) { context in
            GroupedSection("Storage", footer: SystemDetailFormatting.freshness(updatedAt: shownSampledAt, failed: refreshFailed,
                                                                               now: context.date,
                                                                               maximumAge: SystemDetailSections.storageMaximumAge)) {
                if let shown = shownSnapshot {
                    GroupedRow(shown.name, symbol: "internaldrive", value: SystemDetailFormatting.storageAvailable(shown))
                    WidgetPopoutRow {
                        HStack(spacing: 10) {
                            DiskUsageLine(fraction: shown.usedFraction,
                                          color: shown.isLow ? WidgetPalette.warning : WidgetPalette.resolved(kind: "System Activity", accent: .auto))
                            Text(SystemDetailFormatting.storageUsed(shown))
                                .font(DockDesign.Grouped.subtitleFont.monospacedDigit()).foregroundStyle(.secondary)
                                .lineLimit(1).fixedSize()
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(shown.isLow ? "Used, low space" : "Used")
                    .accessibilityValue(SystemDetailFormatting.storageUsed(shown))
                } else {
                    GroupedRow("Startup disk", symbol: "internaldrive", value: refreshFailed ? "Unavailable" : "—")
                }
            }
        }
        .task {
            guard !isFixture else { return }
            await refresh()
            for await _ in RefreshScheduler.shared.ticks(every: SystemDetailSections.storageInterval) {
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }

    private func refresh() async {
        let reading = await Task.detached(priority: .utility) { DiskSpaceSnapshot.read() }.value
        guard !Task.isCancelled else { return }
        if let reading { snapshot = reading; sampledAt = .now; refreshFailed = false }
        else { refreshFailed = true }
    }
}

// MARK: - Link from the independent families

/// Opens another widget's popout in the Dock's popover (as a tab). Only the Dock popover sets it.
struct WidgetPopoutOpener {
    var open: @MainActor (UUID) -> Void
}

private struct WidgetPopoutOpenerKey: EnvironmentKey {
    static var defaultValue: WidgetPopoutOpener? { nil }
}

extension EnvironmentValues {
    var widgetPopoutOpener: WidgetPopoutOpener? {
        get { self[WidgetPopoutOpenerKey.self] }
        set { self[WidgetPopoutOpenerKey.self] = newValue }
    }
}

/// One row in the Network Activity and Disk Space popouts, shown only when this Dock also has a
/// System Activity widget (and only in the Dock popover, which can open it). Otherwise nothing.
struct SystemActivityLinkRow: View {
    @ObservedObject var store: ProfileStore
    var profileID: UUID
    @Environment(\.widgetPopoutOpener) private var opener
    @Environment(\.widgetPopoutShowsHero) private var showsHero

    init(store: ProfileStore, profileID: UUID) {
        self.store = store
        self.profileID = profileID
    }

    private var targetID: UUID? {
        SystemDetailSections.systemActivityItemID(in: store.state.profiles.first { $0.id == profileID }?.items ?? [])
    }

    var body: some View {
        if showsHero, let opener, let targetID {
            GroupedSection {
                GroupedRow("Show in System Activity", symbol: "cpu", chevron: true, action: { opener.open(targetID) })
            }
        }
    }
}
