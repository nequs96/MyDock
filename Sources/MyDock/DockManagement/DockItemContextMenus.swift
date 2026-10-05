import AppKit
import SwiftUI

/// The running-process scan is deferred to this view's body, which SwiftUI evaluates when the
/// context menu opens rather than during every tile body pass. The captured identity is the
/// one observed at that moment and is revalidated again by each action.
///
/// Order follows the macOS Dock: open windows, Show in Finder, then Hide, Quit and Force Quit.
/// Windows are listed inline only when Accessibility is trusted and the bounded discovery
/// answered in time; otherwise "Windows…" keeps the explicit chooser.
struct RunningApplicationMenuSection: View {
    let item: DockItem
    var body: some View {
        if let identity = AppLauncher.runningIdentity(for: item) {
            let name = item.displayName
            let windows = inlineWindows(for: identity)
            if windows.isEmpty {
                Button("Windows…") { WindowAccessibilityService.showWindowMenu(for: identity, action: .activate) }
            } else {
                ForEach(windows) { window in
                    Button {
                        WindowAccessibilityService.activate(window)
                    } label: {
                        if window.isMinimized { Label(window.title, systemImage: "minus.rectangle") }
                        else { Text(window.title) }
                    }
                    .accessibilityLabel(window.isMinimized ? "\(window.title), minimized" : window.title)
                }
            }
            Button("Close Window…") { WindowAccessibilityService.showWindowMenu(for: identity, action: .close) }
            Divider()
            Button("Show in Finder") { AppLauncher.showInFinder(identity) }
                .accessibilityLabel("Show \(name) in Finder")
            Divider()
            Button(RunningApplicationMenuPolicy.hideTitle(isHidden: AppLauncher.isHidden(identity))) {
                AppLauncher.toggleHidden(identity)
            }
            .accessibilityLabel("\(RunningApplicationMenuPolicy.hideTitle(isHidden: AppLauncher.isHidden(identity))) \(name)")
            Button("Quit") { AppLauncher.quit(identity) }
                .accessibilityLabel("Quit \(name)")
            Button("Force Quit…") { AppLauncher.forceQuit(identity) }
                .accessibilityLabel("Force Quit \(name)")
        }
    }

    /// Never prompts for access and never waits longer than the short menu bound.
    private func inlineWindows(for identity: NativeApplicationIdentity) -> [DockWindowDescriptor] {
        guard WindowAccessibilityService.isTrusted(),
              case .available(let windows) = WindowAccessibilityService.discoverWindows(
                for: identity, timeLimit: RunningApplicationMenuPolicy.discoveryTimeLimit) else { return [] }
        return RunningApplicationMenuPolicy.inlineWindows(windows)
    }
}
