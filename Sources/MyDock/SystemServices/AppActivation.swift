import AppKit

/// Brings another application forward. macOS 14 uses cooperative activation, in which
/// `.activateIgnoringOtherApps` has no effect, so MyDock first yields its own activation to the app.
@MainActor
enum AppActivation {
    @discardableResult
    static func activate(_ app: NSRunningApplication) -> Bool {
        if #available(macOS 14.0, *) {
            NSApplication.shared.yieldActivation(to: app)
            return app.activate(options: [])
        }
        return app.activate(options: [.activateIgnoringOtherApps])
    }

    /// Brings MyDock forward after the person asked for one of its windows or alerts.
    static func activateSelf() {
        if #available(macOS 14.0, *) {
            NSApplication.shared.activate()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
