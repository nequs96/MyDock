import CoreAudio
import Foundation

// MARK: - Models

/// How an output device is connected, reduced to what the widget draws.
enum AudioOutputTransport: String, Equatable, Sendable {
    case builtIn, usb, bluetooth, airPlay, hdmi, displayPort, thunderbolt, aggregate, virtual, other

    init(rawTransport: UInt32) {
        switch rawTransport {
        case UInt32(kAudioDeviceTransportTypeBuiltIn): self = .builtIn
        case UInt32(kAudioDeviceTransportTypeUSB): self = .usb
        case UInt32(kAudioDeviceTransportTypeBluetooth), UInt32(kAudioDeviceTransportTypeBluetoothLE): self = .bluetooth
        case UInt32(kAudioDeviceTransportTypeAirPlay): self = .airPlay
        case UInt32(kAudioDeviceTransportTypeHDMI): self = .hdmi
        case UInt32(kAudioDeviceTransportTypeDisplayPort): self = .displayPort
        case UInt32(kAudioDeviceTransportTypeThunderbolt): self = .thunderbolt
        case UInt32(kAudioDeviceTransportTypeAggregate): self = .aggregate
        case UInt32(kAudioDeviceTransportTypeVirtual): self = .virtual
        default: self = .other
        }
    }

    /// A short, honest connection label for a caption. Nil when the type tells the user nothing.
    var title: String? {
        switch self {
        case .builtIn: "Built-in"
        case .usb: "USB"
        case .bluetooth: "Bluetooth"
        case .airPlay: "AirPlay"
        case .hdmi: "HDMI"
        case .displayPort: "DisplayPort"
        case .thunderbolt: "Thunderbolt"
        case .aggregate: "Aggregate"
        case .virtual: "Virtual"
        case .other: nil
        }
    }
}

struct AudioOutputDevice: Equatable, Identifiable, Sendable {
    /// The Core Audio object ID. It is only valid while the device is connected; the UID is the durable identity.
    var id: UInt32
    var uid: String
    var name: String
    var transport: AudioOutputTransport

    var symbol: String { AudioOutputPresentation.symbol(transport: transport, name: name) }
    var shortName: String { AudioOutputPresentation.shortName(name: name, transport: transport) }
}

/// Volume and mute as the current device reports them. A nil value means the device does not let the Mac set it.
struct AudioOutputControlState: Equatable, Sendable {
    /// 0...1.
    var volume: Double?
    var isMuted: Bool?
    static let none = AudioOutputControlState(volume: nil, isMuted: nil)
}

enum AudioOutputError: Error, Equatable, Sendable {
    case nativeEffectsDisabled
    case deviceUnavailable
    case switchNotApplied
    case volumeNotSettable
    case muteNotSettable
    case invalidValue
    case system(OSStatus)
    case failed

    /// Maps a Core Audio status. A device that vanished mid-call reports a bad device or bad object error.
    init(status: OSStatus) {
        if status == OSStatus(kAudioHardwareBadDeviceError) || status == OSStatus(kAudioHardwareBadObjectError) {
            self = .deviceUnavailable
        } else {
            self = .system(status)
        }
    }

    init(_ error: Error) { self = (error as? AudioOutputError) ?? .failed }

    var message: String {
        switch self {
        case .nativeEffectsDisabled: "Audio changes are unavailable in this session."
        case .deviceUnavailable: "That device isn’t available."
        case .switchNotApplied: "macOS didn’t switch to that device."
        case .volumeNotSettable: "This device’s volume is controlled by the device."
        case .muteNotSettable: "This device can’t be muted from the Mac."
        case .invalidValue: "That value isn’t valid."
        case .system(let status): "Couldn’t change the output (error \(status))."
        case .failed: "Couldn’t change the output."
        }
    }
}

extension AudioOutputError: LocalizedError {
    var errorDescription: String? { message }
}

// MARK: - Pure presentation

enum AudioOutputPresentation {
    private static func suggestsHeadphones(_ name: String) -> Bool {
        let lower = name.lowercased()
        return ["headphone", "headset", "earphone", "earbuds", "buds"].contains { lower.contains($0) }
    }

    /// SF Symbol for a device: by connection, refined by what the name says.
    static func symbol(transport: AudioOutputTransport, name: String) -> String {
        let lower = name.lowercased()
        switch transport {
        case .bluetooth:
            if lower.contains("airpods") { return "airpods" }
            if lower.contains("speaker") { return "hifispeaker" }
            return "headphones"
        case .builtIn: return suggestsHeadphones(name) ? "headphones" : "speaker.wave.2"
        case .usb: return suggestsHeadphones(name) ? "headphones" : "hifispeaker"
        case .thunderbolt: return "hifispeaker"
        case .airPlay: return "airplayaudio"
        case .hdmi, .displayPort: return "display"
        case .aggregate, .virtual: return "waveform"
        case .other: return suggestsHeadphones(name) ? "headphones" : "speaker.wave.2"
        }
    }

