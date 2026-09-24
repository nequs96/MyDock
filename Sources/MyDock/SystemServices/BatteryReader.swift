import Foundation
import IOKit.ps

struct BatteryReading: Equatable, Hashable, Identifiable {
    var name: String
    var percentage: Int
    var isCharging: Bool
    var isInternal: Bool

    var id: String { "\(name)-\(isInternal)" }
}

enum BatteryReader {
    static func read() -> [BatteryReading] {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let handles = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [AnyObject] else { return [] }
        return handles.compactMap { handle in
            guard let description = IOPSGetPowerSourceDescription(snapshot, handle)?.takeUnretainedValue() as? [String: Any] else {
                return nil
            }
            return reading(from: description)
        }
        .sorted { $0.isInternal && !$1.isInternal }
    }

    static func reading(from description: [String: Any]) -> BatteryReading? {
        guard let current = (description[kIOPSCurrentCapacityKey as String] as? NSNumber)?.doubleValue,
              let maximum = (description[kIOPSMaxCapacityKey as String] as? NSNumber)?.doubleValue,
              maximum > 0 else { return nil }
        let percentage = Int((current / maximum * 100).rounded())
        let name = description[kIOPSNameKey as String] as? String ?? "Battery"
        let charging = (description[kIOPSIsChargingKey as String] as? NSNumber)?.boolValue ?? false
        let sourceType = description[kIOPSTypeKey as String] as? String
        return BatteryReading(name: name, percentage: min(max(percentage, 0), 100),
                              isCharging: charging, isInternal: sourceType == (kIOPSInternalBatteryType as String))
    }
}
