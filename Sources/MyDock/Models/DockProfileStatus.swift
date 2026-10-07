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

    /// The workspace edits one profile at a time; that is independent of what is on screen.
    /// Select = edit here, Activate = show a custom Dock, Apply = write a layout to Apple's Dock.
    static func actionTitle(for kind: DockProfileKind) -> String { kind == .native ? "Apply" : "Activate" }

    static func actionHelp(for kind: DockProfileKind) -> String {
        kind == .native
            ? "Apply to the macOS Dock now. It stays until you apply another Dock, including after you quit MyDock."
            : "Show this Custom Dock on screen."
    }

    /// One quiet sentence under the profile name: what is being edited versus what is live.
    func workspaceCaption(for kind: DockProfileKind, setupMode: SetupMode) -> String {
        switch (kind, self) {
        case (.custom, .active): "You're editing the Custom Dock on screen."
        case (.custom, _):
            setupMode == .nativeOnly
                ? "Editing only. Activate to show it; MyDock will also turn on the Custom Dock."
                : "Editing only. Activate to show it on screen."
        case (.native, .applied(let hidden)):
            hidden ? "Last applied to the macOS Dock, which is hidden while MyDock replaces it."
                   : "Last applied to the macOS Dock."
        case (.native, _): "Editing a saved macOS Dock. Apply changes the macOS Dock now and stays after you quit."
        }
    }

    /// What each setup mode does to Apple's Dock.
    static func nativeConsequence(for mode: SetupMode) -> String {
        switch mode {
        case .nativeOnly: "The macOS Dock stays as it is. It changes only when you apply a saved Dock, and that stays after you quit."
        case .both: "The macOS Dock stays visible. It changes only when you apply a saved Dock; your Custom Dock appears separately."
        case .customMain: "The macOS Dock is hidden while MyDock runs, and its settings are restored when you change modes or quit."
        }
    }
}
