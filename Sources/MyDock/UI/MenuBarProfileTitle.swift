import Foundation

enum MenuBarProfileTitle {
    static func title(in state: PersistentState) -> String? {
        let names = activeNames(in: state)
        switch state.settings.setupMode {
        case .nativeOnly:
            return names.native.map { shortened($0, to: 28) }
        case .customMain:
            return names.custom.map { shortened($0, to: 28) }
                ?? names.native.map { shortened($0, to: 28) }
        case .both:
            if let native = names.native, let custom = names.custom {
                return "\(shortened(native, to: 16)) · \(shortened(custom, to: 16))"
            }
            return (names.native ?? names.custom).map { shortened($0, to: 28) }
        }
    }

    static func toolTip(in state: PersistentState) -> String {
        let names = activeNames(in: state)
        switch state.settings.setupMode {
        case .nativeOnly:
            return names.native.map { "\(Product.name) — macOS Dock: \($0)" } ?? Product.name
        case .customMain:
            return names.custom.map { "\(Product.name) — Custom Dock: \($0)" }
                ?? names.native.map { "\(Product.name) — macOS Dock: \($0)" }
                ?? Product.name
        case .both:
            if let native = names.native, let custom = names.custom {
                return "\(Product.name) — macOS Dock: \(native); Custom Dock: \(custom)"
            }
            if let native = names.native { return "\(Product.name) — macOS Dock: \(native)" }
            if let custom = names.custom { return "\(Product.name) — Custom Dock: \(custom)" }
            return Product.name
        }
    }

    private static func activeNames(in state: PersistentState) -> (native: String?, custom: String?) {
        func name(for id: UUID?, kind: DockProfileKind) -> String? {
            guard let id, let profile = state.profiles.first(where: { $0.id == id && $0.kind == kind }) else { return nil }
            let cleaned = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? kind.title : cleaned
        }
        return (name(for: state.settings.activeNativeProfileID, kind: .native),
                name(for: state.settings.activeCustomProfileID, kind: .custom))
    }

    private static func shortened(_ name: String, to limit: Int) -> String {
        guard name.count > limit else { return name }
        return String(name.prefix(limit - 1)) + "…"
    }
}
