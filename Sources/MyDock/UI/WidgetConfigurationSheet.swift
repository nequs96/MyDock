import SwiftUI

/// The iOS-style "Edit Widget" sheet: a live preview of this widget on a sample Dock with a size
/// pager, then grouped Content, Appearance and Data sections and a Remove Widget row. Short
/// editors fit their content; longer ones scroll under a fixed header with a Done pill.
struct WidgetConfigurationSheet: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject private var runtimeCache: WidgetRuntimeCache
    var item: DockItem
    var profileID: UUID
    var maximumHeight: CGFloat = 640
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var contentHeight: CGFloat = 360
    @State private var editorDemand = RefreshDemandHolder(kind: .editor)
    @State private var confirmingRemoval = false
    @State private var removalError: String?

    init(store: ProfileStore, item: DockItem, profileID: UUID, maximumHeight: CGFloat = 640) {
        self.store = store; self.item = item; self.profileID = profileID; self.maximumHeight = maximumHeight
        _runtimeCache = ObservedObject(wrappedValue: store.runtimeCache)
    }
    private var currentItem: DockItem {
        store.presentationItem(store.state.profiles.first { $0.id == profileID }?.items.first { $0.id == item.id } ?? item)
    }
    private var kind: String { currentItem.widgetKind ?? currentItem.title }
    private var data: WidgetSheetDataSummary {
        WidgetSheetDataSummary.make(kind: kind, configuration: currentItem.widgetConfiguration ?? WidgetConfiguration())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            DockScrollView {
                sections
                    .padding(.horizontal, WidgetSheetMetrics.inset)
                    .padding(.top, 4)
                    .padding(.bottom, WidgetSheetMetrics.inset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: WidgetConfigurationHeightKey.self, value: geometry.size.height)
                    })
            }
            .frame(height: min(contentHeight, max(200, maximumHeight - WidgetSheetMetrics.headerHeight)))
            .onPreferenceChange(WidgetConfigurationHeightKey.self) { height in
                if height > 0 { contentHeight = height }
            }
        }
        .frame(width: WidgetSheetMetrics.width)
        .background(DockDesign.page)
        .buttonStyle(DockButtonStyle())
        .textFieldStyle(DockTextFieldStyle())
        .onExitCommand { dismiss() }
        // Live previews keep refreshing while the Dock is hidden; the token is released when the editor goes away.
        .onAppear { editorDemand.begin() }
        .onDisappear { editorDemand.end() }
        .confirmationDialog("Remove this widget?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove Widget", role: .destructive, action: removeWidget)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(currentItem.displayName) and its settings are removed from this Dock.")
        }
    }

    private var header: some View {
        ZStack {
            Text(currentItem.displayName)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 84)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(GalleryGlassButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .help("Close widget settings")
                    .accessibilityLabel("Done")
                    .accessibilityHint("Closes widget settings")
            }
        }
        .padding(.horizontal, WidgetSheetMetrics.inset)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(height: WidgetSheetMetrics.headerHeight)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: WidgetSheetMetrics.sectionSpacing) {
            WidgetLayoutPreviewPager(store: store, item: currentItem, profileID: profileID)
            // Content: the family's own setup, exactly as its in-Dock popout draws it, without the
            // hero the live preview above already shows.
            if WidgetSheetHeroPolicy.showsContent(kind: kind, inSheet: true) {
                WidgetPopout(store: store, item: currentItem, profileID: profileID, showsCustomize: false, showsHeader: false, showsData: false)
                    .environment(\.widgetPopoutShowsHero, WidgetSheetHeroPolicy.showsHero(kind: kind, inSheet: true))
            }
            WidgetAppearanceControls(store: store, item: currentItem, profileID: profileID)
            if !data.isEmpty { dataSection }
            GroupedSection(footer: removalError) {
                if WidgetSheetRemoval.hasPendingRemoval(itemID: item.id) {
                    // The removal is applied but not saved: retry the save, no second confirmation.
                    GroupedRow("Retry Remove Widget", role: .destructive, action: removeWidget)
                } else {
                    GroupedRow("Remove Widget", role: .destructive) { confirmingRemoval = true }
                }
            }
        }
    }

    private var dataSection: some View {
        GroupedSection("Data", separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
            if let source = data.source {
                GroupedRow("Source", value: source)
            }
            if data.showsFreshness {
                WidgetFreshnessView(coordinator: store.widgetData, item: currentItem) {
                    Task { await store.widgetData.refresh(item: currentItem, profileID: profileID) }
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
                .padding(.vertical, DockDesign.Grouped.rowVerticalPadding + 2)
                .frame(maxWidth: .infinity, minHeight: DockDesign.Grouped.rowMinHeight, alignment: .leading)
            }
            if let note = data.accessNote {
                GroupedRow("Access", subtitle: note)
            }
        }
    }

    private func removeWidget() {
        do {
            try WidgetSheetRemoval.remove(itemID: item.id, profileID: profileID, store: store, undoManager: undoManager)
            removalError = nil
            dismiss()
        } catch {
            removalError = error.localizedDescription
        }
    }
}

