import Foundation

struct RunningApplicationDescriptor: Equatable, Identifiable {
    var bundleIdentifier: String
    var name: String
    var bundleURL: URL
    var isRegularApplication: Bool
    var isTerminated: Bool

    var id: String { bundleIdentifier }
}

enum RunningApplicationFilter {
    static func visible(_ applications: [RunningApplicationDescriptor], excluding pinnedBundleIdentifiers: Set<String>) -> [RunningApplicationDescriptor] {
        var seen = pinnedBundleIdentifiers
        return applications
            .filter { $0.isRegularApplication && !$0.isTerminated && seen.insert($0.bundleIdentifier).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
