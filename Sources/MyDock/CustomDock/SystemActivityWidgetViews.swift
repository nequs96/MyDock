import AppKit
import SwiftUI

struct SystemActivityWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(SystemActivityCompactWidgetView())
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(SystemActivityPopoutWidgetView())
    }
}

@MainActor
final class SystemActivityMonitor: ObservableObject {
    static let shared = SystemActivityMonitor()

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

    func subscribe(_ identifier: UUID) {
        subscribers.insert(identifier)
        updateSamplingState()
    }

    func unsubscribe(_ identifier: UUID) {
        subscribers.remove(identifier)
        updateSamplingState()
    }

    func setDockVisible(_ visible: Bool) {
        dockIsVisible = visible
        updateSamplingState()
    }

    private func updateSamplingState() {
        let shouldSample = SystemActivitySamplingPolicy.shouldSample(dockIsVisible: dockIsVisible,
                                                                      subscriberCount: subscribers.count)
        guard shouldSample != (samplingTask != nil) else { return }
        if !shouldSample {
            samplingTask?.cancel()
            samplingTask = nil
            previousTicks = nil
            previousPerCoreTicks = nil
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
        guard SystemActivitySamplingPolicy.shouldSample(dockIsVisible: dockIsVisible,
                                                         subscriberCount: subscribers.count) else { return }
        let reading = await Task.detached(priority: .utility) { SystemActivityReader.read() }.value
        guard let reading,
              SystemActivitySamplingPolicy.shouldSample(dockIsVisible: dockIsVisible,
                                                        subscriberCount: subscribers.count) else { return }
        cpuPercentage = previousTicks.flatMap { CPUUsageCalculator.percentage(from: $0, to: reading.cpuTicks) }
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
    @StateObject private var monitor = SystemActivityMonitor.shared
    @State private var subscriptionID = UUID()

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "waveform.path.ecg").font(.system(size: 18)).foregroundStyle(.tint)
            Text(monitor.cpuPercentage.map { "\(Int($0.rounded()))% CPU" } ?? "CPU")
                .font(.system(size: 8, weight: .medium)).lineLimit(1)
            if let memory = monitor.memory {
                Text("\(memory.usedBytes.formattedByteCount) RAM")
                    .font(.system(size: 7)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 54, height: 54)
        .onAppear { monitor.subscribe(subscriptionID) }
        .onDisappear { monitor.unsubscribe(subscriptionID) }
        .help("System Activity")
    }
}

private struct SystemActivityPopoutWidgetView: View {
    @StateObject private var monitor = SystemActivityMonitor.shared
    @StateObject private var scanner = StorageScanMonitor.shared
    @State private var subscriptionID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Live system readings").font(.headline)
                Spacer()
                Button("Refresh") { monitor.refreshNow() }
            }
            HStack(spacing: 10) {
                metricCard(title: "CPU", value: monitor.cpuPercentage.map { "\(Int($0.rounded()))%" } ?? "Warming up", symbol: "cpu")
                metricCard(title: "Memory", value: memorySummary, symbol: "memorychip")
                metricCard(title: "Swap", value: swapSummary, symbol: "externaldrive")
            }
            if let lastUpdated = monitor.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened)) · samples every 4 seconds while visible")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let perCorePercentages = monitor.perCorePercentages {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(Array(perCorePercentages.enumerated()), id: \.offset) { index, percentage in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text("Core \(index + 1)").font(.caption2).foregroundStyle(.secondary)
                                    Spacer(minLength: 3)
                                    Text("\(Int(percentage.rounded()))%")
                                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                ProgressView(value: percentage, total: 100)
                            }
                            .frame(width: 72)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 34)
                .accessibilityLabel("CPU use by logical processor")
            }
            HStack(spacing: 10) {
                metricCard(title: "Thermal", value: monitor.thermalState.title, symbol: "thermometer.medium")
                metricCard(title: "Load average 1 / 5 / 15 min", value: loadAverageSummary, symbol: "chart.bar.xaxis")
                metricCard(title: "Uptime", value: uptimeSummary, symbol: "clock")
            }

            if let memory = monitor.memory {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Memory detail").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("Pressure event: \(monitor.memoryPressure.title)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        memoryDetail("Active", memory.activeBytes)
                        memoryDetail("Wired", memory.wiredBytes)
                        memoryDetail("Compressed", memory.compressedBytes)
                        memoryDetail("Inactive", memory.inactiveBytes)
                        memoryDetail("Free", memory.freeBytes)
                        memoryDetail("Purgeable", memory.purgeableBytes)
                    }
                    Text("Pressure reports system change events; it may be unknown until one occurs. Memory categories overlap and should not be added together.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let volume = monitor.startupVolume {
                HStack {
                    Label(volume.name, systemImage: "internaldrive")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(volume.availableBytes.formattedByteCount) available of \(volume.totalBytes.formattedByteCount)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Storage scan").font(.headline)
                    Text("Scan Home, Applications, and Library separately, or choose a folder. Scans continue when this popout closes. MyDock does not delete or upload files.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if scanner.isScanning {
                    Button("Cancel") { scanner.cancel() }
                } else {
                    Button("Scan Folders") { scanner.scanDefaultLocations() }
                        .buttonStyle(.borderedProminent)
                    Button("Choose Folder…", action: chooseFolder)
                    if !scanner.results.isEmpty {
                        Button("Scan Again") { scanner.scanAgain() }
                    }
                }
            }
            if scanner.isScanning {
                ProgressView("Scanning \(scanner.currentPath ?? "folder")…")
                if let progress = scanner.progress {
                    Text("\(progress.visitedEntries) entries visited · \(progress.scannedFileCount) files · \(progress.scannedBytes.formattedByteCount)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(scanner.warnings, id: \.self) { warning in
                Text(warning).font(.caption).foregroundStyle(.red)
            }
            if !scanner.results.isEmpty {
                Text("Each location is counted independently; Home includes Library.")
                    .font(.caption2).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(scanner.results, id: \.rootPath) { storageResult in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(storageResult.rootPath).font(.caption.weight(.semibold))
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text(storageSummary(storageResult))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(storageResult.largestFiles) { file in
                                    Button { reveal(file) } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "doc").foregroundStyle(.secondary)
                                            Text(file.name).lineLimit(1)
                                            Spacer()
                                            Text(file.byteSize.formattedByteCount).monospacedDigit().foregroundStyle(.secondary)
                                            Image(systemName: "arrow.up.forward.app").foregroundStyle(.tertiary)
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 7).padding(.vertical, 5)
                                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                                    }
                                    .buttonStyle(.plain).help("Reveal in Finder")
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .frame(width: 620).frame(minHeight: 220, alignment: .topLeading)
        .onAppear { monitor.subscribe(subscriptionID) }
        .onDisappear { monitor.unsubscribe(subscriptionID) }
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
            Text(value).font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
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
