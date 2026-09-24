import AppIntents
import Foundation

struct FocusDockProfileEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Dock Profile")
    static let defaultQuery = FocusDockProfileQuery()

    var id: String
    var name: String
    var profileKind: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: profileKind == DockProfileKind.native.rawValue ? "macOS Dock" : "Custom Dock")
    }

    @MainActor
    static func currentProfiles() -> [FocusDockProfileEntity] {
        ProfileStore.shared.state.profiles.map {
            FocusDockProfileEntity(id: $0.id.uuidString, name: $0.name, profileKind: $0.kind.rawValue)
        }
    }
}

struct FocusDockProfileQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FocusDockProfileEntity] {
        let requested = Set(identifiers)
        return await MainActor.run {
            FocusDockProfileEntity.currentProfiles().filter { requested.contains($0.id) }
        }
    }

    func suggestedEntities() async throws -> [FocusDockProfileEntity] {
        await MainActor.run { FocusDockProfileEntity.currentProfiles() }
    }
}

struct MyDockFocusFilterIntent: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Choose Dock Profile"
    static let description = IntentDescription("Apply a saved MyDock profile when this Focus turns on. Turning the Focus off leaves the last selected Dock in place.")
    static let openAppWhenRun = false

    @Parameter(title: "Dock Profile")
    var profile: FocusDockProfileEntity?

    var appContext: FocusFilterAppContext { FocusFilterAppContext() }
    var displayRepresentation: DisplayRepresentation {
        let subtitleText = profile?.name ?? "No profile change when Focus turns off"
        return DisplayRepresentation(title: "Apply Dock Profile",
                                     subtitle: "\(subtitleText)")
    }

    func perform() async throws -> some IntentResult {
        // Focus Filter receives default parameters when a Focus turns off. Keeping nil
        // as a no-op preserves the last profile, matching MyDock's documented behavior.
        guard let id = FocusDockSelectionPolicy.profileIDToApply(profile?.id) else { return .result() }
        try await FocusDockProfileActivator.activate(id)
        return .result()
    }
}

enum FocusDockSelectionPolicy {
    static func profileIDToApply(_ identifier: String?) -> UUID? {
        identifier.flatMap(UUID.init(uuidString:))
    }
}

@MainActor
enum FocusDockProfileActivator {
    static func activate(_ profileID: UUID) async throws {
        let store = ProfileStore.shared
        guard let profile = store.state.profiles.first(where: { $0.id == profileID }) else {
            throw FocusDockProfileError.profileUnavailable
        }
        if profile.kind == .native {
            try await NativeDockController.shared.apply(profile)
        }
        store.activate(profileID)
    }
}

enum FocusDockProfileError: LocalizedError {
    case profileUnavailable

    var errorDescription: String? { "The selected MyDock profile was removed. Choose an existing Dock profile in this Focus filter." }
}
