import SwiftUI

struct DockAppearanceInspector: View {
    @ObservedObject var store: ProfileStore
    let profile: DockProfile
    let close: () -> Void
    private var settings: AppSettings { store.effectiveSettings(for: profile) }
    private func edit(_ change: (inout ProfileAppearance) -> Void) {
        var appearance = profile.appearance ?? ProfileAppearance(settings: settings)
        change(&appearance)
        store.setAppearance(appearance, for: profile.id, immediately: false, recordHistory: false)
    }
    private func sliderRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: DockDesign.Grouped.glyphSpacing) {
            Text(title).font(DockDesign.Grouped.titleFont).frame(width: 64, alignment: .leading)
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
                    .help("Close inspector").accessibilityLabel("Close inspector")
            }.overlay { Text("Dock").font(DockDesign.sectionTitle).allowsHitTesting(false) }
            if profile.kind == .custom {
                GroupedSection("Appearance", footer: profile.appearance == nil ? "Follows app defaults." : "This Dock has its own appearance.") {
                sliderRow("Size") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { settings.customDockSize }, set: { value in edit { $0.size = value } }), in: 0.65...1.5, onEditingChanged: { if !$0 { store.flush() } })
                            .accessibilityLabel("Dock size")
                            .accessibilityValue("\(Int((settings.customDockSize * 100).rounded())) percent")
                        Text("\(Int((settings.customDockSize * 100).rounded()))%")
                            .monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                GroupedRow("Position on this Mac") {
                    Picker("Position on this Mac", selection: Binding(get: { settings.customDockPosition }, set: { value in store.updateSettings { $0.customDockPosition = value } })) {
                        ForEach(DockPosition.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden()
                }
                GroupedRow("Material") {
                    Picker("Material", selection: Binding(get: { settings.customDockMaterial }, set: { value in edit { $0.material = value }; store.flush() })) {
                        ForEach(CustomDockMaterial.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden()
                }
                sliderRow("Spacing") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { settings.customDockItemSpacing }, set: { value in edit { $0.spacing = value } }), in: DockAppearanceBounds.itemSpacing, onEditingChanged: { if !$0 { store.flush() } })
                            .accessibilityLabel("Item spacing")
                            .accessibilityValue("\(Int(settings.customDockItemSpacing.rounded())) points")
                        Text("\(Int(settings.customDockItemSpacing.rounded())) pt")
                            .monospacedDigit().frame(width: 40, alignment: .trailing).accessibilityHidden(true)
                    }
                }
                GroupedRow("Theme") {
                    Picker("Theme", selection: Binding(get: { settings.customDockTheme }, set: { value in edit { $0.theme = value }; store.flush() })) {
                        ForEach(CustomDockTheme.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden()
                }
                if profile.appearance != nil {
                    GroupedRow("Reset to Global", role: .button) { store.setAppearance(nil, for: profile.id) }
                        .help("Remove this Dock's own appearance and follow the global appearance in Settings again")
                }
                }
            } else {
                Text("This layout is applied to Apple’s Dock. Widgets and appearance belong to custom Docks.")
                    .font(DockDesign.caption).foregroundStyle(.secondary)
            }
        }.font(DockDesign.body)
            .padding(16)
            .background(DockDesign.card, in: RoundedRectangle(cornerRadius: DockDesign.Radius.group))
    }
}

struct DockItemInspector: View {
    let item: DockItem
    let update: (DockItem) -> Void
    let replace: () -> Void
    let close: () -> Void
    @State private var draft: DockItem
    init(item: DockItem, update: @escaping (DockItem) -> Void, replace: @escaping () -> Void, close: @escaping () -> Void) {
        self.item = item; self.update = update; self.replace = replace; self.close = close
        _draft = State(initialValue: item)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer()
                Button("Done", action: close).buttonStyle(GalleryGlassButtonStyle()).keyboardShortcut(.cancelAction)
            }.overlay { Text(item.displayName).font(DockDesign.sectionTitle).allowsHitTesting(false) }
            GroupedSection("Item") {
            if item.type == .folder {
                GroupedRow("Folder name") { TextField("Folder name", text: Binding(get: { draft.folderCustomName ?? "" }, set: { draft.folderCustomName = $0 })) }
                GroupedRow("Show name in Dock", isOn: Binding(get: { draft.showFolderLabel ?? false }, set: { draft.showFolderLabel = $0 }))
                GroupedRow("Icon color") {
                Picker("Icon color", selection: Binding(get: { draft.folderIconColor?.rawValue ?? "" }, set: { draft.folderIconColor = DockProfileColor(rawValue: $0) })) {
                    Text("Original icon").tag("")
                    ForEach(DockProfileColor.allCases) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden()
                }
                GroupedRow("Icon letter") { TextField("Icon letter", text: Binding(get: { draft.folderIconLetter ?? "" }, set: { draft.folderIconLetter = String($0.prefix(1)) })) }
                GroupedRow("Icon number") { TextField("Icon number", text: Binding(get: { draft.folderIconNumber ?? "" }, set: { draft.folderIconNumber = String($0.prefix(3)) })) }
            } else if item.type == .spacer {
                GroupedRow("Width") {
                Picker("Width", selection: Binding(get: { draft.spacerKind ?? .small }, set: { draft.spacerKind = $0 })) {
                    ForEach(SpacerKind.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
                }
            } else {
                if let path = item.url?.path { Text(path).font(DockDesign.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                Text("Select this item in the Dock to move it. Activate the Dock to open it.")
                    .foregroundStyle(.secondary).font(DockDesign.body)
            }
            if [.application, .file, .folder].contains(item.type) {
                GroupedRow(AppLauncher.isMissingTarget(item) ? "Locate Missing Item…" : "Replace…", role: .button, action: replace)
            }
            }
        }.padding(24).frame(width: 420).background(DockDesign.page)
            .onChange(of: draft) { update($0) }
    }
}
