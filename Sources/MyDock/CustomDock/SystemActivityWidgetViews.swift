import AppKit
import SwiftUI

struct SystemActivityWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(SystemActivityCompactWidgetView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(SystemActivityPopoutWidgetView(store: store, item: item, profileID: profileID))
    }
}

@MainActor
final class SystemActivityMonitor: ObservableObject {
    static let shared = SystemActivityMonitor()

    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var cpuPercentage: Double?
    @Published private(set) var perCorePercentages: [Double]?
    @Published private(set) var memory: HostMemoryReading?
    @Published private(set) var loadAverage: SystemLoadAverage?
    @Published private(set) var thermalState: SystemThermalState = .unknown
    @Published private(set) var systemUptime: TimeInterval?
    @Published private(set) var startupVolume: SystemVolumeReading?
    @Published private(set) var memoryPressure: MemoryPressureCondition = .awaitingEvent

    private var subscribers = Set<UUID>()
    private var visiblePopouts = Set<UUID>()
    private var schedulerDemand: RefreshDemandToken?
    private var previousTicks: HostCPUTicks?
    private var previousPerCoreTicks: [HostCPUTicks]?
    private var samplingTask: Task<Void, Never>?
    private var dockIsVisible = false
    private var pressureSource: (any DispatchSourceMemoryPressure)?

    private init() {
        // The dispatch source reports only transitions: seed the current level so a calm Mac reads "Normal".
        memoryPressure = MemoryPressureCondition.currentLevel() ?? .awaitingEvent
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .main)
        pressureSource = source
        source.setEventHandler { [weak self] in
            guard let self, let event = self.pressureSource?.data else { return }
            if event.contains(.critical) {
                self.memoryPressure = .critical
            } else if event.contains(.warning) {
                self.memoryPressure = .warning
            } else if event.contains(.normal) {
                self.memoryPressure = .normal
            }
        }
        source.activate()
    }

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

    private func updateSamplingState() {
        RefreshScheduler.shared.setDemand(&schedulerDemand, kind: .popout, active: !visiblePopouts.isEmpty)
        let shouldSample = SystemActivitySamplingPolicy.shouldSample(dockIsVisible: dockIsVisible || !visiblePopouts.isEmpty,
                                                                      subscriberCount: subscribers.count)
        guard shouldSample != (samplingTask != nil) else { return }
        if !shouldSample {
            samplingTask?.cancel()
            samplingTask = nil
            previousTicks = nil
            previousPerCoreTicks = nil
            cpuHistory = []
            cpuPercentage = nil
            perCorePercentages = nil
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
        guard SystemActivitySamplingPolicy.shouldSample(dockIsVisible: dockIsVisible || !visiblePopouts.isEmpty,
                                                         subscriberCount: subscribers.count) else { return }
        let reading = await Task.detached(priority: .utility) { SystemActivityReader.read() }.value
        guard let reading,
              SystemActivitySamplingPolicy.shouldSample(dockIsVisible: dockIsVisible || !visiblePopouts.isEmpty,
                                                        subscriberCount: subscribers.count) else { return }
        cpuPercentage = previousTicks.flatMap { CPUUsageCalculator.percentage(from: $0, to: reading.cpuTicks) }
        cpuHistory = WidgetTelemetryHistory.appending(cpuPercentage, to: cpuHistory)
        previousTicks = reading.cpuTicks
        perCorePercentages = reading.perCoreCPUTicks.flatMap { current in
            previousPerCoreTicks.flatMap { PerCoreCPUUsageCalculator.percentages(previous: $0, current: current) }
        }
        previousPerCoreTicks = reading.perCoreCPUTicks
        memory = reading.memory
        loadAverage = reading.loadAverage
        thermalState = reading.thermalState
        systemUptime = reading.systemUptime
        startupVolume = reading.startupVolume
    }
}

enum MemoryPressureCondition {
    case awaitingEvent
    case normal
    case warning
    case critical

    var title: String {
        switch self {
        case .awaitingEvent: "Awaiting event"
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    /// The kernel's current memory pressure level, or nil when it cannot be read.
    static func currentLevel() -> MemoryPressureCondition? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return nil }
        return condition(sysctlLevel: Int(level))
    }

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    static func condition(sysctlLevel: Int) -> MemoryPressureCondition? {
        switch sysctlLevel {
        case 1: return MemoryPressureCondition.normal
        case 2: return MemoryPressureCondition.warning
        case 4: return MemoryPressureCondition.critical
        default: return nil
        }
    }
}

