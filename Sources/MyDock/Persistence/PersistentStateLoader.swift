import Foundation

/// Reads `state.json` one Dock at a time. A Dock that no longer decodes or validates is set aside on its own while
/// every other Dock and the settings load; before this, one bad value anywhere set the whole file aside and MyDock
/// started with no Docks. Settings decode leniently field by field (see `KeyedDecodingContainer.lenient`).
enum PersistentStateLoader {
    struct Loaded {
        var state: PersistentState
        /// Names of the Docks that could not be read, in file order.
        var setAside: [String]
        /// The settings were present but could not be read at all, so the defaults are in use.
        var settingsReset: Bool
        var isPartial: Bool { !setAside.isEmpty || settingsReset }
    }

    static func load(_ data: Data) throws -> Loaded {
        let file = try JSONDecoder().decode(File.self, from: data)
        var profiles: [DockProfile] = []
        var setAside: [String] = []
        var profileIDs = Set<UUID>()
        var itemIDs = Set<UUID>()
        for entry in file.profiles {
            switch entry {
            case .unreadable(let name):
                setAside.append(name ?? "An unnamed Dock")
            case .decoded(let profile):
                let ids = profile.items.map(\.id)
                guard profiles.count < ProfileSemanticValidator.maximumProfiles, !profileIDs.contains(profile.id),
                      itemIDs.count + ids.count <= ProfileSemanticValidator.maximumItems, itemIDs.isDisjoint(with: ids),
                      (try? ProfileSemanticValidator.validate([profile])) != nil else {
                    setAside.append(profile.name)
                    continue
                }
                profiles.append(profile)
                profileIDs.insert(profile.id)
                itemIDs.formUnion(ids)
            }
        }
        var state = PersistentState()
        state.profiles = profiles
        state.settings = file.settings ?? AppSettings()
        try ProfileSemanticValidator.validate(state.profiles)
        try ProfileAppearance(settings: state.settings).validate()
        return Loaded(state: state, setAside: setAside, settingsReset: file.settingsUnreadable)
    }

    static func warning(for loaded: Loaded, preservedAt path: String) -> String {
        var parts: [String] = []
        if !loaded.setAside.isEmpty {
            let names = loaded.setAside.map { "\u{201C}\($0)\u{201D}" }
            let shown = names.count > 3 ? Array(names.prefix(3)) + ["\(names.count - 3) more"] : names
            let list = shown.count > 1 ? shown.dropLast().joined(separator: ", ") + " and " + shown[shown.count - 1] : shown[0]
            parts.append("\(list) could not be opened and \(names.count == 1 ? "was" : "were") set aside. Your other Docks are unchanged.")
        }
        if loaded.settingsReset { parts.append("Settings could not be read and were reset.") }
        parts.append("The original file was preserved at \(path).")
        return parts.joined(separator: " ")
    }

    private struct File: Decodable {
        var profiles: [Entry]
        var settings: AppSettings?
        var settingsUnreadable: Bool

        private enum CodingKeys: String, CodingKey { case profiles, settings }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            profiles = try values.decodeIfPresent([Entry].self, forKey: .profiles) ?? []
            settings = values.lenient(AppSettings.self, forKey: .settings)
            settingsUnreadable = settings == nil && values.contains(.settings)
        }
    }

    /// One Dock: decoded, or set aside with the name it had, when the name can still be read.
    private enum Entry: Decodable {
        case decoded(DockProfile)
        case unreadable(name: String?)

        private enum NameKey: String, CodingKey { case name }

        init(from decoder: Decoder) throws {
            do {
                self = .decoded(try DockProfile(from: decoder))
            } catch {
                self = .unreadable(name: try? decoder.container(keyedBy: NameKey.self).decode(String.self, forKey: .name))
            }
        }
    }
}
