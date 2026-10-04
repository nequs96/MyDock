import Foundation

enum ProfileDraftMergeError: LocalizedError {
    case profileRemoved
    case conflict(String)

    var errorDescription: String? {
        switch self {
        case .profileRemoved: "This profile was removed while you were editing it. Your draft has been kept."
        case .conflict(let field): "Both the saved profile and your draft changed \(field). Your draft has been kept. Review the latest profile before saving."
        }
    }
}

extension DockProfileDraft {
    /// Apply only the user's edits to the current profile. Runtime widget updates remain intact.
    func merged(with latest: DockProfile) throws -> DockProfile {
        let latest = latest.strippedOfRuntimeReadings
        guard latest.id == original.id, latest.kind == original.kind else {
            throw ProfileDraftMergeError.profileRemoved
        }
        guard [original, profile, latest].allSatisfy({ Set($0.items.map(\.id)).count == $0.items.count }) else {
            throw ProfileValidationError.invalid("duplicate item identities in an edit session")
        }
        var result = latest
        result.name = try Self.mergeValue(original.name, profile.name, latest.name, field: "the profile name")
        result.color = try Self.mergeValue(original.color, profile.color, latest.color, field: "the profile color")
        result.appearance = try Self.mergeValue(original.appearance, profile.appearance, latest.appearance, field: "profile appearance")
        let base = Dictionary(uniqueKeysWithValues: original.items.map { ($0.id, $0) })
        let edited = Dictionary(uniqueKeysWithValues: profile.items.map { ($0.id, $0) })
        let current = Dictionary(uniqueKeysWithValues: latest.items.map { ($0.id, $0) })
        var items = current
        for item in original.items {
            switch (edited[item.id], current[item.id]) {
            case (nil, let live?):
                guard live == item else { throw ProfileDraftMergeError.conflict("the removed item “\(item.title)”") }
                items.removeValue(forKey: item.id)
            case (let draft?, nil):
                guard draft == item else { throw ProfileDraftMergeError.conflict("the deleted item “\(item.title)”") }
            case (let draft?, let live?):
                items[item.id] = try JSONDraftMerge.merge(base: item, edited: draft, latest: live,
                                                        field: "“\(item.title)”")
            case (nil, nil): break
            }
        }
        for item in profile.items where base[item.id] == nil {
            if let live = current[item.id], live != item {
                throw ProfileDraftMergeError.conflict("the new item “\(item.title)”")
            }
            items[item.id] = item
        }
        let common = Set(base.keys).intersection(edited.keys).intersection(current.keys)
        let baseOrder = original.items.map(\.id).filter(common.contains)
        let draftOrder = profile.items.map(\.id).filter(common.contains)
        let liveOrder = latest.items.map(\.id).filter(common.contains)
        if draftOrder != baseOrder, liveOrder != baseOrder, draftOrder != liveOrder {
            throw ProfileDraftMergeError.conflict("the item order")
        }
        // Keep the latest order unless the editor explicitly reordered. Insert concurrent additions
        // beside their nearest preceding surviving neighbor instead of dropping or appending them all.
        var order = (draftOrder != baseOrder ? profile.items : latest.items).map(\.id).filter { items[$0] != nil }
        let secondary = (draftOrder != baseOrder ? latest.items : profile.items).map(\.id)
        for (index, id) in secondary.enumerated() where items[id] != nil && !order.contains(id) {
            if let previous = secondary[..<index].reversed().first(where: order.contains),
               let position = order.firstIndex(of: previous) {
                order.insert(id, at: position + 1)
            } else { order.insert(id, at: 0) }
        }
        result.items = order.compactMap { items[$0] }
        return result
    }

    private static func mergeValue<T: Equatable>(_ base: T, _ edited: T, _ latest: T, field: String) throws -> T {
        if edited == base { return latest }
        if latest == base || latest == edited { return edited }
        throw ProfileDraftMergeError.conflict(field)
    }
}

private enum JSONDraftMerge {
    static func merge<T: Codable>(base: T, edited: T, latest: T, field: String) throws -> T {
        let encoder = JSONEncoder()
        let objects = try [base, edited, latest].map { try JSONSerialization.jsonObject(with: encoder.encode($0)) }
        let merged = try mergeObject(base: objects[0], edited: objects[1], latest: objects[2], path: field)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: merged ?? NSNull()))
    }

    private static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        if lhs == nil && rhs == nil { return true }
        guard let left = lhs as? NSObject, let right = rhs as? NSObject else { return false }
        return left.isEqual(right)
    }

    private static func mergeObject(base: Any?, edited: Any?, latest: Any?, path: String) throws -> Any? {
        if equal(edited, base) { return latest }
        if equal(latest, base) || equal(edited, latest) { return edited }
        if let base = base as? [String: Any], let edited = edited as? [String: Any], let latest = latest as? [String: Any] {
            var result: [String: Any] = [:]
            for key in Set(base.keys).union(edited.keys).union(latest.keys) {
                result[key] = try mergeObject(base: base[key], edited: edited[key], latest: latest[key], path: path + " · " + key)
            }
            return result
        }
        throw ProfileDraftMergeError.conflict(path)
    }
}
