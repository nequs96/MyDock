import AppKit
import SwiftUI

struct SystemActivityWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(SystemActivityCompactWidgetView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(SystemActivityPopoutWidgetView())
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
    @Published private(set) var lastUpdated: Date?

    private var subscribers = Set<UUID>()
    private var visiblePopouts = Set<UUID>()
    private var schedulerDemand: RefreshDemandToken?
    private var previousTicks: HostCPUTicks?
    private var previousPerCoreTicks: [HostCPUTicks]?
    private var samplingTask: Task<Void, Never>?
    private var dockIsVisible = false
    private var pressureSource: (any DispatchSourceMemoryPressure)?

    private init() {
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

    func refreshNow() {
        Task { await sample() }
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
        lastUpdated = .now
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
}

@MainActor
final class StorageScanMonitor: ObservableObject {
    static let shared = StorageScanMonitor()

    @Published private(set) var results: [StorageScanResult] = []
    @Published private(set) var progress: StorageScanProgress?
    @Published private(set) var currentPath: String?
    @Published private(set) var warnings: [String] = []
    @Published private(set) var isScanning = false

    private var cancellation: StorageScanCancellationFlag?
    private var scanTask: Task<Void, Never>?
    private var scanID = UUID()
    private var previousRoots: [URL] = []

    func scanDefaultLocations() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        start([home, URL(fileURLWithPath: "/Applications", isDirectory: true),
               home.appendingPathComponent("Library", isDirectory: true)])
    }

    func scanFolder(_ url: URL) { start([url]) }
    func scanAgain() { start(previousRoots) }
    func cancel() { cancellation?.cancel() }

    private func start(_ roots: [URL]) {
        guard !isScanning, !roots.isEmpty else { return }
        previousRoots = roots
        results = []
        warnings = []
        progress = nil
        isScanning = true
        let flag = StorageScanCancellationFlag()
        cancellation = flag
        let identifier = UUID()
        scanID = identifier

        scanTask = Task { [weak self] in
            guard let self else { return }
            for root in roots {
                guard !flag.isCancelled else { break }
                self.currentPath = root.path
                self.progress = StorageScanProgress(visitedEntries: 0, scannedFileCount: 0, scannedBytes: 0)
                let work = Task.detached(priority: .userInitiated) { [self] in
                    try StorageScanner.scan(at: root, cancellation: flag) { update in
                        Task { @MainActor [self] in
                            guard self.scanID == identifier, self.isScanning else { return }
                            self.progress = update
                        }
                    }
                }
                do {
                    let result = try await work.value
                    self.results.append(result)
                } catch StorageScanner.ScanError.cancelled {
                    break
                } catch {
                    self.warnings.append("\(root.path): \(error.localizedDescription)")
                }
            }
            guard self.scanID == identifier else { return }
            self.currentPath = nil
            self.progress = nil
            self.cancellation = nil
            self.isScanning = false
            self.scanTask = nil
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
    @Environment(\.facesBSystemReadings) private var fixture
    #endif
    private var cpuPercentage: Double? {
        #if DEBUG
        if let fixture { return fixture.cpuPercentage }
        #endif
        return monitor.cpuPercentage
    }
    private var cpuHistory: [Double] {
        #if DEBUG
        if let fixture { return fixture.cpuHistory }
        #endif
        return monitor.cpuHistory
    }
    private var memory: HostMemoryReading? {
        #if DEBUG
        if let fixture { return fixture.memory }
        #endif
        return monitor.memory
    }
    private var loadAverage: SystemLoadAverage? {
        #if DEBUG
        if let fixture { return fixture.loadAverage }
        #endif
        return monitor.loadAverage
    }
    var body: some View {
        SystemTelemetryDockFace(cpu: cpuPercentage, history: cpuHistory, memory: memory, load: loadAverage,
                                secondary: item.widgetConfiguration?.systemSecondaryMetric ?? .memory)
            .frame(width: contentWidth, height: 54)
            .onAppear {
                #if DEBUG
                if fixture != nil { return }
                #endif
                monitor.subscribe(subscriptionID)
            }
            .onDisappear { monitor.unsubscribe(subscriptionID) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("CPU system activity")
            .accessibilityValue(cpuPercentage.map { "\(Int($0.rounded())) percent" } ?? "Sampling")
    }
}

private struct SystemActivityPopoutWidgetView: View {
    @StateObject private var monitor = SystemActivityMonitor.shared
    @StateObject private var scanner = StorageScanMonitor.shared
    @State private var subscriptionID = UUID()

    #if DEBUG
    @Environment(\.facesBSystemReadings) private var fixture
    #endif
    private var cpuPercentage: Double? {
        #if DEBUG
        if let fixture { return fixture.cpuPercentage }
        #endif
        return monitor.cpuPercentage
    }
    private var perCorePercentages: [Double]? {
        #if DEBUG
        if let fixture { return fixture.perCorePercentages }
        #endif
        return monitor.perCorePercentages
    }
    private var memory: HostMemoryReading? {
        #if DEBUG
        if let fixture { return fixture.memory }
        #endif
        return monitor.memory
    }
    private var loadAverage: SystemLoadAverage? {
        #if DEBUG
        if let fixture { return fixture.loadAverage }
        #endif
        return monitor.loadAverage
    }
    private var thermalState: SystemThermalState {
        #if DEBUG
        if let fixture { return fixture.thermalState }
        #endif
        return monitor.thermalState
    }
    private var systemUptime: TimeInterval? {
        #if DEBUG
        if let fixture { return fixture.systemUptime }
        #endif
        return monitor.systemUptime
    }
    private var startupVolume: SystemVolumeReading? {
        #if DEBUG
        if let fixture { return fixture.startupVolume }
        #endif
        return monitor.startupVolume
    }
    private var memoryPressure: MemoryPressureCondition {
        #if DEBUG
        if let fixture { return fixture.memoryPressure }
        #endif
        return monitor.memoryPressure
    }
    private var lastUpdated: Date? {
        #if DEBUG
        if let fixture { return fixture.lastUpdated }
        #endif
        return monitor.lastUpdated
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Live system readings").font(DockDesign.Module.label).foregroundStyle(.secondary)
                Spacer()
                Button { monitor.refreshNow() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(DockButtonStyle(icon: true)).accessibilityLabel("Refresh system readings")
            }
            HStack(spacing: 10) {
                metricCard(title: "CPU", value: cpuPercentage.map { "\(Int($0.rounded()))%" } ?? "Warming up", symbol: "cpu")
                metricCard(title: "Memory", value: memorySummary, symbol: "memorychip")
            }
            if let perCorePercentages = perCorePercentages {
                FacesBDataSection(title: "Logical processors") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(Array(perCorePercentages.enumerated()), id: \.offset) { index, percentage in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 2) {
                                    Text("\(index + 1)").foregroundStyle(.secondary)
                                    Spacer(minLength: 2)
                                    Text("\(Int(percentage.rounded()))%").monospacedDigit()
                                }.font(.system(size: 10, weight: .medium))
                                ProgressView(value: percentage, total: 100).tint(.secondary).controlSize(.mini)
                            }.accessibilityElement(children: .ignore)
                                .accessibilityLabel("Core \(index + 1), \(Int(percentage.rounded())) percent")
                        }
                    }
                }
            }
            GroupedSection("System health", footer: "CPU is busy time across all logical processors (0–100%). Load is the average number of runnable tasks over 1, 5 and 15 minutes, not a percentage. Memory and swap are byte counts.") {
                healthRow("Thermal state", value: thermalState.title, symbol: "thermometer.medium")
                healthRow("Uptime", value: uptimeSummary, symbol: "clock")
                healthRow("Load · 1 / 5 / 15 min", value: loadAverageSummary, symbol: "chart.bar.xaxis")
                healthRow("Swap used", value: swapSummary, symbol: "externaldrive")
            }
            if let memory = memory {
                FacesBDataSection(title: "Memory breakdown") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 12) {
                        memoryDetail("Active", memory.activeBytes)
                        memoryDetail("Wired", memory.wiredBytes)
                        memoryDetail("Compressed", memory.compressedBytes)
                        memoryDetail("Inactive", memory.inactiveBytes)
                        memoryDetail("Free", memory.freeBytes)
                        memoryDetail("Purgeable", memory.purgeableBytes)
                    }
                    Text("Pressure: \(memoryPressure.title). Categories overlap; pressure updates when macOS reports a change.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let volume = startupVolume {
                FacesBDataSection(title: volume.name) {
                    HStack(alignment: .firstTextBaseline) {
                        ModuleValue(value: volume.availableBytes.formattedByteCount)
                        Text("available").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    ProgressView(value: Double(volume.totalBytes - min(volume.availableBytes, volume.totalBytes)), total: Double(max(1, volume.totalBytes))).tint(.secondary)
                    Text("\(volume.totalBytes.formattedByteCount) total capacity").font(.caption).foregroundStyle(.secondary)
                }
            }
            FacesBDataSection(title: "Explore storage") {
                Text("Find large files in Home, Applications and Library, or choose a folder. Nothing is deleted or uploaded.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                GroupedSection {
                    if scanner.isScanning {
                        GroupedRow("Scanning…") { ProgressView().controlSize(.small) }
                        GroupedRow("Cancel", role: .button) { scanner.cancel() }
                    } else {
                        GroupedRow("Scan Folders", role: .button) { scanner.scanDefaultLocations() }
                        GroupedRow("Choose Folder…", role: .button, action: chooseFolder)
                        if !scanner.results.isEmpty { GroupedRow("Again", role: .button) { scanner.scanAgain() } }
                    }
                }
                if scanner.isScanning {
                    Text(scanner.currentPath ?? "Preparing scan…").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    if let progress = scanner.progress {
                        Text("\(progress.scannedFileCount) files · \(progress.scannedBytes.formattedByteCount)").font(.caption).monospacedDigit()
                    }
                }
                ForEach(scanner.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                if !scanner.results.isEmpty {
                    Text("Locations are counted separately. Home includes Library.").font(.caption).foregroundStyle(.secondary)
                    ForEach(scanner.results, id: \.rootPath) { result in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(result.rootPath).font(.caption.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                            Text(storageSummary(result)).font(.caption).foregroundStyle(.secondary)
                            ForEach(result.largestFiles) { file in
                                Button { reveal(file) } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "doc").foregroundStyle(.secondary)
                                        Text(file.name).lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: 4)
                                        Text(file.byteSize.formattedByteCount).monospacedDigit().foregroundStyle(.secondary)
                                        Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                                    }.font(.caption).padding(.vertical, 4)
                                }.buttonStyle(.plain).help("Reveal in Finder")
                            }
                        }
                    }
                }
            }
            if let lastUpdated = lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened)) · every 4 seconds while visible")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            #if DEBUG
            if fixture != nil { return }
            #endif
            monitor.subscribe(subscriptionID, popout: true)
        }
        .onDisappear { monitor.unsubscribe(subscriptionID) }
    }

    private func healthRow(_ title: String, value: String, symbol: String) -> some View {
        GroupedRow(title, symbol: symbol, value: value)
    }

    private var memorySummary: String {
        guard let memory = memory else { return "Unavailable" }
        return "\(memory.usedBytes.formattedByteCount) / \(memory.totalBytes.formattedByteCount)"
    }

    private var swapSummary: String {
        guard let swap = memory?.swapUsedBytes else { return "Unavailable" }
        return swap.formattedByteCount
    }

    private var loadAverageSummary: String {
        guard let load = loadAverage else { return "Unavailable" }
        return String(format: "%.2f · %.2f · %.2f", load.oneMinute, load.fiveMinutes, load.fifteenMinutes)
    }

    private var uptimeSummary: String {
        guard let uptime = systemUptime else { return "Unavailable" }
        let seconds = max(0, Int(uptime))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h \(minutes)m"
    }

    private func memoryDetail(_ title: String, _ bytes: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(bytes.formattedByteCount).font(.caption.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricCard(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            ModuleValue(value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to scan"
        panel.prompt = "Scan"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scanner.scanFolder(url)
    }

    private func reveal(_ file: StorageScanEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
    }

    private func storageSummary(_ result: StorageScanResult) -> String {
        let base = "\(result.scannedFileCount) files · \(result.scannedBytes.formattedByteCount)"
        guard result.skippedEntries > 0 || result.wasCapped else { return base }
        let skipped = result.skippedEntries > 0 ? " · \(result.skippedEntries) skipped" : ""
        let capped = result.wasCapped ? " · scan limit reached" : ""
        return "Partial · \(base)\(skipped)\(capped)"
    }
}

private extension UInt64 {
    var formattedByteCount: String { ByteCountFormatter.string(fromByteCount: Int64(clamping: self), countStyle: .file) }
}

#if DEBUG
struct FacesBSystemReadings {
    var cpuPercentage: Double? = nil
    var cpuHistory: [Double] = []
    var perCorePercentages: [Double]? = nil
    var memory: HostMemoryReading? = nil
    var loadAverage: SystemLoadAverage? = nil
    var thermalState: SystemThermalState = .unknown
    var systemUptime: TimeInterval? = nil
    var startupVolume: SystemVolumeReading? = nil
    var memoryPressure: MemoryPressureCondition = .awaitingEvent
    var lastUpdated: Date? = nil
}
private struct FacesBSystemReadingsKey: EnvironmentKey { static let defaultValue: FacesBSystemReadings? = nil }
extension EnvironmentValues {
    var facesBSystemReadings: FacesBSystemReadings? {
        get { self[FacesBSystemReadingsKey.self] }
        set { self[FacesBSystemReadingsKey.self] = newValue }
    }
}
#endif

/// Calm data section shared by the RD-10 content views; the popout shell supplies its surface.
struct FacesBDataSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(DockDesign.Module.labelLarge).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
