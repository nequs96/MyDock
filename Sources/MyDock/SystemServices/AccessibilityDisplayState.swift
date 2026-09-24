import AppKit
import Combine

@MainActor
final class AccessibilityDisplayState: ObservableObject {
    static let shared = AccessibilityDisplayState()

    @Published private(set) var reduceTransparency = false
    @Published private(set) var increaseContrast = false
    @Published private(set) var reduceMotion = false

    private var observation: AnyCancellable?

    private init() {
        refresh()
        observation = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
    }

    func refresh() {
        let workspace = NSWorkspace.shared
        reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast
        reduceMotion = workspace.accessibilityDisplayShouldReduceMotion
    }
}
