import AppKit
import CoreGraphics
import CoreLocation
import EventKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

extension SettingsView {
    var appearancePage: some View {
    DockScrollView {
        VStack(alignment: .leading, spacing: 20) {
        SettingsPageHeader(page: selectedPage)
        DockSettingSection(title: "Appearance scope") {
            SettingsControlRow(title: "Editing") {
                Picker("Editing", selection: Binding(
                    get: { appearanceProfileID != nil },
                    set: { thisDock in
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
            } else {
                Text(store.customProfiles.isEmpty ? "Create a custom Dock to edit its appearance. You can edit app defaults now." : "Defaults apply to Docks that use inherited appearance. Saved Dock overrides and Dock colors stay as they are.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let appearanceScopeMessage { Text(appearanceScopeMessage).font(.caption).foregroundStyle(.secondary) }
            if let id = appearanceProfileID {
                Toggle("Use app defaults", isOn: Binding(
                    get: { store.customProfiles.first(where: { $0.id == id })?.appearance == nil },
                    set: { inherit in
                        rememberAppearance()
                        store.setAppearance(inherit ? nil : ProfileAppearance(settings: appearanceSettings), for: id)
                    }))
                Text("This Dock can inherit app defaults or keep its full saved appearance. Editing a control creates a full Dock override.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if appearanceProfileID != nil {
                Button("Reset to app defaults") {
                    guard let id = appearanceProfileID, store.customProfiles.contains(where: { $0.id == id }) else { return }
                    rememberAppearance(); store.setAppearance(nil, for: id)
                }
            } else {
                Button("Reset app appearance defaults") {
                    updateAppearance { $0 = ProfileAppearance(settings: AppSettings()).applying(to: $0) }
                }
            }
            if previousAppearance?.isAvailable(for: appearanceProfileID) == true {
                Button("Undo last appearance change") { undoAppearance() }
            }
        }
        DockSettingSection(title: "Preview") {
            appearancePreview
            Text("Widgets in this preview use sample data.").font(.caption).foregroundStyle(.secondary)
        }
        DockSettingSection(title: "Quick styles") {
            Text("Choose a finish. Your Dock updates as you make changes.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                appearancePreset("Minimal", material: .solid, tint: 0.03)
                appearancePreset("Soft frost", material: .frosted, tint: 0.06)
                appearancePreset("Clear glass", material: .liquidGlassClear, tint: 0)
                appearancePreset("Frosted glass", material: .liquidGlass, tint: 0.02)
                appearancePreset("Midnight", material: .dark, tint: 0.10)
            }
            if let profile = appearanceProfileID.flatMap({ id in store.customProfiles.first { $0.id == id } }) {
                SettingsControlRow(title: "Dock color") {
                    Picker("Dock color", selection: Binding(get: { DockProfileColor(rawValue: profile.color) ?? .blue }, set: { rememberAppearance(); store.setProfileColor(profile.id, to: $0) })) {
                        ForEach(DockProfileColor.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
        }
        DockSettingSection(title: "Fine-tune appearance") {
            SettingsControlRow(title: "Color theme") {
                Picker("Color theme", selection: Binding(get: { appearanceSettings.customDockTheme }, set: { value in
                    updateAppearance { $0.customDockTheme = value }
                })) {
                    ForEach(CustomDockTheme.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).frame(width: 220)
            }
            SettingsControlRow(title: "Appearance") {
                Picker("Appearance", selection: Binding(get: { appearanceSettings.customDockMaterial }, set: { value in
                    updateAppearance { $0.customDockMaterial = value }
                })) {
                    ForEach(CustomDockMaterial.allCases) { material in Text(material.title).tag(material) }
                }
            }
            SettingsControlRow(title: "Widget defaults") {
                Picker("Widget defaults", selection: Binding(get: { appearanceSettings.customDockWidgetStyle }, set: { value in
                    updateAppearance { $0.customDockWidgetStyle = value }
                })) {
                    ForEach(CustomDockWidgetStyle.allCases) { style in Text(style.title).tag(style) }
                }
            }
            if [.liquidGlass, .liquidGlassClear].contains(appearanceSettings.customDockMaterial) {
                SettingsControlRow(title: "Glass finish") {
                    Picker("Glass finish", selection: Binding(get: { appearanceSettings.customDockMaterial }, set: { value in
                        updateAppearance { $0.customDockMaterial = value }
                    })) {
                        Text("Clear").tag(CustomDockMaterial.liquidGlassClear)
                        Text("Frosted").tag(CustomDockMaterial.liquidGlass)
                    }.pickerStyle(.segmented).frame(width: 220)
                }
                HStack {
                    Text("Glass opacity")
                    Spacer()
                    Text("\(Int((appearanceSettings.customDockGlassOpacity * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { appearanceSettings.customDockGlassOpacity }, set: { value in
                    updateAppearance { $0.customDockGlassOpacity = value }
                }), in: 0...1).accessibilityLabel("Glass opacity")
                HStack { Text("Clear"); Spacer(); Text("Opaque") }.font(.caption).foregroundStyle(.secondary)
                Text("Keep more wallpaper visible, or give icons a quieter background. Tint strength adjusts the color separately.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Configure each widget’s layout and icon separately. Side Docks use a narrow presentation.")
                .font(.caption).foregroundStyle(.secondary)
            if [.liquidGlass, .liquidGlassClear].contains(appearanceSettings.customDockMaterial) && !supportsLiquidGlass {
                Text("Liquid Glass uses the standard frosted material on macOS versions before 26.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            visualStyleControls
        }
        }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
    }
    }

    private var appearancePreview: some View {
        var profile = appearanceProfileID.flatMap { id in store.customProfiles.first { $0.id == id } }
            ?? DockProfile(name: "Preview", kind: .custom, items: [.widget("Clock"), .widget("Weather"), .widget("Sticky Note")])
        profile.appearance = ProfileAppearance(settings: appearanceSettings)
        return DockLayoutPreview(store: store, profile: profile, maximumSideLength: 180, usesLiveData: false)
            .accessibilityLabel("Dock appearance preview, sample data")
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

    private func appearancePreset(_ title: String, material: CustomDockMaterial, tint: Double) -> some View {
        let previewColor = SettingsAppearanceEditing.previewColor(profiles: store.customProfiles, profileID: appearanceProfileID)
        let backdrop: [Color] = previewColor == nil
            ? [Color(white: 0.38), Color(white: 0.62)]
            : [Color(red: 0.35, green: 0.48, blue: 0.66), Color(red: 0.66, green: 0.52, blue: 0.40)]
        var previewSettings = appearanceSettings
        previewSettings.customDockMaterial = material
        previewSettings.customDockTintStrength = tint
        previewSettings.customDockGlassOpacity = material == .liquidGlass ? 0.15 : 0
        previewSettings.customDockCornerRadius = 9
        return Button {
            updateAppearance {
                $0.customDockMaterial = material
                $0.customDockTintStrength = tint
                $0.customDockGlassOpacity = material == .liquidGlass ? 0.15 : 0
                $0.customDockCornerRadius = 22
            }
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    // A visible backdrop makes the material's clarity legible.
                    LinearGradient(colors: backdrop, startPoint: .topLeading, endPoint: .bottomTrailing)
                    DockMaterialSurface(settings: previewSettings, color: previewColor?.displayColor ?? .gray).padding(3)
                    HStack(spacing: 5) {
                        ForEach(["folder.fill", "clock.fill", "calendar"], id: \.self) { symbol in
                            Image(systemName: symbol).font(.system(size: 13))
                                .foregroundStyle(material == .dark ? Color.white.opacity(0.9) : Color.primary.opacity(0.8))
                                .frame(width: 20, height: 24)
                        }
                    }
                }.frame(height: 43).clipShape(RoundedRectangle(cornerRadius: 9))
                Text(title).font(.system(size: 10, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.85)
            }.padding(7).frame(maxWidth: .infinity)
                .background(appearanceSettings.customDockMaterial == material ? DockDesign.accent.opacity(0.06) : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(appearanceSettings.customDockMaterial == material ? DockDesign.accent : DockDesign.Outline.color(accessibility.contrast),
                            lineWidth: appearanceSettings.customDockMaterial == material ? 1.5 : DockDesign.Outline.controlWidth(accessibility.contrast)))
        }
        .buttonStyle(.plain).accessibilityLabel(title)
        .accessibilityAddTraits(appearanceSettings.customDockMaterial == material ? .isSelected : [])
    }

    private var visualStyleControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                Text("Density")
                Spacer()
                Text(selectedDensity?.title ?? "Custom").foregroundStyle(.secondary)
            }
            Picker("Density", selection: Binding(get: { selectedDensity }, set: { preset in
                guard let preset else { return }
                updateAppearance { $0.customDockSize = preset.size; $0.customDockItemSpacing = preset.spacing }
            })) {
                if selectedDensity == nil { Text("Custom").tag(Optional<DockDensityPreset>.none) }
                ForEach(DockDensityPreset.allCases) { preset in Text(preset.title).tag(Optional(preset)) }
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Text("Tile size")
                Spacer()
                Text("\(Int((appearanceSettings.customDockSize * 100).rounded()))%").foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { appearanceSettings.customDockSize }, set: { value in
                updateAppearance(immediately: false) { $0.customDockSize = value }
            }), in: 0.65...1.5, onEditingChanged: appearanceSliderEditingChanged)
            HStack {
                Text("Item spacing")
                Spacer()
                Text("\(Int(appearanceSettings.customDockItemSpacing)) pt").foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { appearanceSettings.customDockItemSpacing }, set: { value in
                updateAppearance(immediately: false) { $0.customDockItemSpacing = value }
            }), in: DockAppearanceBounds.itemSpacing, step: 1, onEditingChanged: appearanceSliderEditingChanged)
            DisclosureGroup("Advanced appearance", isExpanded: $advancedAppearanceExpanded) {
                VStack(spacing: 12) {
                    HStack {
                        Text("Corner roundness")
                        Spacer()
                        Text("\(Int(appearanceSettings.customDockCornerRadius)) pt").foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { appearanceSettings.customDockCornerRadius }, set: { value in
                        updateAppearance(immediately: false) { $0.customDockCornerRadius = value }
                    }), in: DockAppearanceBounds.cornerRadius, step: 1, onEditingChanged: appearanceSliderEditingChanged)
                    HStack {
                        Text("Profile tint")
                        Spacer()
                        Text("\(Int((appearanceSettings.customDockTintStrength * 100).rounded()))%").foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { appearanceSettings.customDockTintStrength }, set: { value in
                        updateAppearance(immediately: false) { $0.customDockTintStrength = value }
                    }), in: DockAppearanceBounds.tintStrength, step: 0.01, onEditingChanged: appearanceSliderEditingChanged)
                }.padding(.top, 12)
            }
            Button("Restore appearance defaults") {
                updateAppearance {
                    $0.customDockSize = 1
                    $0.customDockItemSpacing = 8
                    $0.customDockCornerRadius = 24
                    $0.customDockTintStrength = 0.08
                    $0.customDockWidgetStyle = .cards
                    $0.showWidgetLabels = true
                    $0.customDockMaterial = .frosted
                }
            }
            .font(.caption)
        }
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
