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
    var body: some View {
        SystemTelemetryDockFace(cpu: monitor.cpuPercentage, history: monitor.cpuHistory, memory: monitor.memory, load: monitor.loadAverage,
                                secondary: item.widgetConfiguration?.systemSecondaryMetric ?? .memory)
            .frame(width: contentWidth, height: 54)
            .onAppear { monitor.subscribe(subscriptionID) }
            .onDisappear { monitor.unsubscribe(subscriptionID) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("CPU system activity")
            .accessibilityValue(monitor.cpuPercentage.map { "\(Int($0.rounded())) percent" } ?? "Sampling")
    }
}

private struct SystemActivityPopoutWidgetView: View {
    @StateObject private var monitor = SystemActivityMonitor.shared
    @StateObject private var scanner = StorageScanMonitor.shared
    @State private var subscriptionID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Live system readings", systemImage: "circle.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.teal)
                Spacer()
                Button { monitor.refreshNow() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(DockButtonStyle(icon: true)).accessibilityLabel("Refresh system readings")
            }
            HStack(spacing: 10) {
                metricCard(title: "CPU", value: monitor.cpuPercentage.map { "\(Int($0.rounded()))%" } ?? "Warming up", symbol: "cpu")
                metricCard(title: "Memory", value: memorySummary, symbol: "memorychip")
            }
            if let perCorePercentages = monitor.perCorePercentages {
                WidgetSection(title: "Logical processors") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(Array(perCorePercentages.enumerated()), id: \.offset) { index, percentage in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 2) {
                                    Text("\(index + 1)").foregroundStyle(.secondary)
                                    Spacer(minLength: 2)
                                    Text("\(Int(percentage.rounded()))%").monospacedDigit()
                                }.font(.system(size: 10, weight: .medium))
                                ProgressView(value: percentage, total: 100).tint(.teal).controlSize(.mini)
                            }.accessibilityElement(children: .ignore)
                                .accessibilityLabel("Core \(index + 1), \(Int(percentage.rounded())) percent")
                        }
                    }
                }
            }
            WidgetSection(title: "System health") {
                healthRow("Thermal state", value: monitor.thermalState.title, symbol: "thermometer.medium")
                healthRow("Uptime", value: uptimeSummary, symbol: "clock")
                healthRow("Load · 1 / 5 / 15 min", value: loadAverageSummary, symbol: "chart.bar.xaxis")
                healthRow("Swap used", value: swapSummary, symbol: "externaldrive")
            }
            if let memory = monitor.memory {
                WidgetSection(title: "Memory breakdown") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 12) {
                        memoryDetail("Active", memory.activeBytes)
                        memoryDetail("Wired", memory.wiredBytes)
                        memoryDetail("Compressed", memory.compressedBytes)
                        memoryDetail("Inactive", memory.inactiveBytes)
                        memoryDetail("Free", memory.freeBytes)
                        memoryDetail("Purgeable", memory.purgeableBytes)
                    }
                    Text("Pressure: \(monitor.memoryPressure.title). Categories overlap; pressure updates when macOS reports a change.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let volume = monitor.startupVolume {
                WidgetSection(title: volume.name) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(volume.availableBytes.formattedByteCount).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                        Text("available").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    ProgressView(value: Double(volume.totalBytes - min(volume.availableBytes, volume.totalBytes)), total: Double(max(1, volume.totalBytes))).tint(.teal)
                    Text("\(volume.totalBytes.formattedByteCount) total capacity").font(.caption).foregroundStyle(.secondary)
                }
            }
            WidgetSection(title: "Explore storage") {
                Text("Find large files in Home, Applications and Library, or choose a folder. Nothing is deleted or uploaded.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if scanner.isScanning {
                        ProgressView().controlSize(.small)
                        Text("Scanning…").font(.caption)
                        Spacer()
                        Button("Cancel") { scanner.cancel() }
                    } else {
                        Button("Scan Folders") { scanner.scanDefaultLocations() }.buttonStyle(DockButtonStyle(primary: true))
                        Button("Choose Folder…", action: chooseFolder)
                        if !scanner.results.isEmpty { Button("Again") { scanner.scanAgain() } }
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
            if let lastUpdated = monitor.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened)) · every 4 seconds while visible")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 420, alignment: .leading)
        .onAppear { monitor.subscribe(subscriptionID, popout: true) }
        .onDisappear { monitor.unsubscribe(subscriptionID) }
    }

    private func healthRow(_ title: String, value: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }.font(.caption).accessibilityElement(children: .combine)
    }

    private var memorySummary: String {
        guard let memory = monitor.memory else { return "Unavailable" }
        return "\(memory.usedBytes.formattedByteCount) / \(memory.totalBytes.formattedByteCount)"
    }

    private var swapSummary: String {
        guard let swap = monitor.memory?.swapUsedBytes else { return "Unavailable" }
        return swap.formattedByteCount
    }

    private var loadAverageSummary: String {
        guard let load = monitor.loadAverage else { return "Unavailable" }
        return String(format: "%.2f · %.2f · %.2f", load.oneMinute, load.fiveMinutes, load.fifteenMinutes)
    }

    private var uptimeSummary: String {
        guard let uptime = monitor.systemUptime else { return "Unavailable" }
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
            Text(value).font(.system(size: 22, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WidgetDesign.inset, in: RoundedRectangle(cornerRadius: 14))
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
