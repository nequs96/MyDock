import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
protocol DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView
    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView
}

@MainActor
enum WidgetProviderRegistry {
    private static let providers: [String: any DockWidgetProvider] = [
        "File Shelf": FileShelfWidgetProvider(),
        "Text Snippets": SavedCollectionWidgetProvider(kind: "Text Snippets"),
        "Quick Links": SavedCollectionWidgetProvider(kind: "Quick Links"),
        "Unit Converter": UnitConverterWidgetProvider(),
        "Color Picker": ColorPickerWidgetProvider(),
        "Disk Space": DiskSpaceWidgetProvider(),
        "Calculator": CalculatorWidgetProvider(),
        "Quick Checklist": QuickChecklistWidgetProvider(),
        "Stock": StockWidgetProvider(),
        "Watchlist": WatchlistWidgetProvider(),
        "Stripe": StripeWidgetProvider(),
        "Paddle": PaddleWidgetProvider(),
        "Shopify": ShopifyWidgetProvider(),
        "AI Limits": AILimitsWidgetProvider(),
        "AI Activity": AIActivityWidgetProvider(),
        "Clock": ClockWidgetProvider(),
        "World Clock": WorldClockWidgetProvider(),
        "Stopwatch": StopwatchWidgetProvider(),
        "Countdown": CountdownWidgetProvider(),
        "Time Progress": TimeProgressWidgetProvider(),
        "Hydration": HydrationWidgetProvider(),
        "Battery": BatteryWidgetProvider(),
        "App Folder": AppFolderWidgetProvider(),
        "Shortcuts": ShortcutsWidgetProvider(),
        "Calendar": CalendarWidgetProvider(),
        "Reminders": RemindersWidgetProvider(),
        "System Activity": SystemActivityWidgetProvider(),
        "Alarm": AlarmWidgetProvider(),
        "Network Activity": NetworkActivityWidgetProvider(),
        "AirDrop": AirDropWidgetProvider(),
        "Trash": TrashWidgetProvider(),
        "Now Playing": NowPlayingWidgetProvider(),
        "Weather": WeatherWidgetProvider(),
        "Focus Timer": FocusTimerWidgetProvider(),
        "Sticky Note": StickyNoteWidgetProvider()
    ]

    static var registeredKinds: Set<String> { Set(providers.keys) }

    static func provider(for kind: String?) -> any DockWidgetProvider {
        guard let kind, let provider = providers[kind] else {
            return PlaceholderWidgetProvider(kind: kind ?? "Widget")
        }
        return provider
    }
}

struct WidgetCompactView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject private var runtimeCache: WidgetRuntimeCache
    var item: DockItem
    var profileID: UUID
    var sampleMode = false
    var presentationSettings: AppSettings? = nil
    var layoutOverride: WidgetLayout? = nil
    init(store: ProfileStore, item: DockItem, profileID: UUID, sampleMode: Bool = false,
         presentationSettings: AppSettings? = nil, layoutOverride: WidgetLayout? = nil) {
        self.store = store; self.item = item; self.profileID = profileID
        self.sampleMode = sampleMode; self.presentationSettings = presentationSettings; self.layoutOverride = layoutOverride
        _runtimeCache = ObservedObject(wrappedValue: store.runtimeCache)
    }
    private var currentItem: DockItem { sampleMode ? item : store.presentationItem(item) }
    private var settings: AppSettings { presentationSettings ?? store.effectiveSettings(profileID: profileID) }
    private var kind: String { item.widgetKind ?? item.title }
    private var configuration: WidgetConfiguration { currentItem.widgetConfiguration ?? WidgetConfiguration() }
    private var layout: WidgetLayout { layoutOverride ?? WidgetPresentationCatalog.resolvedLayout(for: kind, configuration: configuration, compactDefault: settings.customDockWidgetStyle == .compact) }
    private var width: CGFloat { settings.customDockPosition == .bottom ? CGFloat(WidgetPresentationCatalog.width(for: kind, layout: layout)) : 54 }
    var body: some View {
        Group {
            if sampleMode {
                WidgetCardPreview(kind: kind, width: width, layout: layout, appearance: configuration.iconAppearance)
            } else {
                WidgetContainer(width: width, kind: kind) { content }
                    .environment(\.dockWidgetContentWidth, width)
                    .environment(\.widgetLayout, settings.customDockPosition == .bottom ? layout : WidgetPresentationCatalog.options(for: kind).first?.layout == .icon ? .icon : .compact)
                    .environment(\.widgetIconAppearance, configuration.iconAppearance)
            }
        }.overlay(alignment: .topTrailing) {
            if !sampleMode { WidgetFreshnessIndicator(coordinator: store.widgetData, item: currentItem) }
        }
    }
    @ViewBuilder private var content: some View {
        switch kind {
        case "Clock", "Focus Timer", "Stopwatch", "Countdown", "Sticky Note", "Time Progress", "Hydration", "Quick Checklist", "Stock", "Watchlist", "Calculator", "Shortcuts", "App Folder":
            LocalWidgetDockFace(item: currentItem)
        default:
            WidgetProviderRegistry.provider(for: kind).compactView(store: store, item: currentItem, profileID: profileID)
        }
    }
}

