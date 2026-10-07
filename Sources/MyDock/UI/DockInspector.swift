import SwiftUI

struct DockAppearanceInspector: View {
    @ObservedObject var store: ProfileStore
    let profile: DockProfile
    let close: () -> Void
    var workspace: DockWorkspaceSection? = nil
    /// Appearance is written straight to the store, so it is read from the saved profile: the draft
    /// passed in is not refreshed while it has unsaved item edits and would hold an older appearance.
    private var savedAppearance: ProfileAppearance? {
        guard let saved = store.state.profiles.first(where: { $0.id == profile.id }) else { return profile.appearance }
        return saved.appearance
    }
    private var settings: AppSettings { store.effectiveSettings(profileID: profile.id) }
    private func edit(_ change: (inout ProfileAppearance) -> Void) {
        var appearance = savedAppearance ?? ProfileAppearance(settings: settings)
        change(&appearance)
        store.setAppearance(appearance, for: profile.id, immediately: false, recordHistory: false)
    }
    private func sliderRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: DockDesign.Grouped.glyphSpacing) {
            Text(title).font(DockDesign.Grouped.titleFont).frame(width: 92, alignment: .leading)
            content().frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
        .padding(.vertical, DockDesign.Grouped.rowVerticalPadding)
        .frame(minHeight: DockDesign.Grouped.rowMinHeight)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Button("Done", action: close).buttonStyle(GalleryGlassButtonStyle()).keyboardShortcut(.cancelAction)
                    .help("Close inspector")
            }.overlay { Text("Dock").font(DockDesign.sectionTitle).allowsHitTesting(false) }
            if profile.kind == .custom {
                GroupedSection("Appearance", footer: savedAppearance == nil ? "Follows app defaults." : "This Dock has its own appearance.") {
                sliderRow("Tile size") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { settings.customDockSize }, set: { value in edit { $0.size = value } }), in: DockAppearanceBounds.size, onEditingChanged: { if !$0 { store.flush() } })
                            .accessibilityLabel("Tile size")
                            .accessibilityValue("\(Int((settings.customDockSize * 100).rounded())) percent")
                        Text("\(Int((settings.customDockSize * 100).rounded()))%")
                            .monospacedDigit().frame(width: 40, alignment: .trailing).accessibilityHidden(true)
                    }
                }
                GroupedRow("Position on this Mac") {
                    Picker("Position on this Mac", selection: Binding(get: { settings.customDockPosition }, set: { value in store.updateSettings { $0.customDockPosition = value } })) {
                        ForEach(DockPosition.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden()
                }
                GroupedRow("Finish") {
                    Picker("Finish", selection: Binding(get: { settings.customDockMaterial }, set: { value in edit { $0.material = value }; store.flush() })) {
                        ForEach(CustomDockMaterial.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden()
                }
                sliderRow("Item spacing") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { settings.customDockItemSpacing }, set: { value in edit { $0.spacing = value } }), in: DockAppearanceBounds.itemSpacing, onEditingChanged: { if !$0 { store.flush() } })
                            .accessibilityLabel("Item spacing")
                            .accessibilityValue("\(Int(settings.customDockItemSpacing.rounded())) points")
                        Text("\(Int(settings.customDockItemSpacing.rounded())) pt")
                            .monospacedDigit().frame(width: 40, alignment: .trailing).accessibilityHidden(true)
                    }
                }
                GroupedRow("Color theme") {
                    Picker("Color theme", selection: Binding(get: { settings.customDockTheme }, set: { value in edit { $0.theme = value }; store.flush() })) {
                        ForEach(CustomDockTheme.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden()
                }
                if savedAppearance != nil {
                    GroupedRow("Reset to app defaults", role: .button) { store.setAppearance(nil, for: profile.id) }
                        .help("Remove this Dock's own appearance and follow the app defaults in Settings → Appearance again")
                }
                }
            } else {
                Text("A macOS Dock holds apps and spacers. Widgets and appearance belong to Custom Docks.")
                    .font(DockDesign.caption).foregroundStyle(.secondary)
            }
            if let workspace { workspace }
        }.font(DockDesign.body)
            .padding(16)
            .background(DockDesign.card, in: RoundedRectangle(cornerRadius: DockDesign.Radius.group))
    }
}