enum WidgetSheetMetrics {
    static let width: CGFloat = 504
    static let inset: CGFloat = 20
    static let headerHeight: CGFloat = 60
    static let sectionSpacing: CGFloat = 22
    static let previewRadius: CGFloat = 22
    static let previewHorizontalPadding: CGFloat = 10
    /// Chevron (26) plus its spacing (8) on each side of the pager track.
    static let pagerChrome: CGFloat = 2 * (26 + 8)

    /// The largest preview scale that keeps the widest layout's Dock strip inside the pager track.
    static func previewScale(widestWidth: Double, dockPadding: CGFloat, available: CGFloat) -> CGFloat {
        let strip = CGFloat(widestWidth) + 2 * dockPadding
        guard strip > 0, available.isFinite, available > 0 else { return 1 }
        return min(1.8, max(1, available / strip))
    }
}

/// What the sheet's Data section shows for one family, from its capabilities and configuration only.
/// The section is omitted when every part is empty.
struct WidgetSheetDataSummary: Equatable {
    var source: String?
    var showsFreshness: Bool
    var accessNote: String?
    var isEmpty: Bool { source == nil && !showsFreshness && accessNote == nil }

    static func make(kind: String, configuration: WidgetConfiguration) -> WidgetSheetDataSummary {
        let capabilities = WidgetRegistry.definition(named: kind)?.capabilities
        // AI Activity reports its own provenance inside its content.
        let freshness = kind != "AI Activity" && WidgetDataQuery.make(kind: kind, configuration: configuration) != nil
        return WidgetSheetDataSummary(source: capabilities.flatMap(source), showsFreshness: freshness,
                                      accessNote: capabilities?.accessNote)
    }

    /// A short, truthful description of where the family's content comes from.
    static func source(for capabilities: WidgetCapabilities) -> String? {
        switch capabilities.refreshDemand {
        case .none: return nil
        case .timeTick: return "This Mac's clock"
        case .localSampling: return "This Mac"
        case .remoteFetch: return capabilities.needsConnection ? "Connected account" : "Online"
        case .externalSource:
            if capabilities.permissions.contains(.calendars) { return "Calendar" }
            if capabilities.permissions.contains(.reminders) { return "Reminders" }
            return "Apps on this Mac"
        }
    }
}

/// Removal from the sheet uses the Dock editor's own path: the profile's edit session is loaded,
/// the item is removed from the draft, and the draft is saved (`ProfileStore.replaceProfile`, which
/// also cancels the item's notifications and setup drafts). The change is undoable like an editor edit.
///
/// A failed save never leaves a half-done removal behind:
/// - If the store was not changed (a merge or validation failure), the draft is rolled back to what it was.
/// - If the store applied the removal but could not write it to disk, the removal stays pending
///   (the item is already gone from the live Dock); calling `remove` again retries the save.
/// Undo is registered only once the removal is saved.
@MainActor
enum WidgetSheetRemoval {
    private struct Pending {
        var profileID: UUID
        var before: DockProfile
        var after: DockProfile
    }
    /// Removals whose save failed after the store applied them, by item.
    private static var pending: [UUID: Pending] = [:]

    static func hasPendingRemoval(itemID: UUID) -> Bool { pending[itemID] != nil }

    @discardableResult
    static func remove(itemID: UUID, profileID: UUID, store: ProfileStore, undoManager: UndoManager? = nil) throws -> Bool {
        let edits = store.editSessions
        if let retry = pending[itemID], retry.profileID == profileID {
            return try retrySave(itemID: itemID, retry, store: store, undoManager: undoManager)
        }
        guard let profile = store.state.profiles.first(where: { $0.id == profileID }) else { return false }
        edits.load(profile) // keeps a dirty draft, refreshes a clean one
        guard let original = edits.drafts[profileID], original.profile.items.contains(where: { $0.id == itemID }) else { return false }
        var draft = original
        let before = draft.profile
        draft.update { $0.items.removeAll { $0.id == itemID } }
        let after = draft.profile
        edits.set(draft, for: profileID)
        do {
            try edits.save(profileID)
        } catch {
            if storeContains(itemID, profileID: profileID, store: store) {
                edits.set(original, for: profileID)
            } else {
                pending[itemID] = Pending(profileID: profileID, before: before, after: after)
            }
            throw error
        }
        registerUndo(before, replacing: after, edits: edits, undoManager: undoManager)
        return true
    }