struct WidgetPopout: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject private var runtimeCache: WidgetRuntimeCache
    var item: DockItem
    var profileID: UUID
    var showsCustomize = true
    var showsHeader = true
    @Environment(\.dismiss) private var dismiss
    @State private var showsAppearance = false
    init(store: ProfileStore, item: DockItem, profileID: UUID, showsCustomize: Bool = true, showsHeader: Bool = true) {
        self.store = store; self.item = item; self.profileID = profileID
        self.showsCustomize = showsCustomize; self.showsHeader = showsHeader
        _runtimeCache = ObservedObject(wrappedValue: store.runtimeCache)
    }
    private var currentItem: DockItem {
        store.presentationItem(store.state.profiles.first { $0.id == profileID }?.items.first { $0.id == item.id } ?? item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHeader {
                HStack(spacing: 11) {
                    WidgetEmblem(kind: item.widgetKind ?? item.title)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.displayName).font(.system(size: 17, weight: .semibold))
                        Text((WidgetRegistry.all.first { $0.name == item.widgetKind }?.category.rawValue ?? "Dock") + " widget").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if showsCustomize {
                        Button { showsAppearance.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                            .buttonStyle(DockButtonStyle(icon: true))
                            .help("Customize this widget").accessibilityLabel("Customize this widget")
                            .accessibilityValue(showsAppearance ? "Expanded" : "Collapsed")
                    }
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(DockButtonStyle(icon: true)).accessibilityLabel("Close widget")
                }
                Divider()
            }
            if showsAppearance {
                WidgetAppearanceControls(store: store, item: currentItem, profileID: profileID)
                Divider()
            }
            if store.hasUnpersistedChanges || store.persistenceError != nil {
                HStack(alignment: .top, spacing: 10) {
                    Label(store.persistenceError ?? "Changes are waiting to be saved.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Retry Save") { store.commit() }
                        .controlSize(.small).disabled(!store.canRetryPersistence || !store.hasUnpersistedChanges)
                }.padding(10).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            }
            WidgetProviderRegistry.provider(for: currentItem.widgetKind)
                .popoutView(store: store, item: currentItem, profileID: profileID)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.widgetKind != "AI Activity" {
                WidgetFreshnessView(coordinator: store.widgetData, item: currentItem) {
                    Task { await store.widgetData.refresh(item: currentItem, profileID: profileID) }
                }
            }
        }
        .font(DockDesign.body).tint(DockDesign.accent)
        .buttonStyle(DockButtonStyle()).textFieldStyle(DockTextFieldStyle())
        .toggleStyle(SettingsSwitchStyle())
        .frame(width: 420, alignment: .leading)
        .onExitCommand { dismiss() }
    }
}

private struct ClockWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 4) {
                Text(LocalClockFormatter.time(for: context.date))
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(width: 54, height: 54)
        })
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalClockFormatter.time(for: context.date))
                    .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
                Text(LocalClockFormatter.date(for: context.date)).foregroundStyle(.secondary)
            }
        })
    }
}

private struct FocusTimerWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(FocusTimerCompactView(store: store, item: item, profileID: profileID))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(FocusTimerPopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct WorldClockWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(WorldClockCompactView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(WorldClockPopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct StopwatchWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(StopwatchCompactView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(StopwatchPopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct CountdownWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(CountdownCompactView(store: store, item: item, profileID: profileID))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(CountdownPopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct TimeProgressWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(TimeProgressCompactView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(TimeProgressPopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct HydrationWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(HydrationCompactView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(HydrationPopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct BatteryWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(BatteryCompactView())
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(BatteryPopoutView())
    }
}

private struct AppFolderWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AppFolderCompactView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AppFolderPopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct ShortcutsWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(ShortcutsCompactView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(ShortcutsPopoutView(store: store, item: item, profileID: profileID,
                                    runner: ShortcutExecutionService.shared))
    }
}

private struct ShortcutsCompactView: View {
    var item: DockItem
    private var selectedName: String { item.widgetConfiguration?.selectedShortcutName ?? "" }

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "command.square.fill").font(.system(size: 24)).foregroundStyle(.tint)
            Text(selectedName.isEmpty ? "Shortcuts" : selectedName)
                .font(.system(size: 8, weight: .medium)).lineLimit(1).frame(maxWidth: 52)
        }
        .frame(width: 54, height: 54)
        .help(selectedName.isEmpty ? "Choose a shortcut" : selectedName)
    }
}

private struct ShortcutsPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @ObservedObject var runner: ShortcutExecutionService

    @State private var shortcutNames: [String] = []
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    private var selectedName: String { item.widgetConfiguration?.selectedShortcutName ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Shortcut", selection: Binding(get: { selectedName }, set: { name in
                store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.selectedShortcutName = name }
            })) {
                Text("Choose a shortcut").tag("")
                if !selectedName.isEmpty && !shortcutNames.contains(selectedName) {
                    Text("\(selectedName) (not found)").tag(selectedName)
                }
                ForEach(shortcutNames, id: \.self) { name in Text(name).tag(name) }
            }

            HStack {
                if runner.isRunning(selectedName) {
                    Button("Cancel Run") { runner.cancel(selectedName) }
                        .buttonStyle(DockButtonStyle(primary: true))
                        .disabled(runner.statusByShortcut[selectedName] == ShortcutRunMessages.cancelling())
                } else {
                    Button("Run Shortcut", action: runShortcut)
                        .buttonStyle(DockButtonStyle(primary: true)).disabled(selectedName.isEmpty)
                }
                Button("Refresh", action: refreshCatalog).disabled(isRefreshing)
                Button("Open Shortcuts") { runner.openShortcutsApp() }
            }

            if isRefreshing { ProgressView("Loading shortcuts…") }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            if !selectedName.isEmpty, let status = runner.statusByShortcut[selectedName] {
                Label(status, systemImage: status == ShortcutRunMessages.completed() ? "checkmark.circle" : "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Shortcuts that ask for input may open a prompt and wait for you to respond.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 380).frame(minHeight: 190, alignment: .topLeading)
        .task { await loadCatalog() }
    }

    private func refreshCatalog() {
        Task { await loadCatalog() }
    }

    private func loadCatalog() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            shortcutNames = try await ShortcutsCatalog.list()
            errorMessage = shortcutNames.isEmpty ? "No shortcuts were found. Create one in Shortcuts, then refresh." : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runShortcut() {
        do {
            try runner.run(selectedName)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AppFolderCompactView: View {
    var item: DockItem
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(appFolderTint(configuration.appFolderColor).opacity(0.3))
            if !configuration.appFolderLetter.isEmpty {
                Text(configuration.appFolderLetter)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(appFolderTint(configuration.appFolderColor))
                    .lineLimit(1).minimumScaleFactor(0.6)
            } else if configuration.appFolderApplications.isEmpty {
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 24)).foregroundStyle(appFolderTint(configuration.appFolderColor))
            } else {
                LazyVGrid(columns: [GridItem(.fixed(17)), GridItem(.fixed(17))], spacing: 2) {
                    ForEach(configuration.appFolderApplications.prefix(4)) { application in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                            .resizable().scaledToFit().frame(width: 17, height: 17)
                    }
                }
                .padding(4)
            }
        }
        .frame(width: 46, height: 46)
        .overlay(alignment: .bottomTrailing) {
            if configuration.appFolderApplications.contains(where: { !$0.hasExistingBundlePath }) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9)).foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
        }
        .help(configuration.appFolderName)
    }
}