struct DockItemInspector: View {
    /// The live item from the Dock being edited. Each edit changes one field of it, so a Replace or Locate repair
    /// made while the inspector is open is never overwritten by an older copy.
    let item: DockItem
    let update: (DockItem) -> Void
    let replace: () -> Void
    let close: () -> Void

    private func edit(_ change: (inout DockItem) -> Void) {
        var next = item
        change(&next)
        if next != item { update(next) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer()
                Button("Done", action: close).buttonStyle(GalleryGlassButtonStyle()).keyboardShortcut(.cancelAction)
            }.overlay { Text(item.displayName).font(DockDesign.sectionTitle).allowsHitTesting(false) }
            GroupedSection("Item") {
            if item.type == .folder {
                GroupedRow("Folder name") { inspectorField("Folder name", placeholder: "Original name", text: Binding(get: { item.folderCustomName ?? "" }, set: { value in edit { $0.folderCustomName = FolderCustomizationPolicy.editingName(value) } })) }
                GroupedRow("Show name in Dock", isOn: Binding(get: { item.showFolderLabel ?? false }, set: { value in edit { $0.showFolderLabel = value } }))
                GroupedRow("Icon color") {
                Picker("Icon color", selection: Binding(get: { item.folderIconColor?.rawValue ?? "" }, set: { value in edit { $0.folderIconColor = DockProfileColor(rawValue: value) } })) {
                    Text("Original icon").tag("")
                    ForEach(DockProfileColor.allCases) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden()
                }
                GroupedRow("Icon letter") { inspectorField("Icon letter", placeholder: "None", text: Binding(get: { item.folderIconLetter ?? "" }, set: { value in edit { $0.folderIconLetter = FolderCustomizationPolicy.letter(value) } })) }
                GroupedRow("Icon number") { inspectorField("Icon number", placeholder: "None", text: Binding(get: { item.folderIconNumber ?? "" }, set: { value in edit { $0.folderIconNumber = FolderCustomizationPolicy.number(value) } })) }
            } else if item.type == .spacer {
                GroupedRow("Width") {
                Picker("Width", selection: Binding(get: { item.spacerKind ?? .small }, set: { value in edit { $0.spacerKind = value } })) {
                    ForEach(SpacerKind.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
                }
            } else {
                if let path = item.url?.path { Text(path).font(DockDesign.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                Text("Select this item in the Dock to move it. Activate the Dock to open it.")
                    .foregroundStyle(.secondary).font(DockDesign.body)
            }
            if [.application, .file, .folder].contains(item.type) {
                GroupedRow(AppLauncher.isMissingTarget(item) ? "Locate…" : "Replace…", role: .button, action: replace)
            }
            }
        }.padding(24).frame(width: 420).background(DockDesign.page)
            // The name keeps its spaces while typing; it is stored trimmed once the inspector closes.
            .onDisappear { edit { $0.folderCustomName = $0.folderCustomName.flatMap(FolderCustomizationPolicy.name) } }
    }

    /// Borderless, trailing-aligned field so every value lines up at the row's trailing edge,
    /// as in the Stripe "Account name" row; the row title names it, the placeholder shows the empty value.
    private func inspectorField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain).multilineTextAlignment(.trailing)
            .frame(maxWidth: 180)
            .accessibilityLabel(label)
    }
}

/// One normalisation for folder customisation, so every editor stores the same values:
/// a trimmed name, one uppercase letter and up to three digits, each `nil` when empty.
enum FolderCustomizationPolicy {
    static func name(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// While typing: blank is `nil`, anything else is kept as typed so spaces between words survive.
    static func editingName(_ value: String) -> String? {
        name(value) == nil ? nil : value
    }

    static func letter(_ value: String) -> String? {
        let letter = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
        return letter.isEmpty ? nil : letter
    }

    static func number(_ value: String) -> String? {
        let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(3))
        return digits.isEmpty ? nil : digits
    }
}