    /// The name a compact face shows. A built-in device drops the model ("MacBook Pro Speakers" becomes "Speakers").
    static func shortName(name: String, transport: AudioOutputTransport) -> String {
        guard transport == .builtIn else { return name }
        for suffix in ["Speakers", "Headphones"] where name.hasSuffix(" " + suffix) { return suffix }
        return name
    }

    static func percentText(_ volume: Double) -> String {
        let clamped = volume.isFinite ? min(1, max(0, volume)) : 0
        return "\(Int((clamped * 100).rounded()))%"
    }
}

/// What a Dock face draws, derived from the current device and its controls.
struct AudioOutputFaceReading: Equatable, Sendable {
    var name: String
    var shortName: String
    var symbol: String
    /// Volume, "Muted", or the connection type: one short line for the wide face.
    var detail: String?
    var accessibilityValue: String

    init(device: AudioOutputDevice?, controls: AudioOutputControlState) {
        guard let device else {
            self = .unavailable
            return
        }
        let muted = controls.isMuted == true
        let detail: String? = muted ? "Muted" : controls.volume.map(AudioOutputPresentation.percentText) ?? device.transport.title
        name = device.name
        shortName = device.shortName
        symbol = muted ? "speaker.slash" : device.symbol
        self.detail = detail
        accessibilityValue = [device.name, detail].compactMap { $0 }.joined(separator: ", ")
    }

    private init(name: String, shortName: String, symbol: String, detail: String?, accessibilityValue: String) {
        self.name = name; self.shortName = shortName; self.symbol = symbol
        self.detail = detail; self.accessibilityValue = accessibilityValue
    }

    static let unavailable = AudioOutputFaceReading(name: "No output", shortName: "No output", symbol: "speaker.slash",
                                                    detail: nil, accessibilityValue: "No output device")
    /// The gallery and preview sample.
    static let sample = AudioOutputFaceReading(device: AudioOutputDevice(id: 1, uid: "sample", name: "AirPods Pro", transport: .bluetooth),
                                               controls: AudioOutputControlState(volume: 0.62, isMuted: false))
}

enum AudioOutputOrdering {
    /// Built-in first, then alphabetical (locale-aware), with the UID breaking ties so the order is stable.
    static func sorted(_ devices: [AudioOutputDevice]) -> [AudioOutputDevice] {
        devices.sorted { lhs, rhs in
            let lhsBuiltIn = lhs.transport == .builtIn, rhsBuiltIn = rhs.transport == .builtIn
            if lhsBuiltIn != rhsBuiltIn { return lhsBuiltIn }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.uid < rhs.uid
        }
    }
}

/// Listeners run only while a popout is open, or while a face is on a visible Dock.
enum AudioOutputObservationPolicy {
    static func shouldObserve(dockVisible: Bool, faceCount: Int, popoutCount: Int) -> Bool {
        popoutCount > 0 || (dockVisible && faceCount > 0)
    }
}

// MARK: - Hardware boundary

enum AudioControlKind: Hashable, Sendable { case volume, mute }

struct AudioControlAddress: Hashable, Sendable {
    var kind: AudioControlKind
    /// 0 is the main element; 1 and 2 are the left and right channels.
    var element: UInt32
}

struct AudioDeviceDescription: Equatable, Sendable {
    var id: UInt32
    var uid: String
    var name: String
    var transportRaw: UInt32
    var outputChannelCount: Int
}

protocol AudioOutputObservation: AnyObject {
    func cancel()
}

/// The small surface of Core Audio the widget needs. Tests use a fake; the app uses `CoreAudioOutputHardware`.
/// Only the playback (output) scope is ever read or written.
protocol AudioOutputHardware {
    func allDeviceIDs() throws -> [UInt32]
    /// Nil when the device is gone or unreadable.
    func describe(_ deviceID: UInt32) -> AudioDeviceDescription?
    func defaultOutputDeviceID() throws -> UInt32?
    func setDefaultOutputDeviceID(_ deviceID: UInt32) throws
    /// True only when the property exists and Core Audio reports it settable.
    func isSettable(_ deviceID: UInt32, _ control: AudioControlAddress) -> Bool
    /// Volume as 0...1, mute as 0 or 1.
    func readScalar(_ deviceID: UInt32, _ control: AudioControlAddress) throws -> Double
    func writeScalar(_ deviceID: UInt32, _ control: AudioControlAddress, value: Double) throws
    /// Reports device-list and default-output changes until cancelled. The handler may run on any queue.
    func startObserving(_ onChange: @escaping @Sendable () -> Void) -> (any AudioOutputObservation)?
}

