import CoreAudio
import Foundation
import Testing
@testable import MyDock

/// PX-4 / OP-05: the Audio Output family. Core Audio is never touched; a fake stands in for the hardware.
private final class FakeAudioHardware: AudioOutputHardware {
    struct Key: Hashable { var device: UInt32; var control: AudioControlAddress }

    final class Observation: AudioOutputObservation {
        var cancelled = false
        func cancel() { cancelled = true }
    }

    var order: [UInt32] = []
    var descriptions: [UInt32: AudioDeviceDescription] = [:]
    var defaultID: UInt32?
    var settable: Set<Key> = []
    var scalars: [Key: Double] = [:]
    var writes: [Key] = []
    var ignoresSetDefault = false
    var setDefaultCalls = 0
    var totalCalls = 0
    var observations: [Observation] = []

    func add(_ id: UInt32, _ uid: String, _ name: String, transport: AudioOutputTransport, channels: Int = 2) {
        let raw: UInt32
        switch transport {
        case .builtIn: raw = UInt32(kAudioDeviceTransportTypeBuiltIn)
        case .usb: raw = UInt32(kAudioDeviceTransportTypeUSB)
        case .bluetooth: raw = UInt32(kAudioDeviceTransportTypeBluetooth)
        case .airPlay: raw = UInt32(kAudioDeviceTransportTypeAirPlay)
        case .hdmi: raw = UInt32(kAudioDeviceTransportTypeHDMI)
        case .displayPort: raw = UInt32(kAudioDeviceTransportTypeDisplayPort)
        case .thunderbolt: raw = UInt32(kAudioDeviceTransportTypeThunderbolt)
        case .aggregate: raw = UInt32(kAudioDeviceTransportTypeAggregate)
        case .virtual: raw = UInt32(kAudioDeviceTransportTypeVirtual)
        case .other: raw = 0
        }
        order.append(id)
        descriptions[id] = AudioDeviceDescription(id: id, uid: uid, name: name, transportRaw: raw, outputChannelCount: channels)
    }

    func unplug(_ id: UInt32) {
        order.removeAll { $0 == id }
        descriptions[id] = nil
        if defaultID == id { defaultID = order.first }
    }

    func allow(_ id: UInt32, _ kind: AudioControlKind, element: UInt32, value: Double) {
        let key = Key(device: id, control: AudioControlAddress(kind: kind, element: element))
        settable.insert(key)
        scalars[key] = value
    }

    func allDeviceIDs() throws -> [UInt32] { totalCalls += 1; return order }
    func describe(_ deviceID: UInt32) -> AudioDeviceDescription? { totalCalls += 1; return descriptions[deviceID] }
    func defaultOutputDeviceID() throws -> UInt32? { totalCalls += 1; return defaultID }
    func setDefaultOutputDeviceID(_ deviceID: UInt32) throws {
        totalCalls += 1
        setDefaultCalls += 1
        if !ignoresSetDefault { defaultID = deviceID }
    }
    func isSettable(_ deviceID: UInt32, _ control: AudioControlAddress) -> Bool {
        totalCalls += 1
        return settable.contains(Key(device: deviceID, control: control))
    }
    func readScalar(_ deviceID: UInt32, _ control: AudioControlAddress) throws -> Double {
        totalCalls += 1
        return scalars[Key(device: deviceID, control: control)] ?? 0
    }
    func writeScalar(_ deviceID: UInt32, _ control: AudioControlAddress, value: Double) throws {
        totalCalls += 1
        let key = Key(device: deviceID, control: control)
        writes.append(key)
        scalars[key] = value
    }
    func startObserving(_ onChange: @escaping @Sendable () -> Void) -> (any AudioOutputObservation)? {
        let observation = Observation()
        observations.append(observation)
        return observation
    }
    var liveObservations: Int { observations.filter { !$0.cancelled }.count }

