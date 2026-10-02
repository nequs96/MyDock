import Foundation

/// A remembered profile ID is not proof that its Dock is currently enabled.
/// Native layouts retain their applied association even while replacement mode
/// hides Apple's Dock, so presentation distinguishes that from a running Dock.
enum DockProfileStatus: Equatable {
    case inactive
    case active
    case applied(hidden: Bool)

    init(profile: DockProfile, settings: AppSettings) {
        switch profile.kind {
        case .custom:
            self = settings.setupMode != .nativeOnly && settings.activeCustomProfileID == profile.id ? .active : .inactive
        case .native:
            self = settings.activeNativeProfileID == profile.id ? .applied(hidden: settings.setupMode == .customMain) : .inactive
        }
    }

    static func preferredWorkspaceProfileID(profiles: [DockProfile], settings: AppSettings) -> UUID? {
        if settings.setupMode != .nativeOnly,
           let id = settings.activeCustomProfileID,
           profiles.contains(where: { $0.id == id && $0.kind == .custom }) { return id }
        if settings.setupMode != .customMain,
           let id = settings.activeNativeProfileID,
           profiles.contains(where: { $0.id == id && $0.kind == .native }) { return id }
        let preferredKind: DockProfileKind = settings.setupMode == .nativeOnly ? .native : .custom
        return profiles.first(where: { $0.kind == preferredKind })?.id ?? profiles.first?.id
    }

    var isCurrent: Bool { self != .inactive }
    var showsActiveIndicator: Bool { self == .active || self == .applied(hidden: false) }
    var label: String {
        switch self {
        case .active: "Active"
        case .applied: "Applied"
        case .inactive: "Inactive"
        }
    }
}