// MARK: - Logic over the hardware boundary

enum AudioOutputCatalog {
    static let mainElement: UInt32 = 0
    private static let channelElements: [UInt32] = [1, 2]

    /// Apps create hidden aggregates for the default device; they are not choices.
    static func isHiddenSystemDevice(uid: String) -> Bool { uid.hasPrefix("CADefaultDeviceAggregate") }

    static func devices(_ hardware: any AudioOutputHardware) throws -> [AudioOutputDevice] {
        var result: [AudioOutputDevice] = []
        for id in try hardware.allDeviceIDs() {
            guard let description = hardware.describe(id), description.outputChannelCount > 0,
                  !isHiddenSystemDevice(uid: description.uid) else { continue }
            let name = description.name.isEmpty ? description.uid : description.name
            result.append(AudioOutputDevice(id: description.id, uid: description.uid, name: name,
                                            transport: AudioOutputTransport(rawTransport: description.transportRaw)))
        }
        return AudioOutputOrdering.sorted(result)
    }

    /// The elements to write for a control: the main element when it is settable, else the settable channels among 1 and 2.
    /// Empty means the device does not let the Mac set it.
    static func plan(_ kind: AudioControlKind, deviceID: UInt32, hardware: any AudioOutputHardware) -> [UInt32] {
        if hardware.isSettable(deviceID, AudioControlAddress(kind: kind, element: mainElement)) { return [mainElement] }
        return channelElements.filter { hardware.isSettable(deviceID, AudioControlAddress(kind: kind, element: $0)) }
    }

    static func controlState(_ hardware: any AudioOutputHardware, deviceID: UInt32) -> AudioOutputControlState {
        let volumes = plan(.volume, deviceID: deviceID, hardware: hardware).compactMap {
            try? hardware.readScalar(deviceID, AudioControlAddress(kind: .volume, element: $0))
        }
        let mutes = plan(.mute, deviceID: deviceID, hardware: hardware).compactMap {
            try? hardware.readScalar(deviceID, AudioControlAddress(kind: .mute, element: $0))
        }
        return AudioOutputControlState(
            volume: volumes.isEmpty ? nil : min(1, max(0, volumes.reduce(0, +) / Double(volumes.count))),
            isMuted: mutes.isEmpty ? nil : mutes.allSatisfy { $0 >= 0.5 })
    }

    static func write(_ kind: AudioControlKind, value: Double, deviceID: UInt32, hardware: any AudioOutputHardware) throws {
        guard value.isFinite else { throw AudioOutputError.invalidValue }
        let elements = plan(kind, deviceID: deviceID, hardware: hardware)
        guard !elements.isEmpty else { throw kind == .volume ? AudioOutputError.volumeNotSettable : AudioOutputError.muteNotSettable }
        let clamped = min(1, max(0, value))
        for element in elements {
            try hardware.writeScalar(deviceID, AudioControlAddress(kind: kind, element: element), value: clamped)
        }
    }
}

// MARK: - Service

/// Current output, the available outputs, and explicit switching. The system default output is the only
/// thing it changes; it never opens an input or recording path.
@MainActor
final class AudioOutputService: ObservableObject {
    static let shared = AudioOutputService()

    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var currentID: UInt32?
    @Published private(set) var controls = AudioOutputControlState.none
    @Published private(set) var lastError: AudioOutputError?

    private let hardware: any AudioOutputHardware
    private let scheduler: RefreshScheduler
    private let allowsNativeEffects: Bool
    private var subscribers = Set<UUID>()
    private var visiblePopouts = Set<UUID>()
    private var dockIsVisible = false
    private var schedulerDemand: RefreshDemandToken?
    private var observation: (any AudioOutputObservation)?

    init(hardware: any AudioOutputHardware = CoreAudioOutputHardware(),
         scheduler: RefreshScheduler = .shared,
         allowsNativeEffects: Bool = AppRuntimeEnvironment.allowsNativeEffects) {
        self.hardware = hardware
        self.scheduler = scheduler
        self.allowsNativeEffects = allowsNativeEffects
    }

    var currentDevice: AudioOutputDevice? { devices.first { $0.id == currentID } }
    var isObserving: Bool { observation != nil }
    var holdsPopoutDemand: Bool { schedulerDemand != nil }