    struct ControlObservation { var device: UInt32; var observation: Observation; var onChange: @Sendable () -> Void }
    var controlObservations: [ControlObservation] = []
    func startObservingControls(of deviceID: UInt32, _ onChange: @escaping @Sendable () -> Void) -> (any AudioOutputObservation)? {
        totalCalls += 1
        let observation = Observation()
        controlObservations.append(ControlObservation(device: deviceID, observation: observation, onChange: onChange))
        return observation
    }
    var liveControlDevices: [UInt32] { controlObservations.filter { !$0.observation.cancelled }.map(\.device) }
    /// What Core Audio does when the volume keys or Control Center change a device.
    func changeControls(of deviceID: UInt32, volume: Double, muted: Bool) {
        scalars[Key(device: deviceID, control: AudioControlAddress(kind: .volume, element: 0))] = volume
        scalars[Key(device: deviceID, control: AudioControlAddress(kind: .mute, element: 0))] = muted ? 1 : 0
        for entry in controlObservations where entry.device == deviceID && !entry.observation.cancelled { entry.onChange() }
    }
}

@MainActor
struct AudioOutputTests {
    private static func fixture() -> FakeAudioHardware {
        let fake = FakeAudioHardware()
        fake.add(30, "usb-dac", "Desk DAC", transport: .usb)
        fake.add(10, "builtin", "MacBook Pro Speakers", transport: .builtIn)
        fake.add(20, "airpods", "AirPods Pro", transport: .bluetooth)
        fake.add(40, "mic-only", "Studio Microphone", transport: .usb, channels: 0)
        fake.add(50, "CADefaultDeviceAggregate-1234-0", "CADefaultDeviceAggregate", transport: .aggregate)
        fake.defaultID = 10
        return fake
    }

    private static func service(_ fake: FakeAudioHardware, native: Bool = true, scheduler: RefreshScheduler = .makeForTesting(dockVisible: false)) -> AudioOutputService {
        AudioOutputService(hardware: fake, scheduler: scheduler, allowsNativeEffects: native)
    }

    // MARK: Symbols and names

    @Test func transportTypesMapToSymbols() {
        #expect(AudioOutputTransport(rawTransport: UInt32(kAudioDeviceTransportTypeBuiltIn)) == .builtIn)
        #expect(AudioOutputTransport(rawTransport: UInt32(kAudioDeviceTransportTypeBluetooth)) == .bluetooth)
        #expect(AudioOutputTransport(rawTransport: UInt32(kAudioDeviceTransportTypeBluetoothLE)) == .bluetooth)
        #expect(AudioOutputTransport(rawTransport: UInt32(kAudioDeviceTransportTypeHDMI)) == .hdmi)
        #expect(AudioOutputTransport(rawTransport: 0) == .other)
        #expect(AudioOutputPresentation.symbol(transport: .builtIn, name: "MacBook Pro Speakers") == "speaker.wave.2")
        #expect(AudioOutputPresentation.symbol(transport: .builtIn, name: "External Headphones") == "headphones")
        #expect(AudioOutputPresentation.symbol(transport: .bluetooth, name: "Jakub’s AirPods Pro") == "airpods")
        #expect(AudioOutputPresentation.symbol(transport: .bluetooth, name: "WH-1000XM4") == "headphones")
        #expect(AudioOutputPresentation.symbol(transport: .bluetooth, name: "Party Speaker") == "hifispeaker")
        #expect(AudioOutputPresentation.symbol(transport: .usb, name: "Desk DAC") == "hifispeaker")
        #expect(AudioOutputPresentation.symbol(transport: .usb, name: "USB Headset") == "headphones")
        #expect(AudioOutputPresentation.symbol(transport: .hdmi, name: "LG Display") == "display")
        #expect(AudioOutputPresentation.symbol(transport: .displayPort, name: "Studio Display") == "display")
        #expect(AudioOutputPresentation.symbol(transport: .airPlay, name: "Kitchen") == "airplayaudio")
        #expect(AudioOutputPresentation.symbol(transport: .virtual, name: "Loopback") == "waveform")
        #expect(AudioOutputPresentation.symbol(transport: .other, name: "Unknown") == "speaker.wave.2")
    }

