import SwiftUI

/// Definitions are shared by the UI and scope/undo tests. Styles change only their authored fields.
enum DockQuickStyle: String, CaseIterable, Identifiable {
    case clear, glass, frosted, solid, midnight
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var material: CustomDockMaterial {
        switch self {
        case .clear: .liquidGlassClear
        case .glass: .liquidGlass
        case .frosted: .frosted
        case .solid: .solid
        case .midnight: .dark
        }
    }
    var edge: DockEdgeStyle { self == .clear ? .none : .hairline }
    var surface: DockWidgetSurface {
        switch self { case .clear: .plain; case .glass, .midnight: .glass; case .frosted, .solid: .tile }
    }
    var tint: Double {
        switch self { case .clear: 0; case .glass: 0.04; case .frosted: 0.02; case .solid: 0.03; case .midnight: 0.10 }
    }
    func apply(to settings: inout AppSettings) {
        settings.customDockMaterial = material
        settings.customDockEdgeStyle = edge
        settings.customDockWidgetSurface = surface
        settings.customDockTintMode = .custom
        settings.customDockTintStrength = tint
        settings.customDockGlassOpacity = 0
    }
    func matches(_ settings: AppSettings) -> Bool {
        settings.customDockMaterial == material && settings.customDockEdgeStyle == edge
            && settings.customDockWidgetSurface == surface && settings.customDockTintMode == .custom
            && abs(settings.customDockTintStrength - tint) < 0.000001
            && abs(settings.customDockGlassOpacity) < 0.000001
    }
    var look: DockSwatchLook {
        let finish: DockSwatchLook.Surface = switch self {
        case .clear: .clearGlass; case .glass: .glass; case .frosted: .frosted; case .solid: .solid; case .midnight: .midnight
        }
        let module: DockSwatchLook.ModuleSurface = switch surface { case .glass: .glass; case .plain: .plain; case .tile: .tile }
        return DockSwatchLook(surface: finish, showsEdge: edge != .none, moduleSurface: module)
    }
}

enum SettingsAppearanceDefaults {
    static let finishes = CustomDockMaterial.allCases
    static func restore(to settings: inout AppSettings) {
        settings = ProfileAppearance(settings: AppSettings()).applying(to: settings)
    }
}

extension SettingsView {
    var appearancePage: some View {
        DockScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(page: .appearance)
                appearanceHero
                appearanceStyleSection
                appearanceGlassSection
                appearanceLayoutSection
                appearanceWidgetsSection
                appearanceScopeSection
            }
            .padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var appearanceHero: some View {
        var profile = appearanceProfileID.flatMap { id in store.customProfiles.first { $0.id == id } }
            ?? DockProfile(name: "Preview", kind: .custom, items: [.widget("Clock"), .widget("Weather"), .widget("Sticky Note")])
        profile.appearance = ProfileAppearance(settings: appearanceSettings)
        return ZStack {
            SwatchWallpaper()
            DockLayoutPreview(store: store, profile: profile, maximumSideLength: 180, usesLiveData: false)
                .padding(20)
        }
        .frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityLabel("Dock appearance preview, sample data").id("Preview")
    }