enum SystemActivitySamplingPolicy {
    static func shouldSample(dockIsVisible: Bool, subscriberCount: Int) -> Bool {
        dockIsVisible && subscriberCount > 0
    }
}

private struct SystemActivityCompactWidgetView: View {
    var item: DockItem
    @Environment(\.dockWidgetContentWidth) private var contentWidth
    @StateObject private var monitor = SystemActivityMonitor.shared
    @State private var subscriptionID = UUID()
    #if DEBUG
    @Environment(\.systemActivityFixture) private var fixture
    #endif
    /// Every field comes from one reading: the live monitor, or (DEBUG render QA) a fixture.
    private var readings: SystemActivityReadings {
        #if DEBUG
        if let fixture { return fixture }
        #endif
        return SystemActivityReadings(monitor)
    }
    private var isFixture: Bool {
        #if DEBUG
        return fixture != nil
        #else
        return false
        #endif
    }
    private var secondary: SystemSecondaryMetric { item.widgetConfiguration?.systemSecondaryMetric ?? .memory }

    var body: some View {
        let reading = readings
        SystemTelemetryDockFace(cpu: reading.cpuPercentage, history: reading.cpuHistory, memory: reading.memory, load: reading.loadAverage,
                                secondary: secondary)
            .frame(width: contentWidth, height: 54)
            .onAppear {
                guard !isFixture else { return }
                monitor.subscribe(subscriptionID)
            }
            .onDisappear { monitor.unsubscribe(subscriptionID) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("CPU system activity")
            .accessibilityValue(SystemActivityFormatting.accessibilityValue(cpu: reading.cpuPercentage, secondary: secondary,
                                                                            memory: reading.memory, load: reading.loadAverage))
    }
}

private struct SystemActivityPopoutWidgetView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    @State private var showsSettings = false
    private var configuration: WidgetConfiguration { store.presentationConfiguration(for: item, in: profileID) }
    @StateObject private var monitor = SystemActivityMonitor.shared
    @State private var subscriptionID = UUID()

    #if DEBUG
    @Environment(\.systemActivityFixture) private var fixture
    #endif
    /// Every field comes from one reading: the live monitor, or (DEBUG render QA) a fixture.
    private var readings: SystemActivityReadings {
        #if DEBUG
        if let fixture { return fixture }
        #endif
        return SystemActivityReadings(monitor)
    }
    private var isFixture: Bool {
        #if DEBUG
        return fixture != nil
        #else
        return false
        #endif
    }

    var body: some View {
        let reading = readings
        VStack(alignment: .leading, spacing: 14) {
            if showsHero {
                WidgetPopoutHero(
                    value: reading.cpuPercentage.map { "\(Int($0.rounded()))%" } ?? "Warming up",
                    caption: "CPU · Memory " + SystemActivityFormatting.memorySummary(reading.memory),
                    valueColor: SystemActivityState.color(cpu: reading.cpuPercentage))
                    .help("CPU is busy time across logical processors.")
                if let perCorePercentages = reading.perCorePercentages {
                    coresSection(perCorePercentages)
                }
                SystemHealthSection(thermalState: reading.thermalState, uptime: reading.systemUptime, load: reading.loadAverage,
                                    swapUsedBytes: reading.memory?.swapUsedBytes, memoryPressure: reading.memoryPressure)
                if let memory = reading.memory {
                    MemoryBreakdownSection(memory: memory)
                }
                // PX-7: related sections, below CPU and memory. Each reads only while it is shown.
                if SystemDetailSections.showsNetwork(configuration) {
                    SystemDetailNetworkSection()
                }
                if SystemDetailSections.showsStorage(configuration) {
                    // Storage replaces the startup-volume summary, so the popout shows one storage reading.
                    SystemDetailStorageSection()
                } else if let volume = reading.startupVolume {
                    startupVolumeSection(volume)
                }
                SystemStorageExplorerSection()
            }
            if showsHero {
                WidgetPopoutSettingsDisclosure(isExpanded: $showsSettings) {
                    GroupedSection(footer: "Local readings sample every 4 seconds while visible.") {
                        GroupedRow("Dock secondary metric") {
                            Picker(
                                "Dock secondary metric",
                                selection: Binding(
                                    get: { configuration.systemSecondaryMetric },
                                    set: { value in
                                        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.systemSecondaryMetric = value }
                                    })
                            ) { ForEach(SystemSecondaryMetric.allCases) { Text($0.title).tag($0) } }.labelsHidden()
                        }
                    }
                    relatedSectionToggles
                }
            } else {
                // The sheet's Appearance group already edits systemSecondaryMetric.
                Text("Local readings sample every 4 seconds while visible.")
                    .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                relatedSectionToggles
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            guard showsHero, !isFixture else { return }
            monitor.subscribe(subscriptionID, popout: true)
        }
        .onDisappear { monitor.unsubscribe(subscriptionID) }
    }