    @Test func shortNamesDropTheBuiltInModel() {
        #expect(AudioOutputPresentation.shortName(name: "MacBook Pro Speakers", transport: .builtIn) == "Speakers")
        #expect(AudioOutputPresentation.shortName(name: "External Headphones", transport: .builtIn) == "External Headphones")
        #expect(AudioOutputPresentation.shortName(name: "Studio Speakers", transport: .usb) == "Studio Speakers")
        #expect(AudioOutputPresentation.percentText(0.5) == "50%")
        #expect(AudioOutputPresentation.percentText(1.7) == "100%")
        #expect(AudioOutputPresentation.percentText(.nan) == "0%")
    }

    // MARK: Device list

    @Test func devicesAreOutputOnlyBuiltInFirstThenAlphabetical() throws {
        let fake = Self.fixture()
        let devices = try AudioOutputCatalog.devices(fake)
        #expect(devices.map(\.name) == ["MacBook Pro Speakers", "AirPods Pro", "Desk DAC"])
        #expect(devices.map(\.id) == [10, 20, 30])
        #expect(!devices.contains { $0.uid == "mic-only" }, "input-only devices are never listed")
        #expect(!devices.contains { $0.uid.hasPrefix("CADefaultDeviceAggregate") })
    }

    @Test func orderingIsStableAndLocaleAwareWithBuiltInPinnedFirst() {
        let devices = [
            AudioOutputDevice(id: 1, uid: "b", name: "speaker 10", transport: .usb),
            AudioOutputDevice(id: 2, uid: "a", name: "Speaker 2", transport: .usb),
            AudioOutputDevice(id: 3, uid: "z", name: "Zebra", transport: .builtIn),
            AudioOutputDevice(id: 4, uid: "y", name: "Same", transport: .usb),
            AudioOutputDevice(id: 5, uid: "x", name: "Same", transport: .usb)
        ]
        #expect(AudioOutputOrdering.sorted(devices).map(\.id) == [3, 5, 4, 2, 1])
    }

    // MARK: Settable properties

    @Test func mainElementWinsWhenSettable() {
        let fake = Self.fixture()
        fake.allow(10, .volume, element: 0, value: 0.4)
        fake.allow(10, .volume, element: 1, value: 0.9)
        #expect(AudioOutputCatalog.plan(.volume, deviceID: 10, hardware: fake) == [0])
    }

    @Test func channelsAreUsedWhenTheMainElementIsNotSettable() throws {
        let fake = Self.fixture()
        fake.allow(20, .volume, element: 1, value: 0.2)
        fake.allow(20, .volume, element: 2, value: 0.6)
        #expect(AudioOutputCatalog.plan(.volume, deviceID: 20, hardware: fake) == [1, 2])
        let state = AudioOutputCatalog.controlState(fake, deviceID: 20)
        #expect(abs((state.volume ?? -1) - 0.4) < 0.0001, "channels are averaged")
        try AudioOutputCatalog.write(.volume, value: 1.5, deviceID: 20, hardware: fake)
        #expect(fake.writes.map(\.control.element) == [1, 2])
        #expect(fake.scalars[.init(device: 20, control: .init(kind: .volume, element: 1))] == 1, "values are clamped")
    }

