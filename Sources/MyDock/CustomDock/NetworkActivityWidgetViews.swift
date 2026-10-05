import Darwin
import SwiftUI

struct NetworkActivityWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(NetworkActivityCompactWidgetView())
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(NetworkActivityPopoutWidgetView())
    }
}

@MainActor
final class NetworkActivityMonitor: ObservableObject {
    static let shared = NetworkActivityMonitor()

    @Published private(set) var interfaces: [NetworkInterfaceRate] = []
    @Published private(set) var updatedAt: Date?
    @Published private(set) var downloadHistory: [Double] = []
    @Published private(set) var uploadHistory: [Double] = []
    @Published private(set) var hasCompletedRateSample = false

    private var subscribers = Set<UUID>()
    private var visiblePopouts = Set<UUID>()
    private var schedulerDemand: RefreshDemandToken?
    private var previousReading: NetworkCountersReading?
    private var samplingTask: Task<Void, Never>?
    private var dockIsVisible = false

    var aggregateDownloadRate: Double? { completeAggregate(\.receivedBytesPerSecond) }
    var aggregateUploadRate: Double? { completeAggregate(\.sentBytesPerSecond) }

    func subscribe(_ identifier: UUID, popout: Bool = false) {
        subscribers.insert(identifier)
        if popout { visiblePopouts.insert(identifier) }
        updateSamplingState()
    }

    func unsubscribe(_ identifier: UUID) {
        subscribers.remove(identifier)
        visiblePopouts.remove(identifier)
        updateSamplingState()
    }

    func setDockVisible(_ visible: Bool) {
        dockIsVisible = visible
        updateSamplingState()
    }

    func refreshNow() { Task { await sample() } }

    private func updateSamplingState() {
        RefreshScheduler.shared.setDemand(&schedulerDemand, kind: .popout, active: !visiblePopouts.isEmpty)
        let shouldSample = SystemActivitySamplingPolicy.shouldSample(dockIsVisible: dockIsVisible || !visiblePopouts.isEmpty,
                                                                      subscriberCount: subscribers.count)
        guard shouldSample != (samplingTask != nil) else { return }
        if !shouldSample {
            samplingTask?.cancel()
            samplingTask = nil
            previousReading = nil
            interfaces = []
            downloadHistory = []
            uploadHistory = []
            hasCompletedRateSample = false
            return
        }
        samplingTask = Task { [weak self] in
            await self?.sample()
            for await _ in RefreshScheduler.shared.ticks(every: 4) {
                guard !Task.isCancelled else { return }
                await self?.sample()
            }
        }
    }

    private func sample() async {
        let reading = await Task.detached(priority: .utility) { NetworkInterfaceReader.read() }.value
        guard let reading else { return }
        if let previousReading {
            interfaces = NetworkRateCalculator.rates(previous: previousReading, current: reading)
            hasCompletedRateSample = true
            let download = interfaces.compactMap(\.receivedBytesPerSecond).reduce(0, +)
            let upload = interfaces.compactMap(\.sentBytesPerSecond).reduce(0, +)
            downloadHistory = Array((downloadHistory + [download]).suffix(30))
            uploadHistory = Array((uploadHistory + [upload]).suffix(30))
        } else {
            hasCompletedRateSample = false
            interfaces = reading.interfaces.map {
                NetworkInterfaceRate(name: $0.name,
                                     receivedBytesPerSecond: nil,
                                     sentBytesPerSecond: nil,
                                     addresses: $0.addresses)
            }
        }
        previousReading = reading
        updatedAt = .now
    }

    private func completeAggregate(_ keyPath: KeyPath<NetworkInterfaceRate, Double?>) -> Double? {
        guard !interfaces.isEmpty else { return nil }
        let values = interfaces.compactMap { $0[keyPath: keyPath] }
        guard values.count == interfaces.count else { return nil }
        return values.reduce(0, +)
    }
}

private struct NetworkActivityCompactWidgetView: View {
    @Environment(\.dockWidgetContentWidth) private var contentWidth
    @StateObject private var monitor = NetworkActivityMonitor.shared
    @State private var subscriptionID = UUID()