private struct AppFolderPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var reordering = false
    @State private var message: String?

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var applications: [AppFolderApplication] { configuration.appFolderApplications }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Folder name", text: Binding(get: { configuration.appFolderName }, set: { name in
                store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.appFolderName = name }
            }))
            .font(.headline).textFieldStyle(DockTextFieldStyle())
            TextField("Icon letters (optional)", text: Binding(get: { configuration.appFolderLetter }, set: { value in
                let letters = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased()
                store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.appFolderLetter = letters }
            }))
            .textFieldStyle(DockTextFieldStyle())
            HStack(spacing: 7) {
                ForEach(DockProfileColor.allCases) { color in
                    Button { store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.appFolderColor = color.rawValue } } label: {
                        Circle().fill(appFolderTint(color.rawValue)).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(configuration.appFolderColor == color.rawValue ? Color.primary : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain).help(color.title)
                }
                Spacer()
                Button(reordering ? "Done" : "Reorder") { reordering.toggle() }
                Button("Add Apps…", action: pickApplications).buttonStyle(DockButtonStyle(primary: true))
            }

            if applications.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2").font(.title).foregroundStyle(.secondary)
                    Text("Add applications to this folder.").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DockScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(applications.enumerated()), id: \.element.id) { index, application in
                            HStack(spacing: 8) {
                                Button { NSWorkspace.shared.open(application.url) } label: {
                                    HStack(spacing: 8) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                                            .resizable().scaledToFit().frame(width: 26, height: 26)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(application.name).lineLimit(1)
                                            Text(InstalledApplicationIdentity.normalizedURL(application.url).deletingLastPathComponent().path)
                                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                        }
                                        if !application.hasExistingBundlePath {
                                            Label("Missing", systemImage: "exclamationmark.triangle.fill")
                                                .font(.caption2).foregroundStyle(.orange)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain).disabled(!application.hasExistingBundlePath)
                                .help(InstalledApplicationIdentity.normalizedURL(application.url).path)
                                .accessibilityLabel("Open \(application.name), selected copy at \(InstalledApplicationIdentity.normalizedURL(application.url).path)")
                                if !application.hasExistingBundlePath {
                                    Button("Replace…") { replaceApplication(application) }
                                        .font(.caption).help("Choose the application's new location")
                                }
                                if reordering {
                                    Button { moveApplication(at: index, by: -1) } label: { Image(systemName: "arrow.up") }
                                        .disabled(index == 0).buttonStyle(.plain)
                                        .help("Move \(application.name) up").accessibilityLabel("Move \(application.name) up")
                                    Button { moveApplication(at: index, by: 1) } label: { Image(systemName: "arrow.down") }
                                        .disabled(index == applications.count - 1).buttonStyle(.plain)
                                        .help("Move \(application.name) down").accessibilityLabel("Move \(application.name) down")
                                }
                                Button(role: .destructive) { removeApplication(application) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.plain).help("Remove from App Folder").accessibilityLabel("Remove \(application.name) from App Folder")
                            }
                            .padding(7).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(width: 390, height: 340)
    }

    private func pickApplications() {
        let panel = NSOpenPanel()
        panel.title = "Add Apps to \(configuration.appFolderName)"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        var knownIDs = Set(applications.map(\.id))
        let selected = panel.urls.map(AppFolderApplication.init(url:)).filter { knownIDs.insert($0.id).inserted }
        guard !selected.isEmpty else { message = "Those apps are already in this folder."; return }
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.appFolderApplications.append(contentsOf: selected) }
        message = nil
    }

    private func removeApplication(_ application: AppFolderApplication) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) {
            $0.appFolderApplications.removeAll { $0.id == application.id }
        }
    }

    private func replaceApplication(_ application: AppFolderApplication) {
        let panel = NSOpenPanel()
        panel.title = "Replace \(application.name)"
        panel.prompt = "Replace"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let replacement = AppFolderApplication(url: url)
        guard !applications.contains(where: { $0.id == replacement.id && $0.id != application.id }) else {
            message = "That application is already in this folder."
            return
        }
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { configuration in
            guard let index = configuration.appFolderApplications.firstIndex(where: { $0.id == application.id }) else { return }
            configuration.appFolderApplications[index] = replacement
        }
        message = nil
    }

    private func moveApplication(at index: Int, by offset: Int) {
        let target = index + offset
        guard applications.indices.contains(index), applications.indices.contains(target) else { return }
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) {
            $0.appFolderApplications.swapAt(index, target)
        }
    }
}

private func appFolderTint(_ name: String) -> Color {
    switch DockProfileColor(rawValue: name) ?? .blue {
    case .blue: .blue
    case .purple: .purple
    case .teal: .teal
    case .green: .green
    case .orange: .orange
    case .pink: .pink
    case .red: .red
    }
}

