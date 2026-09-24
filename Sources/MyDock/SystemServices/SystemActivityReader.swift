import Darwin
import Foundation

struct HostCPUTicks: Equatable, Sendable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64
}

struct HostMemoryReading: Equatable, Sendable {
    var usedBytes: UInt64
    var totalBytes: UInt64
    var swapUsedBytes: UInt64?
    var activeBytes: UInt64
    var wiredBytes: UInt64
    var compressedBytes: UInt64
    var inactiveBytes: UInt64
    var freeBytes: UInt64
    var purgeableBytes: UInt64
}

struct SystemVolumeReading: Equatable, Sendable {
    var name: String
    var totalBytes: UInt64
    var availableBytes: UInt64
}

struct SystemLoadAverage: Equatable, Sendable {
    var oneMinute: Double
    var fiveMinutes: Double
    var fifteenMinutes: Double
}

enum SystemThermalState: String, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .unknown
        }
    }

    var title: String { rawValue.capitalized }
}

struct HostActivityReading: Equatable, Sendable {
    var cpuTicks: HostCPUTicks
    var perCoreCPUTicks: [HostCPUTicks]?
    var memory: HostMemoryReading
    var loadAverage: SystemLoadAverage?
    var thermalState: SystemThermalState
    var systemUptime: TimeInterval
    var startupVolume: SystemVolumeReading?
}

enum CPUUsageCalculator {
    static func percentage(from previous: HostCPUTicks, to current: HostCPUTicks) -> Double? {
        let previousTotal = previous.user &+ previous.system &+ previous.idle &+ previous.nice
        let currentTotal = current.user &+ current.system &+ current.idle &+ current.nice
        guard currentTotal > previousTotal else { return nil }
        let idleDelta = current.idle >= previous.idle ? current.idle - previous.idle : 0
        let totalDelta = currentTotal - previousTotal
        guard totalDelta > 0 else { return nil }
        let busyDelta = totalDelta > idleDelta ? totalDelta - idleDelta : 0
        return min(100, max(0, Double(busyDelta) / Double(totalDelta) * 100))
    }
}

enum PerCoreCPUUsageCalculator {
    static func percentages(previous: [HostCPUTicks], current: [HostCPUTicks]) -> [Double]? {
        guard !current.isEmpty, previous.count == current.count else { return nil }
        return zip(previous, current).map { old, new in
            CPUUsageCalculator.percentage(from: old, to: new) ?? 0
        }
    }
}

enum SystemActivityReader {
    static func read() -> HostActivityReading? {
        guard let ticks = cpuTicks(), let memory = memoryReading() else { return nil }
        return HostActivityReading(cpuTicks: ticks,
                                  perCoreCPUTicks: processorCPUTicks(),
                                  memory: memory,
                                  loadAverage: loadAverage(),
                                  thermalState: SystemThermalState(ProcessInfo.processInfo.thermalState),
                                  systemUptime: ProcessInfo.processInfo.systemUptime,
                                  startupVolume: startupVolumeReading())
    }

    private static func cpuTicks() -> HostCPUTicks? {
        var load = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return HostCPUTicks(user: UInt64(load.cpu_ticks.0),
                            system: UInt64(load.cpu_ticks.1),
                            idle: UInt64(load.cpu_ticks.2),
                            nice: UInt64(load.cpu_ticks.3))
    }