    private static func retrySave(itemID: UUID, _ retry: Pending, store: ProfileStore, undoManager: UndoManager?) throws -> Bool {
        let edits = store.editSessions
        guard store.state.profiles.contains(where: { $0.id == retry.profileID }) else {
            pending[itemID] = nil
            return false
        }
        if edits.drafts[retry.profileID]?.isDirty == true {
            try edits.save(retry.profileID)
        } else if store.hasUnpersistedChanges {
            // The draft was saved or discarded elsewhere; only the store's write is still owed.
            store.flush()
            if store.hasUnpersistedChanges {
                throw EditSessionSaveError.failed(store.persistenceError ?? "The profile could not be saved.")
            }
        }
        pending[itemID] = nil
        guard !storeContains(itemID, profileID: retry.profileID, store: store) else { return false }
        registerUndo(retry.before, replacing: retry.after, edits: edits, undoManager: undoManager)
        return true
    }

    private static func storeContains(_ itemID: UUID, profileID: UUID, store: ProfileStore) -> Bool {
        store.state.profiles.first { $0.id == profileID }?.items.contains { $0.id == itemID } ?? false
    }

    private static func registerUndo(_ before: DockProfile, replacing after: DockProfile,
                                     edits: ProfileEditSessionCoordinator, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: edits) { coordinator in
            MainActor.assumeIsolated {
                guard let current = try? coordinator.restore(before, replacing: after) else { return }
                let restored = coordinator.drafts[before.id]?.profile ?? before
                registerUndo(current, replacing: restored, edits: coordinator, undoManager: undoManager)
                coordinator.autosave(before.id)
            }
        }
        undoManager.setActionName("Remove Widget")
    }
}