    var appearanceStyleSection: some View {
        GroupedSection("Style", footer: "A style is a preset for finish, edge, widget surface and tint. Fine-tune each in Glass below.") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 122), spacing: 8)], spacing: 12) {
                    ForEach(DockQuickStyle.allCases) { style in
                        StyleSwatch(style.title, look: style.look, isSelected: style.matches(appearanceSettings)) {
                            updateAppearance { style.apply(to: &$0) }
                        }
                        .id("Style " + style.title)
                    }
                }
                if !DockQuickStyle.allCases.contains(where: { $0.matches(appearanceSettings) }) {
                    Text("Custom: fine-tuned below").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(12)
            // Swatches show the Dock's own theme, the same source the hero preview uses.
            .environment(\.dockSwatchTheme, appearanceSettings.customDockTheme)
        }.id("Style").help("Previews use sample data.")
    }

    var appearanceGlassSection: some View {
        GroupedSection("Glass", footer: (supportsLiquidGlass ? "Auto tint follows the Dock color." : "Liquid Glass uses frosted material before macOS 26.") + " These controls adjust the selected style.") {
            SettingsControlRow(title: "Finish") {
                Picker("Appearance", selection: appearanceBinding(\.customDockMaterial)) {
                    ForEach(SettingsAppearanceDefaults.finishes) { Text($0.title).tag($0) }
                }
            }.id("Finish")
            SettingsControlRow(title: "Edge") {
                Picker("Edge", selection: appearanceBinding(\.customDockEdgeStyle)) {
                    Text("None").tag(DockEdgeStyle.none)
                    Text("Hairline").tag(DockEdgeStyle.hairline)
                    Text("Contrast only").tag(DockEdgeStyle.contrastOnly)
                }
            }.id("Edge")
            GroupedRow("Auto tint", isOn: Binding(get: { appearanceSettings.customDockTintMode == .auto }, set: { enabled in
                updateAppearance { $0.customDockTintMode = enabled ? .auto : .custom }
            })).id("Auto tint")
            appearanceSlider("Tint strength", keyPath: \.customDockTintStrength, range: 0...0.5, step: 0.01, percent: true)
                .disabled(appearanceSettings.customDockTintMode == .auto).id("Tint strength")
            appearanceSlider("Glass opacity", keyPath: \.customDockGlassOpacity, range: 0...1, step: nil, percent: true)
                .id("Glass opacity")
            SettingsControlRow(title: "Color theme") {
                Picker("Color theme", selection: appearanceBinding(\.customDockTheme)) {
                    ForEach(CustomDockTheme.allCases) { Text($0.title).tag($0) }
                }
            }
            if let profile = appearanceProfileID.flatMap({ id in store.customProfiles.first { $0.id == id } }) {
                SettingsControlRow(title: "Dock color") {
                    Picker("Dock color", selection: Binding(get: { DockProfileColor(rawValue: profile.color) ?? .blue }, set: { rememberAppearance(); store.setProfileColor(profile.id, to: $0) })) {
                        ForEach(DockProfileColor.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
        }.id("Glass")
    }

    var appearanceLayoutSection: some View {
        GroupedSection("Layout") {
            SettingsControlRow(title: "Density") {
                Picker("Density", selection: Binding(get: { selectedDensity }, set: { preset in
                    guard let preset else { return }
                    updateAppearance { $0.customDockSize = preset.size; $0.customDockItemSpacing = preset.spacing }
                })) {
                    if selectedDensity == nil { Text("Custom").tag(Optional<DockDensityPreset>.none) }
                    ForEach(DockDensityPreset.allCases) { Text($0.title).tag(Optional($0)) }
                }
            }
            appearanceSlider("Tile size", keyPath: \.customDockSize, range: DockAppearanceBounds.size, step: nil, percent: true)
            appearanceSlider("Item spacing", keyPath: \.customDockItemSpacing, range: DockAppearanceBounds.itemSpacing)
            appearanceSlider("Corner roundness", keyPath: \.customDockCornerRadius, range: DockAppearanceBounds.cornerRadius)
            appearanceSlider("Floating inset", keyPath: \.customDockFloatingInset, range: DockAppearanceBounds.floatingInset)
                .id("Floating inset")
        }.id("Layout")
    }

    var appearanceWidgetsSection: some View {
        GroupedSection("Widgets", footer: "Widgets can override these defaults.") {
            SettingsControlRow(title: "Default widget surface") {
                Picker("Default widget surface", selection: appearanceBinding(\.customDockWidgetSurface)) {
                    Text("Glass").tag(DockWidgetSurface.glass)
                    Text("Plain").tag(DockWidgetSurface.plain)
                    Text("Tile").tag(DockWidgetSurface.tile)
                }
            }.id("Default widget surface")
            GroupedRow("Show widget labels", isOn: appearanceBinding(\.showWidgetLabels))
            SettingsControlRow(title: "Widget defaults") {
                Picker("Widget defaults", selection: appearanceBinding(\.customDockWidgetStyle)) {
                    ForEach(CustomDockWidgetStyle.allCases) { Text($0.title).tag($0) }
                }
            }
        }.id("Widgets").help("Each widget can override its layout and icon; side Docks use a narrow layout.")
    }

    var appearanceScopeSection: some View {
        GroupedSection("Scope", footer: appearanceProfileID != nil ? "Edits apply to this Dock." : "Defaults apply to Docks with inherited appearance.") {
            SettingsControlRow(title: "Editing") {
                Picker("Editing", selection: Binding(get: { appearanceProfileID != nil }, set: { thisDock in
                    appearanceProfileID = thisDock ? store.activeCustomProfile?.id ?? store.customProfiles.first?.id : nil
                    appearanceScopeMessage = nil
                })) {
                    Text("This Dock").tag(true).disabled(store.customProfiles.isEmpty)
                    Text("App defaults").tag(false)
                }.pickerStyle(.segmented).frame(width: 240)
            }
            if appearanceProfileID != nil {
                SettingsControlRow(title: "Dock") {
                    Picker("Dock to edit", selection: $appearanceProfileID) {
                        ForEach(store.customProfiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            } else if store.customProfiles.isEmpty {
                GroupedRow("Create a custom Dock to edit its appearance.")
            }
            if let appearanceScopeMessage { GroupedRow(appearanceScopeMessage) }
            if let id = appearanceProfileID {
                GroupedRow("Use app defaults", isOn: Binding(get: {
                    store.customProfiles.first(where: { $0.id == id })?.appearance == nil
                }, set: { inherit in
                    rememberAppearance()
                    store.setAppearance(inherit ? nil : ProfileAppearance(settings: appearanceSettings), for: id)
                }))
                GroupedRow("Reset to app defaults", role: .button) {
                    guard store.customProfiles.contains(where: { $0.id == id }) else { return }
                    rememberAppearance(); store.setAppearance(nil, for: id)
                }
            } else {
                GroupedRow("Reset app appearance defaults", role: .button) {
                    updateAppearance { SettingsAppearanceDefaults.restore(to: &$0) }
                }
            }
            if appearanceProfileID != nil {
                // App defaults already offer "Reset app appearance defaults", which does the same.
                GroupedRow("Restore appearance defaults", role: .button) {
                    updateAppearance { SettingsAppearanceDefaults.restore(to: &$0) }
                }
            }
            if previousAppearance?.isAvailable(for: appearanceProfileID) == true {
                GroupedRow("Undo last appearance change", role: .button) { undoAppearance() }
            }
        }.id("Scope")
    }

    private func appearanceBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { appearanceSettings[keyPath: keyPath] }, set: { value in updateAppearance { $0[keyPath: keyPath] = value } })
    }

    private func appearanceSlider(_ title: String, keyPath: WritableKeyPath<AppSettings, Double>, range: ClosedRange<Double>, step: Double? = 1, percent: Bool = false) -> some View {
        let value = appearanceSettings[keyPath: keyPath]
        return GroupedRow(title) {
            HStack(spacing: 10) {
                Slider(value: Binding(get: { appearanceSettings[keyPath: keyPath] }, set: { value in
                    let adjusted = step.map { (value / $0).rounded() * $0 } ?? value
                    updateAppearance { $0[keyPath: keyPath] = min(range.upperBound, max(range.lowerBound, adjusted)) }
                }), in: range, onEditingChanged: appearanceSliderEditingChanged)
                    .accessibilityLabel(title).frame(minWidth: 80, maxWidth: 180)
                Text(percent ? "\(Int((value * 100).rounded()))%" : "\(Int(value.rounded())) pt")
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
            }
        }
    }

    private var appearanceSettings: AppSettings {
        appearanceProfileID.map { store.effectiveSettings(profileID: $0) } ?? store.state.settings
    }

    private func rememberAppearance() {
        previousAppearance = SettingsAppearanceEditing.capture(in: store, profileID: appearanceProfileID)
    }

    private func updateAppearance(immediately: Bool = false, _ change: (inout AppSettings) -> Void) {
        if !editingAppearanceContinuously { rememberAppearance() }
        SettingsAppearanceEditing.update(in: store, profileID: appearanceProfileID, immediately: immediately,
                                         recordHistory: !editingAppearanceContinuously, change: change)
    }

    private func appearanceSliderEditingChanged(_ editing: Bool) {
        if editing {
            rememberAppearance()
            if let id = appearanceProfileID, let profile = store.customProfiles.first(where: { $0.id == id }) {
                store.history.record(profile, reason: "Before appearance edit")
            }
        } else { store.flush() }
        editingAppearanceContinuously = editing
    }

    private func undoAppearance() {
        previousAppearance?.restore(in: store, editingProfileID: appearanceProfileID)
        previousAppearance = nil
    }

    private var selectedDensity: DockDensityPreset? {
        DockDensityPreset.allCases.first {
            abs(appearanceSettings.customDockSize - $0.size) < 0.001
                && abs(appearanceSettings.customDockItemSpacing - $0.spacing) < 0.001
        }
    }
    private var supportsLiquidGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}