    private static func processorCPUTicks() -> [HostCPUTicks]? {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &processorCount, &processorInfo, &processorInfoCount)
        guard result == KERN_SUCCESS, processorCount > 0, let processorInfo else { return nil }
        let byteCount = vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: processorInfo)), byteCount)
        }

        let loads = UnsafeRawPointer(processorInfo).assumingMemoryBound(to: processor_cpu_load_info_data_t.self)
        return (0..<Int(processorCount)).map { index in
            let ticks = loads[index].cpu_ticks
            return HostCPUTicks(user: UInt64(ticks.0), system: UInt64(ticks.1),
                                idle: UInt64(ticks.2), nice: UInt64(ticks.3))
        }
    }

    private static func loadAverage() -> SystemLoadAverage? {
        var samples = [Double](repeating: 0, count: 3)
        let count = samples.withUnsafeMutableBufferPointer { buffer in
            getloadavg(buffer.baseAddress, Int32(buffer.count))
        }
        guard count == 3 else { return nil }
        return SystemLoadAverage(oneMinute: samples[0], fiveMinutes: samples[1], fifteenMinutes: samples[2])
    }

    private static func memoryReading() -> HostMemoryReading? {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }
        let pageBytes = UInt64(pageSize)
        let active = UInt64(statistics.active_count) * pageBytes
        let wired = UInt64(statistics.wire_count) * pageBytes
        let compressed = UInt64(statistics.compressor_page_count) * pageBytes
        let usedBytes = active &+ wired &+ compressed
        var swap: xsw_usage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapBytes: UInt64? = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 ? swap.xsu_used : nil

        return HostMemoryReading(usedBytes: min(ProcessInfo.processInfo.physicalMemory, usedBytes),
                                 totalBytes: ProcessInfo.processInfo.physicalMemory,
                                 swapUsedBytes: swapBytes,
                                 activeBytes: active,
                                 wiredBytes: wired,
                                 compressedBytes: compressed,
                                 inactiveBytes: UInt64(statistics.inactive_count) * pageBytes,
                                 freeBytes: UInt64(statistics.free_count) * pageBytes,
                                 purgeableBytes: UInt64(statistics.purgeable_count) * pageBytes)
    }

    private static func startupVolumeReading() -> SystemVolumeReading? {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityKey]
        guard let values = try? root.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacity, available >= 0 else { return nil }
        return SystemVolumeReading(name: values.volumeLocalizedName ?? "Startup volume",
                                   totalBytes: UInt64(total),
                                   availableBytes: UInt64(available))
    }
}

struct StorageScanProgress: Equatable, Sendable {
    var visitedEntries: Int
    var scannedFileCount: Int
    var scannedBytes: UInt64
}

struct StorageScanEntry: Identifiable, Equatable, Sendable {
    var path: String
    var name: String
    var byteSize: UInt64
    var id: String { path }
}

struct StorageScanResult: Equatable, Sendable {
    var rootPath: String
    var scannedFileCount: Int
    var scannedBytes: UInt64
    var largestFiles: [StorageScanEntry]
    var skippedEntries: Int
    var wasCapped: Bool
}

private final class StorageScanIssueCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func record() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

final class StorageScanCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

enum StorageScanner {
    enum ScanError: LocalizedError {
        case inaccessible
        case cancelled

        var errorDescription: String? {
            switch self {
            case .inaccessible: "MyDock couldn't read that folder. Choose a folder you can access."
            case .cancelled: "Storage scan cancelled."
            }
        }
    }

    static func scan(at root: URL,
                     cancellation: StorageScanCancellationFlag = StorageScanCancellationFlag(),
                     maximumFiles: Int = 100_000,
                     maximumDepth: Int = 24,
                     largestFileLimit: Int = 12,
                     onProgress: (@Sendable (StorageScanProgress) -> Void)? = nil) throws -> StorageScanResult {
        let didAccess = root.startAccessingSecurityScopedResource()
        defer { if didAccess { root.stopAccessingSecurityScopedResource() } }
        let issues = StorageScanIssueCounter()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in issues.record(); return true }
        ) else { throw ScanError.inaccessible }

        var count = 0
        var visited = 0
        var wasCapped = false
        var total: UInt64 = 0
        var largest: [StorageScanEntry] = []
        for case let url as URL in enumerator {
            if cancellation.isCancelled { throw ScanError.cancelled }
            visited += 1
            if enumerator.level > maximumDepth {
                wasCapped = true
                enumerator.skipDescendants()
                continue
            }
            guard visited <= maximumFiles else { wasCapped = true; break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                issues.record()
                continue
            }
            guard values.isSymbolicLink != true,
                  values.isRegularFile == true,
                  let size = values.fileSize, size >= 0 else { continue }
            count += 1
            let byteSize = UInt64(size)
            total &+= byteSize
            if visited.isMultiple(of: 256) {
                onProgress?(StorageScanProgress(visitedEntries: visited,
                                                scannedFileCount: count,
                                                scannedBytes: total))
            }
            largest.append(StorageScanEntry(path: url.path, name: url.lastPathComponent, byteSize: byteSize))
            largest.sort { $0.byteSize > $1.byteSize }
            if largest.count > max(1, largestFileLimit) { largest.removeLast() }
        }
        if cancellation.isCancelled { throw ScanError.cancelled }
        onProgress?(StorageScanProgress(visitedEntries: visited,
                                        scannedFileCount: count,
                                        scannedBytes: total))
        return StorageScanResult(rootPath: root.path,
                                 scannedFileCount: count,
                                 scannedBytes: total,
                                 largestFiles: largest,
                                 skippedEntries: issues.count,
                                 wasCapped: wasCapped)
    }
}