private struct StickyNoteWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(Image(systemName: "note.text").font(.system(size: 28)).foregroundStyle(.primary))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(StickyNotePopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct PlaceholderWidgetProvider: DockWidgetProvider {
    var kind: String

    private var definition: WidgetDefinition? { WidgetRegistry.all.first(where: { $0.name == kind }) }

    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(Image(systemName: definition?.symbol ?? "square.grid.2x2").font(.system(size: 30)))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 8) {
            Text("\(kind) is unavailable in this version of MyDock.")
                .font(.callout)
            if let description = definition?.description {
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        })
    }
}

private struct WorldClockCompactView: View {
    @Environment(\.dockWidgetContentWidth) private var contentWidth
    var item: DockItem
    private var timeZone: TimeZone { TimeZone(identifier: item.widgetConfiguration?.worldClockTimeZoneID ?? "Europe/Warsaw") ?? .current }

    var body: some View { WorldClockDockFace(configuration: configuration) }

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
}

private struct WorldClockPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var citySearch = ""

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var timeZone: TimeZone { TimeZone(identifier: configuration.worldClockTimeZoneID) ?? .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Primary city · shown in Dock").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(WorldClockCityCatalog.all.first(where: { $0.id == configuration.worldClockTimeZoneID })?.name ?? configuration.worldClockTimeZoneID)
                    .font(.subheadline.weight(.medium))
            }
            TextField("Search cities or time zones", text: $citySearch)
                .textFieldStyle(DockTextFieldStyle())
            if citySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Search by city or time zone, then set it as primary or add it to the list.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                DockScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(WorldClockCityCatalog.matches(citySearch)) { city in
                            cityResult(city)
                        }
                    }
                }
                .frame(maxHeight: 150)
                if WorldClockCityCatalog.matches(citySearch).isEmpty {
                    Text("No matching city or time zone.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !configuration.worldClockAdditionalTimeZoneIDs.isEmpty {
                Text("Additional cities · dates relative to the primary city")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(configuration.worldClockAdditionalTimeZoneIDs, id: \.self) { id in
                timeZoneRow(id)
            }
            Divider()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedTime(context.date, timeZone: timeZone))
                        .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
                    Text(formattedDate(context.date, timeZone: timeZone))
                        .foregroundStyle(.secondary)
                    Text(WidgetTimingPresentation.dayRelation(offset: WorldClockCityCatalog.dayOffset(from: .current, to: timeZone, at: context.date), reference: "this Mac"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func cityResult(_ city: WorldClockCityOption) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(city.name).font(.caption.weight(.medium))
                Text(city.id).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if city.id == configuration.worldClockTimeZoneID {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow).help("Primary city")
            } else {
                Button("Primary") { setPrimaryCity(city.id) }
                    .buttonStyle(DockButtonStyle()).controlSize(.mini)
            }
            if city.id == configuration.worldClockTimeZoneID || configuration.worldClockAdditionalTimeZoneIDs.contains(city.id) {
                Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.secondary)
                    .help("Already in this clock")
            } else {
                Button { addCity(city.id) } label: { Image(systemName: "plus") }
                    .buttonStyle(DockButtonStyle()).controlSize(.mini).help("Add city")
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func timeZoneRow(_ id: String) -> some View {
        let zone = WorldClockCityOption(id: id, name: id).timeZone
        let cityName = WorldClockCityCatalog.all.first(where: { $0.id == id })?.name ?? id
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(cityName)
                    .font(.subheadline.weight(.medium))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 6) {
                        Text(formattedTime(context.date, timeZone: zone)).monospacedDigit()
                        Text(formattedDate(context.date, timeZone: zone)).foregroundStyle(.secondary)
                        let offset = WorldClockCityCatalog.dayOffset(from: timeZone, to: zone, at: context.date)
                        if offset != 0 {
                            Text(offset > 0 ? "+\(offset) day" : "\(offset) day")
                                .foregroundStyle(.secondary)
                                .help("Local date is \(abs(offset)) day\(abs(offset) == 1 ? "" : "s") \(offset > 0 ? "ahead of" : "behind") the primary city")
                        }
                    }
                    .font(.caption)
                }
            }
            Spacer(minLength: 8)
            Button { store.updateWidgetConfiguration(itemID: item.id, in: profileID) {
                $0.worldClockAdditionalTimeZoneIDs.removeAll { $0 == id }
            } } label: {
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Remove city")
        }
        .padding(.vertical, 2)
    }

    private func setPrimaryCity(_ id: String) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) {
            $0.worldClockTimeZoneID = id
            $0.worldClockAdditionalTimeZoneIDs.removeAll { $0 == id }
        }
    }

    private func addCity(_ id: String) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) {
            guard $0.worldClockTimeZoneID != id, !$0.worldClockAdditionalTimeZoneIDs.contains(id) else { return }
            $0.worldClockAdditionalTimeZoneIDs.append(id)
        }
    }
}

private struct StopwatchCompactView: View {
    var item: DockItem
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        Group {
            if configuration.stopwatchStartedAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(stopwatchText(configuration.stopwatchElapsed(at: context.date)))
                }
            } else {
                Text(stopwatchText(configuration.stopwatchElapsed()))
            }
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
        .lineLimit(1).minimumScaleFactor(0.7)
    }
}

private struct StopwatchPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if configuration.stopwatchStartedAt != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(stopwatchText(configuration.stopwatchElapsed(at: context.date)))
                    }
                } else {
                    Text(stopwatchText(configuration.stopwatchElapsed()))
                }
            }
            .font(.system(size: 36, weight: .medium, design: .rounded).monospacedDigit())
            HStack {
                Button(configuration.stopwatchStartedAt == nil ? "Start" : "Pause") {
                    store.updateWidgetConfiguration(itemID: item.id, in: profileID) { value in
                        if value.stopwatchStartedAt == nil { value.startStopwatch() }
                        else { value.pauseStopwatch() }
                    }
                }
                Button("Reset") { store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.resetStopwatch() } }
            }
        }
    }
}