    private func coresSection(_ percentages: [Double]) -> some View {
        GroupedSection("Logical processors") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(Array(percentages.enumerated()), id: \.offset) { index, percentage in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 2) {
                            Text("\(index + 1)").foregroundStyle(.secondary)
                            Spacer(minLength: 2)
                            Text("\(Int(percentage.rounded()))%").monospacedDigit()
                        }.font(DockDesign.Grouped.subtitleFont.weight(.medium))
                        ProgressView(value: percentage, total: 100).tint(.secondary).controlSize(.mini)
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel("Core \(index + 1), \(Int(percentage.rounded())) percent")
                }
            }.padding(DockDesign.Grouped.rowHorizontalPadding)
        }
    }

    private func startupVolumeSection(_ volume: SystemVolumeReading) -> some View {
        GroupedSection(volume.name) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    ModuleValue(value: volume.availableBytes.formattedByteCount)
                    Text("available").font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                    Spacer()
                }
                ProgressView(value: Double(volume.totalBytes - min(volume.availableBytes, volume.totalBytes)), total: Double(max(1, volume.totalBytes))).tint(
                    .secondary)
                Text("\(volume.totalBytes.formattedByteCount) total capacity").font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
            }.padding(DockDesign.Grouped.rowHorizontalPadding)
        }
    }

    /// PX-7: which related sections the popout shows below CPU and memory.
    private var relatedSectionToggles: some View {
        GroupedSection("Sections", footer: "Read only while this popout is open.") {
            GroupedRow("Network", symbol: "network", isOn: Binding(
                get: { SystemDetailSections.showsNetwork(configuration) },
                set: { value in store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.systemShowsNetwork = value } }))
            GroupedRow("Storage", symbol: "internaldrive", isOn: Binding(
                get: { SystemDetailSections.showsStorage(configuration) },
                set: { value in store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.systemShowsStorage = value } }))
        }
    }
}

/// Thermal state, uptime, load, swap and memory pressure: value inputs, so it re-renders only when they change.
private struct SystemHealthSection: View {
    var thermalState: SystemThermalState
    var uptime: TimeInterval?
    var load: SystemLoadAverage?
    var swapUsedBytes: UInt64?
    var memoryPressure: MemoryPressureCondition

    var body: some View {
        GroupedSection("System health") {
            GroupedRow("Thermal state", symbol: "thermometer.medium", value: thermalState.title)
            GroupedRow("Uptime", symbol: "clock", value: uptime.map { SystemActivityFormatting.uptime($0) } ?? "Unavailable")
            GroupedRow("Load · 1 / 5 / 15 min", symbol: "chart.bar.xaxis", value: load.map { SystemActivityFormatting.load($0) } ?? "Unavailable")
            GroupedRow("Swap used", symbol: "externaldrive", value: swapUsedBytes?.formattedByteCount ?? "Unavailable")
            GroupedRow("Memory pressure", symbol: "memorychip", value: memoryPressure.title)
        }
        .help("Load is runnable tasks, not a percentage. Memory pressure changes when macOS reports it.")
    }
}

/// Active, wired, compressed, inactive, free and purgeable memory.
private struct MemoryBreakdownSection: View {
    var memory: HostMemoryReading