/// The large live preview: the real `WidgetCompactView` at each of the family's layouts, scaled up
/// on a strip drawn like this profile's Dock (material, tint, edge, corner radius, theme, module
/// radius and widget surface) over a soft sample wallpaper. Paging writes the saved layout.
/// Shared by the settings sheet and the in-Dock popout's Customize panel.
struct WidgetLayoutPreviewPager: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @ObservedObject private var systemAppearance = DockSystemAppearance.shared
    @DockAccessibilityStyle() private var accessibility
    @State private var panelWidth: CGFloat

    init(store: ProfileStore, item: DockItem, profileID: UUID,
         width: CGFloat = WidgetSheetMetrics.width - 2 * WidgetSheetMetrics.inset) {
        self.store = store; self.item = item; self.profileID = profileID
        _panelWidth = State(initialValue: width)
    }

    private var kind: String { item.widgetKind ?? item.title }
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var settings: AppSettings { store.effectiveSettings(profileID: profileID) }
    private var options: [WidgetLayoutOption] { WidgetPresentationCatalog.options(for: kind) }
    private var layout: WidgetLayout {
        WidgetPresentationCatalog.resolvedLayout(for: kind, configuration: configuration, compactDefault: settings.customDockWidgetStyle == .compact)
    }
    private var dockScale: CGFloat { settings.customDockSize.isFinite && settings.customDockSize > 0 ? CGFloat(settings.customDockSize) : 1 }
    /// Dock padding at size 1; the strip and module radius scale with the preview.
    private var dockPadding: CGFloat { DockSurfaceMetrics.padding(settings: settings, scale: 1) }
    private var scale: CGFloat {
        WidgetSheetMetrics.previewScale(widestWidth: options.map(\.width).max() ?? 120, dockPadding: dockPadding,
                                        available: panelWidth - 2 * WidgetSheetMetrics.previewHorizontalPadding - WidgetSheetMetrics.pagerChrome)
    }
    private var profileColor: Color {
        (DockProfileColor(rawValue: store.state.profiles.first { $0.id == profileID }?.color ?? "") ?? .blue).displayColor
    }
    /// The Dock's own colour scheme, as `CustomDockView` resolves it.
    private var dockScheme: ColorScheme {
        settings.customDockTheme == .dark ? .dark : settings.customDockTheme == .light ? .light
            : settings.customDockMaterial == .dark ? .dark : systemAppearance.scheme
    }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: WidgetSheetMetrics.previewRadius, style: .continuous) }

    private var selection: Binding<WidgetLayout> {
        Binding(get: { layout }, set: { value in
            WidgetAppearanceWriter.setLayout(value, itemID: item.id, profileID: profileID, store: store)
        })
    }

    private func caption(_ page: WidgetLayout) -> String {
        options.first { $0.layout == page }?.title ?? page.title
    }

    private var pager: some View {
        SizePager(options.map(\.layout), selection: selection, accessibilityLabel: "\(item.displayName) size",
                  caption: caption) { page in
            strip(page)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            pager
            .padding(.horizontal, WidgetSheetMetrics.previewHorizontalPadding)
            .padding(.top, 26).padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .background { WidgetSheetWallpaper() }
            .clipShape(shape)
            .overlay {
                if accessibility.contrast == .increased {
                    shape.strokeBorder(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { panelWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { panelWidth = $0 }
                }
            }
            if settings.customDockPosition != .bottom {
                Text("Side Docks show the narrow version of this widget.")
                    .font(DockDesign.Grouped.footerFont).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func strip(_ page: WidgetLayout) -> some View {
        let width = CGFloat(WidgetPresentationCatalog.width(for: kind, layout: page))
        let stripRadius = CGFloat(settings.customDockCornerRadius) / dockScale * scale
        let surface = settings.with(cornerRadius: stripRadius)
        DockGlassGroup(spacing: 0) {
            WidgetCompactView(store: store, item: item, profileID: profileID, presentationSettings: settings.with(position: .bottom), layoutOverride: page)
                .environment(\.dockModuleRadius, DockSurfaceMetrics.moduleRadius(settings: settings, scale: dockScale))
                .scaleEffect(scale)
                .frame(width: width * scale, height: 54 * scale)
        }
        .padding(dockPadding * scale)
        .background(DockMaterialSurface(settings: surface, color: profileColor))
        .environment(\.colorScheme, dockScheme)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The in-Dock popout's Customize panel: the sheet's own size pager and Appearance section, so
/// a widget is customised with one vocabulary wherever it is edited.
struct WidgetCustomizePanel: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            WidgetLayoutPreviewPager(store: store, item: item, profileID: profileID, width: WidgetPopoutMetrics.contentWidth)
            WidgetAppearanceControls(store: store, item: item, profileID: profileID)
        }
    }
}

/// A calm sample wallpaper so the Dock material, glass and widget surface read as they do on a desktop.
private struct WidgetSheetWallpaper: View {
    @Environment(\.colorScheme) private var scheme
    private static let lightColors: [Color] = [Color(red: 0.62, green: 0.76, blue: 0.94), Color(red: 0.96, green: 0.80, blue: 0.70)]
    private static let darkColors: [Color] = [Color(red: 0.13, green: 0.19, blue: 0.33), Color(red: 0.30, green: 0.21, blue: 0.30)]
    var body: some View {
        let dark = scheme == .dark
        let colors: [Color] = dark ? Self.darkColors : Self.lightColors
        let glowA: Color = dark ? Color(red: 0.35, green: 0.45, blue: 0.75).opacity(0.45) : Color.white.opacity(0.45)
        let glowB: Color = dark ? Color(red: 0.70, green: 0.40, blue: 0.45).opacity(0.35) : Color(red: 1.0, green: 0.88, blue: 0.80).opacity(0.7)
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { proxy in
                let width: CGFloat = proxy.size.width
                let height: CGFloat = proxy.size.height
                Circle().fill(glowA)
                    .frame(width: width * 0.7)
                    .blur(radius: 40)
                    .offset(x: -width * 0.15, y: -height * 0.45)
                Circle().fill(glowB)
                    .frame(width: width * 0.6)
                    .blur(radius: 46)
                    .offset(x: width * 0.55, y: height * 0.25)
            }
        }
        .accessibilityHidden(true)
    }
}

private extension AppSettings {
    func with(position: DockPosition) -> AppSettings {
        var copy = self
        copy.customDockPosition = position
        return copy
    }
    func with(cornerRadius: CGFloat) -> AppSettings {
        var copy = self
        copy.customDockCornerRadius = Double(cornerRadius)
        return copy
    }
}

/// Holds one typed refresh-demand token for exactly as long as a visible consumer asks for it.
@MainActor
final class RefreshDemandHolder {
    private let kind: RefreshDemandKind
    private let scheduler: RefreshScheduler
    private var token: RefreshDemandToken?
    var isHolding: Bool { token != nil }

    init(kind: RefreshDemandKind, scheduler: RefreshScheduler = .shared) {
        self.kind = kind; self.scheduler = scheduler
    }

    func begin() { scheduler.setDemand(&token, kind: kind, active: true) }
    func end() { scheduler.setDemand(&token, kind: kind, active: false) }
}

private struct WidgetConfigurationHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