private struct CountdownCompactView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        CountdownValueText(configuration: configuration, compact: true)
        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
        .lineLimit(1).minimumScaleFactor(0.7)
    }
}

private struct CountdownPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var notificationMessage: String?
    @State private var targetDraft = Date().addingTimeInterval(3_600)
    @State private var isSchedulingTarget = false
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CountdownValueText(configuration: configuration, compact: false)
                .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .center)
            Picker("Count down to", selection: modeBinding) {
                ForEach(CountdownMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            if configuration.countdownMode == .duration {
                durationControls
            } else {
                targetDateControls
            }
            Text(configuration.countdownMode == .duration
                 ? "Start requests a macOS completion alert. The timer still runs if alerts are unavailable. Pause and Reset cancel its alert."
                 : "Set or Update Target requests a macOS alert at the chosen time. Clear Target cancels it.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let notificationMessage {
                Text(notificationMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 300, alignment: .leading)
        .onAppear {
            targetDraft = configuration.countdownTargetDate ?? Date().addingTimeInterval(3_600)
        }
        .onChange(of: configuration.countdownTargetDate) { target in
            if let target { targetDraft = target }
        }
    }

    private var durationControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(configuration.countdownStartedAt == nil ? "Start" : "Pause") {
                    var fireDate: Date?
                    var expectedStart: Date?
                    store.updateWidgetConfiguration(itemID: item.id, in: profileID) { value in
                        if value.countdownStartedAt == nil {
                            value.startCountdown()
                            expectedStart = value.countdownStartedAt
                            fireDate = value.countdownNotificationDeadline
                        } else {
                            value.pauseCountdown()
                        }
                    }
                    if let fireDate {
                        let operationID = UUID()
                        CountdownNotificationService.begin(itemID: item.id, operationID: operationID)
                        Task { @MainActor in
                            do {
                                try await CountdownNotificationService.schedule(itemID: item.id,
                                                                               operationID: operationID,
                                                                               fireDate: fireDate)
                                guard CountdownNotificationService.isCurrent(itemID: item.id,
                                                                             operationID: operationID) else { return }
                                let isStillRunning = store.state.profiles
                                    .first(where: { $0.id == profileID })?.items
                                    .first(where: { $0.id == item.id })?.widgetConfiguration?.countdownStartedAt == expectedStart
                                guard isStillRunning else {
                                    CountdownNotificationService.cancel(itemID: item.id)
                                    return
                                }
                                notificationMessage = "Completion alert scheduled with macOS. Delivery depends on your notification settings."
                            } catch {
                                guard CountdownNotificationService.isCurrent(itemID: item.id,
                                                                             operationID: operationID) else { return }
                                notificationMessage = error.localizedDescription
                            }
                        }
                    } else {
                        CountdownNotificationService.cancel(itemID: item.id)
                        notificationMessage = nil
                    }
                }
                .disabled(configuration.countdownStartedAt != nil && configuration.countdownRemaining() <= 0)
                Button("Reset") {
                    CountdownNotificationService.cancel(itemID: item.id)
                    notificationMessage = nil
                    store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.resetCountdown() }
                }
            }
            Stepper(value: durationBinding, in: 60...86_400, step: 60) {
                Text("Duration: \(configuration.countdownDurationSeconds / 60) min").font(.caption)
            }
            .disabled(configuration.countdownStartedAt != nil)
        }
    }

    private var targetDateControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Target", selection: $targetDraft, displayedComponents: [.date, .hourAndMinute])
            HStack {
                Button(configuration.countdownTargetDate == nil ? "Set Target" : "Update Target") {
                    setTargetDate()
                }
                .disabled(isSchedulingTarget || targetDraft <= .now)
                if configuration.countdownTargetDate != nil {
                    Button("Clear Target") {
                        CountdownNotificationService.cancel(itemID: item.id)
                        isSchedulingTarget = false
                        notificationMessage = nil
                        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.resetCountdown() }
                    }
                }
            }
            if let target = configuration.countdownTargetDate {
                Text("Target: \(target.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Setting a target schedules a local alert when allowed. After a backup restore, set it again to arm the alert.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeBinding: Binding<CountdownMode> {
        Binding(get: { configuration.countdownMode }, set: { mode in
            CountdownNotificationService.cancel(itemID: item.id)
            isSchedulingTarget = false
            notificationMessage = nil
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.setCountdownMode(mode) }
            if mode == .targetDate { targetDraft = Date().addingTimeInterval(3_600) }
        })
    }

    private func setTargetDate() {
        let target = targetDraft
        guard target > .now else {
            notificationMessage = "Choose a future date and time."
            return
        }
        CountdownNotificationService.cancel(itemID: item.id)
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.setCountdownTarget(target) }
        let operationID = UUID()
        CountdownNotificationService.begin(itemID: item.id, operationID: operationID)
        isSchedulingTarget = true
        Task { @MainActor in
            defer {
                if CountdownNotificationService.isCurrent(itemID: item.id, operationID: operationID) {
                    isSchedulingTarget = false
                }
            }
            do {
                try await CountdownNotificationService.schedule(itemID: item.id,
                                                               operationID: operationID,
                                                               fireDate: target)
                guard CountdownNotificationService.isCurrent(itemID: item.id,
                                                             operationID: operationID) else { return }
                let current = store.state.profiles
                    .first(where: { $0.id == profileID })?.items
                    .first(where: { $0.id == item.id })?.widgetConfiguration
                guard current?.countdownMode == .targetDate,
                      current?.countdownTargetDate == target else {
                    CountdownNotificationService.cancel(itemID: item.id)
                    return
                }
                notificationMessage = "Target alert scheduled with macOS. Delivery depends on your notification settings."
            } catch {
                guard CountdownNotificationService.isCurrent(itemID: item.id,
                                                             operationID: operationID) else { return }
                notificationMessage = error.localizedDescription
            }
        }
    }

    private var durationBinding: Binding<Int> {
        Binding(get: { configuration.countdownDurationSeconds }, set: { seconds in
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.countdownDurationSeconds = seconds }
        })
    }
}

