import Darwin
import Foundation

struct NetworkInterfaceCounters: Equatable, Sendable, Identifiable {
    var name: String
    var receivedBytes: UInt64?
    var sentBytes: UInt64?
    var addresses: [String]
    /// False for tunnels, bridges and peer-to-peer links, whose traffic a physical interface also counts.
    var isPhysical: Bool = true
    var id: String { name }
}

struct NetworkCountersReading: Equatable, Sendable {
    var uptime: TimeInterval
    var interfaces: [NetworkInterfaceCounters]
}

struct NetworkInterfaceRate: Equatable, Sendable, Identifiable {
    var name: String
    var receivedBytesPerSecond: Double?
    var sentBytesPerSecond: Double?
    var addresses: [String]
    var isPhysical: Bool = true
    var id: String { name }
}

enum NetworkRateCalculator {
    static func rates(previous: NetworkCountersReading,
                      current: NetworkCountersReading) -> [NetworkInterfaceRate] {
        let elapsed = current.uptime - previous.uptime
        guard elapsed > 0 else { return [] }
        let previousByName = Dictionary(uniqueKeysWithValues: previous.interfaces.map { ($0.name, $0) })
        return current.interfaces.map { interface in
            guard let before = previousByName[interface.name] else {
                return NetworkInterfaceRate(name: interface.name,
                                            receivedBytesPerSecond: nil,
                                            sentBytesPerSecond: nil,
                                            addresses: interface.addresses,
                                            isPhysical: interface.isPhysical)
            }
            let downloadRate = zipOptional(before.receivedBytes, interface.receivedBytes)
                .flatMap { plausibleDelta(from: $0.0, to: $0.1) }
                .map { Double($0) / elapsed }
            let uploadRate = zipOptional(before.sentBytes, interface.sentBytes)
                .flatMap { plausibleDelta(from: $0.0, to: $0.1) }
                .map { Double($0) / elapsed }
            return NetworkInterfaceRate(name: interface.name,
                                        receivedBytesPerSecond: downloadRate,
                                        sentBytesPerSecond: uploadRate,
                                        addresses: interface.addresses,
                                        isPhysical: interface.isPhysical)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Total throughput over physical interfaces only, so VPN, bridged and peer-to-peer traffic is not counted twice.
    static func physicalTotal(_ rates: [NetworkInterfaceRate], _ keyPath: KeyPath<NetworkInterfaceRate, Double?>) -> Double {
        rates.filter(\.isPhysical).compactMap { $0[keyPath: keyPath] }.reduce(0, +)
    }

    /// The physical total, or nil until every physical interface has a rate.
    static func completePhysicalTotal(_ rates: [NetworkInterfaceRate], _ keyPath: KeyPath<NetworkInterfaceRate, Double?>) -> Double? {
        let physical = rates.filter(\.isPhysical)
        guard !physical.isEmpty else { return nil }
        let values = physical.compactMap { $0[keyPath: keyPath] }
        guard values.count == physical.count else { return nil }
        return values.reduce(0, +)
    }

    /// A decrease is a 32-bit wrap only when the previous value was near the top of the range and the
    /// wrapped distance is under half the range. Anything else is a reset or reconnect: no rate for that interval.
    static func plausibleDelta(from previous: UInt64, to current: UInt64) -> UInt64? {
        guard current < previous else { return current - previous }
        let modulus = UInt64(UInt32.max) + 1
        guard previous < modulus, current < modulus else { return nil }
        let wrapped = (modulus - previous) + current
        return wrapped <= modulus / 2 ? wrapped : nil
    }

    private static func zipOptional(_ lhs: UInt64?, _ rhs: UInt64?) -> (UInt64, UInt64)? {
        guard let lhs, let rhs else { return nil }
        return (lhs, rhs)
    }
}

/// Tells physical links (Ethernet, Wi-Fi, cellular) from interfaces that carry the same traffic again.
enum NetworkInterfaceKindPolicy {
    /// Tunnels (VPN), bridges, AirDrop/peer-to-peer links, Internet Sharing and VLAN-style interfaces.
    private static let virtualPrefixes = ["utun", "ipsec", "ppp", "gif", "stf", "bridge", "awdl", "llw", "anpi",
                                          "ap", "vmenet", "feth", "vlan", "bond", "pktap"]
    /// `if_data.ifi_type` values: IFT_ETHER (Ethernet and Wi-Fi), IFT_IEEE80211, IFT_CELLULAR.
    private static let physicalTypes: Set<UInt8> = [0x06, 0x47, 0xff]

    static func isPhysical(name: String, interfaceType: UInt8?) -> Bool {
        guard !virtualPrefixes.contains(where: { name.hasPrefix($0) }) else { return false }
        guard let interfaceType else { return true }
        return physicalTypes.contains(interfaceType)
    }
}

enum NetworkInterfaceReader {
    private struct MutableInterface {
        var receivedBytes: UInt64?
        var sentBytes: UInt64?
        var interfaceType: UInt8?
        var addresses = Set<String>()
    }

    static func read() -> NetworkCountersReading? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(first) }

        var records: [String: MutableInterface] = [:]
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current {
            let value = entry.pointee
            defer { current = value.ifa_next }
            guard let namePointer = value.ifa_name else { continue }
            let name = String(cString: namePointer)
            let flags = Int32(value.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var record = records[name] ?? MutableInterface()

            if let address = value.ifa_addr {
                let family = Int32(address.pointee.sa_family)
                if family == AF_INET || family == AF_INET6,
                   let numeric = numericAddress(UnsafePointer(address)) {
                    record.addresses.insert(numeric)
                }
                if family == AF_LINK,
                   let rawData = value.ifa_data {
                    let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                    record.receivedBytes = UInt64(data.ifi_ibytes)
                    record.sentBytes = UInt64(data.ifi_obytes)
                    record.interfaceType = data.ifi_type
                }
            }
            records[name] = record
        }

        let interfaces = records.map { name, record in
            NetworkInterfaceCounters(name: name,
                                     receivedBytes: record.receivedBytes,
                                     sentBytes: record.sentBytes,
                                     addresses: record.addresses.sorted(),
                                     isPhysical: NetworkInterfaceKindPolicy.isPhysical(name: name, interfaceType: record.interfaceType))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return NetworkCountersReading(uptime: ProcessInfo.processInfo.systemUptime, interfaces: interfaces)
    }

    private static func numericAddress(_ address: UnsafePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = host.withUnsafeMutableBufferPointer { buffer in
            getnameinfo(address,
                        socklen_t(address.pointee.sa_len),
                        buffer.baseAddress,
                        socklen_t(buffer.count),
                        nil,
                        0,
                        NI_NUMERICHOST)
        }
        guard result == 0 else { return nil }
        return String(decoding: host.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