    @Test func controlsAreAbsentWhenThePropertyIsNotSettable() {
        let fake = Self.fixture()
        #expect(AudioOutputCatalog.plan(.volume, deviceID: 30, hardware: fake).isEmpty)
        #expect(AudioOutputCatalog.controlState(fake, deviceID: 30) == .none)
        #expect(throws: AudioOutputError.volumeNotSettable) {
            try AudioOutputCatalog.write(.volume, value: 0.5, deviceID: 30, hardware: fake)
        }
        #expect(throws: AudioOutputError.muteNotSettable) {
            try AudioOutputCatalog.write(.mute, value: 1, deviceID: 30, hardware: fake)
        }
        #expect(throws: AudioOutputError.invalidValue) {
            try AudioOutputCatalog.write(.volume, value: .nan, deviceID: 30, hardware: fake)
        }
        #expect(fake.writes.isEmpty)
    }

    @Test func volumeAndMuteAreIndependent() {
        let fake = Self.fixture()
        fake.allow(10, .mute, element: 0, value: 1)
        let state = AudioOutputCatalog.controlState(fake, deviceID: 10)
        #expect(state.volume == nil && state.isMuted == true)
    }

    // MARK: Service

    @Test func selectingADeviceSwitchesAndReadsItBack() {
        let fake = Self.fixture()
        fake.allow(20, .volume, element: 0, value: 0.3)
        let service = Self.service(fake)
        service.refresh()
        #expect(service.currentDevice?.uid == "builtin" && service.controls == .none)
        let target = service.devices.first { $0.uid == "airpods" }!
        service.select(target)
        #expect(service.lastError == nil)
        #expect(service.currentDevice?.uid == "airpods")
        #expect(service.controls.volume == 0.3)
    }

    @Test func anUnpluggedDeviceGivesAnExplicitError() {
        let fake = Self.fixture()
        let service = Self.service(fake)
        service.refresh()
        let target = service.devices.first { $0.uid == "airpods" }!
        fake.unplug(20)
        service.select(target)
        #expect(service.lastError == .deviceUnavailable)
        #expect(fake.setDefaultCalls == 0)
        #expect(!service.devices.contains { $0.uid == "airpods" }, "the list is refreshed after the failure")
        #expect(service.currentDevice?.uid == "builtin")
    }

    @Test func aRefusedSwitchIsNotReportedAsDone() {
        let fake = Self.fixture()
        fake.ignoresSetDefault = true
        let service = Self.service(fake)
        service.refresh()
        service.select(service.devices.first { $0.uid == "airpods" }!)
        #expect(service.lastError == .switchNotApplied)
        #expect(service.currentDevice?.uid == "builtin")
    }

    @Test func volumeAndMuteWriteOnlyWhereSettable() {
        let fake = Self.fixture()
        fake.allow(10, .volume, element: 0, value: 0.5)
        let service = Self.service(fake)
        service.refresh()
        #expect(service.controls.volume == 0.5 && service.controls.isMuted == nil)
        service.setVolume(0.8)
        #expect(service.lastError == nil && service.controls.volume == 0.8)
        service.setMuted(true)
        #expect(service.lastError == .muteNotSettable)
        #expect(fake.writes.count == 1)
    }

    @Test func isolatedRunsNeverTouchTheHardware() {
        let fake = Self.fixture()
        let service = Self.service(fake, native: false)
        service.refresh()
        service.select(AudioOutputDevice(id: 20, uid: "airpods", name: "AirPods Pro", transport: .bluetooth))
        #expect(service.lastError == .nativeEffectsDisabled)
        service.setVolume(0.2)
        #expect(service.lastError == .nativeEffectsDisabled)
        service.subscribe(UUID(), popout: true)
        #expect(!service.isObserving)
        #expect(service.devices.isEmpty && service.currentDevice == nil)
        #expect(fake.totalCalls == 0 && fake.observations.isEmpty)
    }

    @Test func listenersRunOnlyWhileAFaceOrPopoutIsVisible() {
        #expect(!AudioOutputObservationPolicy.shouldObserve(dockVisible: true, faceCount: 0, popoutCount: 0))
        #expect(!AudioOutputObservationPolicy.shouldObserve(dockVisible: false, faceCount: 2, popoutCount: 0))
        #expect(AudioOutputObservationPolicy.shouldObserve(dockVisible: true, faceCount: 1, popoutCount: 0))
        #expect(AudioOutputObservationPolicy.shouldObserve(dockVisible: false, faceCount: 1, popoutCount: 1))

        let fake = Self.fixture()
        let scheduler = RefreshScheduler.makeForTesting(dockVisible: false)
        let service = Self.service(fake, scheduler: scheduler)
        let face = UUID(), popout = UUID()
        service.subscribe(face)
        #expect(!service.isObserving, "a face on a hidden Dock does not listen")
        service.setDockVisible(true)
        #expect(service.isObserving && fake.liveObservations == 1)
        #expect(!service.devices.isEmpty, "listening starts with a read")
        service.setDockVisible(false)
        #expect(!service.isObserving && fake.liveObservations == 0)
        service.subscribe(popout, popout: true)
        #expect(service.isObserving && service.holdsPopoutDemand && scheduler.isActive)
        service.unsubscribe(popout)
        #expect(!service.isObserving && !service.holdsPopoutDemand && !scheduler.isActive)
        service.setDockVisible(true)
        service.unsubscribe(face)
        #expect(!service.isObserving && fake.liveObservations == 0)
        service.subscribe(popout, popout: true)
        service.subscribe(popout, popout: true)
        service.unsubscribe(popout)
        #expect(fake.liveObservations == 0 && !scheduler.isActive)
    }

    /// S05-002: the volume keys, Control Center and other apps change the current device; the reading follows
    /// them while observed, and the listener moves with the current output.
    @Test func volumeAndMuteFollowChangesMadeOutsideMyDock() async throws {
        let fake = Self.fixture()
        for id: UInt32 in [10, 20] {
            fake.allow(id, .volume, element: 0, value: 0.5)
            fake.allow(id, .mute, element: 0, value: 0)
        }
        let service = Self.service(fake)
        let popout = UUID()
        service.subscribe(popout, popout: true)
        #expect(fake.liveControlDevices == [10])
        fake.changeControls(of: 10, volume: 0.25, muted: true)
        try await eventually { service.controls.volume == 0.25 }
        #expect(service.controls.isMuted == true)

        fake.defaultID = 20
        service.refresh()
        #expect(fake.liveControlDevices == [20], "the listener moves to the new output")
        fake.changeControls(of: 10, volume: 0.9, muted: false)
        fake.changeControls(of: 20, volume: 0.75, muted: false)
        try await eventually { service.controls.volume == 0.75 }
        #expect(service.controls.isMuted == false)

        service.unsubscribe(popout)
        #expect(fake.liveControlDevices.isEmpty)
    }

    private func eventually(_ condition: () -> Bool) async throws {
        try await pollUntil(condition)
    }

    // MARK: Face reading

    @Test func faceReadingsAreHonestAboutState() {
        let device = AudioOutputDevice(id: 1, uid: "u", name: "MacBook Pro Speakers", transport: .builtIn)
        let volume = AudioOutputFaceReading(device: device, controls: .init(volume: 0.625, isMuted: false))
        #expect(volume.detail == "63%" && volume.shortName == "Speakers" && volume.symbol == "speaker.wave.2")
        #expect(volume.accessibilityValue == "MacBook Pro Speakers, 63%")
        let muted = AudioOutputFaceReading(device: device, controls: .init(volume: 0.5, isMuted: true))
        #expect(muted.detail == "Muted" && muted.symbol == "speaker.slash")
        let fixed = AudioOutputFaceReading(device: device, controls: .none)
        #expect(fixed.detail == "Built-in")
        let none = AudioOutputFaceReading(device: nil, controls: .none)
        #expect(none == .unavailable && none.symbol == "speaker.slash")
    }

    // MARK: Registration

    @Test func theFamilyIsRegisteredWithItsCapabilities() throws {
        let definition = try #require(WidgetRegistry.definition(named: "Audio Output"))
        #expect(definition.category == .system)
        #expect(definition.symbol == "speaker.wave.2")
        #expect(definition.capabilities.layouts.map(\.layout) == [.compact, .wide])
        #expect(definition.capabilities.defaultLayout == .compact)
        #expect(definition.capabilities.permissions.isEmpty && !definition.capabilities.needsConnection)
        #expect(!definition.capabilities.holdsPrivateContent && !definition.capabilities.hasSetupState)
        #expect(definition.capabilities.refreshDemand == .localSampling)
        #expect(WidgetRegistry.all.filter { $0.name == "Audio Output" }.count == 1)
        #expect(WidgetProviderRegistry.registeredKinds.contains("Audio Output"))
        #expect(WidgetDiscovery.matches(definition, query: "headphones"))
        #expect(WidgetDiscovery.matches(definition, query: "volume"))
    }

    @Test func oldProfilesWithoutAnyAudioFieldsStillDecode() throws {
        let item = DockItem.widget("Audio Output")
        #expect(try JSONDecoder().decode(DockItem.self, from: JSONEncoder().encode(item)) == item)
        let empty = try JSONDecoder().decode(WidgetConfiguration.self, from: Data("{}".utf8))
        #expect(WidgetPresentationCatalog.resolvedLayout(for: "Audio Output", configuration: empty) == .compact)
    }
}