private struct CountdownValueText: View {
    var configuration: WidgetConfiguration
    var compact: Bool
    @State private var targetCompleted = false

    var body: some View {
        Group {
            if configuration.countdownMode == .targetDate {
                if let target = configuration.countdownTargetDate {
                    if targetCompleted || target <= .now {
                        Text(compact ? "Done" : "Complete")
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(targetCountdownText(configuration.countdownRemaining(at: context.date), compact: compact))
                        }
                    }
                } else {
                    Text(compact ? "Set date" : "Choose a target date")
                }
            } else if configuration.countdownStartedAt != nil, configuration.countdownRemaining() > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(timerText(configuration.countdownRemaining(at: context.date)))
                }
            } else {
                Text(timerText(configuration.countdownRemaining()))
            }
        }
        .task(id: configuration.countdownTargetDate) {
            targetCompleted = false
            guard configuration.countdownMode == .targetDate,
                  let target = configuration.countdownTargetDate else { return }
            while !Task.isCancelled {
                let remaining = target.timeIntervalSinceNow
                if remaining <= 0 {
                    targetCompleted = true
                    return
                }
                let nanoseconds = UInt64(max(0.05, min(remaining, 86_400)) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }
}

private struct TimeProgressCompactView: View {
    var item: DockItem
    private var period: TimeProgressPeriod { item.widgetConfiguration?.timeProgressPeriod ?? .day }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let progress = TimeProgressCalculator.fraction(for: period, at: context.date)
            VStack(spacing: 2) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                Text(period.title).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct TimeProgressPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Period", selection: periodBinding) {
                ForEach(TimeProgressPeriod.allCases) { period in Text(period.title).tag(period) }
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let progress = TimeProgressCalculator.fraction(for: configuration.timeProgressPeriod, at: context.date)
                ProgressView(value: progress)
                Text("\(Int(progress * 100))% through this \(configuration.timeProgressPeriod.rawValue)")
                    .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
            }
        }
    }

    private var periodBinding: Binding<TimeProgressPeriod> {
        Binding(get: { configuration.timeProgressPeriod }, set: { period in
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.timeProgressPeriod = period }
        })
    }
}

private struct HydrationDayGroup: Identifiable {
    var date: Date
    var entries: [HydrationEntry]
    var id: Date { date }
}

enum HydrationHistoryPolicy {
    static let recentDayCount = 7

    static func visibleDays<Day>(_ days: [Day], showingOlder: Bool) -> [Day] {
        showingOlder ? days : Array(days.prefix(recentDayCount))
    }
}

private struct HydrationCompactView: View {
    var item: DockItem
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let entries = (item.widgetConfiguration ?? WidgetConfiguration()).hydrationEntriesToday(at: context.date)
            VStack(spacing: 1) {
                Image(systemName: "drop.fill").font(.system(size: 17)).foregroundStyle(.blue)
                Text("\(entries.count)").font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            }.accessibilityLabel("\(entries.count) drinks today")
        }
    }
}

