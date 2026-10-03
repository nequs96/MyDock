import AppKit
import SwiftUI

/// The running-process scan is deferred to this view's body, which SwiftUI evaluates when the
/// context menu opens rather than during every tile body pass. The captured identity is the
/// one observed at that moment and is revalidated again by each action.
struct RunningApplicationMenuSection: View {
    let item: DockItem
    var body: some View {
        if let identity = AppLauncher.runningIdentity(for: item) {
            Button("Windows…") { WindowAccessibilityService.showWindowMenu(for: identity, action: .activate) }
            Button("Close Window…") { WindowAccessibilityService.showWindowMenu(for: identity, action: .close) }
            Divider()
            Button("Quit \(item.displayName)") { AppLauncher.quit(identity) }
        }
    }
}
