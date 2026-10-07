#if DEBUG
import Foundation

/// A state the visual QA export must render for a widget family.
enum WidgetQAState: Hashable, CustomStringConvertible {
    case layout(WidgetLayout)
    case setup

    var description: String {
        switch self {
        case .layout(let layout): "layout \(layout.rawValue)"
        case .setup: "setup/empty state"
        }
    }

    var isLayout: Bool {
        if case .layout = self { return true }
        return false
    }
}

/// Required QA states derive from `WidgetCapabilities`: every advertised layout, plus a setup/empty-state
/// fixture for each family with `hasSetupState`. The export records what it actually rendered and a missing
/// state fails validation, so a new family or layout cannot silently skip QA.
struct WidgetQAMatrix {
    struct Failure: LocalizedError {
        var missing: [String]
        var errorDescription: String? { "Widget visual QA is missing: " + missing.joined(separator: "; ") }
    }

    private(set) var rendered: [String: Set<WidgetQAState>] = [:]

    mutating func record(_ family: String, _ state: WidgetQAState) {
        rendered[family, default: []].insert(state)
    }

    static func required(for definition: WidgetDefinition) -> Set<WidgetQAState> {
        var states = Set(definition.capabilities.layouts.map { WidgetQAState.layout($0.layout) })
        if definition.capabilities.hasSetupState { states.insert(.setup) }
        return states
    }

    /// `states` narrows the check to the states one export owns (for example only layouts).
    func missing(in registry: [WidgetDefinition] = WidgetRegistry.all,
                 states include: (WidgetQAState) -> Bool = { _ in true }) -> [String] {
        registry.flatMap { definition in
            Self.required(for: definition).filter(include)
                .subtracting(rendered[definition.name] ?? [])
                .map { "\(definition.name) \($0)" }
        }.sorted()
    }

    func validate(registry: [WidgetDefinition] = WidgetRegistry.all) throws {
        let gaps = missing(in: registry)
        if !gaps.isEmpty { throw Failure(missing: gaps) }
    }
}
#endif