private struct HydrationPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var reminderMessage: String?
    @State private var reminderPermissionDenied = false
    @State private var reminderOperationID = UUID()
    @State private var showingOlderDrinks = false
    @State private var currentDay = Date.now

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var todayEntries: [HydrationEntry] { configuration.hydrationEntriesToday(at: currentDay) }
    private var dayGroups: [HydrationDayGroup] {
        let grouped = Dictionary(grouping: configuration.hydrationEntries) { Calendar.current.startOfDay(for: $0.timestamp) }
        return grouped.keys.sorted(by: >).map { HydrationDayGroup(date: $0, entries: (grouped[$0] ?? []).sorted { $0.timestamp > $1.timestamp }) }
    }
    private var visibleDayGroups: [HydrationDayGroup] {
        HydrationHistoryPolicy.visibleDays(dayGroups, showingOlder: showingOlderDrinks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today: \(todayEntries.count) drinks").font(.title3.weight(.semibold))
                Text(configuration.hydrationVolumeSummary(at: currentDay)).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("I drank water") { drinkAndRestartReminder() }
                    .buttonStyle(DockButtonStyle(primary: true))
                    .help("Log a drink when history is enabled and restart the water reminder.")
                Button("Log water") { log(amount: configuration.hydrationDefaultAmountML) }
                    .disabled(!configuration.hydrationSaveHistory)
                    .help("Record the configured amount without changing the reminder timer.")
            }
            Toggle("Save drink history", isOn: binding(\.hydrationSaveHistory))
            Toggle("Track drink amounts", isOn: binding(\.hydrationTrackAmounts))
            Toggle("Water reminders", isOn: Binding(get: { configuration.hydrationRemindersEnabled }, set: { enabled in
                setReminders(enabled)
            }))
            Stepper(value: binding(\.hydrationReminderIntervalMinutes), in: 30...240, step: 15) {
                Text("Every \(configuration.hydrationReminderIntervalMinutes) minutes").font(.caption)
            }
            .disabled(!configuration.hydrationRemindersEnabled)
            if let reminderMessage {
                Text(reminderMessage).font(.caption).foregroundStyle(.secondary)
            }
            if reminderPermissionDenied {
                Button("Open Notification Settings") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
                    NSWorkspace.shared.open(url)
                }
                .font(.caption)
            }
            Stepper(value: binding(\.hydrationDefaultAmountML), in: 50...1_000, step: 50) {
                Text("Drink size: \(configuration.hydrationDefaultAmountML) mL").font(.caption)
            }
            .disabled(!configuration.hydrationTrackAmounts)
            if !configuration.hydrationSaveHistory {
                Text("Turn on history to log drinks. Existing entries are kept.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("History").font(.headline)
                Spacer()
                if configuration.hydrationLastRemovedEntry != nil {
                    Button("Undo") { update { $0.undoHydrationRemoval() } }
                        .keyboardShortcut("z", modifiers: .command)
                }
            }
            DockScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(visibleDayGroups) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                        Text(entry.amountML.map { "\($0) mL" } ?? "Amount not recorded")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        update { $0.removeHydrationEntry(id: entry.id) }
                                    } label: {
                                        Image(systemName: "trash").foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove drink")
                                }
                            }
                        } header: {
                            Text(group.date.formatted(date: .complete, time: .omitted))
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxHeight: 180)
            if dayGroups.count > HydrationHistoryPolicy.recentDayCount {
                Button(showingOlderDrinks ? "Show recent drinks" : "Show older drinks") {
                    showingOlderDrinks.toggle()
                }
                .font(.caption)
            }
        }
        .onChange(of: configuration.hydrationReminderIntervalMinutes) { minutes in
            if configuration.hydrationRemindersEnabled { setReminders(true, interval: minutes) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in currentDay = .now }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in currentDay = .now }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in currentDay = .now }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<WidgetConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration[keyPath: keyPath] }, set: { value in
            update { $0[keyPath: keyPath] = value }
        })
    }

    private func log(amount: Int?) {
        update { $0.logHydrationDrink(amountML: amount) }
    }

    private func drinkAndRestartReminder() {
        log(amount: nil)
        guard configuration.hydrationRemindersEnabled else { return }
        setReminders(true, interval: configuration.hydrationReminderIntervalMinutes)
    }

    private func setReminders(_ enabled: Bool) {
        setReminders(enabled, interval: configuration.hydrationReminderIntervalMinutes)
    }

    private func setReminders(_ enabled: Bool, interval: Int) {
        let operationID = UUID()
        reminderOperationID = operationID
        if !enabled {
            HydrationReminderService.cancel(itemID: item.id, operationID: operationID)
            update { $0.hydrationRemindersEnabled = false }
            reminderMessage = nil
            reminderPermissionDenied = false
            return
        }
        HydrationReminderService.begin(itemID: item.id, operationID: operationID)
        Task { @MainActor in
            do {
                try await HydrationReminderService.schedule(itemID: item.id,
                                                            operationID: operationID,
                                                            intervalMinutes: interval)
                guard reminderOperationID == operationID,
                      HydrationReminderService.isCurrent(itemID: item.id, operationID: operationID) else {
                    return
                }
                update { $0.hydrationRemindersEnabled = true }
                reminderMessage = "Reminder scheduled every \(min(max(interval, 30), 240)) minutes."
                reminderPermissionDenied = false
            } catch {
                guard reminderOperationID == operationID,
                      HydrationReminderService.isCurrent(itemID: item.id, operationID: operationID) else { return }
                HydrationReminderService.cancel(itemID: item.id, operationID: operationID)
                update { $0.hydrationRemindersEnabled = false }
                reminderMessage = error.localizedDescription
                reminderPermissionDenied = error is HydrationReminderError
            }
        }
    }

    private func update(_ change: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: change)
    }
}

@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var readings: [BatteryReading] = []
    private var subscribers = Set<UUID>()
    private var visiblePopouts = Set<UUID>()
    private var schedulerDemand: RefreshDemandToken?
    private var refreshTask: Task<Void, Never>?
    private let scheduler: RefreshScheduler

    init(scheduler: RefreshScheduler = .shared) { self.scheduler = scheduler }

    var isSampling: Bool { refreshTask != nil }
    var holdsPopoutDemand: Bool { schedulerDemand != nil }

    func subscribe(_ identifier: UUID, popout: Bool = false) {
        subscribers.insert(identifier)
        if popout { visiblePopouts.insert(identifier) }
        scheduler.setDemand(&schedulerDemand, kind: .popout, active: !visiblePopouts.isEmpty)
        guard refreshTask == nil else { return }
        refresh()
        refreshTask = Task { [weak self, scheduler] in
            for await _ in scheduler.ticks(every: 60) {
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func unsubscribe(_ identifier: UUID) {
        subscribers.remove(identifier)
        visiblePopouts.remove(identifier)
        scheduler.setDemand(&schedulerDemand, kind: .popout, active: !visiblePopouts.isEmpty)
        guard subscribers.isEmpty else { return }
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refresh() {
        readings = BatteryReader.read()
    }
}

private struct BatteryCompactView: View {
    @Environment(\.dockWidgetContentWidth) private var contentWidth
    @StateObject private var monitor = BatteryMonitor.shared
    @State private var subscriptionID = UUID()

    var body: some View {
        BatteryDockFace(readings: monitor.readings).frame(width: contentWidth, height: 54)
            .onAppear { monitor.subscribe(subscriptionID) }
            .onDisappear { monitor.unsubscribe(subscriptionID) }
            .accessibilityElement(children: .ignore).accessibilityLabel("Battery")
            .accessibilityValue(monitor.readings.map { "\($0.name), \($0.percentage) percent" }.joined(separator: ", "))
    }
}

private struct BatteryPopoutView: View {
    @StateObject private var monitor = BatteryMonitor.shared
    @State private var subscriptionID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if monitor.readings.isEmpty {
                Text("No battery information is available on this Mac.").foregroundStyle(.secondary)
            } else {
                ForEach(monitor.readings) { battery in
                    HStack(spacing: 10) {
                        Image(systemName: batterySymbol(battery.percentage, charging: battery.isCharging))
                            .font(.title2).frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(battery.displayName).font(.headline)
                            Text(battery.isCharging ? "Charging" : "Not charging")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(battery.percentage)%").font(.title3.monospacedDigit())
                    }
                }
            }
        }
        .frame(minWidth: 260)
        .onAppear { monitor.subscribe(subscriptionID, popout: true) }
        .onDisappear { monitor.unsubscribe(subscriptionID) }
    }
}

private func batterySymbol(_ percentage: Int, charging: Bool) -> String {
    if charging { return "battery.100percent.bolt" }
    switch percentage {
    case 76...: return "battery.100percent"
    case 51...75: return "battery.75percent"
    case 26...50: return "battery.50percent"
    case 1...25: return "battery.25percent"
    default: return "battery.0percent"
    }
}

private struct FocusTimerCompactView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        Group {
            if configuration.focusStartedAt != nil, configuration.focusRemaining() > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(timerText(configuration.focusRemaining(at: context.date)))
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            } else {
                Text(timerText(configuration.focusRemaining()))
                    .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}

private struct FocusTimerPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            timerTextView
                .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .center)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if configuration.focusRemaining(at: context.date) <= 0 {
                    Label("Session complete · Reset to start a new session.", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(configuration.focusStartedAt == nil ? "Start" : "Pause") {
                    store.updateWidgetConfiguration(itemID: item.id, in: profileID) { value in
                        if value.focusStartedAt == nil { value.startFocusTimer() }
                        else { value.pauseFocusTimer() }
                    }
                }
                .disabled(configuration.focusStartedAt != nil && configuration.focusRemaining() <= 0)
                Button("Reset") {
                    store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.resetFocusTimer() }
                }
            }
            Stepper(value: focusDurationBinding, in: 60...7_200, step: 60) {
                Text("Session: \(configuration.focusDurationSeconds / 60) min").font(.caption)
            }
            .disabled(configuration.focusStartedAt != nil)
        }
    }

    @ViewBuilder private var timerTextView: some View {
        if configuration.focusStartedAt != nil, configuration.focusRemaining() > 0 {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(timerText(configuration.focusRemaining(at: context.date)))
            }
        } else {
            Text(timerText(configuration.focusRemaining()))
        }
    }

    private var focusDurationBinding: Binding<Int> {
        Binding(get: { configuration.focusDurationSeconds }, set: { seconds in
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.focusDurationSeconds = seconds }
        })
    }
}