    #if DEBUG
    @Environment(\.facesBNetworkReadings) private var fixture
    #endif
    private var aggregateDownloadRate: Double? {
        #if DEBUG
        if let fixture { return fixture.aggregateDownloadRate }
        #endif
        return monitor.aggregateDownloadRate
    }
    private var aggregateUploadRate: Double? {
        #if DEBUG
        if let fixture { return fixture.aggregateUploadRate }
        #endif
        return monitor.aggregateUploadRate
    }
    private var downloadHistory: [Double] {
        #if DEBUG
        if let fixture { return fixture.downloadHistory }
        #endif
        return monitor.downloadHistory
    }
    var body: some View {
        NetworkDockFace(download: aggregateDownloadRate, upload: aggregateUploadRate, history: downloadHistory)
            .frame(width: contentWidth, height: 54)
            .onAppear {
                #if DEBUG
                if fixture != nil { return }
                #endif
                monitor.subscribe(subscriptionID)
            }
            .onDisappear { monitor.unsubscribe(subscriptionID) }
            .accessibilityElement(children: .ignore).accessibilityLabel("Network Activity")
            .accessibilityValue("Download \(rateText(aggregateDownloadRate)), upload \(rateText(aggregateUploadRate))")
    }
}

private struct NetworkActivityPopoutWidgetView: View {
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    @State private var showsSettings = false
    @State private var showsOtherInterfaces = false
    @StateObject private var monitor = NetworkActivityMonitor.shared
    @State private var subscriptionID = UUID()