    var body: some View {
        GroupedSection("Memory breakdown") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 12) {
                detail("Active", memory.activeBytes)
                detail("Wired", memory.wiredBytes)
                detail("Compressed", memory.compressedBytes)
                detail("Inactive", memory.inactiveBytes)
                detail("Free", memory.freeBytes)
                detail("Purgeable", memory.purgeableBytes)
            }.padding(DockDesign.Grouped.rowHorizontalPadding)
        }
        .help("Memory categories overlap.")
    }

    private func detail(_ title: String, _ bytes: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
            Text(bytes.formattedByteCount).font(DockDesign.Grouped.subtitleFont.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The CPU state colour the Dock face and the popout hero share: amber from 75%, red from 90%.
enum SystemActivityState {
    static func color(cpu: Double?) -> Color {
        guard let cpu else { return .primary }
        return cpu >= 90 ? WidgetPalette.critical : cpu >= 75 ? WidgetPalette.warning : .primary
    }
}

enum SystemActivityFormatting {
    static func load(_ load: SystemLoadAverage, locale: Locale = .current) -> String {
        [load.oneMinute, load.fiveMinutes, load.fifteenMinutes]
            .map { $0.formatted(.number.precision(.fractionLength(2)).locale(locale)) }.joined(separator: " · ")
    }
    static func bytes(_ bytes: UInt64, locale: Locale = .current) -> String {
        Int64(clamping: bytes).formatted(.byteCount(style: .file).locale(locale))
    }
    /// "12 GB / 32 GB", or "Unavailable".
    static func memorySummary(_ memory: HostMemoryReading?, locale: Locale = .current) -> String {
        guard let memory else { return "Unavailable" }
        return "\(bytes(memory.usedBytes, locale: locale)) / \(bytes(memory.totalBytes, locale: locale))"
    }
    /// Uptime in the locale's abbreviated units, at most two of them: "1d 1h", "3h 12m".
    static func uptime(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        let clamped = seconds.isFinite ? max(0, seconds) : 0
        return formatter.string(from: clamped < 60 ? 60 : clamped) ?? "Unavailable"
    }
    /// The face's VoiceOver value: the CPU reading, then the secondary metric the face can show.
    static func accessibilityValue(cpu: Double?, secondary: SystemSecondaryMetric, memory: HostMemoryReading?, load: SystemLoadAverage?,
                                   locale: Locale = .current) -> String {
        let cpuText = cpu.map { "\(Int($0.rounded())) percent" } ?? "Sampling"
        let secondaryText: String? = switch secondary {
        case .memory: memory.map { "memory \(bytes($0.usedBytes, locale: locale)) used" }
        case .load: load.map { "load average \($0.oneMinute.formatted(.number.precision(.fractionLength(2)).locale(locale)))" }
        case .none: nil
        }
        return [cpuText, secondaryText].compactMap { $0 }.joined(separator: ", ")
    }
}

private extension UInt64 {
    var formattedByteCount: String { SystemActivityFormatting.bytes(self) }
}

/// One System Activity sample as the views read it.
struct SystemActivityReadings {
    var cpuPercentage: Double? = nil
    var cpuHistory: [Double] = []
    var perCorePercentages: [Double]? = nil
    var memory: HostMemoryReading? = nil
    var loadAverage: SystemLoadAverage? = nil
    var thermalState: SystemThermalState = .unknown
    var systemUptime: TimeInterval? = nil
    var startupVolume: SystemVolumeReading? = nil
    var memoryPressure: MemoryPressureCondition = .awaitingEvent
    /// When a render-QA fixture's Storage reading was taken; the live Storage section samples on its own.
    var storageSampledAt: Date? = nil
}

extension SystemActivityReadings {
    @MainActor init(_ monitor: SystemActivityMonitor) {
        self.init(cpuPercentage: monitor.cpuPercentage, cpuHistory: monitor.cpuHistory, perCorePercentages: monitor.perCorePercentages,
                  memory: monitor.memory, loadAverage: monitor.loadAverage, thermalState: monitor.thermalState,
                  systemUptime: monitor.systemUptime, startupVolume: monitor.startupVolume, memoryPressure: monitor.memoryPressure)
    }
}

#if DEBUG
private struct SystemActivityFixtureKey: EnvironmentKey { static let defaultValue: SystemActivityReadings? = nil }
extension EnvironmentValues {
    /// Render QA's fixed System Activity reading; the views read it in place of the live monitor.
    var systemActivityFixture: SystemActivityReadings? {
        get { self[SystemActivityFixtureKey.self] }
        set { self[SystemActivityFixtureKey.self] = newValue }
    }
}
#endif
