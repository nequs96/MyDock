import Foundation

/// UI scope policy: nil means app defaults; a missing Dock is never a global edit.
@MainActor
enum SettingsAppearanceEditing {
    struct Undo {
        let profileID: UUID?
        let appearance: ProfileAppearance?
        let settings: AppSettings
        let color: DockProfileColor?

        @MainActor func restore(in store: ProfileStore) {
            if let profileID {
                guard store.customProfiles.contains(where: { $0.id == profileID }) else { return }
                store.setAppearance(appearance, for: profileID)
                if let color { store.setProfileColor(profileID, to: color) }
            } else {
                store.updateSettings { $0 = ProfileAppearance(settings: settings).applying(to: $0) }
            }
        }
    }

    static func capture(in store: ProfileStore, profileID: UUID?) -> Undo? {
        let profile = profileID.flatMap { id in store.customProfiles.first { $0.id == id } }
        guard profileID == nil || profile != nil else { return nil }
        return Undo(profileID: profileID, appearance: profile?.appearance, settings: store.state.settings,
                    color: profile.flatMap { DockProfileColor(rawValue: $0.color) })
    }

    @discardableResult
    static func update(in store: ProfileStore, profileID: UUID?, immediately: Bool = false,
                       recordHistory: Bool = true, change: (inout AppSettings) -> Void) -> Bool {
        guard profileID == nil || store.customProfiles.contains(where: { $0.id == profileID }) else { return false }
        var settings = profileID.map { store.effectiveSettings(profileID: $0) } ?? store.state.settings
        change(&settings)
        if let profileID {
            store.setAppearance(ProfileAppearance(settings: settings), for: profileID,
                                immediately: immediately, recordHistory: recordHistory)
        } else {
            store.updateSettings(immediately: immediately) { $0 = ProfileAppearance(settings: settings).applying(to: $0) }
        }
        return true
    }
}