    #if DEBUG
    @Environment(\.facesBNetworkReadings) private var fixture
    #endif
    private var interfaces: [NetworkInterfaceRate] {
        #if DEBUG
        if let fixture { return fixture.interfaces }
        #endif
        return monitor.interfaces
    }
    private var downloadHistory: [Double] {
        #if DEBUG
        if let fixture { return fixture.downloadHistory }
        #endif
        return monitor.downloadHistory
    }
    private var uploadHistory: [Double] {
        #if DEBUG
        if let fixture { return fixture.uploadHistory }
        #endif
        return monitor.uploadHistory
    }
    private var hasCompletedRateSample: Bool {
        #if DEBUG
        if let fixture { return fixture.hasCompletedRateSample }
        #endif
        return monitor.hasCompletedRateSample
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHero {
                HStack {
                    Text("Live samples every 4 seconds").font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { monitor.refreshNow() }.buttonStyle(.borderless).controlSize(.small)
                        .accessibilityLabel("Refresh network readings")
                }
                HStack(spacing: 10) {
                    rateCard(title: "Download", value: aggregate(\.receivedBytesPerSecond), history: downloadHistory, color: .secondary, symbol: "arrow.down")
                    rateCard(title: "Upload", value: aggregate(\.sentBytesPerSecond), history: uploadHistory, color: .secondary, symbol: "arrow.up")
                }
                GroupedSection("Interfaces") {
                    let active = NetworkInterfacePresentation.active(interfaces)
                    if active.isEmpty { GroupedRow("No active network interfaces", symbol: "network.slash") }
                    ForEach(active) { interface in interfaceRow(interface) }
                    let other = NetworkInterfacePresentation.other(interfaces)
                    if !other.isEmpty {
                        DisclosureGroup("Other interfaces (\(other.count))", isExpanded: $showsOtherInterfaces) {
                            ForEach(other) { interface in interfaceRow(interface) }
                        }.padding(DockDesign.Grouped.rowHorizontalPadding)
                    }
                }
            }
            WidgetPopoutSettingsDisclosure(isExpanded: $showsSettings) {
                GroupedSection(footer: "Local traffic samples while the Dock or popout is visible.") {
                    GroupedRow("Sampling interval", value: "4 seconds")
                    GroupedRow("Interface scope", value: "Active interfaces")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            guard showsHero else { return }
            #if DEBUG
            if fixture != nil { return }
            #endif
            monitor.subscribe(subscriptionID, popout: true)
        }
        .onDisappear { monitor.unsubscribe(subscriptionID) }
    }

    private func rateCard(title: String, value: String, history: [Double], color: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
            ModuleValue(value: value, size: .medium)
            NetworkRateSparkline(values: history, color: color).frame(height: 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func interfaceRow(_ interface: NetworkInterfaceRate) -> some View {
        GroupedRow(interface.name, subtitle: NetworkInterfacePresentation.addresses(interface.addresses).isEmpty ? nil : NetworkInterfacePresentation.addresses(interface.addresses).joined(separator: " · "),
            symbol: "cable.connector") {
            Text("↓ \(rateText(interface.receivedBytesPerSecond))   ↑ \(rateText(interface.sentBytesPerSecond))")
                .font(DockDesign.Grouped.subtitleFont.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func aggregate(_ keyPath: KeyPath<NetworkInterfaceRate, Double?>) -> String {
        guard !interfaces.isEmpty else { return "No interfaces" }
        let values = interfaces.compactMap { $0[keyPath: keyPath] }
        guard values.count == interfaces.count else { return hasCompletedRateSample ? "Unavailable" : "Warming up" }
        return rateText(values.reduce(0, +))
    }
}

private struct NetworkRateSparkline: View {
    var values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard values.count > 1, geometry.size.width > 0, geometry.size.height > 0 else { return }
                let maximum = max(values.max() ?? 1, 1)
                for (index, value) in values.enumerated() {
                    let x = geometry.size.width * CGFloat(index) / CGFloat(values.count - 1)
                    let y = geometry.size.height * (1 - CGFloat(value / maximum))
                    let point = CGPoint(x: x, y: y)
                    if index == 0 { path.move(to: point) }
                    else { path.addLine(to: point) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

private func rateText(_ bytesPerSecond: Double?) -> String {
    guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "—" }
    let bytes = Int64(min(bytesPerSecond, Double(Int64.max)))
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + "/s"
}

#if DEBUG
struct FacesBNetworkReadings {
    var interfaces: [NetworkInterfaceRate] = []
    var updatedAt: Date? = nil
    var downloadHistory: [Double] = []
    var uploadHistory: [Double] = []
    var hasCompletedRateSample = false
    var aggregateDownloadRate: Double? = nil
    var aggregateUploadRate: Double? = nil
}
private struct FacesBNetworkReadingsKey: EnvironmentKey { static let defaultValue: FacesBNetworkReadings? = nil }
extension EnvironmentValues {
    var facesBNetworkReadings: FacesBNetworkReadings? {
        get { self[FacesBNetworkReadingsKey.self] }
        set { self[FacesBNetworkReadingsKey.self] = newValue }
    }
}
#endif

/// NetworkInterfaceReader already excludes down and loopback interfaces. This pure presentation
/// filter keeps only routable addresses or observed traffic in the primary list.
enum NetworkInterfacePresentation {
    static func isRoutable(_ address: String) -> Bool {
        let host = String(address.split(separator: "%", maxSplits: 1).first ?? "")
        var v4 = in_addr()
        if inet_pton(AF_INET, host, &v4) == 1 {
            let bytes = withUnsafeBytes(of: &v4) { Array($0) }
            return bytes[0] != 0 && bytes[0] != 127 && bytes[0] < 224 && !(bytes[0] == 169 && bytes[1] == 254)
        }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, host, &v6) == 1 else { return false }
        let bytes = withUnsafeBytes(of: &v6) { Array($0) }
        if bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80 { return false } // fe80::/10
        if bytes[0] == 0xff { return false }
        if bytes.prefix(15).allSatisfy({ $0 == 0 }) && bytes[15] <= 1 { return false }
        if bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 0xff && bytes[11] == 0xff {
            return isRoutable(bytes.suffix(4).map(String.init).joined(separator: "."))
        }
        return true
    }
    static func addresses(_ values: [String]) -> [String] { values.filter(isRoutable) }
    static func isActive(_ interface: NetworkInterfaceRate) -> Bool {
        !addresses(interface.addresses).isEmpty || [interface.receivedBytesPerSecond, interface.sentBytesPerSecond]
            .contains { value in value.map { $0.isFinite && $0 > 0 } ?? false }
    }
    static func active(_ interfaces: [NetworkInterfaceRate]) -> [NetworkInterfaceRate] { interfaces.filter(isActive) }
    static func other(_ interfaces: [NetworkInterfaceRate]) -> [NetworkInterfaceRate] { interfaces.filter { !isActive($0) } }
}