    // MARK: Demand

    func subscribe(_ identifier: UUID, popout: Bool = false) {
        subscribers.insert(identifier)
        if popout { visiblePopouts.insert(identifier) }
        let wasObserving = isObserving
        updateObservation()
        // A newly opened popout shows fresh volume even when a face was already listening.
        if popout, wasObserving { refresh() }
    }

    func unsubscribe(_ identifier: UUID) {
        subscribers.remove(identifier)
        visiblePopouts.remove(identifier)
        updateObservation()
    }

    func setDockVisible(_ visible: Bool) {
        guard dockIsVisible != visible else { return }
        dockIsVisible = visible
        updateObservation()
    }

    private func updateObservation() {
        scheduler.setDemand(&schedulerDemand, kind: .popout, active: !visiblePopouts.isEmpty)
        let shouldObserve = allowsNativeEffects && AudioOutputObservationPolicy.shouldObserve(
            dockVisible: dockIsVisible, faceCount: subscribers.count, popoutCount: visiblePopouts.count)
        guard shouldObserve != isObserving else { return }
        if shouldObserve {
            refresh()
            observation = hardware.startObserving { [weak self] in
                Task { @MainActor in self?.hardwareChanged() }
            }
        } else {
            observation?.cancel()
            observation = nil
        }
    }

    private func hardwareChanged() {
        guard isObserving else { return }
        lastError = nil
        refresh()
    }

    // MARK: Reading

    func refresh() {
        guard allowsNativeEffects else {
            devices = []; currentID = nil; controls = .none
            return
        }
        do {
            let list = try AudioOutputCatalog.devices(hardware)
            let current = try hardware.defaultOutputDeviceID()
            devices = list
            currentID = current
            controls = list.first { $0.id == current }
                .map { AudioOutputCatalog.controlState(hardware, deviceID: $0.id) } ?? .none
        } catch {
            devices = []; currentID = nil; controls = .none
            lastError = AudioOutputError(error)
        }
    }

    // MARK: Actions

    /// Makes `device` the system output. The device is looked up again first, so an unplugged device
    /// gives an explicit error, and the result is read back so a refused switch is never reported as done.
    func select(_ device: AudioOutputDevice) {
        lastError = nil
        guard allowsNativeEffects else { lastError = .nativeEffectsDisabled; return }
        do {
            let known = try AudioOutputCatalog.devices(hardware)
            guard let target = known.first(where: { $0.id == device.id && $0.uid == device.uid }) else {
                throw AudioOutputError.deviceUnavailable
            }
            try hardware.setDefaultOutputDeviceID(target.id)
            guard try hardware.defaultOutputDeviceID() == target.id else { throw AudioOutputError.switchNotApplied }
        } catch {
            lastError = AudioOutputError(error)
        }
        let error = lastError
        refresh()
        if let error { lastError = error }
    }

    func setVolume(_ volume: Double) {
        applyControl(.volume, value: volume) { [self] in
            controls.volume = min(1, max(0, volume))
        }
    }

    func setMuted(_ muted: Bool) {
        applyControl(.mute, value: muted ? 1 : 0) { [self] in
            controls.isMuted = muted
        }
    }

    private func applyControl(_ kind: AudioControlKind, value: Double, onSuccess: () -> Void) {
        lastError = nil
        guard allowsNativeEffects else { lastError = .nativeEffectsDisabled; return }
        guard let id = currentID else { lastError = .deviceUnavailable; return }
        do {
            try AudioOutputCatalog.write(kind, value: value, deviceID: id, hardware: hardware)
            onSuccess()
        } catch {
            lastError = AudioOutputError(error)
            let failure = lastError
            refresh()
            if let failure { lastError = failure }
        }
    }
}

// MARK: - Core Audio

