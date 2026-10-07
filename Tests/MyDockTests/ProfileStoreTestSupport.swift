import Foundation
@testable import MyDock

/// Shorthands that only tests use. The app creates, finishes onboarding and reorders through the persisted paths
/// these call (`createProfileAndPersist`, `updateSettings`, `replaceItems`).
extension ProfileStore {
    @discardableResult
    func createProfile(kind: DockProfileKind, name: String? = nil) -> UUID? {
        try? createProfileAndPersist(kind: kind, name: name)
    }

    func completeOnboarding() {
        updateSettings(immediately: true) {
            $0.onboardingComplete = true
            $0.lastSeenWhatsNewVersion = Product.marketingVersion
        }
    }

    func moveItems(_ itemIDs: Set<UUID>, direction: DockItemMoveDirection, in profileID: UUID) {
        guard let items = state.profiles.first(where: { $0.id == profileID })?.items else { return }
        let moved = DockItemOrderingPolicy.moving(items, ids: itemIDs, direction: direction)
        guard moved.map(\.id) != items.map(\.id) else { return }
        replaceItems(moved, in: profileID)
    }
}
