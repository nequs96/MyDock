import Foundation

enum DockAppearanceBounds {
    static let itemSpacing: ClosedRange<Double> = 0...30
    static let cornerRadius: ClosedRange<Double> = 0...50
    static let tintStrength: ClosedRange<Double> = 0...0.5
    static let floatingInset: ClosedRange<Double> = 0...24
    static let autoTintStrength: Double = 0.06
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

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        material = try values.decode(CustomDockMaterial.self, forKey: .material)
        theme = try values.decode(CustomDockTheme.self, forKey: .theme)
        size = try values.decode(Double.self, forKey: .size)
        spacing = try values.decode(Double.self, forKey: .spacing)
        cornerRadius = try values.decode(Double.self, forKey: .cornerRadius)
        tintStrength = try values.decode(Double.self, forKey: .tintStrength)
        widgetStyle = try values.decode(CustomDockWidgetStyle.self, forKey: .widgetStyle)
        showWidgetLabels = try values.decode(Bool.self, forKey: .showWidgetLabels)
        glassOpacity = try values.decodeIfPresent(Double.self, forKey: .glassOpacity)
        // Unknown future choices inherit the same defaults as absent older fields.
        edgeStyle = try? values.decodeIfPresent(DockEdgeStyle.self, forKey: .edgeStyle)
        widgetSurface = try? values.decodeIfPresent(DockWidgetSurface.self, forKey: .widgetSurface)
        floatingInset = try values.decodeIfPresent(Double.self, forKey: .floatingInset)
        tintMode = try? values.decodeIfPresent(DockTintMode.self, forKey: .tintMode)
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
