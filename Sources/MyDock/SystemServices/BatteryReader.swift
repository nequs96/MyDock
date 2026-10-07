import Foundation
import IOKit.ps

struct BatteryReading: Equatable, Hashable, Identifiable {
    var name: String
    var percentage: Int
    var isCharging: Bool
    var isInternal: Bool
    /// Connected to a power adapter (`kIOPSPowerSourceStateKey`), whether or not it is charging.
    var isOnACPower = false
    /// Reported full (`kIOPSIsChargedKey`).
    var isCharged = false

    var displayName: String { BatteryReader.displayName(name: name, isInternal: isInternal) }
    /// "Charging", "Charged", "Not charging" (held on power) or "On battery".
    var statusText: String { BatteryStatusText.text(self) }

    var id: String { "\(name)-\(isInternal)" }
}

enum BatteryReader {
    static func displayName(name: String, isInternal: Bool) -> String {
        isInternal ? "Mac battery" : name
    }

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
        let powerState = description[kIOPSPowerSourceStateKey as String] as? String
        let charged = (description[kIOPSIsChargedKey as String] as? NSNumber)?.boolValue ?? false
        return BatteryReading(name: name, percentage: min(max(percentage, 0), 100),
                              isCharging: charging, isInternal: sourceType == (kIOPSInternalBatteryType as String),
                              isOnACPower: powerState == (kIOPSACPowerValue as String), isCharged: charged)
    }
}

/// A battery's state in the words macOS uses. "Not charging" means plugged in but held (for example by
/// Optimized Battery Charging), so a Mac running on its battery says "On battery" instead.
enum BatteryStatusText {
    static func text(_ reading: BatteryReading) -> String {
        if reading.isCharging { return "Charging" }
        if reading.isOnACPower { return reading.isCharged ? "Charged" : "Not charging" }
        return "On battery"
    }
}