private struct StickyNotePopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var noteDraft = ""
    @State private var noteSaveTask: Task<Void, Never>?
    @State private var noteSaveError: String?

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $noteDraft)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .foregroundColor(noteForeground(configuration.noteBackground))
                .tint(noteAccent(configuration.noteBackground))
                .accessibilityLabel("Note text")
                .padding(6)
                .background(noteColor(configuration.noteBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .onChange(of: noteDraft) { value in
                    WidgetSetupDraftStore.shared.updateNoteDraft(value, for: item.id, in: profileID)
                    noteSaveTask?.cancel()
                    noteSaveTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        saveNote(value)
                    }
                }
            Text("\(noteDraft.utf8.count.formatted()) / 1,048,576 UTF-8 bytes · text above this limit stays in the recovery draft.")
                .font(.caption).foregroundStyle(noteDraft.utf8.count > 1_048_576 ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let noteSaveError {
                Text(noteSaveError).font(.caption).foregroundStyle(.red)
                    .accessibilityLabel("Note not saved. " + noteSaveError)
            }
            Picker("Note", selection: noteBackgroundBinding) {
                ForEach(NoteBackground.allCases) { background in Text(background.title).tag(background) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
        .onAppear { noteDraft = WidgetSetupDraftStore.shared.noteDraft(for: item.id, in: profileID) ?? configuration.noteText }
        .onDisappear {
            noteSaveTask?.cancel()
            saveNote(noteDraft)
        }
    }

    private var noteBackgroundBinding: Binding<NoteBackground> {
        Binding(get: { configuration.noteBackground }, set: { background in
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.noteBackground = background }
        })
    }

    private func saveNote(_ text: String) {
        do {
            try WidgetSetupDraftStore.shared.saveNote(text, for: item.id, in: profileID, to: store)
            noteSaveError = nil
        } catch { noteSaveError = error.localizedDescription + " Your draft is retained." }
    }
}



private func timerText(_ interval: TimeInterval) -> String {
    TimerValueFormatter.text(interval)
}

func targetCountdownText(_ interval: TimeInterval, compact: Bool) -> String {
    let safeInterval = interval.isFinite ? min(max(0, interval), TimeInterval(Int.max / 4)) : 0
    let seconds = Int(safeInterval.rounded(.up))
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    let remainingSeconds = seconds % 60
    if compact {
        if days > 0 { return "\(days)d" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return timerText(safeInterval)
    }
    if days > 0 { return "\(days)d \(String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds))" }
    if hours > 0 { return "\(hours):\(String(format: "%02d:%02d", minutes, remainingSeconds))" }
    return timerText(safeInterval)
}

func stopwatchText(_ interval: TimeInterval) -> String {
    let safeInterval = interval.isNaN ? 0 : min(max(0, interval), TimeInterval(Int.max / 4))
    let seconds = Int(safeInterval.rounded(.down))
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    let remainingSeconds = seconds % 60
    return hours > 0
        ? "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", remainingSeconds))"
        : String(format: "%02d:%02d", minutes, remainingSeconds)
}

func formattedTime(_ date: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = timeZone
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

func formattedDate(_ date: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = timeZone
    formatter.dateStyle = .full
    return formatter.string(from: date)
}



private func noteColor(_ background: NoteBackground) -> Color {
    switch background {
    case .yellow: .yellow.opacity(0.22)
    case .blue: .blue.opacity(0.18)
    case .pink: .pink.opacity(0.18)
    case .white: .white.opacity(0.6)
    case .black: .black.opacity(0.75)
    case .translucent: .primary.opacity(0.06)
    }
}

private func noteForeground(_ background: NoteBackground) -> Color {
    switch background {
    case .white: .black
    case .black: .white
    default: Color(nsColor: .textColor)
    }
}

private func noteAccent(_ background: NoteBackground) -> Color {
    switch background {
    case .white, .black: noteForeground(background)
    default: .accentColor
    }
}