/// The real hardware. Output scope only: no input, recording or capture property is ever touched.
struct CoreAudioOutputHardware: AudioOutputHardware {
    private static var systemObject: AudioObjectID { AudioObjectID(kAudioObjectSystemObject) }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                                element: AudioObjectPropertyElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static func controlAddress(_ control: AudioControlAddress) -> AudioObjectPropertyAddress {
        let selector = control.kind == .volume ? AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar)
                                               : AudioObjectPropertySelector(kAudioDevicePropertyMute)
        return address(selector, scope: AudioObjectPropertyScope(kAudioObjectPropertyScopeOutput), element: control.element)
    }

    func allDeviceIDs() throws -> [UInt32] {
        var address = Self.address(AudioObjectPropertySelector(kAudioHardwarePropertyDevices))
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(Self.systemObject, &address, 0, nil, &size)
        guard status == noErr else { throw AudioOutputError(status: status) }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: count)
        status = ids.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(Self.systemObject, &address, 0, nil, &size, buffer.baseAddress!)
        }
        guard status == noErr else { throw AudioOutputError(status: status) }
        return ids
    }

    func describe(_ deviceID: UInt32) -> AudioDeviceDescription? {
        let channels = outputChannelCount(deviceID)
        guard let uid = stringProperty(deviceID, AudioObjectPropertySelector(kAudioDevicePropertyDeviceUID)) else { return nil }
        let name = stringProperty(deviceID, AudioObjectPropertySelector(kAudioObjectPropertyName)) ?? uid
        let transport = uint32Property(deviceID, AudioObjectPropertySelector(kAudioDevicePropertyTransportType)) ?? 0
        return AudioDeviceDescription(id: deviceID, uid: uid, name: name, transportRaw: transport, outputChannelCount: channels)
    }

    func defaultOutputDeviceID() throws -> UInt32? {
        var address = Self.address(AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice))
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(Self.systemObject, &address, 0, nil, &size, &device)
        guard status == noErr else { throw AudioOutputError(status: status) }
        return device == 0 ? nil : device
    }

    func setDefaultOutputDeviceID(_ deviceID: UInt32) throws {
        var device = AudioObjectID(deviceID)
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.address(AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice))
        let status = AudioObjectSetPropertyData(Self.systemObject, &address, 0, nil, size, &device)
        guard status == noErr else { throw AudioOutputError(status: status) }
        // The Sound settings move alerts along with the output. A refusal here does not undo the switch.
        var systemAddress = Self.address(AudioObjectPropertySelector(kAudioHardwarePropertyDefaultSystemOutputDevice))
        _ = AudioObjectSetPropertyData(Self.systemObject, &systemAddress, 0, nil, size, &device)
    }

    func isSettable(_ deviceID: UInt32, _ control: AudioControlAddress) -> Bool {
        var address = Self.controlAddress(control)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    func readScalar(_ deviceID: UInt32, _ control: AudioControlAddress) throws -> Double {
        var address = Self.controlAddress(control)
        switch control.kind {
        case .volume:
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
            guard status == noErr else { throw AudioOutputError(status: status) }
            return Double(value)
        case .mute:
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
            guard status == noErr else { throw AudioOutputError(status: status) }
            return value == 0 ? 0 : 1
        }
    }

    func writeScalar(_ deviceID: UInt32, _ control: AudioControlAddress, value: Double) throws {
        var address = Self.controlAddress(control)
        switch control.kind {
        case .volume:
            var scalar = Float32(min(1, max(0, value)))
            let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar)
            guard status == noErr else { throw AudioOutputError(status: status) }
        case .mute:
            var flag: UInt32 = value >= 0.5 ? 1 : 0
            let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &flag)
            guard status == noErr else { throw AudioOutputError(status: status) }
        }
    }

    func startObserving(_ onChange: @escaping @Sendable () -> Void) -> (any AudioOutputObservation)? {
        let observation = CoreAudioObservation()
        let selectors = [AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
                         AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice)]
        for selector in selectors {
            let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
            var address = Self.address(selector)
            let status = AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, DispatchQueue.main, block)
            if status == noErr { observation.add(selector: selector, block: block) }
        }
        guard observation.isActive else { return nil }
        return observation
    }

    // MARK: Property helpers

    private func outputChannelCount(_ deviceID: UInt32) -> Int {
        var address = Self.address(AudioObjectPropertySelector(kAudioDevicePropertyStreamConfiguration),
                                   scope: AudioObjectPropertyScope(kAudioObjectPropertyScopeOutput))
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func stringProperty(_ deviceID: UInt32, _ selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private func uint32Property(_ deviceID: UInt32, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = Self.address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}

/// Holds the registered listener blocks so the same blocks can be removed again.
private final class CoreAudioObservation: AudioOutputObservation {
    private var registrations: [(selector: AudioObjectPropertySelector, block: AudioObjectPropertyListenerBlock)] = []

    var isActive: Bool { !registrations.isEmpty }

    func add(selector: AudioObjectPropertySelector, block: @escaping AudioObjectPropertyListenerBlock) {
        registrations.append((selector, block))
    }

    func cancel() {
        for registration in registrations {
            var address = AudioObjectPropertyAddress(mSelector: registration.selector,
                                                     mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                                                     mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
            _ = AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address,
                                                       DispatchQueue.main, registration.block)
        }
        registrations = []
    }
}
