import Carbon
import Combine
import Foundation
import OSLog

private let shortcutLogger = Logger(subsystem: Product.bundleIdentifier, category: "shortcuts")
/// "MyDK": identifies MyDock's hot keys, so the handler ignores any other hot key event it is given.
private let myDockHotKeySignature = OSType(0x4D79444B)

struct DockShortcut: Codable, Equatable, Sendable {
    static let commandMask: UInt8 = 1 << 0
    static let optionMask: UInt8 = 1 << 1
    static let controlMask: UInt8 = 1 << 2
    static let shiftMask: UInt8 = 1 << 3
    static let supportedMask: UInt8 = commandMask | optionMask | controlMask | shiftMask

    var keyCode: UInt16
    var modifierMask: UInt8
    var keyLabel: String

    var isValid: Bool {
        modifierMask & ~Self.supportedMask == 0 && modifierMask.nonzeroBitCount >= 2 && !keyLabel.isEmpty
    }

    var displayString: String {
        var result = ""
        if modifierMask & Self.controlMask != 0 { result += "⌃" }
        if modifierMask & Self.optionMask != 0 { result += "⌥" }
        if modifierMask & Self.shiftMask != 0 { result += "⇧" }
        if modifierMask & Self.commandMask != 0 { result += "⌘" }
        return result + keyLabel.uppercased()
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifierMask & Self.commandMask != 0 { result |= UInt32(cmdKey) }
        if modifierMask & Self.optionMask != 0 { result |= UInt32(optionKey) }
        if modifierMask & Self.controlMask != 0 { result |= UInt32(controlKey) }
        if modifierMask & Self.shiftMask != 0 { result |= UInt32(shiftKey) }
        return result
    }
}

enum DockShortcutStoreError: LocalizedError {
    case requiresTwoModifiers
    case duplicate

    var errorDescription: String? {
        switch self {
        case .requiresTwoModifiers: "Choose a key combination with at least two modifiers."
        case .duplicate: "That shortcut is already assigned to another Dock."
        }
    }
}

@MainActor
final class DockShortcutStore: ObservableObject {
    static let shared = DockShortcutStore()
    private static let defaultsKey = "app.mydock.global-shortcuts.v1"

    @Published private(set) var bindings: [UUID: DockShortcut]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppRuntimeEnvironment.defaults) {
        self.defaults = defaults
        bindings = Self.decodedBindings(from: defaults.data(forKey: Self.defaultsKey))
    }

    /// Each entry decodes on its own, so one unreadable shortcut drops only itself, not every Dock's shortcut.
    static func decodedBindings(from data: Data?) -> [UUID: DockShortcut] {
        guard let data, let stored = try? JSONDecoder().decode([String: LenientShortcut].self, from: data) else { return [:] }
        var result: [UUID: DockShortcut] = [:]
        for (key, entry) in stored {
            guard let profileID = UUID(uuidString: key), let shortcut = entry.shortcut else { continue }
            result[profileID] = shortcut
        }
        return result
    }

    private struct LenientShortcut: Decodable {
        let shortcut: DockShortcut?
        init(from decoder: Decoder) throws { shortcut = try? DockShortcut(from: decoder) }
    }

    func shortcut(for profileID: UUID) -> DockShortcut? { bindings[profileID] }

    func set(_ shortcut: DockShortcut, for profileID: UUID) throws {
        guard shortcut.isValid else { throw DockShortcutStoreError.requiresTwoModifiers }
        guard !bindings.contains(where: { $0.key != profileID && $0.value.keyCode == shortcut.keyCode && $0.value.modifierMask == shortcut.modifierMask }) else {
            throw DockShortcutStoreError.duplicate
        }
        var updated = bindings
        updated[profileID] = shortcut
        try persist(updated)
        bindings = updated
    }

    func remove(for profileID: UUID) {
        guard bindings[profileID] != nil else { return }
        var updated = bindings
        updated.removeValue(forKey: profileID)
        do {
            try persist(updated)
            bindings = updated
        } catch {
            shortcutLogger.error("Could not save shortcut settings: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func persist(_ values: [UUID: DockShortcut]) throws {
        let encoded = Dictionary(uniqueKeysWithValues: values.map { ($0.key.uuidString, $0.value) })
        defaults.set(try JSONEncoder().encode(encoded), forKey: Self.defaultsKey)
    }
}

@MainActor
final class GlobalShortcutController: ObservableObject {
    static let shared = GlobalShortcutController()

    @Published private(set) var statusMessages: [UUID: String] = [:]
    var onActivateProfile: ((UUID) -> Void)?

    private var eventHandler: EventHandlerRef?
    private var eventHandlerStatus: OSStatus = noErr
    private var registeredHotKeys: [EventHotKeyRef] = []
    private var profileIDsByHotKey: [UInt32: UUID] = [:]

    private init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), myDockHotKeyEventHandler, 1, &eventType, nil, &eventHandler)
        eventHandlerStatus = status
        if status != noErr { shortcutLogger.error("Could not install the global shortcut handler: OSStatus \(status)") }
    }

    func register(_ bindings: [UUID: DockShortcut]) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        for hotKey in registeredHotKeys { UnregisterEventHotKey(hotKey) }
        registeredHotKeys = []
        profileIDsByHotKey = [:]
        statusMessages = [:]
        guard eventHandlerStatus == noErr else {
            for profileID in bindings.keys { statusMessages[profileID] = "Shortcuts are unavailable. Quit and reopen MyDock to try again." }
            return
        }

        var numericID: UInt32 = 1
        for (profileID, shortcut) in bindings.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard shortcut.isValid else {
                statusMessages[profileID] = DockShortcutStoreError.requiresTwoModifiers.localizedDescription
                continue
            }
            let hotKeyID = EventHotKeyID(signature: myDockHotKeySignature, id: numericID)
            var hotKey: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                              hotKeyID, GetApplicationEventTarget(), 0, &hotKey)
            if status == noErr, let hotKey {
                registeredHotKeys.append(hotKey)
                profileIDsByHotKey[numericID] = profileID
            } else {
                shortcutLogger.error("Could not register a global shortcut: OSStatus \(status)")
                statusMessages[profileID] = "This shortcut may be in use by macOS or another app."
            }
            numericID &+= 1
        }
    }

    fileprivate func activate(hotKeyID: UInt32) {
        guard let profileID = profileIDsByHotKey[hotKeyID] else { return }
        onActivateProfile?(profileID)
    }
}

private let myDockHotKeyEventHandler: EventHandlerProcPtr = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr else { return status }
    guard hotKeyID.signature == myDockHotKeySignature else { return OSStatus(eventNotHandledErr) }
    let identifier = hotKeyID.id
    Task { @MainActor in GlobalShortcutController.shared.activate(hotKeyID: identifier) }
    return noErr
}
