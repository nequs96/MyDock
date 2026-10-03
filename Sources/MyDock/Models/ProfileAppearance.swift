import Foundation

enum DockAppearanceBounds {
    static let itemSpacing: ClosedRange<Double> = 0...30
    static let cornerRadius: ClosedRange<Double> = 0...50
    static let tintStrength: ClosedRange<Double> = 0...0.5
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
        return result
    }

    func validate() throws {
        let opacity = glassOpacity ?? 0
        guard size.isFinite, (0.65...1.5).contains(size), spacing.isFinite, DockAppearanceBounds.itemSpacing.contains(spacing),
              cornerRadius.isFinite, DockAppearanceBounds.cornerRadius.contains(cornerRadius),
              tintStrength.isFinite, DockAppearanceBounds.tintStrength.contains(tintStrength),
              opacity.isFinite, (0...1).contains(opacity) else {
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
