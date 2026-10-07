import Foundation

enum DockAppearanceBounds {
    static let itemSpacing: ClosedRange<Double> = 0...30
    static let cornerRadius: ClosedRange<Double> = 0...50
    static let tintStrength: ClosedRange<Double> = 0...0.5
    static let floatingInset: ClosedRange<Double> = 0...24
    static let autoTintStrength: Double = 0.06

    /// A stored value outside its range is pulled back into it; a missing or non-finite one takes the default.
    static func clamped(_ value: Double?, default fallback: Double, to range: ClosedRange<Double>) -> Double {
        guard let value, value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// A profile either inherits global appearance or stores its own appearance snapshot.
struct ProfileAppearance: Codable, Hashable {
    var material: CustomDockMaterial
    var theme: CustomDockTheme
    var size: Double
    var spacing: Double
    var cornerRadius: Double
    var tintStrength: Double
    var widgetStyle: CustomDockWidgetStyle
    var showWidgetLabels: Bool
    // Optional for appearance snapshots saved by older builds.
    var glassOpacity: Double?
    var edgeStyle: DockEdgeStyle?
    var widgetSurface: DockWidgetSurface?
    var floatingInset: Double?
    var tintMode: DockTintMode?

    private enum CodingKeys: String, CodingKey {
        case material, theme, size, spacing, cornerRadius, tintStrength, widgetStyle, showWidgetLabels, glassOpacity
        case edgeStyle, widgetSurface, floatingInset, tintMode
    }

    init(settings: AppSettings) {
        material = settings.customDockMaterial
        theme = settings.customDockTheme
        size = settings.customDockSize
        spacing = settings.customDockItemSpacing
        cornerRadius = settings.customDockCornerRadius
        tintStrength = settings.customDockTintStrength
        widgetStyle = settings.customDockWidgetStyle
        showWidgetLabels = settings.showWidgetLabels
        glassOpacity = settings.customDockGlassOpacity
        edgeStyle = settings.customDockEdgeStyle
        widgetSurface = settings.customDockWidgetSurface
        floatingInset = settings.customDockFloatingInset
        tintMode = settings.customDockTintMode
    }

    /// Like `AppSettings`, choices this build does not know fall back to the defaults and numbers are pulled into
    /// their ranges, so one Dock's appearance never makes the saved data unreadable.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        material = values.lenient(CustomDockMaterial.self, forKey: .material) ?? defaults.customDockMaterial
        theme = values.lenient(CustomDockTheme.self, forKey: .theme) ?? defaults.customDockTheme
        size = DockAppearanceBounds.clamped(values.lenient(Double.self, forKey: .size), default: defaults.customDockSize, to: 0.65...1.5)
        spacing = DockAppearanceBounds.clamped(values.lenient(Double.self, forKey: .spacing),
                                               default: defaults.customDockItemSpacing, to: DockAppearanceBounds.itemSpacing)
        cornerRadius = DockAppearanceBounds.clamped(values.lenient(Double.self, forKey: .cornerRadius),
                                                    default: defaults.customDockCornerRadius, to: DockAppearanceBounds.cornerRadius)
        tintStrength = DockAppearanceBounds.clamped(values.lenient(Double.self, forKey: .tintStrength),
                                                    default: defaults.customDockTintStrength, to: DockAppearanceBounds.tintStrength)
        widgetStyle = values.lenient(CustomDockWidgetStyle.self, forKey: .widgetStyle) ?? defaults.customDockWidgetStyle
        showWidgetLabels = values.lenient(Bool.self, forKey: .showWidgetLabels) ?? defaults.showWidgetLabels
        glassOpacity = values.lenient(Double.self, forKey: .glassOpacity).map { DockAppearanceBounds.clamped($0, default: 0, to: 0...1) }
        // Unknown future choices inherit the same defaults as absent older fields.
        edgeStyle = values.lenient(DockEdgeStyle.self, forKey: .edgeStyle)
        widgetSurface = values.lenient(DockWidgetSurface.self, forKey: .widgetSurface)
        floatingInset = values.lenient(Double.self, forKey: .floatingInset)
            .map { DockAppearanceBounds.clamped($0, default: 0, to: DockAppearanceBounds.floatingInset) }
        tintMode = values.lenient(DockTintMode.self, forKey: .tintMode)
    }

    func applying(to global: AppSettings) -> AppSettings {
        var result = global
        result.customDockMaterial = material
        result.customDockTheme = theme
        result.customDockSize = size
        result.customDockItemSpacing = spacing
        result.customDockCornerRadius = cornerRadius
        result.customDockTintStrength = tintStrength
        result.customDockWidgetStyle = widgetStyle
        result.showWidgetLabels = showWidgetLabels
        result.customDockGlassOpacity = glassOpacity ?? 0
        result.customDockEdgeStyle = edgeStyle ?? .hairline
        result.customDockWidgetSurface = widgetSurface ?? .tile
        result.customDockFloatingInset = floatingInset ?? 0
        result.customDockTintMode = tintMode ?? .custom
        return result
    }

    func validate() throws {
        let opacity = glassOpacity ?? 0
        let inset = floatingInset ?? 0
        guard size.isFinite, (0.65...1.5).contains(size), spacing.isFinite, DockAppearanceBounds.itemSpacing.contains(spacing),
              cornerRadius.isFinite, DockAppearanceBounds.cornerRadius.contains(cornerRadius),
              tintStrength.isFinite, DockAppearanceBounds.tintStrength.contains(tintStrength),
              opacity.isFinite, (0...1).contains(opacity),
              inset.isFinite, DockAppearanceBounds.floatingInset.contains(inset) else {
            throw ProfileValidationError.invalid("appearance values are outside supported limits")
        }
    }
}

extension ProfileStore {
    func effectiveSettings(for profile: DockProfile) -> AppSettings {
        var settings = profile.appearance?.applying(to: state.settings) ?? state.settings
        if let preview = dockResizePreview, preview.profileID == profile.id { settings.customDockSize = preview.size }
        return settings
    }

    func effectiveSettings(profileID: UUID) -> AppSettings {
        state.profiles.first(where: { $0.id == profileID }).map { effectiveSettings(for: $0) } ?? state.settings
    }

}
