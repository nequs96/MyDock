import Foundation

/// An optional, explicitly chosen subset of a Dock's own app, folder, file and link items
/// that Start Workspace opens together. Absent by default, so existing Docks are unchanged.
///
/// Items are referenced by their Dock item identity and always resolve in the Dock's own order.
/// References to removed items are ignored rather than pruned, so undoing a removal restores them.
struct DockWorkspace: Codable, Hashable, Sendable {
    static let maximumItems = 500

    var itemIDs: [UUID]

    init(itemIDs: [UUID] = []) {
        self.itemIDs = Self.bounded(itemIDs)
    }

    private enum CodingKeys: String, CodingKey { case itemIDs }

    /// Lenient: a malformed workspace decodes as empty instead of failing the whole profile.
    init(from decoder: Decoder) throws {
        guard let values = try? decoder.container(keyedBy: CodingKeys.self) else { itemIDs = []; return }
        let raw: [String] = (try? values.decodeIfPresent([String].self, forKey: .itemIDs)) ?? []
        itemIDs = Self.bounded(raw.compactMap { UUID(uuidString: $0) })
    }

    var isEmpty: Bool { itemIDs.isEmpty }

    static func isEligible(_ item: DockItem) -> Bool {
        [.application, .folder, .file, .link].contains(item.type)
    }

    /// Maps references from `oldItems` to the item at the same position in `newItems`,
    /// for copies that assign fresh item identities. Nil when nothing survives.
    func remapped(from oldItems: [DockItem], to newItems: [DockItem]) -> DockWorkspace? {
        guard oldItems.count == newItems.count else { return nil }
        let mapping = Dictionary(zip(oldItems.map(\.id), newItems.map(\.id)), uniquingKeysWith: { first, _ in first })
        let ids = itemIDs.compactMap { mapping[$0] }
        return ids.isEmpty ? nil : DockWorkspace(itemIDs: ids)
    }

    private static func bounded(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return Array(ids.filter { seen.insert($0).inserted }.prefix(maximumItems))
    }
}

extension DockProfile {
    /// The Dock's items that may join a workspace, in Dock order.
    var workspaceCandidates: [DockItem] { items.filter(DockWorkspace.isEligible) }

    /// What Start Workspace opens, in Dock order. Empty when no workspace is configured.
    var workspaceTargets: [DockItem] {
        guard let workspace, !workspace.isEmpty else { return [] }
        let chosen = Set(workspace.itemIDs)
        return items.filter { chosen.contains($0.id) && DockWorkspace.isEligible($0) }
    }

    var hasWorkspace: Bool { !workspaceTargets.isEmpty }

    func isInWorkspace(_ itemID: UUID) -> Bool { workspace?.itemIDs.contains(itemID) == true }

    /// Adds or removes one item. Keeps references in Dock order and clears the workspace when empty.
    mutating func setWorkspaceItem(_ itemID: UUID, included: Bool) {
        var chosen = Set(workspace?.itemIDs ?? [])
        if included {
            guard items.contains(where: { $0.id == itemID && DockWorkspace.isEligible($0) }) else { return }
            chosen.insert(itemID)
        } else {
            chosen.remove(itemID)
        }
        // Known items first in Dock order, then references to items not currently present (kept for undo).
        let known = items.map(\.id).filter(chosen.contains)
        let unknown = (workspace?.itemIDs ?? []).filter { chosen.contains($0) && !known.contains($0) }
        let ids = known + unknown
        workspace = ids.isEmpty ? nil : DockWorkspace(itemIDs: ids)
    }
}
