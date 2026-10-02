import Foundation

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

    init(settings: AppSettings) {
        material = settings.customDockMaterial
        theme = settings.customDockTheme
        size = settings.customDockSize
        spacing = settings.customDockItemSpacing
        cornerRadius = settings.customDockCornerRadius
        tintStrength = settings.customDockTintStrength
        widgetStyle = settings.customDockWidgetStyle
        showWidgetLabels = settings.showWidgetLabels
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
        return result
    }

    func validate() throws {
        guard size.isFinite, (0.65...1.5).contains(size), spacing.isFinite, (0...30).contains(spacing),
              cornerRadius.isFinite, (0...50).contains(cornerRadius),
              tintStrength.isFinite, (0...0.5).contains(tintStrength) else {
            throw ProfileValidationError.invalid("appearance values are outside supported limits")
        }
    }
}

extension ProfileStore {
    func effectiveSettings(for profile: DockProfile) -> AppSettings {
        profile.appearance?.applying(to: state.settings) ?? state.settings
    }

    func effectiveSettings(profileID: UUID) -> AppSettings {
        state.profiles.first(where: { $0.id == profileID }).map { effectiveSettings(for: $0) } ?? state.settings
    }

}
