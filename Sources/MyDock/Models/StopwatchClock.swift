import Darwin
import Foundation
import IOKit

/// A sleep-inclusive monotonic clock reading scoped to one macOS boot session.
struct StopwatchClockSample: Codable, Hashable {
    let continuousSeconds: TimeInterval
    let bootSessionID: String

    func elapsed(since start: Self) -> TimeInterval? {
        guard bootSessionID == start.bootSessionID,
              continuousSeconds.isFinite, start.continuousSeconds.isFinite,
              continuousSeconds >= start.continuousSeconds else { return nil }
        return continuousSeconds - start.continuousSeconds
    }
}

enum StopwatchClock {
    private static let bootSessionID: String? = {
        // IOPM.h documents this root-domain property as stable through sleep and hibernation.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        guard let property = IORegistryEntryCreateCFProperty(service, "BootSessionUUID" as CFString,
                                                             kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let value = property as? String else { return nil }
        return UUID(uuidString: value)?.uuidString
    }()

    static func sample() -> StopwatchClockSample? {
        guard let bootSessionID else { return nil }
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else { return nil }
        let seconds = Double(mach_continuous_time()) * Double(timebase.numer)
            / Double(timebase.denom) / 1_000_000_000
        guard seconds.isFinite else { return nil }
        return StopwatchClockSample(continuousSeconds: seconds, bootSessionID: bootSessionID)
    }
}
