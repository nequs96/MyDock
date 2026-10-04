import SwiftUI

/// Redesign presentation values shared between the Dock surface (RD-04) and widget chrome/faces (RD-05+).
/// The Dock injects Dock-level values; `WidgetCompactView` injects per-widget values resolved from
/// `WidgetConfiguration` and the effective `AppSettings`. Faces only read them.
private struct DockWidgetSurfaceKey: EnvironmentKey { static let defaultValue: DockWidgetSurface = .tile }
private struct DockModuleRadiusKey: EnvironmentKey { static let defaultValue: CGFloat = DockDesign.Module.defaultRadius }
private struct WidgetAccentKey: EnvironmentKey { static let defaultValue: WidgetAccent = .auto }
private struct WidgetShowsLabelKey: EnvironmentKey { static let defaultValue = true }
private struct WidgetGlassTintKey: EnvironmentKey { static let defaultValue: WidgetGlassTint = .none }

extension EnvironmentValues {
    /// How widget modules sit on the Dock. Defaults to today's tile.
    var dockWidgetSurface: DockWidgetSurface {
        get { self[DockWidgetSurfaceKey.self] } set { self[DockWidgetSurfaceKey.self] = newValue }
    }
    /// Concentric module corner radius (Dock radius − Dock padding), injected by the Dock.
    var dockModuleRadius: CGFloat {
        get { self[DockModuleRadiusKey.self] } set { self[DockModuleRadiusKey.self] = newValue }
    }
    /// Per-widget accent choice; `.auto` uses the family's semantic accent.
    var widgetAccent: WidgetAccent {
        get { self[WidgetAccentKey.self] } set { self[WidgetAccentKey.self] = newValue }
    }
    /// Resolved label visibility: the widget's `showsLabel`, else the Dock's `showWidgetLabels`.
    var widgetShowsLabel: Bool {
        get { self[WidgetShowsLabelKey.self] } set { self[WidgetShowsLabelKey.self] = newValue }
    }
    /// Glass tint for glass modules.
    var widgetGlassTint: WidgetGlassTint {
        get { self[WidgetGlassTintKey.self] } set { self[WidgetGlassTintKey.self] = newValue }
    }
}
